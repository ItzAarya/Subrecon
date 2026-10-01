#!/bin/bash
#
# subrecon.sh - Run assetfinder, subfinder, findomain, and amass against a domain,
# save each tool's output separately, merge + dedupe into one file, then run
# nuclei against the merged list: once for subdomain takeovers, once for
# general exposures/misconfigs/CVEs.
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
AMASS_OUT="$OUTDIR/${DOMAIN}ama.txt"
FINAL_OUT="$OUTDIR/${DOMAIN}fin.txt"
TAKEOVER_OUT="$OUTDIR/${DOMAIN}tko.txt"
VULN_OUT="$OUTDIR/${DOMAIN}vuln.txt"
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
for tool in assetfinder subfinder findomain amass nuclei; do
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

# ---- Run amass ----
echo "[*] Running amass (passive)..." | tee -a "$LOG_FILE"
amass enum -passive -d "$DOMAIN" -o "$AMASS_OUT" >>"$LOG_FILE" 2>&1 || echo "[!] amass exited with an error" | tee -a "$LOG_FILE"
echo "    -> $(wc -l < "$AMASS_OUT" 2>/dev/null || echo 0) results saved to $AMASS_OUT"

# ---- Merge + dedupe ----
echo "[*] Merging and deduping results..." | tee -a "$LOG_FILE"
cat "$ASSETFINDER_OUT" "$SUBFINDER_OUT" "$FINDOMAIN_OUT" "$AMASS_OUT" 2>/dev/null | sort -u > "$FINAL_OUT"

TOTAL=$(wc -l < "$FINAL_OUT")
echo
echo "[+] Done. $TOTAL unique subdomains saved to $FINAL_OUT"

# ---- Run nuclei (subdomain takeover check) ----
echo
echo "[*] Running nuclei (takeover templates) against merged subdomain list..." | tee -a "$LOG_FILE"
nuclei -l "$FINAL_OUT" -tags takeover -o "$TAKEOVER_OUT" >>"$LOG_FILE" 2>&1 || echo "[!] nuclei exited with an error" | tee -a "$LOG_FILE"
echo "[+] nuclei takeover results saved to $TAKEOVER_OUT"

# ---- Run nuclei (general exposures / misconfigs / CVEs) ----
echo
echo "[*] Running nuclei (general templates, not just takeover) against merged subdomain list..." | tee -a "$LOG_FILE"
nuclei -l "$FINAL_OUT" -o "$VULN_OUT" >>"$LOG_FILE" 2>&1 || echo "[!] nuclei exited with an error" | tee -a "$LOG_FILE"
echo "[+] nuclei general scan results saved to $VULN_OUT"
