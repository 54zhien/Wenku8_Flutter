import Foundation

enum WenkuProtocolError: Error {
  case invalidInput, invalidResponse, invalidImageURL, sessionChanged, encoding
}

/// Protocol rules shared by the iOS bridge and executable Foundation tests.
enum WenkuProtocol {
  static let responseLimit = 8 * 1024 * 1024

  static func form(action: String, now: Int64) -> Data {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    let encoded = Data(action.utf8).base64EncodedString()
      .addingPercentEncoding(withAllowedCharacters: allowed)!
    return Data("appver=1.13&request=\(encoded)&timetoken=\(now)".utf8)
  }

  static func validateBody(_ source: String) throws -> String {
    let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = text.lowercased()
    guard !text.isEmpty, source.utf8.count <= responseLimit,
      Int(text) == nil,
      !lower.hasPrefix("<html"), !lower.hasPrefix("<!doctype html"),
      !lower.hasPrefix("<error"),
      !(lower.hasPrefix("<?xml") && lower.contains("<error")),
      !(lower.hasPrefix("<") && lower.contains("<html"))
    else { throw WenkuProtocolError.invalidResponse }
    return source
  }

  static func imageURL(_ raw: String) throws -> URL {
    guard let url = URL(string: raw), let host = url.host?.lowercased(),
      url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
      url.port == nil || url.port == 443,
      ["wenku8.com", "wenku8.net", "wenku8.cn"].contains(where: {
        host == $0 || host.hasSuffix("." + $0)
      }) || host == "pic.777743.xyz"
    else { throw WenkuProtocolError.invalidImageURL }
    return url
  }

  static func imageRedirect(from: URL, location: String) throws -> URL {
    guard let target = URL(string: location, relativeTo: from)?.absoluteURL,
      var parts = URLComponents(url: target, resolvingAgainstBaseURL: true),
      ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
      parts.port == nil || parts.port == 80 || parts.port == 443
    else { throw WenkuProtocolError.invalidImageURL }
    parts.scheme = "https"
    if parts.port == 80 { parts.port = nil }
    guard let url = parts.url else { throw WenkuProtocolError.invalidImageURL }
    return try imageURL(url.absoluteString)
  }

  static func sessionCookie(in headers: [String]) -> String? {
    for header in headers {
      if header.range(of: #"(?i)(?:^|;)\s*max-age\s*=\s*0(?:;|$)"#, options: .regularExpression) != nil { continue }
      guard let range = header.range(of: #"(?:^|[,;]\s*)PHPSESSID=([A-Za-z0-9,-]{8,256})(?=;|$)"#, options: .regularExpression) else { continue }
      let match = String(header[range]).trimmingCharacters(in: CharacterSet(charactersIn: ",; "))
      return String(match.dropFirst("PHPSESSID=".count))
    }
    return nil
  }
}

/// Confined to the bridge's account queue; generations reject late responses.
struct WenkuSessionState {
  private(set) var cookie: String?
  private(set) var revision: UInt64 = 0

  init(cookie: String? = nil) { self.cookie = cookie }

  mutating func invalidate() {
    cookie = nil
    revision &+= 1
  }

  @discardableResult
  mutating func accept(_ cookie: String, expectedRevision: UInt64) -> Bool {
    guard expectedRevision == revision else { return false }
    self.cookie = cookie
    revision &+= 1
    return true
  }
}
