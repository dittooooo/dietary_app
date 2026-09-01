import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../color/app_colors.dart';
import '../../services/auth_service.dart';
import '../../utils/friendly_error_message.dart';
import '../../utils/profile_value_mapper.dart';
import 'login_page.dart';

/// EditProfilePage 視圖頁面與狀態類別。
class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final bool isMandatoryAdmin;
  final VoidCallback? onSaveSuccess;
  const EditProfilePage({
    super.key, 
    required this.initialData, 
    this.isMandatoryAdmin = false,
    this.onSaveSuccess,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

/// 內部使用的 _EditProfilePageState 元件與狀態處理類別。
class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  
  late AuthService _authService;
  
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _yearController;
  late TextEditingController _monthController;
  late TextEditingController _dayController;
  late TextEditingController _heightController;
  late TextEditingController _weightController;
  
  String _gender = '';
  Set<String> _diseases = {};
  Set<String> _goals = {};

  bool _showTopBanner = false;
  String _topBannerText = '請輸入完整訊息';
  Timer? _bannerTimer;

  final List<String> _genderOptions = ['男', '女'];
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
  final List<String> _goalOptions = ['減脂', '增肌', '養生'];

  bool get _isUserAdmin {
    final role = widget.initialData['user']?['role'] ?? widget.initialData['role'];
    final email = _emailController.text.trim().toLowerCase();
    return widget.isMandatoryAdmin ||
        role == 'ROLE_ADMIN' ||
        role == 'ADMIN' ||
        email == 'admin@gmail.com';
  }

  /// 初始化 Widget 狀態與訂閱生命週期。
  @override
  /// 執行 initState 業務邏輯處理方法。
  void initState() {
    super.initState();
    _authService = AuthService();
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

  /// 向後端服務發送 GET 請求取得最新用戶個人資料。
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

  /// 解析 JSON 個人資料並自動填入各大輸入框 Controller。
  void _populateFieldsFromData(Map<String, dynamic> data) {
    if (data.isEmpty) {
      if (_emailController.text.isEmpty) _loadUserEmail();
      return;
    }
    
    final initialName = (data['nickname'] != null && data['nickname'].toString().trim().isNotEmpty)
        ? data['nickname'].toString().trim()
        : (_isUserAdmin ? '系統管理員' : '');
    if (initialName.isNotEmpty || _nameController.text.isEmpty) {
      _nameController.text = initialName;
    }

    final initialEmail = data['email']?.toString().trim() ?? data['user']?['email']?.toString().trim() ?? '';
    if (initialEmail.isNotEmpty || _emailController.text.isEmpty) {
      _emailController.text = initialEmail;
    }
    _loadUserEmail();

    final gStr = data['gender']?.toString().toUpperCase() ?? '';
    if (gStr == 'FEMALE') {
      _gender = '女';
    } else if (gStr == 'MALE') {
      _gender = '男';
    }

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

  /// 載入本地快取之用戶電子郵件信箱。
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

  /// 銷毀 Widget 狀態與釋放控制器資源。
  @override
  /// 執行 dispose 業務邏輯處理方法。
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

  /// 檢驗修改後之個人資料並發送 PUT 請求更新至後端。
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

    if (yearText.isEmpty || monthText.isEmpty || dayText.isEmpty ||
        yearVal == null || monthVal == null || dayVal == null) {
      _showValidationError('請輸入完整訊息');
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

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

    if (parsedBirthDate.isAfter(today)) {
      _showValidationError('請輸入完整訊息');
      return;
    }

    if (_gender.trim().isEmpty ||
        heightText.isEmpty || heightVal == null || heightVal <= 0 ||
        weightText.isEmpty || weightVal == null || weightVal <= 0 ||
        _diseases.isEmpty ||
        _goals.isEmpty) {
      _showValidationError('請輸入完整訊息');
      return;
    }

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

  /// 觸發頂部警告訊息橫幅彈出。
  void triggerValidationError([String? message]) {
    _showValidationError(message ?? '請輸入完整訊息');
  }

  /// 顯示頂部警告訊息橫幅並設定 2 秒自動隱藏計時器。
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

  /// 彈出對話框供用戶確認，確認後執行帳號註銷刪除流程。
  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確定要註銷帳號嗎？'),
        content: const Text('這將會永久刪除您的所有資料，且無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確認註銷', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

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
  }

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  /// 執行 build 業務邏輯處理方法。
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(widget.isMandatoryAdmin ? '請輸入資訊' : '編輯資料', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: !widget.isMandatoryAdmin,
        leading: widget.isMandatoryAdmin ? null : IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  if (widget.isMandatoryAdmin) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 15),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
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
                  _buildSectionBox([
                    _buildRowItem('暱稱', _nameController, enabled: !_isUserAdmin),
                    _buildRowItem('帳號', _emailController, enabled: false),
                  ]),
                  const SizedBox(height: 15),
                  _buildSectionBox([
                    _buildGenderSelector(),
                    _buildBirthDateRow(),
                    _buildRowItem('身高', _heightController, isNumber: true, suffix: 'cm'),
                    _buildRowItem('體重', _weightController, isNumber: true, suffix: 'kg'),
                    _buildTagSelector('疾病', _diseaseOptions, _diseases),
                    _buildTagSelector('目標', _goalOptions, _goals),
                  ]),
                  const SizedBox(height: 30),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildCustomButton('刪除帳戶', AppColors.danger, isFilled: false, onTap: _deleteAccount),
                        _buildCustomButton('完成修改', AppColors.primary, isFilled: true, onTap: _updateProfile),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

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
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
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
    );
  }

  /// 建立白色圓角背景容器區塊 Widget。
  Widget _buildSectionBox(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 1.95,
            offset: const Offset(0, 0.78),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  /// 建立生日年月日輸入列 Widget。
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
                      hintStyle: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.35), fontSize: 14),
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
                      hintStyle: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.35), fontSize: 14),
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
                      hintStyle: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.35), fontSize: 14),
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

  /// 建立通用單列輸入欄位 Widget。
  Widget _buildRowItem(
    String label, 
    TextEditingController controller, {
    bool enabled = true, 
    bool isNumber = false, 
    String suffix = '', 
    String? hintText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: keyboardType ?? (isNumber ? TextInputType.number : TextInputType.text),
              inputFormatters: inputFormatters,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: enabled ? FontWeight.normal : FontWeight.bold,
                color: enabled ? AppColors.textPrimary : AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: enabled ? (hintText ?? '請輸入') : '',
                hintStyle: TextStyle(
                  color: AppColors.textPrimary.withValues(alpha: 0.35),
                  fontSize: 14,
                ),
                suffixText: suffix,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 建立性別選擇標籤組 Widget。
  Widget _buildGenderSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 60, child: Text('性別', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _genderOptions.map((g) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: ChoiceChip(
                  label: Text(g),
                  selected: _gender == g,
                  onSelected: (val) => setState(() => _gender = g),
                  selectedColor: AppColors.secondary.withValues(alpha: 0.2),
                   labelStyle: TextStyle(
                     color: _gender == g ? AppColors.textPrimary : AppColors.textPrimary.withValues(alpha: 0.5),
                     fontWeight: _gender == g ? FontWeight.bold : FontWeight.normal,
                   ),
                 ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 建立疾病與目標多選標籤列 Widget。
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
                          color: isSelected ? AppColors.textPrimary : AppColors.textPrimary.withValues(alpha: 0.5),
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
                      backgroundColor: AppColors.surface.withValues(alpha: 0.5),
                      selectedColor: AppColors.secondary.withValues(alpha: 0.2),
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
  }

  /// 建立頁面底部自訂樣式操作按鈕 Widget。
  Widget _buildCustomButton(String text, Color color, {bool isFilled = false, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
        decoration: BoxDecoration(
          color: isFilled ? color : AppColors.background,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: isFilled ? color.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.1),
              blurRadius: 3.9,
              offset: const Offset(0, 1.95),
            ),
          ],
          border: isFilled ? null : Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isFilled ? AppColors.background : color,
            fontWeight: FontWeight.bold,
            fontSize: 16
          ),
        ),
      ),
    );
  } // end _buildCustomButton
} // end _EditProfilePageState

/// DateTextInputFormatter 視圖頁面與狀態類別。
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
