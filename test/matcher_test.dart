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

  group('أرقام تعريف طويلة', () {
    List<Student> longIds() => [
          Student.create(row: 9, id: '1101328010140700', lastName: 'خذاري', firstName: 'جمانة'),
          Student.create(row: 10, id: '1001228110059200', lastName: 'بحري', firstName: 'عبد الباقي'),
          Student.create(row: 11, id: '1.1013281100023E+15', lastName: 'عيلاوي', firstName: 'أروى'),
        ];

    test('الصيغة العلمية في Excel تُطابَق', () {
      expect(normalizeId('1.1013281100023E+15'), '1101328110002300');
      final r = StudentMatcher(longIds(), idOnly: true).match('1101328110002300', '');
      expect(r.status, MatchStatus.confirmed);
      expect(r.student!.row, 11);
    });

    test('idOnly: اسم مقروء خاطئ لا يمنع التأكيد برقم مطابق', () {
      final r = StudentMatcher(longIds(), idOnly: true).match('1101328010140700', 'jgaia110');
      expect(r.status, MatchStatus.confirmed);
      expect(r.student!.row, 9);
    });

    test('رقم بخطأ رقم واحد = غير مؤكد وليس مؤكدًا', () {
      final r = StudentMatcher(longIds(), idOnly: true).match('1101328010140780', '');
      expect(r.status, MatchStatus.uncertain);
      expect(r.student!.row, 9);
    });

    test('رقم زائد من خط الجدول في البداية أو النهاية يُحذف ويُؤكَّد', () {
      final m = StudentMatcher(longIds(), idOnly: true);
      final a = m.match('11101328010140700', ''); // 1 زائدة في البداية
      expect(a.status, MatchStatus.confirmed);
      expect(a.student!.row, 9);
      final b = m.match('10012281100592001', ''); // 1 زائدة في النهاية
      expect(b.status, MatchStatus.confirmed);
      expect(b.student!.row, 10);
    });

    test('رقم بعيد = مفقود', () {
      final r = StudentMatcher(longIds(), idOnly: true).match('9999999999999999', '');
      expect(r.status, MatchStatus.missing);
    });

    test('رمز زائد من خط الجدول قبل الرقم يُحذف فتتأكد المطابقة', () {
      final r = StudentMatcher(longIds(), idOnly: true).match('11001228110059200', '');
      expect(r.status, MatchStatus.confirmed);
      expect(r.student!.row, 10);
    });
  });
}
