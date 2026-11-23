import 'dart:math' as math;

const Map<String, String> _map = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y',
  'œ': 'oe', 'æ': 'ae',
  'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا',
  'ى': 'ي', 'ة': 'ه', 'ؤ': 'و', 'ئ': 'ي',
};

const Map<String, String> _digitFix = {'0': 'o', '1': 'i', '5': 's'};

/// يحوّل الأرقام العربية/الفارسية إلى أرقام لاتينية.
String normalizeDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// يحلل نقطة مكتوبة بفاصلة أو نقطة (12,5 أو 12.5). يعيد null إن لم تكن رقمًا.
double? parseGrade(String raw) {
  final s = normalizeDigits(raw)
      .trim()
      .replaceAll(',', '.')
      .replaceAll('٫', '.')
      .replaceAll(' ', '');
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{1,3}(?:\.\d{1,3})?)$').firstMatch(s);
  if (m == null) return null;
  return double.tryParse(m.group(1)!);
}

/// تطبيع الأسماء للمقارنة: أحرف صغيرة، إزالة التشكيل والحركات، توحيد الألف والياء...
String normalizeName(String input) {
  final b = StringBuffer();
  for (final ch in input.toLowerCase().split('')) {
    final mapped = _map[ch] ?? ch;
    for (final c in mapped.split('')) {
      final u = c.codeUnitAt(0);
      if ((u >= 0x064B && u <= 0x065F) || u == 0x0670 || u == 0x0640) {
        continue; // تشكيل / تطويل
      }
      if (u == 0x27 || u == 0x2019) continue; // apostrophe
      final isLatin = u >= 0x61 && u <= 0x7a;
      final isArabic = u >= 0x0621 && u <= 0x064A;
      final isDigit = u >= 0x30 && u <= 0x39;
      if (isLatin || isArabic) {
        b.write(c);
      } else if (isDigit) {
        b.write(_digitFix[c] ?? '');
      } else {
        b.write(' ');
      }
    }
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<String> nameTokens(String s) =>
    normalizeName(s).split(' ').where((t) => t.isNotEmpty).toList();

/// رقم التلميذ: أرقام فقط بدون أصفار بادئة.
String normalizeId(String s) {
  final d = normalizeDigits(s).replaceAll(RegExp(r'[^0-9]'), '');
  return d.replaceFirst(RegExp(r'^0+'), '');
}

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    prev = cur;
  }
  return prev[b.length];
}

double similarity(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1.0;
  final m = math.max(a.length, b.length);
  return 1.0 - levenshtein(a, b) / m;
}

int colIndexFromRef(String ref) {
  var n = 0;
  for (final u in ref.codeUnits) {
    if (u >= 65 && u <= 90) {
      n = n * 26 + (u - 64);
    } else if (u >= 97 && u <= 122) {
      n = n * 26 + (u - 96);
    } else {
      break;
    }
  }
  return n - 1;
}

int rowFromRef(String ref) =>
    int.tryParse(ref.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

String colLetters(int index) {
  var n = index + 1;
  final codes = <int>[];
  while (n > 0) {
    final r = (n - 1) % 26;
    codes.insert(0, 65 + r);
    n = (n - 1) ~/ 26;
  }
  return String.fromCharCodes(codes);
}
