import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ios_route_entrance.dart';
import 'ios_native_composition.dart';

/// Opt in while native/Flutter backdrop composition is awaiting device review.
/// This is a rollout switch, not an automatic substitute for native material.
bool get nativeIOSGlassEnabled =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.iOS &&
    const bool.fromEnvironment('WENKU8_NATIVE_GLASS');

/// Keep the previous composition path available for explicit diagnostics.
bool get sharedIOSGaussianEnabled =>
    nativeIOSGlassEnabled &&
    const bool.fromEnvironment('WENKU8_SHARED_GAUSSIAN', defaultValue: true);

bool nativeIOSControlsReady(BuildContext context) =>
    nativeIOSGlassEnabled && IOSRouteEntrance.readyOf(context);

abstract final class IOSPlatformLayout {
  static bool isPad = false;
  static Future<void> initialize() async {
    if (!nativeIOSGlassEnabled) return;
    final value = await const MethodChannel(
      'org.mewx.wenku8/glass_presentation',
    ).invokeMapMethod<String, dynamic>('layout');
    isPad = value?['isPad'] == true;
  }
}

class IOSNavigationInsets extends StatelessWidget {
  const IOSNavigationInsets({
    super.key,
    required this.extent,
    required this.child,
  });
  final double extent;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!nativeIOSGlassEnabled || !IOSPlatformLayout.isPad) return child;
    final media = MediaQuery.of(context);
    final extra = (extent - media.viewPadding.top).clamp(0.0, double.infinity);
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(top: media.padding.top + extra),
      ),
      child: child,
    );
  }
}

class IOSGlassControl extends StatefulWidget {
  const IOSGlassControl({
    super.key,
    required this.kind,
    required this.configuration,
    required this.onAction,
    this.width,
    this.height = 46,
    this.onMetrics,
  });

  final String kind;
  final Map<String, Object?> configuration;
  final ValueChanged<Map<Object?, Object?>> onAction;
  final double? width;
  final double height;
  final ValueChanged<Map<Object?, Object?>>? onMetrics;

  @override
  State<IOSGlassControl> createState() => _IOSGlassControlState();
}

class _IOSGlassControlState extends State<IOSGlassControl> {
  MethodChannel? _channel;
  double? _measuredHeight;
  Object? _lastSent;
  IOSNativeScene? _scene;
  int _captureRevision = 0;
  bool _sceneMoving = false;
  int? _textureId;
  Size? _captureSize;
  final _pointers = <int>{};
  int _generation = 0, _captureAttempts = 0;
  bool _captureNeeded = true, _captureQueued = false, _capturing = false;
  Object? _viewport;

  void _invalidateCapture() {
    _generation++;
    _captureAttempts = 0;
    _captureNeeded = true;
    _queueCapture();
  }

