#!/bin/bash
# Apex Agents - One-Command Install
# Usage: curl -sL https://raw.githubusercontent.com/.../install.sh | bash

set -e

echo "🐝 Apex Agents Installer"
echo "========================"
echo ""

SKILL_DIR="${SKILL_DIR:-$HOME/.config/apex-agents}"
mkdir -p "$SKILL_DIR"

# Detect if we're in a Clawdbot workspace
if [ -d "./skills" ]; then
    SKILL_DIR="./skills/apex-agents"
    echo "📁 Installing to workspace: $SKILL_DIR"
else
    echo "📁 Installing to: $SKILL_DIR"
fi

# Download or copy skill files
if [ -d "/root/clawd/skills/apex-agents" ]; then
    echo "📦 Copying from local..."
    cp -r /root/clawd/skills/apex-agents/* "$SKILL_DIR/" 2>/dev/null || true
else
    echo "📦 Downloading latest..."
    # Would download from GitHub/ClawdHub here
    echo "⚠️  Remote install not yet configured. Copy skill manually."
    exit 1
fi

echo ""
echo "✅ Skill installed!"
echo ""
echo "Next: Run setup"
echo "  bash $SKILL_DIR/scripts/setup.sh"
echo ""
