import AppKit
import SwiftUI

/// A rules primer in our own words, with pointers to the matching MythosTable controls.
/// It covers the classic Core Set rules used by Night of the Zealot; the official
/// Rules Reference is the authority for edge cases.
struct GuideSection: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let paragraphs: [String]
    var tip: String? = nil
}

enum Guide {
    static let sections: [GuideSection] = [
        GuideSection(id: "welcome", title: "Welcome", icon: "hand.wave", paragraphs: [
            "Arkham Horror: The Card Game is a cooperative game. You play an investigator working through a story scenario: you gather **clues** to move the **act** deck forward while **doom** builds up and pushes the **agenda** deck toward disaster.",
            "MythosTable is a card table, not a rules engine. It shuffles, draws, tracks tokens and keeps a log, but **you** read each card and decide what happens. This guide covers the basics; for edge cases, check the official Rules Reference.",
            "Short on time? Read **Your First Game**, then **The Round**, then come back to the rest as questions come up.",
        ]),
        GuideSection(id: "first", title: "Your First Game", icon: "flag.checkered", paragraphs: [
            "**1. Pick a difficulty.** Open **Table → Chaos Bag…** and choose Easy, Standard, Hard, or Expert. New players should start on Easy or Standard. The bag is saved with your campaign.",
            "**2. Import a deck.** Choose **Table → Import Deck…** and enter an ArkhamDB decklist ID or URL. Decklist **1** is the Roland Banks starter deck, which works well for learning.",
            "**3. Set up the scenario.** Choose **Table → Set Up Scenario…**, select **The Gathering**, check the encounter sets, and click **Set Up**. The agenda and act decks, the scenario reference card, the locations, and a shuffled encounter deck are laid out for you.",
            "**4. Follow the campaign guide's setup.** Open the **Tray** tab on the right and drag the starting location onto the map. Locations start on their unrevealed side; click **Flip** to reveal one, then **Place printed clues**. Leave any other set-aside cards where the guide tells you.",
            "**5. Draw your opening hand.** You start with **5 resources** (shown in the top bar). Click **Opening Hand** to draw 5 cards. If you draw a weakness, move it aside, draw a replacement, and shuffle the weakness back into your deck once your hand is final. You may **Mulligan** once to replace any cards you don't want.",
            "**6. Play.** The first round begins in the **Investigation** phase, because round 1 skips the Mythos phase. You have 3 actions. Use **Next Phase** to move through the round.",
        ], tip: "Read the agenda and act cards before you start; double-click any card to zoom in."),
        GuideSection(id: "round", title: "The Round", icon: "arrow.triangle.2.circlepath", paragraphs: [
            "Every round has four phases, in this order. The top bar tracks the round number and phase; **Next Phase** (⇧⌘N) advances them and starts a new round after Upkeep.",
            "**Mythos phase** (skipped in round 1)\n• Place 1 doom on the current agenda.\n• Check the doom: if the total doom on **all** cards in play reaches the agenda's threshold, the agenda advances.\n• Each investigator draws 1 encounter card.",
            "**Investigation phase**\n• Each investigator takes a turn of up to **3 actions**.",
            "**Enemy phase**\n• Ready enemies with **Hunter** that aren't engaged move one location toward the nearest investigator.\n• Each ready enemy engaged with you attacks, then exhausts.",
            "**Upkeep phase**\n• Ready all exhausted cards.\n• Each investigator draws 1 card and gains 1 resource.\n• If you hold more than **8 cards**, discard down to 8.",
        ], tip: "Doom counter: the top bar adds up all doom in play and compares it to the current agenda's threshold. It turns red when the threshold is reached. Use the agenda's Advance button, then Clear Doom, when that happens."),
        GuideSection(id: "actions", title: "Your Turn: Actions", icon: "figure.walk", paragraphs: [
            "On your turn you take up to 3 actions, in any order, and you can repeat them. The pips in the top bar track the actions you have left; click one to spend it.",
            "**Investigate**: run an Intellect test against the location's shroud. If you succeed, take 1 clue from the location.",
            "**Move**: go to a location connected to yours (the symbols on the location card show connections).",
            "**Draw**: draw 1 card. **Resource**: gain 1 resource.",
            "**Play**: pay an asset's cost to put it into play, or play an event for its one-time effect (then discard the event).",
            "**Activate**: use a card ability marked with the action arrow.",
            "**Fight**: run a Combat test against an enemy's fight value. If you succeed, deal 1 damage, plus any bonus from your weapon.",
            "**Evade**: run an Agility test against an enemy's evade value. If you succeed, exhaust the enemy and disengage from it.",
            "**Engage**: engage an enemy at your location. Some cards also offer **Parley** or **Resign** actions.",
            "**Attacks of opportunity:** while a ready enemy is engaged with you, every action except Fight, Evade, Parley, and Resign gives each such enemy a free attack. Attacks of opportunity don't exhaust the enemy.",
        ], tip: "Your resources are the coin counter in the top bar. Track uses and charges on a card with Resources / Uses in the inspector."),
        GuideSection(id: "tests", title: "Skill Tests & the Chaos Bag", icon: "bag", paragraphs: [
            "Most actions are **skill tests**: Willpower, Intellect, Combat, or Agility against a difficulty number.",
            "**1. Commit cards.** You may commit cards from your hand whose skill icons match the test (a ? icon matches any skill). Each matching icon adds +1.",
            "**2. Reveal a chaos token.** Click **Reveal Token** (⌘T). The result is logged.",
            "**3. Apply the token.** A number changes your skill value. **Skull, Cultist, Tablet, and Elder Thing** do what the scenario reference card says for your difficulty. **Elder Sign** triggers your investigator's elder sign ability. **Auto-fail** means you fail no matter what.",
            "**4. Compare.** If your adjusted skill value is **equal to or higher than** the difficulty, you succeed. Then resolve the effects and discard the committed cards.",
        ], tip: "Keep the scenario reference card handy: double-click it to zoom, and use Flip for the Hard/Expert side."),
        GuideSection(id: "locations", title: "Locations & Clues", icon: "map", paragraphs: [
            "Locations start unrevealed. When an investigator enters one, flip it to its revealed side and place clues equal to its clue value. A value marked \"per investigator\" is multiplied by the number of investigators, which is just 1 when you play solo.",
            "Clues you discover go on your investigator. When you have enough, you can spend them to advance the act.",
        ], tip: "In MythosTable, drag locations from the Tray tab onto the map and arrange them like the layout in the campaign guide. Track clues on the location card, and on your investigator card once you take them."),
        GuideSection(id: "enemies", title: "Enemies", icon: "exclamationmark.triangle", paragraphs: [
            "An enemy drawn from the encounter deck spawns engaged with you at your location, unless its **Spawn** instruction puts it somewhere else.",
            "An engaged enemy stays with you and attacks during the Enemy phase. Defeat it by dealing damage equal to its health; a defeated enemy with **Victory** points goes to the victory display, and any other goes to the encounter discard.",
            "**Keywords:** **Hunter** enemies move toward investigators during the Enemy phase. **Aloof** enemies don't engage on their own. **Retaliate** enemies attack you when you fail to fight them. **Prey** tells a hunter which investigator to chase.",
        ], tip: "Put engaged enemies in your Threat Area, or on the map next to their location if they aren't engaged. Track damage on enemies with the inspector."),
        GuideSection(id: "encounter", title: "Encounter Cards", icon: "rectangle.stack", paragraphs: [
            "Encounter cards are drawn in the Mythos phase and whenever a card tells you to. **Treacheries** take effect right away and are then discarded, unless the card says it stays in play. **Enemies** spawn as described above.",
            "**Surge** means you draw another encounter card. **Peril** means other investigators can't help you with that card.",
            "When the encounter deck runs out, shuffle its discard pile back in to form a new deck.",
        ], tip: "Draw (⌘E) moves the top encounter card to your Threat Area and opens it in the inspector. From there, Move to… Encounter Discard, the map, or wherever it belongs. When the deck runs out, the discard is shuffled back in for you."),
        GuideSection(id: "agenda", title: "Agenda & Act", icon: "book", paragraphs: [
            "The **agenda** is the clock. When the doom in play reaches its threshold, the agenda advances: remove all doom from play, flip the card, and follow its back side. If the last agenda advances, something terrible usually happens.",
            "The **act** is your objective. Most acts tell you how many clues to spend; you can spend them in any player window to advance. Some acts have an **Objective** that works differently, so read each one carefully.",
        ], tip: "Each deck's Advance button flips the top card. Clicking it again removes that card so the next one is on top. Clear Doom removes all doom in play in one step."),
        GuideSection(id: "defeat", title: "Damage, Horror & Defeat", icon: "heart.slash", paragraphs: [
            "Your investigator has **health** and **sanity**. If the damage on you reaches your health, or the horror reaches your sanity, you are **defeated** and out of the scenario. Some assets, such as allies, can absorb damage or horror instead.",
            "Defeat in a campaign brings **trauma**: physical trauma if you were defeated by damage, mental trauma if by horror. You start each later scenario with 1 damage per physical trauma and 1 horror per mental trauma.",
            "If your player deck runs out, shuffle your discard pile into a new deck and take 1 horror.",
        ], tip: "Track damage and horror on your investigator card in the inspector; it shows them against your health and sanity. Record trauma in the Campaign Log."),
        GuideSection(id: "campaign", title: "Ending a Scenario", icon: "trophy", paragraphs: [
            "A scenario ends with a **resolution** in the campaign guide, reached by advancing the last act, by the agenda running out, or by being defeated. Read the resolution and record what it tells you.",
            "**Experience (XP):** add up the Victory points in the victory display, plus any bonus the resolution gives. Spend XP between scenarios to upgrade your deck on ArkhamDB, then import the updated deck.",
        ], tip: "Open Table → Campaign Log… (⇧⌘L) to record the resolution and XP (added to each surviving investigator), trauma, and notes. It's saved between scenarios."),
        GuideSection(id: "claude", title: "Playing with Claude", icon: "sparkles", paragraphs: [
            "Open the **Claude** tab to have Claude act as your game master. You make every decision for your investigator; Claude carries them out and runs the rest of the game.",
            "**On your turn**, type what you do in plain words, like \"Investigate the Study, committing Magnifying Glass\" or \"Move to the Hallway\", or start one with the quick buttons. Claude spends the action and resolves it: it reveals a chaos token for any test, then handles clues, damage, newly revealed locations, enemies, attacks of opportunity, and act objectives.",
            "**When you're done**, click **End Turn** (⇧⌘↩). Claude runs the Enemy and Upkeep phases and the next round's Mythos phase (encounter cards, doom, hunters, attacks, and cleanup), then hands the turn back to you.",
            "**Your choices stay yours.** Whenever a card gives you a choice, Claude asks in the panel and waits for your answer.",
            "After **Set Up Scenario**, **Place Starting Locations** lets Claude lay out the opening map for you.",
        ], tip: "By default Claude runs through Claude Code on your Claude plan, with no extra charges; install Claude Code and sign in once. You can switch to an API key instead in the Claude tab. Either way, you can still fix anything by hand with the normal table controls, and Claude picks up the current table state each time."),
        GuideSection(id: "controls", title: "MythosTable Controls", icon: "keyboard", paragraphs: [
            "**Cards:** click to inspect, double-click (or ⌘Y) to zoom, right-click for quick actions, and drag to move a card between zones or onto the map. On the map, drag a card to reposition it.",
            "**Readability:** **View → Card Size** makes every card bigger. The zoom view lets you flip between front and back without changing the table.",
            "**Shortcuts:** ⌘D draw a player card · ⌘E draw an encounter card · ⌘T reveal a chaos token · ⇧⌘N next phase · ⇧⌘R ready all · ⌘S save table · ⌘O open table.",
            "**Search…** on any pile shows its contents so you can pull out a specific card (for example, to find a card the scenario tells you to search for).",
            "The table is saved automatically. Use **File → Save Table…** to keep a snapshot.",
        ]),
    ]
}

