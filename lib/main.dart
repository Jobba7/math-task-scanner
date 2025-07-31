import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;

void main() => runApp(const OcrSelectionApp());

class OcrSelectionApp extends StatelessWidget {
  const OcrSelectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mathe Aufgaben OCR',
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
      appBar: AppBar(title: const Text('Mathe Aufgabe fotografieren')),
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
  List<MathTask> mathTasks = [];
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
    
    mathTasks = recognizedText.blocks
        .expand((block) => block.lines)
        .map((line) => MathTask.fromTextLine(line))
        .where((task) => task.isValidMathExpression)
        .toList();

    notifyListeners();
  }

  void toggleSelection(int index) {
    if (selectedIndices.contains(index)) {
      selectedIndices.remove(index);
    } else {
      selectedIndices.add(index);
    }
    notifyListeners();
  }

  List<String> getSelectedMathExpressions() {
    return selectedIndices
        .map((index) => mathTasks[index].formattedExpression)
        .toList();
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }
}

class MathTask {
  final TextLine textLine;
  final String formattedExpression;
  final bool isValidMathExpression;

  MathTask({
    required this.textLine,
    required this.formattedExpression,
    required this.isValidMathExpression,
  });

  factory MathTask.fromTextLine(TextLine line) {
    final (formatted, isValid) = _parseMathExpression(line.text);
    return MathTask(
      textLine: line,
      formattedExpression: formatted,
      isValidMathExpression: isValid,
    );
  }

  static (String, bool) _parseMathExpression(String input) {
    // Entferne alle Leerzeichen
    String cleaned = input.replaceAll(RegExp(r'\s+'), '');
    
    // Entferne alles ab dem Gleichheitszeichen (inklusive)
    final equalIndex = cleaned.indexOf('=');
    if (equalIndex != -1) {
      cleaned = cleaned.substring(0, equalIndex);
    }
    
    // Prüfe auf gültiges Mathe-Aufgabenformat
    final isValid = RegExp(r'^\d+[+\-*/]\d+$').hasMatch(cleaned);
    
    return (cleaned, isValid);
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
      appBar: AppBar(title: const Text('Mathe Aufgabe auswählen')),
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
            ..._buildMathTaskOverlays(
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

  List<Widget> _buildMathTaskOverlays({
    required TextRecognitionProvider provider,
    required DisplayMetrics displayMetrics,
  }) {
    return provider.mathTasks.asMap().entries.map((entry) {
      final index = entry.key;
      final mathTask = entry.value;
      final rect = mathTask.textLine.boundingBox;

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
                    : Colors.blue,
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
        builder: (_) => SummaryScreen(
          selectedExpressions: provider.getSelectedMathExpressions(),
        ),
      ),
    );
  }
}

class SummaryScreen extends StatelessWidget {
  final List<String> selectedExpressions;

  const SummaryScreen({super.key, required this.selectedExpressions});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mathe Aufgaben')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: selectedExpressions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) => _buildMathTaskCard(
          expression: selectedExpressions[index],
          index: index + 1,
        ),
      ),
    );
  }

  Widget _buildMathTaskCard({required String expression, required int index}) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aufgabe $index:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              expression,
              style: const TextStyle(fontSize: 24, fontFamily: 'Monospace'),
            ),
          ],
        ),
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