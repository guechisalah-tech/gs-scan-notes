import 'dart:math' as math;

import '../models.dart';
import 'ocr_models.dart';
import 'text_utils.dart';

class NumTok {
  final String value;
  final double x;
  const NumTok(this.value, this.x);
}

/// سطر واحد من الكشف: رقم التلميذ + أجزاء الاسم + الأرقام المقروءة بمواضعها.
class ParsedLine {
  final String id;
  final List<String> nameParts;
  final bool absent;
  final List<NumTok> nums;
  final String raw;
  const ParsedLine(this.id, this.nameParts, this.absent, this.nums, this.raw);
}

/// عمود من الأرقام (قيم متقاربة أفقيًا في عدة أسطر).
class NumColumn {
  final double x;
  final Map<int, String> byLine;
  const NumColumn(this.x, this.byLine);
  int get count => byLine.length;
  List<String> samples([int n = 8]) {
    final keys = byLine.keys.toList()..sort();
    return keys.take(n).map((k) => byLine[k]!).toList();
  }
}

class ParsedTable {
  final List<ParsedLine> lines;
  final List<NumColumn> columns; // مرتبة من يسار الصورة إلى يمينها
  final List<String> rawLines; // كل ما قرأه المحرك (للتشخيص)
  const ParsedTable(this.lines, this.columns, this.rawLines);
}

class BuiltRows {
  final List<ExtractedRow> rows;
  final List<String> skipped;
  const BuiltRows(this.rows, this.skipped);
}

class _Item {
  final String text;
  final double x, y, h;
  _Item(this.text, this.x, this.y, this.h);
}

class _Tok {
  final int line;
  final String value;
  final double x;
  _Tok(this.line, this.value, this.x);
}

/// يحوّل كلمات OCR إلى أسطر (رقم التلميذ، الاسم، أرقام النقاط) ثم يكتشف أعمدة الأرقام.
/// الأستاذ يختار العمود الصحيح بعد ذلك، فلا يُفترض أي ترتيب للأعمدة.
class TableParser {
  TableParser({this.maxGrade = 20, this.idOnly = false});

  final double maxGrade;

  /// true: تُتجاهل الأسماء (عربية غير مقروءة) ولا يُعتبر السطر صفًّا إلا إن وُجد رقم تعريف.
  final bool idOnly;

  static final _absentRe =
      RegExp(r'^(abs|absent|absente|غ|غائب)\.?$', caseSensitive: false);
  static final _gradeRe = RegExp(r'^\d{1,3}([.,]\d{1,2})?$');
  static const _headerWords = {
    'nom', 'prenom', 'note', 'notes', 'matricule', 'moyenne', 'classe',
    'lycee', 'college', 'eleve', 'eleves', 'groupe', 'date', 'naissance',
    'annee', 'scolaire', 'trimestre', 'semestre', 'devoir', 'examen',
    'observation', 'remarque', 'liste', 'releve', 'composition', 'controle',
    'n', 'no', 'num', 'numero',
  };

  /// نقطة محتملة بصيغة نصية موحدة (نقطة عشرية)، أو null.
  String? _asGrade(String raw) {
    var t = normalizeDigits(raw.trim());
    t = t.replaceFirst(RegExp(r'/\s*\d+$'), ''); // 12/20
    if (!RegExp(r'\d').hasMatch(t) || t.length > 6) return null;
    t = t
        .replaceAll(RegExp(r'[Oo]'), '0')
        .replaceAll(RegExp(r'[Il|]'), '1')
        .replaceAll(RegExp(r'[Ss]'), '5');
    if (!_gradeRe.hasMatch(t)) return null;
    return t.replaceAll(',', '.');
  }

  bool _hasLetter(String t) =>
      RegExp(r'[A-Za-zÀ-ɏء-ي]').hasMatch(t);

