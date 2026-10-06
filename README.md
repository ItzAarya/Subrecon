# subrecon

A bash recon-to-triage pipeline for Kali Linux. Runs subdomain enumeration,
tech fingerprinting, liveness/screenshot triage, takeover/vulnerability checks,
and tech-specific CMS scans against a target domain — all in one command.

**Only use this against domains you are authorized to test.**

## Pipeline

**Stage 1 — Enumeration**
`assetfinder`, `subfinder`, `findomain`, `amass` (passive) → merged + deduped list

**Stage 2 — Triage**
`wappalyzer` (tech fingerprint, run first against every subdomain) → `httpx` (liveness, status codes, titles, tech-detect) → `gowitness` (screenshots of live hosts)

**Stage 3 — Easy wins**
`subzy` + `nuclei` (takeover templates), `nuclei` (exposed panels/files/misconfig), `nuclei` (general templates, incl. CVEs) — all run with live output on screen as well as saved to file

**Stage 4 — Tech-specific scans**
Parses the Stage 2 fingerprint data and auto-routes matched hosts into:
- `wpscan` for any host fingerprinted as WordPress
- `joomscan` for any host fingerprinted as Joomla
- `droopescan` for any host fingerprinted as Drupal
- Flags Spring Boot Actuator / Swagger / OpenAPI exposure found in the nuclei or fingerprint output for manual follow-up (no dedicated scanner — these need judgment calls on what's actually interesting)

Each stage checks for its own required tool and **skips gracefully with a
warning** if that tool isn't installed — a missing tool no longer aborts the
whole run.

## Requirements

- [assetfinder](https://github.com/tomnomnom/assetfinder)
- [subfinder](https://github.com/projectdiscovery/subfinder)
- [findomain](https://github.com/findomain/findomain)
- [amass](https://github.com/owasp-amass/amass) (passive enumeration)
- [wappalyzer](https://github.com/wappalyzer/wappalyzer) (npm package — tech fingerprint, run early in Stage 2)
- [httpx](https://github.com/projectdiscovery/httpx) (liveness + tech-detect). Note: Kali's apt package is named `httpx-toolkit`, and `install.sh` symlinks it to `httpx` automatically.
- [gowitness](https://github.com/sensepost/gowitness) (screenshots)
- [subzy](https://github.com/PentestPad/subzy) (takeover check)
- [nuclei](https://github.com/projectdiscovery/nuclei) — run `nuclei -update-templates` once before first use. Used three times per run:
  - `-tags takeover` for subdomain takeover checks
  - `-tags exposure,misconfig,config,backup` for exposed panels/files/misconfigurations
  - no tag restriction, for general exposures/CVEs across all discovered subdomains
- [wpscan](https://github.com/wpscanteam/wpscan) (WordPress-specific, auto-triggered in Stage 4)
- [joomscan](https://github.com/OWASP/joomscan) (Joomla-specific, auto-triggered in Stage 4)
- [droopescan](https://github.com/droope/droopescan) (Drupal-specific, auto-triggered in Stage 4)

## Install

Clone the repo and run the installer:

```bash
git clone <your-repo-url> subrecon
cd subrecon
chmod +x install.sh
./install.sh
```

The installer:
- Checks for all required tools and installs any that are missing (via `apt`,
  `go install`, `npm`, `gem`, or `pip3` depending on the tool — requires the
  relevant runtime to be present for non-apt fallbacks)
- Handles Kali's `httpx-toolkit` → `httpx` naming quirk automatically
- Updates nuclei's template library (`nuclei -update-templates`)
- Copies `bin/subrecon.sh` to `~/bin/subrecon.sh`
- Adds `~/bin` and (if used) Go's bin directory to your `PATH`
- Makes the script executable

You'll be prompted for your `sudo` password during several install steps.

## Usage

```bash
subrecon.sh <domain> [output_dir]
```

Example:

```bash
subrecon.sh example.com
```

This creates a folder named after the domain (e.g. `example.com/`) in your
current directory, containing:

| File / folder                 | Contents                                                        |
|--------------------------------|------------------------------------------------------------------|
| `example.comass.txt`           | assetfinder results                                               |
| `example.comsub.txt`           | subfinder results                                                  |
| `example.comdom.txt`           | findomain results                                                   |
| `example.comama.txt`           | amass (passive) results                                              |
| `example.comfin.txt`           | final merged, deduped subdomain list                                  |
| `example.comwappa.txt`         | wappalyzer fingerprint results (per subdomain)                          |
| `example.comlive.txt`          | httpx liveness check (status codes, titles)                              |
| `example.comtech.txt`          | httpx tech-detect fingerprint results (drives Stage 4 routing)             |
| `example.comscreenshots/`      | gowitness screenshots of live hosts                                         |
| `example.comtko.txt`           | subzy takeover check results                                                 |
| `example.comnuctko.txt`        | nuclei takeover-template results                                              |
| `example.comexp.txt`           | nuclei exposure/misconfig results                                              |
| `example.comvuln.txt`          | nuclei general scan results (CVEs, misc. exposures)                            |
| `example.comwpscan/`           | per-host wpscan results, only created if WordPress was detected                 |
| `example.comjoomscan/`         | per-host joomscan results, only created if Joomla was detected                   |
| `example.comdroopescan/`       | per-host droopescan results, only created if Drupal was detected                  |
| `example.comcmsflags.txt`      | items needing manual follow-up (undetected-CMS hosts without a scanner installed, Spring Actuator / Swagger / OpenAPI hits) |
| `run_<timestamp>.log`          | full run log — every tool's live output, errors, and progress                        |

Pass a second argument to control where the domain folder is created:

```bash
subrecon.sh example.com ~/engagements/clientA
# creates ~/engagements/clientA/example.com/
```

## Manual install (without install.sh)

```bash
mkdir -p ~/bin
cp bin/subrecon.sh ~/bin/
chmod +x ~/bin/subrecon.sh
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```
