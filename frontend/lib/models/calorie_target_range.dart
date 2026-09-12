enum CalorieIntakeLevel { low, suitable, high }

/// 將後端回傳的每日建議熱量轉成前端顯示所需的判斷區間。
class CalorieTargetRange {
  static const double tolerance = 300;
  static const double _lowSegmentEnd = 0.38;
  static const double _suitableSegmentEnd = 0.72;

  final double recommendedCalories;

  const CalorieTargetRange._(this.recommendedCalories);

  static CalorieTargetRange? tryParse(dynamic value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
    return CalorieTargetRange._(parsed);
  }

  double get lowerBound =>
      (recommendedCalories - tolerance).clamp(0, double.infinity);

  double get upperBound => recommendedCalories + tolerance;

  CalorieIntakeLevel levelFor(double currentCalories) {
    if (currentCalories <= lowerBound) return CalorieIntakeLevel.low;
    if (currentCalories >= upperBound) return CalorieIntakeLevel.high;
    return CalorieIntakeLevel.suitable;
  }

  /// 將個人化區間映射到既有儀表板的三段弧線。
  double gaugeProgressFor(double currentCalories) {
    final calories = currentCalories.clamp(0, double.infinity).toDouble();
    if (calories <= lowerBound) {
      if (lowerBound == 0) return 0;
      return (calories / lowerBound).clamp(0.0, 1.0) * _lowSegmentEnd;
    }

    if (calories < upperBound) {
      final suitableProgress =
          ((calories - lowerBound) / (upperBound - lowerBound)).clamp(0.0, 1.0);
      return _lowSegmentEnd +
          suitableProgress * (_suitableSegmentEnd - _lowSegmentEnd);
    }

    final highVisualEnd =
        upperBound +
        (recommendedCalories * 0.5).clamp(tolerance, double.infinity);
    final highProgress =
        ((calories - upperBound) / (highVisualEnd - upperBound)).clamp(
          0.0,
          1.0,
        );
    return _suitableSegmentEnd + highProgress * (1 - _suitableSegmentEnd);
  }

  String get lowLabel => '≤ ${_formatCalories(lowerBound)} kcal';
  String get suitableLabel => '目標 ${_formatCalories(recommendedCalories)} kcal';
  String get highLabel => '≥ ${_formatCalories(upperBound)} kcal';

  static String _formatCalories(double value) {
    return value.round().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
  }
}
