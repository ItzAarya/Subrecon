#!/bin/bash
#
# subrecon.sh - Recon-to-triage pipeline for a target domain.
#
# Stage 1 (enumeration):   assetfinder, subfinder, findomain, amass -> merge/dedupe
# Stage 2 (triage):        wappalyzer + httpx tech-detect (fingerprint), httpx (liveness), gowitness (screenshots)
# Stage 3 (easy wins):     subzy + nuclei (takeover), nuclei (exposures/misconfig), nuclei (general/CVE)
# Stage 4 (tech-specific):  auto-routes to wpscan/joomscan/droopescan based on fingerprinted CMS,
#                           and flags Spring Actuator / Swagger exposure for manual follow-up
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
WPSCAN_DIR="$OUTDIR/${DOMAIN}wpscan"
JOOMSCAN_DIR="$OUTDIR/${DOMAIN}joomscan"
DROOPESCAN_DIR="$OUTDIR/${DOMAIN}droopescan"

mkdir -p "$OUTDIR"

ASSETFINDER_OUT="$OUTDIR/${DOMAIN}ass.txt"
SUBFINDER_OUT="$OUTDIR/${DOMAIN}sub.txt"
FINDOMAIN_OUT="$OUTDIR/${DOMAIN}dom.txt"
AMASS_OUT="$OUTDIR/${DOMAIN}ama.txt"
FINAL_OUT="$OUTDIR/${DOMAIN}fin.txt"
WAPPA_OUT="$OUTDIR/${DOMAIN}wappa.txt"
LIVE_OUT="$OUTDIR/${DOMAIN}live.txt"
TECH_OUT="$OUTDIR/${DOMAIN}tech.txt"
SUBZY_OUT="$OUTDIR/${DOMAIN}tko.txt"
NUCLEI_TKO_OUT="$OUTDIR/${DOMAIN}nuctko.txt"
NUCLEI_EXP_OUT="$OUTDIR/${DOMAIN}exp.txt"
NUCLEI_VULN_OUT="$OUTDIR/${DOMAIN}vuln.txt"
CMS_FLAGS_OUT="$OUTDIR/${DOMAIN}cmsflags.txt"
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

# Runs a command live on screen AND appends everything to the log file.
# The tool's own -o/-output flag (passed as part of "$@") still writes the
# clean results file separately; this just makes progress visible in real time.
run_visible() {
    "$@" 2>&1 | tee -a "$LOG_FILE"
}

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
echo "=== Stage 2: Triage (tech fingerprint, liveness, screenshots) ===" | tee -a "$LOG_FILE"
echo

# ---- wappalyzer: tech fingerprint, run first/early ----
if have wappalyzer; then
    echo "[*] Running wappalyzer against each subdomain (this can take a while)..." | tee -a "$LOG_FILE"
    : > "$WAPPA_OUT"
    while IFS= read -r host; do
        [ -z "$host" ] && continue
        echo "--- $host ---" | tee -a "$LOG_FILE" >> "$WAPPA_OUT"
        run_visible wappalyzer "https://$host" >> "$WAPPA_OUT" 2>>"$LOG_FILE"
    done < "$FINAL_OUT"
    echo "[+] wappalyzer results saved to $WAPPA_OUT"
else
    warn_missing wappalyzer
fi

# ---- httpx: liveness + status/title ----
if have httpx; then
    echo "[*] Running httpx (liveness check)..." | tee -a "$LOG_FILE"
    run_visible httpx -l "$FINAL_OUT" -status-code -title -o "$LIVE_OUT"
    echo "    -> $(count_lines "$LIVE_OUT") live hosts saved to $LIVE_OUT"
else
    warn_missing httpx
    # fall back: treat the full subdomain list as the "live" list so later stages still have input
    cp "$FINAL_OUT" "$LIVE_OUT" 2>/dev/null || true
fi

# ---- httpx: tech fingerprint ----
if have httpx; then
    echo "[*] Running httpx (tech-detect)..." | tee -a "$LOG_FILE"
    run_visible httpx -l "$FINAL_OUT" -tech-detect -o "$TECH_OUT"
    echo "    -> results saved to $TECH_OUT"
fi

# ---- gowitness: screenshots ----
if have gowitness; then
    echo "[*] Running gowitness (screenshots)..." | tee -a "$LOG_FILE"
    mkdir -p "$SCREENSHOT_DIR"
    run_visible gowitness file -f "$LIVE_OUT" -P "$SCREENSHOT_DIR" --no-http || \
    run_visible gowitness file -f "$LIVE_OUT" -P "$SCREENSHOT_DIR" || \
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
    run_visible subzy run --targets "$FINAL_OUT" --hide_fails > "$SUBZY_OUT"
    echo "    -> results saved to $SUBZY_OUT"
else
    warn_missing subzy
fi

# ---- nuclei: takeover templates, exposures, general/CVE ----
if have nuclei; then
    echo "[*] Running nuclei (takeover templates)..." | tee -a "$LOG_FILE"
    run_visible nuclei -l "$FINAL_OUT" -tags takeover -o "$NUCLEI_TKO_OUT"
    echo "    -> results saved to $NUCLEI_TKO_OUT"

    echo "[*] Running nuclei (exposures / misconfig templates)..." | tee -a "$LOG_FILE"
    run_visible nuclei -l "$FINAL_OUT" -tags exposure,misconfig,config,backup -o "$NUCLEI_EXP_OUT"
    echo "    -> results saved to $NUCLEI_EXP_OUT"

    echo "[*] Running nuclei (general templates, incl. CVEs)..." | tee -a "$LOG_FILE"
    run_visible nuclei -l "$FINAL_OUT" -o "$NUCLEI_VULN_OUT"
    echo "    -> results saved to $NUCLEI_VULN_OUT"
