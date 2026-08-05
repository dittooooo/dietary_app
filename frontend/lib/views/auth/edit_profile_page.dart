import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'dart:convert'; // 匯入 dart:convert 元件庫或套件
import 'package:http/http.dart' as http; // 匯入 http.dart 元件庫或套件
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import '../../config/api_config.dart'; // 匯入 api_config.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../services/auth_service.dart'; // 匯入 auth_service.dart 元件庫或套件
import './login_page.dart';  // 匯入 login_page.dart 元件庫或套件

class EditProfilePage extends StatefulWidget { // 定義 EditProfilePage 類別，繼承自 StatefulWidget
  final Map<String, dynamic> initialData; // 宣告類別成員或方法內部的區域變數
  const EditProfilePage({super.key, required this.initialData}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<EditProfilePage> createState() => _EditProfilePageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _EditProfilePageState extends State<EditProfilePage> { // 定義 _EditProfilePageState 類別，繼承自 State
  final _formKey = GlobalKey<FormState>(); // 宣告類別成員或方法內部的區域變數
  
  late AuthService _authService; // 宣告類別成員或方法內部的區域變數
  
  late TextEditingController _nameController; // 宣告類別成員或方法內部的區域變數
  late TextEditingController _ageController; // 宣告類別成員或方法內部的區域變數
  late TextEditingController _heightController; // 宣告類別成員或方法內部的區域變數
  late TextEditingController _weightController; // 宣告類別成員或方法內部的區域變數
  
  String _gender = ''; // 宣告類別成員或方法內部的區域變數
  Set<String> _diseases = {}; // 執行相對應的邏輯計算或設定屬性參數
  Set<String> _goals = {}; // 執行相對應的邏輯計算或設定屬性參數

  final List<String> _genderOptions = ['男', '女']; // 宣告類別成員或方法內部的區域變數
  final List<String> _diseaseOptions = ['糖尿病', '高血壓', '無疾病']; // 宣告類別成員或方法內部的區域變數
  final List<String> _goalOptions = ['減脂', '增肌', '養生']; // 宣告類別成員或方法內部的區域變數

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _authService = AuthService(); // 執行相對應的邏輯計算或設定屬性參數
    final data = widget.initialData; // 宣告類別成員或方法內部的區域變數
    _nameController = TextEditingController(text: data['nickname'] ?? ''); // 執行相對應的邏輯計算或設定屬性參數
    _ageController = TextEditingController(text: data['age']?.toString() ?? ''); // 執行相對應的邏輯計算或設定屬性參數
    _heightController = TextEditingController(text: data['height']?.toString() ?? ''); // 執行相對應的邏輯計算或設定屬性參數
    _weightController = TextEditingController(text: data['weight']?.toString() ?? ''); // 執行相對應的邏輯計算或設定屬性參數
    _gender = data['gender'] ?? '男'; // 執行相對應的邏輯計算或設定屬性參數
    
    // 解析疾病與目標 (相容多種後端命名與格式)
    var healthData = data['healthConditions'] ?? data['health_conditions']; // 執行相對應的邏輯計算或設定屬性參數
    if (healthData != null) { // 執行相對應的邏輯計算或設定屬性參數
      if (healthData is String && healthData.isNotEmpty) { // 執行相對應的邏輯計算或設定屬性參數
        _diseases = healthData.split(RegExp(r'[,\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet(); // 執行相對應的邏輯計算或設定屬性參數
      } else if (healthData is List) { // 執行相對應的邏輯計算或設定屬性參數
        _diseases = Set<String>.from(healthData); // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
    
    var goalData = data['dietGoal'] ?? data['diet_goal']; // 執行相對應的邏輯計算或設定屬性參數
    if (goalData != null) { // 執行相對應的邏輯計算或設定屬性參數
      if (goalData is String && goalData.isNotEmpty) { // 執行相對應的邏輯計算或設定屬性參數
        _goals = goalData.split(RegExp(r'[,\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet(); // 執行相對應的邏輯計算或設定屬性參數
      } else if (goalData is List) { // 執行相對應的邏輯計算或設定屬性參數
        _goals = Set<String>.from(goalData); // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Future<void> _updateProfile() async { // 定義非同步方法（Future），執行耗時操作
    if (!_formKey.currentState!.validate()) return; // 執行相對應的邏輯計算或設定屬性參數

    try { // 執行相對應的邏輯計算或設定屬性參數
      final body = { // 宣告類別成員或方法內部的區域變數
        'nickname': _nameController.text.trim(), // 執行相對應的邏輯計算或設定屬性參數
        'gender': _gender, // 執行相對應的邏輯計算或設定屬性參數
        'age': int.tryParse(_ageController.text) ?? 0, // 執行相對應的邏輯計算或設定屬性參數
        'height': double.tryParse(_heightController.text) ?? 0.0, // 執行相對應的邏輯計算或設定屬性參數
        'weight': double.tryParse(_weightController.text) ?? 0.0, // 執行相對應的邏輯計算或設定屬性參數
        'healthConditions': _diseases.toList(), // 執行相對應的邏輯計算或設定屬性參數
        'dietGoal': _goals.join(', '), // 執行相對應的邏輯計算或設定屬性參數
        'petType': widget.initialData['petType'] ?? '狗兒', // 執行相對應的邏輯計算或設定屬性參數
      }; // 執行相對應的邏輯計算或設定屬性參數

      final result = await _authService.updateProfile(body); // 宣告類別成員或方法內部的區域變數

      if (result['success'] == true) { // 執行相對應的邏輯計算或設定屬性參數
        if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
          ScaffoldMessenger.of(context).showSnackBar( // 執行相對應的邏輯計算或設定屬性參數
            const SnackBar(content: Text('個人資料修改成功！')) // 建立文字顯示元件（Text）
          ); // 程式碼區塊或元件結構結束
          Navigator.pop(context, true); // 導航路由返回：關閉當前頁面並返回上一頁
        } // 程式碼區塊或元件結構結束
      } else { // 程式碼區塊或元件結構結束
        throw Exception(result['message'] ?? 'Server returned error'); // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    } catch (e) { // 執行相對應的邏輯計算或設定屬性參數
      if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
        ScaffoldMessenger.of(context).showSnackBar( // 執行相對應的邏輯計算或設定屬性參數
          SnackBar(content: Text('保存失敗: $e')) // 建立文字顯示元件（Text）
        ); // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Future<void> _deleteAccount() async { // 定義非同步方法（Future），執行耗時操作
    final confirm = await showDialog<bool>( // 宣告類別成員或方法內部的區域變數
      context: context, // 執行相對應的邏輯計算或設定屬性參數
      builder: (ctx) => AlertDialog( // 執行相對應的邏輯計算或設定屬性參數
        title: const Text('確定要註銷帳號嗎？'), // 建立文字顯示元件（Text）
        content: const Text('這將會永久刪除您的所有資料，且無法復原。'), // 建立文字顯示元件（Text）
        actions: [ // 執行相對應的邏輯計算或設定屬性參數
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(color: AppColors.textSecondary))), // 導航路由返回：關閉當前頁面並返回上一頁
          TextButton( // 執行相對應的邏輯計算或設定屬性參數
            onPressed: () => Navigator.pop(ctx, true), // 導航路由返回：關閉當前頁面並返回上一頁
            child: const Text('確認註銷', style: TextStyle(color: AppColors.danger)), // 建立文字顯示元件（Text）
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束

    if (confirm != true) return; // 執行相對應的邏輯計算或設定屬性參數

    try { // 執行相對應的邏輯計算或設定屬性參數
      final prefs = await SharedPreferences.getInstance(); // 宣告類別成員或方法內部的區域變數
      final token = prefs.getString('jwt_token'); // 宣告類別成員或方法內部的區域變數

      final response = await http.delete( // 宣告類別成員或方法內部的區域變數
        Uri.parse('${ApiConfig.baseUrl}/user/account'), // 執行相對應的邏輯計算或設定屬性參數
        headers: { // 執行相對應的邏輯計算或設定屬性參數
          'Authorization': 'Bearer $token', // 執行相對應的邏輯計算或設定屬性參數
        }, // 程式碼區塊或元件結構結束
      ); // 程式碼區塊或元件結構結束

      if (response.statusCode == 200) { // 執行相對應的邏輯計算或設定屬性參數
        // ... (success logic)
      } else if (response.statusCode == 404 || response.statusCode == 405) { // 執行相對應的邏輯計算或設定屬性參數
        // 後端未實作時的補償說明 (前端輔助)
        if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
          ScaffoldMessenger.of(context).showSnackBar( // 執行相對應的邏輯計算或設定屬性參數
            const SnackBar(content: Text('目前後端暫不支援註銷功能，請聯繫管理員。')) // 建立文字顯示元件（Text）
          ); // 程式碼區塊或元件結構結束
        } // 程式碼區塊或元件結構結束
      } else { // 程式碼區塊或元件結構結束
        throw Exception('註銷失敗，請稍後再試'); // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    } catch (e) { // 執行相對應的邏輯計算或設定屬性參數
      if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
        ScaffoldMessenger.of(context).showSnackBar( // 執行相對應的邏輯計算或設定屬性參數
          const SnackBar(content: Text('目前後端尚未開放註銷功能。')) // 建立文字顯示元件（Text）
        ); // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: AppColors.surface, // 設定顏色數值（Color）
      appBar: AppBar( // 設定頂部的導航欄（AppBar）
        title: const Text('編輯資料', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
        centerTitle: true, // 執行相對應的邏輯計算或設定屬性參數
        backgroundColor: AppColors.background, // 設定顏色數值（Color）
        elevation: 0, // 執行相對應的邏輯計算或設定屬性參數
        leading: IconButton( // 建立點擊圖示按鈕（IconButton）
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary), // 設定顏色數值（Color）
          onPressed: () => Navigator.pop(context), // 導航路由返回：關閉當前頁面並返回上一頁
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
      body: SingleChildScrollView( // 設定頁面的主要內容區域（body）
        padding: const EdgeInsets.all(20.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
        child: Form( // 執行相對應的邏輯計算或設定屬性參數
          key: _formKey, // 執行相對應的邏輯計算或設定屬性參數
          child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
            children: [ // 執行相對應的邏輯計算或設定屬性參數
              _buildSectionBox([ // 執行相對應的邏輯計算或設定屬性參數
                _buildRowItem('暱稱', _nameController), // 執行相對應的邏輯計算或設定屬性參數
                _buildRowItem('帳號', TextEditingController(text: widget.initialData['email'] ?? ''), enabled: false), // 執行相對應的邏輯計算或設定屬性參數
              ]), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              _buildSectionBox([ // 執行相對應的邏輯計算或設定屬性參數
                _buildGenderSelector(), // 執行相對應的邏輯計算或設定屬性參數
                _buildRowItem('年齡', _ageController, isNumber: true), // 執行相對應的邏輯計算或設定屬性參數
                _buildRowItem('身高', _heightController, isNumber: true, suffix: 'cm'), // 執行相對應的邏輯計算或設定屬性參數
                _buildRowItem('體重', _weightController, isNumber: true, suffix: 'kg'), // 執行相對應的邏輯計算或設定屬性參數
                _buildTagSelector('疾病', _diseaseOptions, _diseases), // 執行相對應的邏輯計算或設定屬性參數
                _buildTagSelector('目標', _goalOptions, _goals), // 執行相對應的邏輯計算或設定屬性參數
              ]), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(height: 30), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              Row( // 建立水平排列元件（Row），橫向排列多個子元件
                mainAxisAlignment: MainAxisAlignment.spaceEvenly, // 執行相對應的邏輯計算或設定屬性參數
                children: [ // 執行相對應的邏輯計算或設定屬性參數
                  _buildCustomButton('刪除帳戶', AppColors.danger, isFilled: false, onTap: _deleteAccount), // 設定顏色數值（Color）
                  _buildCustomButton('完成修改', AppColors.primary, isFilled: true, onTap: _updateProfile), // 設定顏色數值（Color）
                ], // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ], // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildSectionBox(List<Widget> children) { // 定義用於重複使用的 UI 封裝建構方法
    return Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
        color: AppColors.background, // 設定顏色數值（Color）
        borderRadius: BorderRadius.circular(15), // 設定容器的圓角弧度半徑大小
        boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
          BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
            color: AppColors.primary.withOpacity(0.05), // 設定顏色數值（Color）
            blurRadius: 1.95, // 執行相對應的邏輯計算或設定屬性參數
            offset: const Offset(0, 0.78), // 建立編譯期常數，優化 Flutter 渲染效能
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
      child: Column(children: children), // 建立垂直排列元件（Column），縱向排列多個子元件
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildRowItem(String label, TextEditingController controller, {bool enabled = true, bool isNumber = false, String suffix = ''}) { // 定義用於重複使用的 UI 封裝建構方法
    return Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), // 設定外邊距或內邊距的數值大小（EdgeInsets）
      decoration: const BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
        border: Border(bottom: BorderSide(color: AppColors.border)), // 設定顏色數值（Color）
      ), // 執行相對應的邏輯計算或設定屬性參數
      child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          SizedBox(width: 60, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
          Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
            child: TextField( // 建立文字輸入框元件（TextField）
              controller: controller, // 執行相對應的邏輯計算或設定屬性參數
              enabled: enabled, // 執行相對應的邏輯計算或設定屬性參數
              keyboardType: isNumber ? TextInputType.number : TextInputType.text, // 執行相對應的邏輯計算或設定屬性參數
              textAlign: TextAlign.center, // 執行相對應的邏輯計算或設定屬性參數
              decoration: InputDecoration( // 建立輸入框樣式裝飾（InputDecoration）
                border: InputBorder.none, // 執行相對應的邏輯計算或設定屬性參數
                hintText: '請輸入', // 執行相對應的邏輯計算或設定屬性參數
                suffixText: suffix, // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildGenderSelector() { // 定義用於重複使用的 UI 封裝建構方法
    return Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12), // 設定外邊距或內邊距的數值大小（EdgeInsets）
      decoration: const BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
        border: Border(bottom: BorderSide(color: AppColors.border)), // 設定顏色數值（Color）
      ), // 執行相對應的邏輯計算或設定屬性參數
      child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          const SizedBox(width: 60, child: Text('性別', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
          Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
            child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
              mainAxisAlignment: MainAxisAlignment.center, // 執行相對應的邏輯計算或設定屬性參數
              children: _genderOptions.map((g) => Padding( // 建立間距容器（Padding），用於設定內部邊距
                padding: const EdgeInsets.symmetric(horizontal: 10), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                child: ChoiceChip( // 執行相對應的邏輯計算或設定屬性參數
                  label: Text(g), // 建立文字顯示元件（Text）
                  selected: _gender == g, // 執行相對應的邏輯計算或設定屬性參數
                  onSelected: (val) => setState(() => _gender = g), // 更新狀態數據並通知 UI 重新渲染畫面
                  selectedColor: AppColors.secondary.withOpacity(0.2), // 設定顏色數值（Color）
                   labelStyle: TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                     color: _gender == g ? AppColors.textPrimary : AppColors.textPrimary.withOpacity(0.5), // 設定顏色數值（Color）
                     fontWeight: _gender == g ? FontWeight.bold : FontWeight.normal, // 執行相對應的邏輯計算或設定屬性參數
                   ), // 執行相對應的邏輯計算或設定屬性參數
                 ), // 執行相對應的邏輯計算或設定屬性參數
              )).toList(), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildTagSelector(String label, List<String> options, Set<String> selection) { // 定義用於重複使用的 UI 封裝建構方法
    return Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), // 設定外邊距或內邊距的數值大小（EdgeInsets）
      decoration: const BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
        border: Border(bottom: BorderSide(color: AppColors.border)), // 設定顏色數值（Color）
      ), // 執行相對應的邏輯計算或設定屬性參數
      child: Row( // 建立水平排列元件（Row），橫向排列多個子元件
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          SizedBox(width: 60, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
          Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
            child: Wrap( // 執行相對應的邏輯計算或設定屬性參數
              spacing: 8, // 執行相對應的邏輯計算或設定屬性參數
              alignment: WrapAlignment.center, // 執行相對應的邏輯計算或設定屬性參數
              children: options.map((opt) { // 執行相對應的邏輯計算或設定屬性參數
                final isSelected = selection.contains(opt); // 宣告類別成員或方法內部的區域變數
                 return FilterChip( // 回傳建構完成的元件或方法計算結果
                   label: Text(opt, style: TextStyle(color: isSelected ? AppColors.textPrimary : AppColors.textPrimary.withOpacity(0.5))), // 建立文字顯示元件（Text）
                   selected: isSelected, // 執行相對應的邏輯計算或設定屬性參數
                  onSelected: (val) { // 執行相對應的邏輯計算或設定屬性參數
                    setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
                      if (label == '疾病') { // 執行相對應的邏輯計算或設定屬性參數
                        if (opt == '無疾病') { // 執行相對應的邏輯計算或設定屬性參數
                          if (val) { // 執行相對應的邏輯計算或設定屬性參數
                            selection.clear(); // 執行相對應的邏輯計算或設定屬性參數
                            selection.add('無疾病'); // 執行相對應的邏輯計算或設定屬性參數
                          } else { // 程式碼區塊或元件結構結束
                            selection.remove('無疾病'); // 執行相對應的邏輯計算或設定屬性參數
                          } // 程式碼區塊或元件結構結束
                        } else { // 程式碼區塊或元件結構結束
                          if (val) { // 執行相對應的邏輯計算或設定屬性參數
                            selection.remove('無疾病'); // 執行相對應的邏輯計算或設定屬性參數
                            selection.add(opt); // 執行相對應的邏輯計算或設定屬性參數
                          } else { // 程式碼區塊或元件結構結束
                            selection.remove(opt); // 執行相對應的邏輯計算或設定屬性參數
                          } // 程式碼區塊或元件結構結束
                        } // 程式碼區塊或元件結構結束
                      } else { // 程式碼區塊或元件結構結束
                        // 目標選項維持原本的複選邏輯
                        if (val) { // 執行相對應的邏輯計算或設定屬性參數
                          selection.add(opt); // 執行相對應的邏輯計算或設定屬性參數
                        } else { // 程式碼區塊或元件結構結束
                          selection.remove(opt); // 執行相對應的邏輯計算或設定屬性參數
                        } // 程式碼區塊或元件結構結束
                      } // 程式碼區塊或元件結構結束
                    }); // 程式碼區塊或元件結構結束
                  }, // 程式碼區塊或元件結構結束
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none), // 設定容器的圓角弧度半徑大小
                  showCheckmark: false, // 執行相對應的邏輯計算或設定屬性參數
                   backgroundColor: AppColors.surface.withOpacity(0.5), // 設定顏色數值（Color）
                   selectedColor: AppColors.secondary.withOpacity(0.2), // 設定顏色數值（Color）
                 ); // 程式碼區塊或元件結構結束
              }).toList(), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
          const Icon(Icons.chevron_right, color: Colors.grey), // 設定顏色數值（Color）
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  Widget _buildCustomButton(String text, Color color, {bool isFilled = false, required VoidCallback onTap}) { // 定義用於重複使用的 UI 封裝建構方法
    return InkWell( // 回傳建構完成的元件或方法計算結果
      onTap: onTap, // 執行相對應的邏輯計算或設定屬性參數
      child: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12), // 設定外邊距或內邊距的數值大小（EdgeInsets）
        decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
          color: isFilled ? color : AppColors.background, // 設定顏色數值（Color）
          borderRadius: BorderRadius.circular(15), // 設定容器的圓角弧度半徑大小
          boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
            BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
              color: isFilled ? color.withOpacity(0.3) : Colors.black.withOpacity(0.1), // 設定顏色數值（Color）
              blurRadius: 3.9, // 執行相對應的邏輯計算或設定屬性參數
              offset: const Offset(0, 1.95), // 建立編譯期常數，優化 Flutter 渲染效能
            ), // 執行相對應的邏輯計算或設定屬性參數
          ], // 執行相對應的邏輯計算或設定屬性參數
          border: isFilled ? null : Border.all(color: color.withOpacity(0.5)), // 設定容器的四周邊框線條樣式
        ), // 執行相對應的邏輯計算或設定屬性參數
        child: Text( // 建立文字顯示元件（Text）
          text, // 執行相對應的邏輯計算或設定屬性參數
          style: TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
            color: isFilled ? AppColors.background : color, // 設定顏色數值（Color）
            fontWeight: FontWeight.bold,  // 執行相對應的邏輯計算或設定屬性參數
            fontSize: 16 // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束