struct HowToPlayView: View {
    @State private var selection: String? = Guide.sections.first?.id
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            List(Guide.sections, selection: $selection) { section in
                Label(section.title, systemImage: section.icon).tag(section.id)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            if let section = Guide.sections.first(where: { $0.id == selection }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(section.title, systemImage: section.icon)
                            .font(.largeTitle.weight(.semibold))
                            .padding(.bottom, 4)
                        ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, text in
                            Text(LocalizedStringKey(text))
                                .font(.title3)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        if let tip = section.tip {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                                Text(LocalizedStringKey(tip)).font(.body).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        }
                        navigation(for: section)
                    }
                    .padding(28)
                    .frame(maxWidth: 760, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            // macOS can reopen this window by itself at launch; make sure the table comes back too.
            let tableOpen = NSApp.windows.contains { $0.isVisible && $0.identifier?.rawValue.hasPrefix("table") == true }
            if !tableOpen { openWindow(id: "table") }
        }
    }

    @ViewBuilder private func navigation(for section: GuideSection) -> some View {
        let all = Guide.sections
        if let i = all.firstIndex(of: section) {
            HStack {
                if i > 0 {
                    Button { selection = all[i - 1].id } label: { Label(all[i - 1].title, systemImage: "chevron.left") }
                }
                Spacer()
                if i < all.count - 1 {
                    Button { selection = all[i + 1].id } label: {
                        Label(all[i + 1].title, systemImage: "chevron.right").labelStyle(TrailingIconLabelStyle())
                    }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                }
            }
            .padding(.top, 12)
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}
