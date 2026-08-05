import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../services/admin_service.dart'; // 匯入 admin_service.dart

class AdminAddItemPage extends StatefulWidget { // 定義 AdminAddItemPage 類別，繼承自 StatefulWidget
  final String title; // 宣告類別成員或方法內部的區域變數
  final Map<String, dynamic>? editItem; // 編輯項目，為空則為新增模式

  const AdminAddItemPage({super.key, required this.title, this.editItem}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<AdminAddItemPage> createState() => _AdminAddItemPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _AdminAddItemPageState extends State<AdminAddItemPage> { // 定義 _AdminAddItemPageState 類別，繼承自 State
  final _formKey = GlobalKey<FormState>(); // 宣告類別成員或方法內部的區域變數
  bool _isSaving = false;

  // 餐廳管理欄位
  final TextEditingController _restNameController = TextEditingController();
  final TextEditingController _restAddressController = TextEditingController();
  final TextEditingController _restPhoneController = TextEditingController();
  final TextEditingController _restReviewController = TextEditingController();
  int _restStars = 5;

  // 菜單管理欄位
  final TextEditingController _menuRestaurantNameController = TextEditingController();
  final TextEditingController _menuDishNameController = TextEditingController();
  final TextEditingController _menuIngredientsController = TextEditingController();
  final TextEditingController _menuNutritionController = TextEditingController();
  String _menuRecommendLevel = '高';

  bool get _isEditMode => widget.editItem != null;

  @override // 標記此方法為覆寫父類別之方法
  void initState() {
    super.initState();
    if (_isEditMode) {
      final item = widget.editItem!;
      if (widget.title.contains('餐廳')) {
        _restNameController.text = item['name'] ?? '';
        _restAddressController.text = item['address'] ?? '';
        _restPhoneController.text = item['phone'] ?? '';
        _restReviewController.text = item['review'] ?? '';
        _restStars = item['stars'] ?? 5;
      } else {
        _menuRestaurantNameController.text = item['restaurantName'] ?? '';
        _menuDishNameController.text = item['dishName'] ?? '';
        _menuIngredientsController.text = item['ingredients'] ?? '';
        _menuNutritionController.text = item['nutrition'] ?? '';
        _menuRecommendLevel = item['recommendLevel'] ?? '高';
      }
    }
  }

  @override
  void dispose() {
    _restNameController.dispose();
    _restAddressController.dispose();
    _restPhoneController.dispose();
    _restReviewController.dispose();
    _menuRestaurantNameController.dispose();
    _menuDishNameController.dispose();
    _menuIngredientsController.dispose();
    _menuNutritionController.dispose();
    super.dispose();
  }

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    final isRestaurant = widget.title.contains('餐廳');
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: AppColors.surface, // 設定顏色數值（Color）
      appBar: AppBar( // 設定頂部的導航欄（AppBar）
        title: Text('${_isEditMode ? '編輯' : '新增'}${widget.title.replaceAll('管理', '')}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
        backgroundColor: AppColors.background, // 設定顏色數值（Color）
        elevation: 0, // 執行相對應的邏輯計算或設定屬性參數
        iconTheme: const IconThemeData(color: AppColors.textPrimary), // 設定顏色數值（Color）
      ), // 執行相對應的邏輯計算或設定屬性參數
      body: SingleChildScrollView( // 設定頁面的主要內容區域（body）
        padding: const EdgeInsets.all(20.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
        child: Form( // 執行相對應的邏輯計算或設定屬性參數
          key: _formKey, // 執行相對應的邏輯計算或設定屬性參數
          child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
            crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
            children: [ // 執行相對應的邏輯計算或設定屬性參數
              Text( // 建立文字顯示元件（Text）
                isRestaurant ? '餐廳詳細資訊' : '菜單餐點詳細資訊', // 執行相對應的邏輯計算或設定屬性參數
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
              ), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              
              if (isRestaurant) ...[
                // 餐廳管理表單
                _buildField(_restNameController, '餐廳名稱', Icons.store, '請輸入餐廳名稱'),
                const SizedBox(height: 15),
                _buildField(_restAddressController, '地址', Icons.location_on, '請輸入地址'),
                const SizedBox(height: 15),
                _buildField(_restPhoneController, '電話', Icons.phone, '請輸入電話'),
                const SizedBox(height: 15),
                _buildField(_restReviewController, '特色介紹 / 評價描述', Icons.rate_review, '請輸入評價描述', maxLines: 3),
                const SizedBox(height: 15),
                Row(
                  children: [
                    const Text('星級評分：', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    const SizedBox(width: 10),
                    DropdownButton<int>(
                      value: _restStars,
                      dropdownColor: AppColors.background,
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                      items: [5, 4, 3, 2, 1].map((s) => DropdownMenuItem(value: s, child: Text('$s 星'))).toList(),
                      onChanged: (val) => setState(() => _restStars = val!),
                    ),
                  ],
                ),
              ] else ...[
                // 菜單管理表單
                _buildField(_menuRestaurantNameController, '所屬餐廳名稱', Icons.store, '請輸入餐廳名稱'),
                const SizedBox(height: 15),
                _buildField(_menuDishNameController, '餐點名稱', Icons.restaurant_menu, '請輸入餐點名稱'),
                const SizedBox(height: 15),
                _buildField(_menuIngredientsController, '主要食材 (逗號分隔)', Icons.shopping_basket, '請輸入主要食材'),
                const SizedBox(height: 15),
                _buildField(_menuNutritionController, '營養資訊 (如：熱量 400kcal)', Icons.health_and_safety, '請輸入營養資訊'),
                const SizedBox(height: 15),
                Row(
                  children: [
                    const Text('推薦指數：', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: _menuRecommendLevel,
                      dropdownColor: AppColors.background,
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                      items: ['高', '中', '低'].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                      onChanged: (val) => setState(() => _menuRecommendLevel = val!),
                    ),
                  ],
                ),
              ],
              
              const SizedBox(height: 40), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              SizedBox( // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                width: double.infinity, // 執行相對應的邏輯計算或設定屬性參數
                height: 55, // 執行相對應的邏輯計算或設定屬性參數
                child: ElevatedButton( // 建立常規按鈕（ElevatedButton），點擊時觸作相對應事件
                  style: ElevatedButton.styleFrom( // 執行相對應的邏輯計算或設定屬性參數
                    backgroundColor: AppColors.primary, // 設定顏色數值（Color）
                    foregroundColor: AppColors.background, // 設定顏色數值（Color）
                    elevation: 5, // 執行相對應的邏輯計算或設定屬性參數
                    shadowColor: Colors.black.withOpacity(0.3), // 設定顏色數值（Color）
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // 設定容器的圓角弧度半徑大小
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  onPressed: _isSaving ? null : _submitForm, // 執行相對應的邏輯計算或設定屬性參數
                  child: _isSaving 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(_isEditMode ? '儲存變更' : '確認新增', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
            ], // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildField(TextEditingController controller, String label, IconData icon, String errorMsg, {int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.background,
        labelText: label,
        labelStyle: const TextStyle(color: Colors.black54),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
        prefixIcon: Icon(icon, color: AppColors.secondary),
      ),
      validator: (value) => (value == null || value.trim().isEmpty) ? errorMsg : null,
    );
  }

  Future<void> _submitForm() async { // 執行相對應的邏輯計算或設定屬性參數
    if (_formKey.currentState!.validate()) { // 執行相對應的邏輯計算或設定屬性參數
      setState(() => _isSaving = true);
      final isRestaurant = widget.title.contains('餐廳');
      try {
        if (isRestaurant) {
          final payload = {
            'name': _restNameController.text.trim(),
            'address': _restAddressController.text.trim(),
            'phone': _restPhoneController.text.trim(),
            'review': _restReviewController.text.trim(),
            'stars': _restStars,
            'latitude': 25.0330, // 台北預設經緯度
            'longitude': 121.5654,
          };
          
          final res = _isEditMode
              ? await AdminService().updateRestaurant(widget.editItem!['id'], payload)
              : await AdminService().createRestaurant(payload);
              
          if (res['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isEditMode ? '已成功更新餐廳' : '已成功新增餐廳')));
            Navigator.pop(context, true);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失敗: ${res['message']}')));
          }
        } else {
          final payload = {
            'restaurantName': _menuRestaurantNameController.text.trim(),
            'dishName': _menuDishNameController.text.trim(),
            'ingredients': _menuIngredientsController.text.trim(),
            'nutrition': _menuNutritionController.text.trim(),
            'recommendLevel': _menuRecommendLevel,
          };
          
          final res = _isEditMode
              ? await AdminService().updateMenuItem(widget.editItem!['id'], payload)
              : await AdminService().createMenuItem(payload);
              
          if (res['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isEditMode ? '已成功更新菜單' : '已成功新增菜單')));
            Navigator.pop(context, true);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失敗: ${res['message']}')));
          }
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作出錯: $e')));
      } finally {
        setState(() => _isSaving = false);
      }
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束
