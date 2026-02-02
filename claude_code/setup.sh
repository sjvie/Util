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

echo "Installing Claude Code configuration..."
echo ""

# Create ~/.claude directory if it doesn't exist
mkdir -p "$CLAUDE_DIR"

# Function to check and warn about existing files
check_and_warn() {
    local file_path="$1"
    local file_name="$2"
    local show_content="${3:-true}"

    if [ -f "$file_path" ]; then
        echo ""
        echo "⚠️  WARNING: $file_name already exists at $file_path"
        echo ""
        if [ "$show_content" = "true" ]; then
            echo "Current file content:"
            echo "---"
            head -20 "$file_path"
            if [ $(wc -l < "$file_path") -gt 20 ]; then
                echo "... ($(wc -l < "$file_path") total lines)"
            fi
            echo "---"
            echo ""
        fi
        read -p "Overwrite? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping $file_name"
            return 1
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

# Check existing files
echo ""
echo "=== Checking existing files ==="
check_and_warn "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md" && {
    echo "Installing CLAUDE.md..."
    cp "$TMP_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
} || echo "Keeping existing CLAUDE.md"

check_and_warn "$CLAUDE_DIR/statusline-command.sh" "statusline-command.sh" && {
    echo "Installing statusline-command.sh..."
    cp "$TMP_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
    chmod +x "$CLAUDE_DIR/statusline-command.sh"
} || echo "Keeping existing statusline-command.sh"

# Plugin configuration
echo ""
echo "=== Plugin Configuration ==="
echo ""
echo "Select which plugins to enable (use space to toggle, enter to confirm):"
echo ""

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
if [ -f "$SCRIPT_DIR/settings.json" ]; then
    current_model=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$SCRIPT_DIR/settings.json" | cut -d'"' -f4)
    declare -A enabled_plugins
    for plugin in "${plugins[@]}"; do
        if grep -q "\"$plugin@claude-plugins-official\"[[:space:]]*:[[:space:]]*true" "$SCRIPT_DIR/settings.json"; then
            enabled_plugins[$plugin]=true
        else
            enabled_plugins[$plugin]=false
        fi
    done
else
    current_model="haiku"
    for plugin in "${plugins[@]}"; do
        enabled_plugins[$plugin]=false
    done
fi

# Try to use fzf for multi-select if available
if command -v fzf &> /dev/null; then
    echo "Using interactive menu (fzf):"
    echo ""

    # Prepare options with current state
    options=()
    for plugin in "${plugins[@]}"; do
        state="[disabled]"
        if [ "${enabled_plugins[$plugin]}" = "true" ]; then
            state="[enabled]"
            options+=("$plugin $state")
        else
            options+=("$plugin $state")
        fi
    done

    # Use fzf for multi-select
    selected=$(printf '%s\n' "${options[@]}" | fzf -m --preview 'echo {1} && echo "" && echo "{2}"' | awk '{print $1}')

    # Reset enabled plugins
    for plugin in "${plugins[@]}"; do
        enabled_plugins[$plugin]=false
    done

    # Mark selected as enabled
    while IFS= read -r plugin; do
        [ -z "$plugin" ] && continue
        enabled_plugins[$plugin]=true
    done <<< "$selected"
else
    # Fallback: simple text-based menu
    echo ""
    while true; do
        echo ""
        echo "Current selections:"
        for plugin in "${plugins[@]}"; do
            status="disabled"
            if [ "${enabled_plugins[$plugin]}" = "true" ]; then
                status="enabled"
            fi
            echo "  [$([[ "${enabled_plugins[$plugin]}" == "true" ]] && echo "X" || echo " ")] $plugin - ${plugin_descriptions[$plugin]} ($status)"
        done
        echo ""
        echo "Options:"
        for i in "${!plugins[@]}"; do
            echo "  $((i+1)). Toggle ${plugins[$i]}"
        done
        echo "  d. Done configuring"
        echo ""
        read -p "Select option: " choice

        if [[ "$choice" == "d" ]]; then
            break
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#plugins[@]}" ]; then
            idx=$((choice-1))
            plugin="${plugins[$idx]}"
            if [ "${enabled_plugins[$plugin]}" = "true" ]; then
                enabled_plugins[$plugin]=false
            else
                enabled_plugins[$plugin]=true
            fi
        else
            echo "Invalid option. Please try again."
        fi
    done
fi

# Ask for model selection
echo ""
echo "=== Model Selection ==="
echo "Current default: $current_model"
read -p "Enter model name (haiku/sonnet/opus, or press enter to keep current): " model_choice
if [ -z "$model_choice" ]; then
    model_choice="$current_model"
fi

# Check if settings.json exists and show current state
if [ -f "$CLAUDE_DIR/settings.json" ]; then
    echo ""
    echo "⚠️  WARNING: settings.json already exists at $CLAUDE_DIR/settings.json"
    echo ""
    echo "Current settings:"
    echo "---"
    cat "$CLAUDE_DIR/settings.json"
    echo "---"
    echo ""
    read -p "Overwrite with new configuration? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting setup. Keeping existing settings.json"
        exit 0
    fi
fi

# Generate settings.json
echo "Generating settings.json..."
cat > "$CLAUDE_DIR/settings.json" << EOF
{
  "model": "$model_choice",
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  },
  "enabledPlugins": {
EOF

first=true
for plugin in "${plugins[@]}"; do
    if [ "${enabled_plugins[$plugin]}" = "true" ]; then
        if [ "$first" = true ]; then
            echo "    \"${plugin}@claude-plugins-official\": true" >> "$CLAUDE_DIR/settings.json"
            first=false
        else
            echo "    \"${plugin}@claude-plugins-official\": true" >> "$CLAUDE_DIR/settings.json"
        fi
    else
        if [ "$first" = true ]; then
            echo "    \"${plugin}@claude-plugins-official\": false" >> "$CLAUDE_DIR/settings.json"
            first=false
        else
            echo "    \"${plugin}@claude-plugins-official\": false" >> "$CLAUDE_DIR/settings.json"
        fi
    fi
done

cat >> "$CLAUDE_DIR/settings.json" << EOF
  }
}
EOF

echo ""
echo "✓ Claude Code configuration installed successfully!"
echo ""
echo "Configuration files installed to: $CLAUDE_DIR"
echo "  - CLAUDE.md (global memory/guidelines)"
echo "  - settings.json (model, plugins, status line)"
echo "  - statusline-command.sh (custom status line)"
echo ""
echo "Enabled plugins:"
for plugin in "${plugins[@]}"; do
    if [ "${enabled_plugins[$plugin]}" = "true" ]; then
        echo "  ✓ $plugin"
    fi
done
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code to load the new configuration"
echo "  2. (Optional) Copy project-specific .claude/settings.json to your projects"
