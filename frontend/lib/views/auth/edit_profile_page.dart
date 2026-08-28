import 'dart:async';
import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'package:flutter/services.dart'; // 匯入 services.dart 用於 TextInputFormatter
// import 'dart:convert'; // 匯入 dart:convert 元件庫或套件
import 'package:http/http.dart' as http; // 匯入 http.dart 元件庫或套件
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import '../../config/api_config.dart'; // 匯入 api_config.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../services/auth_service.dart'; // 匯入 auth_service.dart 元件庫或套件
import '../../utils/friendly_error_message.dart';
import '../../utils/profile_value_mapper.dart'; // 匯入 ProfileValueMapper
import 'login_page.dart';

class EditProfilePage extends StatefulWidget { // 定義 EditProfilePage 類別，繼承自 StatefulWidget
  final Map<String, dynamic> initialData; // 宣告類別成員或方法內部的區域變數
  final bool isMandatoryAdmin;
  final VoidCallback? onSaveSuccess;
  const EditProfilePage({
    super.key, 
    required this.initialData, 
    this.isMandatoryAdmin = false,
    this.onSaveSuccess,
  }); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<EditProfilePage> createState() => _EditProfilePageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _EditProfilePageState extends State<EditProfilePage> { // 定義 _EditProfilePageState 類別，繼承自 State
  final _formKey = GlobalKey<FormState>(); // 宣告類別成員或方法內部的區域變數
  
  late AuthService _authService; // 宣告類別成員或方法內部的區域變數
  
  late TextEditingController _nameController; // 宣告類別成員或方法內部的區域變數
  late TextEditingController _emailController;
  late TextEditingController _yearController;
  late TextEditingController _monthController;
  late TextEditingController _dayController;
  late TextEditingController _heightController; // 宣告類別成員或方法內部的區域變數
  late TextEditingController _weightController; // 宣告類別成員或方法內部的區域變數
  
  String _gender = ''; // 宣告類別成員或方法內部的區域變數
  Set<String> _diseases = {}; // 執行相對應的邏輯計算或設定屬性參數
  Set<String> _goals = {}; // 執行相對應的邏輯計算或設定屬性參數

  bool _showTopBanner = false;
  String _topBannerText = '請輸入完整訊息';
  Timer? _bannerTimer;

  final List<String> _genderOptions = ['男', '女']; // 宣告類別成員或方法內部的區域變數
  final List<String> _diseaseOptions = [
    '高血壓',
    '高血脂',
    '糖尿病',
    '心血管疾病',
    '慢性腎臟病',
    '腦中風',
    '代謝症候群',
    '痛風',
    '高尿酸血症',
    '胃食道逆流',
    '無疾病',
  ];
  final List<String> _goalOptions = ['減脂', '增肌', '養生']; // 宣告類別成員或方法內部的區域變數

  bool get _isUserAdmin {
    final role = widget.initialData['user']?['role'] ?? widget.initialData['role'];
    final email = _emailController.text.trim().toLowerCase();
    return widget.isMandatoryAdmin ||
        role == 'ROLE_ADMIN' ||
        role == 'ADMIN' ||
        email == 'admin@gmail.com';
  }

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _authService = AuthService(); // 執行相對應的邏輯計算或設定屬性參數
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _yearController = TextEditingController();
    _monthController = TextEditingController();
    _dayController = TextEditingController();
    _heightController = TextEditingController();
    _weightController = TextEditingController();

    _populateFieldsFromData(widget.initialData);
    _fetchProfileFromBackend();
  }

  Future<void> _fetchProfileFromBackend() async {
    try {
      final result = await _authService.getUserProfile();
      if (mounted && result['success'] == true && result['data'] != null) {
        final data = Map<String, dynamic>.from(result['data']);
        setState(() {
          _populateFieldsFromData(data);
        });
      }
    } catch (_) {}
  }

