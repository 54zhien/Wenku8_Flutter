import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Diagnostic-build only. Passive callbacks never draw, inject gestures, change
/// animation durations, read page content, or write files in the timing callback.
class IOSMotionDiagnostics extends NavigatorObserver {
  IOSMotionDiagnostics({
    required this.environment,
    required this.save,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    WidgetsBinding.instance.addTimingsCallback(_timings);
  }

  static const enabled = bool.fromEnvironment('WENKU8_MOTION_DIAGNOSTICS');
  final Map<String, Object?> Function() environment;
  final Future<void> Function(Map<String, Object?>) save;
  final DateTime Function() _now;
  final _windows = <_MotionWindow>[];
  Timer? _timer;
  bool _disposed = false;
  Future<void> _saving = Future.value();
  int get windowCount => _windows.length;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _record('push', route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('pop', route);
  }

  void _record(String action, Route<dynamic> route) {
    if (_disposed || route is! PageRoute) return;
    _windows.add(
      _MotionWindow(
        start: _now().microsecondsSinceEpoch,
        action: action,
        duration: action == 'pop'
            ? route.reverseTransitionDuration
            : route.transitionDuration,
        environment: Map.unmodifiable(environment()),
      ),
    );
    if (_windows.length > 10) _windows.removeAt(0);
    _timer?.cancel();
    // Two-second window plus 1.5 seconds for release-mode timing batches.
    _timer = Timer(const Duration(milliseconds: 3500), () {
      unawaited(
        flush().catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'Wenku8 motion diagnostic export',
            ),
          );
        }),
      );
    });
  }

  void _timings(List<ui.FrameTiming> frames) {
    for (final window in _windows) {
      for (final frame in frames) {
        // Pinned native Flutter 3.41.5: flow/frame_timings.cc records this
        // particular phase with TimePoint::CurrentWallTime (system_clock).
        // Other phases use steady_clock and must never be compared to DateTime.
        final wall = frame.timestampInMicroseconds(
          ui.FramePhase.rasterFinishWallTime,
        );
        if (wall < window.start || wall > window.start + 2000000) continue;
        if (window.frames.length < 2000) {
          window.frames.add(frame);
        } else {
          window.truncated = true;
        }
      }
    }
  }

  Future<void> flush() async {
    if (_disposed || _windows.isEmpty) return;
    final payload = <String, Object?>{
      'schema_version': 1,
      'kind': 'UNACCEPTED_DEVICE_MOTION_DIAGNOSTIC',
      'source_sha': const String.fromEnvironment(
        'WENKU8_SOURCE_SHA',
        defaultValue: 'not supplied',
      ),
      'build_mode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      'actual_present_fps_measured': false,
      'timebase':
          'Native Flutter 3.41.5 iOS rasterFinishWallTime / system_clock. Other FramePhase timestamps use a different epoch.',
      'export_policy':
          'After 3.5 seconds without a new navigation event. A new gesture can overlap an already running asynchronous export; no per-frame writes.',
      'meaning':
          'Engine build/raster timings in two-second navigation windows; includes idle work; not Core Animation presentation FPS or a smoothness pass. Overlapping windows can share frames.',
      'events': [for (final window in _windows) window.json()],
    };
    final write = _saving.then((_) => save(payload));
    _saving = write.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    await write;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(_timings);
    _windows.clear();
  }
}

class _MotionWindow {
  _MotionWindow({
    required this.start,
    required this.action,
    required this.duration,
    required this.environment,
  });
  final int start;
  final String action;
  final Duration duration;
  final Map<String, Object?> environment;
  final frames = <ui.FrameTiming>[];
  bool truncated = false;
  Map<String, Object?> json() => {
    'action': action,
    'window_start_wall_us': start,
    'window_end_wall_us': start + 2000000,
    'route_duration_us': duration.inMicroseconds,
    'environment': environment,
    'truncated': truncated,
    'samples': frames.length,
    'status': frames.isEmpty
        ? 'missing_timings'
        : truncated
        ? 'truncated'
        : 'recorded',
    'frames': [
      for (final frame in frames)
        {
          'finish_wall_us': frame.timestampInMicroseconds(
            ui.FramePhase.rasterFinishWallTime,
          ),
          'vsync_us': frame.timestampInMicroseconds(ui.FramePhase.vsyncStart),
          'build_us': frame.buildDuration.inMicroseconds,
          'raster_us': frame.rasterDuration.inMicroseconds,
          'total_us': frame.totalSpan.inMicroseconds,
        },
    ],
  };
}

Future<void> saveIOSMotionDiagnostic(Map<String, Object?> report) async {
  final native = await const MethodChannel(
    'org.mewx.wenku8/glass_presentation',
  ).invokeMapMethod<String, dynamic>('layout');
  final directory = Directory(
    '${(await getApplicationDocumentsDirectory()).path}/WenkuMotion',
  );
  await directory.create(recursive: true);
  final file = File('${directory.path}/motion-latest.json');
  await file.writeAsString(
    const JsonEncoder.withIndent(
      '  ',
    ).convert({...report, 'native_environment_at_export': native}),
    flush: true,
  );
}
