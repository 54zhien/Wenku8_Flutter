import Flutter
import UIKit
import CoreVideo

/// Explicitly enabled by the benchmark only; contains counts, never content.
private enum WenkuGlassWork {
  static var recording = false
  static var counts: [String: Int] = [:]
  static func add(_ event: String) {
    if recording { counts[event, default: 0] += 1 }
  }
  static func snapshotDuration(_ start: CFTimeInterval) {
    guard recording else { return }
    let elapsed = Int((CACurrentMediaTime() - start) * 1_000_000)
    counts["window_snapshot_total_us", default: 0] += elapsed
    counts["window_snapshot_max_us"] = max(counts["window_snapshot_max_us", default: 0], elapsed)
  }
}

/// Native-only prototype. Flutter owns state/routes; this view owns controls.
final class WenkuGlassFactory: NSObject, FlutterPlatformViewFactory, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  private let textures: FlutterTextureRegistry
  private weak var registrar: FlutterPluginRegistrar?
  private var menuButton: WenkuMenuButton?
  private var menuResult: FlutterResult?
  init(messenger: FlutterBinaryMessenger, textures: FlutterTextureRegistry) {
    self.messenger = messenger; self.textures = textures
  }
  static func register(with registrar: FlutterPluginRegistrar) {
    let factory = WenkuGlassFactory(messenger: registrar.messenger(), textures: registrar.textures())
    factory.registrar = registrar
    registrar.register(factory, withId: "org.mewx.wenku8/glass_controls")
    let channel = FlutterMethodChannel(name: "org.mewx.wenku8/glass_presentation", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(factory, channel: channel)
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "probeStart" {
      WenkuGlassWork.counts = [:]; WenkuGlassWork.recording = true; result(nil); return
    }
    if call.method == "probeEnd" {
      WenkuGlassWork.recording = false; result(WenkuGlassWork.counts); return
    }
    if call.method == "layout" {
      let environment: [String: Any] = ["isPad": UIDevice.current.userInterfaceIdiom == .pad,
        "systemVersion": UIDevice.current.systemVersion,
        "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
        "reduceMotion": UIAccessibility.isReduceMotionEnabled]
      result(environment); return
    }
    guard call.method == "menu", let args = call.arguments as? [String: Any],
      let items = args["items"] as? [[String: Any]], !items.isEmpty else {
      result(FlutterMethodNotImplemented); return
    }
    guard menuResult == nil, var presenter = registrar?.viewController else {
      result(FlutterError(code: "PRESENTATION_BUSY", message: "菜单暂时无法打开", details: nil)); return
    }
    while let next = presenter.presentedViewController { presenter = next }
    let button = WenkuMenuButton(type: .system)
    button.overrideUserInterfaceStyle = args["dark"] as? Bool == true ? .dark : .light
    let anchor = args["anchor"] as? [String: NSNumber] ?? [:]
    let windowRect = CGRect(x: anchor["x"]?.doubleValue ?? 0, y: anchor["y"]?.doubleValue ?? 0,
      width: max(1, anchor["width"]?.doubleValue ?? 44), height: max(1, anchor["height"]?.doubleValue ?? 44))
    button.frame = presenter.view.convert(windowRect, from: presenter.view.window)
    button.menu = UIMenu(children: items.enumerated().map { index, item in
      UIAction(title: item["label"] as? String ?? "", attributes:
        item["destructive"] as? Bool == true ? .destructive : [], state:
        item["selected"] as? Bool == true ? .on : .off) { [weak button] _ in button?.selection = index }
    })
    button.showsMenuAsPrimaryAction = true
    button.dismissed = { [weak self] in
      guard let self else { return }
      let selection = self.menuButton?.selection
      self.menuButton?.removeFromSuperview()
      self.menuButton = nil
      let callback = self.menuResult
      self.menuResult = nil
      callback?(selection)
    }
    menuButton = button
    menuResult = result
    presenter.view.addSubview(button)
    button.performPrimaryAction()
  }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    WenkuGlassView(frame: frame, id: viewId, args: args as? [String: Any] ?? [:], messenger: messenger, textures: textures)
  }
}

private final class WenkuMenuButton: UIButton {
  var selection: Int?
  var dismissed: (() -> Void)?
  override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
    willEndFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
    super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
    if let animator { animator.addCompletion { [weak self] in self?.dismissed?() } }
    else { dismissed?() }
  }
}

