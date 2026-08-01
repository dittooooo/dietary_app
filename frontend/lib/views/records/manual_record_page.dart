import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import 'elf_feeding_page.dart'; // 匯入 elf_feeding_page.dart 元件庫或套件
import 'package:image_picker/image_picker.dart'; // 匯入 image_picker.dart 元件庫或套件
import 'dart:typed_data'; // 匯入 dart:typed_data 元件庫或套件
import 'simple_camera_page.dart'; // 匯入 simple_camera_page.dart 元件庫或套件
import '../../services/diet_service.dart'; // 匯入 diet_service.dart 元件庫或套件

class ManualRecordPage extends StatefulWidget { // 定義 ManualRecordPage 類別，繼承自 StatefulWidget
  final DateTime? initialDate; // 宣告類別成員或方法內部的區域變數
  const ManualRecordPage({super.key, this.initialDate}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<ManualRecordPage> createState() => _ManualRecordPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _ManualRecordPageState extends State<ManualRecordPage> { // 定義 _ManualRecordPageState 類別，繼承自 State
  late DateTime _selectedDate; // 宣告類別成員或方法內部的區域變數
  late String _mealType; // 宣告類別成員或方法內部的區域變數
  final List<TextEditingController> _itemControllers = [TextEditingController()]; // 宣告類別成員或方法內部的區域變數
  final TextEditingController _caloriesController = TextEditingController();
  final TextEditingController _proteinController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();
  final TextEditingController _carbsController = TextEditingController();
  XFile? _selectedImage; // 執行相對應的邏輯計算或設定屬性參數
  Uint8List? _imageBytes; // 執行相對應的邏輯計算或設定屬性參數
  final ImagePicker _picker = ImagePicker(); // 宣告類別成員或方法內部的區域變數
  
  final List<String> _mealOptions = ['早餐', '午餐', '晚餐']; // 宣告類別成員或方法內部的區域變數

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _selectedDate = widget.initialDate ?? DateTime.now(); // 執行相對應的邏輯計算或設定屬性參數
    _mealType = _getAutoMealType(); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  String _getAutoMealType() { // 宣告類別成員或方法內部的區域變數
    final hour = DateTime.now().hour; // 宣告類別成員或方法內部的區域變數
    if (hour >= 5 && hour < 11) return '早餐'; // 回傳建構完成的元件或方法計算結果
    if (hour >= 11 && hour < 17) return '午餐'; // 回傳建構完成的元件或方法計算結果
    return '晚餐'; // 回傳建構完成的元件或方法計算結果
  } // 程式碼區塊或元件結構結束

  Future<void> _selectDate() async { // 定義非同步方法（Future），執行耗時操作
    final picked = await showDatePicker( // 宣告類別成員或方法內部的區域變數
      context: context, // 執行相對應的邏輯計算或設定屬性參數
      initialDate: _selectedDate, // 執行相對應的邏輯計算或設定屬性參數
      firstDate: DateTime(2023), // 執行相對應的邏輯計算或設定屬性參數
      lastDate: DateTime.now(), // 執行相對應的邏輯計算或設定屬性參數
      builder: (context, child) => Theme( // 執行相對應的邏輯計算或設定屬性參數
        data: Theme.of(context).copyWith( // 執行相對應的邏輯計算或設定屬性參數
          colorScheme: const ColorScheme.light(primary: AppColors.primary, onPrimary: Colors.white, onSurface: AppColors.textPrimary), // 設定顏色數值（Color）
        ), // 執行相對應的邏輯計算或設定屬性參數
        child: child!, // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
    if (picked != null) setState(() => _selectedDate = picked); // 更新狀態數據並通知 UI 重新渲染畫面
  } // 程式碼區塊或元件結構結束

  void _addItem() { // 執行相對應的邏輯計算或設定屬性參數
    setState(() => _itemControllers.add(TextEditingController())); // 更新狀態數據並通知 UI 重新渲染畫面
  } // 程式碼區塊或元件結構結束

  void _removeItem(int index) { // 執行相對應的邏輯計算或設定屬性參數
    if (_itemControllers.length > 1) { // 執行相對應的邏輯計算或設定屬性參數
      setState(() => _itemControllers.removeAt(index)); // 更新狀態數據並通知 UI 重新渲染畫面
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Future<void> _pickImage() async { // 定義非同步方法（Future），執行耗時操作
    // 彈出選單讓使用者選擇「拍照」或「從相簿選取」
    final ImageSource? source = await showModalBottomSheet<ImageSource>( // 宣告類別成員或方法內部的區域變數
      context: context, // 執行相對應的邏輯計算或設定屬性參數
      backgroundColor: AppColors.background, // 設定顏色數值（Color）
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), // 建立編譯期常數，優化 Flutter 渲染效能
      builder: (context) => Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        padding: const EdgeInsets.symmetric(vertical: 20), // 設定外邊距或內邊距的數值大小（EdgeInsets）
        child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
          mainAxisSize: MainAxisSize.min, // 執行相對應的邏輯計算或設定屬性參數
          children: [ // 執行相對應的邏輯計算或設定屬性參數
            ListTile( // 執行相對應的邏輯計算或設定屬性參數
              leading: const Icon(Icons.camera_alt, color: AppColors.textPrimary), // 設定顏色數值（Color）
              title: const Text('拍照', style: TextStyle(fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
              onTap: () => Navigator.pop(context, ImageSource.camera), // 導航路由返回：關閉當前頁面並返回上一頁
            ), // 執行相對應的邏輯計算或設定屬性參數
            ListTile( // 執行相對應的邏輯計算或設定屬性參數
              leading: const Icon(Icons.photo_library, color: AppColors.textPrimary), // 設定顏色數值（Color）
              title: const Text('從相簿選取', style: TextStyle(fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
              onTap: () => Navigator.pop(context, ImageSource.gallery), // 導航路由返回：關閉當前頁面並返回上一頁
            ), // 執行相對應的邏輯計算或設定屬性參數
          ], // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束

    if (source != null) { // 執行相對應的邏輯計算或設定屬性參數
      try { // 執行相對應的邏輯計算或設定屬性參數
        XFile? image; // 執行相對應的邏輯計算或設定屬性參數
        if (source == ImageSource.camera) { // 執行相對應的邏輯計算或設定屬性參數
          // 使用自訂的 SimpleCameraPage 進行拍照，解決 Web 和行動端相機拉起與預覽問題
          image = await Navigator.push<XFile>( // 導航路由跳轉：開啟並推入新頁面
            context, // 執行相對應的邏輯計算或設定屬性參數
            MaterialPageRoute(builder: (context) => const SimpleCameraPage()), // 建立編譯期常數，優化 Flutter 渲染效能
          ); // 程式碼區塊或元件結構結束
        } else { // 程式碼區塊或元件結構結束
          image = await _picker.pickImage(source: ImageSource.gallery); // 執行相對應的邏輯計算或設定屬性參數
        } // 程式碼區塊或元件結構結束

        if (image != null) { // 執行相對應的邏輯計算或設定屬性參數
          final bytes = await image.readAsBytes(); // 宣告類別成員或方法內部的區域變數
          setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
            _selectedImage = image; // 執行相對應的邏輯計算或設定屬性參數
            _imageBytes = bytes; // 執行相對應的邏輯計算或設定屬性參數
          }); // 程式碼區塊或元件結構結束
        } // 程式碼區塊或元件結構結束
      } catch (e) { // 執行相對應的邏輯計算或設定屬性參數
        if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
          ScaffoldMessenger.of(context).showSnackBar( // 執行相對應的邏輯計算或設定屬性參數
            SnackBar(content: Text('選取圖片失敗: $e')) // 建立文字顯示元件（Text）
          ); // 程式碼區塊或元件結構結束
        } // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  bool _isSaving = false;

  Future<void> _submit() async {
    List<String> items = [];
    for (var controller in _itemControllers) {
      if (controller.text.trim().isNotEmpty) {
        items.add(controller.text.trim());
      }
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請至少輸入一項飲食內容')));
      return;
    }

    setState(() => _isSaving = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在儲存飲食紀錄...')));

    try {
      final dishName = items.join(', ');
      final caloriesText = _caloriesController.text.trim();
      final proteinText = _proteinController.text.trim();
      final fatText = _fatController.text.trim();
      final carbsText = _carbsController.text.trim();

      final List<String> nutritionParts = [];
      if (caloriesText.isNotEmpty) nutritionParts.add('熱量: $caloriesText kcal');
      if (proteinText.isNotEmpty) nutritionParts.add('蛋白質: $proteinText g');
      if (fatText.isNotEmpty) nutritionParts.add('脂肪: $fatText g');
      if (carbsText.isNotEmpty) nutritionParts.add('碳水化合物: $carbsText g');
      final nutritionString = nutritionParts.isNotEmpty 
          ? nutritionParts.join(', ') 
          : '熱量: 0 kcal, 蛋白質: 0 g, 脂肪: 0 g, 碳水化合物: 0 g';

      final result = await DietService().createDietRecord(
        dishName: dishName,
        mealType: _mealType,
        description: '手動輸入飲食紀錄',
        nutrition: nutritionString,
        mealDate: _selectedDate,
      ).timeout(const Duration(seconds: 2));

      if (result['success'] == true) {
        final recordData = result['data'];
        final int? recordId = recordData['id'];

        if (recordId != null && _imageBytes != null && _selectedImage != null) {
          // 上傳照片改為背景執行，不阻礙使用者
          DietService().uploadDietPhoto(recordId, _imageBytes!, _selectedImage!.name).catchError((e) {
            debugPrint('背景上傳圖片失敗: $e');
            return {'success': false, 'message': e.toString()};
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('儲存成功！')));
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ElfFeedingPage(
                imagePath: _selectedImage?.path ?? "",
                items: items.map((name) => {
                  'name': name,
                  'portion': '1份',
                  'calories': caloriesText.isNotEmpty ? '$caloriesText kcal' : '-- kcal',
                }).toList(),
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('儲存失敗：' + (result['message'] ?? '未知錯誤'))));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('儲存時發生錯誤: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: AppColors.surface, // 設定顏色數值（Color）
      appBar: AppBar( // 設定頂部的導航欄（AppBar）
        title: const Text('手動紀錄', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
        centerTitle: true, // 執行相對應的邏輯計算或設定屬性參數
        backgroundColor: AppColors.background, // 設定顏色數值（Color）
        elevation: 0, // 執行相對應的邏輯計算或設定屬性參數
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary), onPressed: () => Navigator.pop(context)), // 導航路由返回：關閉當前頁面並返回上一頁
      ), // 執行相對應的邏輯計算或設定屬性參數
      body: SingleChildScrollView( // 設定頁面的主要內容區域（body）
        padding: const EdgeInsets.all(20), // 設定外邊距或內邊距的數值大小（EdgeInsets）
        child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
          crossAxisAlignment: CrossAxisAlignment.start, // 執行相對應的邏輯計算或設定屬性參數
          children: [ // 執行相對應的邏輯計算或設定屬性參數
            // 0. 照片選擇區
            _buildPhotoSection(), // 執行相對應的邏輯計算或設定屬性參數
            const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
            
            // 1. 日期與時段選擇
            _buildSelectionSection(), // 執行相對應的邏輯計算或設定屬性參數
            const SizedBox(height: 25), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
            
            // 2. 飲食內容標題
            const Row( // 建立水平排列元件（Row），橫向排列多個子元件
              children: [ // 執行相對應的邏輯計算或設定屬性參數
                Icon(Icons.restaurant_menu, color: AppColors.secondary, size: 20), // 設定顏色數值（Color）
                SizedBox(width: 8), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                Text('飲食內容', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
              ], // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）

            // 3. 項目列表
            ..._itemControllers.asMap().entries.map((entry) => _buildItemField(entry.key, entry.value)).toList(), // 執行相對應的邏輯計算或設定屬性參數

            const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
            
            // 4. 新增項目按鈕
            Center( // 建立置中對齊元件（Center），將子元件居中顯示
              child: TextButton.icon( // 執行相對應的邏輯計算或設定屬性參數
                onPressed: _addItem, // 執行相對應的邏輯計算或設定屬性參數
                icon: const Icon(Icons.add_circle_outline, color: AppColors.secondary), // 設定顏色數值（Color）
                label: const Text('新增一項內容', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            
            const SizedBox(height: 40), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
            
            // 5. 完成按鈕
            SizedBox( // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              width: double.infinity, // 執行相對應的邏輯計算或設定屬性參數
              height: 55, // 執行相對應的邏輯計算或設定屬性參數
              child: ElevatedButton( // 建立常規按鈕（ElevatedButton），點擊時觸作相對應事件
                onPressed: _isSaving ? null : _submit, // 執行相對應的邏輯計算或設定屬性參數
                style: ElevatedButton.styleFrom( // 執行相對應的邏輯計算或設定屬性參數
                  backgroundColor: AppColors.primary, // 設定顏色數值（Color）
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // 設定容器的圓角弧度半徑大小
                  elevation: 2, // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('完成紀錄並餵食', style: TextStyle(color: AppColors.background, fontSize: 18, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ], // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildSelectionSection() { // 定義用於重複使用的 UI 封裝建構方法
    return Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15), // 設定外邊距或內邊距的數值大小（EdgeInsets）
      decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
        color: AppColors.background, // 設定顏色數值（Color）
        borderRadius: BorderRadius.circular(20), // 設定容器的圓角弧度半徑大小
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 10)], // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
      ), // 執行相對應的邏輯計算或設定屬性參數
      child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
            child: _buildSelectRow("${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}", Icons.calendar_today, _selectDate), // 建立水平排列元件（Row），橫向排列多個子元件
          ), // 執行相對應的邏輯計算或設定屬性參數
          Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
            width: 1, // 執行相對應的邏輯計算或設定屬性參數
            height: 30, // 執行相對應的邏輯計算或設定屬性參數
            color: AppColors.border.withOpacity(0.5), // 設定顏色數值（Color）
          ), // 執行相對應的邏輯計算或設定屬性參數
          Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
            child: _buildSelectRow(_mealType, Icons.access_time, _showMealPicker), // 建立水平排列元件（Row），橫向排列多個子元件
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildSelectRow(String value, IconData icon, VoidCallback onTap) { // 建立水平排列元件（Row），橫向排列多個子元件
    return InkWell( // 回傳建構完成的元件或方法計算結果
      onTap: onTap, // 執行相對應的邏輯計算或設定屬性參數
      child: Padding( // 建立間距容器（Padding），用於設定內部邊距
        padding: const EdgeInsets.symmetric(horizontal: 10), // 設定外邊距或內邊距的數值大小（EdgeInsets）
        child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
          mainAxisAlignment: MainAxisAlignment.center, // 水平置中
          children: [ // 執行相對應的邏輯計算或設定屬性參數
            Icon(icon, size: 18, color: AppColors.textPrimary), // 設定顏色數值（Color）
            const SizedBox(width: 8), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
            Flexible( // 執行相對應的邏輯計算或設定屬性參數
              child: Text( // 建立文字顯示元件（Text）
                value,  // 執行相對應的邏輯計算或設定屬性參數
                style: const TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                  fontWeight: FontWeight.bold,  // 執行相對應的邏輯計算或設定屬性參數
                  fontSize: 14, // 稍微縮小字體以適應並排
                  color: AppColors.textPrimary // 設定顏色數值（Color）
                ), // 執行相對應的邏輯計算或設定屬性參數
                overflow: TextOverflow.ellipsis, // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
            const SizedBox(width: 2), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
            const Icon(Icons.chevron_right, color: Colors.grey, size: 16), // 設定顏色數值（Color）
          ], // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildItemField(int index, TextEditingController controller) { // 定義用於重複使用的 UI 封裝建構方法
    return Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      margin: const EdgeInsets.only(bottom: 12), // 設定外邊距或內邊距的數值大小（EdgeInsets）
      decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
        color: AppColors.background, // 設定顏色數值（Color）
        borderRadius: BorderRadius.circular(15), // 設定容器的圓角弧度半徑大小
        border: Border.all(color: AppColors.border.withOpacity(0.5)), // 設定容器的四周邊框線條樣式
      ), // 執行相對應的邏輯計算或設定屬性參數
      child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          const Padding(padding: EdgeInsets.symmetric(horizontal: 15), child: Icon(Icons.edit_note, color: Colors.grey)), // 建立間距容器（Padding），用於設定內部邊距
          Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
            child: TextField( // 建立文字輸入框元件（TextField）
              controller: controller, // 執行相對應的邏輯計算或設定屬性參數
              decoration: InputDecoration( // 建立輸入框樣式裝飾（InputDecoration）
                hintText: '例：火腿蛋吐司', // 執行相對應的邏輯計算或設定屬性參數
                hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5)), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                border: InputBorder.none, // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              style: const TextStyle(fontWeight: FontWeight.w500), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
          if (_itemControllers.length > 1) // 執行相對應的邏輯計算或設定屬性參數
            IconButton( // 建立點擊圖示按鈕（IconButton）
              icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger, size: 20), // 設定顏色數值（Color）
              onPressed: () => _removeItem(index), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _showMealPicker() { // 執行相對應的邏輯計算或設定屬性參數
    showModalBottomSheet( // 執行相對應的邏輯計算或設定屬性參數
      context: context, // 執行相對應的邏輯計算或設定屬性參數
      backgroundColor: AppColors.background, // 設定顏色數值（Color）
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), // 建立編譯期常數，優化 Flutter 渲染效能
      builder: (context) => Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        padding: const EdgeInsets.symmetric(vertical: 20), // 設定外邊距或內邊距的數值大小（EdgeInsets）
        child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
          mainAxisSize: MainAxisSize.min, // 執行相對應的邏輯計算或設定屬性參數
          children: _mealOptions.map((m) => ListTile( // 執行相對應的邏輯計算或設定屬性參數
            title: Text(m, textAlign: TextAlign.center, style: TextStyle(fontWeight: _mealType == m ? FontWeight.bold : FontWeight.normal)), // 建立文字顯示元件（Text）
            onTap: () { setState(() => _mealType = m); Navigator.pop(context); }, // 更新狀態數據並通知 UI 重新渲染畫面
          )).toList(), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildPhotoSection() { // 定義用於重複使用的 UI 封裝建構方法
    return GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
      onTap: _pickImage, // 執行相對應的邏輯計算或設定屬性參數
      child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        width: double.infinity, // 執行相對應的邏輯計算或設定屬性參數
        decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
          color: AppColors.background, // 設定顏色數值（Color）
          borderRadius: BorderRadius.circular(20), // 設定容器的圓角弧度半徑大小
          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 10)], // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
        ), // 執行相對應的邏輯計算或設定屬性參數
        clipBehavior: Clip.antiAlias, // 執行相對應的邏輯計算或設定屬性參數
        child: _selectedImage == null || _imageBytes == null // 執行相對應的邏輯計算或設定屬性參數
            ? SizedBox( // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                height: 150, // 執行相對應的邏輯計算或設定屬性參數
                child: Center( // 建立置中對齊元件（Center），將子元件居中顯示
                  child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
                    mainAxisAlignment: MainAxisAlignment.center, // 執行相對應的邏輯計算或設定屬性參數
                    children: [ // 執行相對應的邏輯計算或設定屬性參數
                      Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                        width: 80, height: 70, // 執行相對應的邏輯計算或設定屬性參數
                        decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                          color: AppColors.primary, // 設定顏色數值（Color）
                          borderRadius: BorderRadius.circular(20), // 設定容器的圓角弧度半徑大小
                          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 5, offset: const Offset(0, 2))], // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                        ), // 執行相對應的邏輯計算或設定屬性參數
                        child: const Icon(Icons.camera_alt, color: AppColors.background, size: 30), // 設定顏色數值（Color）
                      ), // 執行相對應的邏輯計算或設定屬性參數
                      const SizedBox(height: 10), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                      const Text('添加照片 (選填)', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
                    ], // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ) // 執行相對應的邏輯計算或設定屬性參數
            : Stack( // 建立層疊佈局元件（Stack），可將多個子元件重疊顯示
                children: [ // 執行相對應的邏輯計算或設定屬性參數
                  Image.memory( // 執行相對應的邏輯計算或設定屬性參數
                    _imageBytes!, // 執行相對應的邏輯計算或設定屬性參數
                    width: double.infinity, // 執行相對應的邏輯計算或設定屬性參數
                    fit: BoxFit.contain, // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  Positioned( // 建立絕對定位元件（Positioned），用於精確設定子元件在 Stack 中的位置
                    right: 10, top: 10, // 執行相對應的邏輯計算或設定屬性參數
                    child: GestureDetector( // 建立手勢偵測器（GestureDetector），用於監聽點擊、拖動等觸控事件
                      onTap: () => setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                        _selectedImage = null; // 執行相對應的邏輯計算或設定屬性參數
                        _imageBytes = null; // 執行相對應的邏輯計算或設定屬性參數
                      }), // 執行相對應的邏輯計算或設定屬性參數
                      child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
                        padding: const EdgeInsets.all(4), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                        decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle), // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                        child: const Icon(Icons.close, color: Colors.white, size: 20), // 設定顏色數值（Color）
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ], // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束