  void _populateFieldsFromData(Map<String, dynamic> data) {
    if (data.isEmpty) {
      if (_emailController.text.isEmpty) _loadUserEmail();
      return;
    }
    
    // 暱稱：若未設定則預設顯示 '系統管理員' 或空
    final initialName = (data['nickname'] != null && data['nickname'].toString().trim().isNotEmpty)
        ? data['nickname'].toString().trim()
        : (_isUserAdmin ? '系統管理員' : '');
    if (initialName.isNotEmpty || _nameController.text.isEmpty) {
      _nameController.text = initialName;
    }

    // 帳號：動態取得 Email (唯讀)
    final initialEmail = data['email']?.toString().trim() ?? data['user']?['email']?.toString().trim() ?? '';
    if (initialEmail.isNotEmpty || _emailController.text.isEmpty) {
      _emailController.text = initialEmail;
    }
    _loadUserEmail();

    // 載入個人資訊 (若 DB 有紀錄則自動填入現有資料)
    final gStr = data['gender']?.toString().toUpperCase() ?? '';
    if (gStr == 'FEMALE') {
      _gender = '女';
    } else if (gStr == 'MALE') {
      _gender = '男';
    }

    // 相容後端所有生日格式 (List JSON, ISO YYYY-MM-DD, 斜線 YYYY/MM/DD, 點號 YYYY.MM.DD, 無分隔符 8 位數, 帶時間 T, 及年齡 age 備用)
    String yearStr = '';
    String monthStr = '';
    String dayStr = '';

    final rawBirthDateData = data['birthDate'] ?? data['birth_date'] ?? data['birthday'] ?? data['dateOfBirth'];
    final rawAge = data['age'] != null ? int.tryParse(data['age'].toString()) : null;

    if (rawBirthDateData is List && rawBirthDateData.length >= 3) {
      yearStr = rawBirthDateData[0].toString().padLeft(4, '0');
      monthStr = rawBirthDateData[1].toString().padLeft(2, '0');
      dayStr = rawBirthDateData[2].toString().padLeft(2, '0');
    } else if (rawBirthDateData != null && rawBirthDateData.toString().trim().isNotEmpty) {
      var birthStr = rawBirthDateData.toString().trim();
      if (birthStr.contains('T')) {
        birthStr = birthStr.split('T')[0];
      }
      birthStr = birthStr.replaceAll('/', '-').replaceAll('.', '-').replaceAll(' ', '');
      if (birthStr.contains('-')) {
        final parts = birthStr.split('-');
        if (parts.length >= 3) {
          yearStr = parts[0].padLeft(4, '0');
          monthStr = parts[1].padLeft(2, '0');
          dayStr = parts[2].padLeft(2, '0');
        }
      } else if (birthStr.length == 8 && RegExp(r'^\d{8}$').hasMatch(birthStr)) {
        yearStr = birthStr.substring(0, 4);
        monthStr = birthStr.substring(4, 6);
        dayStr = birthStr.substring(6, 8);
      }
    }

    if (yearStr.isEmpty && rawAge != null && rawAge > 0) {
      yearStr = (DateTime.now().year - rawAge).toString();
      monthStr = '01';
      dayStr = '01';
    }

    if (yearStr.isNotEmpty) _yearController.text = yearStr;
    if (monthStr.isNotEmpty) _monthController.text = monthStr;
    if (dayStr.isNotEmpty) _dayController.text = dayStr;

    final hVal = data['height'];
    if (hVal != null && (double.tryParse(hVal.toString()) ?? 0) > 0) {
      _heightController.text = hVal.toString();
    }

    final wVal = data['weight'];
    if (wVal != null && (double.tryParse(wVal.toString()) ?? 0) > 0) {
      _weightController.text = wVal.toString();
    }

    if (data['healthConditions'] != null && data['healthConditions'].toString().isNotEmpty) {
      _diseases = ProfileValueMapper.healthConditionsToDisplaySet(data['healthConditions']);
    }

    if (data['dietGoal'] != null && data['dietGoal'].toString().isNotEmpty) {
      _goals = ProfileValueMapper.dietGoalsToDisplaySet(data['dietGoal']);
    }
  }