private final class WenkuGlassRoot: UIView {
  var layout: (() -> Void)?
  var attached: (() -> Void)?
  override func layoutSubviews() { super.layoutSubviews(); layout?() }
  override func didMoveToWindow() {
    super.didMoveToWindow(); setNeedsLayout()
    if window != nil { attached?() }
  }
}

/// Apple requires the hosting WINDOW to be captured for visual effects to
/// appear. Reuse that image for all control requests in the same main-loop
/// batch, then release it before the loop sleeps; no timer or idle ticker.
private enum WenkuWindowCapture {
  // Cache failed attempts as well: an incomplete Metal/window render must not
  // trigger the same full-window readback separately for every control.
  static var images: [ObjectIdentifier: (window: UIWindow, bounds: CGRect, image: CGImage?)] = [:]
  static var observer: CFRunLoopObserver?
  static func image(_ window: UIWindow) -> CGImage? {
    let key = ObjectIdentifier(window)
    if let cached = images[key], cached.bounds == window.bounds { return cached.image }
    guard window.bounds.width > 0, window.bounds.height > 0 else { return nil }
    if observer == nil {
      observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue,
        false, 0) { _, _ in images.removeAll(); observer = nil }
      CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false; format.preferredRange = .standard
    format.scale = min(window.traitCollection.displayScale,
      sqrt(4_194_304 / (window.bounds.width * window.bounds.height)))
    let started = CACurrentMediaTime()
    defer { WenkuGlassWork.snapshotDuration(started) }
    var rendered = false
    let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
      rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    WenkuGlassWork.add("window_snapshots")
    let cg = rendered ? image.cgImage : nil
    images[key] = (window, window.bounds, cg)
    return cg
  }
}

/// One bounded, immutable native render per state/layout change. The raster
/// thread only retains the last pixel buffer; it never asks UIKit to render.
final class WenkuControlTexture: NSObject, FlutterTexture {
  private let lock = NSLock()
  private var pixels: CVPixelBuffer?
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock(); defer { lock.unlock() }
    return pixels.map { Unmanaged.passRetained($0) }
  }
  func capture(_ view: UIView) -> Bool {
    guard Thread.isMainThread, let window = view.window,
      view.bounds.width.isFinite, view.bounds.height.isFinite,
      view.bounds.width > 0, view.bounds.height > 0 else { return false }
    view.layoutIfNeeded()
    guard let image = WenkuWindowCapture.image(window) else { return false }
    let windowScale = CGFloat(image.width) / window.bounds.width
    let rect = view.convert(view.bounds, to: window).offsetBy(dx: -window.bounds.minX, dy: -window.bounds.minY)
    let source = CGRect(x: rect.minX * windowScale, y: rect.minY * windowScale,
      width: rect.width * windowScale, height: rect.height * windowScale).integral
    let visible = source.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard !visible.isEmpty, let cg = image.cropping(to: visible) else { return false }
    let scale = min(view.traitCollection.displayScale, sqrt(1_048_576 / (view.bounds.width * view.bounds.height)))
    let width = max(1, Int(ceil(view.bounds.width * scale)))
    let height = max(1, Int(ceil(view.bounds.height * scale)))
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
      kCVPixelFormatType_32BGRA,
      [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferCGImageCompatibilityKey: true,
       kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
    guard status == kCVReturnSuccess, let buffer else { return false }
    guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return false }
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer),
      let context = CGContext(data: base, width: width,
      height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return false }
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    let x = (visible.minX - source.minX) / source.width * CGFloat(width)
    let y = (source.maxY - visible.maxY) / source.height * CGFloat(height)
    context.draw(cg, in: CGRect(x: x, y: y,
      width: visible.width / source.width * CGFloat(width),
      height: visible.height / source.height * CGFloat(height)))
    lock.lock(); pixels = buffer; lock.unlock()
    return true
  }
}

private final class WenkuGlassView: NSObject, FlutterPlatformView, UIGestureRecognizerDelegate, UITabBarControllerDelegate {
  private let root: WenkuGlassRoot
  private let channel: FlutterMethodChannel
  private let textures: FlutterTextureRegistry
  private var controlTexture: WenkuControlTexture?
  private var textureId: Int64?
  private var state: [String: Any]
  private var buttons: [UIButton] = []
  private var slider: UISlider?
  private var toggle: UISwitch?
  private var previewIndex: Int?
  private var tabs: UITabBarController?
  private var toolbar: UIToolbar?
  private var segmented: UISegmentedControl?
  private var lastHeight: CGFloat = 0
  private var surface: UIVisualEffectView?

