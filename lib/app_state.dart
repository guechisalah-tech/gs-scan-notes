import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import 'models.dart';
import 'services/image_service.dart';
import 'services/mapping_detector.dart';
import 'services/matcher.dart';
import 'services/ocr_models.dart';
import 'services/ocr_service.dart';
import 'services/table_parser.dart';
import 'services/xlsx_service.dart';

class SavePlan {
  final int toInsert;
  final int overwrites;
  final int notApproved;
  final List<String> problems;
  const SavePlan(this.toInsert, this.overwrites, this.notApproved, this.problems);
}

class AppState extends ChangeNotifier {
  // ---------- Excel ----------
  Uint8List? _xlsxBytes;
  XlsxDocument? doc;
  String fileName = '';
  SheetInfo? sheet;
  SheetGrid? grid;
  ColumnMapping mapping = ColumnMapping();
  List<Student> students = [];
  StudentMatcher? _matcher;

  // ---------- الصورة ----------
  String? originalPath;
  String? imagePath;
  bool enhance = true;
  bool gradeOnRight = true;
  double maxGrade = 20;

  // ---------- النتائج ----------
  List<ExtractedRow> rows = [];
  List<String> skipped = [];

  bool busy = false;
  String busyMessage = '';

  final OcrEngine ocrEngine = MlKitOcrEngine();
  final ImagePicker _picker = ImagePicker();

  bool get hasExcel => doc != null;
  bool get hasMapping => students.isNotEmpty;
  bool get hasImage => imagePath != null;
  bool get hasRows => rows.isNotEmpty;

  void refresh() => notifyListeners();

  void _setBusy(bool v, [String msg = '']) {
    busy = v;
    busyMessage = msg;
    notifyListeners();
  }