  void _queueCapture() {
    if (sharedIOSGaussianEnabled ||
        !const bool.fromEnvironment(
          'WENKU8_ROUTE_TEXTURE',
          defaultValue: false,
        ) ||
        !mounted ||
        // A window crop includes Flutter labels painted above a passive
        // material. Replaying it behind those labels would paint them twice.
        widget.kind == 'surface' ||
        _channel == null ||
        !_captureNeeded ||
        _captureQueued ||
        _capturing ||
        _captureAttempts >= 1 ||
        _pointers.isNotEmpty ||
        (_scene?.moving ?? false) ||
        (_scene?.scrolling ?? false)) {
      return;
    }
    _captureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _captureQueued = false;
      if (!mounted ||
          _channel == null ||
          !_captureNeeded ||
          _capturing ||
          _pointers.isNotEmpty ||
          (_scene?.moving ?? false) ||
          (_scene?.scrolling ?? false)) {
        return;
      }
      final generation = _generation;
      _captureAttempts++;
      _capturing = true;
      try {
        final result = await _channel!.invokeMapMethod<String, dynamic>(
          'snapshot',
        );
        if (!mounted) return;
        final id = result?['textureId'];
        if (generation == _generation && id is int && id >= 0) {
          final changed = _captureNeeded || _textureId != id;
          _captureNeeded = false;
          if (changed) setState(() => _textureId = id);
        }
      } on PlatformException {
        // Preserve the visible native control when capture is unavailable.
      } on MissingPluginException {
        // Older hosts keep their original live native composition.
      } finally {
        _capturing = false;
        if (mounted) _queueCapture();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _pointerEnded(PointerEvent event) {
    setState(() => _pointers.remove(event.pointer));
    _invalidateCapture();
  }

  void _compositionChanged() {
    final moving = _scene?.moving ?? false;
    if (moving && !_sceneMoving && _capturing) {
      // The request was queued at rest, but its window may be rendered only
      // after navigation starts. Never admit that crop into the moving plane.
      _invalidateCapture();
    }
    _sceneMoving = moving;
    final revision = _scene?.captureRevision ?? 0;
    if (_captureRevision != revision) {
      _captureRevision = revision;
      setState(_invalidateCapture);
    } else {
      _queueCapture();
    }
  }

  Map<String, Object?> get _configuration => {
    ...widget.configuration,
    'kind': widget.kind,
    'dark': CupertinoTheme.brightnessOf(context) == Brightness.dark,
    'textScale': MediaQuery.textScalerOf(context).scale(1),
  };

  Future<dynamic> _receive(MethodCall call) async {
    if (mounted && call.method == 'attached') {
      _captureAttempts = 0;
      _queueCapture();
      return null;
    }
    if (mounted && call.method == 'metrics' && call.arguments is Map) {
      widget.onMetrics?.call(Map<Object?, Object?>.from(call.arguments as Map));
      final height = (call.arguments as Map)['height'];
      if (height is num &&
          height.isFinite &&
          height >= 44 &&
          height <= 180 &&
          (_measuredHeight == null || (_measuredHeight! - height).abs() > .5)) {
        setState(() => _measuredHeight = height.toDouble());
      }
      return null;
    }
    if (!mounted ||
        call.method != 'action' ||
        widget.configuration['enabled'] == false ||
        call.arguments is! Map) {
      return null;
    }
    widget.onAction(Map<Object?, Object?>.from(call.arguments as Map));
    return null;
  }

  void _created(int id) {
    if (!mounted) return;
    _channel = MethodChannel('org.mewx.wenku8/glass_controls/$id')
      ..setMethodCallHandler(_receive);
    _sync();
    _queueCapture();
  }

  void _sync() {
    final channel = _channel;
    if (channel == null) return;
    final configuration = _configuration;
    if (_sameNativeValue(configuration, _lastSent)) return;
    final snapshot = _copyNativeValue(configuration);
    _lastSent = snapshot;
    _invalidateCapture();
    unawaited(
      channel.invokeMethod<void>('state', configuration).catchError((
        Object error,
        StackTrace stack,
      ) {
        if (identical(_lastSent, snapshot)) _lastSent = null;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'Wenku8 native glass',
          ),
        );
      }),
    );
  }

  @override
  void didUpdateWidget(IOSGlassControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    final viewport = media == null
        ? null
        : (
            media.size,
            media.viewPadding,
            media.viewInsets,
            media.devicePixelRatio,
          );
    if (_viewport != viewport) {
      _viewport = viewport;
      _invalidateCapture();
    }
    final scene = IOSNativeComposition.maybeOf(context);
    if (scene != _scene) {
      _scene?.removeListener(_compositionChanged);
      _scene = scene;
      _captureRevision = scene?.captureRevision ?? 0;
      _sceneMoving = scene?.moving ?? false;
      _scene?.addListener(_compositionChanged);
      _invalidateCapture();
    }
    _sync();
    _queueCapture();
  }

  @override
  void dispose() {
    _scene?.removeListener(_compositionChanged);
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: _measuredHeight ?? widget.height,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isFinite && size != _captureSize) {
          _captureSize = size;
          _invalidateCapture();
        }
        return Listener(
          onPointerDown: (event) =>
              setState(() => _pointers.add(event.pointer)),
          onPointerUp: _pointerEnded,
          onPointerCancel: _pointerEnded,
          child: IOSNativeControlPlane(
            textureId: _captureNeeded ? null : _textureId,
            interacting: _pointers.isNotEmpty,
            child: UiKitView(
              viewType: 'org.mewx.wenku8/glass_controls',
              creationParams: _configuration,
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: _created,
            ),
          ),
        );
      },
    ),
  );
}

