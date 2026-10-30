import Foundation

enum ChaosToken: String, Codable, CaseIterable, Identifiable {
    case plus1 = "+1", zero = "0"
    case minus1 = "-1", minus2 = "-2", minus3 = "-3", minus4 = "-4"
    case minus5 = "-5", minus6 = "-6", minus7 = "-7", minus8 = "-8"
    case skull, cultist, tablet, elderThing, autoFail, elderSign
    case bless, curse, frost

    var id: String { rawValue }

    var label: String {
        switch self {
        case .skull: "Skull"
        case .cultist: "Cultist"
        case .tablet: "Tablet"
        case .elderThing: "Elder Thing"
        case .autoFail: "Auto-fail"
        case .elderSign: "Elder Sign"
        case .bless: "Bless"
        case .curse: "Curse"
        case .frost: "Frost"
        default: rawValue
        }
    }

    var isSymbol: Bool { Int(rawValue) == nil && self != .plus1 }

    var systemImage: String? {
        switch self {
        case .skull: "theatermasks.fill"
        case .cultist: "person.fill.questionmark"
        case .tablet: "rectangle.portrait.fill"
        case .elderThing: "staroflife.fill"
        case .autoFail: "xmark.octagon.fill"
        case .elderSign: "star.circle.fill"
        case .bless: "sun.max.fill"
        case .curse: "moon.fill"
        case .frost: "snowflake"
        default: nil
        }
    }
}

enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case easy, standard, hard, expert
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Night of the Zealot chaos bag presets.
    var preset: [ChaosToken] {
        let symbols: [ChaosToken] = [.skull, .skull, .cultist, .tablet, .autoFail, .elderSign]
        switch self {
        case .easy:
            return [.plus1, .plus1, .zero, .zero, .zero, .minus1, .minus1, .minus1, .minus2, .minus2] + symbols
        case .standard:
            return [.plus1, .zero, .zero, .minus1, .minus1, .minus1, .minus2, .minus2, .minus3, .minus4] + symbols
        case .hard:
            return [.zero, .zero, .zero, .minus1, .minus1, .minus2, .minus2, .minus3, .minus3, .minus4, .minus5] + symbols
        case .expert:
            return [.zero, .minus1, .minus1, .minus2, .minus2, .minus3, .minus3, .minus4, .minus4, .minus5, .minus6, .minus8] + symbols
        }
    }
}