  Future<void> _loadUserEmail() async {
    if (_emailController.text.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('user_email');
      final emailToSet = (savedEmail != null && savedEmail.isNotEmpty)
          ? savedEmail
          : (widget.isMandatoryAdmin ? 'admin@gmail.com' : '');
      if (emailToSet.isNotEmpty && mounted) {
        setState(() {
          _emailController.text = emailToSet;
        });
      }
    }
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _updateProfile() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final yearText = _yearController.text.trim();
    final monthText = _monthController.text.trim();
    final dayText = _dayController.text.trim();

    final yearVal = int.tryParse(yearText);
    final monthVal = int.tryParse(monthText);
    final dayVal = int.tryParse(dayText);

    final heightText = _heightController.text.trim();
    final weightText = _weightController.text.trim();

    final heightVal = double.tryParse(heightText);
    final weightVal = double.tryParse(weightText);

    // 1. 驗證年月日必填
    if (yearText.isEmpty || monthText.isEmpty || dayText.isEmpty ||
        yearVal == null || monthVal == null || dayVal == null) {
      _showValidationError('請輸入完整訊息');
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 2. 年月日數值與範圍檢查
    if (yearVal < 1900 || yearVal > now.year ||
        monthVal < 1 || monthVal > 12 ||
        dayVal < 1 || dayVal > 31) {
      _showValidationError('請輸入完整訊息');
      return;
    }

    DateTime? parsedBirthDate;
    try {
      parsedBirthDate = DateTime(yearVal, monthVal, dayVal);
      if (parsedBirthDate.year != yearVal || parsedBirthDate.month != monthVal || parsedBirthDate.day != dayVal) {
        _showValidationError('請輸入完整訊息');
        return;
      }
    } catch (_) {
      _showValidationError('請輸入完整訊息');
      return;
    }

    // 3. 前端阻擋超過今天的未來日期
    if (parsedBirthDate.isAfter(today)) {
      _showValidationError('請輸入完整訊息');
      return;
    }

    // 4. 有任何未填寫或未選擇的欄位，跳出籠統通知「請輸入完整訊息」
    if (_gender.trim().isEmpty ||
        heightText.isEmpty || heightVal == null || heightVal <= 0 ||
        weightText.isEmpty || weightVal == null || weightVal <= 0 ||
        _diseases.isEmpty ||
        _goals.isEmpty) {
      _showValidationError('請輸入完整訊息');
      return;
    }

    // 動態計算年齡
    int ageVal = now.year - parsedBirthDate.year;
    if (now.month < parsedBirthDate.month || (now.month == parsedBirthDate.month && now.day < parsedBirthDate.day)) {
      ageVal--;
    }
    if (ageVal < 0) ageVal = 0;

    final formattedBirthDate = "${parsedBirthDate.year.toString().padLeft(4, '0')}-${parsedBirthDate.month.toString().padLeft(2, '0')}-${parsedBirthDate.day.toString().padLeft(2, '0')}";

    try {
      final body = {
        'nickname': _nameController.text.trim(),
        'gender': ProfileValueMapper.genderToApi(_gender),
        'birthDate': formattedBirthDate,
        'age': ageVal,
        'height': heightVal,
        'weight': weightVal,
        'healthConditions': ProfileValueMapper.healthConditionsToApi(_diseases),
        'dietGoal': ProfileValueMapper.firstDietGoalToApi(_goals),
        'petType': ProfileValueMapper.petTypeToApi(widget.initialData['petType']?.toString()),
      };

      final result = await _authService.updateProfile(body);

      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('個人資料儲存成功！'))
          );
          if (widget.onSaveSuccess != null) {
            widget.onSaveSuccess!();
          } else if (Navigator.canPop(context)) {
            Navigator.of(context).pop(true);
          }
        }
      } else {
        final msg = result['message'] ?? '伺服器回應錯誤';
        throw Exception(msg);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(FriendlyErrorMessage.generic))
        );
      }
    }
  }

  void triggerValidationError([String? message]) {
    _showValidationError(message ?? '請輸入完整訊息');
  }

  void _showValidationError([String? message]) {
    _bannerTimer?.cancel();
    setState(() {
      _topBannerText = message ?? '請輸入完整訊息';
      _showTopBanner = true;
    });
    _bannerTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showTopBanner = false;
        });
      }
    });
  }

  Future<void> _deleteAccount() async { // 定義非同步方法（Future），執行耗時操作
    final confirm = await showDialog<bool>( // 宣告類別成員或方法內部的區域變數
      context: context, // 執行相對應的邏輯計算或設定屬性參數
      builder: (ctx) => AlertDialog( // 執行相對應的邏輯計算或設定屬性參數
        title: const Text('確定要註銷帳號嗎？'), // 建立文字顯示元件（Text）
        content: const Text('這將會永久刪除您的所有資料，且無法復原。'), // 建立文字顯示元件（Text）
        actions: [ // 執行相對應的邏輯計算或設定屬性參數
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ), // 導航路由返回：關閉當前頁面並返回上一頁
          TextButton( // 執行相對應的邏輯計算或設定屬性參數
            onPressed: () => Navigator.pop(ctx, true), // 導航路由返回：關閉當前頁面並返回上一頁
            child: const Text('確認註銷', style: TextStyle(color: AppColors.danger)), // 建立文字顯示元件（Text）
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束

    if (confirm != true) return; // 執行相對應的邏輯計算或設定屬性參數

    try {
      final res = await _authService.deleteAccount();

      if (res['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? '帳號已成功註銷。')),
          );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? '註銷帳號失敗，請稍後再試。')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('註銷失敗，請檢查網路連線。')),
        );
      }
    }
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: AppColors.surface, // 設定顏色數值（Color）
      appBar: AppBar( // 設定頂部的導航欄（AppBar）
        title: Text(widget.isMandatoryAdmin ? '請輸入資訊' : '編輯資料', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
        centerTitle: true, // 執行相對應的邏輯計算或設定屬性參數
        backgroundColor: AppColors.background, // 設定顏色數值（Color）
        elevation: 0, // 執行相對應的邏輯計算或設定屬性參數
        automaticallyImplyLeading: !widget.isMandatoryAdmin,
        leading: widget.isMandatoryAdmin ? null : IconButton( // 建立點擊圖示按鈕（IconButton）
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary), // 設定顏色數值（Color）
          onPressed: () => Navigator.pop(context), // 導航路由返回：關閉當前頁面並返回上一頁
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
      body: Stack(
        children: [
          SingleChildScrollView( // 設定頁面的主要內容區域（body）
            padding: const EdgeInsets.all(20.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
            child: Form( // 執行相對應的邏輯計算或設定屬性參數
              key: _formKey, // 執行相對應的邏輯計算或設定屬性參數
              child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
                children: [ // 執行相對應的邏輯計算或設定屬性參數
                  if (widget.isMandatoryAdmin) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 15),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: AppColors.primary),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '請先完成個人資訊設定，儲存後方可繼續操作系統。',
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  _buildSectionBox([ // 執行相對應的邏輯計算或設定屬性參數
                    _buildRowItem('暱稱', _nameController, enabled: !_isUserAdmin), // 管理者權限為唯讀；一般使用者可修改
                    _buildRowItem('帳號', _emailController, enabled: false), // 帳號恆為唯讀
                  ]), // 執行相對應的邏輯計算或設定屬性參數
                  const SizedBox(height: 15), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  _buildSectionBox([ // 執行相對應的邏輯計算或設定屬性參數
                    _buildGenderSelector(), // 執行相對應的邏輯計算或設定屬性參數
                    _buildBirthDateRow(),
                    _buildRowItem('身高', _heightController, isNumber: true, suffix: 'cm'), // 執行相對應的邏輯計算或設定屬性參數
                    _buildRowItem('體重', _weightController, isNumber: true, suffix: 'kg'), // 執行相對應的邏輯計算或設定屬性參數
                    _buildTagSelector('疾病', _diseaseOptions, _diseases), // 執行相對應的邏輯計算或設定屬性參數
                    _buildTagSelector('目標', _goalOptions, _goals), // 執行相對應的邏輯計算或設定屬性參數
                  ]), // 執行相對應的邏輯計算或設定屬性參數
                  const SizedBox(height: 30), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                  if (widget.isMandatoryAdmin) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _updateProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('完成並儲存個人資訊', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ] else ...[
                    Row( // 建立水平排列元件（Row），橫向排列多個子元件
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly, // 執行相對應的邏輯計算或設定屬性參數
                      children: [ // 執行相對應的邏輯計算或設定屬性參數
                        _buildCustomButton('刪除帳戶', AppColors.danger, isFilled: false, onTap: _deleteAccount), // 設定顏色數值（Color）
                        _buildCustomButton('完成修改', AppColors.primary, isFilled: true, onTap: _updateProfile), // 設定顏色數值（Color）
                      ], // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ],
                ], // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數

          // 頂部滑出深灰色通知條 (Top Notification Banner)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            top: _showTopBanner ? 10 : -70,
            left: 15,
            right: 15,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary, // 深灰色 / 深咖啡色背景
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _topBannerText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildBirthDateRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 60, child: Text('生日', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 65,
                  child: TextField(
                    controller: _yearController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      counterText: '',
                      hintText: 'YYYY',
                      hintStyle: TextStyle(color: AppColors.textPrimary.withOpacity(0.35), fontSize: 14),
                    ),
                  ),
                ),
                const Text('年', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 45,
                  child: TextField(
                    controller: _monthController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 2,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      counterText: '',
                      hintText: 'MM',
                      hintStyle: TextStyle(color: AppColors.textPrimary.withOpacity(0.35), fontSize: 14),
                    ),
                  ),
                ),
                const Text('月', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 45,
                  child: TextField(
                    controller: _dayController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 2,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      counterText: '',
                      hintText: 'DD',
                      hintStyle: TextStyle(color: AppColors.textPrimary.withOpacity(0.35), fontSize: 14),
                    ),
                  ),
                ),
                const Text('日', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowItem(
    String label, 
    TextEditingController controller, {
    bool enabled = true, 
    bool isNumber = false, 
    String suffix = '', 
    String? hintText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) { // 定義用於重複使用的 UI 封裝建構方法
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
              keyboardType: keyboardType ?? (isNumber ? TextInputType.number : TextInputType.text), // 執行相對應的邏輯計算或設定屬性參數
              inputFormatters: inputFormatters,
              textAlign: TextAlign.center, // 執行相對應的邏輯計算或設定屬性參數
              style: TextStyle(
                fontSize: 16,
                fontWeight: enabled ? FontWeight.normal : FontWeight.bold,
                color: enabled ? AppColors.textPrimary : AppColors.textPrimary,
              ),
              decoration: InputDecoration( // 建立輸入框樣式裝飾（InputDecoration）
                border: InputBorder.none, // 執行相對應的邏輯計算或設定屬性參數
                disabledBorder: InputBorder.none,
                hintText: enabled ? (hintText ?? '請輸入') : '', // 執行相對應的邏輯計算或設定屬性參數
                hintStyle: TextStyle(
                  color: AppColors.textPrimary.withOpacity(0.35),
                  fontSize: 14,
                ),
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

  Widget _buildTagSelector(String label, List<String> options, Set<String> selection) {
    final sortedOptions = List<String>.from(options);
    sortedOptions.sort((a, b) {
      final aSelected = selection.contains(a);
      final bSelected = selection.contains(b);
      if (aSelected && !bSelected) return -1;
      if (!aSelected && bSelected) return 1;
      return options.indexOf(a).compareTo(options.indexOf(b));
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: sortedOptions.map((opt) {
                  final isSelected = selection.contains(opt);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      label: Text(
                        opt,
                        style: TextStyle(
                          color: isSelected ? AppColors.textPrimary : AppColors.textPrimary.withOpacity(0.5),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() {
                          if (label == '疾病') {
                            if (opt == '無疾病') {
                              if (val) {
                                selection.clear();
                                selection.add('無疾病');
                              } else {
                                selection.remove('無疾病');
                              }
                            } else {
                              if (val) {
                                selection.remove('無疾病');
                                selection.add(opt);
                              } else {
                                selection.remove(opt);
                              }
                            }
                          } else if (label == '目標') {
                            if (val) {
                              selection.clear();
                              selection.add(opt);
                            } else if (selection.length > 1) {
                              selection.remove(opt);
                            }
                          } else {
                            if (val) {
                              selection.add(opt);
                            } else {
                              selection.remove(opt);
                            }
                          }
                        });
                      },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                      showCheckmark: false,
                      backgroundColor: AppColors.surface.withOpacity(0.5),
                      selectedColor: AppColors.secondary.withOpacity(0.2),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
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
  } // end _buildCustomButton
} // end _EditProfilePageState

class DateTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (text.length > 8) text = text.substring(0, 8);

    var formatted = '';
    for (int i = 0; i < text.length; i++) {
      if (i == 4 || i == 6) {
        formatted += '-';
      }
      formatted += text[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
