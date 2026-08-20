import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../color/app_colors.dart';
import '../../config/api_config.dart';
import '../../controllers/dog_state_controller.dart';
import '../../models/body_status_models.dart';
import '../../services/auth_service.dart';
import '../../services/body_status_api_service.dart';
import '../../widgets/dog_avatar.dart';
import '../home/home_page.dart';
import 'initial_info_page.dart';

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

class _SuccessTransitionPageState extends State<SuccessTransitionPage> {
  final DogStateController _dogController = DogStateController.instance;
  final BodyStatusApiService _bodyStatusApi = BodyStatusApiService();

  double _progress = 0.0;
  String _statusText = '正在準備資料...';

  @override
  void initState() {
    super.initState();
    _runTransition();
  }

  Future<void> _runTransition() async {
    final alreadyOnboarded = await _checkOnboarding();
    SettlementResponse? settlement;

    if (alreadyOnboarded) {
      settlement = await _settleDailyScores();
      if (settlement != null) {
        await _saveBodyStatus(settlement.bodyType);
        await _playBodyTypeChangeIfNeeded(settlement);
      }
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

  Future<bool> _checkOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AuthService.accessTokenKey);
      final needsOnboarding = prefs.getBool(AuthService.needsOnboardingKey);
      final cachedNickname = prefs.getString('user_nickname');

      if (token == null || token.isEmpty) return false;

      // 如果本機紀錄已完成 onboarding 或有舊有暱稱，優先判斷為已完成
      if (needsOnboarding == false || (cachedNickname != null && cachedNickname.isNotEmpty)) {
        return true;
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/user/profile'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final userData = decoded is Map<String, dynamic>
            ? (decoded['data'] is Map<String, dynamic> ? decoded['data'] : decoded)
            : <String, dynamic>{};
        final role = userData['user']?['role'] ?? userData['role'];
        if (role != null) {
          await prefs.setString('user_role', role.toString());
        }
        await prefs.setBool(AuthService.needsOnboardingKey, false);
        return true;
      }

      // 若後端明確回傳 404 (尚未完成 onboarding)
      if (response.statusCode == 404) {
        await prefs.setBool(AuthService.needsOnboardingKey, true);
        return false;
      }

      // 其他網路或暫時性狀態錯誤，若非 404 則預設信任本機資料或已完成
      return needsOnboarding == false;
    } catch (e) {
      debugPrint('Check onboarding failed: $e');
      final prefs = await SharedPreferences.getInstance();
      final needsOnboarding = prefs.getBool(AuthService.needsOnboardingKey);
      return needsOnboarding == false || prefs.getString('user_nickname') != null;
    }
  }

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
    _dogController.setState(DogAnimationState.response);
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    _dogController.setBodyType(newType);
    _dogController.setState(DogAnimationState.idle);
    await Future.delayed(const Duration(milliseconds: 600));
  }

  Future<void> _saveBodyStatus(String bodyType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dog_body_type', bodyType);
  }

  Future<void> _animateProgress() async {
    if (mounted) {
      setState(() => _statusText = '正在載入 App...');
    }

    for (int i = 0; i <= 100; i++) {
      await Future.delayed(const Duration(milliseconds: 15));
      if (!mounted) return;
      setState(() => _progress = i / 100.0);
    }
  }

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
                const SizedBox(height: 24),
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: AppColors.surface,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  minHeight: 10,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
