#!/bin/bash
#
# subrecon.sh - Run assetfinder, subfinder, and findomain against a domain,
# save each tool's output separately, then merge + dedupe into one file.
#
# Usage: subrecon.sh domain.com [output_dir]

set -euo pipefail

# ---- Args ----
if [ $# -lt 1 ]; then
    echo "Usage: $0 <domain> [output_dir]"
    exit 1
fi

DOMAIN="$1"
OUTDIR="${2:-./$DOMAIN}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$OUTDIR"

ASSETFINDER_OUT="$OUTDIR/${DOMAIN}ass.txt"
SUBFINDER_OUT="$OUTDIR/${DOMAIN}sub.txt"
FINDOMAIN_OUT="$OUTDIR/${DOMAIN}dom.txt"
FINAL_OUT="$OUTDIR/${DOMAIN}fin.txt"
LOG_FILE="$OUTDIR/run_$TIMESTAMP.log"

echo "[*] Target domain : $DOMAIN"
echo "[*] Output dir     : $OUTDIR"
echo "[*] Log file       : $LOG_FILE"
echo

# ---- Check tools exist ----
check_tool() {
    if ! command -v "$1" &>/dev/null; then
        echo "[!] $1 not found in PATH. Install it before running this script." | tee -a "$LOG_FILE"
        return 1
    fi
    return 0
}

MISSING=0
for tool in assetfinder subfinder findomain; do
    check_tool "$tool" || MISSING=1
done

if [ "$MISSING" -eq 1 ]; then
    echo "[!] One or more tools are missing. Aborting." | tee -a "$LOG_FILE"
    exit 1
fi

# ---- Run assetfinder ----
echo "[*] Running assetfinder..." | tee -a "$LOG_FILE"
assetfinder --subs-only "$DOMAIN" > "$ASSETFINDER_OUT" 2>>"$LOG_FILE" || echo "[!] assetfinder exited with an error" | tee -a "$LOG_FILE"
echo "    -> $(wc -l < "$ASSETFINDER_OUT" 2>/dev/null || echo 0) results saved to $ASSETFINDER_OUT"

# ---- Run subfinder ----
echo "[*] Running subfinder..." | tee -a "$LOG_FILE"
subfinder -d "$DOMAIN" -silent > "$SUBFINDER_OUT" 2>>"$LOG_FILE" || echo "[!] subfinder exited with an error" | tee -a "$LOG_FILE"
echo "    -> $(wc -l < "$SUBFINDER_OUT" 2>/dev/null || echo 0) results saved to $SUBFINDER_OUT"

# ---- Run findomain ----
echo "[*] Running findomain..." | tee -a "$LOG_FILE"
findomain -t "$DOMAIN" -u "$FINDOMAIN_OUT" >>"$LOG_FILE" 2>&1 || echo "[!] findomain exited with an error" | tee -a "$LOG_FILE"
echo "    -> $(wc -l < "$FINDOMAIN_OUT" 2>/dev/null || echo 0) results saved to $FINDOMAIN_OUT"

# ---- Merge + dedupe ----
echo "[*] Merging and deduping results..." | tee -a "$LOG_FILE"
cat "$ASSETFINDER_OUT" "$SUBFINDER_OUT" "$FINDOMAIN_OUT" 2>/dev/null | sort -u > "$FINAL_OUT"

TOTAL=$(wc -l < "$FINAL_OUT")
echo
echo "[+] Done. $TOTAL unique subdomains saved to $FINAL_OUT"
