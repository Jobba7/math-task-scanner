import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import 'dart:developer' as developer;

void main() => runApp(const OcrSelectionApp());

class OcrSelectionApp extends StatelessWidget {
  const OcrSelectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OCR Auswahl Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const CameraScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  Future<void> _pickImage(BuildContext context) async {
    final imagePicker = ImagePicker();
    final imageFile = await imagePicker.pickImage(source: ImageSource.camera);
    if (imageFile == null) return;
    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TextRecognitionScreen(imageFile: File(imageFile.path)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bild aufnehmen')),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.camera_alt),
          label: const Text('Foto machen'),
          onPressed: () => _pickImage(context),
        ),
      ),
    );
  }
}

class TextRecognitionProvider extends ChangeNotifier {
  final File imageFile;
  final TextRecognizer _textRecognizer;
  List<TextLine> textElements = [];
  final Set<int> selectedIndices = {};
  ui.Image? loadedImage;

  TextRecognitionProvider({required this.imageFile})
      : _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin) {
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadImage();
    await _processImage();
  }

  Future<void> _loadImage() async {
    final bytes = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    loadedImage = frame.image;
    notifyListeners();
  }

  Future<void> _processImage() async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognizedText = await _textRecognizer.processImage(inputImage);
    
    final blocks = recognizedText.blocks;
    _logDetectedBlocks(blocks.where((block) => block.lines.length > 1).toList());
    textElements = blocks
        .expand((block) => block.lines)
        .toList();

    notifyListeners();
  }

  void _logDetectedBlocks(List<TextBlock> blocks) {
    developer.log(
      '▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄',
      name: 'OCR_DEBUG',
    );

    for (final block in blocks) {
      developer.log(
        '▌ Block erkannt:',
        name: 'OCR_DEBUG',
      );
      developer.log("$block",
        name: 'OCR_DEBUG',
      );
      developer.log(
        '▌   Text: "${block.text}"',
        name: 'OCR_DEBUG',
      );
      for (final line in block.lines) {
        developer.log(
          '▌   Line: "${line.text}"',
          name: 'OCR_DEBUG',
        );
        developer.log(
          '▌   Confidence: ${line.confidence?.toStringAsFixed(2)}',
          name: 'OCR_DEBUG',
        );
        developer.log("Bounding Box: ${line.boundingBox}",
          name: 'OCR_DEBUG',
        );
      }
      
      developer.log(
        '▌   Bounding Box: ${block.boundingBox}',
        name: 'OCR_DEBUG',
      );
      developer.log(
        '▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌',
        name: 'OCR_DEBUG',
      );
    }
  }

  void toggleSelection(int index) {
    if (selectedIndices.contains(index)) {
      selectedIndices.remove(index);
    } else {
      selectedIndices.add(index);
    }
    notifyListeners();
  }

  List<String> getSelectedTexts() {
    return selectedIndices.map((index) => textElements[index].text).toList();
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }
}

class TextRecognitionScreen extends StatelessWidget {
  final File imageFile;

  const TextRecognitionScreen({super.key, required this.imageFile});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TextRecognitionProvider(imageFile: imageFile),
      child: const _TextRecognitionView(),
    );
  }
}

class _TextRecognitionView extends StatelessWidget {
  const _TextRecognitionView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Text auswählen')),
      body: const _ImageOverlayWithText(),
      bottomNavigationBar: const _ConfirmationButton(),
    );
  }
}

class _ImageOverlayWithText extends StatelessWidget {
  const _ImageOverlayWithText();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TextRecognitionProvider>();
    final image = provider.loadedImage;

    if (image == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final displayMetrics = _calculateDisplayMetrics(
          image: image,
          constraints: constraints,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: Image.file(provider.imageFile, fit: BoxFit.contain),
            ),
            ..._buildTextElementsOverlay(
              provider: provider,
              displayMetrics: displayMetrics,
            ),
          ],
        );
      },
    );
  }

  DisplayMetrics _calculateDisplayMetrics({
    required ui.Image image,
    required BoxConstraints constraints,
  }) {
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    final containerWidth = constraints.maxWidth;
    final containerHeight = constraints.maxHeight;
    final imageAspect = imageWidth / imageHeight;
    final containerAspect = containerWidth / containerHeight;

    double displayWidth, displayHeight, offsetX, offsetY;

    if (containerAspect > imageAspect) {
      displayHeight = containerHeight;
      displayWidth = imageAspect * displayHeight;
      offsetX = (containerWidth - displayWidth) / 2;
      offsetY = 0;
    } else {
      displayWidth = containerWidth;
      displayHeight = displayWidth / imageAspect;
      offsetX = 0;
      offsetY = (containerHeight - displayHeight) / 2;
    }

    return DisplayMetrics(
      scaleX: displayWidth / imageWidth,
      scaleY: displayHeight / imageHeight,
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }

  List<Widget> _buildTextElementsOverlay({
    required TextRecognitionProvider provider,
    required DisplayMetrics displayMetrics,
  }) {
    return provider.textElements.asMap().entries.map((entry) {
      final index = entry.key;
      final element = entry.value;
      final rect = element.boundingBox;

      return Positioned(
        left: rect.left * displayMetrics.scaleX + displayMetrics.offsetX,
        top: rect.top * displayMetrics.scaleY + displayMetrics.offsetY,
        width: rect.width * displayMetrics.scaleX,
        height: rect.height * displayMetrics.scaleY,
        child: GestureDetector(
          onTap: () => provider.toggleSelection(index),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: provider.selectedIndices.contains(index)
                    ? Colors.green
                    : Colors.red,
                width: 2,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}

class _ConfirmationButton extends StatelessWidget {
  const _ConfirmationButton();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TextRecognitionProvider>();
    final selectionCount = provider.selectedIndices.length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(
        onPressed: selectionCount > 0
            ? () => _navigateToSummary(context, provider)
            : null,
        child: Text('Bestätigen ($selectionCount)'),
      ),
    );
  }

  void _navigateToSummary(
    BuildContext context,
    TextRecognitionProvider provider,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SummaryScreen(selectedTexts: provider.getSelectedTexts()),
      ),
    );
  }
}

class SummaryScreen extends StatelessWidget {
  final List<String> selectedTexts;

  const SummaryScreen({super.key, required this.selectedTexts});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Übersicht')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: selectedTexts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildTextCard(selectedTexts[index]),
      ),
    );
  }

  Widget _buildTextCard(String text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

@immutable
class DisplayMetrics {
  final double scaleX;
  final double scaleY;
  final double offsetX;
  final double offsetY;

  const DisplayMetrics({
    required this.scaleX,
    required this.scaleY,
    required this.offsetX,
    required this.offsetY,
  });
}