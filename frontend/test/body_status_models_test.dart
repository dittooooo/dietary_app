import 'package:flutter_test/flutter_test.dart';
import 'package:my_project/models/body_status_models.dart';

void main() {
  group('BodyStatusModel', () {
    test('parses backend response fields', () {
      final model = BodyStatusModel.fromJson({
        'bodyScore': 62,
        'muscleScore': 58,
        'bodyType': 'NORMAL',
        'bmr': 1650.0,
        'tdee': 2268.75,
        'recommendedCalories': 2268.75,
        'recommendedProtein': 84.0,
        'lastSettleDate': '2026-07-25',
      });

      expect(model.bodyScore, 62);
      expect(model.muscleScore, 58);
      expect(model.bodyType, 'NORMAL');
      expect(model.recommendedCalories, 2268.75);
      expect(model.lastSettleDate, DateTime(2026, 7, 25));
    });

    test('uses safe defaults when optional JSON fields are missing', () {
      final model = BodyStatusModel.fromJson({});

      expect(model.bodyScore, 50);
      expect(model.muscleScore, 50);
      expect(model.bodyType, 'NORMAL');
      expect(model.recommendedCalories, isNull);
    });
  });

  group('SettlementResponse', () {
    test('parses body type change and daily results', () {
      final response = SettlementResponse.fromJson({
        'settled': true,
        'lastSettleDate': '2026-07-25',
        'bodyScore': 70,
        'muscleScore': 58,
        'bodyType': 'FAT',
        'oldBodyType': 'NORMAL',
        'newBodyType': 'FAT',
        'bodyTypeChanged': true,
        'bodyScoreChange': 10,
        'muscleScoreChange': 3,
        'recommendedCalories': 2200.0,
        'totalCalories': 2950.0,
        'recommendedProtein': 84.0,
        'totalProtein': 76.0,
        'results': [
          {
            'settled': true,
            'recordDate': '2026-07-25',
            'oldBodyType': 'NORMAL',
            'newBodyType': 'FAT',
            'bodyTypeChanged': true,
            'bodyScore': 70,
            'muscleScore': 58,
            'bodyScoreChange': 10,
            'muscleScoreChange': 3,
            'recommendedCalories': 2200.0,
            'totalCalories': 2950.0,
            'recommendedProtein': 84.0,
            'totalProtein': 76.0,
          }
        ],
      });

      expect(response.settled, isTrue);
      expect(response.bodyTypeChanged, isTrue);
      expect(response.oldBodyType, 'NORMAL');
      expect(response.newBodyType, 'FAT');
      expect(response.bodyScoreChange, 10);
      expect(response.results, hasLength(1));
      expect(response.results.single.recordDate, DateTime(2026, 7, 25));
    });

    test('does not require change fields when no settlement happened', () {
      final response = SettlementResponse.fromJson({
        'settled': false,
        'bodyScore': 50,
        'muscleScore': 50,
        'bodyType': 'NORMAL',
        'bodyTypeChanged': false,
      });

      expect(response.settled, isFalse);
      expect(response.bodyTypeChanged, isFalse);
      expect(response.oldBodyType, 'NORMAL');
      expect(response.newBodyType, 'NORMAL');
      expect(response.results, isEmpty);
    });
  });
}
