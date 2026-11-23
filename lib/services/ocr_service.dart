import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_models.dart';

/// OCR محلي بالكامل (Google ML Kit، النموذج مضمّن في التطبيق، بدون إنترنت).
/// يدعم الحروف اللاتينية والأرقام. الحروف العربية غير مدعومة في هذا المحرك.
class MlKitOcrEngine implements OcrEngine {
  @override
  Future<OcrResult> recognize(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      final words = <OcrWord>[];
      final angles = <double>[];
      for (final block in text.blocks) {
        for (final line in block.lines) {
          final pts = line.cornerPoints;
          final box = line.boundingBox;
          if (pts.length >= 2 && box.width > 3 * box.height) {
            final dx = (pts[1].x - pts[0].x).toDouble();
            final dy = (pts[1].y - pts[0].y).toDouble();
            if (dx > 0) angles.add(math.atan2(dy, dx));
          }
          for (final el in line.elements) {
            final b = el.boundingBox;
            words.add(OcrWord(el.text, b.left, b.top, b.right, b.bottom));
          }
        }
      }
      var skew = 0.0;
      if (angles.length >= 3) {
        angles.sort();
        skew = angles[angles.length ~/ 2].clamp(-0.35, 0.35).toDouble();
      }
      return OcrResult(words, skew);
    } finally {
      await recognizer.close();
    }
  }
}
