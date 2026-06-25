#!/bin/bash
# ── Software Inventory — Launcher ────────────────────────────────────────────
# Ensures Homebrew and mas are available for the fullest possible report,
# then runs inventory_mac.py and opens the result.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT="$HOME/Desktop/software_inventory.html"

echo ""
echo "  Software Inventory"
echo "  Light Is Beauty Inc"
echo "  ────────────────────"
echo ""

# ── Python 3 (via Xcode Command Line Tools) ──────────────────────────────────
if ! command -v python3 &>/dev/null; then
    echo "  This tool is built with Python, which isn't installed on this Mac yet."
    echo "  Python is included with Apple's free Xcode Command Line Tools."
    echo ""
    read -rp "  Install Xcode Command Line Tools now? [Y/n] " choice
    choice="${choice:-Y}"
    if [[ "$choice" =~ ^[Yy] ]]; then
        echo ""
        xcode-select --install 2>/dev/null
        echo "  A system dialog should have appeared. Follow the prompts to install,"
        echo "  then re-run this tool when the installation completes."
    else
        echo ""
        echo "  Skipping — this tool cannot run without Python."
    fi
    echo ""
    read -rp "  Press Enter to exit." _
    exit 1
fi

# ── Homebrew + mas ───────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
    echo "  Homebrew is not installed."
    echo "  It's needed to read your full App Store inventory (app names, versions,"
    echo "  and IDs). Without it, the App Store section will be limited or missing."
    echo ""
    read -rp "  Install Homebrew now? [Y/n] " choice
    choice="${choice:-Y}"
    if [[ "$choice" =~ ^[Yy] ]]; then
        echo ""
        echo "  Installing Homebrew (you may be prompted for your password)..."
        echo ""
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Add brew to PATH for this session (Apple Silicon vs Intel)
        if [ -f /opt/homebrew/bin/brew ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -f /usr/local/bin/brew ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
        # Install mas automatically since that's why we installed Homebrew
        if command -v brew &>/dev/null; then
            echo ""
            echo "  Installing mas (Mac App Store CLI)..."
            brew install mas
        fi
        echo ""
    else
        echo ""
        echo "  Skipping — App Store section may be limited."
        echo ""
    fi
elif ! command -v mas &>/dev/null; then
    # Homebrew exists but mas doesn't — user installed brew themselves
    echo "  Installing mas (Mac App Store CLI) for full App Store inventory..."
    brew install mas
    echo ""
fi

# ── Run inventory ────────────────────────────────────────────────────────────
echo "  Scanning system..."
python3 "$SCRIPT_DIR/inventory_mac.py" > "$REPORT"
echo "  Report saved to: $REPORT"
echo ""
open "$REPORT"
echo "  Done. You can re-run this anytime to refresh."
echo ""
read -rp "  Press Enter to close." _
