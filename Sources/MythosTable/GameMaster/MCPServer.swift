import Foundation
import Network

/// A minimal MCP server (Streamable HTTP transport, JSON responses only) bound to
/// 127.0.0.1, so a local Claude Code session can use the table tools. Every
/// request must carry the per-launch bearer token.
final class MCPServer: @unchecked Sendable {
    typealias ToolHandler = @Sendable (_ name: String, _ arguments: [String: Any]) async -> (text: String, isError: Bool)

    let token = UUID().uuidString
    private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "mythostable.mcp")
    private let tools: [[String: Any]]
    private let handler: ToolHandler

    init(tools: [[String: Any]], handler: @escaping ToolHandler) {
        // MCP uses camelCase inputSchema; the Messages API definitions use input_schema.
        self.tools = tools.map { tool in
            ["name": tool["name"] ?? "", "description": tool["description"] ?? "", "inputSchema": tool["input_schema"] ?? [:]]
        }
        self.handler = handler
    }

    var url: String { "http://127.0.0.1:\(port)/mcp" }

    /// Starts listening on a free localhost port and returns once the port is known.
    func start() async throws {
        if listener != nil { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: params)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = Box(false)
            listener.stateUpdateHandler = { [weak self] state in
                guard !resumed.value else { return }
                switch state {
                case .ready:
                    resumed.value = true
                    self?.port = listener.port?.rawValue ?? 0
                    continuation.resume()
                case .failed(let error):
                    resumed.value = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - HTTP

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            // Handle every complete request in the buffer (keep-alive connections may pipeline).
            while let (request, consumed) = HTTPRequest.parse(buffer) {
                buffer = Data(buffer.dropFirst(consumed))
                self.handle(request, on: connection)
            }
            if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        guard request.headers["authorization"] == "Bearer \(token)" else {
            send(status: 401, body: Data("unauthorized".utf8), on: connection)
            return
        }
        guard request.method == "POST" else {
            // No server-initiated stream; clients fall back to plain POSTs.
            send(status: 405, body: Data(), on: connection)
            return
        }
        guard let message = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            send(status: 400, body: Data("bad json".utf8), on: connection)
            return
        }
        guard let id = message["id"] else {
            // Notifications (e.g. notifications/initialized) get no JSON-RPC response.
            send(status: 202, body: Data(), on: connection)
            return
        }
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        Task {
            let result = await self.dispatch(method: method, params: params)
            var response: [String: Any] = ["jsonrpc": "2.0", "id": id]
            switch result {
            case .success(let value): response["result"] = value
            case .failure(let error): response["error"] = ["code": error.code, "message": error.message]
            }
            let body = (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
            self.send(status: 200, body: body, contentType: "application/json", on: connection)
        }
    }

    private struct RPCError: Error { let code: Int; let message: String }

    private func dispatch(method: String, params: [String: Any]) async -> Result<[String: Any], RPCError> {
        switch method {
        case "initialize":
            return .success([
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "mythostable", "version": "1.0"],
            ])
        case "ping":
            return .success([:])
        case "tools/list":
            return .success(["tools": tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let (text, isError) = await handler(name, arguments)
            return .success(["content": [["type": "text", "text": text]], "isError": isError])
        default:
            return .failure(RPCError(code: -32601, message: "Method not found: \(method)"))
        }
    }

    private func send(status: Int, body: Data, contentType: String = "text/plain", on connection: NWConnection) {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 405: "Method Not Allowed"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
        if status == 405 { head += "Allow: POST\r\n" }
        head += "\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in })
    }
}

/// Just enough HTTP/1.1 request parsing for JSON-RPC over POST.
private struct HTTPRequest {
    var method: String
    var headers: [String: String]
    var body: Data

    /// Returns a request and the number of bytes it used, or nil if the buffer is incomplete.
    static func parse(_ data: Data) -> (HTTPRequest, Int)? {
        guard let headerEnd = data.firstRange(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return nil }
        let body = data[bodyStart..<data.index(bodyStart, offsetBy: length)]
        let consumed = data.distance(from: data.startIndex, to: bodyStart) + length
        return (HTTPRequest(method: requestLine.first.map(String.init) ?? "", headers: headers, body: Data(body)), consumed)
    }
}

/// Mutable state shared with callbacks that all run on one serial queue.
final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
