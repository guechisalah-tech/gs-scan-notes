import 'package:flutter/material.dart';

import '../models.dart';
import '../services/text_utils.dart';

void showToast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
      duration: Duration(seconds: error ? 6 : 3),
    ));
}

Future<void> runGuarded(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on AppException catch (e) {
    if (context.mounted) showToast(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) showToast(context, 'حدث خطأ غير متوقع: $e', error: true);
  }
}

class Option<T> {
  final T value;
  final String label;
  const Option(this.value, this.label);
}

/// حقل اختيار بسيط (يتجنب DropdownButtonFormField لثبات الواجهة عبر إصدارات Flutter).
class PickerField<T> extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<Option<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    String current = '';
    for (final o in options) {
      if (o.value == selected) current = o.label;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(label, style: const TextStyle(fontSize: 13)),
        subtitle: Text(current,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.arrow_drop_down),
        onTap: () async {
          final r = await showModalBottomSheet<Option<T>>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.7),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(label,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    for (final o in options)
                      ListTile(
                        title: Text(o.label),
                        trailing: o.value == selected
                            ? const Icon(Icons.check, color: Colors.teal)
                            : null,
                        onTap: () => Navigator.pop(ctx, o),
                      ),
                  ],
                ),
              ),
            ),
          );
          if (r != null) onChanged(r.value);
        },
      ),
    );
  }
}

/// اختيار تلميذ يدويًا مع بحث. الاقتراحات (المرشحون) تظهر أولًا.
Future<Student?> showStudentPicker(
    BuildContext context, List<Student> all, List<Student> suggestions) {
  return showModalBottomSheet<Student>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _StudentPicker(all: all, suggestions: suggestions),
  );
}

class _StudentPicker extends StatefulWidget {
  const _StudentPicker({required this.all, required this.suggestions});
  final List<Student> all;
  final List<Student> suggestions;

  @override
  State<_StudentPicker> createState() => _StudentPickerState();
}

class _StudentPickerState extends State<_StudentPicker> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final nq = normalizeName(q);
    final list = <Student>[
      if (nq.isEmpty) ...widget.suggestions,
      ...widget.all.where((s) =>
          (nq.isEmpty && !widget.suggestions.contains(s)) ||
          (nq.isNotEmpty &&
              (normalizeName(s.displayName).contains(nq) ||
                  s.id.contains(q.trim())))),
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'ابحث بالاسم أو الرقم',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => q = v),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final s = list[i];
                    final isSug = nq.isEmpty && widget.suggestions.contains(s);
                    return ListTile(
                      leading: isSug ? const Icon(Icons.star, color: Colors.orange) : null,
                      title: Text(s.displayName),
                      subtitle: Text([
                        if (s.id.isNotEmpty) 'الرقم: ${s.id}',
                        'السطر ${s.row}',
                        if (s.existingGrade.isNotEmpty) 'نقطة حالية: ${s.existingGrade}',
                      ].join(' • ')),
                      onTap: () => Navigator.pop(ctx, s),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String colLabel(int c, String header) {
  final h = header.trim();
  final short = h.length > 22 ? '${h.substring(0, 22)}…' : h;
  return '${colLetters(c)} — ${short.isEmpty ? '(فارغ)' : short}';
}
