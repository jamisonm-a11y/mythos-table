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
