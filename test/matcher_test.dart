import 'package:flutter_test/flutter_test.dart';
import 'package:gs_scan_notes/models.dart';
import 'package:gs_scan_notes/services/matcher.dart';
import 'package:gs_scan_notes/services/text_utils.dart';

List<Student> _students() => [
      Student.create(row: 4, id: '20230101', lastName: 'BENALI', firstName: 'Amine'),
      Student.create(row: 5, id: '20230102', lastName: 'BENALI', firstName: 'Amina'),
      Student.create(row: 6, id: '20230104', lastName: 'KHELIFI', firstName: 'Yacine'),
      Student.create(row: 7, id: '20230112', lastName: 'DJAOUI', firstName: 'Walid'),
      Student.create(row: 8, id: '20230107', lastName: 'CHERIF', firstName: 'Mohamed Amine'),
    ];

void main() {
  test('parseGrade: فاصلة ونقطة وأرقام عربية', () {
    expect(parseGrade('12,5'), 12.5);
    expect(parseGrade('12.5'), 12.5);
    expect(parseGrade('١٤'), 14);
    expect(parseGrade('abc'), isNull);
    expect(parseGrade(''), isNull);
  });

  test('تطبيع الأسماء يزيل التشكيل والحركات', () {
    expect(normalizeName('Éléa  BEN-ALI'), 'elea ben ali');
    expect(normalizeName('أَحمد'), 'احمد');
  });

  test('مطابقة بالرقم', () {
    final m = StudentMatcher(_students());
    final r = m.match('20230104', '');
    expect(r.status, MatchStatus.confirmed);
    expect(r.student!.row, 6);
  });

  test('مطابقة دقيقة بالاسم بغض النظر عن الترتيب', () {
    final m = StudentMatcher(_students());
    final r = m.match('', 'Amine BENALI');
    expect(r.status, MatchStatus.confirmed);
    expect(r.student!.row, 4);
  });

  test('أسماء متشابهة: لا مطابقة مؤكدة بالخطأ (Amine مقابل Amina)', () {
    final m = StudentMatcher(_students());
    expect(m.match('', 'BENALI Amine').student!.row, 4);
    expect(m.match('', 'BENALI Amina').student!.row, 5);
    // خطأ OCR: يجب ألا يصبح "مؤكدًا"
    final r = m.match('', 'BENALI Amin');
    expect(r.status, MatchStatus.uncertain);
  });

  test('خطأ إملائي بسيط = غير مؤكد وليس مؤكدًا', () {
    final r = StudentMatcher(_students()).match('', 'KHELIFI Yacin');
    expect(r.status, MatchStatus.uncertain);
    expect(r.student!.row, 6);
  });

  test('تلميذ غير موجود = مفقود', () {
    final r = StudentMatcher(_students()).match('', 'TOUATI Walid');
    expect(r.status, MatchStatus.missing);
    expect(r.student, isNull);
  });

  test('رقم يطابق لكن الاسم مختلف تمامًا = غير مؤكد', () {
    final r = StudentMatcher(_students()).match('20230112', 'ZZZZ QQQQ');
    expect(r.status, MatchStatus.uncertain);
  });

  test('تطابق مجموعة جزئية للأسماء المركبة = غير مؤكد', () {
    final r = StudentMatcher(_students()).match('', 'CHERIF Mohamed');
    expect(r.student!.row, 8);
    expect(r.status, MatchStatus.uncertain);
  });
}