  init(frame: CGRect, id: Int64, args: [String: Any], messenger: FlutterBinaryMessenger, textures: FlutterTextureRegistry) {
    WenkuGlassWork.add("platform_views_created")
    state = args
    self.textures = textures
    root = WenkuGlassRoot(frame: frame)
    channel = FlutterMethodChannel(name: "org.mewx.wenku8/glass_controls/\(id)", binaryMessenger: messenger)
    super.init()
    root.attached = { [weak self] in self?.channel.invokeMethod("attached", arguments: nil) }
    root.backgroundColor = .clear
    createControls()
    update(args)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      if call.method == "state", let value = call.arguments as? [String: Any] { self.update(value); result(nil) }
      else if call.method == "snapshot" {
        guard self.slider?.isTracking != true, self.toggle?.isTracking != true,
          !self.buttons.contains(where: { $0.isTracking }) else { result(nil); return }
        let texture = self.controlTexture ?? WenkuControlTexture()
        WenkuGlassWork.add("snapshot_requests")
        guard texture.capture(self.root) else { result(nil); return }
        self.controlTexture = texture
        let id = self.textureId ?? self.textures.register(texture)
        self.textureId = id
        self.textures.textureFrameAvailable(id)
        WenkuGlassWork.add("snapshots_captured")
        result(["textureId": id, "width": self.root.bounds.width, "height": self.root.bounds.height])
      }
      else { result(FlutterMethodNotImplemented) }
    }
  }

  deinit {
    if let textureId { textures.unregisterTexture(textureId) }
    channel.setMethodCallHandler(nil)
    root.layout = nil
    root.attached = nil
    tabs?.willMove(toParent: nil)
    tabs?.view.removeFromSuperview()
    tabs?.removeFromParent()
  }
  func view() -> UIView { root }

  private func pin(_ child: UIView, to parent: UIView, inset: CGFloat = 0) {
    parent.addSubview(child)
    child.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
      child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
      child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
      child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
    ])
  }

  private func createControls() {
    switch state["kind"] as? String {
    case "surface":
      root.isUserInteractionEnabled = false
      let opaque = state["opaque"] as? Bool == true
      let glass = UIVisualEffectView(effect: opaque ? nil : UIGlassEffect(style: .regular))
      if !opaque { WenkuGlassWork.add("surface_effects_created") }
      glass.backgroundColor = opaque ? .systemBackground : .clear
      surface = glass
      glass.layer.cornerRadius = (state["radius"] as? NSNumber)?.doubleValue ?? 28
      glass.clipsToBounds = true
      pin(glass, to: root)
    case "tabbar":
      let controller = UITabBarController()
      controller.delegate = self
      controller.view.backgroundColor = .clear
      let items = state["items"] as? [[String: Any]] ?? []
      controller.viewControllers = items.enumerated().map { index, item in
        let page = UIViewController()
        page.view.backgroundColor = .clear
        let name = item["symbol"] as? String ?? ""
        page.tabBarItem = UITabBarItem(title: item["label"] as? String,
          image: UIImage(systemName: name + ".fill") ?? UIImage(systemName: name), tag: index)
        page.tabBarItem.accessibilityIdentifier = "wenku-tab-\(index)"
        return page
      }
      tabs = controller
      root.layout = { [weak self] in
        guard let self else { return }
        if controller.parent == nil, self.root.window != nil {
          var responder: UIResponder? = self.root.superview
          while let value = responder {
            if let parent = value as? UIViewController {
              parent.addChild(controller)
              self.pin(controller.view, to: self.root)
              controller.didMove(toParent: parent)
              break
            }
            responder = value.next
          }
        }
        guard controller.parent != nil else { return }
        controller.view.frame = self.root.bounds
        controller.view.layoutIfNeeded()
        let height = controller.traitCollection.userInterfaceIdiom == .pad
          ? max(controller.tabBar.frame.maxY, controller.selectedViewController?.view.safeAreaInsets.top ?? 0)
          : controller.tabBar.frame.height
        self.reportHeight(height)
      }
    case "toolbar":
      let bar = UIToolbar()
      toolbar = bar
      root.addSubview(bar)
      let items = state["items"] as? [[String: Any]] ?? []
      var barItems: [UIBarButtonItem] = []
      for (index, item) in items.enumerated() {
        if index > 0 { barItems.append(UIBarButtonItem(systemItem: .flexibleSpace)) }
        let action = UIBarButtonItem(title: item["label"] as? String, image:
          index == 1 ? nil : (item["symbol"] as? String).flatMap { UIImage(systemName: $0) },
          primaryAction: UIAction { [weak self] _ in self?.channel.invokeMethod("action", arguments: ["index": index]) })
        action.accessibilityLabel = item["semanticLabel"] as? String ?? item["label"] as? String
        action.accessibilityIdentifier = "wenku-reader-action-\(index)"
        barItems.append(action)
      }
      bar.items = barItems
      root.layout = { [weak self] in
        guard let self else { return }
        let height = bar.sizeThatFits(self.root.bounds.size).height
        bar.frame = CGRect(x: 0, y: 0, width: self.root.bounds.width, height: height)
        self.reportHeight(height + self.root.safeAreaInsets.bottom)
      }
    case "segmented":
      let control = UISegmentedControl(items: (state["items"] as? [[String: Any]] ?? []).map { $0["label"] as? String ?? "" })
      segmented = control
      pin(control, to: root, inset: 4)
      control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    case "dock":
      let effect = UIGlassEffect(style: .regular)
      effect.isInteractive = true
      let glass = UIVisualEffectView(effect: effect)
      glass.layer.cornerRadius = 27
      glass.clipsToBounds = true
      pin(glass, to: root)
      let stack = UIStackView()
      stack.axis = .horizontal
      stack.distribution = .fillEqually
      stack.spacing = 2
      pin(stack, to: glass.contentView, inset: 4)
      let count = (state["items"] as? [[String: Any]])?.count ?? 0
      for index in 0..<count {
        let button = UIButton(type: .system)
        button.tag = index
        button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
        buttons.append(button)
        stack.addArrangedSubview(button)
      }
      let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
      pan.delegate = self
      root.addGestureRecognizer(pan)
    case "slider":
      let control = UISlider()
      control.addTarget(self, action: #selector(sliderBegan), for: .touchDown)
      control.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
      control.addTarget(self, action: #selector(sliderEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
      slider = control
      pin(control, to: root, inset: 6)
    case "switch":
      let control = UISwitch()
      control.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(control)
      NSLayoutConstraint.activate([control.centerXAnchor.constraint(equalTo: root.centerXAnchor), control.centerYAnchor.constraint(equalTo: root.centerYAnchor)])
      control.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
      toggle = control
    default:
      let button = UIButton(type: .system)
      if state["kind"] as? String != "selection" {
        button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
      }
      buttons = [button]
      pin(button, to: root)
    }
  }

  private func update(_ args: [String: Any]) {
    WenkuGlassWork.add("state_updates")
    let previousOpaque = state["opaque"] as? Bool == true
    state = args
    let style: UIUserInterfaceStyle = args["dark"] as? Bool == true ? .dark : .light
    if root.overrideUserInterfaceStyle != style { root.overrideUserInterfaceStyle = style }
    let enabled = args["enabled"] as? Bool ?? true
    if let surface {
      surface.layer.cornerRadius = (args["radius"] as? NSNumber)?.doubleValue ?? 28
      let opaque = args["opaque"] as? Bool == true
      if opaque != previousOpaque {
        surface.effect = opaque ? nil : UIGlassEffect(style: .regular)
        if !opaque { WenkuGlassWork.add("surface_effects_created") }
        surface.backgroundColor = opaque ? .systemBackground : .clear
      }
    }
    if let tabs {
      tabs.overrideUserInterfaceStyle = style
      tabs.selectedIndex = max(0, min((tabs.viewControllers?.count ?? 1) - 1, args["selectedIndex"] as? Int ?? 0))
    }
    if let toolbar {
      let items = args["items"] as? [[String: Any]] ?? []
      for (index, item) in items.enumerated() {
        let position = index * 2
        guard let actions = toolbar.items, position < actions.count else { continue }
        actions[position].title = item["label"] as? String
        actions[position].isEnabled = enabled && (item["enabled"] as? Bool ?? true)
        actions[position].accessibilityLabel = item["semanticLabel"] as? String ?? item["label"] as? String
      }
    }
    if let segmented {
      segmented.selectedSegmentIndex = args["selectedIndex"] as? Int ?? UISegmentedControl.noSegment
      segmented.isEnabled = enabled
    }
    if tabs != nil || toolbar != nil { lastHeight = 0; root.setNeedsLayout() }
    if let slider {
      slider.minimumValue = (args["min"] as? NSNumber)?.floatValue ?? 0
      slider.maximumValue = (args["max"] as? NSNumber)?.floatValue ?? 1
      if !slider.isTracking { slider.value = (args["value"] as? NSNumber)?.floatValue ?? 0 }
      slider.accessibilityLabel = args["label"] as? String
      slider.isEnabled = enabled
    }
    if let toggle {
      toggle.setOn(args["value"] as? Bool ?? false, animated: false)
      toggle.accessibilityLabel = args["label"] as? String
      toggle.isEnabled = enabled
    }
    let items = args["items"] as? [[String: Any]]
    let selected = previewIndex ?? (args["selectedIndex"] as? Int ?? 0)
    for (index, button) in buttons.enumerated() {
      let item = items.flatMap { index < $0.count ? $0[index] : nil } ?? args
      let active = items != nil && selected == index
      var config: UIButton.Configuration = active ? .prominentGlass() : (items == nil ? .glass() : .plain())
      config.cornerStyle = .capsule
      config.showsActivityIndicator = item["loading"] as? Bool ?? false
      config.image = (item["symbol"] as? String).flatMap { UIImage(systemName: $0) }
      config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: items == nil ? 20 : 17)
      if items != nil || item["showLabel"] as? Bool == true { config.title = item["label"] as? String }
      config.imagePlacement = args["kind"] as? String == "selection" ? .trailing : (items == nil ? .leading : .top)
      config.imagePadding = 3
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        let base = UIFont.systemFont(ofSize: items == nil ? 14 : 10, weight: .medium)
        outgoing.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: base)
        return outgoing
      }
      button.configuration = config
      WenkuGlassWork.add("button_configurations")
      if let menuItems = args["menu"] as? [[String: Any]] {
        button.menu = UIMenu(children: menuItems.enumerated().map { option, item in
          UIAction(title: item["label"] as? String ?? "", state:
            item["selected"] as? Bool == true ? .on : .off) { [weak self] _ in
              self?.channel.invokeMethod("action", arguments: ["index": option])
            }
        })
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = true
      }
      button.accessibilityLabel = item["semanticLabel"] as? String ?? item["label"] as? String
      button.isEnabled = enabled && (item["enabled"] as? Bool ?? true)
      button.accessibilityTraits = active ? [.button, .selected] : .button
    }
  }

  private func reportHeight(_ height: CGFloat) {
    guard height >= 44, height <= 180, abs(height - lastHeight) > 0.5 else { return }
    lastHeight = height
    channel.invokeMethod("metrics", arguments: ["height": height])
  }

  func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
    channel.invokeMethod("action", arguments: ["index": tabBarController.selectedIndex])
  }

  @objc private func segmentChanged() {
    if let segmented { channel.invokeMethod("action", arguments: ["index": segmented.selectedSegmentIndex]) }
  }

  @objc private func tap(_ sender: UIButton) {
    guard sender.isEnabled else { return }
    channel.invokeMethod("action", arguments: ["index": sender.tag])
  }

  @objc private func pan(_ gesture: UIPanGestureRecognizer) {
    guard !buttons.isEmpty, root.bounds.width > 0 else { return }
    let index = max(0, min(buttons.count - 1, Int(gesture.location(in: root).x / root.bounds.width * CGFloat(buttons.count))))
    switch gesture.state {
    case .began, .changed:
      previewIndex = index
      update(state)
    case .ended:
      previewIndex = nil
      update(state)
      let items = state["items"] as? [[String: Any]] ?? []
      if buttons[index].isEnabled, index < items.count, items[index]["selectableOnDrag"] as? Bool != false { tap(buttons[index]) }
    case .cancelled, .failed:
      previewIndex = nil
      update(state)
    default: break
    }
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
    let velocity = pan.velocity(in: root)
    return WenkuControlPolicy.shouldBeginPan(horizontal: Double(velocity.x), vertical: Double(velocity.y))
  }

  @objc private func sliderBegan() { channel.invokeMethod("action", arguments: ["phase": "start"]) }
  @objc private func sliderChanged() { sendSlider(phase: slider?.isTracking == true ? "change" : "end") }
  @objc private func sliderEnded() { sendSlider(phase: "end") }
  private func sendSlider(phase: String) {
    guard let slider, slider.isEnabled else { return }
    var value = Double(slider.value)
    if let steps = state["divisions"] as? Int, steps > 0 {
      let min = Double(slider.minimumValue), span = Double(slider.maximumValue - slider.minimumValue)
      if span > 0 { value = min + ((value - min) / span * Double(steps)).rounded() / Double(steps) * span }
    }
    channel.invokeMethod("action", arguments: ["phase": phase, "value": value])
  }
  @objc private func toggleChanged() {
    guard let toggle, toggle.isEnabled else { return }
    channel.invokeMethod("action", arguments: ["value": toggle.isOn])
  }
}
