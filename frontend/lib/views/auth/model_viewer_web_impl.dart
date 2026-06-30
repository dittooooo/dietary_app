import 'dart:convert'; // 匯入 dart:convert 元件庫或套件
import 'dart:html' as html; // 匯入 dart:html 元件庫或套件
import 'dart:ui_web' as ui_web; // 匯入 dart:ui_web 元件庫或套件
import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件

bool _isFactoryRegistered = false; // 宣告類別成員或方法內部的區域變數

Widget createWebModelView({ // 定義用於重複使用的 UI 封裝建構方法
  required String colorScheme, // 執行相對應的邏輯計算或設定屬性參數
  required bool autoSpin, // 執行相對應的邏輯計算或設定屬性參數
  required double scale, // 執行相對應的邏輯計算或設定屬性參數
  String? src, // 執行相對應的邏輯計算或設定屬性參數
  bool cameraControls = true, // 宣告類別成員或方法內部的區域變數
  String? cameraOrbit = '0deg 75deg auto', // 執行相對應的邏輯計算或設定屬性參數
  String? animationName, // 新增動畫名稱參數
  bool autoPlay = true, // 新增自動播放參數
}) { // 執行相對應的邏輯計算或設定屬性參數
  // Ensure the `<model-viewer>` library is dynamically injected
  void ensureModelViewerScriptLoaded() { // 執行相對應的邏輯計算或設定屬性參數
    final existingScript = html.document.querySelector('script[src*="model-viewer"]'); // 宣告類別成員或方法內部的區域變數
    if (existingScript == null) { // 執行相對應的邏輯計算或設定屬性參數
      debugPrint('Dynamically injecting backup model-viewer script via jsdelivr CDN...'); // 執行相對應的邏輯計算或設定屬性參數
      final script = html.ScriptElement() // 宣告類別成員或方法內部的區域變數
        ..src = 'https://cdn.jsdelivr.net/npm/@google/model-viewer@3.4.0/dist/model-viewer.min.js'
        ..type = 'module'; // 執行相對應的邏輯計算或設定屬性參數
      html.document.head?.append(script); // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  ensureModelViewerScriptLoaded(); // 執行相對應的邏輯計算或設定屬性參數

  final uri = Uri.parse(html.window.location.href); // 宣告類別成員或方法內部的區域變數
  final portStr = uri.hasPort ? ':${uri.port}' : ''; // 宣告類別成員或方法內部的區域變數
  final baseUrl = '${uri.scheme}://${uri.host}$portStr';
  
  final String path1 = 'assets/images/dog_rigged.glb'; // 宣告類別成員或方法內部的區域變數
  final String path2 = 'assets/assets/images/dog_rigged.glb'; // 宣告類別成員或方法內部的區域變數

  // Helper to return the uncorrupted pure Base64 Data URI directly.
  String? convertDataUriToBlobUrl(String? dataUri) { // 執行相對應的邏輯計算或設定屬性參數
    if (dataUri == null || !dataUri.startsWith('data:')) return dataUri; // 回傳建構完成的元件或方法計算結果
    return dataUri; // 回傳建構完成的元件或方法計算結果
  } // 程式碼區塊或元件結構結束

  // Helper to test URLs asynchronously and set the correct source as a fallback
  void detectAndSetSrc(html.Element element) async { // 執行相對應的邏輯計算或設定屬性參數
    final String url1 = '$baseUrl/$path1'; // 宣告類別成員或方法內部的區域變數
    final String url2 = '$baseUrl/$path2'; // 宣告類別成員或方法內部的區域變數
    
    try { // 執行相對應的邏輯計算或設定屬性參數
      final response1 = await html.window.fetch(url1); // 宣告類別成員或方法內部的區域變數
      final contentType1 = response1.headers.get('content-type') ?? ''; // 宣告類別成員或方法內部的區域變數
      if (response1.status == 200 && !contentType1.toLowerCase().contains('html')) { // 執行相對應的邏輯計算或設定屬性參數
        element.setAttribute('src', url1); // 執行相對應的邏輯計算或設定屬性參數
        return; // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    } catch (_) {} // 執行相對應的邏輯計算或設定屬性參數
    
    try { // 執行相對應的邏輯計算或設定屬性參數
      final response2 = await html.window.fetch(url2); // 宣告類別成員或方法內部的區域變數
      final contentType2 = response2.headers.get('content-type') ?? ''; // 宣告類別成員或方法內部的區域變數
      if (response2.status == 200 && !contentType2.toLowerCase().contains('html')) { // 執行相對應的邏輯計算或設定屬性參數
        element.setAttribute('src', url2); // 執行相對應的邏輯計算或設定屬性參數
        return; // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    } catch (_) {} // 執行相對應的邏輯計算或設定屬性參數
    
    element.setAttribute('src', path1); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  // Locate the existing elements and update attributes reactively
  final existingElement = html.document.getElementById('model-viewer-pet'); // 宣告類別成員或方法內部的區域變數
  if (existingElement != null) { // 執行相對應的邏輯計算或設定屬性參數
    existingElement.removeAttribute('auto-rotate'); // 執行相對應的邏輯計算或設定屬性參數
    if (cameraControls) { // 執行相對應的邏輯計算或設定屬性參數
      existingElement.setAttribute('camera-controls', ''); // 執行相對應的邏輯計算或設定屬性參數
    } else { // 程式碼區塊或元件結構結束
      existingElement.removeAttribute('camera-controls'); // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束
    
    if (src != null && src.isNotEmpty) { // 執行相對應的邏輯計算或設定屬性參數
      final resolvedSrc = convertDataUriToBlobUrl(src); // 宣告類別成員或方法內部的區域變數
      if (existingElement.getAttribute('src') != resolvedSrc) { // 執行相對應的邏輯計算或設定屬性參數
        existingElement.setAttribute('src', resolvedSrc ?? ''); // 執行相對應的邏輯計算或設定屬性參數
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
    
    final fovDeg = (45.0 / scale).clamp(15.0, 90.0); // 宣告類別成員或方法內部的區域變數
    existingElement.setAttribute('field-of-view', '${fovDeg.toInt()}deg'); // 執行相對應的邏輯計算或設定屬性參數
    if (cameraOrbit != null) { // 執行相對應的邏輯計算或設定屬性參數
      existingElement.setAttribute('camera-orbit', cameraOrbit); // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束

    if (animationName != null) {
      existingElement.setAttribute('animation-name', animationName);
    } else {
      existingElement.removeAttribute('animation-name');
    }

    if (autoPlay) {
      existingElement.setAttribute('autoplay', '');
    } else {
      existingElement.removeAttribute('autoplay');
    }
  } // 程式碼區塊或元件結構結束
  
  // Register the view factory
  if (!_isFactoryRegistered) { // 執行相對應的邏輯計算或設定屬性參數
    try { // 執行相對應的邏輯計算或設定屬性參數
      ui_web.platformViewRegistry.registerViewFactory( // 執行相對應的邏輯計算或設定屬性參數
        'model-viewer-custom', // 執行相對應的邏輯計算或設定屬性參數
        (int viewId) { // 執行相對應的邏輯計算或設定屬性參數
          // Create `<model-viewer>` tag
          final element = html.Element.tag('model-viewer') // 宣告類別成員或方法內部的區域變數
            ..id = 'model-viewer-pet' // 執行相對應的邏輯計算或設定屬性參數
            ..setAttribute('alt', '3D Mascot Pet') // 執行相對應的邏輯計算或設定屬性參數
            ..setAttribute('shadow-intensity', '1.0') // 執行相對應的邏輯計算或設定屬性參數
            ..setAttribute('shadow-softness', '0.5') // 執行相對應的邏輯計算或設定屬性參數
            ..setAttribute('environment-image', 'neutral') // 執行相對應的邏輯計算或設定屬性參數
            ..setAttribute('exposure', '1.0') // 執行相對應的邏輯計算或設定屬性參數
            ..setAttribute('interaction-prompt', 'none') // 執行相對應的邏輯計算或設定屬性參數
            ..style.width = '100%' // 執行相對應的邏輯計算或設定屬性參數
            ..style.height = '100%' // 執行相對應的邏輯計算或設定屬性參數
            ..style.border = 'none' // 執行相對應的邏輯計算或設定屬性參數
            ..style.outline = 'none' // 執行相對應的邏輯計算或設定屬性參數
            ..style.backgroundColor = 'transparent'; // 執行相對應的邏輯計算或設定屬性參數
            
          if (cameraControls) { // 執行相對應的邏輯計算或設定屬性參數
            element.setAttribute('camera-controls', ''); // 執行相對應的邏輯計算或設定屬性參數
          } // 程式碼區塊或元件結構結束
            
          // auto-rotate disabled as requested
          
          final fovDeg = (45.0 / scale).clamp(15.0, 90.0); // 宣告類別成員或方法內部的區域變數
          element.setAttribute('field-of-view', '${fovDeg.toInt()}deg'); // 執行相對應的邏輯計算或設定屬性參數
          if (cameraOrbit != null) { // 執行相對應的邏輯計算或設定屬性參數
            element.setAttribute('camera-orbit', cameraOrbit); // 執行相對應的邏輯計算或設定屬性參數
          } // 程式碼區塊或元件結構結束

          if (animationName != null) {
            element.setAttribute('animation-name', animationName);
          }
          if (autoPlay) {
            element.setAttribute('autoplay', '');
          }
          
          // Asynchronously trigger URL validation and binding
          if (src != null && src.isNotEmpty) { // 執行相對應的邏輯計算或設定屬性參數
            final resolvedSrc = convertDataUriToBlobUrl(src); // 宣告類別成員或方法內部的區域變數
            element.setAttribute('src', resolvedSrc ?? ''); // 執行相對應的邏輯計算或設定屬性參數
          } else { // 程式碼區塊或元件結構結束
            detectAndSetSrc(element); // 執行相對應的邏輯計算或設定屬性參數
          } // 程式碼區塊或元件結構結束
          
          return element; // 回傳建構完成的元件或方法計算結果
        }, // 程式碼區塊或元件結構結束
      ); // 程式碼區塊或元件結構結束
      _isFactoryRegistered = true; // 執行相對應的邏輯計算或設定屬性參數
      debugPrint('Registered model-viewer-custom view factory successfully.'); // 執行相對應的邏輯計算或設定屬性參數
    } catch (e) { // 執行相對應的邏輯計算或設定屬性參數
      debugPrint('View factory registration bypassed or already exist: $e'); // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
  
  return const HtmlElementView(viewType: 'model-viewer-custom'); // 建立編譯期常數，優化 Flutter 渲染效能
} // 程式碼區塊或元件結構結束
