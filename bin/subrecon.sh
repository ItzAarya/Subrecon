#!/bin/bash
#
# subrecon.sh - Recon-to-triage pipeline for a target domain.
#
# Stage 1 (enumeration):  assetfinder, subfinder, findomain, amass -> merge/dedupe
# Stage 2 (triage):       httpx (liveness + tech fingerprint), gowitness (screenshots)
# Stage 3 (easy wins):    subzy + nuclei (takeover), nuclei (exposures/misconfig), nuclei (general/CVE)
#
# Each stage checks for its own required tool(s) and skips gracefully (with a
# warning) if a tool is missing, rather than aborting the whole run.
#
# Usage: subrecon.sh domain.com [output_dir]

set -uo pipefail

# ---- Args ----
if [ $# -lt 1 ]; then
    echo "Usage: $0 <domain> [output_dir]"
    exit 1
fi

DOMAIN="$1"
OUTDIR="${2:-./$DOMAIN}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCREENSHOT_DIR="$OUTDIR/${DOMAIN}screenshots"

mkdir -p "$OUTDIR"

ASSETFINDER_OUT="$OUTDIR/${DOMAIN}ass.txt"
SUBFINDER_OUT="$OUTDIR/${DOMAIN}sub.txt"
FINDOMAIN_OUT="$OUTDIR/${DOMAIN}dom.txt"
AMASS_OUT="$OUTDIR/${DOMAIN}ama.txt"
FINAL_OUT="$OUTDIR/${DOMAIN}fin.txt"
LIVE_OUT="$OUTDIR/${DOMAIN}live.txt"
TECH_OUT="$OUTDIR/${DOMAIN}tech.txt"
SUBZY_OUT="$OUTDIR/${DOMAIN}tko.txt"
NUCLEI_TKO_OUT="$OUTDIR/${DOMAIN}nuctko.txt"
NUCLEI_EXP_OUT="$OUTDIR/${DOMAIN}exp.txt"
NUCLEI_VULN_OUT="$OUTDIR/${DOMAIN}vuln.txt"
LOG_FILE="$OUTDIR/run_$TIMESTAMP.log"

echo "[*] Target domain : $DOMAIN"
echo "[*] Output dir     : $OUTDIR"
echo "[*] Log file       : $LOG_FILE"
echo

# ---- Helpers ----
have() { command -v "$1" &>/dev/null; }

warn_missing() {
    echo "[!] $1 not found in PATH — skipping this stage." | tee -a "$LOG_FILE"
}

count_lines() { wc -l < "$1" 2>/dev/null || echo 0; }

echo "=== Stage 1: Enumeration ===" | tee -a "$LOG_FILE"
echo

# ---- assetfinder ----
if have assetfinder; then
    echo "[*] Running assetfinder..." | tee -a "$LOG_FILE"
    assetfinder --subs-only "$DOMAIN" > "$ASSETFINDER_OUT" 2>>"$LOG_FILE" || echo "[!] assetfinder exited with an error" | tee -a "$LOG_FILE"
    echo "    -> $(count_lines "$ASSETFINDER_OUT") results saved to $ASSETFINDER_OUT"
else
    warn_missing assetfinder
fi

# ---- subfinder ----
if have subfinder; then
    echo "[*] Running subfinder..." | tee -a "$LOG_FILE"
    subfinder -d "$DOMAIN" -silent > "$SUBFINDER_OUT" 2>>"$LOG_FILE" || echo "[!] subfinder exited with an error" | tee -a "$LOG_FILE"
    echo "    -> $(count_lines "$SUBFINDER_OUT") results saved to $SUBFINDER_OUT"
else
    warn_missing subfinder
fi

# ---- findomain ----
if have findomain; then
    echo "[*] Running findomain..." | tee -a "$LOG_FILE"
    findomain -t "$DOMAIN" -u "$FINDOMAIN_OUT" >>"$LOG_FILE" 2>&1 || echo "[!] findomain exited with an error" | tee -a "$LOG_FILE"
    echo "    -> $(count_lines "$FINDOMAIN_OUT") results saved to $FINDOMAIN_OUT"
else
    warn_missing findomain
fi

# ---- amass ----
if have amass; then
    echo "[*] Running amass (passive)..." | tee -a "$LOG_FILE"
    amass enum -passive -d "$DOMAIN" -o "$AMASS_OUT" >>"$LOG_FILE" 2>&1 || echo "[!] amass exited with an error" | tee -a "$LOG_FILE"
    echo "    -> $(count_lines "$AMASS_OUT") results saved to $AMASS_OUT"
else
    warn_missing amass
fi

# ---- Merge + dedupe ----
echo
echo "[*] Merging and deduping results..." | tee -a "$LOG_FILE"
MERGE_FILES=()
for f in "$ASSETFINDER_OUT" "$SUBFINDER_OUT" "$FINDOMAIN_OUT" "$AMASS_OUT"; do
    [ -s "$f" ] && MERGE_FILES+=("$f")
done

if [ "${#MERGE_FILES[@]}" -eq 0 ]; then
    echo "[!] No tool produced any output; nothing to merge." | tee -a "$LOG_FILE"
    touch "$FINAL_OUT"
else
    cat "${MERGE_FILES[@]}" | sort -u > "$FINAL_OUT"
fi

TOTAL=$(count_lines "$FINAL_OUT")
echo "[+] $TOTAL unique subdomains saved to $FINAL_OUT"

if [ "$TOTAL" -eq 0 ]; then
    echo "[!] No subdomains to work with — skipping all remaining stages." | tee -a "$LOG_FILE"
    exit 0
fi

echo
echo "=== Stage 2: Triage (liveness, tech fingerprint, screenshots) ===" | tee -a "$LOG_FILE"
echo

# ---- httpx: liveness + status/title ----
if have httpx; then
    echo "[*] Running httpx (liveness check)..." | tee -a "$LOG_FILE"
    httpx -l "$FINAL_OUT" -silent -status-code -title -o "$LIVE_OUT" >>"$LOG_FILE" 2>&1 || echo "[!] httpx exited with an error" | tee -a "$LOG_FILE"
    echo "    -> $(count_lines "$LIVE_OUT") live hosts saved to $LIVE_OUT"
else
    warn_missing httpx
    # fall back: treat the full subdomain list as the "live" list so later stages still have input
    cp "$FINAL_OUT" "$LIVE_OUT" 2>/dev/null || true
fi

# ---- httpx: tech fingerprint ----
if have httpx; then
    echo "[*] Running httpx (tech-detect)..." | tee -a "$LOG_FILE"
    httpx -l "$FINAL_OUT" -silent -tech-detect -o "$TECH_OUT" >>"$LOG_FILE" 2>&1 || echo "[!] httpx tech-detect exited with an error" | tee -a "$LOG_FILE"
    echo "    -> results saved to $TECH_OUT"
fi

# ---- gowitness: screenshots ----
if have gowitness; then
    echo "[*] Running gowitness (screenshots)..." | tee -a "$LOG_FILE"
    mkdir -p "$SCREENSHOT_DIR"
    gowitness file -f "$LIVE_OUT" -P "$SCREENSHOT_DIR" --no-http 2>&1 | tee -a "$LOG_FILE" >/dev/null || \
    gowitness file -f "$LIVE_OUT" -P "$SCREENSHOT_DIR" >>"$LOG_FILE" 2>&1 || \
    echo "[!] gowitness exited with an error (CLI syntax may differ by version — check $LOG_FILE)" | tee -a "$LOG_FILE"
    echo "    -> screenshots saved to $SCREENSHOT_DIR/"
else
    warn_missing gowitness
fi

echo
echo "=== Stage 3: Easy wins (takeover, exposures, CVEs) ===" | tee -a "$LOG_FILE"
echo

# ---- subzy: takeover check ----
if have subzy; then
    echo "[*] Running subzy (takeover check)..." | tee -a "$LOG_FILE"
    subzy run --targets "$FINAL_OUT" --hide_fails > "$SUBZY_OUT" 2>>"$LOG_FILE" || echo "[!] subzy exited with an error" | tee -a "$LOG_FILE"
    echo "    -> results saved to $SUBZY_OUT"
else
    warn_missing subzy
fi

# ---- nuclei: takeover templates ----
if have nuclei; then
    echo "[*] Running nuclei (takeover templates)..." | tee -a "$LOG_FILE"
    nuclei -l "$FINAL_OUT" -tags takeover -o "$NUCLEI_TKO_OUT" >>"$LOG_FILE" 2>&1 || echo "[!] nuclei (takeover) exited with an error" | tee -a "$LOG_FILE"
    echo "    -> results saved to $NUCLEI_TKO_OUT"

    # ---- nuclei: exposed panels/files/misconfig ----
    echo "[*] Running nuclei (exposures / misconfig templates)..." | tee -a "$LOG_FILE"
    nuclei -l "$FINAL_OUT" -tags exposure,misconfig,config,backup -o "$NUCLEI_EXP_OUT" >>"$LOG_FILE" 2>&1 || echo "[!] nuclei (exposures) exited with an error" | tee -a "$LOG_FILE"
    echo "    -> results saved to $NUCLEI_EXP_OUT"

    # ---- nuclei: general / CVE sweep ----
    echo "[*] Running nuclei (general templates, incl. CVEs)..." | tee -a "$LOG_FILE"
    nuclei -l "$FINAL_OUT" -o "$NUCLEI_VULN_OUT" >>"$LOG_FILE" 2>&1 || echo "[!] nuclei (general) exited with an error" | tee -a "$LOG_FILE"
    echo "    -> results saved to $NUCLEI_VULN_OUT"
else
    warn_missing nuclei
fi

echo
echo "[+] Pipeline complete. Output directory: $OUTDIR"