  ParsedTable parse(OcrResult ocr) {
    final words = ocr.words.where((w) => w.text.trim().isNotEmpty).toList();
    if (words.isEmpty) return const ParsedTable([], [], []);

    final c = math.cos(ocr.skew), s = math.sin(ocr.skew);
    final items = words.map((w) {
      final cx = (w.left + w.right) / 2, cy = (w.top + w.bottom) / 2;
      return _Item(w.text.trim(), cx * c + cy * s, -cx * s + cy * c,
          (w.bottom - w.top).abs());
    }).toList();

    final hs = items.map((e) => e.h).toList()..sort();
    final medH = hs[hs.length ~/ 2];
    final tol = math.max(4.0, medH * 0.6);

    items.sort((a, b) => a.y.compareTo(b.y));
    final grouped = <List<_Item>>[];
    var meanY = 0.0;
    for (final it in items) {
      if (grouped.isNotEmpty && (it.y - meanY).abs() <= tol) {
        grouped.last.add(it);
        meanY = grouped.last.fold<double>(0, (a, e) => a + e.y) / grouped.last.length;
      } else {
        grouped.add([it]);
        meanY = it.y;
      }
    }

    final merged = _mergeOrphans(grouped);
    final lines = <ParsedLine>[];
    final raw = <String>[];
    for (final line in merged) {
      line.sort((a, b) => a.x.compareTo(b.x));
      raw.add(line.map((e) => e.text).join('  '));
      final pl = _parseLine(line);
      if (pl != null) lines.add(pl);
    }
    return ParsedTable(lines, _columns(lines, math.max(30.0, medH * 3.0)), raw);
  }

  /// الخط اليدوي ينزاح عموديًا فيتحول إلى سطر مستقل. نعيد دمجه مع أقرب سطر فيه رقم تعريف.
  List<List<_Item>> _mergeOrphans(List<List<_Item>> lines) {
    bool isAnchor(List<_Item> l) => l.any((e) {
          final d = idDigits(e.text);
          return d != null && d.length >= 8 && d.length <= 20;
        });
    double ly(List<_Item> l) => l.fold<double>(0, (a, e) => a + e.y) / l.length;

    final anchors = <int>[
      for (var i = 0; i < lines.length; i++)
        if (isAnchor(lines[i])) i
    ];
    if (anchors.length < 3) return lines;
    final diffs = <double>[
      for (var i = 1; i < anchors.length; i++)
        ly(lines[anchors[i]]) - ly(lines[anchors[i - 1]])
    ]..sort();
    final spacing = diffs[diffs.length ~/ 2];
    if (spacing <= 0) return lines;

    final result = <List<_Item>>[
      for (final a in anchors) [...lines[a]]
    ];
    final anchorY = [for (final a in anchors) ly(lines[a])];
    final anchorSet = anchors.toSet();
    final leftovers = <List<_Item>>[];
    for (var i = 0; i < lines.length; i++) {
      if (anchorSet.contains(i)) continue;
      final y = ly(lines[i]);
      var bi = 0;
      var bd = double.infinity;
      for (var k = 0; k < anchorY.length; k++) {
        final d = (y - anchorY[k]).abs();
        if (d < bd) {
          bd = d;
          bi = k;
        }
      }
      if (bd <= spacing * 0.6) {
        result[bi].addAll(lines[i]);
      } else {
        leftovers.add(lines[i]);
      }
    }
    return [...result, ...leftovers];
  }

