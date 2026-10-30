import SwiftUI

/// Full-window view of one card so its text is readable. Viewing the other side
/// here doesn't flip the card on the table.
struct CardZoomOverlay: View {
    let instance: CardInstance
    let card: Card?
    let onClose: () -> Void
    @State private var showBack: Bool

    init(instance: CardInstance, card: Card?, onClose: @escaping () -> Void) {
        self.instance = instance
        self.card = card
        self.onClose = onClose
        _showBack = State(initialValue: instance.showingBack)
    }

    private var shownSide: CardInstance {
        var side = instance
        side.showingBack = showBack
        return side
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.75))
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 12) {
                CardFaceView(instance: shownSide, card: card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(radius: 20)
                    .padding(.horizontal, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture(perform: onClose)

                HStack(spacing: 12) {
                    Text(card?.displayName ?? instance.code).font(.headline).foregroundStyle(.white)
                    Picker("", selection: $showBack) {
                        Text("Front").tag(false)
                        Text("Back").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Button("Close", action: onClose).keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(24)
        }
        .transition(.opacity)
    }
}
