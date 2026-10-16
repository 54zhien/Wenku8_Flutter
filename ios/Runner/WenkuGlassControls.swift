import Flutter
import UIKit

/// Explicitly enabled by the benchmark only; contains counts, never content.
private enum WenkuGlassWork {
  static var recording = false
  static var counts: [String: Int] = [:]
  static func add(_ event: String) {
    if recording { counts[event, default: 0] += 1 }
  }
}

/// Native-only prototype. Flutter owns state/routes; this view owns controls.
final class WenkuGlassFactory: NSObject, FlutterPlatformViewFactory, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  private weak var registrar: FlutterPluginRegistrar?
  private var menuButton: WenkuMenuButton?
  private var menuResult: FlutterResult?
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  static func register(with registrar: FlutterPluginRegistrar) {
    let factory = WenkuGlassFactory(messenger: registrar.messenger())
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
      result(["isPad": UIDevice.current.userInterfaceIdiom == .pad]); return
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
    WenkuGlassView(frame: frame, id: viewId, args: args as? [String: Any] ?? [:], messenger: messenger)
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
  override func layoutSubviews() { super.layoutSubviews(); layout?() }
  override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
}

private final class WenkuGlassView: NSObject, FlutterPlatformView, UIGestureRecognizerDelegate, UITabBarControllerDelegate {
  private let root: WenkuGlassRoot
  private let channel: FlutterMethodChannel
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

  init(frame: CGRect, id: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    WenkuGlassWork.add("platform_views_created")
    state = args
    root = WenkuGlassRoot(frame: frame)
    channel = FlutterMethodChannel(name: "org.mewx.wenku8/glass_controls/\(id)", binaryMessenger: messenger)
    super.init()
    root.backgroundColor = .clear
    createControls()
    update(args)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      if call.method == "state", let value = call.arguments as? [String: Any] { self.update(value); result(nil) }
      else { result(FlutterMethodNotImplemented) }
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
    root.layout = nil
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
