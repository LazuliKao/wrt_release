#!/bin/bash
set -e

FIRMWARE_PATH="${1:-./firmware}"
REMOTE_NAME="$2"
TARGET_DIR="$3"

if [ -z "$REMOTE_NAME" ] || [ -z "$TARGET_DIR" ]; then
  echo "Error: REMOTE_NAME and TARGET_DIR must be specified."
  echo "Usage: $0 <firmware_path> <remote_name> <target_dir>"
  exit 1
fi

# Function to run rclone copy with retry and increasing timeout
# Try 1: 15m, Try 2: 20m, Try 3: 30m
rclone_copy_with_retry() {
  local src="$1"
  local dest="$2"
  local timeouts=("15m" "20m" "30m")
  
  for i in "${!timeouts[@]}"; do
    local attempt=$((i + 1))
    local t="${timeouts[$i]}"
    echo "==> Attempt $attempt/3: Uploading '$src' to '$dest' with $t timeout..."
    
    # Run rclone copy with verbose logging (-v) and 5m stats interval.
    # Do not use -P or --stats-one-line to avoid carriage returns messing up GitHub Actions logs.
    if timeout -k 10s "$t" rclone copy "$src" "$dest" -v --stats 5m; then
      echo "==> Attempt $attempt succeeded!"
      return 0
    else
      local status=$?
      if [ $status -eq 124 ]; then
        echo "==> Attempt $attempt timed out after $t."
      else
        echo "==> Attempt $attempt failed with exit status $status."
      fi
      
      if [ $attempt -lt 3 ]; then
        echo "==> Waiting 10 seconds before next retry..."
        sleep 10
      fi
    fi
  done
  
  echo "==> Error: All 3 upload attempts failed for '$src'."
  return 1
}

echo "Uploading firmware from '$FIRMWARE_PATH'..."
rclone_copy_with_retry "$FIRMWARE_PATH" "${REMOTE_NAME}:${TARGET_DIR}"

if [ -f ./kmods_*.tar.gz ]; then
  echo "Uploading kmods..."
  rclone_copy_with_retry ./kmods_*.tar.gz "${REMOTE_NAME}:${TARGET_DIR}"
fi
