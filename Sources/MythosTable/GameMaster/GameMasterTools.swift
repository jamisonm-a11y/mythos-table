import Foundation

/// The table controls the game master can use, expressed as Messages API tools, plus the
/// code that carries them out against the GameStore. These are the same
/// operations a human player has; rules adjudication stays with the model.
enum GameMasterTools {
    static func schema(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }

    static let zoneNames = Zone.allCases.map(\.rawValue)
    static let tokenNames = ["clues", "doom", "damage", "horror", "resources"]

    static let definitions: [[String: Any]] = [
        ["name": "get_table_state",
         "description": "Returns the whole table: round, phase, actions left, resource pool, doom vs. threshold, every zone's cards (id, name, type, side, exhausted, tokens, map position), hidden deck sizes, the chaos bag, and your notes. Call this at the start and whenever you're unsure of the state.",
         "input_schema": schema([:])],
        ["name": "get_cards",
         "description": "Returns full rules text and stats for cards on the table by instance id (from get_table_state): type, traits, cost, skill icons, health/sanity, shroud, clue value, enemy fight/health/evade/damage/horror, victory, and the text of both sides. Read a card before you resolve or play it.",
         "input_schema": schema(["ids": ["type": "array", "items": ["type": "string"], "description": "Card instance ids"]], required: ["ids"])],
        ["name": "move_card",
         "description": "Moves a card to a zone. For decks (agenda, act, encounterDeck, playerDeck) it goes on top unless bottom is true. Cards leaving play lose their tokens and become ready. For the map, give x/y (canvas is 2400x1600; place connected locations ~170 px apart, enemies just below their location).",
         "input_schema": schema([
            "id": ["type": "string"],
            "zone": ["type": "string", "enum": zoneNames],
            "bottom": ["type": "boolean"],
            "x": ["type": "number"], "y": ["type": "number"],
         ], required: ["id", "zone"])],
        ["name": "adjust_tokens",
         "description": "Adds (positive delta) or removes (negative delta) tokens on a card: clues, doom, damage, horror, or resources (resources also tracks uses such as ammo, secrets, or charges). The investigator card holds the player's clues, damage, and horror.",
         "input_schema": schema([
            "id": ["type": "string"],
            "token": ["type": "string", "enum": tokenNames],
            "delta": ["type": "integer"],
         ], required: ["id", "token", "delta"])],
        ["name": "flip_card",
         "description": "Flips a card to its other side (e.g. reveal a location: the back side is the unrevealed side; flip an agenda/act to its b side).",
         "input_schema": schema(["id": ["type": "string"]], required: ["id"])],
        ["name": "set_exhausted",
         "description": "Exhausts or readies a card.",
         "input_schema": schema(["id": ["type": "string"], "exhausted": ["type": "boolean"]], required: ["id", "exhausted"])],
        ["name": "draw_player_cards",
         "description": "Draws cards from the top of the player deck into the hand. If the deck is empty, the discard pile is reshuffled into it (the investigator then takes 1 horror; apply it with adjust_tokens).",
         "input_schema": schema(["count": ["type": "integer", "minimum": 1, "maximum": 10]], required: ["count"])],
        ["name": "draw_encounter_card",
         "description": "Draws the top encounter card into the threat area and returns it with its full text. Resolve it, then move it where it belongs (e.g. encounterDiscard for most treacheries, or spawn an enemy).",
         "input_schema": schema([:])],
        ["name": "shuffle",
         "description": "Shuffles a zone, usually encounterDeck or playerDeck.",
         "input_schema": schema(["zone": ["type": "string", "enum": zoneNames]], required: ["zone"])],
        ["name": "reveal_chaos_token",
         "description": "Draws a random token from the chaos bag for a skill test and returns it. Always use this; never invent a result.",
         "input_schema": schema(["test": ["type": "string", "description": "What the test is, e.g. 'Investigate Study: Intellect 3 + 1 committed vs shroud 2'"]], required: ["test"])],
        ["name": "adjust_resources",
         "description": "Changes the investigator's resource pool (positive to gain, negative to pay).",
         "input_schema": schema(["delta": ["type": "integer"]], required: ["delta"])],
        ["name": "spend_action",
         "description": "Spends one of the investigator's actions this turn and records what it was.",
         "input_schema": schema(["description": ["type": "string"]], required: ["description"])],
        ["name": "advance",
         "description": "Advances the agenda or act deck: the first call flips the top card to its b side; the next call removes it so the next stage is on top. Clear doom with adjust_tokens when the rules require it.",
         "input_schema": schema(["deck": ["type": "string", "enum": ["agenda", "act"]]], required: ["deck"])],
        ["name": "next_phase",
         "description": "Ends the current phase and moves to the next one (Mythos → Investigation → Enemy → Upkeep → next round's Mythos). Entering Investigation resets actions to 3.",
         "input_schema": schema([:])],
        ["name": "set_investigator_location",
         "description": "Records which map location the investigator is at. Call it after every move, including when a card moves them.",
         "input_schema": schema(["id": ["type": "string", "description": "Location id on the map"]], required: ["id"])],
        ["name": "ask_player",
         "description": "Asks the player a question and waits for their answer. Use it for every decision that belongs to the investigator (choices on cards, damage assignment, discards, optional abilities, spending clues). Give short choices when the options are known; the player can also type a free answer.",
         "input_schema": schema([
            "question": ["type": "string"],
            "choices": ["type": "array", "items": ["type": "string"]],
         ], required: ["question"])],
        ["name": "narrate",
         "description": "Tells the player what you're doing and why, in one or two short sentences. Use it before each action and to report test results.",
         "input_schema": schema(["text": ["type": "string"]], required: ["text"])],
        ["name": "remember",
         "description": "Saves a short note for later requests (set-aside cards, delayed effects, scenario reminders). Notes persist between requests. Pass replace_all to rewrite the whole list.",
         "input_schema": schema(["note": ["type": "string"], "replace_all": ["type": "boolean"]], required: ["note"])],
        ["name": "end_scenario",
         "description": "Call when the scenario reaches a resolution or the investigator is defeated.",
         "input_schema": schema(["resolution": ["type": "string"]], required: ["resolution"])],
    ]
}

