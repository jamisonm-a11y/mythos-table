import Foundation
import Security

/// Minimal Messages API client over raw HTTP (there is no official Swift SDK).
/// Bodies are kept as JSON dictionaries so assistant content, including thinking
/// blocks, can be sent back exactly as received.
struct ClaudeClient {
    static let model = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    let apiKey: String

    struct Usage {
        var input = 0, output = 0, cacheRead = 0, cacheWrite = 0

        mutating func add(_ json: [String: Any]?) {
            guard let json else { return }
            input += json["input_tokens"] as? Int ?? 0
            output += json["output_tokens"] as? Int ?? 0
            cacheRead += json["cache_read_input_tokens"] as? Int ?? 0
            cacheWrite += json["cache_creation_input_tokens"] as? Int ?? 0
        }

        /// Estimate at Claude Opus 5.5 list prices: $4 input, $20 output, $0.20 cache
        /// read, and $5 cache write (1.25x input) per million tokens.
        var estimatedDollars: Double {
            (Double(input) * 4 + Double(output) * 20 + Double(cacheRead) * 0.2 + Double(cacheWrite) * 5) / 1_000_000
        }
    }

    enum ClientError: LocalizedError {
        case http(Int, String)
        case badResponse
        var errorDescription: String? {
            switch self {
            case .http(let code, let message): "Claude API error \(code): \(message)"
            case .badResponse: "Couldn't read the Claude API response."
            }
        }
    }

    func send(system: String, tools: [[String: Any]], messages: [[String: Any]], effort: String) async throws -> [String: Any] {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": effort],
            // Re-run a safety-classifier decline on Anthropic's recommended fallback model.
            "fallbacks": "default",
            // Cache the stable prefix (tools, system, earlier turns) across the loop.
            "cache_control": ["type": "ephemeral"],
            "system": system,
            "tools": tools,
            "messages": messages,
        ]
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 600)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var attempt = 0
        while true {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClientError.badResponse }
                return json
            }
            // Retry rate limits, overload, and server errors with backoff.
            if (status == 429 || status == 529 || status >= 500) && attempt < 3 {
                attempt += 1
                let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
                try await Task.sleep(for: .seconds(retryAfter ?? pow(2, Double(attempt))))
                continue
            }
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                ?? String(data: data, encoding: .utf8) ?? ""
            throw ClientError.http(status, message)
        }
    }
}

/// Stores the Anthropic API key in the login keychain.
enum APIKeyStore {
    private static let service = "local.mythostable.anthropic"
    private static let account = "api-key"

    static func load() -> String? {
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty { return env }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(key.utf8),
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
