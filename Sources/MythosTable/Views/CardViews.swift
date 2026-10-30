import AppKit
import SwiftUI

let cardAspect: CGFloat = 300.0 / 419.0

/// Loads an ArkhamDB image path through the disk cache.
struct CardImageView: View {
    let path: String
    var fallbackTitle: String = ""
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    .overlay {
                        if failed {
                            Text(fallbackTitle).font(.caption2).multilineTextAlignment(.center).padding(4)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
            }
        }
        .task(id: path) {
            image = nil
            failed = false
            image = await ImageCache.shared.image(for: path)
            failed = image == nil
        }
    }
}

/// Drawn stand-in for card backs; no back artwork ships with the app.
struct CardBackView: View {
    var encounter: Bool
    var title: String? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(
                colors: encounter ? [Color(red: 0.18, green: 0.25, blue: 0.22), Color(red: 0.08, green: 0.12, blue: 0.10)]
                                  : [Color(red: 0.30, green: 0.20, blue: 0.12), Color(red: 0.14, green: 0.09, blue: 0.05)],
                startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: encounter ? "eye.trianglebadge.exclamationmark" : "book.closed.fill")
                        .font(.title3)
                    Text(title ?? (encounter ? "Encounter" : "Player")).font(.caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(4)
            }
    }
}

/// Front or back face for a card instance.
struct CardFaceView: View {
    let instance: CardInstance
    let card: Card?
    var faceDown = false

    var body: some View {
        Group {
            if faceDown {
                CardBackView(encounter: card?.isEncounterCard ?? false)
            } else if instance.showingBack {
                if let back = card?.backimagesrc {
                    CardImageView(path: back, fallbackTitle: card?.displayName ?? instance.code)
                } else {
                    CardBackView(encounter: card?.isEncounterCard ?? false)
                }
            } else if let front = card?.imagesrc {
                CardImageView(path: front, fallbackTitle: card?.displayName ?? instance.code)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    .overlay(Text(card?.displayName ?? instance.code).font(.caption2).padding(4))
            }
        }
    }
}

struct TokenBadges: View {
    let instance: CardInstance

    var body: some View {
        let items: [(Int, Color, String)] = [
            (instance.clues, .teal, "magnifyingglass"),
            (instance.doom, .red, "hourglass"),
            (instance.damage, Color(red: 0.6, green: 0.1, blue: 0.1), "heart.fill"),
            (instance.horror, .blue, "brain.head.profile"),
            (instance.resources, .orange, "circle.hexagongrid.fill"),
        ].filter { $0.0 > 0 }
        VStack(alignment: .trailing, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 2) {
                    Image(systemName: item.2).font(.system(size: 9))
                    Text("\(item.0)").font(.system(size: 11, weight: .bold)).monospacedDigit()
                }
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(item.1, in: Capsule())
                .foregroundStyle(.white)
            }
        }
        .padding(3)
    }
}

/// A card as it appears in zones and on the map: face, exhaust rotation, token badges, selection ring.
struct CardThumb: View {
    @Environment(GameStore.self) private var store
    let instance: CardInstance
    var width: CGFloat = 80
    var faceDown = false

    var body: some View {
        let card = store.card(for: instance)
        let horizontal = (card?.isHorizontal ?? false) && !faceDown
        let w = horizontal ? width / cardAspect : width
        let h = horizontal ? width : width / cardAspect
        CardFaceView(instance: instance, card: card, faceDown: faceDown)
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topTrailing) { TokenBadges(instance: instance) }
            .overlay {
                if store.selectedID == instance.id {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .shadow(radius: 1.5, y: 1)
            .rotationEffect(.degrees(instance.exhausted ? 90 : 0))
            .frame(width: instance.exhausted ? h : w, height: instance.exhausted ? w : h)
            .help(faceDown ? "" : (card?.displayName ?? instance.code))
    }
}

struct ChaosTokenView: View {
    let token: ChaosToken
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5)
            if let symbol = token.systemImage {
                Image(systemName: symbol).font(.system(size: size * 0.45))
            } else {
                Text(token.rawValue).font(.system(size: size * 0.42, weight: .bold)).monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .help(token.label)
    }

    private var fill: Color {
        switch token {
        case .autoFail: .red
        case .elderSign: Color(red: 0.2, green: 0.5, blue: 0.3)
        case .skull, .cultist, .tablet, .elderThing: Color(red: 0.35, green: 0.2, blue: 0.4)
        case .bless: .yellow.opacity(0.85)
        case .curse: .purple
        case .frost: .cyan
        default: Color(white: 0.3)
        }
    }
}

/// "Move to…" menu shared by the inspector and context menus.
struct MoveMenu: View {
    @Environment(GameStore.self) private var store
    let id: UUID
    var label: String = "Move to…"

    var body: some View {
        Menu(label) {
            ForEach(Zone.allCases) { zone in
                if zone.isDeck {
                    Button("Top of \(zone.title)") { store.move(id, to: zone) }
                    Button("Bottom of \(zone.title)") { store.move(id, to: zone, bottom: true) }
                    Button("Shuffle into \(zone.title)") { store.move(id, to: zone); store.shuffle(zone) }
                    Divider()
                } else {
                    Button(zone.title) { store.move(id, to: zone) }
                }
            }
        }
    }
}

extension View {
    /// Click to select, drag to another zone, right-click for quick actions.
    func cardInteractions(_ instance: CardInstance, store: GameStore, draggable: Bool = true) -> some View {
        self
            .contentShape(Rectangle())
            .onTapGesture { store.selectedID = instance.id }
            .contextMenu {
                Button(instance.exhausted ? "Ready" : "Exhaust") { store.toggleExhaust(instance.id) }
                Button("Flip") { store.flip(instance.id) }
                Divider()
                MoveMenu(id: instance.id)
            }
            .modifier(OptionalDraggable(id: instance.id, enabled: draggable))
    }
}

private struct OptionalDraggable: ViewModifier {
    let id: UUID
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.draggable(id.uuidString) } else { content }
    }
}
