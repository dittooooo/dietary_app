import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../color/app_colors.dart';
import '../controllers/dog_state_controller.dart';
import 'dog_avatar.dart';

/// 當柴犬體態改變時彈出之 3D 動畫慶祝過渡對話框。
class BodyTransitionAnimationDialog extends StatefulWidget {
  final DogBodyType oldBodyType;
  final DogBodyType newBodyType;

  const BodyTransitionAnimationDialog({
    super.key,
    required this.oldBodyType,
    required this.newBodyType,
  });

  @override
  State<BodyTransitionAnimationDialog> createState() =>
      _BodyTransitionAnimationDialogState();
}

/// BodyTransitionAnimationDialog 之動畫狀態控制器。
class _BodyTransitionAnimationDialogState
    extends State<BodyTransitionAnimationDialog>
    with SingleTickerProviderStateMixin {
  static const double _waitForNewModelProgress = 0.86;
  static const Duration _modelVisibleDelay = Duration(milliseconds: 1500);

  late final AnimationController _controller;
  late final DogStateController _oldDogController;
  late final DogStateController _newDogController;
  late final String _oldDogInstanceId;
  late final String _newDogInstanceId;
  bool _transitionStarted = false;
  bool _newModelLoaded = false;

  /// 初始化 Widget 狀態與動畫控制器。
  @override
  /// 執行 initState 之專屬功能操作。
  void initState() {
    super.initState();
    final transitionId = DateTime.now().microsecondsSinceEpoch;
    _oldDogInstanceId = 'body-transition-old-dog-$transitionId';
    _newDogInstanceId = 'body-transition-new-dog-$transitionId';
    _oldDogController = DogStateController(bodyType: widget.oldBodyType);
    _newDogController = DogStateController(bodyType: widget.newBodyType);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..addListener(_holdLightUntilNewModelLoaded);
  }

  /// 銷毀狀態並釋放動畫控制器資源。
  @override
  /// 執行 dispose 之專屬功能操作。
  void dispose() {
    _controller.dispose();
    _oldDogController.dispose();
    _newDogController.dispose();
    super.dispose();
  }

  /// 當舊體態 3D 模型載入完成時觸發，啟動過渡計時動畫。
  void _handleIntroModelLoaded() {
    if (_transitionStarted) return;
    _transitionStarted = true;

    Future.delayed(_modelVisibleDelay, () {
      if (!mounted || _controller.isAnimating || _controller.value > 0) return;
      _controller.forward();
    });
  }

  /// 在新模型尚未準備好前將光芒動畫定格於最高峰狀態。
  void _holdLightUntilNewModelLoaded() {
    if (_newModelLoaded ||
        _controller.value < _waitForNewModelProgress ||
        !_controller.isAnimating) {
      return;
    }

    _controller
      ..stop()
      ..value = _waitForNewModelProgress;
  }

  /// 當新體態 3D 模型載入完成時解鎖並繼續完成收尾動畫。
  void _handleNewModelLoaded() {
    if (_newModelLoaded) return;

    _newModelLoaded = true;
    if (_controller.value >= _waitForNewModelProgress &&
        !_controller.isAnimating) {
      _controller.forward();
    }
  }

  /// 將體態 Enum 轉譯為單字中文標籤（瘦、標準、壯、胖）。
  String _bodyTypeLabel(DogBodyType bodyType) {
    switch (bodyType) {
      case DogBodyType.thin:
        return '瘦';
      case DogBodyType.normal:
        return '標準';
      case DogBodyType.muscle:
        return '壯';
      case DogBodyType.heavy:
        return '胖';
    }
  }

  /// 計算區間動態數值之正規化百分比（0.0 ~ 1.0）。
  double _progress(double value, double start, double end) {
    return ((value - start) / (end - start)).clamp(0.0, 1.0).toDouble();
  }

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  /// 建立 BodyTransitionAnimationDialog 區塊之視覺 UI 視圖元件。
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      backgroundColor: AppColors.background,
      elevation: 10,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '體態變化',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_bodyTypeLabel(widget.oldBodyType)} -> ${_bodyTypeLabel(widget.newBodyType)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 320,
              height: 285,
              child: ClipOval(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final progress = _controller.value;
                    final oldOpacity = progress < 0.54
                        ? 1.0
                        : 1.0 -
                            Curves.easeOut.transform(
                              _progress(progress, 0.54, 0.64),
                            );
                    final newOpacity = progress < 0.58
                        ? 0.0
                        : Curves.easeIn.transform(
                            _progress(progress, 0.58, 0.7),
                          );

                    final growProgress = Curves.easeOutCubic.transform(
                      _progress(progress, 0.28, 0.56),
                    );
                    final shrinkProgress = Curves.easeInOutCubic.transform(
                      _progress(progress, _waitForNewModelProgress, 1.0),
                    );
                    final lightScale = progress < 0.56
                        ? 0.18 + (2.72 * growProgress)
                        : progress < _waitForNewModelProgress
                            ? 2.9
                            : 2.9 - (2.58 * shrinkProgress);
                    final lightOpacity = progress <= 0.28
                        ? 0.0
                        : progress < 0.42
                            ? Curves.easeOut.transform(
                                  _progress(progress, 0.28, 0.42),
                                ) *
                                0.95
                            : progress < 0.9
                                ? 0.95
                                : (1.0 -
                                        Curves.easeIn.transform(
                                          _progress(progress, 0.9, 1.0),
                                        )) *
                                    0.95;
                    final showSparkLines = progress < 0.72;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(
                          opacity: oldOpacity,
                          child: SizedBox(
                            width: 300,
                            height: 265,
                            child: DogAvatar(
                              controller: _oldDogController,
                              scale: 3.0,
                              instanceId: _oldDogInstanceId,
                              onModelLoaded: _handleIntroModelLoaded,
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: newOpacity,
                          child: SizedBox(
                            width: 300,
                            height: 265,
                            child: DogAvatar(
                              controller: _newDogController,
                              scale: 3.0,
                              instanceId: _newDogInstanceId,
                              onModelLoaded: _handleNewModelLoaded,
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: lightOpacity,
                          child: Transform.scale(
                            scale: lightScale,
                            child: _BodyTransitionLightEffect(
                              showSparkLines: showSparkLines,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  '知道了',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 體態變換光波與閃耀背景特效元件。
class _BodyTransitionLightEffect extends StatelessWidget {
  final bool showSparkLines;

  const _BodyTransitionLightEffect({
    required this.showSparkLines,
  });

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  /// 建立 _BodyTransitionLightEffect 區塊之視覺 UI 視圖元件。
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white,
            const Color(0xFFFFF7C7).withValues(alpha: 0.98),
            const Color(0xFFFFD166).withValues(alpha: 0.78),
            const Color(0xFFFFD166).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.34, 0.68, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD166).withValues(alpha: 0.65),
            blurRadius: 28,
            spreadRadius: 14,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.8),
            blurRadius: 18,
            spreadRadius: 4,
          ),
        ],
      ),
      child: showSparkLines
          ? CustomPaint(
              painter: _BodyTransitionSparkPainter(),
            )
          : null,
    );
  }
}

/// 繪製體態過渡時四射金光線條之自訂 CustomPainter。
class _BodyTransitionSparkPainter extends CustomPainter {
  @override
  /// 執行 paint 之專屬功能操作。
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 10; i++) {
      final angle = (math.pi * 2 / 10) * i;
      final start = Offset(
        center.dx + math.cos(angle) * 42,
        center.dy + math.sin(angle) * 42,
      );
      final end = Offset(
        center.dx + math.cos(angle) * 60,
        center.dy + math.sin(angle) * 60,
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  /// 執行 shouldRepaint 之專屬功能操作。
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
