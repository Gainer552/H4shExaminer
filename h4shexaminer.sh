#!/usr/bin/env bash
# Purpose:
#   1) Scan filesystem recursively, compute sha256 of every regular file, store "hash<TAB>path" into an output .txt
#   2) Compare two hash-list files (prompt for paths) and show mismatches; differing characters highlighted in red
#   3) Display a hash-list with different colors per-hash (cycling palette)
#
# WARNING: Scanning entire disk can be very slow and produce huge files. Script skips /proc, /sys, /dev, /run by default.
#          Run as root if you want to access all files. This script is non-destructive.
#

set -euo pipefail
IFS=$'\n\t'

# Color constants
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Palette for Option 3 (cycling)
PALETTE=("$RED" "$GREEN" "$YELLOW" "$BLUE" "$MAGENTA" "$CYAN")

# Exclude these paths (virtual filesystems) to avoid hangs; edit if you want to include them.
EXCLUDES=(/proc /sys /dev /run)

# Ensure required tools exist
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required but not found. Install coreutils."; exit 1; }

# Helper: print header
echo
print_header(){
  cat <<'HDR'
==========================================
Hash Tool - scan / compare / display
Options:
  1) Scan filesystem, compute SHA256 for every regular file -> output .txt
  2) Compare two hash-list files (prompt for paths), highlight differing chars in red
  3) Display a hash-list with cycling colors per hash
==========================================
HDR
}
echo

