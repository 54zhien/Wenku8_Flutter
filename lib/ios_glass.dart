import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Opt in while native/Flutter backdrop composition is awaiting device review.
/// This is a rollout switch, not an automatic substitute for native material.
bool get nativeIOSGlassEnabled =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.iOS &&
    const bool.fromEnvironment('WENKU8_NATIVE_GLASS');

class IOSGlassControl extends StatefulWidget {
  const IOSGlassControl({
    super.key,
    required this.kind,
    required this.configuration,
    required this.onAction,
    this.width,
    this.height = 46,
  });

  final String kind;
  final Map<String, Object?> configuration;
  final ValueChanged<Map<Object?, Object?>> onAction;
  final double? width;
  final double height;

  @override
  State<IOSGlassControl> createState() => _IOSGlassControlState();
}

class _IOSGlassControlState extends State<IOSGlassControl> {
  MethodChannel? _channel;

  Map<String, Object?> get _configuration => {
    ...widget.configuration,
    'kind': widget.kind,
    'dark': CupertinoTheme.brightnessOf(context) == Brightness.dark,
    'textScale': MediaQuery.textScalerOf(context).scale(1),
  };

  Future<dynamic> _receive(MethodCall call) async {
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
  }

  void _sync() {
    final channel = _channel;
    if (channel == null) return;
    unawaited(
      channel
          .invokeMethod<void>('state', _configuration)
          .catchError(
            (Object error, StackTrace stack) => FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stack,
                library: 'Wenku8 native glass',
              ),
            ),
          ),
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
    _sync();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: widget.height,
    child: UiKitView(
      viewType: 'org.mewx.wenku8/glass_controls',
      creationParams: _configuration,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _created,
    ),
  );
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
