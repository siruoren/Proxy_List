#!/bin/bash
# Fetch the latest release zip from guoyue2010/lxmusic- and extract JS files.
# Each JS file is saved to the current directory with a sequential number
# as the filename: 1.js, 2.js, 3.js, ...
#
# Usage:
#   ./fetch_latest_release.sh
#
# Behavior:
#   1. Query the GitHub API for the latest release of guoyue2010/lxmusic-.
#   2. Pick the zip asset whose name matches the release tag (e.g. V260907.zip).
#      If that is missing, fall back to the largest .zip asset in the release.
#   3. Remove any previously generated numbered js files (1.js, 2.js, ...)
#      in the current directory so stale entries don't accumulate.
#   4. Extract every *.js file from the zip and copy each one to {N}.js
#      starting at N=1. Files are sorted by their original (decoded) name
#      for a stable, deterministic ordering across runs.
#
# Note: zip files in this repo are created on Chinese Windows and store
# filenames in GBK without setting the UTF-8 flag. Python's zipfile module
# is used for extraction because the stock `unzip` on macOS/Linux often
# refuses to create those files ("Illegal byte sequence").

set -euo pipefail

REPO="guoyue2010/lxmusic-"
OUTPUT_DIR="$(pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# 1. Clean up previously generated numbered js files so stale ones don't linger.
echo "Cleaning up old numbered js files in $OUTPUT_DIR ..."
find "$OUTPUT_DIR" -maxdepth 1 -type f -regex '.*/[0-9]+\.js$' -delete

# 2. Fetch latest release metadata from GitHub API.
echo "Fetching latest release info for ${REPO} ..."
API_RESPONSE=$(curl -sSL --fail \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/releases/latest")

if [ -z "$API_RESPONSE" ]; then
    echo "Error: Failed to fetch release info from GitHub API." >&2
    exit 1
fi

# 3. Parse the JSON with python3 (available on macOS and GitHub runners).
#    Prefer the asset named "<tag>.zip"; otherwise pick the largest .zip asset.
PARSE_RESULT=$(printf '%s' "$API_RESPONSE" | python3 -c '
import json, sys
data = json.load(sys.stdin)
tag = data.get("tag_name", "") or ""
assets = data.get("assets", []) or []
zip_assets = [a for a in assets if (a.get("name") or "").lower().endswith(".zip")]
preferred = f"{tag}.zip"
url = ""
for a in zip_assets:
    if a.get("name") == preferred:
        url = a.get("browser_download_url", "") or ""
        break
if not url and zip_assets:
    url = max(zip_assets, key=lambda a: a.get("size", 0)).get("browser_download_url", "") or ""
print(f"{tag}\t{url}")
')

TAG_NAME=$(printf '%s' "$PARSE_RESULT" | cut -f1)
DOWNLOAD_URL=$(printf '%s' "$PARSE_RESULT" | cut -f2)

echo "Latest release tag: ${TAG_NAME:-<unknown>}"

if [ -z "$DOWNLOAD_URL" ]; then
    echo "Error: No .zip asset found in release '${TAG_NAME}'." >&2
    exit 1
fi

# 4. Download the zip.
echo "Downloading zip: $DOWNLOAD_URL"
ZIP_FILE="${WORK_DIR}/release.zip"
curl -sSL --fail -o "$ZIP_FILE" "$DOWNLOAD_URL"

if ! python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).testzip()' "$ZIP_FILE" 2>/dev/null; then
    echo "Error: Downloaded file is not a valid zip archive." >&2
    exit 1
fi

# 5. Extract JS files using Python's zipfile (handles GBK filenames correctly).
echo ""
echo "Extracting JS files and saving as 1.js, 2.js, ..."
ZIP_FILE="$ZIP_FILE" OUTPUT_DIR="$OUTPUT_DIR" python3 <<'PYEOF'
import os
import sys
import zipfile

zip_path = os.environ["ZIP_FILE"]
out_dir = os.environ["OUTPUT_DIR"]

with zipfile.ZipFile(zip_path) as z:
    files = []
    for info in z.infolist():
        if info.is_dir():
            continue
        name = info.filename
        # If the UTF-8 flag (bit 0x800) is NOT set, Python decoded the filename
        # as cp437. Recover the raw bytes and re-decode as GBK, which is the
        # de-facto encoding used by Chinese Windows zip tools.
        if not (info.flag_bits & 0x800):
            try:
                raw = info.orig_filename if isinstance(info.orig_filename, bytes) \
                    else info.filename.encode("cp437")
                name = raw.decode("gbk")
            except Exception:
                pass  # fall back to whatever Python already gave us
        if not name.lower().endswith(".js"):
            continue
        files.append((name, info))

    # Sort by decoded name for a stable, deterministic ordering across runs.
    files.sort(key=lambda x: x[0])

    if not files:
        print("Warning: No .js files found in the zip.", file=sys.stderr)
        sys.exit(0)

    idx = 0
    for name, info in files:
        idx += 1
        target = os.path.join(out_dir, f"{idx}.js")
        with z.open(info) as src, open(target, "wb") as dst:
            while True:
                chunk = src.read(65536)
                if not chunk:
                    break
                dst.write(chunk)
        print(f"  [{idx}] {os.path.basename(name)} -> {idx}.js")

    print(f"\nDone. Saved {idx} js file(s) to {out_dir}")
PYEOF