// MARK: - Execution

extension GameStore {
    /// Short, stable id for a card instance in tool payloads.
    func shortID(_ id: UUID) -> String { String(id.uuidString.prefix(6)).lowercased() }

    func resolveShortID(_ short: String) -> UUID? {
        let key = short.lowercased().trimmingCharacters(in: .whitespaces)
        for cards in state.zones.values {
            if let inst = cards.first(where: { shortID($0.id) == key }) { return inst.id }
        }
        return nil
    }

    func tableSnapshot() -> [String: Any] {
        func describe(_ inst: CardInstance, zone: Zone) -> [String: Any] {
            let card = card(for: inst)
            var d: [String: Any] = ["id": shortID(inst.id), "name": card?.displayName ?? inst.code, "type": card?.typeCode ?? "unknown"]
            if card?.hasBackImage == true || card?.backText != nil {
                d["side"] = inst.showingBack ? "back" : "front"
                if card?.typeCode == "location" { d["revealed"] = !inst.showingBack }
            }
            if inst.exhausted { d["exhausted"] = true }
            for (name, value) in [("clues", inst.clues), ("doom", inst.doom), ("damage", inst.damage),
                                  ("horror", inst.horror), ("resources", inst.resources)] where value > 0 {
                d[name] = value
            }
            if zone == .map { d["x"] = Int(inst.position.x); d["y"] = Int(inst.position.y) }
            return d
        }

        var zones: [String: Any] = [:]
        for zone in Zone.allCases {
            let cards = state[zone]
            switch zone {
            case .encounterDeck, .playerDeck:
                zones[zone.rawValue] = ["count": cards.count]
            case .agenda, .act:
                zones[zone.rawValue] = ["count": cards.count, "top": cards.first.map { describe($0, zone: zone) } as Any]
            default:
                zones[zone.rawValue] = cards.map { describe($0, zone: zone) }
            }
        }
        var bag: [String: Int] = [:]
        for token in activeCampaign?.chaosBag ?? [] { bag[token.label, default: 0] += 1 }

        return [
            "scenario": state.scenarioName ?? "none",
            "difficulty": activeCampaign?.difficulty.title ?? "Standard",
            "round": state.round,
            "phase": state.phase.rawValue,
            "actions_remaining": state.actionsRemaining,
            "resource_pool": state.resourcePool,
            "doom_in_play": totalDoom,
            "doom_threshold": doomThreshold as Any,
            "zones": zones,
            "chaos_bag": bag,
            "notes": state.autopilotNotes ?? [],
            "investigator_location": state.investigatorLocationID
                .flatMap { id in state.locate(id)?.zone == .map ? ["id": shortID(id), "name": name(of: id)] : nil } as Any,
        ]
    }

