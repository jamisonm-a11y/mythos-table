import Foundation
import Observation

/// Claude as the game master: the player decides what the investigator does, and
/// Claude carries out the declared actions and everything the game does on its
/// own (encounter cards, enemies, doom, the Mythos/Enemy/Upkeep phases, cleanup).
/// Claude runs either inside a local Claude Code session (the user's Claude plan)
/// or through the Messages API with an API key.
@MainActor
@Observable
final class GameMaster {
    enum Backend: String, CaseIterable, Identifiable {
        case claudeCode, api
        var id: String { rawValue }
        var title: String { self == .claudeCode ? "Claude plan (Claude Code)" : "API key" }
    }

    enum Request {
        case setUpScenario
        /// Runs phases until it is the player's Investigation phase again.
        case runPhases
        /// Resolves an action or effect the player declares in their own words.
        case action(String)
    }

    struct Entry: Identifiable {
        enum Kind { case player, narration, action, result, info, error }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    struct Question: Identifiable {
        let id = UUID()
        let text: String
        let choices: [String]
    }

    var entries: [Entry] = []
    var isRunning = false
    var pendingQuestion: Question?
    var usage = ClaudeClient.Usage()
    var hasAPIKey = APIKeyStore.load() != nil
    var claudeCodeInstalled = ClaudeCodeSession.findExecutable() != nil
    var backend: Backend = Backend(rawValue: UserDefaults.standard.string(forKey: "gameMasterBackend") ?? "") ?? .claudeCode {
        didSet {
            UserDefaults.standard.set(backend.rawValue, forKey: "gameMasterBackend")
            session.stop()
        }
    }
    var effort: String = UserDefaults.standard.string(forKey: "autopilotEffort") ?? "medium" {
        didSet {
            UserDefaults.standard.set(effort, forKey: "autopilotEffort")
            session.stop()  // effort is fixed per Claude Code session
        }
    }

    /// Whether the selected backend can run right now.
    var isReady: Bool { backend == .api ? hasAPIKey : claudeCodeInstalled }

    /// Hard cap on model calls per request so a confused loop can't run up a bill.
    static let maxStepsPerRun = 80

    @ObservationIgnored private let store: GameStore
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var answerContinuation: CheckedContinuation<String, Never>?
    @ObservationIgnored private let session = ClaudeCodeSession()
    @ObservationIgnored private var mcpServer: MCPServer?
    @ObservationIgnored private var phaseAdvanced = false
    @ObservationIgnored private var scenarioEnded = false

    init(store: GameStore) { self.store = store }

    // MARK: - API key

    func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        APIKeyStore.save(trimmed)
        hasAPIKey = true
    }

    func forgetKey() {
        APIKeyStore.delete()
        hasAPIKey = APIKeyStore.load() != nil
    }

    // MARK: - Requests

    /// Ends the player's turn: Claude runs Enemy, Upkeep, and the next Mythos phase.
    func endTurn() {
        guard !isRunning else { return }
        if store.state.phase == .investigation {
            store.setActions(0)
            store.nextPhase()
        }
        submit(.runPhases)
    }

    func submit(_ request: Request) {
        guard !isRunning, isReady else { return }
        switch request {
        case .setUpScenario: add(.info, "Setting up \(store.state.scenarioName ?? "the scenario")…")
        case .runPhases: add(.info, "Running the \(store.state.phase.title) phase…")
        case .action(let text): add(.player, text)
        }
        if backend == .claudeCode {
            submitToClaudeCode(request)
        } else if let key = APIKeyStore.load() {
            submitToAPI(request, key: key)
        }
    }

    private func submitToAPI(_ request: Request, key: String) {
        isRunning = true
        task = Task {
            defer {
                isRunning = false
                task = nil
                pendingQuestion = nil
            }
            let client = ClaudeClient(apiKey: key)
            do {
                switch request {
                case .runPhases:
                    // One fresh conversation per phase keeps each request small.
                    var guardCount = 0
                    while store.state.phase != .investigation && guardCount < 4 {
                        guardCount += 1
                        if try await run(phaseInstruction(), client: client, stopAfterNextPhase: true) { break }
                        if store.state.phase != .investigation { add(.info, "Running the \(store.state.phase.title) phase…") }
                    }
                    if store.state.phase == .investigation {
                        add(.info, "Your turn: round \(store.state.round), \(store.state.actionsRemaining) actions.")
                    }
                case .setUpScenario:
                    _ = try await run(setupInstruction(), client: client, stopAfterNextPhase: false)
                case .action(let text):
                    _ = try await run(actionInstruction(text), client: client, stopAfterNextPhase: false)
                }
            } catch is CancellationError {
                add(.info, "Stopped.")
            } catch {
                add(.error, error.localizedDescription)
            }
        }
    }