bool _sameNativeValue(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.entries.every(
          (entry) =>
              right.containsKey(entry.key) &&
              _sameNativeValue(entry.value, right[entry.key]),
        );
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_sameNativeValue(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

Object? _copyNativeValue(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key, _copyNativeValue(value)));
  }
  if (value is List) return value.map(_copyNativeValue).toList(growable: false);
  return value;
}

/// Native material stays behind Flutter labels without filtering their layer.
class IOSGlassSurface extends StatelessWidget {
  const IOSGlassSurface({
    super.key,
    required this.child,
    this.radius = 28,
    this.opaque = false,
  });
  final Widget child;
  final double radius;
  final bool opaque;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: nativeIOSControlsReady(context)
                ? IOSGlassControl(
                    kind: 'surface',
                    height: double.infinity,
                    configuration: {'radius': radius, 'opaque': opaque},
                    onAction: (_) {},
                  )
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemBackground
                          .resolveFrom(context)
                          .withValues(alpha: opaque ? 1 : .87),
                      borderRadius: BorderRadius.circular(radius),
                    ),
                  ),
          ),
        ),
      ),
      child,
    ],
  );
}

Widget adaptiveSwitch({
  Key? key,
  required bool value,
  required ValueChanged<bool>? onChanged,
  Color? activeTrackColor,
  String label = '开关',
}) => Builder(
  builder: (context) {
    if (nativeIOSControlsReady(context)) {
      return IOSGlassControl(
        key: key,
        kind: 'switch',
        width: 64,
        height: 44,
        configuration: {
          'label': label,
          'value': value,
          'enabled': onChanged != null,
        },
        onAction: (event) {
          if (event['value'] case final bool value) onChanged?.call(value);
        },
      );
    }
    final control = CupertinoSwitch(
      key: nativeIOSGlassEnabled ? null : key,
      value: value,
      activeTrackColor: activeTrackColor,
      onChanged: onChanged,
    );
    return nativeIOSGlassEnabled
        ? SizedBox(
            key: key,
            width: 64,
            height: 44,
            child: Center(child: control),
          )
        : control;
  },
);

class AdaptiveSegmentedControl<T extends Object> extends StatelessWidget {
  const AdaptiveSegmentedControl({
    super.key,
    required this.children,
    required this.groupValue,
    required this.onValueChanged,
  });
  final Map<T, Widget> children;
  final T? groupValue;
  final ValueChanged<T?> onValueChanged;
  @override
  Widget build(BuildContext context) {
    final textOnly = children.values.every((value) => value is Text);
    if (nativeIOSControlsReady(context) && textOnly) {
      return IOSGlassControl(
        kind: 'segmented',
        height: 44,
        configuration: {
          'selectedIndex': groupValue == null
              ? -1
              : children.keys.toList().indexOf(groupValue as T),
          'items': [
            for (final child in children.values)
              {'label': (child as Text).data ?? ''},
          ],
        },
        onAction: (event) {
          if (event['index'] case final int index) {
            if (index >= 0 && index < children.length) {
              onValueChanged(children.keys.elementAt(index));
            }
          }
        },
      );
    }
    final control = CupertinoSlidingSegmentedControl<T>(
      children: children,
      groupValue: groupValue,
      onValueChanged: onValueChanged,
    );
    return nativeIOSGlassEnabled && textOnly
        ? SizedBox(width: double.infinity, height: 44, child: control)
        : control;
  }
}

class IOSMenuOption<T> {
  const IOSMenuOption(
    this.value,
    this.label, {
    this.selected = false,
    this.destructive = false,
  });
  final T value;
  final String label;
  final bool selected;
  final bool destructive;
}

class IOSSelectionButton<T> extends StatelessWidget {
  const IOSSelectionButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.options,
    required this.onSelected,
  });
  final String label;
  final String semanticLabel;
  final List<IOSMenuOption<T>> options;
  final ValueChanged<T> onSelected;
  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: const TextStyle(fontSize: 14)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width + 56;
    painter.dispose();
    return IOSGlassControl(
      kind: 'selection',
      width: width,
      height: 44,
      configuration: {
        'label': label,
        'semanticLabel': semanticLabel,
        'symbol': 'chevron.down',
        'showLabel': true,
        'menu': [
          for (final option in options)
            {'label': option.label, 'selected': option.selected},
        ],
      },
      onAction: (event) {
        if (event['index'] case final int index) {
          if (index >= 0 && index < options.length) {
            onSelected(options[index].value);
          }
        }
      },
    );
  }
}

