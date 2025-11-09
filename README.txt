
H4shExaminer

Overview
H4shExaminer is a lightweight, defensive filesystem hashing and comparison utility written in Bash.
It recursively scans regular files on a Unix-like system, computes SHA-256 hashes for each file,
and stores the results in a simple tab-separated text file. It also provides tools to compare
hash lists and to display hashes with colorized output for quick visual inspection.

H4shExaminer is intended for legitimate administrative, audit, and incident-response usage only.
It is non-destructive by design and includes dry-run behavior and clear warnings. Use responsibly
and only on systems you own or are explicitly authorized to analyze.

Key features
1) Full filesystem SHA-256 scan
   - Compute SHA-256 for every regular file reachable from /.
   - Output format: <sha256><TAB><absolute_path> (one per line).
   - Skips virtual filesystems by default (e.g., /proc, /sys, /dev, /run) to avoid hangs,
     but the exclusions are configurable in the script.

2) Hash-list comparison
   - Prompt the user for two hash-list files and compare them by file path.
   - Reports files only present in one list and files present in both with differing hashes.
   - Differences in hash values are highlighted character-by-character in red for quick triage.

3) Colorized display
   - Present a hash-list file to the terminal and color each hash line with a cycling palette
     so different entries are easy to scan visually.

Requirements
- Bash (recommended: bash 4+)
- coreutils: sha256sum
- Optional (but helpful): gawk, sed (standard on most Unix systems)
- Adequate disk space for output files (scanning a large filesystem can produce very large outputs).
- Run as root if you need to access all files (the script will record inaccessible files as ERROR entries)
- A terminal supporting ANSI color codes for colorized output

Installation
------------
1. Place the provided script in a secure location:
   sudo cp h4shexaminer.sh /usr/local/bin/h4shexaminer.sh
   sudo chmod 755 /usr/local/bin/h4shexaminer.sh

2. Optionally, add a signed, versioned copy to an audit repository and record the SHA-256 of the script itself.

Quick usage
Run the script: ./h4shexaminer.sh

You will see a menu with three main options:

1) Scan filesystem and write SHA256 hashes for every regular file to a .txt
   - Prompts for an output path (default: /var/tmp/all_hashes.txt).
   - Confirms overwrite if the target exists.
   - Skips virtual filesystems by default to avoid hangs; adjust the EXCLUDES array in the script if you need different behavior.
   - Example:
  
     ./h4shexaminer.sh
     Option: 1
     Enter output file path (or press ENTER for /var/tmp/all_hashes.txt): /var/tmp/hashes_2025-11-09.txt
  

2) Compare two hash-list files (prompt for file paths). Differences highlighted in red.
   - Prompts for the two files to compare (first and second).
   - Outputs:
     - ONLY_IN_FIRST <path> or ONLY_IN_SECOND <path> for files missing in one list.
     - MISMATCH for file: <path> followed by the two hashes with differing characters colored red.

3) Display a hash-list file, coloring each hash line with cycling colors.
   - Prompts for a hash-list file and prints each line with the hash field colorized to improve readability.

Output format and notes
- Each output line for the scan is: <sha256><TAB><absolute_path>
- Lines where a file could not be read due to permissions or other errors will be recorded as:
  ERROR<TAB><absolute_path>
- The script preserves file paths exactly as returned by find and sha256sum. Filenames with whitespace
  and special characters are handled carefully by using NUL-delimited find output and safe printing.
- The default behavior does not follow symlinks and does not traverse excluded virtual filesystems.

Performance & safety considerations
- Scanning an entire system is I/O- and time-intensive and can produce very large output files.
- Run scans during maintenance windows or on copies/backups if possible.
- Consider excluding large mount points (network shares, backup stores) if they are not relevant.
- The script is non-destructive: it does not modify or delete files. Use --apply or destructive flags
  are not present. Always inspect produced outputs before taking automated action.
- The script records unreadable files as ERROR entries so you can identify permission gaps.

Configuration hints
- EXCLUDES array at the top of the script controls which top-level paths are pruned by the scanner.
- PALETTE array controls the cycling colors used for colored output; adjust to suit terminal preferences.
- To change hash algorithm, adjust calls to sha256sum to another tool or algorithm (note: compatibility and cryptographic strength vary).

Logging and evidence handling
- For incident response, consider:
  - Signing produced artifacts with gpg or your organization's signing key before upload.
  - Storing outputs in an encrypted, access-controlled repository.
  - Recording the exact command, script SHA-256, user, and timestamp whenever a scan is performed.

Security & privacy
- The scanning operation will enumerate and read files across the filesystem. The resulting hash-list may contain
  paths that reveal sensitive information (usernames, project names, etc.). Treat outputs as sensitive artifacts.
- Do not upload or share produced hash-lists to third parties without proper authorization and redaction.
- Ensure you have explicit written permission to scan any system that is not under your direct ownership.

Limitations
- The script avoids virtual filesystems (e.g. /proc, /sys) by default to prevent hangs. Including them is possible but dangerous.
- It records hashes and paths only; the script does not attempt to detect file content changes beyond hash comparison.
- For distributed environments or extremely large filesystems, consider using a more scalable approach (parallel workers,
  incremental scanning, or a purpose-built agent).

Examples
1) Quick scan to /tmp/hashes.txt:
./h4shexaminer.sh
Option: 1
Enter output file path (or press ENTER for /var/tmp/all_hashes.txt): /tmp/hashes.txt

2) Compare two previous scans:
./h4shexaminer.sh
Option: 2
Enter path to FIRST hash file: /tmp/hashes.2025-11-01.txt
Enter path to SECOND hash file: /tmp/hashes.2025-11-09.txt

3) Display a hash-list with color:
./h4shexaminer.sh
Option: 3
Enter path to hash-list file to display: /tmp/hashes.2025-11-09.txt

Legal Disclaimer
H4shExaminer is provided for defensive, administrative, audit, and incident-response purposes only.
By using this software you agree to comply with all applicable laws, regulations, and organizational policies.
You must obtain explicit written permission to run H4shExaminer on any system you do not own or manage.

The author and distributor of H4shExaminer are not responsible for any misuse of this tool, data loss, or other
consequences resulting from its use. You agree to hold the author and distributor harmless for any claims arising
from unauthorized or negligent use.

If you are unsure about the legality or appropriateness of scanning a system, consult legal counsel or your
organization's security/compliance team before proceeding.