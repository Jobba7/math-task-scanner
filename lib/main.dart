import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:ui' as ui;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (!mounted) return;
    if (image != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TextRecognitionScreen(File(image.path)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bild aufnehmen')),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.camera_alt),
          label: const Text('Foto machen'),
          onPressed: _pickImage,
        ),
      ),
    );
  }
}

class TextRecognitionScreen extends StatefulWidget {
  final File imageFile;
  const TextRecognitionScreen(this.imageFile, {super.key});

  @override
  State<TextRecognitionScreen> createState() => _TextRecognitionScreenState();
}

class _TextRecognitionScreenState extends State<TextRecognitionScreen> {
  late final TextRecognizer _textRecognizer;
  List<TextElement> _elements = [];
  final Set<int> _selected = {};
  ui.Image? _loadedImage;

  @override
  void initState() {
    super.initState();
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _loadImage();
    _processImage();
  }

  Future<void> _loadImage() async {
    final bytes = await widget.imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    setState(() {
      _loadedImage = frame.image;
    });
  }

  Future<void> _processImage() async {
    final inputImage = InputImage.fromFile(widget.imageFile);
    final recognizedText = await _textRecognizer.processImage(inputImage);
    if (!mounted) return;

    final elements = recognizedText.blocks
        .expand((block) => block.lines)
        .expand((line) => line.elements)
        .toList();

    // Konsole-Log für Debugging
    for (final elem in elements) {
      log('Erkannt: "${elem.text}" → ${elem.boundingBox}');
    }

    setState(() {
      _elements = elements;
    });
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else {
        _selected.add(index);
      }
    });
  }

  void _confirmSelection() {
    final selectedTexts = _selected.map((i) => _elements[i].text).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SummaryScreen(selectedTexts),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadedImage == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Text auswählen')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final imageWidth = _loadedImage!.width.toDouble();
          final imageHeight = _loadedImage!.height.toDouble();

          final containerWidth = constraints.maxWidth;
          final containerHeight = constraints.maxHeight;

          final imageAspect = imageWidth / imageHeight;
          final containerAspect = containerWidth / containerHeight;

          double displayWidth, displayHeight, dx = 0, dy = 0;

          if (containerAspect > imageAspect) {
            displayHeight = containerHeight;
            displayWidth = imageAspect * displayHeight;
            dx = (containerWidth - displayWidth) / 2;
          } else {
            displayWidth = containerWidth;
            displayHeight = displayWidth / imageAspect;
            dy = (containerHeight - displayHeight) / 2;
          }

          final scaleX = displayWidth / imageWidth;
          final scaleY = displayHeight / imageHeight;

          return Stack(
            children: [
              Positioned.fill(
                child: Image.file(widget.imageFile, fit: BoxFit.contain),
              ),
              ..._elements.asMap().entries.map((entry) {
                final idx = entry.key;
                final elem = entry.value;
                final rect = elem.boundingBox;

                return Positioned(
                  left: rect.left * scaleX + dx,
                  top: rect.top * scaleY + dy,
                  width: rect.width * scaleX,
                  height: rect.height * scaleY,
                  child: GestureDetector(
                    onTap: () => _toggleSelection(idx),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        border: Border.all(
                          color: _selected.contains(idx)
                              ? Colors.green
                              : Colors.red,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton(
          onPressed: _selected.isNotEmpty ? _confirmSelection : null,
          child: Text('Bestätigen (${_selected.length})'),
        ),
      ),
    );
  }
}

class SummaryScreen extends StatelessWidget {
  final List<String> selectedTexts;
  const SummaryScreen(this.selectedTexts, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Übersicht')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView.builder(
          itemCount: selectedTexts.length,
          itemBuilder: (context, index) => Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(selectedTexts[index], style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
      ),
    );
  }
}
