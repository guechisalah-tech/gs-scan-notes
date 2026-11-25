import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class _PrepArgs {
  final String input;
  final String output;
  final bool enhance;
  const _PrepArgs(this.input, this.output, this.enhance);
}

String _prepareIsolate(_PrepArgs a) {
  final bytes = File(a.input).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('تعذر قراءة الصورة');
  image = img.bakeOrientation(image);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > 3000) {
    final f = 3000 / longest;
    image = img.copyResize(image,
        width: (image.width * f).round(),
        height: (image.height * f).round(),
        interpolation: img.Interpolation.average);
  } else if (longest < 1400) {
    final f = 1800 / longest;
    image = img.copyResize(image,
        width: (image.width * f).round(),
        height: (image.height * f).round(),
        interpolation: img.Interpolation.cubic);
  }
  if (a.enhance) {
    image = img.grayscale(image);
    image = img.normalize(image, min: 0, max: 255);
    image = img.adjustColor(image, contrast: 1.2);
  }
  File(a.output).writeAsBytesSync(img.encodeJpg(image, quality: 92));
  return a.output;
}

class ImageService {
  /// ينشئ نسخة مؤقتة محسّنة للتعرف الضوئي (النسخة الأصلية لا تُمسّ).
  static Future<String> prepare(String path, {required bool enhance}) async {
    final dir = await Directory.systemTemp.createTemp('gsscan_');
    final out = '${dir.path}/prepared.jpg';
    return compute(_prepareIsolate, _PrepArgs(path, out, enhance));
  }

  /// يحذف الملف فقط إن كان داخل مجلد التخزين المؤقت للتطبيق (لا يمس صور المعرض).
  static void deleteIfTemp(String? path) {
    if (path == null) return;
    try {
      if (path.startsWith(Directory.systemTemp.path)) {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
        final parent = f.parent;
        if (parent.path != Directory.systemTemp.path &&
            parent.path.contains('gsscan_') &&
            parent.listSync().isEmpty) {
          parent.deleteSync();
        }
      }
    } catch (_) {}
  }
}
