import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class DishSearchResult {
  const DishSearchResult({
    required this.id,
    required this.name,
    required this.type,
    required this.calories,
  });

  final String id;
  final String name;
  final String type;
  final double? calories;

  bool get isDish => type == 'dish';
  String get unitLabel => isDish ? '1份' : '100克';

  factory DishSearchResult.fromJson(Map<String, dynamic> json) {
    final caloriesData = json['calories'];
    final caloriesValue = caloriesData is Map<String, dynamic>
        ? caloriesData['value']
        : caloriesData;

    return DishSearchResult(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      calories: caloriesValue is num
          ? caloriesValue.toDouble()
          : double.tryParse(caloriesValue?.toString() ?? ''),
    );
  }
}

class DishSearchService {
  Future<List<DishSearchResult>> search(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return const [];

    final baseUri = Uri.parse(
      '${ApiConfig.nutritionistBaseUrl}/nutritionist-agent/dishes/search',
    );
    final uri = baseUri.replace(
      queryParameters: {'q': trimmedQuery, 'limit': '20'},
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
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
