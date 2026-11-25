import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/text_utils.dart';
import 'common.dart';
import 'review_screen.dart';

/// إدخال النقاط يدويًا: قائمة تلاميذ الملف وحقل نقطة أمام كل اسم، ثم مراجعة وحفظ.
class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  final Map<int, TextEditingController> _c = {};
  String q = '';

  TextEditingController _ctl(Student s) =>
      _c.putIfAbsent(s.row, () => TextEditingController());

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final nq = normalizeName(q);
    final list = s.students
        .where((st) =>
            nq.isEmpty ||
            normalizeName(st.displayName).contains(nq) ||
            st.id.contains(q.trim()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('إدخال النقاط يدويًا')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'بحث بالاسم أو الرقم',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final st = list[i];
                return ListTile(
                  title: Text(st.displayName),
                  subtitle: Text([
                    if (st.id.isNotEmpty) st.id,
                    if (st.existingGrade.isNotEmpty) 'نقطة حالية: ${st.existingGrade}',
                  ].join(' • ')),
                  trailing: SizedBox(
                    width: 84,
                    child: TextField(
                      controller: _ctl(st),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: '—',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.fact_check),
                  label: const Text('إضافة إلى المراجعة'),
                  onPressed: () => _submit(context, s),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _submit(BuildContext context, AppState s) {
    final entries = <Student, String>{};
    final bad = <String>[];
    for (final st in s.students) {
      final t = _c[st.row]?.text.trim() ?? '';
      if (t.isEmpty) continue;
      final g = parseGrade(t);
      if (g == null || g < 0 || g > s.maxGrade) {
        bad.add(st.displayName);
      } else {
        entries[st] = t;
      }
    }
    if (bad.isNotEmpty) {
      showToast(context, 'نقطة غير صالحة عند: ${bad.take(3).join('، ')}', error: true);
      return;
    }
    if (entries.isEmpty) {
      showToast(context, 'لم تُدخل أي نقطة بعد', error: true);
      return;
    }
    s.addManualGrades(entries);
    Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const ReviewScreen()));
  }
}