  ParsedLine? _parseLine(List<_Item> line) {
    final tokens = line.map((e) => e.text).toList();
    final cands = tokens.map(idDigits).toList();
    var id = '';
    final used = <int>{};

    var best = -1;
    for (var i = 0; i < tokens.length; i++) {
      final cd = cands[i];
      if (cd != null &&
          cd.length >= 8 &&
          cd.length <= 20 &&
          (best < 0 || cd.length > cands[best]!.length)) {
        best = i;
      }
    }
    if (best >= 0) {
      id = cands[best]!;
      used.add(best);
    } else {
      // رقم مقسوم إلى قطعتين أو أكثر
      for (var i = 0; i < tokens.length && id.isEmpty; i++) {
        if (cands[i] == null) continue;
        final b = StringBuffer();
        var j = i;
        while (j < tokens.length && cands[j] != null && b.length < 12) {
          b.write(cands[j]);
          j++;
        }
        if (j - i >= 2 && b.length >= 12 && b.length <= 20) {
          id = b.toString();
          for (var k = i; k < j; k++) {
            used.add(k);
          }
        }
      }
    }

    var absent = false;
    final nameParts = <String>[];
    final nums = <NumTok>[];
    for (var i = 0; i < tokens.length; i++) {
      if (used.contains(i)) continue;
      final t = tokens[i];
      if (_absentRe.hasMatch(t)) {
        absent = true;
        continue;
      }
      final g = _asGrade(t);
      if (g != null) {
        final v = double.tryParse(g);
        if (v != null && v <= maxGrade) nums.add(NumTok(g, line[i].x));
        continue;
      }
      if (!idOnly && _hasLetter(t)) nameParts.add(t);
    }

    if (nameParts.isNotEmpty) {
      final norm = nameParts.expand(nameTokens).toList();
      final hdr = norm.where(_headerWords.contains).length;
      if (hdr > 0 && hdr * 2 >= norm.length) return null; // سطر عناوين
    }
    if (id.isEmpty && nameParts.isEmpty) return null;
    return ParsedLine(id, nameParts, absent, nums, tokens.join('  '));
  }

  List<NumColumn> _columns(List<ParsedLine> lines, double gap) {
    final toks = <_Tok>[];
    for (var i = 0; i < lines.length; i++) {
      for (final n in lines[i].nums) {
        toks.add(_Tok(i, n.value, n.x));
      }
    }
    if (toks.isEmpty) return const [];
    toks.sort((a, b) => a.x.compareTo(b.x));
    final clusters = <List<_Tok>>[];
    for (final t in toks) {
      if (clusters.isEmpty || t.x - clusters.last.last.x > gap) {
        clusters.add([t]);
      } else {
        clusters.last.add(t);
      }
    }
    final minCount = lines.length < 4 ? 1 : 2;
    final out = <NumColumn>[];
    for (final c in clusters) {
      final mean = c.fold<double>(0, (a, e) => a + e.x) / c.length;
      final by = <int, _Tok>{};
      for (final t in c) {
        final ex = by[t.line];
        if (ex == null || (t.x - mean).abs() < (ex.x - mean).abs()) by[t.line] = t;
      }
      if (by.length < minCount) continue;
      final col = NumColumn(mean, {for (final e in by.entries) e.key: e.value.value});
      if (_looksLikeRowNumbers(col)) continue;
      out.add(col);
    }
    return out;
  }

  /// عمود الترتيب (1، 2، 3 ...) ليس عمود نقاط.
  bool _looksLikeRowNumbers(NumColumn c) {
    final keys = c.byLine.keys.toList()..sort();
    if (keys.length < 4) return false;
    final vals = keys.map((k) => int.tryParse(c.byLine[k]!)).toList();
    if (vals.any((v) => v == null)) return false;
    var seq = 0;
    for (var i = 1; i < vals.length; i++) {
      if (vals[i]! - vals[i - 1]! == 1) seq++;
    }
    return seq >= 0.7 * (vals.length - 1);
  }

  /// يبني الصفوف من العمود الذي اختاره الأستاذ ([column] = فهرس في ParsedTable.columns).
  BuiltRows buildRows(ParsedTable t, int? column) {
    final rows = <ExtractedRow>[];
    final skipped = <String>[];
    for (var i = 0; i < t.lines.length; i++) {
      final l = t.lines[i];
      String? v;
      if (column != null && column >= 0 && column < t.columns.length) {
        v = t.columns[column].byLine[i];
      }
      if (v != null || l.absent) {
        final split = _splitName(l.nameParts);
        rows.add(ExtractedRow(
          lastName: split[0],
          firstName: split[1],
          idText: l.id,
          gradeText: v ?? '',
          absent: l.absent && v == null,
        ));
      } else if (l.id.isNotEmpty || l.nameParts.length >= 2) {
        skipped.add(l.raw);
      }
    }
    return BuiltRows(rows, skipped);
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
