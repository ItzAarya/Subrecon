# subrecon

A small bash script for Kali Linux that runs `assetfinder`, `subfinder`, and `findomain`
against a target domain, saves each tool's raw output, then merges and dedupes the
results into a single file.

**Only use this against domains you are authorized to test.**

## Requirements

Make sure these tools are installed and available in your `PATH`:

- [assetfinder](https://github.com/tomnomnom/assetfinder)
- [subfinder](https://github.com/projectdiscovery/subfinder)
- [findomain](https://github.com/findomain/findomain)
- [nuclei](https://github.com/projectdiscovery/nuclei) (subdomain takeover check, using the `takeover` template tag — run `nuclei -update-templates` once before first use)

## Install

Clone the repo and run the installer:

```bash
git clone <your-repo-url> subrecon
cd subrecon
chmod +x install.sh
./install.sh
```

The installer:
- Copies `bin/subrecon.sh` to `~/bin/subrecon.sh`
- Adds `~/bin` to your `PATH` (in `.bashrc` or `.zshrc`, whichever you use) if it isn't already
- Makes the script executable

After installing, reload your shell config or open a new terminal:

```bash
source ~/.bashrc   # or ~/.zshrc
```

## Usage

```bash
subrecon.sh <domain> [output_dir]
```

Example:

```bash
subrecon.sh example.com
```

This creates a folder named after the domain (e.g. `example.com/`) in your current
directory, containing:

| File                  | Contents                          |
|------------------------|------------------------------------|
| `example.comass.txt`   | assetfinder results                |
| `example.comsub.txt`   | subfinder results                  |
| `example.comdom.txt`   | findomain results                  |
| `example.comfin.txt`   | final merged, deduped subdomain list |
| `example.comtko.txt`   | nuclei subdomain takeover check results |
| `run_<timestamp>.log`  | run log / errors                   |

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
