#!/bin/bash
# Apex Agents - One-Line Installer
# curl -sL https://raw.githubusercontent.com/YOUR_USERNAME/apex-agents/main/install.sh | bash

set -e

REPO="saeed9321/apex-agents"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/$REPO/$BRANCH"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}       🐝 ${YELLOW}APEX AGENTS INSTALLER${NC} 🐝               ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}       Multi-Agent Coordination Hive             ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# Detect install location
if [ -d "./skills" ]; then
    INSTALL_DIR="./skills/apex-agents"
    echo -e "${GREEN}📁 Installing to workspace:${NC} $INSTALL_DIR"
elif [ -n "$CLAWDBOT_SKILLS" ]; then
    INSTALL_DIR="$CLAWDBOT_SKILLS/apex-agents"
    echo -e "${GREEN}📁 Installing to Clawdbot skills:${NC} $INSTALL_DIR"
else
    INSTALL_DIR="$HOME/.local/share/apex-agents"
    echo -e "${GREEN}📁 Installing to:${NC} $INSTALL_DIR"
fi

# Create directories
mkdir -p "$INSTALL_DIR"/{scripts,references,templates}
mkdir -p "$HOME/.config/apex-agents"

echo ""
echo -e "${BLUE}📦 Downloading skill files...${NC}"

# Download all files
FILES=(
    "SKILL.md"
    "scripts/quick-setup.sh"
    "scripts/setup.sh"
    "scripts/check-tasks.sh"
    "scripts/update-task.sh"
    "scripts/test-connection.sh"
    "scripts/queen-decompose.sh"
    "scripts/queen-assign.sh"
    "scripts/queen-status.sh"
    "scripts/hive-channel.sh"
    "scripts/a2a-setup.sh"
    "references/HIVEMIND.md"
    "references/LINEAR-API.md"
    "references/A2A.md"
    "templates/config.json"
)

for file in "${FILES[@]}"; do
    echo -n "  ↓ $file "
    if curl -sfL "$BASE_URL/$file" -o "$INSTALL_DIR/$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}(skipped)${NC}"
    fi
done

# Make scripts executable
chmod +x "$INSTALL_DIR/scripts/"*.sh 2>/dev/null || true

echo ""
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "  ${YELLOW}Next step: Run the setup wizard${NC}"
echo ""
echo -e "  ${BLUE}bash $INSTALL_DIR/scripts/quick-setup.sh${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Ask to run setup now
read -p "Run setup wizard now? (Y/n): " RUN_SETUP
RUN_SETUP=${RUN_SETUP:-Y}

if [ "$RUN_SETUP" == "Y" ] || [ "$RUN_SETUP" == "y" ]; then
    echo ""
    bash "$INSTALL_DIR/scripts/quick-setup.sh"
fi
