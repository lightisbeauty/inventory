# Changelog

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
