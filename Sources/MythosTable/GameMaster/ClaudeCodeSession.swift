import Foundation

/// A long-running headless Claude Code process (`claude -p` with stream-json in and
/// out). It signs in with the user's own Claude Code login, so usage counts against
/// their Claude plan instead of an API key. Its only tools are MythosTable's,
/// served over the local MCP endpoint; all built-in tools are disabled.
@MainActor
final class ClaudeCodeSession {
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stderrText = ""

    /// Called on the main actor for each JSON event Claude Code prints.
    var onEvent: (([String: Any]) -> Void)?
    /// Called on the main actor when the process exits.
    var onExit: ((_ status: Int32, _ stderr: String) -> Void)?

    var isAlive: Bool { process?.isRunning == true }

    static func findExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            UserDefaults.standard.string(forKey: "claudeCodePath"),
            "\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
            "/usr/local/bin/claude", "/opt/homebrew/bin/claude",
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    enum SessionError: LocalizedError {
        case notInstalled
        var errorDescription: String? {
            "Claude Code isn't installed. Install it from claude.com/claude-code, run `claude` once in Terminal to sign in, then try again."
        }
    }

    func start(mcpURL: String, token: String, systemPrompt: String, effort: String) throws {
        guard let executable = Self.findExecutable() else { throw SessionError.notInstalled }
        let mcpConfig: [String: Any] = ["mcpServers": ["mythostable": [
            "type": "http", "url": mcpURL, "headers": ["Authorization": "Bearer \(token)"],
        ]]]
        let mcpJSON = String(data: try JSONSerialization.data(withJSONObject: mcpConfig), encoding: .utf8) ?? "{}"

        let workDir = Storage.root.appendingPathComponent("claude-session", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.currentDirectoryURL = workDir
        process.arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--tools", "",                       // no built-in tools: no shell, no file access
            "--mcp-config", mcpJSON,
            "--strict-mcp-config",
            "--allowedTools", "mcp__mythostable",
            "--system-prompt", systemPrompt,
            "--model", "opus",
            "--effort", effort,
            "--no-session-persistence",
        ]
        var env = ProcessInfo.processInfo.environment
        // Use the Claude Code login (subscription), never a pay-per-use key from the environment.
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        // ask_player waits for the human, which can take a while.
        env["MCP_TOOL_TIMEOUT"] = "3600000"
        env["PATH"] = [env["PATH"], "/usr/local/bin", "/opt/homebrew/bin", "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin"]
            .compactMap { $0 }.joined(separator: ":")
        process.environment = env

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let lineBuffer = Box(Data())
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            lineBuffer.value.append(chunk)
            while let newline = lineBuffer.value.firstIndex(of: 0x0A) {
                let line = lineBuffer.value[lineBuffer.value.startIndex..<newline]
                lineBuffer.value = Data(lineBuffer.value[lineBuffer.value.index(after: newline)...])
                guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                Task { @MainActor in self?.onEvent?(event) }
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(data: handle.availableData, encoding: .utf8) ?? ""
            guard !text.isEmpty else { return }
            Task { @MainActor in self?.stderrText += text }
        }
        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            Task { @MainActor in
                guard let self else { return }
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                if self.process === proc { self.process = nil; self.stdinHandle = nil }
                self.onExit?(status, self.stderrText)
            }
        }

        stderrText = ""
        try process.run()
        self.process = process
        self.stdinHandle = stdin.fileHandleForWriting
    }

    func send(_ text: String) {
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": [["type": "text", "text": text]]]]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        stdinHandle?.write(data + Data([0x0A]))
    }

    func stop() {
        stdinHandle = nil
        process?.terminate()
        process = nil
    }
}
