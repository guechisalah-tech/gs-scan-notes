import 'services/text_utils.dart';

class AppException implements Exception {
  final String message;
  const AppException(this.message);
  @override
  String toString() => message;
}

class SheetInfo {
  final String name;
  final String path;
  const SheetInfo(this.name, this.path);
}

/// محتوى ورقة العمل كنصوص: صف (يبدأ من 1) -> عمود (يبدأ من 0) -> نص.
class SheetGrid {
  final Map<int, Map<int, String>> rows;
  final int maxRow;
  final int maxCol;
  const SheetGrid(this.rows, this.maxRow, this.maxCol);

  String cell(int row, int col) => rows[row]?[col] ?? '';
}

class ColumnMapping {
  int headerRow;
  int? nameCol; // اللقب أو الاسم الكامل
  int? firstNameCol; // الاسم (اختياري)
  int? idCol; // رقم التلميذ (اختياري)
  int gradeCol;
  ColumnMapping({
    this.headerRow = 1,
    this.nameCol,
    this.firstNameCol,
    this.idCol,
    this.gradeCol = 0,
  });
}

class Student {
  final int row; // رقم الصف في Excel (يبدأ من 1)
  final String id;
  final String lastName;
  final String firstName;
  final String existingGrade;
  final List<String> tokens;
  final String nameKey;

  Student._(this.row, this.id, this.lastName, this.firstName,
      this.existingGrade, this.tokens, this.nameKey);

  factory Student.create({
    required int row,
    String id = '',
    required String lastName,
    String firstName = '',
    String existingGrade = '',
  }) {
    final tokens = nameTokens('$lastName $firstName');
    final key = ([...tokens]..sort()).join(' ');
    return Student._(row, id, lastName, firstName, existingGrade, tokens, key);
  }

  String get displayName => '$lastName $firstName'.trim();
}

enum MatchStatus { confirmed, uncertain, missing }

class ExtractedRow {
  ExtractedRow({
    required this.lastName,
    required this.firstName,
    this.idText = '',
    this.gradeText = '',
    this.absent = false,
  });

  String lastName;
  String firstName;
  String idText;
  String gradeText;
  bool absent;

  Student? matched;
  MatchStatus status = MatchStatus.missing;
  String note = '';
  double score = 0;
  List<Student> candidates = const [];
  bool ignored = false;
  bool approved = false;

  double? get grade => parseGrade(gradeText);
  String get fullName => '$lastName $firstName'.trim();
  bool gradeValid(double max) {
    final g = grade;
    return g != null && g >= 0 && g <= max;
  }
}
