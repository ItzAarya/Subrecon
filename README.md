# subrecon

A bash recon-to-triage pipeline for Kali Linux. Runs subdomain enumeration,
liveness/tech triage, screenshots, and takeover/vulnerability checks against a
target domain — all in one command.

**Only use this against domains you are authorized to test.**

## Pipeline

**Stage 1 — Enumeration**
`assetfinder`, `subfinder`, `findomain`, `amass` (passive) → merged + deduped list

**Stage 2 — Triage**
`httpx` (liveness, status codes, titles, tech fingerprint) → `gowitness` (screenshots of live hosts)

**Stage 3 — Easy wins**
`subzy` + `nuclei` (takeover templates), `nuclei` (exposed panels/files/misconfig), `nuclei` (general templates, incl. CVEs)

Each stage checks for its own required tool and **skips gracefully with a
warning** if that tool isn't installed — a missing tool no longer aborts the
whole run.

## Requirements

- [assetfinder](https://github.com/tomnomnom/assetfinder)
- [subfinder](https://github.com/projectdiscovery/subfinder)
- [findomain](https://github.com/findomain/findomain)
- [amass](https://github.com/owasp-amass/amass) (passive enumeration)
- [httpx](https://github.com/projectdiscovery/httpx) (liveness + tech-detect). Note: Kali's apt package is named `httpx-toolkit`, and `install.sh` symlinks it to `httpx` automatically.
- [gowitness](https://github.com/sensepost/gowitness) (screenshots)
- [subzy](https://github.com/PentestPad/subzy) (takeover check)
- [nuclei](https://github.com/projectdiscovery/nuclei) — run `nuclei -update-templates` once before first use. Used three times per run:
  - `-tags takeover` for subdomain takeover checks
  - `-tags exposure,misconfig,config,backup` for exposed panels/files/misconfigurations
  - no tag restriction, for general exposures/CVEs across all discovered subdomains

## Install

Clone the repo and run the installer:

```bash
git clone <your-repo-url> subrecon
cd subrecon
chmod +x install.sh
./install.sh
```

The installer:
- Checks for all required tools and installs any that are missing (via `apt`
  where available, or `go install` as a fallback — requires Go for that path)
- Handles Kali's `httpx-toolkit` → `httpx` naming quirk automatically
- Updates nuclei's template library (`nuclei -update-templates`)
- Copies `bin/subrecon.sh` to `~/bin/subrecon.sh`
- Adds `~/bin` and (if used) Go's bin directory to your `PATH`
- Makes the script executable

You'll be prompted for your `sudo` password during the apt install steps.

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

| File                        | Contents                                              |
|------------------------------|--------------------------------------------------------|
| `example.comass.txt`         | assetfinder results                                    |
| `example.comsub.txt`         | subfinder results                                      |
| `example.comdom.txt`         | findomain results                                       |
| `example.comama.txt`         | amass (passive) results                                 |
| `example.comfin.txt`         | final merged, deduped subdomain list                    |
| `example.comlive.txt`        | httpx liveness check (status codes, titles)              |
| `example.comtech.txt`        | httpx tech-detect fingerprint results                     |
| `example.comscreenshots/`    | gowitness screenshots of live hosts                       |
| `example.comtko.txt`         | subzy takeover check results                               |
| `example.comnuctko.txt`      | nuclei takeover-template results                            |
| `example.comexp.txt`         | nuclei exposure/misconfig results                             |
| `example.comvuln.txt`        | nuclei general scan results (CVEs, misc. exposures)             |
| `run_<timestamp>.log`        | run log / errors                                                 |

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
