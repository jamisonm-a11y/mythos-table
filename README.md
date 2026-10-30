# MythosTable

A manual solo table for Arkham Horror: The Card Game (Night of the Zealot). It handles the bookkeeping only; you rule on all card text yourself.

## Build & run
```
./scripts/make-app.sh --install                        # builds MythosTable.app into ~/Applications
swift run MythosTable                                  # or run directly
.build/debug/MythosTable --self-test                   # headless setup check (writes nothing)
```

## Data (personal use)
No card text or images ship with the app. Everything is fetched from arkhamdb.com at runtime and cached in
`~/Library/Application Support/MythosTable/`:
- `cards/*.json`: raw API responses (core, rcore, plus single cards fetched for imported decks)
- `images/`: card images
- `scenarios.json`: editable scenario setup (encounter sets, set-aside sets, random set choices, set-aside card names)
- `campaigns.json`: campaign log and chaos bag for each campaign
- `autosave.json`: the current table

Revised core uses `rcore` for player cards plus `core` for encounter cards, which keep their original codes.

## Game Master
You play the investigator; Claude (Claude Opus 5.5, via the Anthropic Messages API) runs everything else from the
Game Master tab.

- **Declare actions** in your own words ("Investigate the Study, committing Magnifying Glass", "Move to the Hallway").
  Claude spends the action and resolves it: skill tests with the chaos bag, clues, damage, revealing locations,
  enemies, attacks of opportunity, forced effects, and act objectives.
- **End Turn** (⇧⌘↩): Claude runs the Enemy, Upkeep, and next Mythos phases, including encounter cards, doom, and
  cleanup, then hands the turn back to you.
- **Your decisions stay yours.** Whenever a card or rule gives the investigator a choice, Claude asks you in the panel.
- **Place Starting Locations** lets Claude lay out the scenario's opening map after Set Up Scenario.

Two ways to run Claude (choose in the Claude tab):

- **Claude plan (default):** the app starts a headless [Claude Code](https://claude.com/claude-code) session signed in
  with your Claude account, so play counts toward your plan's usage limits with no API charges. MythosTable serves
  its table tools to that session over a local MCP endpoint (127.0.0.1 only, with a per-launch token), and Claude
  Code's built-in tools (shell, files) are turned off. Requires Claude Code installed and signed in (`claude`, then
  `/login`).
- **API key:** calls the Anthropic Messages API directly with your own key (stored in the macOS keychain, or read
  from `ANTHROPIC_API_KEY`), billed per use; the panel shows an estimated cost. Requests opt in to server-side
  refusal fallbacks (`fallbacks: "default"`), and each request is capped at 80 model calls.

Test modes: `--self-test` (offline), `--mcp-test` (serves the tools for 30 s), and `--gm-test` (one real request
through Claude Code).
