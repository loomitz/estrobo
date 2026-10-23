import Foundation
import CryptoKit

// Diagnose the native networking stack without modifying either release app.
guard NSUserName() == "runner", FileManager.default.homeDirectoryForCurrentUser.path == "/Users/runner",
      ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" else {
    fatalError("Disposable hosted qualification user required")
}
let configuration = URLSessionConfiguration.ephemeral
configuration.httpCookieStorage = nil
configuration.httpShouldSetCookies = false
configuration.urlCredentialStorage = nil
configuration.urlCache = nil
configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
configuration.timeoutIntervalForRequest = 20
configuration.timeoutIntervalForResource = 30
let session = URLSession(configuration: configuration)
let trace = CommandLine.arguments.last == "trace"
let url = URL(string: trace ? "https://estrobo.app/cdn-cgi/trace" : "https://estrobo.app/updates/macos/appcast.xml")!
let probes = trace ? [("GET", "Estrobo Updater")] : [("HEAD", "Estrobo Updater"), ("GET", "estrobo/0.1.0 Sparkle/2.10.0")]
var results: [[String: Any]] = []
for (method, agent) in probes {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue(agent, forHTTPHeaderField: "User-Agent")
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    var result: [String: Any] = ["method": method, "userAgent": agent]
    do {
        let (data, response) = try await session.data(for: request)
        if let response = response as? HTTPURLResponse {
            result["status"] = response.statusCode
            result["cacheControl"] = response.value(forHTTPHeaderField: "Cache-Control")
            result["challenge"] = response.value(forHTTPHeaderField: "cf-mitigated")
            result["ray"] = response.value(forHTTPHeaderField: "cf-ray")
        }
        result["sha256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if trace {
            let fields = String(decoding: data, as: UTF8.self).split(separator: "\n").map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
            result["address"] = fields.first { $0.count == 2 && $0[0] == "ip" }?.last
        }
    } catch {
        let error = error as NSError
        result["errorDomain"] = error.domain
        result["errorCode"] = error.code
        result["errorDescription"] = error.localizedDescription
    }
    results.append(result)
}
let bytes = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
print(String(decoding: bytes, as: UTF8.self))
