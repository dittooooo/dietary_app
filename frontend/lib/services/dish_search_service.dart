import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class DishSearchResult {
  const DishSearchResult({
    required this.id,
    required this.name,
    required this.type,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbohydrates,
  });

  final String id;
  final String name;
  final String type;
  final double? calories;
  final double? protein;
  final double? fat;
  final double? carbohydrates;

  bool get isDish => type == 'dish';
  String get unitLabel => isDish ? '1份' : '100克';

  factory DishSearchResult.fromJson(Map<String, dynamic> json) {
    double? parseNumber(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    }

    double? parseNutritionValue(dynamic value) {
      if (value is Map<String, dynamic>) {
        return parseNumber(value['value'] ?? value['amount']);
      }
      return parseNumber(value);
    }

    final macronutrients = json['macronutrients'] is Map
        ? Map<String, dynamic>.from(json['macronutrients'] as Map)
        : const <String, dynamic>{};
    final nutrition = json['nutrition'] is Map
        ? Map<String, dynamic>.from(json['nutrition'] as Map)
        : const <String, dynamic>{};

    return DishSearchResult(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      calories: parseNutritionValue(json['calories'] ?? nutrition['calories']),
      protein: parseNutritionValue(
        json['protein'] ?? nutrition['protein'] ?? macronutrients['protein_g'],
      ),
      fat: parseNutritionValue(
        json['fat'] ?? nutrition['fat'] ?? macronutrients['fat_g'],
      ),
      carbohydrates: parseNutritionValue(
        json['carbohydrates'] ??
            json['carbs'] ??
            nutrition['carbohydrates'] ??
            nutrition['carbs'] ??
            macronutrients['carbohydrates_g'] ??
            macronutrients['carbs_g'],
      ),
    );
  }
}

class DishSearchService {
  Future<List<DishSearchResult>> search(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return const [];

    http.Response? response;
    for (final baseUrl in ApiConfig.nutritionistCandidateBaseUrls) {
      final baseUri = Uri.parse(
        '$baseUrl/nutritionist-agent/dishes/search',
      );
      final uri = baseUri.replace(
        queryParameters: {'q': trimmedQuery, 'limit': '20'},
      );

      try {
        response = await http.get(uri).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          break;
        }
      } catch (_) {
        response = null;
      }
    }

    if (response == null || response.statusCode != 200) {
      throw Exception('Food search service is unavailable');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['results'] is! List) {
      throw Exception('Food search response has an invalid format');
    }

    return (decoded['results'] as List)
        .whereType<Map>()
        .map((item) => DishSearchResult.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
        .take(20)
        .toList();
  }
}
