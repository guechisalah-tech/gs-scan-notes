import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gs_scan_notes/services/mapping_detector.dart';
import 'package:gs_scan_notes/services/xlsx_service.dart';

void main() {
  final bytes = File('sample_data/liste_eleves_exemple.xlsx').readAsBytesSync();

  test('قراءة الأوراق والأعمدة واكتشاف التعيين تلقائيًا', () {
    final doc = XlsxDocument.parse(bytes);
    expect(doc.sheets.map((s) => s.name), ['3AS-1', '3AS-2']);
    final g = doc.readSheet(doc.sheets.first);
    final m = MappingDetector.detect(g);
    expect(m.headerRow, 3);
    expect(m.nameCol, 2); // Nom
    expect(m.firstNameCol, 3); // Prénom
    expect(m.idCol, 1); // Matricule
    expect(m.gradeCol, 5); // Note
    expect(g.cell(4, 2), 'BENALI');
  });

  test('الإدراج يحفظ باقي البيانات ولا يمس الملف الأصلي', () {
    final doc = XlsxDocument.parse(bytes);
    final sheet = doc.sheets.first;
    final out = doc.writeGrades(sheet, {4: 15, 5: 12.5, 12: 9.75}, 5,
        headerRow: 3, headerText: 'Note');

    final doc2 = XlsxDocument.parse(out);
    final g = doc2.readSheet(doc2.sheets.first);
    expect(g.cell(4, 5), '15');
    expect(g.cell(5, 5), '12.5');
    expect(g.cell(12, 5), '9.75'); // استبدال قيمة موجودة (كانت 6)
    expect(g.cell(4, 2), 'BENALI'); // بقية البيانات
    expect(g.cell(3, 5), 'Note');
    expect(g.cell(6, 5), ''); // صفوف لم تُمس

    // الورقة الثانية لم تتغير
    final g2 = doc2.readSheet(doc2.sheets[1]);
    expect(g2.cell(2, 0), 'HAMMOUCHE Sofiane');

    // الأصل لم يتغير
    final orig = XlsxDocument.parse(bytes).readSheet(sheet);
    expect(orig.cell(4, 5), '');
    expect(orig.cell(12, 5), '6');
  });

  test('إنشاء عمود جديد خلف آخر عمود', () {
    final doc = XlsxDocument.parse(bytes);
    final sheet = doc.sheets[1];
    final out = doc.writeGrades(sheet, {2: 14}, 2, headerRow: 1, headerText: 'Note2');
    final d2 = XlsxDocument.parse(out);
    final g = d2.readSheet(d2.sheets[1]);
    expect(g.cell(2, 2), '14');
    expect(g.cell(1, 2), 'Note2');
    expect(g.cell(1, 1), 'Note'); // لم يتغير
  });
}