    func stop() {
        task?.cancel()
        if backend == .claudeCode {
            session.stop()
            isRunning = false
            add(.info, "Stopped.")
        }
        answer("(The player stopped the game master.)")
    }

    // MARK: - Claude Code backend

    private func submitToClaudeCode(_ request: Request) {
        isRunning = true
        Task {
            do {
                try await ensureSession()
                let text: String
                switch request {
                case .setUpScenario: text = setupInstruction()
                case .runPhases: text = phasesInstruction()
                case .action(let action): text = actionInstruction(action)
                }
                session.send(text + "\n(Call get_table_state first: the player may have changed the table by hand.)")
            } catch {
                add(.error, error.localizedDescription)
                isRunning = false
            }
        }
    }

    private func ensureSession() async throws {
        if session.isAlive { return }
        if mcpServer == nil {
            let server = MCPServer(tools: GameMasterTools.definitions) { [weak self] name, arguments in
                guard let self else { return ("Game master is gone.", true) }
                return await self.handleTool(name, arguments)
            }
            try await server.start()
            mcpServer = server
        }
        guard let server = mcpServer else { return }
        session.onEvent = { [weak self] event in self?.handle(event) }
        session.onExit = { [weak self] status, stderr in
            guard let self else { return }
            if self.isRunning {
                let detail = stderr.split(separator: "\n").suffix(3).joined(separator: " ")
                self.add(.error, "Claude Code stopped unexpectedly (exit \(status)). \(detail)")
                self.isRunning = false
                self.answer("(Claude Code stopped.)")
            }
        }
        try session.start(mcpURL: server.url, token: server.token,
                          systemPrompt: Self.systemPrompt + Self.claudeCodeNote, effort: effort)
        add(.info, "Started a Claude Code session on your Claude plan.")
    }