# Helper: read user confirmation
confirm() {
  local prompt=${1:-"Proceed?"}
  read -r -p "$prompt [y/N]: " ans
  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

# Helper: check if path needs to be excluded
is_excluded() {
  local p="$1"
  for ex in "${EXCLUDES[@]}"; do
    if [[ "$p" == "$ex" || "$p" == "$ex/"* ]]; then
      return 0
    fi
  done
  return 1
}

# Option 1: scan filesystem and write hash list
scan_filesystem() {
  local out="${1:-}"
  if [[ -z "$out" ]]; then
    read -r -p "Enter output file path (e.g. /var/tmp/all_hashes.txt): " out
  fi
  out="${out/#\~/$HOME}"
  if [[ -e "$out" ]]; then
    echo "Output file $out already exists."
    if ! confirm "Overwrite $out?"; then
      echo "Aborting."
      return 1
    fi
    : > "$out"
  else
    mkdir -p "$(dirname "$out")"
    : > "$out"
  fi

  echo "Scanning filesystem (skipping ${EXCLUDES[*]}) and writing SHA256 hashes to: $out"
  echo "Each line: <sha256><TAB><path>"

  # Use find and compute sha256 for each regular file; handle spaces safely.
  # Avoid following symlinks (-P) and skip excluded paths.
  # We'll iterate over mount points starting at / and prune excluded directories.
  # Important: This will be slow on large filesystems.

  # Build find prune arguments
  local find_prune_args=()
  for ex in "${EXCLUDES[@]}"; do
    find_prune_args+=( -path "$ex" -prune -o )
  done

  # Use an explicit subshell to stream results to output incrementally
  (
    # Export IFS for while read -d
    export IFS=$'\n'
    # Use -type f to get regular files only
    # We use -print0 to safely iterate
    # Note: on some systems find supports -xdev; we do not use it so all mounts are included
    # The following 'eval' builds the prune expression dynamically
    # Form: find / ( -path /proc -prune -o -path /sys -prune -o ... ) -type f -print0
    local find_cmd=(find /)
    for ex in "${EXCLUDES[@]}"; do
      find_cmd+=( -path "$ex" -prune -o )
    done
    find_cmd+=( -type f -print0 )

    # Execute find and process results
    "${find_cmd[@]}" | while IFS= read -r -d '' file; do
      # Skip if file disappeared
      [[ -e "$file" ]] || continue
      # Compute hash; if permission denied, note and continue
      if hash_out=$(sha256sum -- "$file" 2>/dev/null); then
        # sha256sum prints: <hash>  <path>
        # But to ensure a stable format even if filename contains weird chars, extract hash then print hash<TAB>path
        local h="${hash_out%% *}"
        printf '%s\t%s\n' "$h" "$file" >>"$out"
      else
        # record unreadable files with placeholder 'ERROR'
        printf 'ERROR\t%s\n' "$file" >>"$out"
      fi
    done
  )

  echo "Scan complete. Output: $out"
  return 0
}

# Helper: split a line "hash<TAB>path" into hash and path
split_line() {
  local line="$1"
  # support tabs; also support multiple spaces
  # prefer tab delimiter; if no tab, fallback to first whitespace separation
  if [[ "$line" == *$'\t'* ]]; then
    local _hash="${line%%$'\t'*}"
    local _path="${line#*$'\t'}"
  else
    # split on first whitespace
    local _hash="${line%%[[:space:]]*}"
    local _path="${line#${_hash}}"
    _path="${_path#"${_path%%[![:space:]]*}"}" # trim leading spaces
  fi
  printf '%s\n%s' "$_hash" "$_path"
}

# Helper: color-diff two strings char-by-char; differing chars printed in RED
color_diff() {
  local a="$1"
  local b="$2"
  local -i la=${#a}
  local -i lb=${#b}
  local -i lm=$(( la>lb ? la : lb ))
  local out_a=''
  local out_b=''
  for ((i=0;i<lm;i++)); do
    ca="${a:i:1}"
    cb="${b:i:1}"
    # when substring is empty, treat as different
    if [[ "$ca" == "$cb" && -n "$ca" ]]; then
      out_a+="$ca"
      out_b+="$cb"
    else
      # show differing char (or space) in red
      if [[ -n "$ca" ]]; then out_a+="${RED}${ca}${RESET}"; else out_a+="${RED} ${RESET}"; fi
      if [[ -n "$cb" ]]; then out_b+="${RED}${cb}${RESET}"; else out_b+="${RED} ${RESET}"; fi
    fi
  done
  printf '%s\n%s\n' "$out_a" "$out_b"
}

# Option 2: compare two hash files
compare_hash_files() {
  local f1 f2
  read -r -p "Enter path to FIRST hash file: " f1
  read -r -p "Enter path to SECOND hash file: " f2
  f1="${f1/#\~/$HOME}"
  f2="${f2/#\~/$HOME}"
  if [[ ! -f "$f1" ]]; then echo "File not found: $f1"; return 1; fi
  if [[ ! -f "$f2" ]]; then echo "File not found: $f2"; return 1; fi

  echo "Parsing files..."
  declare -A map1
  declare -A map2
  declare -a paths1
  declare -a paths2

  # Read file1 safely
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    # Split only on first tab or space
    h="${line%%$'\t'*}"
    p="${line#*$'\t'}"
    if [[ "$h" == "$p" ]]; then
      # fallback: split on first space
      h="${line%%[[:space:]]*}"
      p="${line#${h}}"
      p="${p#"${p%%[![:space:]]*}"}"
    fi
    # Clean up and validate
    p="${p//$'\r'/}"
    p="${p%%[$'\n']*}"
    [[ -z "$p" || -z "$h" ]] && continue
    if [[ ! "$h" =~ ^[0-9a-fA-F]{64}$ && "$h" != "ERROR" ]]; then
      echo "Skipping malformed hash: $line"
      continue
    fi
    map1["$p"]="$h"
    paths1+=("$p")
  done <"$f1"

  # Read file2 safely
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    h="${line%%$'\t'*}"
    p="${line#*$'\t'}"
    if [[ "$h" == "$p" ]]; then
      h="${line%%[[:space:]]*}"
      p="${line#${h}}"
      p="${p#"${p%%[![:space:]]*}"}"
    fi
    p="${p//$'\r'/}"
    p="${p%%[$'\n']*}"
    [[ -z "$p" || -z "$h" ]] && continue
    if [[ ! "$h" =~ ^[0-9a-fA-F]{64}$ && "$h" != "ERROR" ]]; then
      echo "Skipping malformed hash: $line"
      continue
    fi
    map2["$p"]="$h"
    paths2+=("$p")
  done <"$f2"

  echo "Comparing..."
  local any_diff=0

  for p in "${paths1[@]}"; do
    h1="${map1[$p]}"
    if [[ -z "${map2[$p]+x}" ]]; then
      printf 'ONLY_IN_FIRST\t%s\n' "$p"
      any_diff=1
    else
      h2="${map2[$p]}"
      if [[ "$h1" != "$h2" ]]; then
        any_diff=1
        printf 'MISMATCH for file: %s\n' "$p"
        echo "First : $h1"
        echo "Second: $h2"
        echo
      fi
    fi
  done

  for p in "${paths2[@]}"; do
    if [[ -z "${map1[$p]+x}" ]]; then
      printf 'ONLY_IN_SECOND\t%s\n' "$p"
      any_diff=1
    fi
  done

  if (( any_diff == 0 )); then
    echo -e "${GREEN}Files match (by path and hash).${RESET}"
  else
    echo -e "${YELLOW}Differences found. See above.${RESET}"
  fi
}


# Option 3: display hashes with cycling colors
display_colored_hashes() {
  local file="${1:-}"
  if [[ -z "$file" ]]; then
    read -r -p "Enter path to hash-list file to display: " file
  fi
  file="${file/#\~/$HOME}"
  if [[ ! -f "$file" ]]; then echo "File not found: $file"; return 1; fi

  local i=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    color="${PALETTE[$(( i % ${#PALETTE[@]} ))]}"
    # Print hash (first field) in color, path normal
    if [[ "$line" == *$'\t'* ]]; then
      h="${line%%$'\t'*}"
      p="${line#*$'\t'}"
    else
      # fallback split
      h="${line%%[[:space:]]*}"
      p="${line#${h}}"
      p="${p#"${p%%[![:space:]]*}"}"
    fi
    printf '%b%s%b\t%s\n' "$color" "$h" "$RESET" "$p"
    ((i++))
  done <"$file"
}

# Main UI
main_menu() {
  print_header
  cat <<'MENU'
Choose an option:
  1) Scan filesystem and write SHA256 hashes for every regular file to a .txt
  2) Compare two hash-list files (prompt for file paths). Differences highlighted in red.
  3) Display a hash-list file, coloring each hash line with cycling colors.
  q) Quit
MENU

  read -r -p "Option: " opt
  case "$opt" in
    1)
      read -r -p "Output file path (or press ENTER for /var/tmp/all_hashes.txt): " outp
      outp="${outp:-/var/tmp/all_hashes.txt}"
      echo "Starting scan. This may take a long time. Continue?"
      if confirm "Proceed with full filesystem scan to: $outp ?"; then
        scan_filesystem "$outp"
      else
        echo "Cancelled."
      fi
      ;;
    2)
      compare_hash_files
      ;;
    3)
      display_colored_hashes
      ;;
    q|Q)
      echo "Exiting."
      exit 0
      ;;
    *)
      echo "Unknown option: $opt"
      ;;
  esac
}

# Run main menu
main_menu