    func cardDetails(_ inst: CardInstance) -> [String: Any] {
        guard let c = card(for: inst) else { return ["id": shortID(inst.id), "code": inst.code, "error": "card data not loaded"] }
        var d: [String: Any] = ["id": shortID(inst.id), "name": c.displayName, "type": c.typeCode]
        let optional: [(String, Any?)] = [
            ("back_name", c.backName), ("traits", c.traits), ("faction", c.factionCode), ("subtype", c.subtypeCode),
            ("cost", c.cost), ("xp", c.xp), ("slot", c.slot),
            ("willpower", c.skillWillpower), ("intellect", c.skillIntellect), ("combat", c.skillCombat),
            ("agility", c.skillAgility), ("wild", c.skillWild),
            ("health", c.health), ("sanity", c.sanity), ("health_per_investigator", c.healthPerInvestigator),
            ("shroud", c.shroud), ("clue_value", c.clues), ("clues_fixed", c.cluesFixed),
            ("doom_threshold", c.typeCode == "agenda" ? c.doom : nil), ("stage", c.stage),
            ("enemy_fight", c.enemyFight), ("enemy_evade", c.enemyEvade),
            ("enemy_damage", c.enemyDamage), ("enemy_horror", c.enemyHorror),
            ("victory", c.victory), ("encounter_set", c.encounterName),
            ("text", c.text), ("back_text", c.backText),
        ]
        for (key, value) in optional { if let value { d[key] = value } }
        d["showing"] = inst.showingBack ? "back" : "front"
        return d
    }

