import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../color/app_colors.dart';
import '../../services/diet_service.dart';
import '../../services/dish_search_service.dart';
import '../../utils/friendly_error_message.dart';
import 'elf_feeding_page.dart';
import 'simple_camera_page.dart';

// === 1. 資料模型與輔助類別 (Data Models & Auxiliary Classes) ===

String _formatNumber(double? value) {
  if (value == null) return '';
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

class _NutritionValues {
  const _NutritionValues({
    this.calories,
    this.protein,
    this.fat,
    this.carbohydrates,
  });

  final double? calories;
  final double? protein;
  final double? fat;
  final double? carbohydrates;

  String toNutritionText() => [
        if (calories != null) '熱量 ${_formatNumber(calories)} kcal',
        if (protein != null) '蛋白質 ${_formatNumber(protein)} g',
        if (fat != null) '脂肪 ${_formatNumber(fat)} g',
        if (carbohydrates != null)
          '碳水化合物 ${_formatNumber(carbohydrates)} g',
      ].join('，');

  _NutritionValues scaledBy(double multiplier) => _NutritionValues(
        calories: calories == null ? null : calories! * multiplier,
        protein: protein == null ? null : protein! * multiplier,
        fat: fat == null ? null : fat! * multiplier,
        carbohydrates:
            carbohydrates == null ? null : carbohydrates! * multiplier,
      );

  _NutritionValues dividedBy(double divisor) => _NutritionValues(
        calories: calories == null ? null : calories! / divisor,
        protein: protein == null ? null : protein! / divisor,
        fat: fat == null ? null : fat! / divisor,
        carbohydrates:
            carbohydrates == null ? null : carbohydrates! / divisor,
      );
}

class _SelectedFood {
  const _SelectedFood({
    required this.id,
    required this.name,
    required this.unitLabel,
    required this.isManual,
    required this.nutrition,
    required this.recordDate,
    required this.mealType,
    this.amount = 1,
    this.selectedImage,
    this.imageBytes,
  });

  final String id;
  final String name;
  final String unitLabel;
  final bool isManual;
  final _NutritionValues nutrition;
  final DateTime recordDate;
  final String mealType;
  final double amount;
  final XFile? selectedImage;
  final Uint8List? imageBytes;

  _NutritionValues get totalNutrition => nutrition.scaledBy(amount);

  _SelectedFood copyWith({
    double? amount,
    _NutritionValues? nutrition,
    DateTime? recordDate,
    String? mealType,
    XFile? selectedImage,
    Uint8List? imageBytes,
    bool clearImage = false,
  }) {
    return _SelectedFood(
      id: id,
      name: name,
      unitLabel: unitLabel,
      isManual: isManual,
      nutrition: nutrition ?? this.nutrition,
      recordDate: recordDate ?? this.recordDate,
      mealType: mealType ?? this.mealType,
      amount: amount ?? this.amount,
      selectedImage: clearImage ? null : selectedImage ?? this.selectedImage,
      imageBytes: clearImage ? null : imageBytes ?? this.imageBytes,
    );
  }
}

class _EditorResult {
  const _EditorResult({required this.name, required this.nutrition});

  final String name;
  final _NutritionValues nutrition;
}

class _SavedCustomDish {
  const _SavedCustomDish({
    required this.name,
    required this.unitLabel,
    required this.nutrition,
    required this.updatedAt,
  });

  final String name;
  final String unitLabel;
  final _NutritionValues nutrition;
  final DateTime updatedAt;

  factory _SavedCustomDish.fromApi(Map<String, dynamic> json) {
    double? parseNum(dynamic value) => double.tryParse(value?.toString() ?? '');

    final rawUpdatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    return _SavedCustomDish(
      name: (json['dishName'] ?? '').toString(),
      unitLabel: '1份',
      nutrition: _NutritionValues(
        calories: parseNum(json['calories']),
        protein: parseNum(json['protein']),
        fat: parseNum(json['fat']),
        carbohydrates: parseNum(json['carbohydrates']),
      ),
      updatedAt: rawUpdatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

enum _DishSource { catalog, custom }

class _SelectedFoodEditorResult {
  const _SelectedFoodEditorResult({
    required this.amount,
    required this.nutrition,
  });

  final double amount;
  final _NutritionValues nutrition;
}

// === 2. 已選食物編輯對話框 (Selected Food Editor Dialog) ===

class _SelectedFoodEditorDialog extends StatefulWidget {
  const _SelectedFoodEditorDialog({required this.item});

  final _SelectedFood item;

  @override
  State<_SelectedFoodEditorDialog> createState() =>
      _SelectedFoodEditorDialogState();
}

class _SelectedFoodEditorDialogState extends State<_SelectedFoodEditorDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _fatController;
  late final TextEditingController _carbohydratesController;
  late final _NutritionValues _perServingNutrition;
  var _isUpdatingCalculatedValues = false;
  var _caloriesEdited = false;
  var _proteinEdited = false;
  var _fatEdited = false;
  var _carbohydratesEdited = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _numberText(widget.item.amount),
    );
    _perServingNutrition = widget.item.nutrition;
    final totalNutrition = widget.item.totalNutrition;
    _caloriesController = TextEditingController(
      text: _numberText(totalNutrition.calories),
    );
    _proteinController = TextEditingController(
      text: _numberText(totalNutrition.protein),
    );
    _fatController = TextEditingController(text: _numberText(totalNutrition.fat));
    _carbohydratesController = TextEditingController(
      text: _numberText(totalNutrition.carbohydrates),
    );
    _amountController.addListener(_recalculateUneditedNutrition);
    _caloriesController.addListener(
      () => _caloriesEdited = !_isUpdatingCalculatedValues,
    );
    _proteinController.addListener(
      () => _proteinEdited = !_isUpdatingCalculatedValues,
    );
    _fatController.addListener(() => _fatEdited = !_isUpdatingCalculatedValues);
    _carbohydratesController.addListener(
      () => _carbohydratesEdited = !_isUpdatingCalculatedValues,
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbohydratesController.dispose();
    super.dispose();
  }

  String _numberText(double? value) {
    return _formatNumber(value);
  }

  void _recalculateUneditedNutrition() {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;

    _isUpdatingCalculatedValues = true;
    if (!_caloriesEdited) {
      _caloriesController.text = _numberText(
        _perServingNutrition.calories == null
            ? null
            : _perServingNutrition.calories! * amount,
      );
    }
    if (!_proteinEdited) {
      _proteinController.text = _numberText(
        _perServingNutrition.protein == null
            ? null
            : _perServingNutrition.protein! * amount,
      );
    }
    if (!_fatEdited) {
      _fatController.text = _numberText(
        _perServingNutrition.fat == null ? null : _perServingNutrition.fat! * amount,
      );
    }
    if (!_carbohydratesEdited) {
      _carbohydratesController.text = _numberText(
        _perServingNutrition.carbohydrates == null
            ? null
            : _perServingNutrition.carbohydrates! * amount,
      );
    }
    _isUpdatingCalculatedValues = false;
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = const TextInputType.numberWithOptions(
      decimal: true,
    ),
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  void _submit() {
    final amount = double.tryParse(_amountController.text.trim());
    final calories = double.tryParse(_caloriesController.text.trim());
    final protein = double.tryParse(_proteinController.text.trim());
    final fat = double.tryParse(_fatController.text.trim());
    final carbohydrates = double.tryParse(
      _carbohydratesController.text.trim(),
    );
    if (amount == null || amount <= 0 || amount != amount.roundToDouble()) {
      setState(() => _error = '請輸入大於 0 的整數份數。');
      return;
    }
    if ([calories, protein, fat, carbohydrates].any(
      (value) => value == null || value < 0,
    )) {
      setState(() => _error = '請填寫四項營養數值；沒有資料請填 0。');
      return;
    }

    Navigator.pop(
      context,
      _SelectedFoodEditorResult(
        amount: amount,
        nutrition: _NutritionValues(
          calories: calories,
          protein: protein,
          fat: fat,
          carbohydrates: carbohydrates,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('編輯餐點資訊'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              '以下為依目前份數換算的總營養，並非單份；沒有資料請填 0。',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.6)), // [API更新] withOpacity 已過時，改用 withValues(alpha: 0.6)
            ),
            const SizedBox(height: 14),
            _field(
              widget.item.unitLabel == '100克' ? '倍數（1 = 100克）' : '份數',
              _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            _field('熱量（kcal）', _caloriesController),
            _field('蛋白質（g）', _proteinController),
            _field('脂肪（g）', _fatController),
            _field('碳水化合物（g）', _carbohydratesController),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('儲存')),
      ],
    );
  }
}

// === 3. 手動新增營養資訊對話框 (Nutrition Editor Dialog) ===

class _NutritionEditorDialog extends StatefulWidget {
  const _NutritionEditorDialog({
    required this.initialName,
    required this.initialNutrition,
  });

  final String initialName;
  final _NutritionValues initialNutrition;

  @override
  State<_NutritionEditorDialog> createState() => _NutritionEditorDialogState();
}

class _NutritionEditorDialogState extends State<_NutritionEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _fatController;
  late final TextEditingController _carbohydratesController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _caloriesController = TextEditingController(
      text: _numberText(widget.initialNutrition.calories),
    );
    _proteinController = TextEditingController(
      text: _numberText(widget.initialNutrition.protein),
    );
    _fatController = TextEditingController(
      text: _numberText(widget.initialNutrition.fat),
    );
    _carbohydratesController = TextEditingController(
      text: _numberText(widget.initialNutrition.carbohydrates),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbohydratesController.dispose();
    super.dispose();
  }

  String _numberText(double? value) {
    return _formatNumber(value);
  }

  Widget _field(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: label == '名稱'
            ? TextInputType.text
            : const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  void _submit() {
    final nutrition = _NutritionValues(
      calories: double.tryParse(_caloriesController.text.trim()),
      protein: double.tryParse(_proteinController.text.trim()),
      fat: double.tryParse(_fatController.text.trim()),
      carbohydrates: double.tryParse(_carbohydratesController.text.trim()),
    );
    final nutritionValues = [
      nutrition.calories,
      nutrition.protein,
      nutrition.fat,
      nutrition.carbohydrates,
    ];
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = '請填寫料理名稱。');
      return;
    }
    if (nutritionValues.any((value) => value == null || value < 0)) {
      setState(() => _error = '請填寫四項營養數值；沒有資料請填 0。');
      return;
    }
    Navigator.pop(
      context,
      _EditorResult(name: _nameController.text.trim(), nutrition: nutrition),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('手動新增營養資訊'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '請填寫料理名稱與四項營養數值；沒有資料請填 0。',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 14),
            _field('名稱', _nameController),
            _field('熱量（kcal）', _caloriesController),
            _field('蛋白質（g）', _proteinController),
            _field('脂肪（g）', _fatController),
            _field('碳水化合物（g）', _carbohydratesController),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('儲存')),
      ],
    );
  }
}

