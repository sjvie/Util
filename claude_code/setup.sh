#!/bin/bash
set -euo pipefail

# GitHub URLs for configuration files
GITHUB_REPO="https://raw.githubusercontent.com/sjvie/Util/refs/heads/main"
GITHUB_CLAUDE_MD="$GITHUB_REPO/claude_code/CLAUDE.md"
GITHUB_STATUSLINE="$GITHUB_REPO/claude_code/statusline-command.sh"

CLAUDE_DIR="$HOME/.claude"
TMP_DIR=$(mktemp -d)

# Cleanup temporary files on exit
trap 'rm -rf "$TMP_DIR"' EXIT

# Color codes for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
RESET='\033[0m'

# Pretty diff printer
pretty_diff() {
    local old_file="$1"
    local new_file="$2"

    diff -u "$old_file" "$new_file" | while IFS= read -r line; do
        if [[ "$line" =~ ^--- ]]; then
            echo -e "${BLUE}${line}${RESET}"
        elif [[ "$line" =~ ^\+\+\+ ]]; then
            echo -e "${BLUE}${line}${RESET}"
        elif [[ "$line" =~ ^@@ ]]; then
            echo -e "${YELLOW}${line}${RESET}"
        elif [[ "$line" =~ ^\+ ]]; then
            echo -e "${GREEN}${line}${RESET}"
        elif [[ "$line" =~ ^- ]]; then
            echo -e "${RED}${line}${RESET}"
        else
            echo "$line"
        fi
    done
    return 0
}

echo "Installing Claude Code configuration..."
echo ""

# Create ~/.claude directory if it doesn't exist
mkdir -p "$CLAUDE_DIR"

# Function to check and warn about existing files
check_and_warn() {
    local downloaded_file="$1"
    local existing_file="$2"
    local file_name="$3"

    if [ -f "$existing_file" ]; then
        # Compare files
        if cmp -s "$downloaded_file" "$existing_file"; then
            # Files are identical
            echo "✓ $file_name is up to date (no changes needed)"
            return 1
        else
            # Files are different
            echo ""
            echo -e "⚠️  ${YELLOW}$file_name will be modified${RESET}"
            echo ""
            pretty_diff "$existing_file" "$downloaded_file"
            echo ""
            read -p "Apply these changes? (y/N): " -r response < /dev/tty
            if [[ ! $response =~ ^[Yy]$ ]]; then
                echo "Keeping existing $file_name"
                return 1
            fi
        fi
    fi
    return 0
}

# Download files from GitHub
echo "=== Downloading files from GitHub ==="
echo "Downloading CLAUDE.md..."
if ! curl -sSL -o "$TMP_DIR/CLAUDE.md" "$GITHUB_CLAUDE_MD"; then
    echo "Error: Failed to download CLAUDE.md" >&2
    exit 1
fi

echo "Downloading statusline-command.sh..."
if ! curl -sSL -o "$TMP_DIR/statusline-command.sh" "$GITHUB_STATUSLINE"; then
    echo "Error: Failed to download statusline-command.sh" >&2
    exit 1
fi

# Define available plugins and their descriptions
declare -a plugins=(
    "pyright-lsp"
    "typescript-lsp"
    "superpowers"
    "context7"
)

declare -A plugin_descriptions=(
    ["pyright-lsp"]="Python language server"
    ["typescript-lsp"]="TypeScript language server"
    ["superpowers"]="Advanced development superpowers"
    ["context7"]="Enhanced documentation lookup"
)

# Read current settings to get defaults
declare -A enabled_plugins
if [ -f "$CLAUDE_DIR/settings.json" ]; then
    for plugin in "${plugins[@]}"; do
        if grep -q "\"$plugin@claude-plugins-official\"[[:space:]]*:[[:space:]]*true" "$CLAUDE_DIR/settings.json"; then
            enabled_plugins[$plugin]=true
        else
            enabled_plugins[$plugin]=false
        fi
    done
else
    for plugin in "${plugins[@]}"; do
        enabled_plugins[$plugin]=false
    done
fi

# ===== CONFIGURATION QUESTIONS =====
echo ""
echo "=== Plugin Configuration ==="
echo ""
echo "Select plugins to enable (↑↓ to navigate, space to toggle, enter to confirm):"
echo ""

selected_idx=0

