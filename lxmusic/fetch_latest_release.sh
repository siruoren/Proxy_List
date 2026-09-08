#!/bin/bash
# Fetch the latest release zip from guoyue2010/lxmusic- and extract JS files.
# Each JS file is saved to the current directory, using the value of the @name
# field found at the top of the file as the filename. Spaces in the name are
# replaced with '_'.
#
#   e.g.  * @name 星澜聚合音源 (StellarWave)   ->  星澜聚合音源_(StellarWave).js
#
# Each run replaces the previously generated js files. However, if fetching or
# extraction fails (no new files obtained), the existing js files are kept
# untouched so the repo always has a valid set.
#
# Usage:
#   ./fetch_latest_release.sh
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

# 1. Fetch latest release metadata from GitHub API.
echo "Fetching latest release info for ${REPO} ..."
API_RESPONSE=$(curl -sSL --fail \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/releases/latest") || {
    echo "Error: Failed to fetch release info from GitHub API. Keeping existing js files." >&2
    exit 1
}

# 2. Parse the JSON with python3.
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
    echo "Error: No .zip asset found in release '${TAG_NAME}'. Keeping existing js files." >&2
    exit 1
fi

# 3. Download the zip.
echo "Downloading zip: $DOWNLOAD_URL"
ZIP_FILE="${WORK_DIR}/release.zip"
curl -sSL --fail -o "$ZIP_FILE" "$DOWNLOAD_URL" || {
    echo "Error: Failed to download zip. Keeping existing js files." >&2
    exit 1
}

if ! python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).testzip()' "$ZIP_FILE" 2>/dev/null; then
    echo "Error: Downloaded file is not a valid zip archive. Keeping existing js files." >&2
    exit 1
fi

# 4. Extract JS files, parse @name from each, then (only on success) delete old
#    js files and write the new ones. All in one Python process so that a
#    failure at any step leaves the existing files untouched.
echo ""
echo "Extracting JS files and parsing @name ..."

if ! ZIP_FILE="$ZIP_FILE" OUTPUT_DIR="$OUTPUT_DIR" python3 <<'PYEOF'
import os
import re
import sys
import zipfile

zip_path = os.environ["ZIP_FILE"]
out_dir = os.environ["OUTPUT_DIR"]

# Matches "@name <value>" and captures the value (rest of line, minus trailing
# whitespace). MULTILINE so ^/$ match per line; . does not cross newlines.
name_re = re.compile(r'@name\s+(.+?)\s*$', re.MULTILINE)

# Pattern matching emoji / pictographic "icon" characters that should be
# removed from the @name value before it is used as a filename.
# NOTE: we intentionally do NOT include mathematical alphanumeric symbols
# (1D400-1D7FF) here — those are stylized *letters*, not pictures, and
# stripping them turns disguised text like "𝖧ello 𝖶orld" into garbage.
emoji_re = re.compile(
    "["  # the join of the ranges below in one character class
    "\U0001F300-\U0001FAFF"  # symbols & pictographs, supplemental, extended-A
    "\U0001F600-\U0001F64F"  # emoticons
    "\U0001F680-\U0001F6FF"  # transport & map symbols
    "\U00002600-\U000027BF"  # misc symbols + dingbats
    "\U0001F1E6-\U0001F1FF"  # regional indicator (flag letters)
    "\U0001F900-\U0001F9FF"  # supplemental symbols & pictographs
    "\u2700-\u27bf"          # dingbats
    "\uFE00-\uFE0F"          # variation selectors
    "\u2600-\u26FF"          # misc symbols
    "]+",
    flags=re.UNICODE,
)