// === 4. 手動紀錄主頁面 (Manual Record Page Widget & State) ===

class ManualRecordPage extends StatefulWidget {
  const ManualRecordPage({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  State<ManualRecordPage> createState() => _ManualRecordPageState();
}

class _ManualRecordPageState extends State<ManualRecordPage> {
  final _searchController = TextEditingController();
  final _searchService = DishSearchService();
  final _dietService = DietService();
  final _imagePicker = ImagePicker();
  final _selectedItems = <_SelectedFood>[];
  final _savedCustomDishes = <_SavedCustomDish>[];

  Timer? _searchDebounce;
  DateTime _selectedDate = DateTime.now();
  String _mealType = '早餐';
  List<DishSearchResult> _results = const [];
  bool _isSearching = false;
  bool _isSaving = false;
  bool _isLoadingCustomDishes = true;
  _DishSource _dishSource = _DishSource.catalog;
  String? _searchError;

  static const _mealOptions = ['早餐', '午餐', '晚餐', '其他'];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _mealType = _automaticMealType();
    _loadSavedCustomDishes();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // === 5. 料理搜尋與自訂料理載入邏輯 ===
  String _automaticMealType() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return '早餐';
    if (hour >= 11 && hour < 17) return '午餐';
    return '晚餐';
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final trimmedQuery = query.trim();
    if (_dishSource == _DishSource.custom) {
      setState(() {
        _results = const [];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }
    if (trimmedQuery.isEmpty) {
      setState(() {
        _results = const [];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _search(trimmedQuery);
    });
  }

  Future<void> _search(String query) async {
    if (_dishSource != _DishSource.catalog) return;
    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final results = await _searchService.search(query);
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _results = const [];
        _searchError = '搜尋暫時失敗，請確認 GraphRAG 服務已啟動。';
      });
    } finally {
      if (mounted && _searchController.text.trim() == query) {
        setState(() => _isSearching = false);
      }
    }
  }

  List<DishSearchResult> get _visibleResults => _results;

  List<_SavedCustomDish> get _visibleCustomDishes {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return List<_SavedCustomDish>.from(_savedCustomDishes);
    }
    return _savedCustomDishes
        .where((dish) => dish.name.toLowerCase().contains(query))
        .toList();
  }

