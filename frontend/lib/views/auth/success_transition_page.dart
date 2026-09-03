import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../color/app_colors.dart';
import '../../controllers/dog_state_controller.dart';
import '../../models/body_status_models.dart';
import '../../services/auth_service.dart';
import '../../services/body_status_api_service.dart';
import '../../widgets/body_transition_animation_dialog.dart';
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

  String _statusText = '正在確認資料...';
  Timer? _delayTimer;

  /// 初始化 Widget 狀態與訂閱生命週期。
  @override
  void initState() {
    super.initState();
    _runTransition();
  }

  /// 銷毀 Widget 狀態與釋放控制器資源。
  @override
  void dispose() {
    _delayTimer?.cancel();
    super.dispose();
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
      final token = prefs.getString(AuthService.accessTokenKey);
      final needsOnboarding = prefs.getBool(AuthService.needsOnboardingKey);
      final cachedNickname = prefs.getString('user_nickname');
      final cachedRole = prefs.getString('user_role');
      final cachedEmail = prefs.getString('user_email')?.trim().toLowerCase();

      final bool isAdmin = cachedRole == 'ROLE_ADMIN' ||
          cachedRole == 'ADMIN' ||
          cachedEmail == 'admin@gmail.com';
      if (isAdmin) {
        await prefs.setBool(AuthService.needsOnboardingKey, false);
        return true;
      }

      if (token == null || token.isEmpty) return false;

      if (needsOnboarding == false || (cachedNickname != null && cachedNickname.isNotEmpty)) {
        return true;
      }

      final profileResult = await AuthService()
          .getUserProfile()
          .timeout(const Duration(seconds: 5));

      if (profileResult['success'] == true) {
        final userData = profileResult['data'] is Map<String, dynamic>
            ? profileResult['data'] as Map<String, dynamic>
            : <String, dynamic>{};
        final role = userData['user']?['role'] ?? userData['role'];
        if (role != null) {
          await prefs.setString('user_role', role.toString());
        }
        await prefs.setBool(AuthService.needsOnboardingKey, false);
        return true;
      }

      if (profileResult['statusCode'] == 404) {
        await prefs.setBool(AuthService.needsOnboardingKey, true);
        return false;
      }

      return needsOnboarding == false;
    } catch (e) {
      debugPrint('Check onboarding failed: $e');
      final prefs = await SharedPreferences.getInstance();
      final needsOnboarding = prefs.getBool(AuthService.needsOnboardingKey);
      return needsOnboarding == false || prefs.getString('user_nickname') != null;
    }
  }

  /// 向後端發送每日飲食與身體分數結算請求。
  Future<SettlementResponse?> _settleDailyScores() async {
    if (mounted) {
      setState(() => _statusText = '正在更新每日結算...');
    }

    try {
      return await _bodyStatusApi.settleDailyScores()
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Settle daily scores failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('每日結算暫時失敗，但仍會繼續進入首頁。')),
        );
      }
      return null;
    }
  }

  /// 當寵物體態改變時彈出變化慶祝動畫對話框。
  Future<void> _playBodyTypeChangeIfNeeded(SettlementResponse settlement) async {
    final oldType = DogStateController.parseBodyType(settlement.oldBodyType);
    final newType = DogStateController.parseBodyType(settlement.newBodyType);

    if (!settlement.bodyTypeChanged || oldType == newType) {
      _dogController.setBodyType(newType);
      _dogController.setState(DogAnimationState.idle);
      return;
    }

    if (mounted) {
      setState(() => _statusText = '正在同步寵物狀態...');
    }

    _dogController.setBodyType(oldType);
    _dogController.setState(DogAnimationState.idle);
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return BodyTransitionAnimationDialog(
          oldBodyType: oldType,
          newBodyType: newType,
        );
      },
    );
    if (!mounted) return;

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
    _delayTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
  }

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
