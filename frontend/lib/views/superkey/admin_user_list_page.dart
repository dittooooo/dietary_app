// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_detail_page.dart'; // 匯入 user_detail_page.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../services/admin_service.dart'; // 匯入 admin_service.dart
import '../../utils/friendly_error_message.dart';
import '../../utils/profile_value_mapper.dart'; // 匯入 ProfileValueMapper 進行字串對應轉換

/// 管理者全站使用者帳號管理、權限變更與刪除清單頁面。
class AdminUserListPage extends StatefulWidget {
  const AdminUserListPage({super.key}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<AdminUserListPage> createState() => _AdminUserListPageState();
}

/// 全站使用者管理清單頁面之搜尋、分頁與權限狀態。
class _AdminUserListPageState extends State<AdminUserListPage> { // 定義 _AdminUserListPageState 類別，繼承自 State
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  String _currentAdminEmail = '';

  List<dynamic> _users = []; // 儲存後端獲取的使用者列表

  @override // 標記此方法為覆寫父類別之方法
  /// 執行 initState 之專屬功能操作。
  void initState() { // 初始化狀態生命週期方法，頁年建立時執行一次
    super.initState();
    _loadCurrentAdmin();
    _fetchUsers(); // 獲取後端使用者清單
  }

  Future<void> _loadCurrentAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _currentAdminEmail =
          prefs.getString('user_email')?.trim().toLowerCase() ?? '';
    });
  }

  /// 向後端獲取全站使用者帳號清單，包含暱稱、Email、角色與健康目標。
  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    try {
      final list = await AdminService().listUsers(keyword: _searchController.text.trim());
      list.sort((a, b) {
        final aIsAdmin = _isAdminUser(a);
        final bIsAdmin = _isAdminUser(b);
        if (aIsAdmin == bIsAdmin) return 0;
        return aIsAdmin ? -1 : 1;
      });
      setState(() {
        _users = list;
      });
    } catch (e) {
      debugPrint('管理員獲取用戶清單錯誤: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _isAdminUser(dynamic userProfile) {
    final userObj = userProfile is Map && userProfile['user'] is Map
        ? userProfile['user'] as Map
        : const {};
    final role = (userProfile is Map
            ? userProfile['role'] ?? userObj['role'] ?? ''
            : '')
        .toString()
        .trim()
        .toUpperCase();
    return role == 'ROLE_ADMIN';
  }

  @override // 標記此方法為覆寫父類別之方法
  /// 建立  區塊之視覺 UI 視圖元件。
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('使用者管理清單', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton( // 建立點擊圖示按鈕（IconButton）
            icon: const Icon(Icons.refresh), // 顯示預設的圖示元件（Icon）
            onPressed: _fetchUsers, // 更新狀態數據並通知 UI 重新渲染畫面
          ),
        ],
      ),
      body: Column(
        children: [
          Padding( // 建立間距容器（Padding），用於設定內部邊距
            padding: const EdgeInsets.all(15.0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => _fetchUsers(), // 輸入變更時重新查詢 API
              decoration: InputDecoration( // 建立輸入框樣式裝飾（InputDecoration）
                filled: true,
                fillColor: AppColors.background,
                hintText: '輸入名稱、帳號或 ID 查詢...',
                prefixIcon: const Icon(Icons.search, color: AppColors.secondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppColors.primary)),
              ),
            ),
          ),

          Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _users.isNotEmpty
                  ? ListView.builder( // 建立滾動清單元件（ListView），支援多個子元件滾動瀏覽
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final userProfile = _users[index]; // 這是 UserProfileResponse 物件
                        final userObj = userProfile['user'] is Map ? userProfile['user'] : {};
                        final int profileId = userProfile['id'] ?? 0;
                        final String email = (userProfile['email'] ?? userObj['email'] ?? '').toString();
                        final String displayName = userProfile['nickname'] ?? (email.isNotEmpty ? email.split('@')[0] : '使用者');
                        final bool isEnabled = userProfile['enabled'] != false && userObj['enabled'] != false;
                        final bool isCurrentAdmin =
                            _currentAdminEmail.isNotEmpty &&
                            email.trim().toLowerCase() == _currentAdminEmail;
                        
                        return Card(
                          color: AppColors.background,
                          margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.secondary,
                              child: Text("#${index + 1}", style: const TextStyle(color: AppColors.background, fontSize: 12)),
                            ),
                            title: Text(
                              displayName,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(email.isNotEmpty ? email : '無電子郵件', style: const TextStyle(color: Colors.black54)),
                                const SizedBox(height: 4),
                                Text(
                                  isCurrentAdmin
                                      ? '狀態：啟用中（目前登入管理者）'
                                      : (isEnabled ? '狀態：啟用中' : '狀態：已禁用'),
                                  style: TextStyle(
                                    color: isEnabled ? AppColors.primary : AppColors.danger,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Switch(
                              value: isEnabled,
                              thumbColor:
                                  WidgetStateProperty.resolveWith<Color>(
                                (states) {
                                  if (isCurrentAdmin) {
                                    return AppColors.secondary
                                        .withValues(alpha: 0.45);
                                  }
                                  return isEnabled
                                      ? AppColors.primary
                                      : AppColors.danger;
                                },
                              ),
                              trackColor:
                                  WidgetStateProperty.resolveWith<Color>(
                                (states) {
                                  if (isCurrentAdmin) {
                                    return AppColors.secondary
                                        .withValues(alpha: 0.20);
                                  }
                                  return isEnabled
                                      ? AppColors.primary
                                          .withValues(alpha: 0.35)
                                      : AppColors.danger
                                          .withValues(alpha: 0.28);
                                },
                              ),
                              onChanged: isCurrentAdmin
                                  ? null
                                  : (value) => _showStatusConfirmDialog(
                                        profileId,
                                        displayName,
                                        value,
                                      ),
                            ),
                            onTap: () {
                              final String goalText = ProfileValueMapper.dietGoalsToDisplaySet(userProfile['dietGoal']).join(', ');
                              final String healthText = ProfileValueMapper.healthConditionsToDisplaySet(userProfile['healthConditions']).join(', ');

                              final Map<String, String> mappedDetail = {
                                'id': "#$profileId",
                                'name': displayName,
                                'email': email,
                                'gender': userProfile['gender'] ?? '未填',
                                'height': "${userProfile['height'] ?? '未填'}",
                                'weight': "${userProfile['weight'] ?? '未填'}",
                                'goal': goalText.isNotEmpty ? goalText : '養成健康飲食習慣',
                                'healthConditions': healthText.isNotEmpty ? healthText : '無疾病',
                                'status': isEnabled ? '啟用中' : '已禁用',
                              };
                              Navigator.push( // 導航路由跳轉：開啟並推入新頁面
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserDetailPage(userData: mappedDetail),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    )
                  : const Center( // 建立置中對齊元件（Center），將子元件居中顯示
                      child: Text('找不到該使用者', style: TextStyle(fontSize: 18, color: Colors.black54)),
                    ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: _showCreateUserDialog, // 新增使用者彈出對話框
        child: const Icon(Icons.add, color: AppColors.background),
      ),
    );
  }

  /// 彈出對話框供管理者確認是否啟用或禁用指定使用者帳號，點擊確認後呼叫控制台修改狀態。
  void _showStatusConfirmDialog(int userId, String name, bool enabled) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.background,
          title: Text(enabled ? '確認啟用' : '確認禁用', style: const TextStyle(color: AppColors.textPrimary)),
          content: Text(
            enabled
                ? '確定要啟用使用者「$name」嗎？啟用後該帳號可以重新登入。'
                : '確定要禁用使用者「$name」嗎？禁用後該帳號將無法登入，既有登入狀態也會失效。',
            style: const TextStyle(color: Colors.black54),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消', style: TextStyle(color: Colors.black54)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop(); // 關閉對話框
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(enabled ? '正在啟用使用者...' : '正在禁用使用者...')),
                );
                
                final res = await AdminService().updateUserStatus(userId, enabled);
                
                if (context.mounted) {
                  if (res['success'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(enabled ? '已啟用使用者：$name' : '已禁用使用者：$name')),
                    );
                    _fetchUsers(); // 重新整理清單
                  } else {
                    String msg = (res['message'] ?? '狀態更新失敗').toString();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                  }
                }

              },
              child: Text(
                enabled ? '確認啟用' : '確認禁用',
                style: TextStyle(
                  color: enabled ? AppColors.primary : AppColors.danger,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 彈出新增使用者對話框，提供必填欄位供管理者快速創建新帳號。
  void _showCreateUserDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateUserDialog(onCreated: _fetchUsers),
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog({required this.onCreated});

  final VoidCallback onCreated;

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _birthYearController = TextEditingController();
  final TextEditingController _birthMonthController = TextEditingController();
  final TextEditingController _birthDayController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();

  String? _gender;
  bool _isSubmitting = false;
  bool _showValidationPrompt = false;
  final Set<String> _selectedDiseases = {};
  final Set<String> _selectedGoals = {};

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _birthYearController.dispose();
    _birthMonthController.dispose();
    _birthDayController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  String? _buildBirthDate() {
    final year = int.tryParse(_birthYearController.text.trim());
    final month = int.tryParse(_birthMonthController.text.trim());
    final day = int.tryParse(_birthDayController.text.trim());
    if (year == null || month == null || day == null) return null;

    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    if (parsed.isAfter(DateTime.now())) return null;

    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  Widget _buildBirthField(
    TextEditingController controller,
    String hint,
    int maxLength,
  ) {
    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: maxLength,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          counterText: '',
          hintText: hint,
          border: const UnderlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final birthDate = _buildBirthDate();
    final height = double.tryParse(_heightController.text.trim());
    final weight = double.tryParse(_weightController.text.trim());
    final missing = <String>[];

    if (_emailController.text.trim().isEmpty) missing.add('請填寫電子郵件');
    if (_passwordController.text.isEmpty) missing.add('請填寫密碼');
    if (_nameController.text.trim().isEmpty) missing.add('請填寫暱稱');
    if (_birthYearController.text.trim().isEmpty ||
        _birthMonthController.text.trim().isEmpty ||
        _birthDayController.text.trim().isEmpty) {
      missing.add('請完整填寫生日');
    } else if (birthDate == null) {
      missing.add('請填寫正確的生日日期');
    }
    if (_heightController.text.trim().isEmpty) {
      missing.add('請填寫身高');
    } else if (height == null || height <= 0) {
      missing.add('身高必須為正數');
    }
    if (_weightController.text.trim().isEmpty) {
      missing.add('請填寫體重');
    } else if (weight == null || weight <= 0) {
      missing.add('體重必須為正數');
    }
    if (_gender == null) missing.add('請選擇性別');
    if (_selectedDiseases.isEmpty) missing.add('請選擇特殊疾病，若無請選「無疾病」');
    if (_selectedGoals.isEmpty) missing.add('請選擇飲食目標');

    if (missing.isNotEmpty) {
      setState(() => _showValidationPrompt = true);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final Map<String, dynamic> payload = {
      'email': _emailController.text.trim(),
      'password': _passwordController.text,
      'role': 'ROLE_USER',
      'name': _nameController.text.trim(),
      'gender': ProfileValueMapper.genderToApi(_gender),
      'birthDate': birthDate,
      'height': height,
      'weight': weight,
      'petType': ProfileValueMapper.petTypeToApi('米粒(Mili)'),
      'dietGoal': ProfileValueMapper.firstDietGoalToApi(_selectedGoals),
      'specialDisease': ProfileValueMapper.healthConditionsToApi(
        _selectedDiseases,
      ).join(','),
    };

    setState(() {
      _isSubmitting = true;
      _showValidationPrompt = false;
    });
    messenger.showSnackBar(const SnackBar(content: Text('正在創建帳戶...')));

    try {
      final res = await AdminService().createUser(payload);
      if (!mounted) return;

      if (res['success'] == true) {
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('帳戶建立成功！')));
        widget.onCreated();
      } else {
        setState(() => _isSubmitting = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              (res['message'] ?? FriendlyErrorMessage.generic).toString(),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      messenger.showSnackBar(
        const SnackBar(content: Text(FriendlyErrorMessage.generic)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: const Text(
        '新增使用者帳戶 (管理員特權)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: _showValidationPrompt
                  ? Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.white, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '請完整填寫必填欄位',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: '電子郵件'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: '密碼'),
              obscureText: true,
            ),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '暱稱'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const SizedBox(
                  width: 54,
                  child: Text(
                    '生日',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _buildBirthField(_birthYearController, '', 4),
                const SizedBox(width: 4),
                const Text(
                  '年',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                _buildBirthField(_birthMonthController, '', 2),
                const SizedBox(width: 4),
                const Text(
                  '月',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                _buildBirthField(_birthDayController, '', 2),
                const SizedBox(width: 4),
                const Text(
                  '日',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            TextField(
              controller: _heightController,
              decoration: const InputDecoration(labelText: '身高 (cm)'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            TextField(
              controller: _weightController,
              decoration: const InputDecoration(labelText: '體重 (kg)'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('性別：'),
                Radio<String>(
                  value: '男',
                  groupValue: _gender,
                  onChanged: (val) => setState(() => _gender = val),
                ),
                const Text('男'),
                Radio<String>(
                  value: '女',
                  groupValue: _gender,
                  onChanged: (val) => setState(() => _gender = val),
                ),
                const Text('女'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text('特殊疾病：'),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      '無疾病',
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
                    ].map((disease) {
                      final isSelected = _selectedDiseases.contains(disease);
                      return FilterChip(
                        label: Text(disease),
                        selected: isSelected,
                        backgroundColor: Colors.transparent,
                        selectedColor: AppColors.secondary.withValues(alpha: 0.2),
                        onSelected: (bool selected) {
                          setState(() {
                            if (disease == '無疾病') {
                              _selectedDiseases.clear();
                              if (selected) _selectedDiseases.add('無疾病');
                            } else {
                              _selectedDiseases.remove('無疾病');
                              if (_selectedDiseases.contains(disease)) {
                                _selectedDiseases.remove(disease);
                              } else {
                                _selectedDiseases.add(disease);
                              }
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text('飲食目標：'),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: ['養生', '減脂', '增肌'].map((goal) {
                      final isSelected = _selectedGoals.contains(goal);
                      return FilterChip(
                        label: Text(goal),
                        selected: isSelected,
                        backgroundColor: Colors.transparent,
                        selectedColor: AppColors.primary.withValues(alpha: 0.2),
                        onSelected: (bool selected) {
                          setState(() {
                            _selectedGoals.clear();
                            if (selected) {
                              _selectedGoals.add(goal);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _isSubmitting ? null : _submit,
          child: Text(
            _isSubmitting ? '創建中...' : '確認創建',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
