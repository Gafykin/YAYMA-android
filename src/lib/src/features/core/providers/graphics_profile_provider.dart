import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:yayma/src/app/session.dart';
import 'package:yayma/src/features/core/providers/notification_provider.dart';
import 'package:yayma/src/features/core/providers/visual_effects_provider.dart';
import 'package:yayma/src/rust/api/simple.dart' as simple;

/// Готовые наборы графических настроек.
enum GraphicsProfile { light, standard, max }

extension GraphicsProfileText on GraphicsProfile {
  String get label => switch (this) {
    GraphicsProfile.light => 'Лёгкий',
    GraphicsProfile.standard => 'Стандарт',
    GraphicsProfile.max => 'Максимум',
  };

  String get description => switch (this) {
    GraphicsProfile.light =>
      'Без анимированного фона и размытия — для слабых телефонов',
    GraphicsProfile.standard =>
      'Анимированный фон и размытие панелей, умеренная нагрузка',
    GraphicsProfile.max =>
      'Фон в максимальном качестве, размытие и цветное свечение обложки',
  };
}

final FlutterSignal<GraphicsProfile> graphicsProfileSignal = signal(
  GraphicsProfile.standard,
);

/// Автоматически снижать качество, если интерфейс стабильно тормозит.
final FlutterSignal<bool> autoQualitySignal = signal(true);

/// Цветное свечение под обложкой (включается профилем «Максимум»).
final FlutterSignal<bool> coverGlowEnabledSignal = signal(false);

class GraphicsProfileController {
  GraphicsProfileController._();

  static File? _file;
  static bool _monitorStarted = false;

  // Мониторинг кадров.
  static int _frames = 0;
  static int _slowFrames = 0;
  static int _badWindows = 0;
  static DateTime _lastDowngrade = DateTime.fromMillisecondsSinceEpoch(0);

  /// Вызывается один раз при старте. Значения размытия и фона уже
  /// восстановлены из настроек Rust — здесь только то, что хранится отдельно.
  static Future<void> initialize(String basePath) async {
    _file = File('$basePath${Platform.pathSeparator}graphics_profile.json');
    try {
      final file = _file!;
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map<String, dynamic>) {
          final name = data['profile'];
          graphicsProfileSignal.value = GraphicsProfile.values.firstWhere(
            (p) => p.name == name,
            orElse: () => GraphicsProfile.standard,
          );
          autoQualitySignal.value = data['auto'] is bool
              ? data['auto'] as bool
              : true;
        }
      }
    } on Object catch (e) {
      debugPrint('graphics profile load failed: $e');
    }
    _applyLocal(graphicsProfileSignal.value);
    if (Platform.isAndroid) _startMonitor();
  }

  static Future<void> setProfile(GraphicsProfile profile) async {
    graphicsProfileSignal.value = profile;
    _badWindows = 0;
    _frames = 0;
    _slowFrames = 0;

    final bool vibe;
    final double scale;
    final bool blur;
    switch (profile) {
      case GraphicsProfile.light:
        vibe = false;
        scale = minVibeRenderScale;
        blur = false;
      case GraphicsProfile.standard:
        vibe = true;
        scale = 0.35;
        blur = true;
      case GraphicsProfile.max:
        vibe = true;
        scale = maxVibeRenderScale;
        blur = true;
    }
    vibeVisibleSignal.value = vibe;
    vibeRenderScaleSignal.value = scale;
    blurEffectsEnabledSignal.value = blur;
    _applyLocal(profile);

    final ctx = appContextSignal.value;
    if (ctx != null) {
      try {
        await simple.setVibeAnimationEnabled(ctx: ctx, enabled: vibe);
        await simple.setVibeRenderScale(ctx: ctx, scale: scale);
        await simple.setBlurEffectsEnabled(ctx: ctx, enabled: blur);
      } on Object catch (e) {
        debugPrint('graphics profile apply failed: $e');
      }
    }
    await _save();
  }

  static Future<void> setAutoQuality(bool enabled) async {
    autoQualitySignal.value = enabled;
    _badWindows = 0;
    await _save();
  }

  static void _applyLocal(GraphicsProfile profile) {
    coverGlowEnabledSignal.value = profile == GraphicsProfile.max;
    try {
      final cache = PaintingBinding.instance.imageCache;
      switch (profile) {
        case GraphicsProfile.light:
          cache.maximumSizeBytes = 40 << 20;
          cache.maximumSize = 120;
        case GraphicsProfile.standard:
          cache.maximumSizeBytes = 100 << 20;
          cache.maximumSize = 1000;
        case GraphicsProfile.max:
          cache.maximumSizeBytes = 200 << 20;
          cache.maximumSize = 1500;
      }
    } on Object catch (_) {}
  }

  static Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString(
        jsonEncode({
          'profile': graphicsProfileSignal.value.name,
          'auto': autoQualitySignal.value,
        }),
      );
    } on Object catch (e) {
      debugPrint('graphics profile save failed: $e');
    }
  }

  // ---- Автоснижение качества -------------------------------------------

  static void _startMonitor() {
    if (_monitorStarted) return;
    _monitorStarted = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<ui.FrameTiming> timings) {
    if (!autoQualitySignal.value) return;
    if (graphicsProfileSignal.value == GraphicsProfile.light) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    for (final timing in timings) {
      _frames++;
      if (timing.totalSpan.inMilliseconds > 24) _slowFrames++;
      if (_frames < 150) continue;

      final ratio = _slowFrames / _frames;
      _frames = 0;
      _slowFrames = 0;
      _badWindows = ratio > 0.4 ? _badWindows + 1 : 0;

      final cooledDown =
          DateTime.now().difference(_lastDowngrade) >
          const Duration(seconds: 30);
      if (_badWindows >= 3 && cooledDown) {
        _badWindows = 0;
        _lastDowngrade = DateTime.now();
        unawaited(_downgrade());
        return;
      }
    }
  }

  static Future<void> _downgrade() async {
    final next = graphicsProfileSignal.value == GraphicsProfile.max
        ? GraphicsProfile.standard
        : GraphicsProfile.light;
    await setProfile(next);
    showAppWarning(
      'Интерфейс тормозил — включён профиль «${next.label}». '
      'Изменить можно в Настройках → Визуальные эффекты.',
    );
  }
}
