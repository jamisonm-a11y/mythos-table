import SwiftUI

/// Accepts cards dragged from any other zone.
struct ZoneDrop: ViewModifier {
    @Environment(GameStore.self) private var store
    let zone: Zone
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                }
            }
            .dropDestination(for: String.self) { items, _ in
                for item in items { if let id = UUID(uuidString: item) { store.move(id, to: zone) } }
                return true
            } isTargeted: { targeted = $0 }
    }
}

extension View {
    func acceptsCards(into zone: Zone) -> some View { modifier(ZoneDrop(zone: zone)) }
}

struct ZoneHeader: View {
    let title: String
    var count: Int?
    var body: some View {
        HStack(spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            if let count { Text("\(count)").font(.caption2).monospacedDigit().foregroundStyle(.tertiary) }
        }
    }
}

/// Horizontal strip of face-up cards (threat area, play area, hand, ...).
struct ZoneStrip: View {
    @Environment(GameStore.self) private var store
    let zone: Zone
    var cardWidth: CGFloat = 70
    var minHeight: CGFloat = 110
    @AppStorage("cardScale") private var cardScale = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZoneHeader(title: zone.title, count: store.state[zone].count)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(store.state[zone]) { inst in
                        CardThumb(instance: inst, width: cardWidth)
                            .cardInteractions(inst, store: store)
                    }
                    if store.state[zone].isEmpty {
                        Text("Drop cards here").font(.caption).foregroundStyle(.tertiary)
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding(.vertical, 4)
                .frame(minHeight: minHeight * cardScale, alignment: .leading)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .acceptsCards(into: zone)
    }
}

/// A stacked pile: deck, discard, agenda, act. Shows the top card (face down for hidden decks).
struct PileView<Actions: View>: View {
    @Environment(GameStore.self) private var store
    let zone: Zone
    var cardWidth: CGFloat = 70
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        let pile = store.state[zone]
        VStack(alignment: .leading, spacing: 4) {
            ZoneHeader(title: zone.title, count: pile.count)
            HStack(alignment: .top, spacing: 8) {
                Group {
                    if let top = pile.first(where: { _ in zone.isDeck }) ?? pile.last {
                        CardThumb(instance: top, width: cardWidth, faceDown: zone.isFaceDown)
                            .cardInteractions(top, store: store, draggable: true)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .frame(width: cardWidth, height: cardWidth / cardAspect)
                            .overlay(Text("Empty").font(.caption2).foregroundStyle(.tertiary))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    actions()
                    Button("Search…") { store.searchZone = zone }
                        .disabled(pile.isEmpty)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .acceptsCards(into: zone)
    }
}

extension PileView where Actions == EmptyView {
    init(zone: Zone, cardWidth: CGFloat = 70) {
        self.init(zone: zone, cardWidth: cardWidth) { EmptyView() }
    }
}

/// Free-position canvas for locations and enemies.
struct MapCanvas: View {
    @Environment(GameStore.self) private var store
    static let size = CGSize(width: 2400, height: 1600)

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(store.state[.map]) { inst in
                    MapCard(instance: inst)
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .coordinateSpace(name: "map")
            .background(
                LinearGradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.17), Color(red: 0.10, green: 0.12, blue: 0.11)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .dropDestination(for: String.self) { items, location in
                for (i, item) in items.enumerated() {
                    if let id = UUID(uuidString: item) {
                        store.move(id, to: .map, position: CGPoint(x: location.x + CGFloat(i) * 20, y: location.y))
                    }
                }
                return true
            }
        }
        .overlay(alignment: .topLeading) {
            ZoneHeader(title: "Map", count: store.state[.map].count)
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .padding(8)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MapCard: View {
    @Environment(GameStore.self) private var store
    let instance: CardInstance
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        CardThumb(instance: instance, width: 100)
            .position(x: instance.position.x + dragOffset.width, y: instance.position.y + dragOffset.height)
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named("map"))
                    .onChanged { value in
                        if dragOffset == .zero { store.bringToFront(instance.id) }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let p = CGPoint(
                            x: min(max(instance.position.x + value.translation.width, 40), MapCanvas.size.width - 40),
                            y: min(max(instance.position.y + value.translation.height, 40), MapCanvas.size.height - 40))
                        dragOffset = .zero
                        store.setPosition(instance.id, p)
                    }
            )
            .onTapGesture { store.selectedID = instance.id }
            .simultaneousGesture(TapGesture(count: 2).onEnded { store.zoom(instance.id) })
            .contextMenu { CardContextMenu(instance: instance, store: store) }
    }
}
