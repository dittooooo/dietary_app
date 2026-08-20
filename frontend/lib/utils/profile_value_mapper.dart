class ProfileValueMapper {
  static const String defaultDietGoalApi = 'MAINTAIN';
  static const String defaultDietGoalDisplay = '養生';
  static const String defaultPetTypeApi = 'DOG';
  static const String defaultPetTypeDisplay = '狗兒';

  static String dietGoalToApi(String? value) {
    final normalized = (value ?? '').trim();
    final upper = normalized.toUpperCase();

    if (upper == 'LOSE_WEIGHT' ||
        normalized.contains('減脂') ||
        normalized.contains('減重')) {
      return 'LOSE_WEIGHT';
    }
    if (upper == 'GAIN_MUSCLE' || normalized.contains('增肌')) {
      return 'GAIN_MUSCLE';
    }
    if (upper == 'MAINTAIN' ||
        normalized.contains('養生') ||
        normalized.contains('維持') ||
        normalized.contains('健康')) {
      return 'MAINTAIN';
    }

    return defaultDietGoalApi;
  }

  static String dietGoalToDisplay(String? value) {
    final normalized = (value ?? '').trim();
    final upper = normalized.toUpperCase();

    if (upper == 'LOSE_WEIGHT' ||
        normalized.contains('減脂') ||
        normalized.contains('減重')) {
      return '減脂';
    }
    if (upper == 'GAIN_MUSCLE' || normalized.contains('增肌')) {
      return '增肌';
    }
    if (upper == 'MAINTAIN' ||
        normalized.contains('養生') ||
        normalized.contains('維持') ||
        normalized.contains('健康')) {
      return '養生';
    }

    return defaultDietGoalDisplay;
  }

  static String petTypeToApi(String? value) {
    final normalized = (value ?? '').trim();
    final upper = normalized.toUpperCase();

    if (upper == 'CAT' || normalized.contains('貓')) {
      return 'CAT';
    }
    if (upper == 'DOG' ||
        normalized.contains('狗') ||
        normalized.contains('奶油皮丘')) {
      return 'DOG';
    }

    return defaultPetTypeApi;
  }

  static String petTypeToDisplay(String? value) {
    final normalized = (value ?? '').trim();
    final upper = normalized.toUpperCase();

    if (upper == 'CAT' || normalized.contains('貓')) {
      return '貓兒';
    }
    if (upper == 'DOG' ||
        normalized.contains('狗') ||
        normalized.contains('奶油皮丘')) {
      return defaultPetTypeDisplay;
    }

    return defaultPetTypeDisplay;
  }

  static String genderToApi(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized == '女' || normalized.toUpperCase() == 'FEMALE') {
      return 'FEMALE';
    }
    return 'MALE';
  }

  static String healthConditionToApi(String? value) {
    final normalized = (value ?? '').trim();
    final upper = normalized.toUpperCase();

    if (upper == 'HYPERTENSION' || normalized.contains('高血壓')) return 'HYPERTENSION';
    if (upper == 'HYPERLIPIDEMIA' || normalized.contains('高血脂')) return 'HYPERLIPIDEMIA';
    if (upper == 'DIABETES' || normalized.contains('糖尿')) return 'DIABETES';
    if (upper == 'CARDIOVASCULAR' || normalized.contains('心血管')) return 'CARDIOVASCULAR';
    if (upper == 'KIDNEY_DISEASE' || normalized.contains('腎臟')) return 'KIDNEY_DISEASE';
    if (upper == 'STROKE' || normalized.contains('中風')) return 'STROKE';
    if (upper == 'METABOLIC_SYNDROME' || normalized.contains('代謝症候群')) return 'METABOLIC_SYNDROME';
    if (upper == 'GOUT' || normalized.contains('痛風')) return 'GOUT';
    if (upper == 'HYPERURICEMIA' || normalized.contains('高尿酸')) return 'HYPERURICEMIA';
    if (upper == 'GERD' || normalized.contains('胃食道逆流')) return 'GERD';
    if (upper == 'NONE' ||
        normalized == '無' ||
        normalized.contains('無特殊疾病') ||
        normalized.contains('無疾病') ||
        normalized.toLowerCase() == 'none') {
      return 'NONE';
    }

    return upper.isNotEmpty ? upper : 'NONE';
  }

  static String healthConditionToDisplay(String? value) {
    final normalized = (value ?? '').trim();
    final upper = normalized.toUpperCase();

    if (upper == 'HYPERTENSION' || normalized.contains('高血壓')) return '高血壓';
    if (upper == 'HYPERLIPIDEMIA' || normalized.contains('高血脂')) return '高血脂';
    if (upper == 'DIABETES' || normalized.contains('糖尿')) return '糖尿病';
    if (upper == 'CARDIOVASCULAR' || normalized.contains('心血管')) return '心血管疾病';
    if (upper == 'KIDNEY_DISEASE' || normalized.contains('腎臟')) return '慢性腎臟病';
    if (upper == 'STROKE' || normalized.contains('中風')) return '腦中風';
    if (upper == 'METABOLIC_SYNDROME' || normalized.contains('代謝症候群')) return '代謝症候群';
    if (upper == 'GOUT' || normalized.contains('痛風')) return '痛風';
    if (upper == 'HYPERURICEMIA' || normalized.contains('高尿酸')) return '高尿酸血症';
    if (upper == 'GERD' || normalized.contains('胃食道逆流')) return '胃食道逆流';
    if (upper == 'NONE' ||
        normalized == '無' ||
        normalized.contains('無特殊疾病') ||
        normalized.contains('無疾病') ||
        normalized.toLowerCase() == 'none') {
      return '無疾病';
    }

    return normalized.isNotEmpty ? normalized : '無疾病';
  }

  static List<String> healthConditionsToApi(Iterable<dynamic> values) {
    final mapped = values
        .map((value) => healthConditionToApi(value?.toString()))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    if (mapped.isEmpty) {
      return ['NONE'];
    }

    if (mapped.length > 1) {
      mapped.remove('NONE');
    }

    return mapped;
  }

  static Set<String> healthConditionsToDisplaySet(dynamic value) {
    final values = _coerceToList(value)
        .map(healthConditionToDisplay)
        .where((item) => item.isNotEmpty)
        .toSet();

    return values.isEmpty ? {'無疾病'} : values;
  }

  static Set<String> dietGoalsToDisplaySet(dynamic value) {
    final values = _coerceToList(value)
        .map(dietGoalToDisplay)
        .where((item) => item.isNotEmpty)
        .toSet();

    return values.isEmpty ? {defaultDietGoalDisplay} : values;
  }

  static String firstDietGoalToApi(Iterable<String> values) {
    if (values.isEmpty) {
      return defaultDietGoalApi;
    }

    return dietGoalToApi(values.first);
  }

  static List<String> _coerceToList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }

    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return [];
    }

    return text
        .split(RegExp(r'[,，]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
