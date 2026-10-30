import SwiftUI

struct InspectorView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        if let id = store.selectedID, let loc = store.state.locate(id) {
            let inst = store.state[loc.zone][loc.index]
            let card = store.card(for: inst)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CardFaceView(instance: inst, card: card)
                        .frame(maxWidth: .infinity)
                        .frame(height: card?.isHorizontal == true ? 240 : 400)
                        .rotationEffect(.degrees(inst.exhausted ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: inst.exhausted)
                        .contentShape(Rectangle())
                        .onTapGesture { store.zoom(id) }
                        .help("Click to zoom")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card?.displayName ?? inst.code).font(.title3.weight(.semibold))
                        Text([card?.typeName, card?.encounterName, "In \(loc.zone.title)"].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if inst.showingBack { Text("Showing back").font(.caption).foregroundStyle(.secondary) }
                    }

                    HStack {
                        Button { store.flip(id) } label: { Label("Flip", systemImage: "arrow.left.arrow.right") }
                        Button { store.toggleExhaust(id) } label: {
                            Label(inst.exhausted ? "Ready" : "Exhaust", systemImage: inst.exhausted ? "arrow.uturn.backward" : "arrow.turn.down.right")
                        }
                        Button { store.zoom(id) } label: { Label("Zoom", systemImage: "plus.magnifyingglass") }
                        MoveMenu(id: id).fixedSize()
                    }

                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        TokenRow(id: id, label: "Clues", icon: "magnifyingglass", color: .teal, key: \.clues, value: inst.clues)
                        TokenRow(id: id, label: "Doom", icon: "hourglass", color: .red, key: \.doom, value: inst.doom)
                        TokenRow(id: id, label: "Damage", icon: "heart.fill", color: Color(red: 0.6, green: 0.1, blue: 0.1), key: \.damage, value: inst.damage,
                                 limit: card?.health)
                        TokenRow(id: id, label: "Horror", icon: "brain.head.profile", color: .blue, key: \.horror, value: inst.horror,
                                 limit: card?.sanity)
                        TokenRow(id: id, label: "Resources / Uses", icon: "circle.hexagongrid.fill", color: .orange, key: \.resources, value: inst.resources)
                    }

                    if loc.zone == .map {
                        Button("Bring to Front") { store.bringToFront(id) }.buttonStyle(.borderless)
                    }

                    if let card, card.typeCode == "location", let clues = card.clues {
                        Button("Place \(clues) printed clue\(clues == 1 ? "" : "s")") {
                            store.adjust(id, \.clues, by: clues, label: "Clues")
                        }
                        .help("Adds the card's printed clue value. Adjust for per-investigator values yourself.")
                    }
                }
                .padding(12)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "hand.tap").font(.largeTitle).foregroundStyle(.tertiary)
                Text("Click a card to inspect it.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct TokenRow: View {
    @Environment(GameStore.self) private var store
    let id: UUID
    let label: String
    let icon: String
    let color: Color
    let key: WritableKeyPath<CardInstance, Int>
    let value: Int
    var limit: Int? = nil

    var body: some View {
        GridRow {
            Label(label, systemImage: icon).foregroundStyle(color).labelStyle(.titleAndIcon)
            HStack(spacing: 6) {
                Button { store.adjust(id, key, by: -1, label: label) } label: { Image(systemName: "minus.circle") }
                    .disabled(value == 0)
                Text(limit.map { "\(value) / \($0)" } ?? "\(value)").monospacedDigit().frame(minWidth: 44)
                Button { store.adjust(id, key, by: 1, label: label) } label: { Image(systemName: "plus.circle") }
            }
            .buttonStyle(.borderless)
            .font(.title3)
        }
    }
}

extension Card {
    var typeName: String { typeCode.replacingOccurrences(of: "_", with: " ").capitalized }
}
