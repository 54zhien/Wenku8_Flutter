import Flutter
import Foundation
import CoreFoundation
import CryptoKit
import ImageIO

/// Receives bytes incrementally so an oversized response is never fully buffered.
private final class WenkuTransfer: NSObject, URLSessionDataDelegate {
  private var data = Data()
  private var response: HTTPURLResponse?
  private var failure: Error?
  private var redirects = 0
  private let image: Bool
  private let finished = DispatchSemaphore(value: 0)

  init(image: Bool) { self.image = image }

  func perform(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.httpCookieStorage = nil
    config.urlCache = nil
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 30
    let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    let task = session.dataTask(with: request)
    task.resume()
    guard finished.wait(timeout: .now() + 35) == .success else {
      session.invalidateAndCancel()
      throw URLError(.timedOut)
    }
    session.finishTasksAndInvalidate()
    if let failure { throw failure }
    guard let response, (200...299).contains(response.statusCode), !data.isEmpty else {
      throw WenkuProtocolError.invalidResponse
    }
    return (data, response)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                  didReceive response: URLResponse,
                  completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    guard let http = response as? HTTPURLResponse,
      response.expectedContentLength <= Int64(WenkuProtocol.responseLimit) else {
      failure = WenkuProtocolError.invalidResponse
      completionHandler(.cancel)
      return
    }
    self.response = http
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
    guard data.count + chunk.count <= WenkuProtocol.responseLimit else {
      failure = WenkuProtocolError.invalidResponse
      dataTask.cancel()
      return
    }
    data.append(chunk)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if failure == nil { failure = error }
    finished.signal()
  }

  func urlSession(_ session: URLSession, task: URLSessionTask,
                  willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                  completionHandler: @escaping (URLRequest?) -> Void) {
    guard image, redirects < 3, let from = response.url,
      let location = response.value(forHTTPHeaderField: "Location"),
      let url = try? WenkuProtocol.imageRedirect(from: from, location: location) else {
      completionHandler(nil)
      return
    }
    redirects += 1
    completionHandler(URLRequest(url: url))
  }
}

