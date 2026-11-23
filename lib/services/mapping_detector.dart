import 'dart:math' as math;

import '../models.dart';
import 'text_utils.dart';

/// اقتراح تلقائي لسطر العناوين والأعمدة (يستطيع الأستاذ تغييرها يدويًا).
class MappingDetector {
  static int detectHeaderRow(SheetGrid g) {
    final limit = math.min(g.maxRow, 20);
    if (limit < 1) return 1;
    final counts = <int, int>{};
    var best = 0;
    for (var r = 1; r <= limit; r++) {
      final n = g.rows[r]?.values.where((v) => v.trim().isNotEmpty).length ?? 0;
      counts[r] = n;
      if (n > best) best = n;
    }
    if (best == 0) return 1;
    final threshold = math.max(2, (best * 0.6).ceil());
    for (var r = 1; r <= limit; r++) {
      if ((counts[r] ?? 0) >= threshold) return r;
    }
    return 1;
  }

  static const _gradeWords = {
    'note', 'notes', 'moyenne', 'mark', 'score', 'devoir', 'examen',
    'composition', 'controle', 'نقطه', 'نقاط', 'علامه', 'معدل',
  };
  static const _idWords = {'matricule', 'identifiant', 'massar', 'code', 'id', 'رقم'};

  static ColumnMapping detect(SheetGrid g) {
    final hr = detectHeaderRow(g);
    final m = ColumnMapping(headerRow: hr);
    int? full, last, first, id, grade;
    for (var c = 0; c <= g.maxCol; c++) {
      final tokens = nameTokens(g.cell(hr, c));
      if (tokens.isEmpty) continue;
      final joined = tokens.join(' ');
      final hasPrenom = joined.contains('prenom') || tokens.contains('first');
      final hasNom = joined.replaceAll('prenom', '').contains('nom') ||
          tokens.contains('name') ||
          tokens.contains('surname');
      final hasLaqab = joined.contains('لقب');
      final hasIsm = joined.contains('اسم');
      if ((hasNom && hasPrenom) || (hasLaqab && hasIsm)) {
        full ??= c;
      } else if (hasPrenom) {
        first ??= c;
      } else if (hasNom || hasLaqab) {
        last ??= c;
      } else if (hasIsm) {
        first ??= c;
      } else if (tokens.any(_gradeWords.contains)) {
        grade ??= c;
      } else if (tokens.any(_idWords.contains) && !joined.contains('naiss')) {
        id ??= c;
      }
    }
    m.nameCol = full ?? last ?? first;
    if (full == null && last != null) m.firstNameCol = first;
    m.idCol = id;
    m.gradeCol = grade ?? (g.maxCol + 1);
    return m;
  }
}
