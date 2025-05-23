#!/bin/bash
set -euo pipefail # Exit on error, undefined variable, or pipe failure

# --- Configuration ---
TARGET_BASHRC="$HOME/.bashrc"
# IMPORTANT: Replace this URL with the raw URL of your custom bashrc file on GitHub
GITHUB_URL="https://raw.githubusercontent.com/sjvie/Util/refs/heads/main/linux_setup/my_bashrc"

START_MARKER="######## sjvie CUSTOM ~/.bashrc"
END_MARKER="######## END sjvie CUSTOM ~/.bashrc"

# --- Temporary files ---
# We use mktemp to create temporary files securely
TMP_BASHRC=$(mktemp)
DOWNLOADED_CUSTOM_PART_FILE=$(mktemp)

# Ensure temporary files are cleaned up on script exit, error, or interrupt
trap 'echo "Cleaning up temporary files..."; rm -f "$TMP_BASHRC" "$DOWNLOADED_CUSTOM_PART_FILE"' EXIT

# --- Preliminary Check ---
if [[ "$GITHUB_URL" == "YOUR_GITHUB_RAW_FILE_URL_HERE" || -z "$GITHUB_URL" ]]; then
    echo "Error: GITHUB_URL is not set. Please edit the script and provide a valid URL." >&2
    exit 1
fi

# --- Download custom part ---
echo "Downloading custom bashrc content from: $GITHUB_URL"
if curl -sSL -o "$DOWNLOADED_CUSTOM_PART_FILE" "$GITHUB_URL"; then
    echo "Download successful."
    # Check if downloaded file is empty, which might indicate an issue or an empty remote file
    if [[ ! -s "$DOWNLOADED_CUSTOM_PART_FILE" ]]; then
        echo "Warning: Downloaded file is empty. The custom section will be empty or cleared." >&2
    fi
else
    echo "Error: Failed to download custom bashrc from '$GITHUB_URL'." >&2
    echo "Please check the URL and your internet connection." >&2
    # Trap will clean up $DOWNLOADED_CUSTOM_PART_FILE
    exit 1
fi

# --- Ensure target .bashrc exists, create if not ---
if [[ ! -f "$TARGET_BASHRC" ]]; then
    echo "Info: '$TARGET_BASHRC' not found. Creating it." >&2
    touch "$TARGET_BASHRC"
fi

# --- Prepare custom content ---
# Read the custom content from the downloaded file.
# Ensure it ends with a newline if it's not empty, so it fits well between markers.
CUSTOM_CONTENT=$(cat "$DOWNLOADED_CUSTOM_PART_FILE")
if [[ -n "$CUSTOM_CONTENT" && "${CUSTOM_CONTENT: -1}" != $'\n' ]]; then
    CUSTOM_CONTENT+=$'\n'
fi
# Note: If DOWNLOADED_CUSTOM_PART_FILE was empty, CUSTOM_CONTENT will be empty.

# --- Process the .bashrc file ---
markers_found_and_replaced=false
currently_in_old_custom_block=false

# Read $TARGET_BASHRC line by line
# The `|| [[ -n "$line" ]]` ensures the last line is processed even if it doesn't end with a newline
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$START_MARKER" ]]; then
        if $markers_found_and_replaced; then
            echo "Warning: A subsequent start marker was found. It and its content will be preserved if intact." >&2
            echo "$line" >> "$TMP_BASHRC"
            currently_in_old_custom_block=false # Reset state for this new (to be preserved) block
            continue
        fi

        # This is the start of the block we want to replace
        echo "$START_MARKER" >> "$TMP_BASHRC"
        if [[ -n "$CUSTOM_CONTENT" ]]; then
            # Append content. -n for echo prevents it from adding its own newline.
            # $CUSTOM_CONTENT already has its trailing newline if non-empty.
            echo -n "$CUSTOM_CONTENT" >> "$TMP_BASHRC"
        fi
        echo "$END_MARKER" >> "$TMP_BASHRC"

        markers_found_and_replaced=true
        currently_in_old_custom_block=true # Start skipping old content lines until END_MARKER

    elif [[ "$line" == "$END_MARKER" ]] && $currently_in_old_custom_block; then
        # This is the end of the old block we were skipping
        currently_in_old_custom_block=false
        # The new END_MARKER has already been written. Do nothing with this old one.

    elif ! $currently_in_old_custom_block; then
        # Not in a block we're skipping, so print the line
        echo "$line" >> "$TMP_BASHRC"
    fi
    # If currently_in_old_custom_block is true and it's not an END_MARKER, the line is skipped (implicit else)
done < "$TARGET_BASHRC"

# --- Append if markers were not found ---
if ! $markers_found_and_replaced; then
    echo "Info: Markers not found in '$TARGET_BASHRC'. Appending new custom part." >&2
    # If $TARGET_BASHRC (and thus $TMP_BASHRC, which contains its copy) was not empty,
    # add a separating newline before the new block.
    # -s checks if file exists and has a size greater than zero.
    if [[ -s "$TMP_BASHRC" ]]; then
        # Check if the tmp file already ends with a newline
        # This avoids double newlines if .bashrc already ended with one.
        # However, a simple "echo" is usually fine as an extra blank line is harmless.
        echo "" >> "$TMP_BASHRC" # The separating newline
    fi

    echo "$START_MARKER" >> "$TMP_BASHRC"
    if [[ -n "$CUSTOM_CONTENT" ]]; then
        echo -n "$CUSTOM_CONTENT" >> "$TMP_BASHRC"
    fi
    echo "$END_MARKER" >> "$TMP_BASHRC"
fi

# --- Finalize ---
# Atomically replace the old .bashrc with the new one
if mv "$TMP_BASHRC" "$TARGET_BASHRC"; then
    echo "Successfully updated '$TARGET_BASHRC'."
    # The trap will attempt to rm $TMP_BASHRC, but it's gone now after a successful mv, which is fine.
    # $DOWNLOADED_CUSTOM_PART_FILE will be removed by the trap.
else
    echo "Error: Failed to move '$TMP_BASHRC' to '$TARGET_BASHRC'." >&2
    # $TMP_BASHRC still exists and will be cleaned by the trap if mv fails.
    # $DOWNLOADED_CUSTOM_PART_FILE will also be removed by the trap.
    exit 1
fi

# The trap will execute upon exit, cleaning $DOWNLOADED_CUSTOM_PART_FILE
exit 0