final class WenkuBridge: NSObject, FlutterPlugin {
  private let accounts = DispatchQueue(label: "wenku8.accounts")
  private let images = DispatchQueue(label: "wenku8.images")
  private let workers: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 4
    return queue
  }()
  private let stateLock = NSLock()
  private var state = WenkuSessionState()
  private var loaded = false
  private let store = WenkuSessionStore()
  private let imageDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("wenku8-illustrations-v1", isDirectory: true)

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "org.mewx.wenku8/legacy_api", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(WenkuBridge(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let methods = ["request", "requestBytes", "cover", "accountRequest", "login", "hasSession", "clearSession", "illustration", "clearIllustrations", "encodeReview"]
    guard methods.contains(call.method) else { result(FlutterMethodNotImplemented); return }
    stateLock.lock()
    if call.method == "clearSession" { state.invalidate(); loaded = true }
    let revision = state.revision
    stateLock.unlock()
    let job = { [self] in
      do {
        let value = try execute(call, revision: revision)
        DispatchQueue.main.async { result(value) }
      } catch WenkuProtocolError.encoding {
        DispatchQueue.main.async { result(FlutterError(code: "REVIEW_ENCODING", message: "无法使用原版书评编码", details: nil)) }
      } catch {
        DispatchQueue.main.async { result(FlutterError(code: "LEGACY_API_ERROR", message: "Request or local storage failed", details: nil)) }
      }
    }
    if ["accountRequest", "login", "hasSession", "clearSession"].contains(call.method) {
      accounts.async(execute: job)
    } else if ["illustration", "clearIllustrations"].contains(call.method) {
      images.async(execute: job)
    } else { workers.addOperation(job) }
  }

  private func execute(_ call: FlutterMethodCall, revision: UInt64) throws -> Any? {
    let args = call.arguments as? [String: Any] ?? [:]
    if ["accountRequest", "login", "hasSession"].contains(call.method) {
      stateLock.lock()
      defer { stateLock.unlock() }
      if !loaded { state = WenkuSessionState(cookie: try store.read()); loaded = true }
    }
    switch call.method {
    case "hasSession":
      stateLock.lock(); defer { stateLock.unlock() }
      return state.cookie != nil
    case "clearSession": try store.write(nil); return nil
    case "encodeReview":
      guard let text = args["text"] as? String, text.utf16.count <= 10000 else { throw WenkuProtocolError.invalidInput }
      let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GBK_95.rawValue)))
      guard let bytes = text.data(using: encoding, allowLossyConversion: false) else { throw WenkuProtocolError.encoding }
      let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-*_".utf8)
      let encoded = bytes.map { byte -> String in
        if byte == 32 { return "+" }
        if safe.contains(byte) { return String(UnicodeScalar(byte)) }
        return String(format: "%%%02X", byte)
      }.joined()
      return Data(encoded.utf8).base64EncodedString()
    case "clearIllustrations":
      if FileManager.default.fileExists(atPath: imageDirectory.path) { try FileManager.default.removeItem(at: imageDirectory) }
      return nil
    case "illustration":
      guard let raw = args["url"] as? String else { throw WenkuProtocolError.invalidInput }
      return FlutterStandardTypedData(bytes: try illustration(raw))
    default: break
    }
    let action: String
    if call.method == "cover" {
      guard let id = args["aid"] as? Int, id > 0 else { throw WenkuProtocolError.invalidInput }
      action = "action=book&do=cover&aid=\(id)"
    } else {
      guard let value = args["action"] as? String, !value.isEmpty, value.utf16.count <= 60000 else { throw WenkuProtocolError.invalidInput }
      action = value
    }
    var cookie: String?
    if call.method == "accountRequest" {
      stateLock.lock()
      let snapshot = state
      stateLock.unlock()
      guard snapshot.revision == revision else { throw WenkuProtocolError.sessionChanged }
      guard let active = snapshot.cookie else { return "4" }
      cookie = active
    }
    if call.method == "login" && !(action.hasPrefix("action=login&") || action.hasPrefix("action=loginemail&")) {
      throw WenkuProtocolError.invalidInput
    }
    let (data, response) = try request(action, cookie: cookie)
    if ["requestBytes", "cover"].contains(call.method) { return FlutterStandardTypedData(bytes: data) }
    guard let text = String(data: data, encoding: .utf8) else { throw WenkuProtocolError.invalidResponse }
    if action.hasPrefix("action=book&do=text&") { _ = try WenkuProtocol.validateBody(text) }
    if ["accountRequest", "login"].contains(call.method) {
      stateLock.lock(); defer { stateLock.unlock() }
      guard state.revision == revision else { throw WenkuProtocolError.sessionChanged }
      if call.method == "login" && text.trimmingCharacters(in: .whitespacesAndNewlines) != "1" { return text }
      let header = response.value(forHTTPHeaderField: "Set-Cookie")
      let incoming = WenkuProtocol.sessionCookie(in: header.map { [$0] } ?? [])
      if call.method == "login" && incoming == nil { throw WenkuProtocolError.invalidResponse }
      if text.trimmingCharacters(in: .whitespacesAndNewlines) != "4", let incoming, incoming != state.cookie {
        try store.write(incoming)
        state.accept(incoming, expectedRevision: revision)
      }
    }
    return text
  }

  private func request(_ action: String, cookie: String?) throws -> (Data, HTTPURLResponse) {
    var request = URLRequest(url: URL(string: "https://wenku8-relay.mewx.org/")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
    if let cookie { request.setValue("PHPSESSID=\(cookie)", forHTTPHeaderField: "Cookie") }
    request.httpBody = WenkuProtocol.form(action: action, now: Int64(Date().timeIntervalSince1970 * 1000))
    return try WenkuTransfer(image: false).perform(request)
  }

  private func validateImage(_ data: Data) throws {
    guard !data.isEmpty, data.count <= WenkuProtocol.responseLimit,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= 50000000 / height else { throw WenkuProtocolError.invalidResponse }
  }

  private func illustration(_ raw: String) throws -> Data {
    let url = try WenkuProtocol.imageURL(raw)
    let name = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    let file = imageDirectory.appendingPathComponent(name)
    let cachedSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
    if let size = cachedSize, size <= WenkuProtocol.responseLimit,
      let data = try? Data(contentsOf: file), (try? validateImage(data)) != nil {
      try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
      return data
    }
    let (data, _) = try WenkuTransfer(image: true).perform(URLRequest(url: url))
    try validateImage(data)
    // Cache failure does not invalidate a successfully downloaded image.
    try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
    trimImages(keeping: file)
    return data
  }

  private func trimImages(keeping file: URL) {
    let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
    let entries = (try? FileManager.default.contentsOfDirectory(at: imageDirectory, includingPropertiesForKeys: Array(keys))) ?? []
    let files = entries.compactMap { url -> (URL, Int, Date)? in
      guard let info = try? url.resourceValues(forKeys: keys), info.isRegularFile == true else { return nil }
      return (url, info.fileSize ?? 0, info.contentModificationDate ?? .distantPast)
    }.sorted { $0.2 < $1.2 }
    var size = files.reduce(0) { $0 + $1.1 }
    for (url, bytes, _) in files where size > 256 * 1024 * 1024 && url != file {
      if (try? FileManager.default.removeItem(at: url)) != nil { size -= bytes }
    }
  }
}