    private func handle(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "system":
            guard event["subtype"] as? String == "init" else { return }
            let servers = event["mcp_servers"] as? [[String: Any]] ?? []
            if let table = servers.first(where: { $0["name"] as? String == "mythostable" }),
               table["status"] as? String != "connected" {
                add(.error, "Claude Code couldn't connect to the table (status: \(table["status"] ?? "unknown")).")
            }
        case "assistant":
            let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            for block in content where block["type"] as? String == "text" {
                if let text = block["text"] as? String, !text.isEmpty { add(.narration, text) }
            }
        case "result":
            isRunning = false
            pendingQuestion = nil
            if event["is_error"] as? Bool == true || event["subtype"] as? String != "success" {
                let message = event["result"] as? String ?? (event["subtype"] as? String ?? "unknown error")
                if message.localizedCaseInsensitiveContains("login") || message.localizedCaseInsensitiveContains("api key") {
                    add(.error, "Claude Code isn't signed in. Open Terminal, run `claude`, and sign in with your Claude account, then try again. (\(message))")
                } else {
                    add(.error, message)
                }
            } else if store.state.phase == .investigation, scenarioEnded == false {
                add(.info, "Your turn: round \(store.state.round), \(store.state.actionsRemaining) action\(store.state.actionsRemaining == 1 ? "" : "s") left.")
            }
        default:
            break
        }
    }

    // MARK: - Tool calls (both backends)

    private func handleTool(_ name: String, _ input: [String: Any]) async -> (text: String, isError: Bool) {
        show(name, input)
        if name == "ask_player" {
            let answer = await ask(input["question"] as? String ?? "?", choices: input["choices"] as? [String] ?? [])
            return (answer, false)
        }
        do {
            let output = try store.runTool(name, input)
            if name == "reveal_chaos_token" || name == "draw_encounter_card" { add(.result, Self.brief(name, output)) }
            if name == "next_phase" { phaseAdvanced = true }
            if name == "end_scenario" { scenarioEnded = true }
            return (Self.encode(output), false)
        } catch {
            add(.error, "\(name): \(error.localizedDescription)")
            return (error.localizedDescription, true)
        }
    }

    func answer(_ text: String) {
        guard let continuation = answerContinuation else { return }
        answerContinuation = nil
        pendingQuestion = nil
        if !text.hasPrefix("(") { add(.player, text) }
        continuation.resume(returning: text)
    }

    func clearTranscript() { entries.removeAll() }

    private func ask(_ text: String, choices: [String]) async -> String {
        await withCheckedContinuation { continuation in
            answerContinuation = continuation
            pendingQuestion = Question(text: text, choices: choices)
        }
    }

    private func add(_ kind: Entry.Kind, _ text: String) {
        entries.append(Entry(kind: kind, text: text))
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
    }

    // MARK: - Instructions

    private func phaseInstruction() -> String {
        """
        Run the \(store.state.phase.title) phase of round \(store.state.round) completely, following the rules \
        procedure for that phase and resolving every card effect it triggers. Ask the player only for decisions \
        that are theirs. When the phase is over, call next_phase once and stop.
        """
    }

    /// Claude Code keeps one conversation, so it runs all the phases from a single request.
    private func phasesInstruction() -> String {
        """
        Run the game's phases, starting with the current \(store.state.phase.title) phase of round \(store.state.round). \
        For each phase, follow its rules procedure, resolve every card effect it triggers, then call next_phase. \
        Keep going until the phase becomes Investigation, then stop: it's the player's turn.
        """
    }

    private func setupInstruction() -> String {
        """
        Perform the setup for \(store.state.scenarioName ?? "this scenario") from your knowledge of the campaign \
        guide: place the starting location(s) on the map from the locations tray (revealed, with clues), put the \
        investigator at the starting location, and leave set-aside cards in setAside or locationsTray. The agenda, \
        act, and encounter deck are already built. Don't draw the player's opening hand; they do that. Note any \
        scenario reminders with remember, then summarize the setup in two or three sentences.
        """
    }

    private func actionInstruction(_ text: String) -> String {
        """
        The player says: "\(text)"
        Carry this out on the table. If it's an action, spend it, resolve it fully (skill tests, clues, damage, \
        moving and revealing locations, enemies engaging, attacks of opportunity, forced effects, act objectives), \
        then stop. If the player didn't say which cards they commit to a test, commit none. If what they describe \
        isn't legal, explain why with narrate and change nothing.
        """
    }

    // MARK: - Loop

    /// One fresh conversation. Returns true if the scenario ended.
    private func run(_ instruction: String, client: ClaudeClient, stopAfterNextPhase: Bool) async throws -> Bool {
        var messages: [[String: Any]] = [["role": "user", "content": instruction]]

        for _ in 0..<Self.maxStepsPerRun {
            try Task.checkCancellation()
            let response = try await client.send(system: Self.systemPrompt, tools: GameMasterTools.definitions,
                                                 messages: messages, effort: effort)
            try Task.checkCancellation()
            usage.add(response["usage"] as? [String: Any])
            let content = response["content"] as? [[String: Any]] ?? []
            // Send the assistant turn back exactly as received (thinking blocks included).
            messages.append(["role": "assistant", "content": content])

            for block in content where block["type"] as? String == "text" {
                if let text = block["text"] as? String, !text.isEmpty { add(.narration, text) }
            }

            switch response["stop_reason"] as? String {
            case "tool_use":
                var results: [[String: Any]] = []
                phaseAdvanced = false
                scenarioEnded = false
                for block in content where block["type"] as? String == "tool_use" {
                    guard let id = block["id"] as? String, let name = block["name"] as? String else { continue }
                    let (text, isError) = await handleTool(name, block["input"] as? [String: Any] ?? [:])
                    try Task.checkCancellation()
                    var result: [String: Any] = ["type": "tool_result", "tool_use_id": id, "content": text]
                    if isError { result["is_error"] = true }
                    results.append(result)
                }
                // All results for one assistant turn go back in a single user message.
                messages.append(["role": "user", "content": results])
                if scenarioEnded { return true }
                if stopAfterNextPhase && phaseAdvanced { return false }
            case "pause_turn":
                continue
            case "refusal":
                add(.error, "Claude declined to continue this request.")
                return true
            case "max_tokens":
                add(.error, "Claude's response hit the length limit; stopping this request.")
                return false
            default:
                return false
            }
        }
        add(.error, "Stopped after \(Self.maxStepsPerRun) steps without finishing.")
        return true
    }

    private func show(_ name: String, _ input: [String: Any]) {
        switch name {
        case "narrate":
            add(.narration, input["text"] as? String ?? "")
        case "get_table_state", "get_cards", "ask_player":
            break
        default:
            let args = input.sorted { $0.key < $1.key }
                .map { "\($0.key): \(store.resolveShortID("\($0.value)").map { store.name(of: $0) } ?? "\($0.value)")" }
                .joined(separator: ", ")
            add(.action, args.isEmpty ? name : "\(name) (\(args))")
        }
    }

    private static func brief(_ name: String, _ output: Any) -> String {
        let dict = output as? [String: Any]
        if name == "reveal_chaos_token" { return "Chaos token: \(dict?["token"] ?? "?")" }
        return "Encounter card: \(dict?["name"] ?? "?")"
    }

    /// Serializes a tool result, turning nil optionals into JSON null.
    static func encode(_ value: Any) -> String {
        if let string = value as? String { return string }
        let safe = jsonSafe(value)
        guard JSONSerialization.isValidJSONObject(safe),
              let data = try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "\(value)" }
        return text
    }

    private static func jsonSafe(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let wrapped = mirror.children.first?.value else { return NSNull() }
            return jsonSafe(wrapped)
        }
        if let dict = value as? [String: Any] { return dict.mapValues(jsonSafe) }
        if let array = value as? [Any] { return array.map(jsonSafe) }
        return value
    }

    static let systemPrompt = """
    You are the game master for a solo game of Arkham Horror: The Card Game (classic Core Set rules, Night of the \
    Zealot campaign) on MythosTable, a digital card table. A human plays the investigator. You run everything else: \
    you carry out the actions the player declares, resolve every card effect, and run the game's own steps (Mythos, \
    Enemy, and Upkeep phases, encounter cards, enemies, doom, agenda and act, and cleanup). The table doesn't enforce \
    rules; it only does what your tools tell it.

    The player is in charge of the investigator:
    - Never choose an action, a card to play, a target, or any option for the investigator yourself. When the rules \
    or a card give the player a choice (assigning damage to allies, which cards to discard, "choose one" effects, \
    whether to use an optional ability, a Peril decision), call ask_player with a short question and the choices.
    - Be a fair, neutral referee: resolve effects as written, including the bad ones, and don't give strategy advice \
    unless asked.

    How the table works:
    - get_table_state lists every card with a short id. Hidden decks show only counts. Use get_cards to read rules \
    text before resolving anything; never guess a card's text.
    - The investigator card (zone "investigator") holds the player's clues, damage, and horror. The resource pool is \
    separate (adjust_resources). investigator_location says where the investigator is; keep it current with \
    set_investigator_location.
    - Locations sit on the map. A location's back side is its unrevealed side; flip it when it's revealed and place \
    its clue value on it (per-investigator values count once in solo play). Place newly revealed or added locations \
    about 170 px from the locations they connect to.
    - Enemies engaged with the investigator go in threatArea; unengaged enemies go on the map just below their location.
    - Treacheries that stay in play go in threatArea (or wherever their text says); others go to encounterDiscard. \
    Defeated enemies with victory points go to victory, others to encounterDiscard.
    - Assets the player plays go in playArea; spent events and committed cards go to playerDiscard.

    Rules procedure:
    - Mythos phase (skipped in round 1): place 1 doom on the agenda; if doom in play meets the threshold, advance \
    the agenda (remove all doom in play, resolve its back); then draw 1 encounter card and resolve it (Surge means \
    draw another).
    - Investigation phase: the player declares actions. For each one, call spend_action, then resolve it. While \
    engaged with a ready enemy, any action other than fight, evade, parley, or resign provokes an attack of \
    opportunity from each such enemy (it doesn't exhaust them).
    - Enemy phase: unengaged ready hunters move one location toward the investigator; ready enemies at the \
    investigator's location engage; then each ready engaged enemy attacks and exhausts.
    - Upkeep phase: ready all exhausted cards, the investigator draws 1 card and gains 1 resource, then discards \
    down to 8 cards (ask which).
    - Skill tests: skill value + matching committed icons + modifiers, then reveal_chaos_token. Symbol tokens use \
    the scenario reference card for this difficulty; Elder Sign uses the investigator's ability; Auto-fail fails. \
    Succeed if the total is at least the difficulty.
    - Advance the act as soon as its requirements are met and the player agrees to spend the clues.
    - If damage reaches health or horror reaches sanity, the investigator is defeated: call end_scenario.

    Style:
    - Narrate every step briefly with narrate: what happens and why, including each test's math and result.
    - Work quickly; don't deliberate over routine bookkeeping.
    - Use remember for things to track across requests (set-aside cards, delayed effects, scenario reminders).
    - When the request is done, stop calling tools and give a one- or two-sentence summary.
    """

    static let claudeCodeNote = """

    You are running inside MythosTable's game master panel. Your only tools come from the "mythostable" MCP \
    server (they appear as mcp__mythostable__<name>). Requests from the player arrive one at a time in this \
    conversation; the table may have changed between them, so check get_table_state at the start of each one.
    """
}
