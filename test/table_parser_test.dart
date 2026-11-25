import 'package:flutter_test/flutter_test.dart';
import 'package:gs_scan_notes/services/ocr_models.dart';
import 'package:gs_scan_notes/services/table_parser.dart';

OcrWord _w(String t, double x, double y) => OcrWord(t, x, y, x + 60, y + 30);

void main() {
  test('جدول لاتيني: لقب/اسم/نقطة، تجاهل العناوين وعمود الترتيب', () {
    final words = [
      _w('N°', 40, 100), _w('Nom', 130, 100), _w('Prénom', 430, 100), _w('Note', 820, 100),
      _w('1', 40, 170), _w('BENALI', 130, 170), _w('Amine', 430, 170), _w('15', 820, 170),
      _w('2', 40, 240), _w('BENALI', 130, 241), _w('Amina', 430, 239), _w('12,5', 820, 240),
      _w('3', 40, 310), _w('HAMDI', 130, 310), _w('Lina', 430, 310), _w('ABS', 820, 310),
      _w('4', 40, 380), _w('CHERIF', 130, 380), _w('Mohamed', 430, 380), _w('Amine', 560, 380), _w('11', 820, 380),
    ];
    final p = TableParser();
    final t = p.parse(OcrResult(words, 0));
    expect(t.columns.length, 1); // عمود الترتيب 1،2،3،4 استُبعد
    final res = p.buildRows(t, 0);
    expect(res.rows.length, 4);
    expect(res.rows[0].lastName, 'BENALI');
    expect(res.rows[0].firstName, 'Amine');
    expect(res.rows[0].gradeText, '15');
    expect(res.rows[1].gradeText, '12.5');
    expect(res.rows[2].absent, isTrue);
    expect(res.rows[2].gradeText, '');
    expect(res.rows[3].firstName, 'Mohamed Amine');
    expect(res.rows[3].gradeText, '11');
  });

  test('سطر بلا نقطة يذهب إلى الأسطر المتجاوزة ولا يأخذ رقم الترتيب', () {
    final words = <OcrWord>[];
    final names = [('A', 'Aaa'), ('B', 'Bbb'), ('C', 'Ccc'), ('D', 'Ddd'), ('E', 'Eee')];
    for (var i = 0; i < names.length; i++) {
      final y = 100.0 + i * 70;
      words.addAll([_w('${i + 1}', 40, y), _w(names[i].$1 * 5, 130, y), _w(names[i].$2, 430, y)]);
      if (i != 2 && i != 4) words.add(_w('${10 + i}', 820, y));
    }
    final p = TableParser();
    final t = p.parse(OcrResult(words, 0));
    final res = p.buildRows(t, 0);
    expect(res.rows.length, 3);
    expect(res.skipped.length, 2);
  });

  test('جدول عربي: صفوف بأرقام التعريف الطويلة، وعدة أعمدة نقاط بخط اليد', () {
    // ترتيب الأعمدة (من اليسار): فرض ~400، نشاطات ~760، تاريخ ~900، رقم التعريف ~1450
    final ids = [
      '1101328010140700', '1001228110059200', '1101328110002300',
      '1001228110064000', '1001119011190100', '1001228150005400',
    ];
    final words = <OcrWord>[];
    for (var i = 0; i < ids.length; i++) {
      final y = 400.0 + i * 55;
      words.add(_w(ids[i], 1400, y));
      words.add(_w('2013-11-27', 880, y)); // تاريخ: لا يُعتبر نقطة
      words.add(_w('${15 + i % 4}', 760, y + (i.isEven ? 8 : -8))); // نشاطات (انزياح عمودي)
      if (i < 4) words.add(_w('${13 + i}', 390, y + 12)); // فرض: لا توجد إلا لأول 4 صفوف
    }
    // عنوان بلا أرقام تعريف
    words.add(_w('Lycee', 600, 100));
    final p = TableParser(idOnly: true);
    final t = p.parse(OcrResult(words, 0));
    expect(t.lines.length, 6);
    expect(t.lines.first.id, '1101328010140700');
    expect(t.columns.length, 2);
    expect(t.columns[0].count, 4); // فرض (يسار)
    expect(t.columns[1].count, 6); // نشاطات

    final fard = p.buildRows(t, 0);
    expect(fard.rows.length, 4);
    expect(fard.rows.first.idText, '1101328010140700');
    expect(fard.rows.first.gradeText, '13');
    expect(fard.skipped.length, 2); // صفان بلا فرض
  });

  test('رقم تعريف مقسوم إلى قطعتين ورموز متشابهة', () {
    final words = [
      _w('11013280', 1300, 170), _w('10140700', 1420, 170), _w('18', 700, 170),
      _w('l001228110059200', 1300, 240), _w('16', 700, 240),
      _w('1101328110002300', 1300, 310), _w('1S', 700, 310),
    ];
    final p = TableParser(idOnly: true);
    final t = p.parse(OcrResult(words, 0));
    expect(t.lines.length, 3);
    expect(t.lines[0].id, '1101328010140700');
    expect(t.lines[1].id, '1001228110059200'); // l → 1
    final r = p.buildRows(t, 0);
    expect(r.rows[2].gradeText, '15'); // S → 5
  });

  test('رقم التلميذ الطويل يُفصل عن النقطة (جدول لاتيني برقم)', () {
    final words = [
      _w('20230104', 40, 170), _w('KHELIFI', 200, 170), _w('Yacine', 430, 170), _w('14', 820, 170),
    ];
    final p = TableParser();
    final t = p.parse(OcrResult(words, 0));
    final res = p.buildRows(t, 0);
    expect(res.rows.single.idText, '20230104');
    expect(res.rows.single.gradeText, '14');
  });
}
