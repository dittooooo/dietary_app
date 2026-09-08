import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../color/app_colors.dart';
import '../../controllers/dog_state_controller.dart';
import '../../models/body_status_models.dart';
import '../../services/auth_service.dart';
import '../../services/token_storage.dart';
import '../../services/body_status_api_service.dart';
import '../../widgets/dog_avatar.dart';
import '../home/home_page.dart';
import 'initial_info_page.dart';

/// 登入/註冊成功過渡動畫頁面 Widget。
class SuccessTransitionPage extends StatefulWidget {
  final String title;
  final bool shouldNavigate;

  const SuccessTransitionPage({
    super.key,
    this.title = '成功',
    this.shouldNavigate = true,
  });

  @override
  State<SuccessTransitionPage> createState() => _SuccessTransitionPageState();
}

/// 內部使用的 _SuccessTransitionPageState 元件與狀態處理類別。
class _SuccessTransitionPageState extends State<SuccessTransitionPage> {
  final DogStateController _dogController = DogStateController.instance;
  final BodyStatusApiService _bodyStatusApi = BodyStatusApiService();
  final Random _tipRandom = Random();

  String _statusText = '正在確認資料...';
  String _tipText = '您可以向小精靈尋求飲食建議喔～';
  Timer? _delayTimer;
  Timer? _tipTimer;

  static const List<String> _transitionTips = [
    '您可以向小精靈尋求飲食建議喔～',
    '請記得每天都要均衡飲食',
    '記錄餐點越清楚，小精靈給的建議會越準確',
    '請避免輸入過於抽象的餐點，例如：冷路歐雷',
    '餐點名稱可以寫具體一點，例如：雞腿便當、鮭魚沙拉',
    '若有特殊疾病，記得在個人資料中更新健康狀況',
    '飲食建議僅供參考，身體不適時請優先諮詢專業人員',
  ];

  /// 初始化 Widget 狀態與訂閱生命週期。
  @override
  void initState() {
    super.initState();
    _startTipRotation();
    _runTransition();
  }

  /// 銷毀 Widget 狀態與釋放控制器資源。
  @override
  void dispose() {
    _delayTimer?.cancel();
    _tipTimer?.cancel();
    super.dispose();
  }

