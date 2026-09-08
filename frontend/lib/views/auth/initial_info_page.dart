import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home/home_page.dart';
import 'login_page.dart';
import '../../color/app_colors.dart';
import 'model_viewer_web_stub.dart'
    if (dart.library.html) 'model_viewer_web_impl.dart';
import '../../services/auth_service.dart';
import '../../utils/friendly_error_message.dart';
import '../../utils/profile_value_mapper.dart';

/// 首次登入健康問卷與基本身體資料（暱稱、性別、生日、身高、體重、疾病史、飲食目標）收集頁面。
class InitialInfoPage extends StatefulWidget {
  const InitialInfoPage({super.key});

  @override
  State<InitialInfoPage> createState() => _InitialInfoPageState();
}

/// 內部使用的 _InitialInfoPageState 元件與狀態處理類別。
class _InitialInfoPageState extends State<InitialInfoPage>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _pacmanController;
  late AnimationController _peelController;
  int _currentPage = 0;

  bool _isAnimatingPage = false;
  bool _isBackAnimating = false;
  int _animatingFromPage = 0;
  int _animatingToPage = 0;

  static const TextStyle _titleStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    fontFamily: 'Roboto',
  );

  static const TextStyle _inputTextStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
  );

  static const TextStyle _buttonTextStyle = TextStyle(
    fontSize: 16,

    fontWeight: FontWeight.bold,
    color: Colors.black,
  );

  final Map<int, String> _pageErrors = {};

  String _name = '';
  String _gender = '';
  String _age = '26';
  String _height = '';
  String _weight = '';

  int? _selectedBirthYear;
  int? _selectedBirthMonth;
  int? _selectedBirthDay;

  String get _birthDateString =>
      (_selectedBirthYear != null &&
          _selectedBirthMonth != null &&
          _selectedBirthDay != null)
      ? '${_selectedBirthYear!.toString().padLeft(4, '0')}-${_selectedBirthMonth!.toString().padLeft(2, '0')}-${_selectedBirthDay!.toString().padLeft(2, '0')}'
      : '';

  int get _calculatedAge {
    if (_selectedBirthYear == null ||
        _selectedBirthMonth == null ||
        _selectedBirthDay == null) {
      return 0;
    }
    final now = DateTime.now();
    int age = now.year - _selectedBirthYear!;
    if (now.month < _selectedBirthMonth! ||
        (now.month == _selectedBirthMonth! && now.day < _selectedBirthDay!)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }

  /// 依據西元年份與月份，計算並傳回該月份之實際總天數（自動處理閏年 29 天）。
  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  late TextEditingController _nameController;
  late TextEditingController _ageController;
  late TextEditingController _heightController;
  late TextEditingController _weightController;
  Set<String> _diseases = {};
  Set<String> _goals = {};

  static const String _defaultPetType = '米粒(Mili)';
  bool _isSubmitting = false;

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

  /// 初始化 Widget 狀態與訂閱生命週期。
  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pacmanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);

    _peelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _peelController.addStatusListener((status) {
      if (_isAnimatingPage) {
        if ((!_isBackAnimating && status == AnimationStatus.completed) ||
            (_isBackAnimating && status == AnimationStatus.dismissed)) {
          setState(() {
            _isAnimatingPage = false;
            _pageController.jumpToPage(_animatingToPage);
          });
          _peelController.reset();
        }
      }
    });

    _nameController = TextEditingController(text: _name);
    _ageController = TextEditingController(text: _age);
    _heightController = TextEditingController(text: _height);
    _weightController = TextEditingController(text: _weight);
    _checkAdminRedirect();
  }

  /// 檢查快取之帳號權限，若為管理者則直接自動重導向至管理者主頁。
  Future<void> _checkAdminRedirect() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedRole = prefs.getString('user_role');
    final bool isAdmin = cachedRole == 'ROLE_ADMIN';
    if (isAdmin && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    }
  }

  /// 清除本地會話憑證與快取資料，並強行退回登入頁面。
  Future<void> _logoutToLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AuthService.accessTokenKey);
    await prefs.remove(AuthService.refreshTokenKey);
    await prefs.remove(AuthService.needsOnboardingKey);
    await prefs.remove('user_role');
    await prefs.remove('user_email');
    await prefs.remove('user_avatar_url');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  /// 銷毀 Widget 狀態與釋放控制器資源。
  @override
  void dispose() {
    _pageController.dispose();
    _pacmanController.dispose();
    _peelController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  /// 處理問卷「下一步」動作：執行欄位資料校驗、觸發撕紙翻頁動畫並切換頁碼。
  void _nextPage() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_canProceed()) {
      final msg = _validationMessage();
      debugPrint('校驗失敗: $msg');
      setState(() {
        _pageErrors[_currentPage] = msg;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    if (_currentPage < 6) {
      final targetPage = _currentPage + 1;
      debugPrint('啟動自訂撕紙翻頁動畫 (前進) -> 從 $_currentPage 到 $targetPage');
      if (_isAnimatingPage) return;
      setState(() {
        _isAnimatingPage = true;
        _isBackAnimating = false;
        _animatingFromPage = _currentPage;
        _animatingToPage = targetPage;
        _currentPage = targetPage;
        _peelController.value = 0.0;
      });
      _pageController.jumpToPage(targetPage);
      _peelController.forward();
    } else {
      debugPrint('已在最後一頁，啟動完成設定流程...');
      _completeSetup();
    }
  }

  /// 處理問卷「上一步」動作：觸發倒放撕紙動畫並返回上一頁面。
  void _previousPage() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_currentPage > 0) {
      final targetPage = _currentPage - 1;
      debugPrint('啟動自訂倒放撕紙動畫 (返回) -> 從 $_currentPage 到 $targetPage');
      if (_isAnimatingPage) return;
      setState(() {
        _isAnimatingPage = true;
        _isBackAnimating = true;
        _animatingFromPage = _currentPage;
        _animatingToPage = targetPage;
        _currentPage = targetPage;
        _peelController.value = 1.0;
      });
      _peelController.reverse();
    }
  }

  /// 判斷傳入之字串是否可解析為有效之數值。
  bool _isNumeric(String? s) {
    if (s == null || s.trim().isEmpty) return false;
    return double.tryParse(s.trim()) != null;
  }

  /// 檢查當前步驟頁面之必填欄位是否已完成輸入。
  bool _canProceed() {
    switch (_currentPage) {
      case 0:
        return _name.trim().isNotEmpty;
      case 1:
        return _gender.isNotEmpty;
      case 2:
        return _selectedBirthYear != null &&
            _selectedBirthMonth != null &&
            _selectedBirthDay != null;
      case 3:
        return _isNumeric(_height) && _isNumeric(_weight);
      case 4:
        return _diseases.isNotEmpty;
      case 5:
        return _goals.isNotEmpty;
      case 6:
        return true;
      default:
        return true;
    }
  }

  /// 當前步驟驗證失敗時，取得對應之白話錯誤提示字串。
  String _validationMessage() {
    switch (_currentPage) {
      case 0:
        return '請輸入您的名字';
      case 1:
        return '請選擇性別';
      case 2:
        return '請選擇正確的生日日期';
      case 3:
        if (_height.trim().isEmpty || _weight.trim().isEmpty) return '請輸入身高與體重';
        if (!_isNumeric(_height)) return '身高必須為數字';
        if (!_isNumeric(_weight)) return '體重必須為數字';
        return '請輸入正確的身高與體重';
      case 4:
        return '請選擇是否有特殊疾病';
      case 5:
        return '請選擇一個飲食目標';
      default:
        return '請完成本頁內容';
    }
  }

  /// 封裝問卷收集之用戶身體與目標資料，並發送 API 提交至後端服務。
  Future<void> _completeSetup() async {
    if (_isSubmitting) return;

    debugPrint('開始啟動提交流程...');
    setState(() => _isSubmitting = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在連線伺服器，請稍候...'),
          duration: Duration(milliseconds: 1500),
        ),
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      String apiGender = 'MALE';
      if (_gender == '女' || _gender.toUpperCase() == 'FEMALE') {
        apiGender = 'FEMALE';
      } else if (_gender == '男' || _gender.toUpperCase() == 'MALE') {
        apiGender = 'MALE';
      }

      final Map<String, dynamic> onboardingData = {
        'nickname': _name.trim(),
        'gender': apiGender,
        'birthDate': _birthDateString,
        'age': _calculatedAge,
        'height': double.tryParse(_height) ?? 170.0,
        'weight': double.tryParse(_weight) ?? 60.0,
        'healthConditions': ProfileValueMapper.healthConditionsToApi(_diseases),
        'dietGoal': ProfileValueMapper.firstDietGoalToApi(_goals),
        'petType': ProfileValueMapper.petTypeToApi(_defaultPetType),
      };

      // AuthService 會帶入目前登入帳號的 token；不可直接使用可能殘留
      // 上一個帳號 token 的共用 ApiClient。
      final result = await AuthService()
          .updateProfile(onboardingData)
          .timeout(const Duration(seconds: 15));

      if (result['success'] == true) {
        await prefs.setBool(AuthService.needsOnboardingKey, false);
        await prefs.setString('user_nickname', _name);
        await prefs.setString('user_pet_type', _defaultPetType);
        if (mounted) {
          debugPrint('提交成功，切換至首頁');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        }
      } else {
        final errorMsg = result['message'] ?? '設定失敗';
        throw Exception(errorMsg);
      }
    } catch (_) {
      debugPrint('提交健康資料失敗');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(FriendlyErrorMessage.generic)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        body: Container(
          color: AppColors.surface,
          child: Stack(
            children: [
              Positioned(
                top: topPadding + 10,
                right: 20,
                child: GestureDetector(
                  onTap: _logoutToLogin,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primary),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.logout, size: 16, color: AppColors.primary),
                        SizedBox(width: 4),
                        Text(
                          '返回登入',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: Listenable.merge([
                  _pageController,
                  _pacmanController,
                ]),
                builder: (context, child) {
                  return CustomPaint(
                    painter: HandDrawnNotebookPainter(
                      scrollProgress: _pageController.hasClients
                          ? (_pageController.page ?? 0)
                          : 0,
                      mouthProgress: _pacmanController.value,
                      topPadding: topPadding,
                      bottomPadding: bottomPadding,
                    ),
                    size: Size.infinite,
                  );
                },
              ),
              PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                pageSnapping: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 7,
                itemBuilder: (context, index) {
                  return _buildPageByIndex(
                    index,
                    hideNavButtons: _isAnimatingPage,
                  );
                },
              ),
              if (_isAnimatingPage)
                AnimatedBuilder(
                  animation: _peelController,
                  builder: (context, child) {
                    final progress = _peelController.value;
                    return Stack(
                      children: [
                        if (_isBackAnimating) ...[
                          _buildPageByIndex(
                            _animatingFromPage,
                            hideNavButtons: true,
                          ),
                          ClipPath(
                            clipper: PagePeelClipper(progress: progress),
                            child: _buildPageByIndex(
                              _animatingToPage,
                              hideNavButtons: false,
                            ),
                          ),
                        ] else ...[
                          _buildPageByIndex(
                            _animatingToPage,
                            hideNavButtons: true,
                          ),
                          ClipPath(
                            clipper: PagePeelClipper(progress: progress),
                            child: _buildPageByIndex(
                              _animatingFromPage,
                              hideNavButtons: false,
                            ),
                          ),
                        ],
                        CustomPaint(
                          painter: PageFlipPainter(progress: progress),
                          size: Size.infinite,
                        ),
                      ],
                    );
                  },
                ),

              AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  if (_pageController.positions.isEmpty) {
                    return Container();
                  }

                  double pageValue =
                      _pageController.page ?? _currentPage.toDouble();

                  if ((pageValue - pageValue.floor()).abs() > 0.01 &&
                      (pageValue - pageValue.floor()).abs() < 0.99) {
                    return CustomPaint(
                      painter: PageFlipPainter(
                        progress: pageValue - pageValue.floor(),
                      ),
                      size: Size.infinite,
                    );
                  }

                  return Container();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 建立問卷步驟頁面之通用卡片容器與佈局架構。
  Widget _buildPageContainer({
    required int pageIndex,
    required String title,
    required Widget content,
    bool scrollable = true,
    bool hideNavButtons = false,
  }) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        40,
        140 + topPadding,
        40,
        30 + bottomPadding,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: Colors.transparent,
                child: Text(title, style: _titleStyle),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: scrollable
                    ? SingleChildScrollView(child: content)
                    : content,
              ),
              SizedBox(height: scrollable ? 60 : 20),
            ],
          ),
          if (!isKeyboardOpen && !hideNavButtons)
            Positioned(
              bottom: 5,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (pageIndex > 0)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _previousPage();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: CustomPaint(
                          painter: WashiTapeButtonPainter(text: '返回修改'),
                          size: const Size(110, 40),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 134),

                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      if (_isSubmitting) return;
                      _nextPage();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      child: Opacity(
                        opacity: _isSubmitting ? 0.6 : 1.0,
                        child: CustomPaint(
                          painter: WashiTapeButtonPainter(
                            text: _isSubmitting
                                ? '提交中...'
                                : (pageIndex == 6 ? '完成' : '下一頁 >'),
                          ),
                          size: const Size(110, 40),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 依據傳入之頁碼索引（0-6）傳回對應之步驟問卷 Widget。
  Widget _buildPageByIndex(int index, {bool hideNavButtons = false}) {
    switch (index) {
      case 0:
        return _buildNamePage(hideNavButtons: hideNavButtons);
      case 1:
        return _buildGenderPage(hideNavButtons: hideNavButtons);
      case 2:
        return _buildAgePage(hideNavButtons: hideNavButtons);
      case 3:
        return _buildHeightWeightPage(hideNavButtons: hideNavButtons);
      case 4:
        return _buildDiseasesPage(hideNavButtons: hideNavButtons);
      case 5:
        return _buildGoalsPage(hideNavButtons: hideNavButtons);
      case 6:
        return _buildElfSelectionPage(hideNavButtons: hideNavButtons);
      default:
        return _buildNamePage(hideNavButtons: hideNavButtons);
    }
  }

  /// 建立步驟 1：用戶暱稱輸入視圖頁面 Widget。
  Widget _buildNamePage({bool hideNavButtons = false}) {
    return _buildPageContainer(
      pageIndex: 0,
      hideNavButtons: hideNavButtons,
      title: '嗨！您想我如何稱呼您呢?',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          _buildHandDrawnTextField(
            '輸入您的名字',
            _nameController,
            (value) => setState(() {
              _name = value;
              _pageErrors.remove(0);
            }),
            onSubmitted: () => FocusManager.instance.primaryFocus?.unfocus(),
          ),
        ],
      ),
    );
  }

  /// 建立步驟 2：性別選擇視圖頁面 Widget。
  Widget _buildGenderPage({bool hideNavButtons = false}) {
    return _buildPageContainer(
      pageIndex: 1,
      hideNavButtons: hideNavButtons,
      title: '您的性別是?',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 60),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildHandDrawnButton(
                '男',
                _gender == '男',
                () => setState(() {
                  _gender = '男';
                  _pageErrors.remove(1);
                }),
              ),
              _buildHandDrawnButton(
                '女',
                _gender == '女',
                () => setState(() {
                  _gender = '女';
                  _pageErrors.remove(1);
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showDropdownMenu<T>({
    required BuildContext context,
    required Rect buttonRect,
    required T? selectedValue,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T> onSelected,
  }) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromLTWH(
        buttonRect.left,
        buttonRect.top + buttonRect.height + 6,
        buttonRect.width,
        0,
      ),
      Offset.zero & overlay.size,
    );

    final T? selected = await showMenu<T>(
      context: context,
      position: position,
      constraints: BoxConstraints(
        minWidth: buttonRect.width,
        maxWidth: buttonRect.width + 20,
        maxHeight: 340,
      ),
      color: AppColors.background,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      initialValue: selectedValue,
      items: items.map((T item) {
        final bool isCurrent = item == selectedValue;
        return PopupMenuItem<T>(
          value: item,
          height: 40,
          child: Text(
            itemLabel(item),
            style: TextStyle(
              fontSize: 16,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              color: isCurrent ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        );
      }).toList(),
    );

    if (selected != null) {
      onSelected(selected);
    }
  }

  Widget _buildHandDrawnDropdown<T>({
    required BuildContext context,
    required T? value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T> onChanged,
    required double width,
    String placeholder = '請選擇',
  }) {
    return Builder(
      builder: (btnContext) {
        final bool isSelected = value != null;
        return GestureDetector(
          onTap: () {
            final RenderBox renderBox =
                btnContext.findRenderObject() as RenderBox;
            final Offset offset = renderBox.localToGlobal(Offset.zero);
            final Rect rect = offset & renderBox.size;

            _showDropdownMenu<T>(
              context: context,
              buttonRect: rect,
              selectedValue: value,
              items: items,
              itemLabel: itemLabel,
              onSelected: onChanged,
            );
          },
          child: CustomPaint(
            painter: HandDrawnBoxPainter(),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: width,
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        isSelected ? itemLabel(value) : placeholder,
                        style: _inputTextStyle.copyWith(
                          color: isSelected
                              ? AppColors.textPrimary
                              : const Color(0xFF555555),
                          fontSize: isSelected ? 15 : 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down,
                      color: AppColors.textPrimary,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 建立步驟 3：生日與年齡選擇視圖頁面 Widget。
  Widget _buildAgePage({bool hideNavButtons = false}) {
    final currentYear = DateTime.now().year;
    final years = List<int>.generate(
      currentYear - 1940 + 1,
      (i) => currentYear - i,
    );
    final months = List<int>.generate(12, (i) => i + 1);
    final maxDays = _daysInMonth(
      _selectedBirthYear ?? 2000,
      _selectedBirthMonth ?? 1,
    );
    final days = List<int>.generate(maxDays, (i) => i + 1);

    if (_selectedBirthDay != null && _selectedBirthDay! > maxDays) {
      _selectedBirthDay = maxDays;
    }

    return _buildPageContainer(
      pageIndex: 2,
      hideNavButtons: hideNavButtons,
      title: '請選擇您的生日',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 25),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '年 (西元)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildHandDrawnDropdown<int>(
                      context: context,
                      value: _selectedBirthYear,
                      items: years,
                      placeholder: '請選擇',
                      itemLabel: (y) => '$y 年',
                      onChanged: (val) {
                        setState(() {
                          _selectedBirthYear = val;
                          _age = _calculatedAge.toString();
                          _pageErrors.remove(2);
                        });
                      },
                      width: double.infinity,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '月',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildHandDrawnDropdown<int>(
                      context: context,
                      value: _selectedBirthMonth,
                      items: months,
                      placeholder: '請選擇',
                      itemLabel: (m) => '$m 月',
                      onChanged: (val) {
                        setState(() {
                          _selectedBirthMonth = val;
                          _age = _calculatedAge.toString();
                          _pageErrors.remove(2);
                        });
                      },
                      width: double.infinity,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '日',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildHandDrawnDropdown<int>(
                      context: context,
                      value: _selectedBirthDay,
                      items: days,
                      placeholder: '請選擇',
                      itemLabel: (d) => '$d 日',
                      onChanged: (val) {
                        setState(() {
                          _selectedBirthDay = val;
                          _age = _calculatedAge.toString();
                          _pageErrors.remove(2);
                        });
                      },
                      width: double.infinity,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 建立步驟 4：身高與體重數值輸入視圖頁面 Widget。
  Widget _buildHeightWeightPage({bool hideNavButtons = false}) {
    return _buildPageContainer(
      pageIndex: 3,
      hideNavButtons: hideNavButtons,
      title: '請輸入您的身高與體重',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('身高', style: _buttonTextStyle.copyWith(fontSize: 22)),
                    const SizedBox(height: 12),
                    _buildHandDrawnTextField(
                      'cm',
                      _heightController,
                      (value) => setState(() {
                        _height = value;
                        _pageErrors.remove(3);
                      }),
                      isNumber: true,
                      onSubmitted: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 30),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('體重', style: _buttonTextStyle.copyWith(fontSize: 22)),
                    const SizedBox(height: 12),
                    _buildHandDrawnTextField(
                      'kg',
                      _weightController,
                      (value) => setState(() {
                        _weight = value;
                        _pageErrors.remove(3);
                      }),
                      isNumber: true,
                      onSubmitted: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 建立步驟 5：慢性疾病與健康狀況標籤選擇視圖頁面 Widget。
  Widget _buildDiseasesPage({bool hideNavButtons = false}) {
    return _buildPageContainer(
      pageIndex: 4,
      hideNavButtons: hideNavButtons,
      title: '您是否患有特殊疾病?',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _diseaseOptions
                .map(
                  (disease) => _buildHandDrawnToggleButton(
                    disease,
                    _diseases.contains(disease),
                    () {
                      setState(() {
                        if (_diseases.contains(disease)) {
                          _diseases.remove(disease);
                        } else {
                          if (disease == '無疾病') {
                            _diseases.clear();
                            _diseases.add('無疾病');
                          } else {
                            _diseases.remove('無疾病');
                            _diseases.add(disease);
                          }
                        }
                        if (_diseases.isNotEmpty) _pageErrors.remove(4);
                      });
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  /// 建立步驟 6：飲食健康目標標籤選擇視圖頁面 Widget。
  Widget _buildGoalsPage({bool hideNavButtons = false}) {
    return _buildPageContainer(
      pageIndex: 5,
      hideNavButtons: hideNavButtons,
      title: '您的飲食目標是?',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Wrap(
            spacing: 20,
            runSpacing: 20,
            children: _goalOptions
                .map(
                  (goal) => _buildHandDrawnToggleButton(
                    goal,
                    _goals.contains(goal),
                    () {
                      setState(() {
                        _goals
                          ..clear()
                          ..add(goal);
                        if (_goals.isNotEmpty) _pageErrors.remove(5);
                      });
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  /// 建立步驟 7：專屬寵物角色確認與預覽視圖頁面 Widget。
  Widget _buildElfSelectionPage({bool hideNavButtons = false}) {
    return _buildPageContainer(
      pageIndex: 6,
      hideNavButtons: hideNavButtons,
      title: '這是您專屬的小精靈',
      scrollable: false,
      content: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Align(
            alignment: const Alignment(0, -0.55),
            child: _buildHandDrawnBox(
              width: 300,
              height: 300,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: createWebModelView(
                        colorScheme: 'orange',
                        autoSpin: false,
                        scale: 1.4,
                        src: 'assets/images/0606.glb',
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      _defaultPetType,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 30,
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

  /// 建立手繪風格之文字輸入框 Widget。
  Widget _buildHandDrawnTextField(
    String hint,
    TextEditingController controller,
    Function(String) onChanged, {
    bool isNumber = false,
    VoidCallback? onSubmitted,
  }) {
    return CustomPaint(
      painter: HandDrawnBoxPainter(),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          child: TextField(
            controller: controller,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            onChanged: onChanged,
            onSubmitted: (_) => onSubmitted?.call(),
            style: _inputTextStyle,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 20),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }

  /// 建立手繪風格之單選按鈕 Widget。
  Widget _buildHandDrawnButton(
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: HandDrawnBoxPainter(isSelected: isSelected),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 20),
            child: Text(
              label,
              style: _buttonTextStyle.copyWith(
                color: isSelected ? const Color(0xFFFFA500) : Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 建立手繪風格之多選切換標籤按鈕 Widget。
  Widget _buildHandDrawnToggleButton(
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: HandDrawnRoundedBoxPainter(isSelected: isSelected),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Text(
              label,
              style: _buttonTextStyle.copyWith(
                fontSize: 20,
                color: isSelected ? const Color(0xFFFFA500) : Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 建立手繪風格外框容器 Widget。
  Widget _buildHandDrawnBox({
    required Widget child,
    double width = 200,
    double height = 200,
  }) {
    return CustomPaint(
      painter: HandDrawnBoxPainter(),
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// HandDrawnNotebookPainter 視圖頁面與狀態類別。
class HandDrawnNotebookPainter extends CustomPainter {
  final double scrollProgress;
  final double mouthProgress;
  final double topPadding;
  final double bottomPadding;
  HandDrawnNotebookPainter({
    required this.scrollProgress,
    required this.mouthProgress,
    required this.topPadding,
    required this.bottomPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint paint = Paint()..color = AppColors.surface;
    canvas.drawRect(rect, paint);

    double margin = 20;
    double topMargin = margin + topPadding;
    double bottomMargin = margin + bottomPadding;
    double paperW = size.width - margin * 2;
    double paperH = size.height - bottomMargin - topMargin;
    Offset paperOrigin = Offset(margin, topMargin);

    Paint paperPaint = Paint()..color = const Color(0xFFFCF8EC);
    Path paperPath = _getHandDrawnRectPath(paperOrigin, paperW, paperH);

    canvas.drawShadow(
      paperPath,
      Colors.black.withValues(alpha: 0.1),
      10.0,
      true,
    );
    canvas.drawPath(paperPath, paperPaint);

    _drawBinderRings(canvas, paperOrigin, paperW);

    _drawPacManProgress(canvas, paperOrigin, paperW);
  }

  Path _getHandDrawnRectPath(Offset origin, double w, double h) {
    Path path = Path();
    Random rand = Random();

    path.moveTo(origin.dx, origin.dy);

    for (double x = 0; x < w; x += 20) {
      double nextX = origin.dx + x + 20;
      path.quadraticBezierTo(
        origin.dx + x + 10 + rand.nextDouble() * 2,
        origin.dy - 2 + rand.nextDouble() * 2,
        nextX,
        origin.dy,
      );
    }

    for (double y = 0; y < h; y += 20) {
      double nextY = origin.dy + y + 20;
      path.quadraticBezierTo(
        origin.dx + w + 2 + rand.nextDouble() * 2,
        origin.dy + y + 10,
        origin.dx + w,
        nextY,
      );
    }

    for (double x = w; x > 0; x -= 20) {
      double nextX = origin.dx + x - 20;
      path.quadraticBezierTo(
        origin.dx + x - 10 + rand.nextDouble() * 2,
        origin.dy + h + 2 + rand.nextDouble() * 2,
        nextX,
        origin.dy + h,
      );
    }

    for (double y = h; y > 0; y -= 20) {
      double nextY = origin.dy + y - 20;
      path.quadraticBezierTo(
        origin.dx - 2 + rand.nextDouble() * 2,
        origin.dy + y - 10,
        origin.dx,
        nextY,
      );
    }

    path.close();
    return path;
  }

  void _drawBinderRings(Canvas canvas, Offset origin, double w) {
    int ringCount = 18;
    double yPos = origin.dy;
    double ringSpacing = w / (ringCount + 1);

    Paint ringPaint = Paint()
      ..color = const Color(0xFF707070)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (int i = 1; i <= ringCount; i++) {
      double cx = origin.dx + ringSpacing * i;

      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx + 1, yPos + 1), radius: 12),
        -0.8 * pi,
        1.6 * pi,
        false,
        shadowPaint,
      );

      Rect ringRect = Rect.fromCenter(
        center: Offset(cx, yPos),
        width: 10,
        height: 24,
      );
      canvas.drawArc(ringRect, -0.8 * pi, 1.6 * pi, false, ringPaint);

      Paint holePaint = Paint()..color = Colors.black;
      canvas.drawCircle(Offset(cx, yPos + 15), 3, holePaint);
    }
  }

  void _drawPacManProgress(Canvas canvas, Offset origin, double w) {
    double yPos = origin.dy + 75;
    int dotCount = 7;
    double dotSpacing = w / (dotCount + 1);

    for (int i = 1; i <= dotCount; i++) {
      double dotX = origin.dx + dotSpacing * i;
      if (i > scrollProgress + 1.2) {
        Paint dotPaint = Paint()..color = Colors.black;
        canvas.drawCircle(Offset(dotX, yPos), 7, dotPaint);
      }
    }

    double pacX = origin.dx + dotSpacing * (scrollProgress + 1);
    Paint pacPaint = Paint()
      ..color = const Color(0xFFFFA500)
      ..style = PaintingStyle.fill;

    double openingAngle = 0.1 * pi + (0.25 * pi * mouthProgress);
    double startAngle = openingAngle;
    double sweepAngle = 2 * pi - (2 * openingAngle);

    Path pacPath = Path();
    pacPath.moveTo(pacX, yPos);
    pacPath.arcTo(
      Rect.fromCircle(center: Offset(pacX, yPos), radius: 14),
      startAngle,
      sweepAngle,
      false,
    );
    pacPath.close();
    canvas.drawPath(pacPath, pacPaint);

    Paint pacStroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(pacPath, pacStroke);
  }

  @override
  bool shouldRepaint(HandDrawnNotebookPainter oldDelegate) {
    return oldDelegate.scrollProgress != scrollProgress ||
        oldDelegate.mouthProgress != mouthProgress;
  }
}

/// HandDrawnBoxPainter 視圖頁面與狀態類別。
class HandDrawnBoxPainter extends CustomPainter {
  final bool isSelected;
  HandDrawnBoxPainter({this.isSelected = false});

  @override
  void paint(Canvas canvas, Size size) {
    Path boxPath = Path();
    Random rand = Random();
    boxPath.moveTo(3, 2);

    for (double x = 0; x < size.width - 3; x += 15) {
      double nextX = (x + 15 > size.width - 3) ? size.width - 3 : x + 15;
      boxPath.quadraticBezierTo(
        x + 7.5 + rand.nextDouble() * 2 - 1,
        1 + rand.nextDouble() * 1.5,
        nextX,
        2,
      );
    }
    for (double y = 0; y < size.height - 3; y += 15) {
      double nextY = (y + 15 > size.height - 3) ? size.height - 3 : y + 15;
      boxPath.quadraticBezierTo(
        size.width - 1 + rand.nextDouble() * 1,
        y + 7.5 + rand.nextDouble() * 2 - 1,
        size.width - 3,
        nextY,
      );
    }
    for (double x = size.width - 3; x > 3; x -= 15) {
      double nextX = (x - 15 < 3) ? 3 : x - 15;
      boxPath.quadraticBezierTo(
        x - 7.5 + rand.nextDouble() * 2 - 1,
        size.height - 1 + rand.nextDouble() * 1,
        nextX,
        size.height - 3,
      );
    }
    for (double y = size.height - 3; y > 3; y -= 15) {
      double nextY = (y - 15 < 3) ? 3 : y - 15;
      boxPath.quadraticBezierTo(
        1 + rand.nextDouble() * 1,
        y - 7.5 + rand.nextDouble() * 2 - 1,
        3,
        nextY,
      );
    }
    boxPath.close();

    Paint fillPaint = Paint()
      ..color = isSelected ? AppColors.primary : AppColors.surface
      ..style = PaintingStyle.fill;

    canvas.drawPath(
      boxPath.shift(const Offset(8, 10)),
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.12),
    );

    canvas.drawPath(boxPath, fillPaint);
  }

  @override
  bool shouldRepaint(HandDrawnBoxPainter oldDelegate) =>
      oldDelegate.isSelected != isSelected;
}

/// HandDrawnRoundedBoxPainter 視圖頁面與狀態類別。
class HandDrawnRoundedBoxPainter extends CustomPainter {
  final bool isSelected;
  HandDrawnRoundedBoxPainter({this.isSelected = false});

  @override
  void paint(Canvas canvas, Size size) {
    Random rand = Random();
    Path path = Path();
    const double cornerRadius = 12;

    path.moveTo(cornerRadius + 2, 2);
    for (
      double x = cornerRadius + 2;
      x < size.width - cornerRadius - 2;
      x += 12
    ) {
      double nextX = (x + 12 > size.width - cornerRadius - 2)
          ? size.width - cornerRadius - 2
          : x + 12;
      path.quadraticBezierTo(
        x + 6 + rand.nextDouble(),
        1 + rand.nextDouble(),
        nextX,
        2,
      );
    }
    path.quadraticBezierTo(size.width - 2, 2, size.width - 3, cornerRadius + 2);
    for (
      double y = cornerRadius + 2;
      y < size.height - cornerRadius - 2;
      y += 12
    ) {
      double nextY = (y + 12 > size.height - cornerRadius - 2)
          ? size.height - cornerRadius - 2
          : y + 12;
      path.quadraticBezierTo(
        size.width - 1 + rand.nextDouble(),
        y + 6 + rand.nextDouble(),
        size.width - 3,
        nextY,
      );
    }
    path.quadraticBezierTo(
      size.width - 2,
      size.height - 2,
      size.width - cornerRadius - 2,
      size.height - 3,
    );
    for (
      double x = size.width - cornerRadius - 2;
      x > cornerRadius + 2;
      x -= 12
    ) {
      double nextX = (x - 12 < cornerRadius + 2) ? cornerRadius + 2 : x - 12;
      path.quadraticBezierTo(
        x - 6 + rand.nextDouble(),
        size.height - 1 + rand.nextDouble(),
        nextX,
        size.height - 3,
      );
    }
    path.quadraticBezierTo(
      2,
      size.height - 2,
      3,
      size.height - cornerRadius - 2,
    );
    for (
      double y = size.height - cornerRadius - 2;
      y > cornerRadius + 2;
      y -= 12
    ) {
      double nextY = (y - 12 < cornerRadius + 2) ? cornerRadius + 2 : y - 12;
      path.quadraticBezierTo(
        1 + rand.nextDouble(),
        y - 6 + rand.nextDouble(),
        3,
        nextY,
      );
    }
    path.quadraticBezierTo(2, 2, cornerRadius + 2, 2);
    path.close();

    Paint fillPaint = Paint()
      ..color = isSelected ? AppColors.primary : AppColors.surface;

    canvas.drawPath(
      path.shift(const Offset(8, 10)),
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.12),
    );

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(HandDrawnRoundedBoxPainter oldDelegate) =>
      oldDelegate.isSelected != isSelected;
}

/// ArrowPainter 視圖頁面與狀態類別。
class ArrowPainter extends CustomPainter {
  final String direction;
  ArrowPainter({required this.direction});

  @override
  void paint(Canvas canvas, Size size) {
    Paint arrowPaint = Paint()
      ..color = AppColors.background
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    double cx = size.width / 2;
    double cy = size.height / 2;

    if (direction == 'left') {
      canvas.drawLine(Offset(cx + 6, cy - 10), Offset(cx - 6, cy), arrowPaint);
      canvas.drawLine(Offset(cx - 6, cy), Offset(cx + 6, cy + 10), arrowPaint);
    } else {
      canvas.drawLine(Offset(cx - 6, cy - 10), Offset(cx + 6, cy), arrowPaint);
      canvas.drawLine(Offset(cx + 6, cy), Offset(cx - 6, cy + 10), arrowPaint);
    }
  }

  @override
  bool shouldRepaint(ArrowPainter oldDelegate) =>
      oldDelegate.direction != direction;
}

/// PageFlipPainter 視圖頁面與狀態類別。
class PageFlipPainter extends CustomPainter {
  final double progress;
  PageFlipPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final double W = size.width;
    final double H = size.height;

    final double curveProgress = Curves.easeInOut.transform(progress);

    final double t = curveProgress * 2.0;

    final Offset pBottom = Offset((W - t * W).clamp(0.0, W), H);
    final Offset pRight = Offset(W, (H - t * H).clamp(0.0, H));

    final Offset pCurl = Offset(W - t * W * 1.25, H - t * H * 1.25);

    final Path shadowPath = Path();
    shadowPath.moveTo(pBottom.dx, pBottom.dy);
    shadowPath.quadraticBezierTo(
      pCurl.dx - 20 * (1 - progress),
      pCurl.dy - 20 * (1 - progress),
      pRight.dx,
      pRight.dy,
    );
    shadowPath.lineTo(W, H);
    shadowPath.close();

    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: (1 - progress) * 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawPath(shadowPath, shadowPaint);

    final Path unpeeledPath = Path();
    unpeeledPath.moveTo(0, 0);
    unpeeledPath.lineTo(W, 0);
    unpeeledPath.lineTo(pRight.dx, pRight.dy);
    unpeeledPath.quadraticBezierTo(
      pCurl.dx + (W - pCurl.dx) * 0.12,
      pCurl.dy + (H - pCurl.dy) * 0.12,
      pBottom.dx,
      pBottom.dy,
    );
    unpeeledPath.lineTo(0, H);
    unpeeledPath.close();

    final Paint paperPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawPath(unpeeledPath, paperPaint);

    final Paint edgeLinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(unpeeledPath, edgeLinePaint);

    final Path curlBackPath = Path();
    curlBackPath.moveTo(pBottom.dx, pBottom.dy);
    curlBackPath.quadraticBezierTo(
      pCurl.dx + (W - pCurl.dx) * 0.12,
      pCurl.dy + (H - pCurl.dy) * 0.12,
      pRight.dx,
      pRight.dy,
    );
    curlBackPath.quadraticBezierTo(
      pCurl.dx + 30 * (1 - progress),
      pCurl.dy + 30 * (1 - progress),
      pCurl.dx,
      pCurl.dy,
    );
    curlBackPath.quadraticBezierTo(
      pCurl.dx + 30 * (1 - progress),
      pCurl.dy + 30 * (1 - progress),
      pBottom.dx,
      pBottom.dy,
    );
    curlBackPath.close();

    final Paint curlPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFF9F6F0),
          const Color(0xFFEFECE5),
          const Color(0xFFD4CFC7),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromPoints(pCurl, Offset(W, H)));

    canvas.drawShadow(
      curlBackPath,
      Colors.black.withValues(alpha: 0.24),
      8.0,
      true,
    );
    canvas.drawPath(curlBackPath, curlPaint);
  }

  @override
  bool shouldRepaint(PageFlipPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// WashiTapeButtonPainter 視圖頁面與狀態類別。
class WashiTapeButtonPainter extends CustomPainter {
  final String text;
  WashiTapeButtonPainter({this.text = '下一頁 >'});

  @override
  void paint(Canvas canvas, Size size) {
    Path baseShape = Path();
    Random rand = Random(text.hashCode);
    double w = size.width;
    double h = size.height;

    baseShape.moveTo(0, 0);
    for (double y = 0; y < h; y += 6) {
      if (y + 6 < h) {
        baseShape.lineTo(4 + rand.nextDouble() * 2, y + 3);
        baseShape.lineTo(0, y + 6);
      }
    }
    baseShape.lineTo(w, h);
    for (double y = h; y > 0; y -= 6) {
      if (y - 6 > 0) {
        baseShape.lineTo(w - 4 - rand.nextDouble() * 2, y - 3);
        baseShape.lineTo(w, y - 6);
      }
    }
    baseShape.close();

    canvas.drawPath(
      baseShape.shift(const Offset(10, 12)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.9),
    );

    canvas.drawPath(baseShape, Paint()..color = Colors.white);

    TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset((w - textPainter.width) / 2, (h - textPainter.height) / 2),
    );
  }

  @override
  bool shouldRepaint(WashiTapeButtonPainter oldDelegate) =>
      oldDelegate.text != text;
}

/// WashiPainter 視圖頁面與狀態類別。
class WashiPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    /* 可擴充紙膠帶條紋圖案的邏輯 */
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// PagePeelClipper 視圖頁面與狀態類別。
class PagePeelClipper extends CustomClipper<Path> {
  final double progress;
  PagePeelClipper({required this.progress});

  @override
  Path getClip(Size size) {
    final double W = size.width;
    final double H = size.height;
    final double curveProgress = Curves.easeInOut.transform(progress);
    final double t = curveProgress * 2.0;

    final Offset pBottom = Offset((W - t * W).clamp(0.0, W), H);
    final Offset pRight = Offset(W, (H - t * H).clamp(0.0, H));
    final Offset pCurl = Offset(W - t * W * 1.25, H - t * H * 1.25);

    final Path unpeeledPath = Path();
    unpeeledPath.moveTo(0, 0);
    unpeeledPath.lineTo(W, 0);
    unpeeledPath.lineTo(pRight.dx, pRight.dy);
    unpeeledPath.quadraticBezierTo(
      pCurl.dx + (W - pCurl.dx) * 0.12,
      pCurl.dy + (H - pCurl.dy) * 0.12,
      pBottom.dx,
      pBottom.dy,
    );
    unpeeledPath.lineTo(0, H);
    unpeeledPath.close();
    return unpeeledPath;
  }

  @override
  bool shouldReclip(PagePeelClipper oldClipper) =>
      oldClipper.progress != progress;
}

/// SinglePagePacmanProgressPainter 視圖頁面與狀態類別。
class SinglePagePacmanProgressPainter extends CustomPainter {
  final int pageIndex;
  final double mouthProgress;

  SinglePagePacmanProgressPainter({
    required this.pageIndex,
    required this.mouthProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double ringRadius = min(size.width, size.height) / 2 - 4;
    final double progress = ((pageIndex + 1) / 7).clamp(0.0, 1.0);
    final Paint trackPaint = Paint()
      ..color = AppColors.surface.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, ringRadius, trackPaint);

    final Paint progressPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: ringRadius),
      -pi / 2,
      2 * pi * progress,
      false,
      progressPaint,
    );

    Paint pacPaint = Paint()
      ..color = const Color(0xFFFFA500)
      ..style = PaintingStyle.fill;

    double openingAngle = 0.1 * pi + (0.25 * pi * mouthProgress);
    double startAngle = openingAngle;
    double sweepAngle = 2 * pi - (2 * openingAngle);

    Path pacPath = Path();
    pacPath.moveTo(center.dx, center.dy);
    pacPath.arcTo(
      Rect.fromCircle(center: center, radius: 14),
      startAngle,
      sweepAngle,
      false,
    );
    pacPath.close();
    canvas.drawPath(pacPath, pacPaint);

    Paint pacStroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(pacPath, pacStroke);
  }

  @override
  bool shouldRepaint(SinglePagePacmanProgressPainter oldDelegate) {
    return oldDelegate.pageIndex != pageIndex ||
        oldDelegate.mouthProgress != mouthProgress;
  }
}

/// HandDrawnNotebookPaperPainter 視圖頁面與狀態類別。
class HandDrawnNotebookPaperPainter extends CustomPainter {
  final double topPadding;
  final double bottomPadding;

  HandDrawnNotebookPaperPainter({
    required this.topPadding,
    required this.bottomPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double margin = 20;
    double topMargin = margin + topPadding;
    double bottomMargin = margin + bottomPadding;
    double paperW = size.width - margin * 2;
    double paperH = size.height - bottomMargin - topMargin;
    Offset paperOrigin = Offset(margin, topMargin);

    Paint paperPaint = Paint()..color = Colors.white;
    Path paperPath = _getHandDrawnRectPath(paperOrigin, paperW, paperH);

    canvas.drawShadow(
      paperPath,
      Colors.black.withValues(alpha: 0.1),
      10.0,
      true,
    );
    canvas.drawPath(paperPath, paperPaint);
  }

  Path _getHandDrawnRectPath(Offset origin, double w, double h) {
    Path path = Path();
    Random rand = Random(42);

    path.moveTo(origin.dx, origin.dy);

    for (double x = 0; x < w; x += 20) {
      double nextX = origin.dx + x + 20;
      path.quadraticBezierTo(
        origin.dx + x + 10 + rand.nextDouble() * 2,
        origin.dy - 2 + rand.nextDouble() * 2,
        nextX,
        origin.dy,
      );
    }
    for (double y = 0; y < h; y += 20) {
      double nextY = origin.dy + y + 20;
      path.quadraticBezierTo(
        origin.dx + w + 2 + rand.nextDouble() * 2,
        origin.dy + y + 10,
        origin.dx + w,
        nextY,
      );
    }
    for (double x = w; x > 0; x -= 20) {
      double nextX = origin.dx + x - 20;
      path.quadraticBezierTo(
        origin.dx + x - 10 + rand.nextDouble() * 2,
        origin.dy + h + 2 + rand.nextDouble() * 2,
        nextX,
        origin.dy + h,
      );
    }
    for (double y = h; y > 0; y -= 20) {
      double nextY = origin.dy + y - 20;
      path.quadraticBezierTo(
        origin.dx - 2 + rand.nextDouble() * 2,
        origin.dy + y - 10,
        origin.dx,
        nextY,
      );
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(HandDrawnNotebookPaperPainter oldDelegate) => false;
}