  // ================= استيراد Excel =================
  Future<bool> importExcel() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return false;
    final f = res.files.single;
    if (!f.name.toLowerCase().endsWith('.xlsx')) {
      throw const AppException(
          'الصيغة غير مدعومة. اختر ملفًا بامتداد .xlsx (إن كان ملفك .xls فافتحه في Excel واحفظه بصيغة xlsx).');
    }
    final bytes = f.bytes;
    if (bytes == null) throw const AppException('تعذر قراءة الملف من الهاتف.');
    _setBusy(true, 'قراءة ملف Excel…');
    try {
      final d = XlsxDocument.parse(bytes);
      _xlsxBytes = bytes;
      doc = d;
      fileName = f.name;
      rows = [];
      skipped = [];
      selectSheet(d.sheets.first);
    } finally {
      _setBusy(false);
    }
    return true;
  }

  void selectSheet(SheetInfo s) {
    sheet = s;
    grid = doc!.readSheet(s);
    mapping = MappingDetector.detect(grid!);
    rebuildStudents();
  }

  void rebuildStudents() {
    final g = grid;
    final m = mapping;
    students = [];
    if (g != null && m.nameCol != null) {
      for (var r = m.headerRow + 1; r <= g.maxRow; r++) {
        final last = g.cell(r, m.nameCol!).trim();
        final first = m.firstNameCol == null ? '' : g.cell(r, m.firstNameCol!).trim();
        final id = m.idCol == null ? '' : g.cell(r, m.idCol!).trim();
        if (last.isEmpty && first.isEmpty) continue;
        students.add(Student.create(
          row: r,
          id: id,
          lastName: last,
          firstName: first,
          existingGrade: g.cell(r, m.gradeCol).trim(),
        ));
      }
    }
    _matcher = StudentMatcher(students);
    if (rows.isNotEmpty) rematchAll();
    notifyListeners();
  }

  // ================= الصورة =================
  Future<void> pickImage(ImageSource source) async {
    XFile? x;
    try {
      x = await _picker.pickImage(source: source);
    } catch (_) {
      throw AppException(source == ImageSource.camera
          ? 'تعذر فتح الكاميرا. تحقق من الأذونات في إعدادات الهاتف.'
          : 'تعذر فتح المعرض. تحقق من الأذونات في إعدادات الهاتف.');
    }
    if (x == null) return;
    clearImage();
    originalPath = x.path;
    imagePath = x.path;
    notifyListeners();
    await cropCurrent();
  }

  /// قص/تدوير الصورة. إن ألغى الأستاذ القص تبقى الصورة الأصلية.
  Future<void> cropCurrent() async {
    final src = originalPath;
    if (src == null) return;
    final c = await ImageCropper().cropImage(
      sourcePath: src,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 95,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'قص وتدوير كشف النقاط',
          toolbarColor: const Color(0xFF00695C),
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: false,
          initAspectRatio: CropAspectRatioPreset.original,
        ),
      ],
    );
    if (c != null) {
      if (imagePath != null && imagePath != originalPath) {
        ImageService.deleteIfTemp(imagePath);
      }
      imagePath = c.path;
      notifyListeners();
    }
  }

  void clearImage() {
    if (imagePath != null && imagePath != originalPath) {
      ImageService.deleteIfTemp(imagePath);
    }
    ImageService.deleteIfTemp(originalPath);
    imagePath = null;
    originalPath = null;
  }

  // ================= الاستخراج =================
  Future<void> extract({bool append = false}) async {
    final path = imagePath;
    if (path == null) throw const AppException('اختر صورة أولًا.');
    if (students.isEmpty) {
      throw const AppException('استورد ملف Excel وحدد الأعمدة أولًا.');
    }
    _setBusy(true, 'تحسين الصورة…');
    String? prepared;
    try {
      prepared = await ImageService.prepare(path, enhance: enhance);
      busyMessage = 'التعرف على النصوص (محليًا على الهاتف)…';
      notifyListeners();
      final ocr = await ocrEngine.recognize(prepared);
      if (ocr.words.isEmpty) {
        throw const AppException(
            'لم يتم العثور على أي نص في الصورة. جرّب صورة أوضح، بإضاءة جيدة، وقصّ الجدول فقط.');
      }
      final parsed =
          TableParser(maxGrade: maxGrade, gradeOnRight: gradeOnRight).parse(ocr);
      if (parsed.rows.isEmpty) {
        throw const AppException(
            'تم التعرف على نصوص لكن لم تُستخرج أي صفوف (لقب/اسم + نقطة). تحقق من قص الصورة ومن خيار موضع عمود النقطة (يمين/يسار).');
      }
      if (!append) rows = [];
      rows.addAll(parsed.rows);
      skipped = append ? [...skipped, ...parsed.skipped] : parsed.skipped;
      _matcher!.matchAll(parsed.rows, maxGrade);
    } finally {
      ImageService.deleteIfTemp(prepared);
      _setBusy(false);
    }
  }

  // ================= المطابقة والمراجعة =================
  void rematchAll() {
    final m = _matcher;
    if (m == null) return;
    for (final r in rows) {
      if (r.ignored) continue;
      m.matchRow(r, maxGrade);
    }
    notifyListeners();
  }

  void rematchRow(ExtractedRow r) {
    _matcher?.matchRow(r, maxGrade);
    notifyListeners();
  }

  void updateRowFields(ExtractedRow r,
      {required String last, required String first, required String grade}) {
    final namesChanged = last != r.lastName || first != r.firstName;
    r.lastName = last;
    r.firstName = first;
    r.gradeText = grade;
    if (namesChanged) {
      _matcher?.matchRow(r, maxGrade);
    } else if (!r.gradeValid(maxGrade)) {
      r.approved = false;
    }
    notifyListeners();
  }

  void setStudent(ExtractedRow r, Student s) {
    r.matched = s;
    r.status = MatchStatus.confirmed;
    r.note = 'اختيار يدوي';
    r.approved = r.gradeValid(maxGrade);
    r.ignored = false;
    notifyListeners();
  }

  void setApproved(ExtractedRow r, bool v) {
    if (v && (r.matched == null || !r.gradeValid(maxGrade))) return;
    r.approved = v;
    notifyListeners();
  }

  void setIgnored(ExtractedRow r, bool v) {
    r.ignored = v;
    if (v) r.approved = false;
    notifyListeners();
  }

  void approveConfirmed() {
    for (final r in rows) {
      if (!r.ignored &&
          r.status == MatchStatus.confirmed &&
          r.matched != null &&
          r.gradeValid(maxGrade) &&
          duplicateCount(r) <= 1) {
        r.approved = true;
      }
    }
    notifyListeners();
  }

  ExtractedRow addManualRow({String last = '', String first = '', String grade = ''}) {
    final r = ExtractedRow(lastName: last, firstName: first, gradeText: grade);
    _matcher?.matchRow(r, maxGrade);
    rows.add(r);
    notifyListeners();
    return r;
  }

  /// كم صفًّا (غير متجاهل) يستهدف نفس التلميذ في Excel.
  int duplicateCount(ExtractedRow r) {
    final s = r.matched;
    if (s == null || r.ignored) return 0;
    return rows.where((o) => !o.ignored && o.matched?.row == s.row).length;
  }

  // ================= الحفظ =================
  List<ExtractedRow> get applicable => rows
      .where((r) =>
          !r.ignored && r.approved && r.matched != null && r.gradeValid(maxGrade))
      .toList();

  SavePlan buildSavePlan() {
    final app = applicable;
    final problems = <String>[];
    final seen = <int>{};
    for (final r in app) {
      if (!seen.add(r.matched!.row) || duplicateCount(r) > 1) {
        problems.add('التلميذ ${r.matched!.displayName} مستهدف بأكثر من صف. تجاهل الصف الزائد.');
      }
    }
    final overwrites =
        app.where((r) => r.matched!.existingGrade.isNotEmpty).length;
    final notApproved = rows.where((r) => !r.ignored && !app.contains(r)).length;
    return SavePlan(app.length, overwrites, notApproved, problems.toSet().toList());
  }

  /// يبني ملف Excel جديدًا ويطلب من الأستاذ اختيار مكان الحفظ.
  /// يعيد مسار الملف، أو null إن ألغى الأستاذ.
  Future<String?> saveExcel() async {
    final d = doc, s = sheet;
    if (d == null || s == null) throw const AppException('لا يوجد ملف Excel.');
    final app = applicable;
    if (app.isEmpty) throw const AppException('لا توجد نقاط معتمدة للإدراج.');
    _setBusy(true, 'إنشاء ملف Excel جديد…');
    try {
      final grades = <int, double>{
        for (final r in app) r.matched!.row: r.grade!,
      };
      final hasHeader = mapping.headerRow >= 1;
      final bytes = d.writeGrades(
        s,
        grades,
        mapping.gradeCol,
        headerRow: hasHeader ? mapping.headerRow : null,
        headerText: hasHeader ? 'Note' : null,
      );
      busyMessage = 'اختر مكان الحفظ…';
      notifyListeners();
      return await FilePicker.platform.saveFile(
        dialogTitle: 'اختر مكان حفظ الملف',
        fileName: 'Notes_Importees_${DateTime.now().year}.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
    } finally {
      _setBusy(false);
    }
  }

  // ================= إعادة التهيئة =================
  void resetAll() {
    clearImage();
    rows = [];
    skipped = [];
    doc = null;
    _xlsxBytes = null;
    sheet = null;
    grid = null;
    students = [];
    _matcher = null;
    fileName = '';
    mapping = ColumnMapping();
    notifyListeners();
  }

  void wipeResults() {
    rows = [];
    skipped = [];
    clearImage();
    notifyListeners();
  }

  @override
  void dispose() {
    clearImage();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
