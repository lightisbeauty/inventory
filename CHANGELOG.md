# Changelog

## v26062606 — 2026-06-27

### Added
- Update checker — checks GitHub Releases on launch and notifies when a new version is available
- "Check for Updates…" menu item for manual checks at any time
- "Automatically Check for Updates" toggle in the inventory menu (on by default, persists across restarts)


## v26062605 — 2026-06-27

### Added
- Snapshot library — Save Snapshot stores a timestamped report to `~/Library/Application Support/inventory/snapshots/`
- In-app snapshot picker — Compare now shows a list of saved snapshots (newest first) instead of a raw file picker
- Delete snapshots directly from the picker; list refreshes in place
- "Compare from file…" fallback at the bottom of the picker for external HTML files
- Export bar redesigned as a 2×2 grid: Save Snapshot / Export HTML / Compare / Export PDF


## v26062604 — 2026-06-26

### Added
- Compare diff cards are now collapsible — launch collapsed by default
- System card always appears first in the diff; remaining sections sorted alphabetically
- Each diff card shows a total change count badge


## v26062603 — 2026-06-26

### Added
- Compare diff now includes a System card — tracks macOS version, model, chip, memory, and serial number between scans
- 30-second timeout on all scanner subprocess calls — prevents any single stuck tool from hanging the report

### Fixed
- App now signed and notarized with Developer ID — resolves "damaged" Gatekeeper error on Sequoia and Tahoe
- Fixed scan hang on machines with large inventories — pipe buffer deadlock in the Swift wrapper caused indefinite hang on "Scanning system…"
- Removed Edit menu from menu bar (Cut/Copy/Paste don't apply to this app)


## v26062502 — 2026-06-25

### Added
- App icon (inventory-icon.svg) — navy background with grid motif, blue i letterform, magenta accents


## v26062501 — 2026-06-25

### Added
- Compare feature — import any previous HTML report and view a delta (Added / Removed / Updated) per section
- Export filenames now include date and serial number: `inventory_YYMMDD_SERIALNUMBER.html/.pdf`

### Fixed
- Removed menu bar app card (apps are already enumerated in /Applications)
- Repo renamed to lowercase `inventory`


## v26062402 — 2026-06-24

### Fixed
- PDF export now renders all cards expanded (switched from print pipeline to createPDF API)
- Homebrew/mas detection in .app context (PATH not inherited from shell)
- Removed all password/authorization prompts (system_profiler, sfltool, osascript)

### Added
- Move-to-Applications prompt on first launch
- Pip packages: repo links and hover descriptions via batch metadata
- Ruby gems: repo links and hover descriptions via parallel spec lookup

## v26062401 — 2026-06-24

### Initial release
- Native macOS app — scans system software and displays interactive HTML report
- Scans: /Applications, ~/Applications, Homebrew (casks + formulae), Mac App Store, MacPorts, Fink, Nix, pip, npm, gem, cargo, conda, Launch Agents, Launch Daemons
- System info header: model, chip, memory, macOS version, serial number
- Export as PDF (all sections expanded) or HTML via native save dialogs
- Homebrew/pip/gem entries include clickable repo links and hover descriptions
- Auto-installs Homebrew + mas on first run for full App Store inventory
- Homebrew sections hidden if mas is the only user-installed formula
- All data fetched concurrently — no elevated access required
- Distributed as DMG with drag-to-Applications layout