  void _startTipRotation() {
    _tipText = _transitionTips[_tipRandom.nextInt(_transitionTips.length)];
    _tipTimer?.cancel();
    _tipTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() {
        _tipText = _pickNextTip();
      });
    });
  }

  String _pickNextTip() {
    if (_transitionTips.length <= 1) return _transitionTips.first;

    String nextTip = _tipText;
    while (nextTip == _tipText) {
      nextTip = _transitionTips[_tipRandom.nextInt(_transitionTips.length)];
    }
    return nextTip;
  }

  /// 執行過渡頁面核心傳輸、資料確認與結算流程。
  Future<void> _runTransition() async {
    final alreadyOnboarded = await _checkOnboarding();
    SettlementResponse? settlement;
    final isAdmin = await AuthService().isAdmin();

    if (alreadyOnboarded && !isAdmin) {
      settlement = await _settleDailyScores();
      if (settlement != null) {
        await _saveBodyStatus(settlement.bodyType);
        await _playBodyTypeChangeIfNeeded(settlement);
      }
    } else if (isAdmin && mounted) {
      setState(() => _statusText = '正在載入管理者模式...');
    }

    await _animateProgress();
    if (!mounted || !widget.shouldNavigate) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            alreadyOnboarded ? const HomePage() : const InitialInfoPage(),
      ),
    );
  }

  /// 檢查用戶是否已完成初始健康問卷流程。
  Future<bool> _checkOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = await const SecureTokenStorage().readAccessToken();
      final needsOnboarding = prefs.getBool(AuthService.needsOnboardingKey);
      final cachedRole = prefs.getString('user_role');

      final bool isAdmin = cachedRole == 'ROLE_ADMIN';
      if (isAdmin) {
        await prefs.setBool(AuthService.needsOnboardingKey, false);
        return true;
      }

      if (token == null || token.isEmpty) return false;

      // 暱稱只代表註冊/登入時的快取資料，不能代表 onboarding 已完成。
      // 是否完成必須以後端 profile 為準，否則新使用者可能跳過流程，
      // 或因本地快取與資料庫不同步而反覆進入 onboarding。
      if (needsOnboarding == false) {
        return true;
      }

      final profileResult = await AuthService().getUserProfile().timeout(
        const Duration(seconds: 5),
      );

      if (profileResult['success'] == true) {
        final userData = profileResult['data'] is Map<String, dynamic>
            ? profileResult['data'] as Map<String, dynamic>
            : <String, dynamic>{};
        final role = userData['user']?['role'] ?? userData['role'];
        if (role != null) {
          await prefs.setString('user_role', role.toString());
        }
        final hasCompleted = userData['hasCompletedOnboarding'] == true;
        final hasProfileData =
            userData['gender']?.toString().trim().isNotEmpty == true &&
            (double.tryParse(userData['height']?.toString() ?? '') ?? 0) > 0 &&
            (double.tryParse(userData['weight']?.toString() ?? '') ?? 0) > 0 &&
            userData['birthDate'] != null &&
            userData['dietGoal']?.toString().trim().isNotEmpty == true;
        final completed = hasCompleted || hasProfileData;
        await prefs.setBool(AuthService.needsOnboardingKey, !completed);
        return completed;
      }

      if (profileResult['statusCode'] == 404) {
        await prefs.setBool(AuthService.needsOnboardingKey, true);
        return false;
      }

      return false;
    } catch (_) {
      debugPrint('檢查 onboarding 失敗');
      final prefs = await SharedPreferences.getInstance();
      final needsOnboarding = prefs.getBool(AuthService.needsOnboardingKey);
      return needsOnboarding == false;
    }
  }

  /// 向後端發送每日飲食與身體分數結算請求。
  Future<SettlementResponse?> _settleDailyScores() async {
    if (mounted) {
      setState(() => _statusText = '正在更新每日結算...');
    }

    try {
      return await _bodyStatusApi.settleDailyScores().timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {
      debugPrint('每日結算失敗');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('每日結算暫時失敗，但仍會繼續進入首頁。')));
      }
      return null;
    }
  }

  /// 當寵物體態改變時，紀錄待彈出的慶祝動畫旗標，延遲至進入 HomeView 後再播放。
  Future<void> _playBodyTypeChangeIfNeeded(
    SettlementResponse settlement,
  ) async {
    final oldType = DogStateController.parseBodyType(settlement.oldBodyType);
    final newType = DogStateController.parseBodyType(settlement.newBodyType);

    final prefs = await SharedPreferences.getInstance();
    if (settlement.bodyTypeChanged && oldType != newType) {
      await prefs.setBool('pending_body_transition_show', true);
      await prefs.setString('pending_old_body_type', settlement.oldBodyType);
      await prefs.setString('pending_new_body_type', settlement.newBodyType);
    } else {
      await prefs.remove('pending_body_transition_show');
    }

    _dogController.setBodyType(newType);
    _dogController.setState(DogAnimationState.idle);
  }

  /// 儲存最新寵物體態資訊至本地快取。
  Future<void> _saveBodyStatus(String bodyType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dog_body_type', bodyType);
  }

  /// 執行安全的倒數計時，可隨時在 dispose 時銷毀。
  Future<void> _animateProgress() async {
    if (mounted) {
      setState(() => _statusText = '正在載入 App...');
    }

    final completer = Completer<void>();
    _delayTimer?.cancel();
    _delayTimer = Timer(const Duration(milliseconds: 4600), () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
  }

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 220,
                  height: 220,
                  child: DogAvatar(
                    controller: _dogController,
                    scale: 1.35,
                    cameraOrbit: '0deg 75deg auto',
                    instanceId: 'login-transition-dog',
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    key: ValueKey(_tipText),
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      _tipText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
