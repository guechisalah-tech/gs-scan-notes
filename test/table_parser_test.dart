import 'package:flutter_test/flutter_test.dart';
import 'package:gs_scan_notes/services/ocr_models.dart';
import 'package:gs_scan_notes/services/table_parser.dart';

OcrWord _w(String t, double x, double y) => OcrWord(t, x, y, x + 60, y + 30);

void main() {
  test('استخراج لقب/اسم/نقطة وتجاهل العناوين ورقم الترتيب', () {
    final words = [
      _w('N°', 40, 100), _w('Nom', 130, 100), _w('Prénom', 430, 100), _w('Note', 820, 100),
      _w('1', 40, 170), _w('BENALI', 130, 170), _w('Amine', 430, 170), _w('15', 820, 170),
      _w('2', 40, 240), _w('BENALI', 130, 241), _w('Amina', 430, 239), _w('12,5', 820, 240),
      _w('3', 40, 310), _w('HAMDI', 130, 310), _w('Lina', 430, 310), _w('ABS', 820, 310),
      _w('4', 40, 380), _w('CHERIF', 130, 380), _w('Mohamed', 430, 380), _w('Amine', 560, 380), _w('11', 820, 380),
    ];
    final res = TableParser().parse(OcrResult(words, 0));
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

  test('رقم الترتيب لا يُعتبر نقطة إذا فُقدت النقطة', () {
    final words = [
      _w('5', 40, 170), _w('MEZIANE', 130, 170), _w('Sarah', 430, 170),
    ];
    final res = TableParser().parse(OcrResult(words, 0));
    expect(res.rows, isEmpty);
    expect(res.skipped.length, 1);
  });

  test('رقم التلميذ الطويل يُفصل عن النقطة', () {
    final words = [
      _w('20230104', 40, 170), _w('KHELIFI', 200, 170), _w('Yacine', 430, 170), _w('14', 820, 170),
    ];
    final res = TableParser().parse(OcrResult(words, 0));
    expect(res.rows.single.idText, '20230104');
    expect(res.rows.single.gradeText, '14');
  });
}
