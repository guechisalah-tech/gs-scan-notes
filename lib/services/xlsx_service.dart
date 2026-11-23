import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models.dart';
import 'text_utils.dart';

XmlElement? _kid(XmlElement e, String name) {
  for (final c in e.childElements) {
    if (c.name.local == name) return c;
  }
  return null;
}

Iterable<XmlElement> _kids(XmlElement e, String name) =>
    e.childElements.where((c) => c.name.local == name);

String _stripBom(String s) =>
    s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF ? s.substring(1) : s;

/// قراءة وتعديل ملفات XLSX مباشرة على مستوى XML داخل ملف ZIP:
/// كل الأجزاء الأخرى (التنسيق، الأوراق الأخرى، الدمج، العرض...) تبقى كما هي حرفيًا.
class XlsxDocument {
  XlsxDocument._(this._archive, this.sheets, this._shared);

  final Archive _archive;
  final List<SheetInfo> sheets;
  final List<String> _shared;

  static XlsxDocument parse(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const AppException(
          'تعذر فتح الملف: ليس ملف XLSX صالحًا أو أنه محمي بكلمة مرور.');
    }
    String? read(String name) {
      final f = archive.findFile(name);
      if (f == null) return null;
      return _stripBom(utf8.decode(f.content as List<int>, allowMalformed: true));
    }