  void _changeDishSource(_DishSource source) {
    if (_dishSource == source) return;

    setState(() {
      _dishSource = source;
      _searchError = null;
      _isSearching = false;
    });

    if (source == _DishSource.catalog && _searchController.text.trim().isNotEmpty) {
      _onSearchChanged(_searchController.text);
    }
  }

  Future<void> _loadSavedCustomDishes() async {
    try {
      final records = await _dietService.getMyCustomDishes();
      final dishes = records
          .whereType<Map>()
          .map(
            (item) => _SavedCustomDish.fromApi(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((dish) => dish.name.trim().isNotEmpty)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (mounted) {
        setState(() {
          _savedCustomDishes
            ..clear()
            ..addAll(dishes);
          _isLoadingCustomDishes = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingCustomDishes = false);
      }
    }
  }

  // === 6. 已選料理項目管理邏輯（選擇、編輯、相片） ===
  _SelectedFood? _selectedFor(String id) {
    for (final item in _selectedItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _toggleSelection(DishSearchResult item) {
    setState(() {
      final index = _selectedItems.indexWhere(
        (selected) => selected.id == item.id,
      );
      if (index >= 0) {
        _selectedItems.removeAt(index);
      } else {
        _selectedItems.add(
          _SelectedFood(
            id: item.id,
            name: item.name,
            unitLabel: item.unitLabel,
            isManual: false,
            nutrition: _NutritionValues(
              calories: item.calories,
              protein: item.protein,
              fat: item.fat,
              carbohydrates: item.carbohydrates,
            ),
            recordDate: _selectedDate,
            mealType: _mealType,
          ),
        );
      }
    });
  }

  void _replaceSelectedItem(_SelectedFood replacement) {
    final index = _selectedItems.indexWhere(
      (item) => item.id == replacement.id,
    );
    if (index < 0) return;
    setState(() => _selectedItems[index] = replacement);
  }

  void _addSavedCustomDishToSelection(_SavedCustomDish dish) {
    final existingIndex = _selectedItems.indexWhere(
      (item) => item.name.trim().toLowerCase() == dish.name.trim().toLowerCase(),
    );

    setState(() {
      if (existingIndex >= 0) {
        final existingItem = _selectedItems[existingIndex];
        _selectedItems[existingIndex] = existingItem.copyWith(
          amount: existingItem.amount + 1,
        );
      } else {
        _selectedItems.add(
          _SelectedFood(
            id: 'saved-${dish.name}-${dish.updatedAt.microsecondsSinceEpoch}',
            name: dish.name,
            unitLabel: dish.unitLabel,
            isManual: true,
            nutrition: dish.nutrition,
            recordDate: _selectedDate,
            mealType: _mealType,
          ),
        );
      }
    });
  }

  String _formatAmount(double amount) {
    return _formatNumber(amount);
  }

  Future<void> _editSelectedItem(_SelectedFood item) async {
    final result = await showDialog<_SelectedFoodEditorResult>(
      context: context,
      builder: (_) => _SelectedFoodEditorDialog(item: item),
    );
    if (result != null && mounted) {
      _replaceSelectedItem(
        item.copyWith(
          amount: result.amount,
          nutrition: result.nutrition.dividedBy(result.amount),
        ),
      );
    }
  }

  Future<void> _pickImageFor(_SelectedFood item) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('相機拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('從相簿選擇'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      XFile? image;
      if (source == ImageSource.camera) {
        image = await Navigator.push<XFile>(
          context,
          MaterialPageRoute(builder: (context) => const SimpleCameraPage()),
        );
      } else {
        image = await _imagePicker.pickImage(source: ImageSource.gallery);
      }
      if (image == null || !mounted) return;
      _replaceSelectedItem(
        item.copyWith(
          selectedImage: image,
          imageBytes: await image.readAsBytes(),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(FriendlyErrorMessage.upload)),
        );
      }
    }
  }

  Future<void> _showSelectedItemsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: StatefulBuilder(
          builder: (context, setSheetState) => Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '設定已選項目',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  '每個餐點都可設定不同的日期、餐別、份數與照片',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _selectedItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = _selectedItems[index];
                      final hasPhoto = item.imageBytes != null;
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 23,
                                  backgroundColor: Colors.white,
                                  backgroundImage: hasPhoto
                                      ? MemoryImage(item.imageBytes!)
                                      : null,
                                  child: hasPhoto
                                      ? null
                                      : const Icon(
                                          Icons.restaurant_outlined,
                                          color: AppColors.secondary,
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${_formatAmount(item.amount)} × ${item.unitLabel}',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        item.totalNutrition.toNutritionText(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.success,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: '移除此項目',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: AppColors.danger,
                                  ),
                                  onPressed: () {
                                    setState(
                                      () => _selectedItems.removeAt(index),
                                    );
                                    setSheetState(() {});
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      await _pickDateFor(item);
                                      setSheetState(() {});
                                    },
                                    icon: const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      _formatRecordDate(item.recordDate),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      await _pickMealTypeFor(item);
                                      setSheetState(() {});
                                    },
                                    icon: const Icon(
                                      Icons.restaurant_outlined,
                                      size: 18,
                                    ),
                                    label: Text(item.mealType),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      await _editSelectedItem(item);
                                      setSheetState(() {});
                                    },
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('編輯'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      await _pickImageFor(item);
                                      setSheetState(() {});
                                    },
                                    icon: Icon(
                                      hasPhoto
                                          ? Icons.photo_camera
                                          : Icons.add_a_photo_outlined,
                                      size: 18,
                                    ),
                                    label: Text(hasPhoto ? '更換照片' : '新增照片'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('完成設定'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // === 7. 日期選擇與飲食紀錄儲存提交邏輯 ===
  Future<void> _pickDate() async {
    final picked = await _showRecordDatePicker(_selectedDate);
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  Future<void> _pickDateFor(_SelectedFood item) async {
    final picked = await _showRecordDatePicker(item.recordDate);
    if (picked != null && mounted) {
      _replaceSelectedItem(item.copyWith(recordDate: picked));
    }
  }

  Future<DateTime?> _showRecordDatePicker(DateTime initialDate) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.secondary),
        ),
        child: child!,
      ),
    );
  }

