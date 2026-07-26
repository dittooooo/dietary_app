import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

Widget createWebModelView({
  required String colorScheme,
  required bool autoSpin,
  required double scale,
  String? src,
  bool cameraControls = true,
  String? cameraOrbit = '0deg 75deg auto',
  String? animationName,
  bool autoPlay = true,
  String instanceId = 'default',
}) {
  final String resolvedSrc = (src != null && !src.startsWith('data:'))
      ? src
      : 'assets/images/dog_rigged.glb';

  final double fovDeg = (45.0 / scale).clamp(15.0, 90.0);

  return _MobileModelViewerAnimationSwitcher(
    key: ValueKey(
      'mobile_mascot_3d_viewer_${instanceId}_${resolvedSrc}_$scale',
    ),
    src: resolvedSrc,
    autoRotate: autoSpin,
    cameraControls: cameraControls,
    cameraOrbit: cameraOrbit,
    fieldOfView: '${fovDeg.toInt()}deg',
    animationName: animationName,
    autoPlay: autoPlay,
  );
}

class _MobileModelViewerAnimationSwitcher extends StatefulWidget {
  final String src;
  final bool autoRotate;
  final bool cameraControls;
  final String? cameraOrbit;
  final String fieldOfView;
  final String? animationName;
  final bool autoPlay;

  const _MobileModelViewerAnimationSwitcher({
    super.key,
    required this.src,
    required this.autoRotate,
    required this.cameraControls,
    required this.cameraOrbit,
    required this.fieldOfView,
    required this.animationName,
    required this.autoPlay,
  });

  @override
  State<_MobileModelViewerAnimationSwitcher> createState() =>
      _MobileModelViewerAnimationSwitcherState();
}

class _MobileModelViewerAnimationSwitcherState
    extends State<_MobileModelViewerAnimationSwitcher> {
  WebViewController? _controller;

  @override
  void didUpdateWidget(covariant _MobileModelViewerAnimationSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationName != widget.animationName ||
        oldWidget.autoPlay != widget.autoPlay) {
      _applyAnimation();
    }
  }

  void _handleWebViewCreated(WebViewController controller) {
    _controller = controller;
    _applyAnimation();
  }

  void _applyAnimation() {
    final controller = _controller;
    final animationName = widget.animationName;
    if (controller == null || animationName == null || animationName.isEmpty) {
      return;
    }

    final escapedAnimationName = animationName.replaceAll("'", r"\'");
    final shouldPlay = widget.autoPlay ? 'true' : 'false';
    for (final delayMs in const [250, 700, 1200]) {
      Future.delayed(Duration(milliseconds: delayMs), () {
        _runAnimationSwitchScript(escapedAnimationName, shouldPlay);
      });
    }
  }

  void _runAnimationSwitchScript(String animationName, String shouldPlay) {
    if (!mounted || _controller == null) return;
    _controller!.runJavaScript('''
        (function() {
          const model = document.querySelector('model-viewer');
          if (!model) return;
          model.animationName = '$animationName';
          model.setAttribute('animation-name', '$animationName');
          model.currentTime = 0;
          if ($shouldPlay && model.play) {
            model.play();
          } else if (model.pause) {
            model.pause();
          }
        })();
      ''');
  }

  @override
  Widget build(BuildContext context) {
    return ModelViewer(
      src: widget.src,
      alt: '3D Mascot Pet',
      autoRotate: widget.autoRotate,
      cameraControls: widget.cameraControls,
      cameraOrbit: widget.cameraOrbit,
      backgroundColor: Colors.transparent,
      fieldOfView: widget.fieldOfView,
      animationName: widget.animationName,
      autoPlay: widget.autoPlay,
      interactionPrompt: InteractionPrompt.none,
      onWebViewCreated: _handleWebViewCreated,
    );
  }
}