with zipfile.ZipFile(zip_path) as z:
    # --- Collect every *.js entry, decoding GBK filenames when needed ---
    files = []  # list of (decoded_name, ZipInfo)
    for info in z.infolist():
        if info.is_dir():
            continue
        name = info.filename
        # If the UTF-8 flag (bit 0x800) is NOT set, Python decoded the filename
        # as cp437. Recover the raw bytes and re-decode as GBK, which is the
        # de-facto encoding used by Chinese Windows zip tools.
        if not (info.flag_bits & 0x800):
            try:
                raw_bytes = info.orig_filename if isinstance(info.orig_filename, bytes) \
                    else info.filename.encode("cp437")
                name = raw_bytes.decode("gbk")
            except Exception:
                pass  # fall back to whatever Python already gave us
        if not name.lower().endswith(".js"):
            continue
        files.append((name, info))

    # Sort by decoded name for a stable, deterministic ordering across runs.
    files.sort(key=lambda x: x[0])

    if not files:
        print("No .js files found in the zip. Keeping existing js files.", file=sys.stderr)
        sys.exit(1)

    # --- Parse @name from each file and build target filenames ---
    targets = []  # list of (original_basename, target_filename, content_bytes)
    used_names = set()

    for decoded_name, info in files:
        with z.open(info) as f:
            content = f.read()

        # Decode text for @name search (js files are typically utf-8)
        try:
            text = content.decode('utf-8', errors='replace')
        except Exception:
            text = content.decode('gbk', errors='replace')

        # Search @name in the first 50 lines (header comment block is at top)
        head = '\n'.join(text.split('\n')[:50])
        m = name_re.search(head)

        orig_basename = os.path.basename(decoded_name)
        if m:
            base = m.group(1).strip()
        else:
            # Fallback: use the original filename (without extension) if no @name
            base = os.path.splitext(orig_basename)[0]
            print(f"  Warning: no @name found in {orig_basename}, using filename as fallback",
                  file=sys.stderr)

        # Strip emoji / pictographic / symbol characters (icons) from the name.
        # Covers: emoticons, misc symbols & pictographs, transport/map,
        # supplemental symbols & pictographs, dingbats, regional flags,
        # variation selectors (FE00-FE0F), and mathematical alphanumeric
        # symbols (1D400-1D7FF) that are used as decorative "icons".
        name_before_strip = base
        base = emoji_re.sub('', base)
        if base != name_before_strip:
            print(f"  Stripped icons from name: {name_before_strip!r} -> {base!r}",
                  file=sys.stderr)
        # Collapse whitespace that may have been left by removed icons.
        base = re.sub(r'\s+', ' ', base).strip()

        # Sanitize: replace spaces with _ (explicit requirement), plus other
        # characters that are illegal in filenames across OSes.
        base = base.replace(' ', '_')
        for ch in '\\/:*?"<>|':
            base = base.replace(ch, '_')
        base = base.strip().strip('._')
        if not base:
            base = os.path.splitext(orig_basename)[0]

        target = f"{base}.js"
        # Dedupe: if name already used, append _2, _3, ...
        if target in used_names:
            i = 2
            while f"{base}_{i}.js" in used_names:
                i += 1
            target = f"{base}_{i}.js"
        used_names.add(target)
        targets.append((orig_basename, target, content))

    # --- Only now (success) delete old js files in the output directory ---
    deleted = 0
    for existing in os.listdir(out_dir):
        if existing.lower().endswith('.js'):
            try:
                os.remove(os.path.join(out_dir, existing))
                deleted += 1
            except OSError as e:
                print(f"Warning: could not remove {existing}: {e}", file=sys.stderr)

    # --- Write new files ---
    print(f"Deleted {deleted} old js file(s). Writing {len(targets)} new file(s):")
    for orig_basename, target, content in targets:
        out_path = os.path.join(out_dir, target)
        with open(out_path, 'wb') as f:
            f.write(content)
        print(f"  {orig_basename} -> {target}")

    print(f"\nDone. Saved {len(targets)} js file(s) to {out_dir}")
PYEOF
then
    echo "Error: Failed to extract or parse files. Keeping existing js files." >&2
    exit 1
fi
