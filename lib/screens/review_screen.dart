import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';
import 'manual_entry_screen.dart';

enum _Filter { all, confirmed, uncertain, missing, ignored }

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  _Filter filter = _Filter.all;

  bool _match(ExtractedRow r, _Filter f) {
    switch (f) {
      case _Filter.all:
        return true;
      case _Filter.ignored:
        return r.ignored;
      case _Filter.confirmed:
        return !r.ignored && r.status == MatchStatus.confirmed;
      case _Filter.uncertain:
        return !r.ignored && r.status == MatchStatus.uncertain;
      case _Filter.missing:
        return !r.ignored && r.status == MatchStatus.missing;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final visible = s.rows.where((r) => _match(r, filter)).toList();
    int count(_Filter f) => s.rows.where((r) => _match(r, f)).length;
    final plan = s.buildSavePlan();

    final chips = <_Filter, String>{
      _Filter.all: 'الكل',
      _Filter.confirmed: 'مؤكدة',
      _Filter.uncertain: 'غير مؤكدة',
      _Filter.missing: 'مفقودة',
      _Filter.ignored: 'متجاهلة',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('مراجعة ومطابقة التلاميذ'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'rematch') {
                s.rematchAll();
              } else if (v == 'approve') {
                s.approveConfirmed();
              } else if (v == 'skipped') {
                _showSkipped(context, s);
              } else if (v == 'all') {
                Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ManualEntryScreen()));
              } else if (v == 'raw') {
                _showRaw(context, s);
              } else if (v == 'add') {
                final r = s.addManualRow();
                _edit(context, s, r);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'approve', child: Text('اعتماد كل المؤكدة')),
              const PopupMenuItem(value: 'rematch', child: Text('إعادة المطابقة للكل')),
              PopupMenuItem(
                  value: 'skipped', child: Text('الأسطر المتجاوزة (${s.skipped.length})')),
              const PopupMenuItem(value: 'all', child: Text('كل التلاميذ وإكمال النقاط يدويًا')),
              const PopupMenuItem(value: 'raw', child: Text('النص المقروء من الصورة')),
              const PopupMenuItem(value: 'add', child: Text('إضافة صف يدويًا')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                for (final e in chips.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text('${e.value} (${count(e.key)})'),
                      selected: filter == e.key,
                      onSelected: (_) => setState(() => filter = e.key),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            color: Colors.grey.shade300,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: const Row(
              children: [
                SizedBox(width: 40),
                _H('اللقب', 3),
                _H('الاسم', 3),
                _H('النقطة', 2),
                _H('التلميذ المطابق', 4),
                _H('الحالة', 3),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('لا توجد صفوف في هذا التصنيف'))
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => _RowTile(row: visible[i], s: s, onTap: () => _edit(ctx, s, visible[i])),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.grey.shade400, blurRadius: 6)],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'معتمدة للإدراج: ${plan.toInsert}'
                      '${plan.notApproved > 0 ? '\nتحتاج مراجعة: ${plan.notApproved}' : ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.save_alt),
                    label: const Text('حفظ ملف Excel'),
                    onPressed: s.busy ? null : () => confirmAndSave(context, s),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRaw(BuildContext context, AppState s) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ما قرأه المحرك (للتشخيص)'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              s.rawLines.isEmpty ? 'لا يوجد نص' : s.rawLines.join('\n'),
              style: const TextStyle(fontSize: 12),
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
      ),
    );
  }

  void _showSkipped(BuildContext context, AppState s) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('أسطر لم تُعتبر صفوف تلاميذ'),
        content: SizedBox(
          width: double.maxFinite,
          child: s.skipped.isEmpty
              ? const Text('لا توجد أسطر متجاوزة.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    const Text('هذه أسطر فيها أسماء لكن بدون نقطة مقروءة. اضغط + لإضافتها كصف وتكملة النقطة يدويًا.',
                        style: TextStyle(fontSize: 12)),
                    for (final line in s.skipped)
                      ListTile(
                        dense: true,
                        title: Text(line),
                        trailing: IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () {
                            final parts = line
                                .split(' ')
                                .where((e) => e.isNotEmpty && !RegExp(r'^\d+$').hasMatch(e))
                                .toList();
                            Navigator.pop(ctx);
                            final r = s.addManualRow(
                              last: parts.isEmpty ? '' : parts.first,
                              first: parts.length > 1 ? parts.sublist(1).join(' ') : '',
                            );
                            _edit(context, s, r);
                          },
                        ),
                      ),
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
      ),
    );
  }

  void _edit(BuildContext context, AppState s, ExtractedRow r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EditSheet(row: r, s: s),
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.t, this.flex);
  final String t;
  final int flex;
  @override
  Widget build(BuildContext context) => Expanded(
        flex: flex,
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      );
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.s, required this.onTap});
  final ExtractedRow row;
  final AppState s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dup = s.duplicateCount(row) > 1;
    final invalid = !row.gradeValid(s.maxGrade);
    String label;
    Color color;
    if (row.ignored) {
      label = 'متجاهل';
      color = Colors.grey.shade300;
    } else if (invalid) {
      label = 'نقطة غير صالحة';
      color = Colors.red.shade100;
    } else if (dup) {
      label = 'تكرار';
      color = Colors.orange.shade200;
    } else {
      switch (row.status) {
        case MatchStatus.confirmed:
          label = 'مؤكدة';
          color = Colors.green.shade100;
          break;
        case MatchStatus.uncertain:
          label = 'غير مؤكدة';
          color = Colors.orange.shade100;
          break;
        case MatchStatus.missing:
          label = 'مفقودة';
          color = Colors.red.shade100;
          break;
      }
    }
    final overwrite = row.matched != null && row.matched!.existingGrade.isNotEmpty;
    const st = TextStyle(fontSize: 13);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: row.ignored ? Colors.grey.shade100 : null,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: Checkbox(
                visualDensity: VisualDensity.compact,
                value: row.approved,
                onChanged: (row.ignored || row.matched == null || invalid)
                    ? null
                    : (v) => s.setApproved(row, v == true),
              ),
            ),
            Expanded(flex: 3, child: Text(row.lastName.isEmpty ? row.idText : row.lastName, style: st)),
            Expanded(flex: 3, child: Text(row.firstName, style: st)),
            Expanded(
              flex: 2,
              child: Text(row.absent && row.gradeText.isEmpty ? 'غ' : row.gradeText,
                  style: st.copyWith(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.matched == null
                        ? '—'
                        : '${row.status == MatchStatus.uncertain ? '؟ ' : ''}${row.matched!.displayName}',
                    style: st,
                  ),
                  if (overwrite)
                    Text('تستبدل: ${row.matched!.existingGrade}',
                        style: TextStyle(fontSize: 11, color: Colors.orange.shade900)),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                child: Text(label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.row, required this.s});
  final ExtractedRow row;
  final AppState s;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController last = TextEditingController(text: widget.row.lastName);
  late final TextEditingController first = TextEditingController(text: widget.row.firstName);
  late final TextEditingController grade = TextEditingController(text: widget.row.gradeText);
  late final TextEditingController id = TextEditingController(text: widget.row.idText);

  @override
  void dispose() {
    last.dispose();
    first.dispose();
    grade.dispose();
    id.dispose();
    super.dispose();
  }

  void _apply() => widget.s.updateRowFields(widget.row,
      last: last.text.trim(), first: first.text.trim(), grade: grade.text.trim(), id: id.text.trim());

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final r = widget.row;
    return AnimatedBuilder(
      animation: s,
      builder: (ctx, _) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('تعديل الصف', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                    controller: id,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'رقم التلميذ (رقم التعريف)', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                    controller: last,
                    decoration: const InputDecoration(labelText: 'اللقب', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                    controller: first,
                    decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                  controller: grade,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'النقطة (0 – ${s.maxGrade.toStringAsFixed(0)})',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  r.matched == null
                      ? 'التلميذ المطابق: لا يوجد'
                      : 'التلميذ المطابق: ${r.matched!.displayName}'
                          '${r.matched!.id.isEmpty ? '' : ' [${r.matched!.id}]'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (r.note.isNotEmpty) Text(r.note, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.person_search),
                      label: const Text('اختيار التلميذ'),
                      onPressed: () async {
                        _apply();
                        final st = await showStudentPicker(context, s.students, r.candidates);
                        if (st != null) s.setStudent(r, st);
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المطابقة'),
                      onPressed: () {
                        _apply();
                        s.rematchRow(r);
                      },
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تجاهل هذا الصف'),
                  value: r.ignored,
                  onChanged: (v) => s.setIgnored(r, v),
                ),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          _apply();
                          Navigator.pop(context);
                        },
                        child: const Text('حفظ التعديل'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: (r.matched == null || r.ignored)
                            ? null
                            : () {
                                _apply();
                                if (!r.gradeValid(s.maxGrade)) {
                                  showToast(context, 'النقطة غير صالحة، صحّحها أولًا', error: true);
                                  return;
                                }
                                s.setApproved(r, true);
                                Navigator.pop(context);
                              },
                        child: const Text('اعتماد'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// مراجعة أخيرة ثم حفظ نسخة جديدة. لا يُدرج شيء قبل موافقة الأستاذ هنا.
Future<void> confirmAndSave(BuildContext context, AppState s) async {
  final plan = s.buildSavePlan();
  if (plan.problems.isNotEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('يجب حل المشاكل التالية'),
        content: Text(plan.problems.join('\n')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسنًا'))],
      ),
    );
    return;
  }
  if (plan.toInsert == 0) {
    showToast(context, 'لا توجد نقاط معتمدة للإدراج. اعتمد الصفوف أولًا.', error: true);
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تأكيد الإدراج'),
      content: Text(
        'سيتم إنشاء نسخة جديدة من الملف (الأصل لا يتغير).\n\n'
        '• نقاط ستُدرج: ${plan.toInsert}\n'
        '${plan.overwrites > 0 ? '• قيم موجودة في عمود النقاط ستُستبدل: ${plan.overwrites}\n' : ''}'
        '${plan.notApproved > 0 ? '• صفوف غير معتمدة لن تُدرج: ${plan.notApproved}\n' : ''}',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اعتماد وحفظ')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await runGuarded(context, () async {
    final path = await s.saveExcel();
    if (!context.mounted) return;
    if (path == null) {
      showToast(context, 'تم إلغاء الحفظ');
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تم الحفظ'),
          content: Text('أُدرجت ${plan.toInsert} نقطة.\n\n$path'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسنًا'))],
        ),
      );
    }
  });
}