    /// Runs one tool call. Returns the JSON-serializable result, or throws a message for an error result.
    func runTool(_ tool: String, _ input: [String: Any]) throws -> Any {
        func id(_ key: String = "id") throws -> UUID {
            guard let short = input[key] as? String, let uuid = resolveShortID(short) else {
                throw ToolError("Unknown card id \(input[key] ?? "nil"). Call get_table_state for current ids.")
            }
            return uuid
        }
        func int(_ key: String) throws -> Int {
            if let i = input[key] as? Int { return i }
            if let d = input[key] as? Double { return Int(d) }
            throw ToolError("Missing integer \(key).")
        }

        switch tool {
        case "get_table_state":
            return tableSnapshot()

        case "get_cards":
            guard let ids = input["ids"] as? [String] else { throw ToolError("ids must be an array of strings.") }
            return ids.map { short -> Any in
                guard let uuid = resolveShortID(short), let inst = state.instance(uuid) else { return ["id": short, "error": "unknown id"] }
                if let loc = state.locate(uuid), loc.zone.isFaceDown { return ["id": short, "error": "card is face down in a deck"] }
                return cardDetails(inst)
            }

        case "move_card":
            let uuid = try id()
            guard let zoneName = input["zone"] as? String, let zone = Zone(rawValue: zoneName) else { throw ToolError("Unknown zone.") }
            var position: CGPoint?
            if let x = input["x"] as? Double, let y = input["y"] as? Double { position = CGPoint(x: x, y: y) }
            if let x = input["x"] as? Int, let y = input["y"] as? Int { position = CGPoint(x: x, y: y) }
            move(uuid, to: zone, bottom: input["bottom"] as? Bool ?? false, position: position)
            return "Moved \(name(of: uuid)) to \(zone.title)."

        case "adjust_tokens":
            let uuid = try id()
            let delta = try int("delta")
            let keys: [String: WritableKeyPath<CardInstance, Int>] = [
                "clues": \.clues, "doom": \.doom, "damage": \.damage, "horror": \.horror, "resources": \.resources]
            guard let token = input["token"] as? String, let key = keys[token] else { throw ToolError("Unknown token type.") }
            adjust(uuid, key, by: delta, label: token.capitalized)
            return "\(name(of: uuid)) now has \(state.instance(uuid)?[keyPath: key] ?? 0) \(token)."

        case "flip_card":
            let uuid = try id()
            flip(uuid)
            return cardDetails(state.instance(uuid)!)

        case "set_exhausted":
            let uuid = try id()
            let want = input["exhausted"] as? Bool ?? true
            if state.instance(uuid)?.exhausted != want { toggleExhaust(uuid) }
            return "\(name(of: uuid)) is \(want ? "exhausted" : "ready")."

        case "draw_player_cards":
            let count = try int("count")
            var drawn: [String] = []
            for _ in 0..<count {
                let before = state[.hand].count
                drawPlayerCard()
                if state[.hand].count > before, let inst = state[.hand].last {
                    drawn.append("\(card(for: inst)?.displayName ?? inst.code) [\(shortID(inst.id))]")
                }
            }
            return ["drawn": drawn, "hand_size": state[.hand].count]

        case "draw_encounter_card":
            drawEncounterCard()
            guard let inst = state[.threatArea].first else { throw ToolError("No encounter card could be drawn.") }
            return cardDetails(inst)

        case "shuffle":
            guard let zoneName = input["zone"] as? String, let zone = Zone(rawValue: zoneName) else { throw ToolError("Unknown zone.") }
            shuffle(zone)
            return "Shuffled \(zone.title)."

        case "reveal_chaos_token":
            if let test = input["test"] as? String { log("Skill test: \(test)") }
            revealChaosToken()
            guard let token = state.lastToken else { throw ToolError("The chaos bag is empty.") }
            return ["token": token.label]

        case "adjust_resources":
            adjustResources(try int("delta"))
            return ["resource_pool": state.resourcePool]

        case "spend_action":
            guard state.actionsRemaining > 0 else { throw ToolError("No actions remaining this turn.") }
            setActions(state.actionsRemaining - 1)
            log("Action: \(input["description"] as? String ?? "action") (\(state.actionsRemaining) left).")
            return ["actions_remaining": state.actionsRemaining]

        case "advance":
            let zone: Zone = (input["deck"] as? String) == "act" ? .act : .agenda
            advance(zone)
            return ["top": state[zone].first.map { cardDetails($0) } as Any, "remaining": state[zone].count]

        case "next_phase":
            nextPhase()
            return ["round": state.round, "phase": state.phase.rawValue]

        case "set_investigator_location":
            let uuid = try id()
            guard state.locate(uuid)?.zone == .map else { throw ToolError("That card isn't on the map.") }
            setInvestigatorLocation(uuid)
            return "The investigator is at \(name(of: uuid))."

        case "narrate":
            return "ok"

        case "remember":
            let note = input["note"] as? String ?? ""
            if input["replace_all"] as? Bool == true {
                state.autopilotNotes = note.split(separator: "\n").map(String.init)
            } else {
                state.autopilotNotes = (state.autopilotNotes ?? []) + [note]
            }
            return ["notes": state.autopilotNotes ?? []]

        case "end_scenario":
            log("Scenario ended: \(input["resolution"] as? String ?? "").")
            return "Recorded. Stop playing now."

        default:
            throw ToolError("Unknown tool \(tool).")
        }
    }
}

struct ToolError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
