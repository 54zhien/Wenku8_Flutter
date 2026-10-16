import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registry = engineBridge.pluginRegistry
    if let registrar = registry.registrar(forPlugin: "WenkuBridge") {
      WenkuBridge.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "WenkuLocalTools") {
      WenkuLocalTools.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "WenkuGlassControls") {
      registrar.register(WenkuGlassFactory(messenger: registrar.messenger()), withId: "org.mewx.wenku8/glass_controls")
    }
  }
}
