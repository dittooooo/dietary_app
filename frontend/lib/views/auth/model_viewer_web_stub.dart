import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String _modelViewerLoadingHtml = '''
<div class="model-viewer-loading" slot="progress-bar">
  <div class="model-viewer-loading__spinner"></div>
</div>
''';

const String _modelViewerLoadingCss = '''
.model-viewer-loading {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  pointer-events: none;
  transition: opacity 180ms ease;
}
.model-viewer-loading.is-hidden {
  opacity: 0;
}
.model-viewer-loading__spinner {
  width: 42px;
  height: 42px;
  border: 4px solid rgba(238, 238, 238, 0.92);
  border-top-color: #202808;
  border-radius: 50%;
  animation: modelViewerSpin 900ms linear infinite;
}
@keyframes modelViewerSpin {
  to { transform: rotate(360deg); }
}
''';

const String _modelViewerLoadingJs = '''
(() => {
  const model = document.querySelector('model-viewer');
  const loading = document.querySelector('.model-viewer-loading');
  if (!model || !loading) return;

  const hideLoading = () => loading.classList.add('is-hidden');
  const showLoading = () => loading.classList.remove('is-hidden');

  model.addEventListener('load', hideLoading);
  model.addEventListener('error', hideLoading);
  model.addEventListener('progress', (event) => {
    if (event.detail && event.detail.totalProgress >= 1) {
      hideLoading();
    } else {
      showLoading();
    }
  });

  if (model.loaded) hideLoading();
})();
''';

const String _modelViewerLoadedCallbackJs = '''
(() => {
  if (window.__modelLoadedBridgeReady) return;
  window.__modelLoadedBridgeReady = true;

  const notifyLoaded = () => {
    if (window.__modelLoadedBridgeNotified) return;
    window.__modelLoadedBridgeNotified = true;
    if (window.ModelLoaded && window.ModelLoaded.postMessage) {
      window.ModelLoaded.postMessage('loaded');
    }
  };

  const attachModelListeners = () => {
    const model = document.querySelector('model-viewer');
    if (!model) return false;

    model.addEventListener('load', notifyLoaded);
    model.addEventListener('error', notifyLoaded);
    model.addEventListener('progress', (event) => {
      if (event.detail && event.detail.totalProgress >= 1) {
        notifyLoaded();
      }
    });

    if (model.loaded) notifyLoaded();
    return true;
  };

  if (!attachModelListeners()) {
    const timer = setInterval(() => {
      if (attachModelListeners()) clearInterval(timer);
    }, 100);
    setTimeout(() => clearInterval(timer), 10000);
  }
})();
''';

/// createWebModelView 業務邏輯處理方法。
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
  VoidCallback? onModelLoaded,
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
    onModelLoaded: onModelLoaded,
  );
}

/// 內部使用的 _MobileModelViewerAnimationSwitcher 元件與狀態處理類別。
class _MobileModelViewerAnimationSwitcher extends StatefulWidget {
  final String src;
  final bool autoRotate;
  final bool cameraControls;
  final String? cameraOrbit;
  final String fieldOfView;
  final String? animationName;
  final bool autoPlay;
  final VoidCallback? onModelLoaded;

  const _MobileModelViewerAnimationSwitcher({
    super.key,
    required this.src,
    required this.autoRotate,
    required this.cameraControls,
    required this.cameraOrbit,
    required this.fieldOfView,
    required this.animationName,
    required this.autoPlay,
    required this.onModelLoaded,
  });

  @override
  State<_MobileModelViewerAnimationSwitcher> createState() =>
      _MobileModelViewerAnimationSwitcherState();
}

/// 內部使用的 _MobileModelViewerAnimationSwitcherState 元件與狀態處理類別。
class _MobileModelViewerAnimationSwitcherState
    extends State<_MobileModelViewerAnimationSwitcher> {
  WebViewController? _controller;

  @override
  /// 執行 didUpdateWidget 業務邏輯處理方法。
  void didUpdateWidget(covariant _MobileModelViewerAnimationSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationName != widget.animationName ||
        oldWidget.autoPlay != widget.autoPlay) {
      _applyAnimation();
    }
  }

  /// 執行 _handleWebViewCreated 業務邏輯處理方法。
  void _handleWebViewCreated(WebViewController controller) {
    _controller = controller;
    _installModelLoadedBridge();
    _applyAnimation();
  }

  /// 執行 _installModelLoadedBridge 業務邏輯處理方法。
  void _installModelLoadedBridge() {
    final controller = _controller;
    if (controller == null) return;

    controller.addJavaScriptChannel(
      'ModelLoaded',
      onMessageReceived: (_) {
        if (!mounted) return;
        widget.onModelLoaded?.call();
      },
    ).then((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted || _controller == null) return;
        _controller!.runJavaScript(_modelViewerLoadedCallbackJs);
      });
    });
  }

  /// 執行 _applyAnimation 業務邏輯處理方法。
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

  /// 執行 _runAnimationSwitchScript 業務邏輯處理方法。
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

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  /// 執行 build 業務邏輯處理方法。
  Widget build(BuildContext context) {
    return ModelViewer(
      src: widget.src,
      alt: '3D Mascot Pet',
      autoRotate: widget.autoRotate,
      cameraControls: widget.cameraControls,
      cameraOrbit: widget.cameraOrbit,
      backgroundColor: Colors.transparent,
      loading: Loading.eager,
      reveal: Reveal.auto,
      fieldOfView: widget.fieldOfView,
      animationName: widget.animationName,
      autoPlay: widget.autoPlay,
      interactionPrompt: InteractionPrompt.none,
      innerModelViewerHtml: _modelViewerLoadingHtml,
      relatedCss: _modelViewerLoadingCss,
      relatedJs: _modelViewerLoadingJs,
      onWebViewCreated: _handleWebViewCreated,
    );
  }
}
