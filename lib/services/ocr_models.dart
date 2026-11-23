class OcrWord {
  final String text;
  final double left, top, right, bottom;
  const OcrWord(this.text, this.left, this.top, this.right, this.bottom);
}

class OcrResult {
  final List<OcrWord> words;

  /// ميلان الصفحة بالراديان (موجب = النص ينزل نحو اليمين).
  final double skew;
  const OcrResult(this.words, this.skew);
}

abstract class OcrEngine {
  Future<OcrResult> recognize(String imagePath);
}
