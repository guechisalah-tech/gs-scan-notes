import 'dart:math' as math;

import '../models.dart';
import 'ocr_models.dart';
import 'text_utils.dart';

class ParsedTable {
  final List<ExtractedRow> rows;
  final List<String> skipped; // أسطر لم تُعتبر صفوف تلاميذ (بدون نقطة)
  const ParsedTable(this.rows, this.skipped);
}

class _Item {
  final String text;
  final double x, y, h;
  _Item(this.text, this.x, this.y, this.h);
}

/// يحوّل كلمات OCR إلى صفوف (لقب، اسم، رقم، نقطة).
class TableParser {
  TableParser({this.maxGrade = 20, this.gradeOnRight = true});

  final double maxGrade;

  /// true: عمود النقطة في أقصى يمين الصورة (جداول لاتينية LTR). false: أقصى اليسار.
  final bool gradeOnRight;

  static final _absentRe = RegExp(r'^(abs|absent|absente|غ|غائب)\.?$', caseSensitive: false);
  static const _headerWords = {
    'nom', 'prenom', 'note', 'notes', 'matricule', 'moyenne', 'classe',
    'lycee', 'college', 'eleve', 'eleves', 'groupe', 'date', 'naissance',
    'annee', 'scolaire', 'trimestre', 'semestre', 'devoir', 'examen',
    'observation', 'remarque', 'liste', 'releve', 'composition', 'controle',
    'n', 'no', 'num', 'numero',
  };

  /// يرجع الرقم بصيغة نصية موحدة (نقطة عشرية) أو null إن لم يكن الرمز رقمًا.
  String? _asNumber(String raw) {
    var t = normalizeDigits(raw.trim());
    t = t.replaceFirst(RegExp(r'/\s*\d+$'), ''); // 12/20
    if (!RegExp(r'\d').hasMatch(t)) return null;
    // أخطاء OCR الشائعة داخل الأرقام
    t = t
        .replaceAll(RegExp(r'[Oo]'), '0')
        .replaceAll(RegExp(r'[Il|]'), '1')
        .replaceAll(RegExp(r'[Ss]'), '5');
    if (!RegExp(r'^\d+([.,]\d+)?$').hasMatch(t)) return null;
    return t.replaceAll(',', '.');
  }

  bool _hasLetter(String t) =>
      RegExp(r'[A-Za-zÀ-ɏء-ي]').hasMatch(t);

  ParsedTable parse(OcrResult ocr) {
    final words = ocr.words.where((w) => w.text.trim().isNotEmpty).toList();
    if (words.isEmpty) return const ParsedTable([], []);

    final c = math.cos(ocr.skew), s = math.sin(ocr.skew);
    final items = words.map((w) {
      final cx = (w.left + w.right) / 2, cy = (w.top + w.bottom) / 2;
      return _Item(w.text.trim(), cx * c + cy * s, -cx * s + cy * c,
          (w.bottom - w.top).abs());
    }).toList();

    final hs = items.map((e) => e.h).toList()..sort();
    final tol = math.max(4.0, hs[hs.length ~/ 2] * 0.6);

    items.sort((a, b) => a.y.compareTo(b.y));
    final lines = <List<_Item>>[];
    var meanY = 0.0;
    for (final it in items) {
      if (lines.isNotEmpty && (it.y - meanY).abs() <= tol) {
        lines.last.add(it);
        meanY = lines.last.fold<double>(0, (a, e) => a + e.y) / lines.last.length;
      } else {
        lines.add([it]);
        meanY = it.y;
      }
    }

    final rows = <ExtractedRow>[];
    final skipped = <String>[];
    for (final line in lines) {
      line.sort((a, b) => a.x.compareTo(b.x));
      final tokens = line.map((e) => e.text).toList();
      final r = _parseLine(tokens, skipped);
      if (r != null) rows.add(r);
    }
    return ParsedTable(rows, skipped);
  }

  ExtractedRow? _parseLine(List<String> tokens, List<String> skipped) {
    var absent = false;
    String? idTok;
    final numIdx = <int>[];
    final numVal = <int, String>{};
    final nameIdx = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (_absentRe.hasMatch(t)) {
        absent = true;
        continue;
      }
      final n = _asNumber(t);
      if (n != null) {
        if (RegExp(r'^\d{5,}$').hasMatch(n)) {
          idTok ??= n;
        } else {
          numIdx.add(i);
          numVal[i] = n;
        }
        continue;
      }
      if (_hasLetter(t)) nameIdx.add(i);
    }

    final nameParts = nameIdx.map((i) => tokens[i]).toList();
    final norm = nameParts.expand((p) => nameTokens(p)).toList();
    if (norm.isNotEmpty) {
      final hdr = norm.where(_headerWords.contains).length;
      if (hdr > 0 && hdr * 2 >= norm.length) return null; // سطر عناوين
    }

    // اختيار النقطة حسب جهة العمود، وتجاهل رقم الترتيب في الجهة المقابلة
    String? gradeText;
    if (numIdx.isNotEmpty) {
      final pick = gradeOnRight ? numIdx.last : numIdx.first;
      var isRowNumber = false;
      if (nameIdx.isNotEmpty) {
        if (gradeOnRight && pick < nameIdx.first) isRowNumber = true;
        if (!gradeOnRight && pick > nameIdx.last) isRowNumber = true;
      }
      if (!isRowNumber) gradeText = numVal[pick];
    }

    final hasIdentity = nameParts.isNotEmpty || idTok != null;
    if ((gradeText != null || absent) && hasIdentity) {
      final split = _splitName(nameParts);
      return ExtractedRow(
        lastName: split[0],
        firstName: split[1],
        idText: idTok ?? '',
        gradeText: gradeText ?? '',
        absent: absent && gradeText == null,
      );
    }
    if (nameParts.length >= 2 || idTok != null) {
      skipped.add(tokens.join(' '));
    }
    return null;
  }

  /// "BENALI Amine" -> [BENALI, Amine]. الكلمات الكبيرة في البداية = اللقب.
  List<String> _splitName(List<String> parts) {
    if (parts.isEmpty) return ['', ''];
    if (parts.length == 1) return [parts.first, ''];
    var k = 0;
    while (k < parts.length &&
        parts[k] == parts[k].toUpperCase() &&
        parts[k] != parts[k].toLowerCase()) {
      k++;
    }
    if (k == 0 || k == parts.length) k = 1;
    return [parts.sublist(0, k).join(' '), parts.sublist(k).join(' ')];
  }
}