Future<T?> showIOSMenu<T>(
  BuildContext context,
  List<IOSMenuOption<T>> options,
) async {
  final box = context.findRenderObject() as RenderBox;
  final origin = box.localToGlobal(Offset.zero);
  final index = await const MethodChannel('org.mewx.wenku8/glass_presentation')
      .invokeMethod<int>('menu', {
        'dark': CupertinoTheme.brightnessOf(context) == Brightness.dark,
        'anchor': {
          'x': origin.dx,
          'y': origin.dy,
          'width': box.size.width,
          'height': box.size.height,
        },
        'items': [
          for (final option in options)
            {
              'label': option.label,
              'selected': option.selected,
              'destructive': option.destructive,
            },
        ],
      });
  return index != null && index >= 0 && index < options.length
      ? options[index].value
      : null;
}

String? iosSystemSymbol(IconData icon) {
  final symbols = <int, String>{
    CupertinoIcons.back.codePoint: 'chevron.backward',
    CupertinoIcons.search.codePoint: 'magnifyingglass',
    CupertinoIcons.settings.codePoint: 'gearshape',
    CupertinoIcons.house.codePoint: 'house',
    CupertinoIcons.book.codePoint: 'book',
    CupertinoIcons.bookmark.codePoint: 'bookmark',
    CupertinoIcons.bookmark_fill.codePoint: 'bookmark.fill',
    CupertinoIcons.ellipsis.codePoint: 'ellipsis',
    CupertinoIcons.xmark.codePoint: 'xmark',
    CupertinoIcons.share.codePoint: 'square.and.arrow.up',
    CupertinoIcons.trash.codePoint: 'trash',
    CupertinoIcons.arrow_down.codePoint: 'arrow.down',
    CupertinoIcons.arrow_up.codePoint: 'arrow.up',
    CupertinoIcons.arrow_left.codePoint: 'chevron.backward',
    CupertinoIcons.arrow_right.codePoint: 'chevron.forward',
    CupertinoIcons.play.codePoint: 'play',
    CupertinoIcons.pause.codePoint: 'pause',
    CupertinoIcons.list_bullet.codePoint: 'list.bullet',
    CupertinoIcons.textformat.codePoint: 'textformat',
    CupertinoIcons.slider_horizontal_3.codePoint: 'slider.horizontal.3',
    CupertinoIcons.arrow_clockwise.codePoint: 'arrow.clockwise',
    CupertinoIcons.check_mark.codePoint: 'checkmark',
    CupertinoIcons.plus.codePoint: 'plus',
    CupertinoIcons.minus.codePoint: 'minus',
    CupertinoIcons.headphones.codePoint: 'headphones',
    CupertinoIcons.moon.codePoint: 'moon',
    CupertinoIcons.sun_max.codePoint: 'sun.max',
    CupertinoIcons.refresh.codePoint: 'arrow.clockwise',
    CupertinoIcons.minus_circle.codePoint: 'minus.circle',
    CupertinoIcons.backward_end.codePoint: 'backward.end',
    CupertinoIcons.forward_end.codePoint: 'forward.end',
    CupertinoIcons.play_fill.codePoint: 'play.fill',
    CupertinoIcons.pause_fill.codePoint: 'pause.fill',
    CupertinoIcons.stop_fill.codePoint: 'stop.fill',
    CupertinoIcons.location.codePoint: 'location',
    CupertinoIcons.cloud_download.codePoint: 'icloud.and.arrow.down',
    CupertinoIcons.square_grid_2x2.codePoint: 'square.grid.2x2',
    CupertinoIcons.line_horizontal_3_decrease.codePoint:
        'line.3.horizontal.decrease',
    CupertinoIcons.clock.codePoint: 'clock',
    CupertinoIcons.textformat_size.codePoint: 'textformat.size',
  };
  return symbols[icon.codePoint];
}
