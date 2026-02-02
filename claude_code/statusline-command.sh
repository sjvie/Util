#!/bin/bash
# Read JSON input from stdin
input=$(cat)

# Function to extract JSON value (pure bash, no jq needed)
get_json_value() {
    local json="$1"
    local key="$2"
    local default="${3:-0}"

    # Extract value using grep and sed
    local value=$(echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*[^,}]*" | sed 's/.*:[[:space:]]*"\?\([^"]*\)"\?.*/\1/' | sed 's/[^0-9a-zA-Z._\/-]//g')

    # Return default if empty or null
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Function to format numbers with K/M suffix (with rounding)
format_number() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        echo "$(((num + 500000) / 1000000))M"
    elif [ "$num" -ge 1000 ]; then
        echo "$(((num + 500) / 1000))K"
    else
        echo "$num"
    fi
}

# Extract model name
MODEL=$(get_json_value "$input" "display_name" "Unknown")

# Calculate line changes from git diff in workspace
WORKSPACE=$(get_json_value "$input" "current_dir" "")
if [ -d "$WORKSPACE/.git" ]; then
    cd "$WORKSPACE" 2>/dev/null
    DIFF_STATS=$(git diff --numstat 2>/dev/null | awk '{added+=$1; removed+=$2} END {print added" "removed}')
    LINES_ADDED=$(echo "$DIFF_STATS" | awk '{print $1}')
    LINES_REMOVED=$(echo "$DIFF_STATS" | awk '{print $2}')
    [ -z "$LINES_ADDED" ] && LINES_ADDED=0
    [ -z "$LINES_REMOVED" ] && LINES_REMOVED=0
else
    LINES_ADDED=0
    LINES_REMOVED=0
fi

# Session token data (total cumulative)
TOTAL_IN=$(get_json_value "$input" "total_input_tokens" "0")
TOTAL_OUT=$(get_json_value "$input" "total_output_tokens" "0")
CONTEXT_SIZE=$(get_json_value "$input" "context_window_size" "200000")

# Current usage data - check if current_usage exists
if echo "$input" | grep -q '"current_usage"[[:space:]]*:[[:space:]]*{'; then
    CURRENT_IN=$(get_json_value "$input" "input_tokens" "0")
    CACHE_CREATE=$(get_json_value "$input" "cache_creation_input_tokens" "0")
    CACHE_READ=$(get_json_value "$input" "cache_read_input_tokens" "0")

    # Calculate current total as input_tokens + cache_creation + cache_read
    CURRENT_TOTAL=$((CURRENT_IN + CACHE_CREATE + CACHE_READ))
else
    CURRENT_IN=0
    CACHE_CREATE=0
    CACHE_READ=0
    CURRENT_TOTAL=0
fi

# Calculate percentage (with rounding)
if [ "$CONTEXT_SIZE" -gt 0 ] && [ "$CURRENT_TOTAL" -gt 0 ]; then
    CURRENT_PCT=$(((CURRENT_TOTAL * 100 + CONTEXT_SIZE / 2) / CONTEXT_SIZE))
else
    CURRENT_PCT=0
fi

# Color codes (dimmed colors work well in terminal)
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
RESET='\033[0m'

# Build the status line with better formatting
printf "${CYAN}%s${RESET} | " "$MODEL"
printf "${GREEN}+%s${RESET}/${RED}-%s${RESET} | " "$LINES_ADDED" "$LINES_REMOVED"
printf "${YELLOW}Session:${RESET} %s↓ %s↑ | " "$(format_number $TOTAL_IN)" "$(format_number $TOTAL_OUT)"
printf "${BLUE}Context:${RESET} %s ${YELLOW}(%s%%)${RESET} | " "$(format_number $CURRENT_TOTAL)" "$CURRENT_PCT"
printf "${MAGENTA}Cache:${RESET} %s↓ %s↑" "$(format_number $CACHE_READ)" "$(format_number $CACHE_CREATE)"

printf "\n"
