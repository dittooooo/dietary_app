class BodyStatusModel {
  final int bodyScore;
  final int muscleScore;
  final String bodyType;
  final double? bmr;
  final double? tdee;
  final double? recommendedCalories;
  final double? recommendedProtein;
  final DateTime? lastSettleDate;

  const BodyStatusModel({
    required this.bodyScore,
    required this.muscleScore,
    required this.bodyType,
    this.bmr,
    this.tdee,
    this.recommendedCalories,
    this.recommendedProtein,
    this.lastSettleDate,
  });

  factory BodyStatusModel.fromJson(Map<String, dynamic> json) {
    return BodyStatusModel(
      bodyScore: _asInt(json['bodyScore'], fallback: 50),
      muscleScore: _asInt(json['muscleScore'], fallback: 50),
      bodyType: _asString(json['bodyType'], fallback: 'NORMAL'),
      bmr: _asDouble(json['bmr']),
      tdee: _asDouble(json['tdee']),
      recommendedCalories: _asDouble(json['recommendedCalories']),
      recommendedProtein: _asDouble(json['recommendedProtein']),
      lastSettleDate: _asDate(json['lastSettleDate']),
    );
  }
}

class SettlementResponse {
  final bool settled;
  final DateTime? lastSettleDate;
  final int bodyScore;
  final int muscleScore;
  final String bodyType;
  final String oldBodyType;
  final String newBodyType;
  final bool bodyTypeChanged;
  final int bodyScoreChange;
  final int muscleScoreChange;
  final double? recommendedCalories;
  final double? totalCalories;
  final double? recommendedProtein;
  final double? totalProtein;
  final List<DailySettlementResult> results;

  const SettlementResponse({
    required this.settled,
    required this.lastSettleDate,
    required this.bodyScore,
    required this.muscleScore,
    required this.bodyType,
    required this.oldBodyType,
    required this.newBodyType,
    required this.bodyTypeChanged,
    required this.bodyScoreChange,
    required this.muscleScoreChange,
    required this.recommendedCalories,
    required this.totalCalories,
    required this.recommendedProtein,
    required this.totalProtein,
    required this.results,
  });

  factory SettlementResponse.fromJson(Map<String, dynamic> json) {
    final bodyType = _asString(json['bodyType'], fallback: 'NORMAL');
    final newBodyType = _asString(json['newBodyType'], fallback: bodyType);

    return SettlementResponse(
      settled: _asBool(json['settled']),
      lastSettleDate: _asDate(json['lastSettleDate']),
      bodyScore: _asInt(json['bodyScore'], fallback: 50),
      muscleScore: _asInt(json['muscleScore'], fallback: 50),
      bodyType: bodyType,
      oldBodyType: _asString(json['oldBodyType'], fallback: newBodyType),
      newBodyType: newBodyType,
      bodyTypeChanged: _asBool(json['bodyTypeChanged']),
      bodyScoreChange: _asInt(json['bodyScoreChange']),
      muscleScoreChange: _asInt(json['muscleScoreChange']),
      recommendedCalories: _asDouble(json['recommendedCalories']),
      totalCalories: _asDouble(json['totalCalories']),
      recommendedProtein: _asDouble(json['recommendedProtein']),
      totalProtein: _asDouble(json['totalProtein']),
      results: (json['results'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(DailySettlementResult.fromJson)
          .toList(),
    );
  }
}

class DailySettlementResult {
  final bool settled;
  final DateTime? recordDate;
  final String oldBodyType;
  final String newBodyType;
  final bool bodyTypeChanged;
  final int bodyScore;
  final int muscleScore;
  final int bodyScoreChange;
  final int muscleScoreChange;
  final double? recommendedCalories;
  final double? totalCalories;
  final double? recommendedProtein;
  final double? totalProtein;

  const DailySettlementResult({
    required this.settled,
    required this.recordDate,
    required this.oldBodyType,
    required this.newBodyType,
    required this.bodyTypeChanged,
    required this.bodyScore,
    required this.muscleScore,
    required this.bodyScoreChange,
    required this.muscleScoreChange,
    required this.recommendedCalories,
    required this.totalCalories,
    required this.recommendedProtein,
    required this.totalProtein,
  });

  factory DailySettlementResult.fromJson(Map<String, dynamic> json) {
    return DailySettlementResult(
      settled: _asBool(json['settled']),
      recordDate: _asDate(json['recordDate']),
      oldBodyType: _asString(json['oldBodyType'], fallback: 'NORMAL'),
      newBodyType: _asString(json['newBodyType'], fallback: 'NORMAL'),
      bodyTypeChanged: _asBool(json['bodyTypeChanged']),
      bodyScore: _asInt(json['bodyScore'], fallback: 50),
      muscleScore: _asInt(json['muscleScore'], fallback: 50),
      bodyScoreChange: _asInt(json['bodyScoreChange']),
      muscleScoreChange: _asInt(json['muscleScoreChange']),
      recommendedCalories: _asDouble(json['recommendedCalories']),
      totalCalories: _asDouble(json['totalCalories']),
      recommendedProtein: _asDouble(json['recommendedProtein']),
      totalProtein: _asDouble(json['totalProtein']),
    );
  }
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? fallback;
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  return '${value ?? ''}'.toLowerCase() == 'true';
}

String _asString(dynamic value, {required String fallback}) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
  return text;
}

DateTime? _asDate(dynamic value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return DateTime.tryParse(text);
}
