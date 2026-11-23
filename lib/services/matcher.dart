import 'dart:math' as math;

import '../models.dart';
import 'text_utils.dart';

class MatchResult {
  final Student? student;
  final MatchStatus status;
  final double score;
  final String note;
  final List<Student> candidates;
  const MatchResult(this.student, this.status, this.score, this.note,
      [this.candidates = const []]);
}

/// درجة تشابه بين مجموعتي كلمات (بغض النظر عن ترتيب اللقب والاسم).
double nameScore(List<String> a, List<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final sa = ([...a]..sort()).join(' ');
  final sb = ([...b]..sort()).join(' ');
  var best = similarity(sa, sb);
  best = math.max(best, similarity(a.join(), b.join()));

  final shorter = a.length <= b.length ? a : b;
  final longer = a.length <= b.length ? b : a;
  final used = List<bool>.filled(longer.length, false);
  var sum = 0.0;
  var strong = 0;
  for (final t in shorter) {
    var bi = -1;
    var bs = 0.0;
    for (var i = 0; i < longer.length; i++) {
      if (used[i]) continue;
      final s = similarity(t, longer[i]);
      if (s > bs) {
        bs = s;
        bi = i;
      }
    }
    if (bi >= 0) {
      used[bi] = true;
      sum += bs;
      if (bs >= 0.85) strong++;
    }
  }
  best = math.max(best, sum / longer.length);
  if (shorter.length >= 2 && strong == shorter.length) {
    best = math.max(best, 0.85);
  }
  return best;
}

class StudentMatcher {
  StudentMatcher(this.students) {
    for (final s in students) {
      final id = normalizeId(s.id);
      if (id.isNotEmpty) _byId.putIfAbsent(id, () => []).add(s);
    }
  }

  final List<Student> students;
  final Map<String, List<Student>> _byId = {};

  static const double fuzzyThreshold = 0.72;

  /// الأولوية: 1) رقم التلميذ  2) اللقب والاسم  3) مطابقة تقريبية.
  /// المطابقة التقريبية لا تُعتبر "مؤكدة" أبدًا: تحتاج مراجعة الأستاذ.
  MatchResult match(String idText, String nameText) {
    final id = normalizeId(idText);
    final tokens = nameTokens(nameText);
    final key = ([...tokens]..sort()).join(' ');

    List<Student> pool = students;
    String idNote = '';
    if (id.length >= 3 && _byId.containsKey(id)) {
      final list = _byId[id]!;
      if (list.length == 1) {
        final s = list.first;
        if (tokens.isEmpty) {
          return MatchResult(s, MatchStatus.confirmed, 1.0, 'مطابقة برقم التلميذ');
        }
        final sc = nameScore(tokens, s.tokens);
        if (sc >= 0.6) {
          return MatchResult(s, MatchStatus.confirmed, 1.0, 'مطابقة برقم التلميذ');
        }
        return MatchResult(s, MatchStatus.uncertain, sc,
            'الرقم يطابق لكن الاسم مختلف، تحقق', [s]);
      }
      pool = list; // رقم مكرر في الملف: نحصر البحث بالاسم داخلهم
    } else if (id.isNotEmpty) {
      idNote = ' (الرقم غير موجود في الملف)';
    }

    if (tokens.isEmpty) {
      return const MatchResult(null, MatchStatus.missing, 0, 'لا يوجد اسم للمطابقة');
    }

    final exact = pool.where((s) => s.nameKey == key).toList();
    if (exact.length == 1) {
      return MatchResult(
          exact.first, MatchStatus.confirmed, 1.0, 'مطابقة الاسم$idNote');
    }
    if (exact.length > 1) {
      return MatchResult(exact.first, MatchStatus.uncertain, 1.0,
          'اسم مكرر في الملف: اختر التلميذ الصحيح', exact);
    }

    final scored = pool
        .map((s) => MapEntry(s, nameScore(tokens, s.tokens)))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final cands =
        scored.where((e) => e.value >= 0.5).take(5).map((e) => e.key).toList();
    if (scored.isNotEmpty && scored.first.value >= fuzzyThreshold) {
      final pct = (scored.first.value * 100).round();
      return MatchResult(scored.first.key, MatchStatus.uncertain,
          scored.first.value, 'تشابه تقريبي $pct% — يلزم التأكيد', cands);
    }
    return MatchResult(null, MatchStatus.missing,
        scored.isEmpty ? 0 : scored.first.value, 'غير موجود في القائمة', cands);
  }

  void applyTo(ExtractedRow row, MatchResult r, double maxGrade) {
    row.matched = r.student;
    row.status = r.status;
    row.score = r.score;
    row.note = r.note;
    row.candidates = r.candidates;
    row.approved = r.status == MatchStatus.confirmed && row.gradeValid(maxGrade);
  }

  void matchRow(ExtractedRow row, double maxGrade) {
    applyTo(row, match(row.idText, row.fullName), maxGrade);
  }

  void matchAll(List<ExtractedRow> rows, double maxGrade) {
    for (final r in rows) {
      matchRow(r, maxGrade);
      if (r.grade == null && r.absent) {
        r.ignored = true;
        r.note = 'غائب — لا توجد نقطة';
      }
    }
  }
}