draw_menu() {
    for i in "${!plugins[@]}"; do
        plugin="${plugins[$i]}"
        if [ "$i" -eq "$selected_idx" ]; then
            # Highlight current selection
            if [ "${enabled_plugins[$plugin]}" = "true" ]; then
                printf "\033[47;30m▶ [✓] %-20s\033[0m %s\n" "$plugin" "${plugin_descriptions[$plugin]}"
            else
                printf "\033[47;30m▶ [ ] %-20s\033[0m %s\n" "$plugin" "${plugin_descriptions[$plugin]}"
            fi
        else
            # Normal lines
            if [ "${enabled_plugins[$plugin]}" = "true" ]; then
                printf "  [✓] %-20s %s\n" "$plugin" "${plugin_descriptions[$plugin]}"
            else
                printf "  [ ] %-20s %s\n" "$plugin" "${plugin_descriptions[$plugin]}"
            fi
        fi
    done
}

initial_lines=$(( ${#plugins[@]} ))
draw_menu

# Interactive key handling:
# - Up/Down arrows: Navigate selection
# - Space: Toggle current item
# - Enter: Confirm and proceed
while true; do
    IFS= read -rsn1 key < /dev/tty

    case "$key" in
        $'\x1b')  # Escape sequence (arrow keys)
            IFS= read -rsn2 rest < /dev/tty
            case "$rest" in
                '[A')  # Up arrow
                    if [ "$selected_idx" -gt 0 ]; then
                        selected_idx=$((selected_idx - 1))
                        tput cuu "$initial_lines"
                        draw_menu
                    fi
                    ;;
                '[B')  # Down arrow
                    if [ "$selected_idx" -lt $((${#plugins[@]} - 1)) ]; then
                        selected_idx=$((selected_idx + 1))
                        tput cuu "$initial_lines"
                        draw_menu
                    fi
                    ;;
            esac
            ;;
        ' ')  # Space key - toggle current selection
            plugin="${plugins[$selected_idx]}"
            if [ "${enabled_plugins[$plugin]}" = "true" ]; then
                enabled_plugins[$plugin]=false
            else
                enabled_plugins[$plugin]=true
            fi
            tput cuu "$initial_lines"
            draw_menu
            ;;
        '')  # Enter key - confirm and proceed
            break
            ;;
    esac
done

echo ""

# Track installation results
declare -a installed_files=()
declare -a skipped_files=()

# ===== CHECK EXISTING FILES AND WARN =====
echo "=== Checking existing files ==="
if check_and_warn "$TMP_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md"; then
    echo "Installing CLAUDE.md..."
    cp "$TMP_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
    installed_files+=("CLAUDE.md")
else
    skipped_files+=("CLAUDE.md")
fi

if check_and_warn "$TMP_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh" "statusline-command.sh"; then
    echo "Installing statusline-command.sh..."
    cp "$TMP_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
    chmod +x "$CLAUDE_DIR/statusline-command.sh"
    installed_files+=("statusline-command.sh")
else
    skipped_files+=("statusline-command.sh")
fi

# Generate settings.json to temp file first
cat > "$TMP_DIR/settings.json" << EOF
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  },
  "enabledPlugins": {
EOF

first=true
for plugin in "${plugins[@]}"; do
    # Add comma before this entry if not first
    if [ "$first" = true ]; then
        first=false
    else
        echo "," >> "$TMP_DIR/settings.json"
    fi

    # Add the plugin entry (without trailing comma)
    if [ "${enabled_plugins[$plugin]}" = "true" ]; then
        printf "    \"${plugin}@claude-plugins-official\": true" >> "$TMP_DIR/settings.json"
    else
        printf "    \"${plugin}@claude-plugins-official\": false" >> "$TMP_DIR/settings.json"
    fi
done
# Add final newline after last entry
echo "" >> "$TMP_DIR/settings.json"

cat >> "$TMP_DIR/settings.json" << EOF
  }
}
EOF

# Check and install settings.json
if check_and_warn "$TMP_DIR/settings.json" "$CLAUDE_DIR/settings.json" "settings.json"; then
    echo "Installing settings.json..."
    cp "$TMP_DIR/settings.json" "$CLAUDE_DIR/settings.json"
    installed_files+=("settings.json")
else
    skipped_files+=("settings.json")
fi

echo ""
# Show summary based on what actually happened
if [ ${#installed_files[@]} -gt 0 ]; then
    echo "✓ Claude Code configuration updated successfully!"
    echo ""
    echo "Installed files:"
    for file in "${installed_files[@]}"; do
        echo "  ✓ $file"
    done
else
    echo "✓ No changes made"
fi

if [ ${#skipped_files[@]} -gt 0 ]; then
    echo ""
    echo "Skipped files (no changes or declined):"
    for file in "${skipped_files[@]}"; do
        echo "  - $file"
    done
fi

echo ""
echo "Configuration directory: $CLAUDE_DIR"
if [ ${#installed_files[@]} -gt 0 ]; then
    echo ""
    echo "Restart Claude Code to load the new configuration"
fi
