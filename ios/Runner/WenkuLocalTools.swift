import Flutter
import UIKit
import UniformTypeIdentifiers

final class WenkuLocalTools: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private weak var registrar: FlutterPluginRegistrar?
  private var pending: FlutterResult?
  private var operation: String?
  private var exportFile: URL?
  private let io = DispatchQueue(label: "wenku8.documents")
  private let limit = 8 * 1024 * 1024

  init(registrar: FlutterPluginRegistrar) { self.registrar = registrar }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "org.mewx.wenku8/local_tools", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(WenkuLocalTools(registrar: registrar), channel: channel)
  }

  private var presenter: UIViewController? {
    // Implicit-engine registration may run before the Flutter view attaches.
    var current = registrar?.viewController
    while let presented = current?.presentedViewController { current = presented }
    return current
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "keepScreenOn": UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) == true; result(nil)
    case "getKeepScreenOn": result(UIApplication.shared.isIdleTimerDisabled)
    case "shareText":
      guard let text = args["text"] as? String, text.utf8.count <= limit,
        pending == nil, let presenter, presenter.viewIfLoaded?.window != nil else {
        result(FlutterError(code: "share", message: "分享面板暂不可用", details: nil)); return
      }
      pending = result
      let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
      if let popover = sheet.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }
      sheet.completionWithItemsHandler = { [weak self] _, _, _, _ in self?.finish(nil) }
      presenter.present(sheet, animated: true)
    case "exportBackup", "importBackup", "importLegacyData":
      guard pending == nil, let presenter, presenter.viewIfLoaded?.window != nil else {
        result(FlutterError(code: "busy", message: "文件面板暂不可用", details: nil)); return
      }
      let picker: UIDocumentPickerViewController
      if call.method == "exportBackup" {
        guard let text = args["text"] as? String, text.utf8.count <= limit else {
          result(FlutterError(code: "input", message: "备份内容无效或过大", details: nil)); return
        }
        let requested = args["name"] as? String ?? "wenku8-backup.json"
        let name = URL(fileURLWithPath: requested).lastPathComponent
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          let file = folder.appendingPathComponent(name.isEmpty ? "wenku8-backup.json" : name)
          try Data(text.utf8).write(to: file, options: .atomic)
          exportFile = file
          picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        } catch { result(FlutterError(code: "file", message: "无法生成备份", details: nil)); return }
      } else {
        picker = UIDocumentPickerViewController(forOpeningContentTypes: call.method == "importLegacyData" ? [.folder] : [.json, .plainText, .data], asCopy: false)
      }
      pending = result
      operation = call.method
      picker.allowsMultipleSelection = false
      picker.delegate = self
      presenter.present(picker, animated: true)
    default: result(FlutterMethodNotImplemented)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(operation == "exportBackup" ? false : nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { finish(operation == "exportBackup" ? false : nil); return }
    if operation == "exportBackup" { finish(true); return }
    let legacy = operation == "importLegacyData"
    io.async { [self] in
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      do {
        var readFailure: Error?
        var value: Any?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
          do { value = legacy ? try readLegacy(coordinated) : try readText(coordinated) }
          catch { readFailure = error }
        }
        if let error = coordinationError ?? (readFailure as NSError?) { throw error }
        guard let value else { throw WenkuProtocolError.invalidInput }
        DispatchQueue.main.async { self.finish(value) }
      } catch {
        DispatchQueue.main.async { self.finish(FlutterError(code: "file", message: "文件内容无效、超过大小限制或无法读取", details: nil)) }
      }
    }
  }

  private func readText(_ url: URL) throws -> String {
    let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
    guard info.isRegularFile == true, info.isSymbolicLink != true,
      let size = info.fileSize, size <= limit else { throw WenkuProtocolError.invalidInput }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard data.count <= limit, let text = String(data: data, encoding: .utf8) else { throw WenkuProtocolError.invalidInput }
    return text
  }

  private func readLegacy(_ root: URL) throws -> [String: Any] {
    let manager = FileManager.default
    let candidates = [root, root.appendingPathComponent("saves", isDirectory: true)]
    let allowed = Set(["bookshelf_local.wk8", "read_saves.wk8", "read_saves_v1.wk8", "search_history.wk8"])
    var documents: [String: Any] = [:]
    var total = 0
    var skipped = 0
    for folder in candidates {
      let folderInfo = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard folderInfo?.isDirectory == true, folderInfo?.isSymbolicLink != true else { continue }
      for directory in [folder, folder.appendingPathComponent("intro", isDirectory: true)] {
        let dirInfo = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard dirInfo?.isDirectory == true, dirInfo?.isSymbolicLink != true else { continue }
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        guard files.count <= 10000 else { throw WenkuProtocolError.invalidInput }
        for file in files {
          let name = file.lastPathComponent
          let record = allowed.contains(name)
          guard documents[name] == nil,
            record || name.range(of: #"^[1-9][0-9]{0,9}-volume\.xml$"#, options: .regularExpression) != nil else { continue }
          do {
            let text = try readText(file)
            guard total + text.utf8.count <= limit else { throw WenkuProtocolError.invalidInput }
            let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            documents[name] = ["text": text, "modifiedAt": Int64((modified?.timeIntervalSince1970 ?? 0) * 1000)]
            total += text.utf8.count
          } catch { if record { throw error }; skipped += 1 }
        }
      }
    }
    guard documents.keys.contains(where: { allowed.contains($0) }) else { throw WenkuProtocolError.invalidInput }
    return ["documents": documents, "skippedFiles": skipped]
  }

  private func finish(_ value: Any?) {
    let callback = pending
    pending = nil
    operation = nil
    if let file = exportFile { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    exportFile = nil
    callback?(value)
  }
}