else
    warn_missing nuclei
fi

echo
echo "=== Stage 4: Tech-specific scans (auto-routed from fingerprint data) ===" | tee -a "$LOG_FILE"
echo

: > "$CMS_FLAGS_OUT"

extract_hosts_matching() {
    # $1 = case-insensitive keyword; prints matching lines' first field (the URL/host).
    # Driven by httpx's tech-detect output, which is one line per host — Wappalyzer's
    # output is saved separately for manual review but isn't structured per-line the
    # same way, so it isn't used for automatic routing here.
    grep -i "$1" "$TECH_OUT" 2>/dev/null | awk '{print $1}'
}

# ---- WordPress ----
WP_HOSTS=$(extract_hosts_matching "wordpress" | sort -u)
if [ -n "$WP_HOSTS" ]; then
    if have wpscan; then
        mkdir -p "$WPSCAN_DIR"
        echo "[*] WordPress detected — running wpscan against matched hosts..." | tee -a "$LOG_FILE"
        echo "$WP_HOSTS" | while IFS= read -r host; do
            [ -z "$host" ] && continue
            SAFE_NAME=$(echo "$host" | sed 's|https\?://||; s/[^A-Za-z0-9._-]/_/g')
            echo "[*] wpscan -> $host" | tee -a "$LOG_FILE"
            run_visible wpscan --url "$host" --no-banner -o "$WPSCAN_DIR/$SAFE_NAME.txt" || \
                echo "[!] wpscan exited with an error for $host" | tee -a "$LOG_FILE"
        done
        echo "[+] wpscan results saved to $WPSCAN_DIR/"
    else
        echo "[!] WordPress detected on one or more hosts, but wpscan is not installed — skipping active scan." | tee -a "$LOG_FILE"
        echo "$WP_HOSTS" >> "$CMS_FLAGS_OUT"
    fi
fi

# ---- Joomla ----
JOOMLA_HOSTS=$(extract_hosts_matching "joomla" | sort -u)
if [ -n "$JOOMLA_HOSTS" ]; then
    if have joomscan; then
        mkdir -p "$JOOMSCAN_DIR"
        echo "[*] Joomla detected — running joomscan against matched hosts..." | tee -a "$LOG_FILE"
        echo "$JOOMLA_HOSTS" | while IFS= read -r host; do
            [ -z "$host" ] && continue
            SAFE_NAME=$(echo "$host" | sed 's|https\?://||; s/[^A-Za-z0-9._-]/_/g')
            echo "[*] joomscan -> $host" | tee -a "$LOG_FILE"
            run_visible joomscan --url "$host" > "$JOOMSCAN_DIR/$SAFE_NAME.txt" || \
                echo "[!] joomscan exited with an error for $host" | tee -a "$LOG_FILE"
        done
        echo "[+] joomscan results saved to $JOOMSCAN_DIR/"
    else
        echo "[!] Joomla detected on one or more hosts, but joomscan is not installed — skipping active scan." | tee -a "$LOG_FILE"
        echo "$JOOMLA_HOSTS" >> "$CMS_FLAGS_OUT"
    fi
fi

# ---- Drupal ----
DRUPAL_HOSTS=$(extract_hosts_matching "drupal" | sort -u)
if [ -n "$DRUPAL_HOSTS" ]; then
    if have droopescan; then
        mkdir -p "$DROOPESCAN_DIR"
        echo "[*] Drupal detected — running droopescan against matched hosts..." | tee -a "$LOG_FILE"
        echo "$DRUPAL_HOSTS" | while IFS= read -r host; do
            [ -z "$host" ] && continue
            SAFE_NAME=$(echo "$host" | sed 's|https\?://||; s/[^A-Za-z0-9._-]/_/g')
            echo "[*] droopescan -> $host" | tee -a "$LOG_FILE"
            run_visible droopescan scan drupal -u "$host" > "$DROOPESCAN_DIR/$SAFE_NAME.txt" || \
                echo "[!] droopescan exited with an error for $host" | tee -a "$LOG_FILE"
        done
        echo "[+] droopescan results saved to $DROOPESCAN_DIR/"
    else
        echo "[!] Drupal detected on one or more hosts, but droopescan is not installed — skipping active scan." | tee -a "$LOG_FILE"
        echo "$DRUPAL_HOSTS" >> "$CMS_FLAGS_OUT"
    fi
fi

# ---- Spring Boot Actuator / Swagger exposure flags (manual follow-up, no dedicated scanner run) ----
for keyword in "actuator" "swagger" "openapi"; do
    grep -il "$keyword" "$NUCLEI_EXP_OUT" "$NUCLEI_VULN_OUT" "$TECH_OUT" "$WAPPA_OUT" 2>/dev/null >> "$CMS_FLAGS_OUT" || true
done
sort -u -o "$CMS_FLAGS_OUT" "$CMS_FLAGS_OUT" 2>/dev/null || true

if [ -s "$CMS_FLAGS_OUT" ]; then
    echo "[+] Flagged items needing manual follow-up saved to $CMS_FLAGS_OUT"
fi

echo
echo "[+] Pipeline complete. Output directory: $OUTDIR"
