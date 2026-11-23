import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'common.dart';

/// تحديد ورقة العمل وسطر العناوين والأعمدة (اللقب، الاسم، الرقم، عمود النقاط).
class MappingScreen extends StatelessWidget {
  const MappingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final g = s.grid;
    if (g == null || s.doc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('إعداد الأعمدة')),
        body: const Center(child: Text('استورد ملف Excel أولًا')),
      );
    }
    final m = s.mapping;
    final hr = m.headerRow;
    String head(int c) => g.cell(hr, c);

    final colOpts = <Option<int?>>[
      for (var c = 0; c <= g.maxCol; c++) Option<int?>(c, colLabel(c, head(c))),
    ];
    final optionalCols = <Option<int?>>[const Option<int?>(null, '— بدون —'), ...colOpts];
    final nameCols = colOpts;
    final gradeOpts = <Option<int>>[
      for (var c = 0; c <= g.maxCol; c++) Option<int>(c, colLabel(c, head(c))),
      Option<int>(g.maxCol + 1, '${colLetters2(g.maxCol + 1)} — عمود جديد (سيُنشأ)'),
    ];
    final rowOpts = <Option<int>>[
      for (var r = 1; r <= math.max(1, math.min(g.maxRow, 30)); r++)
        Option<int>(r, 'السطر $r'),
    ];

    final preview = s.students.take(4).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('إعداد الأعمدة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.fileName, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          PickerField<String>(
            label: 'ورقة العمل (Sheet)',
            options: [for (final sh in s.doc!.sheets) Option<String>(sh.name, sh.name)],
            selected: s.sheet!.name,
            onChanged: (v) => s.selectSheet(s.doc!.sheets.firstWhere((e) => e.name == v)),
          ),
          PickerField<int>(
            label: 'سطر العناوين',
            options: rowOpts,
            selected: hr,
            onChanged: (v) {
              m.headerRow = v;
              s.rebuildStudents();
            },
          ),
          PickerField<int?>(
            label: 'عمود اللقب (أو الاسم الكامل) *',
            options: nameCols,
            selected: m.nameCol,
            onChanged: (v) {
              m.nameCol = v;
              s.rebuildStudents();
            },
          ),
          PickerField<int?>(
            label: 'عمود الاسم (اختياري إن كان منفصلًا)',
            options: optionalCols,
            selected: m.firstNameCol,
            onChanged: (v) {
              m.firstNameCol = v;
              s.rebuildStudents();
            },
          ),
          PickerField<int?>(
            label: 'عمود رقم التلميذ / المعرّف (اختياري)',
            options: optionalCols,
            selected: m.idCol,
            onChanged: (v) {
              m.idCol = v;
              s.rebuildStudents();
            },
          ),
          PickerField<int>(
            label: 'عمود إدراج النقاط *',
            options: gradeOpts,
            selected: m.gradeCol,
            onChanged: (v) {
              m.gradeCol = v;
              s.rebuildStudents();
            },
          ),
          const SizedBox(height: 8),
          Card(
            color: Colors.teal.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('عدد التلاميذ المقروءين: ${s.students.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if (preview.isEmpty)
                    const Text('لم يُعثر على تلاميذ: تحقق من سطر العناوين وعمود اللقب.',
                        style: TextStyle(color: Colors.red)),
                  for (final st in preview)
                    Text(
                        '• ${st.displayName}${st.id.isEmpty ? '' : '  [${st.id}]'}'
                        '${st.existingGrade.isEmpty ? '' : '  (نقطة حالية: ${st.existingGrade})'}'),
                  if (m.gradeCol > g.maxCol)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('سيُنشأ عمود جديد باسم "Note" لإدراج النقاط.'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('اعتماد الإعداد'),
            onPressed: () {
              if (m.nameCol == null || s.students.isEmpty) {
                showToast(context, 'حدّد عمود اللقب/الاسم بشكل صحيح أولًا', error: true);
                return;
              }
              if (m.gradeCol == m.nameCol ||
                  m.gradeCol == m.firstNameCol ||
                  m.gradeCol == m.idCol) {
                showToast(context, 'عمود النقاط لا يجوز أن يكون نفس عمود الاسم أو الرقم', error: true);
                return;
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

String colLetters2(int c) {
  var n = c + 1;
  final codes = <int>[];
  while (n > 0) {
    final r = (n - 1) % 26;
    codes.insert(0, 65 + r);
    n = (n - 1) ~/ 26;
  }
  return String.fromCharCodes(codes);
}