    final wbText = read('xl/workbook.xml');
    if (wbText == null) {
      throw const AppException(
          'الملف ليس مصنف Excel بصيغة XLSX (إن كان .xls فاحفظه من Excel بصيغة .xlsx).');
    }
    try {
      final rels = <String, String>{};
      final relText = read('xl/_rels/workbook.xml.rels');
      if (relText != null) {
        for (final r in _kids(XmlDocument.parse(relText).rootElement, 'Relationship')) {
          final type = r.getAttribute('Type') ?? '';
          if (type.endsWith('/worksheet')) {
            rels[r.getAttribute('Id') ?? ''] = r.getAttribute('Target') ?? '';
          }
        }
      }
      final sheets = <SheetInfo>[];
      final sheetsEl = _kid(XmlDocument.parse(wbText).rootElement, 'sheets');
      if (sheetsEl != null) {
        for (final s in _kids(sheetsEl, 'sheet')) {
          String? rid;
          for (final a in s.attributes) {
            if (a.name.local == 'id') rid = a.value;
          }
          final target = rid == null ? null : rels[rid];
          if (target == null) continue;
          sheets.add(SheetInfo(s.getAttribute('name') ?? 'Sheet', _resolve(target)));
        }
      }
      if (sheets.isEmpty) {
        throw const AppException('لا توجد أوراق عمل في الملف.');
      }
      final shared = <String>[];
      final ssText = read('xl/sharedStrings.xml');
      if (ssText != null) {
        for (final si in _kids(XmlDocument.parse(ssText).rootElement, 'si')) {
          shared.add(_siText(si));
        }
      }
      return XlsxDocument._(archive, sheets, shared);
    } on XmlException {
      throw const AppException('ملف XLSX تالف أو بنية XML غير مدعومة.');
    }
  }

  static String _resolve(String target) {
    final t = target.replaceAll('\\', '/');
    if (t.startsWith('/')) return t.substring(1);
    final parts = <String>['xl'];
    for (final seg in t.split('/')) {
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (seg != '.' && seg.isNotEmpty) {
        parts.add(seg);
      }
    }
    return parts.join('/');
  }

  static String _siText(XmlElement si) {
    final b = StringBuffer();
    for (final c in si.childElements) {
      if (c.name.local == 't') {
        b.write(c.innerText);
      } else if (c.name.local == 'r') {
        for (final t in _kids(c, 't')) {
          b.write(t.innerText);
        }
      }
    }
    return b.toString();
  }

  String? _read(String name) {
    final f = _archive.findFile(name);
    if (f == null) return null;
    return _stripBom(utf8.decode(f.content as List<int>, allowMalformed: true));
  }

  String _cellText(XmlElement c) {
    final t = c.getAttribute('t');
    final v = _kid(c, 'v')?.innerText ?? '';
    switch (t) {
      case 's':
        final i = int.tryParse(v.trim());
        return (i != null && i >= 0 && i < _shared.length) ? _shared[i] : '';
      case 'inlineStr':
        final is_ = _kid(c, 'is');
        return is_ == null ? '' : _siText(is_);
      case 'b':
        return v.trim() == '1' ? 'TRUE' : 'FALSE';
      default:
        return v;
    }
  }

  SheetGrid readSheet(SheetInfo sheet) {
    final text = _read(sheet.path);
    if (text == null) throw const AppException('ورقة العمل غير موجودة داخل الملف.');
    final root = XmlDocument.parse(text).rootElement;
    final data = _kid(root, 'sheetData');
    final rows = <int, Map<int, String>>{};
    var maxRow = 0, maxCol = 0;
    if (data != null) {
      var prevRow = 0;
      for (final row in _kids(data, 'row')) {
        final rIdx = int.tryParse(row.getAttribute('r') ?? '') ?? (prevRow + 1);
        prevRow = rIdx;
        var prevCol = -1;
        for (final c in _kids(row, 'c')) {
          final ref = c.getAttribute('r');
          final col = ref != null ? colIndexFromRef(ref) : prevCol + 1;
          prevCol = col;
          final txt = _cellText(c);
          if (txt.trim().isEmpty) continue;
          rows.putIfAbsent(rIdx, () => {})[col] = txt;
          maxRow = math.max(maxRow, rIdx);
          maxCol = math.max(maxCol, col);
        }
      }
    }
    return SheetGrid(rows, maxRow, maxCol);
  }

  static String _fmt(double v) {
    final r = (v * 100).round() / 100;
    return r == r.truncateToDouble() ? r.toInt().toString() : r.toString();
  }

  static bool _isBlank(XmlElement c) {
    final v = _kid(c, 'v');
    return (v == null || v.innerText.trim().isEmpty) &&
        _kid(c, 'is') == null &&
        _kid(c, 'f') == null;
  }

  XmlElement _rowFor(XmlElement data, Map<int, XmlElement> map, int n) {
    final ex = map[n];
    if (ex != null) return ex;
    final created = XmlElement(XmlName('row'), [XmlAttribute(XmlName('r'), '$n')]);
    XmlElement? before;
    for (final r in _kids(data, 'row')) {
      final rn = int.tryParse(r.getAttribute('r') ?? '') ?? 0;
      if (rn > n) {
        before = r;
        break;
      }
    }
    if (before != null) {
      data.children.insert(data.children.indexOf(before), created);
    } else {
      data.children.add(created);
    }
    map[n] = created;
    return created;
  }

  XmlElement? _findCell(XmlElement row, int col) {
    for (final c in _kids(row, 'c')) {
      final ref = c.getAttribute('r');
      if (ref != null && colIndexFromRef(ref) == col) return c;
    }
    return null;
  }

  XmlElement _cellFor(XmlElement row, int rowIdx, int col) {
    XmlElement? before;
    for (final c in _kids(row, 'c')) {
      final ref = c.getAttribute('r');
      final ci = ref == null ? -1 : colIndexFromRef(ref);
      if (ci == col) return c;
      if (ci > col && before == null) before = c;
    }
    final created = XmlElement(
        XmlName('c'), [XmlAttribute(XmlName('r'), '${colLetters(col)}$rowIdx')]);
    if (before != null) {
      row.children.insert(row.children.indexOf(before), created);
    } else {
      row.children.add(created);
    }
    return created;
  }

  /// يكتب النقاط (صف -> نقطة) في العمود [col] ويعيد ملف XLSX جديدًا.
  /// الملف الأصلي (البايتات المحمّلة) لا يتغير أبدًا.
  Uint8List writeGrades(
    SheetInfo sheet,
    Map<int, double> grades,
    int col, {
    int? headerRow,
    String? headerText,
  }) {
    final text = _read(sheet.path);
    if (text == null) throw const AppException('ورقة العمل غير موجودة داخل الملف.');
    final doc = XmlDocument.parse(text);
    final root = doc.rootElement;
    final data = _kid(root, 'sheetData');
    if (data == null) throw const AppException('بنية ورقة العمل غير صالحة.');

    final rowMap = <int, XmlElement>{};
    for (final r in _kids(data, 'row')) {
      final n = int.tryParse(r.getAttribute('r') ?? '');
      if (n != null) rowMap[n] = r;
    }

    var formulaTouched = false;

    if (headerRow != null && headerText != null) {
      final row = _rowFor(data, rowMap, headerRow);
      final cell = _cellFor(row, headerRow, col);
      if (_isBlank(cell)) {
        final left = col > 0 ? _findCell(row, col - 1) : null;
        final style = left?.getAttribute('s');
        if (style != null) cell.setAttribute('s', style);
        cell.setAttribute('t', 'inlineStr');
        cell.children.clear();
        cell.children.add(XmlElement(XmlName('is'), [], [
          XmlElement(XmlName('t'), [], [XmlText(headerText)])
        ]));
        row.removeAttribute('spans');
      }
    }

    for (final e in grades.entries) {
      final row = _rowFor(data, rowMap, e.key);
      final cell = _cellFor(row, e.key, col);
      if (_kid(cell, 'f') != null) formulaTouched = true;
      cell.removeAttribute('t');
      cell.children.clear();
      cell.children.add(XmlElement(XmlName('v'), [], [XmlText(_fmt(e.value))]));
      row.removeAttribute('spans');
    }

    final dim = _kid(root, 'dimension');
    final ref = dim?.getAttribute('ref');
    if (dim != null && ref != null) {
      final parts = ref.split(':');
      final end = parts.last;
      final maxTouched = grades.keys.fold<int>(headerRow ?? 0, math.max);
      dim.setAttribute('ref',
          '${parts.first}:${colLetters(math.max(colIndexFromRef(end), col))}${math.max(rowFromRef(end), maxTouched)}');
    }

    final newSheet = utf8.encode(doc.toXmlString());
    final out = Archive();
    for (final f in _archive.files) {
      if (!f.isFile) continue;
      if (f.name == sheet.path) {
        out.addFile(ArchiveFile(f.name, newSheet.length, newSheet));
        continue;
      }
      if (formulaTouched) {
        // حذف calcChain كي لا يشتكي Excel من خلية صيغة استُبدلت
        if (f.name == 'xl/calcChain.xml') continue;
        if (f.name == '[Content_Types].xml' || f.name == 'xl/_rels/workbook.xml.rels') {
          final s = utf8.decode(f.content as List<int>, allowMalformed: true);
          final cleaned = s
              .replaceAll(RegExp(r'<Override[^>]*calcChain[^>]*/>'), '')
              .replaceAll(RegExp(r'<Relationship[^>]*calcChain[^>]*/>'), '');
          final b = utf8.encode(cleaned);
          out.addFile(ArchiveFile(f.name, b.length, b));
          continue;
        }
      }
      out.addFile(ArchiveFile(f.name, f.size, f.content));
    }
    final List<int>? encoded = ZipEncoder().encode(out);
    if (encoded == null) throw const AppException('فشل إنشاء ملف Excel.');
    return Uint8List.fromList(encoded);
  }
}
