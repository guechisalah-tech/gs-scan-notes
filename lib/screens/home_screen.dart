import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../services/table_parser.dart';
import 'common.dart';
import 'manual_entry_screen.dart';
import 'mapping_screen.dart';
import 'review_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final busy = s.busy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GS Scan Notes'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'جلسة جديدة (مسح كل شيء)',
            icon: const Icon(Icons.restart_alt),
            onPressed: busy ? null : () => _reset(context, s),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _Step(
                n: 1,
                icon: Icons.upload_file,
                title: 'استيراد ملف Excel',
                subtitle: s.hasExcel
                    ? '${s.fileName} • ${s.students.length} تلميذ • عمود النقاط: ${_gradeColName(s)}'
                    : 'اختر ملف .xlsx يحتوي على قائمة التلاميذ',
                done: s.hasMapping,
                enabled: !busy,
                onTap: () => runGuarded(context, () async {
                  final ok = await s.importExcel();
                  if (ok && context.mounted) {
                    await Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const MappingScreen()));
                  }
                }),
                trailing: s.hasExcel
                    ? IconButton(
                        tooltip: 'إعداد الأعمدة',
                        icon: const Icon(Icons.tune),
                        onPressed: busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(builder: (_) => const MappingScreen())),
                      )
                    : null,
              ),
              _Step(
                n: 2,
                icon: Icons.photo_camera,
                title: 'تصوير كشف النقاط',
                subtitle: 'التقط صورة للجدول ثم قصّه وعدّل دورانه',
                done: false,
                enabled: !busy,
                onTap: () => runGuarded(context, () => s.pickImage(ImageSource.camera)),
              ),
              _Step(
                n: 3,
                icon: Icons.photo_library,
                title: 'اختيار صورة من الهاتف',
                subtitle: s.hasImage ? 'تم اختيار صورة ✔ (اضغط لاختيار أخرى)' : 'اختر صورة موجودة في المعرض',
                done: s.hasImage,
                enabled: !busy,
                onTap: () => runGuarded(context, () => s.pickImage(ImageSource.gallery)),
              ),
              if (s.hasImage) _ImageCard(s: s),
              _OptionsCard(s: s),
              _Step(
                n: 0,
                icon: Icons.keyboard,
                title: 'إدخال النقاط يدويًا (بدون صورة)',
                subtitle: s.hasMapping
                    ? 'قائمة تلاميذ ملفك: اكتب النقطة أمام كل اسم'
                    : 'يتطلب أولًا استيراد Excel وتحديد الأعمدة',
                done: false,
                enabled: !busy && s.hasMapping,
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const ManualEntryScreen())),
              ),
              _Step(
                n: 4,
                icon: Icons.document_scanner,
                title: 'استخراج النقاط',
                subtitle: !s.hasMapping
                    ? 'يتطلب أولًا استيراد Excel وتحديد الأعمدة'
                    : !s.hasImage
                        ? 'يتطلب أولًا اختيار صورة'
                        : s.hasRows
                            ? 'تم استخراج ${s.rows.length} صف'
                            : 'تشغيل التعرف الضوئي محليًا على الهاتف',
                done: s.hasRows,
                enabled: !busy && s.hasMapping && s.hasImage,
                onTap: () => runGuarded(context, () => _extract(context, s)),
              ),
              _Step(
                n: 5,
                icon: Icons.fact_check,
                title: 'مراجعة ومطابقة التلاميذ',
                subtitle: s.hasRows
                    ? 'صحّح الأخطاء واعتمد المطابقات قبل الإدراج'
                    : 'متاح بعد استخراج النقاط',
                done: s.applicable.isNotEmpty,
                enabled: !busy && s.hasRows,
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const ReviewScreen())),
              ),
              _Step(
                n: 6,
                icon: Icons.save_alt,
                title: 'حفظ ملف Excel',
                subtitle: s.hasRows
                    ? 'نقاط معتمدة: ${s.applicable.length} • يُحفظ كنسخة جديدة'
                    : 'متاح بعد المراجعة',
                done: false,
                enabled: !busy && s.hasRows,
                onTap: () => confirmAndSave(context, s),
              ),
              const SizedBox(height: 8),
              const Text(
                'الخصوصية: كل المعالجة تتم على هاتفك دون إنترنت. لا تُرسل أي بيانات، '
                'ولا يُحفظ شيء من الصور بعد إنهاء الجلسة.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
          if (busy)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(s.busyMessage),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _gradeColName(AppState s) {
    final g = s.grid;
    if (g == null) return '';
    final h = g.cell(s.mapping.headerRow, s.mapping.gradeCol).trim();
    return h.isEmpty ? 'جديد' : h;
  }

  Future<void> _extract(BuildContext context, AppState s) async {
    var append = false;
    if (s.hasRows) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('توجد نتائج سابقة'),
          content: const Text('هل تريد استبدال النتائج الحالية أم إضافة نتائج هذه الصورة إليها؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'append'), child: const Text('إضافة')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('استبدال')),
          ],
        ),
      );
      if (choice == null) return;
      append = choice == 'append';
    }
    await s.extract(append: append);
    final p = s.pending;
    if (p == null || !context.mounted) return;
    int? col;
    if (p.columns.length == 1) {
      col = 0;
    } else if (p.columns.length > 1) {
      col = await showColumnPicker(context, p);
      if (col == null) {
        s.pending = null;
        return;
      }
    }
    s.commitPending(col);
    if (context.mounted && s.hasRows) {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const ReviewScreen()));
    }
  }

  Future<void> _reset(BuildContext context, AppState s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بدء جلسة جديدة؟'),
        content: const Text('سيتم مسح الصورة والنتائج وإعدادات الملف من التطبيق (الملفات الأصلية في هاتفك لا تُحذف).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مسح')),
        ],
      ),
    );
    if (ok == true) s.resetAll();
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.enabled,
    required this.onTap,
    this.trailing,
  });
  final int n;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final bool enabled;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: done ? Colors.green : Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  child: done ? const Icon(Icons.check) : (n == 0 ? Icon(icon) : Text('$n')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                    ],
                  ),
                ),
                if (trailing != null) trailing! else Icon(icon, color: Colors.teal),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({required this.s});
  final AppState s;
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(s.imagePath!),
                  key: ValueKey(s.imagePath), height: 180, fit: BoxFit.contain),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.crop_rotate),
                  label: const Text('قص / تدوير'),
                  onPressed: s.busy ? null : () => runGuarded(context, s.cropCurrent),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('إزالة الصورة'),
                  onPressed: s.busy
                      ? null
                      : () {
                          s.clearImage();
                          s.refresh();
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionsCard extends StatelessWidget {
  const _OptionsCard({required this.s});
  final AppState s;
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('خيارات الاستخراج', style: TextStyle(fontWeight: FontWeight.bold)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تحسين وضوح الصورة تلقائيًا', style: TextStyle(fontSize: 14)),
              value: s.enhance,
              onChanged: (v) {
                s.enhance = v;
                s.refresh();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('المطابقة برقم التلميذ فقط', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                  'للجداول العربية: تُتجاهل الأسماء ويُعتمد رقم التعريف (مفعّل تلقائيًا إن كانت أسماء ملفك عربية)',
                  style: TextStyle(fontSize: 11)),
              value: s.idOnly,
              onChanged: (v) => s.setIdOnly(v),
            ),
            const Text('العمود المقترح تلقائيًا إن وُجدت عدة أعمدة أرقام', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('أقصى اليمين')),
                ButtonSegment(value: false, label: Text('أقصى اليسار')),
              ],
              selected: {s.gradeOnRight},
              onSelectionChanged: (v) {
                s.gradeOnRight = v.first;
                s.refresh();
              },
            ),
            const SizedBox(height: 10),
            PickerField<double>(
              label: 'الحد الأقصى للنقطة',
              options: const [
                Option(10.0, '10'),
                Option(20.0, '20'),
                Option(40.0, '40'),
                Option(100.0, '100'),
              ],
              selected: s.maxGrade,
              onChanged: (v) {
                s.maxGrade = v;
                s.refresh();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// عدة أعمدة أرقام في الصورة (نشاطات، فرض، اختبار...): الأستاذ يختار العمود المطلوب.
Future<int?> showColumnPicker(BuildContext context, ParsedTable p) {
  final n = p.columns.length;
  return showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('أي عمود يحتوي النقاط المطلوبة؟'),
      children: [
        for (var i = 0; i < n; i++)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, i),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i == 0 ? 'أقصى يسار الصورة' : i == n - 1 ? 'أقصى يمين الصورة' : 'وسط الجدول'}'
                  ' — ${p.columns[i].count} قيمة',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(p.columns[i].samples().join('  •  '),
                    style: const TextStyle(fontSize: 13), textDirection: TextDirection.ltr),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Text('الأعمدة مرتبة من يسار الصورة إلى يمينها. اختر العمود الذي تقرأ منه القيم الصحيحة.',
              style: TextStyle(fontSize: 11, color: Colors.black54)),
        ),
      ],
    ),
  );
}