  String _formatRecordDate(DateTime date) {
    return '${date.year}/${date.month}/${date.day}';
  }

  Future<void> _pickMealTypeFor(_SelectedFood item) async {
    final selectedMeal = await _showMealTypePicker();
    if (selectedMeal != null && mounted) {
      _replaceSelectedItem(item.copyWith(mealType: selectedMeal));
    }
  }

  void _changeDateBy(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final candidate = _selectedDate.add(Duration(days: days));
    final normalized = DateTime(candidate.year, candidate.month, candidate.day);
    if (normalized.isAfter(today)) return;
    setState(() => _selectedDate = normalized);
  }

  bool get _isTodaySelected {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Future<void> _addManualItem() async {
    final query = _searchController.text.trim();
    final result = await _showNutritionEditor(
      initialName: query,
      initialNutrition: const _NutritionValues(),
    );
    if (result == null || !mounted) return;

    const unitLabel = '1份';
    setState(() {
      _selectedItems.add(
        _SelectedFood(
          id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
          name: result.name,
          unitLabel: unitLabel,
          isManual: true,
          nutrition: result.nutrition,
          recordDate: _selectedDate,
          mealType: _mealType,
        ),
      );
    });
  }

  Future<_EditorResult?> _showNutritionEditor({
    required String initialName,
    required _NutritionValues initialNutrition,
  }) async {
    return showDialog<_EditorResult>(
      context: context,
      builder: (_) => _NutritionEditorDialog(
        initialName: initialName,
        initialNutrition: initialNutrition,
      ),
    );
  }

  Future<void> _saveSelectedItems() async {
    if (_selectedItems.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);

    var savedCount = 0;
    String? firstImagePath;
    final elfItems = <Map<String, dynamic>>[];
    try {
      for (final item in _selectedItems) {
        final result = await _dietService.createDietRecord(
          dishName: item.name,
          mealType: item.mealType,
          amount: item.amount,
          nutrition: item.totalNutrition.toNutritionText(),
          description: '${item.isManual ? '手動新增' : '系統搜尋'}（${item.unitLabel}）',
          mealDate: item.recordDate,
          fetchNutritionIfMissing: false,
          type: item.isManual ? 'MANUAL' : null,
        );
        if (result['success'] == true) {
          savedCount++;
          final recordData = result['data'];
          final recordId = int.tryParse(recordData?['id']?.toString() ?? '');
          if (recordId != null &&
              item.selectedImage != null &&
              item.imageBytes != null) {
            await _dietService.uploadDietPhoto(
              recordId,
              item.imageBytes!,
              item.selectedImage!.name,
            );
          }
          firstImagePath ??= item.selectedImage?.path;
          elfItems.add({
            'name': item.name,
            'portion': '${_formatAmount(item.amount)} × ${item.unitLabel}',
            'calories': item.totalNutrition.calories == null
                ? '-- kcal'
                : '${_formatNumber(item.totalNutrition.calories)} kcal',
          });
        }
      }

      if (!mounted) return;
      if (savedCount == _selectedItems.length) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ElfFeedingPage(
              imagePath: firstImagePath ?? '',
              items: elfItems,
              recordDate: _selectedItems.first.recordDate,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已儲存 $savedCount 項，部分項目未能儲存。')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(FriendlyErrorMessage.dietRecord)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // === 8. UI 介面建構與組件拆分 (Main Layout & UI Sub-views) ===
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '前一天',
              onPressed: () => _changeDateBy(-1),
              icon: const Icon(Icons.chevron_left, color: AppColors.secondary),
              visualDensity: VisualDensity.compact,
            ),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 18,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '後一天',
              onPressed: _isTodaySelected ? null : () => _changeDateBy(1),
              icon: Icon(
                Icons.chevron_right,
                color: _isTodaySelected
                    ? Colors.black26
                    : AppColors.secondary,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (query) {
                setState(() {});
                _onSearchChanged(query);
              },
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: '搜尋料理',
                prefixIcon: const Icon(Icons.search, color: AppColors.secondary),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        icon: Icon(
                          Icons.cancel,
                          color: AppColors.secondary.withValues(alpha: 0.6),
                        ),
                      ),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(
                    color: AppColors.secondary.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(
                    color: AppColors.secondary.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          _buildDishSourceTabs(),
          Expanded(
            child: Container(
              color: AppColors.surface,
              child: _buildResultArea(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedItems.isNotEmpty) ...[
              SizedBox(
                width: double.infinity,
                height: 58,
                child: OutlinedButton(
                  onPressed: _showSelectedItemsSheet,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.background,
                    foregroundColor: AppColors.secondary,
                    side: const BorderSide(color: AppColors.secondary),
                    shape: const StadiumBorder(),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      const Icon(Icons.tune_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '設定已選 ${_selectedItems.length} 項',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Text(
                              '可編輯份數、營養與照片',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _selectedItems.isEmpty || _isSaving
                    ? null
                    : _saveSelectedItems,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  disabledBackgroundColor: const Color(0xFFD5C7AE),
                  disabledForegroundColor: const Color(0xFF8E7E6C),
                  shape: const StadiumBorder(),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _selectedItems.isEmpty ? '請選擇食物' : '完成紀錄並餵食',
                        style: TextStyle(
                          color: _selectedItems.isEmpty
                              ? const Color(0xFF8E7E6C)
                              : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultArea() {
    if (_dishSource == _DishSource.custom) {
      return _buildCustomDishesArea();
    }
    if (_isSearching) {
      // [格式修復] if 語句補全大括號
      return const Center(
        child: CircularProgressIndicator(color: AppColors.secondary),
      );
    }
    if (_searchError != null) {
      // [格式修復] if 語句補全大括號
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_searchError!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_searchController.text.trim().isEmpty) return _buildCatalogPrompt();

    final results = _visibleResults;
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '找不到你要的內容？',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _addManualItem,
                icon: const Icon(Icons.add),
                label: const Text('新增自訂料理'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [_buildSearchResultsSection(results)],
    );
  }

  Widget _buildDishSourceTabs() {
    return Container(
      width: double.infinity,
      color: AppColors.secondary,
      child: Row(
        children: [
          _buildDishSourceTab(
            source: _DishSource.catalog,
            label: '推薦料理',
            icon: Icons.restaurant_menu_outlined,
          ),
          _buildDishSourceTab(
            source: _DishSource.custom,
            label: '我的料理',
            icon: Icons.bookmark_added_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildDishSourceTab({
    required _DishSource source,
    required String label,
    required IconData icon,
  }) {
    final selected = _dishSource == source;
    return Expanded(
      child: InkWell(
        onTap: () => _changeDishSource(source),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 62,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? Colors.white : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCatalogPrompt() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '輸入名稱搜尋推薦料理。',
          style: TextStyle(color: Colors.black54),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildCustomDishesArea() {
    if (_isLoadingCustomDishes) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.secondary),
      );
    }

    final dishes = _visibleCustomDishes;
    if (dishes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _searchController.text.trim().isEmpty
                    ? '目前還沒有你建立的料理。'
                    : '找不到符合的我的料理。',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _addManualItem,
                icon: const Icon(Icons.add),
                label: const Text('新增自訂料理'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      itemCount: dishes.length,
      separatorBuilder: (_, _) => const Divider(height: 1), // [Lint修復] 簡化未使用的回呼參數 (__ 改為 _)
      itemBuilder: (context, index) => _buildSavedDishTile(dishes[index]),
    );
  }

  Widget _buildSavedDishTile(_SavedCustomDish dish) {
    final selected = _selectedItems.any(
      (item) => item.name.trim().toLowerCase() == dish.name.trim().toLowerCase(),
    );

    return ListTile(
      onTap: () => _addSavedCustomDishToSelection(dish),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      title: Text(
        dish.name,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          '${dish.unitLabel}  ·  ${dish.nutrition.toNutritionText().isEmpty ? '未填營養資訊' : dish.nutrition.toNutritionText()}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.success, fontSize: 14),
        ),
      ),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: selected
            ? AppColors.success
            : AppColors.secondary.withValues(alpha: 0.35),
        size: 28,
      ),
    );
  }

  Widget _buildSearchResultsSection(List<DishSearchResult> results) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text(
            '搜尋結果',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.secondary,
            ),
          ),
        ),
        ...results.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final selected = _selectedFor(item.id);
          final nutrition = selected?.totalNutrition ??
              _NutritionValues(
                calories: item.calories,
                protein: item.protein,
                fat: item.fat,
                carbohydrates: item.carbohydrates,
              );
          final nutritionText = nutrition.toNutritionText().isEmpty
              ? '營養資訊暫無資料'
              : nutrition.toNutritionText();
          return Column(
            children: [
              ListTile(
                onTap: () => _toggleSelection(item),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 6,
                ),
                title: Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    '${item.unitLabel}  ·  $nutritionText',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 15,
                    ),
                  ),
                ),
                trailing: Icon(
                  selected == null
                      ? Icons.radio_button_unchecked
                      : Icons.check_circle,
                  color: selected == null
                      ? AppColors.secondary.withValues(alpha: 0.35)
                      : AppColors.success,
                  size: 28,
                ),
              ),
              if (index < results.length - 1)
                const Divider(height: 1, indent: 20),
            ],
          );
        }),
      ],
    );
  }


  Future<String?> _showMealTypePicker() {
    return showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _mealOptions
              .map(
                (meal) => ListTile(
                  title: Text(meal, textAlign: TextAlign.center),
                  onTap: () => Navigator.pop(context, meal),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
