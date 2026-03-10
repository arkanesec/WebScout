# WebScout

```
  ██╗    ██╗███████╗██████╗ ███████╗ ██████╗ ██████╗ ██╗   ██╗████████╗
  ██║    ██║██╔════╝██╔══██╗██╔════╝██╔════╝██╔═══██╗██║   ██║╚══██╔══╝
  ██║ █╗ ██║█████╗  ██████╔╝███████╗██║     ██║   ██║██║   ██║   ██║
  ██║███╗██║██╔══╝  ██╔══██╗╚════██║██║     ██║   ██║██║   ██║   ██║
  ╚███╔███╔╝███████╗██████╔╝███████║╚██████╗╚██████╔╝╚██████╔╝   ██║
   ╚══╝╚══╝ ╚══════╝╚═════╝ ╚══════╝ ╚═════╝ ╚═════╝  ╚═════╝    ╚═╝
Masscan + Aquatone Web Recon Pipeline created by 4rk4n3 |  use responsibly
```

WebScout is a Bash recon pipeline that sweeps a subnet for web servers and automatically screenshots every one it finds. Point it at a CIDR range, walk away, and come back to a full HTML report of every live web interface.

---

## How it works

**Stage 1 — Masscan** sweeps the target subnet for open ports 80 and 443 at 1000 packets/second and saves results to a list file.

**Stage 2 — Parse** extracts all IPs with open web ports, writes a clean `targets.txt` (IPs only) and a `urls.txt` (full HTTP/HTTPS URLs, preferring HTTPS where both ports are open).

**Stage 3 — Aquatone** reads the URL list, visits every host with a headless Chromium browser, takes screenshots, and produces a single `aquatone_report.html` you can open in any browser.

---

## Dependencies

WebScout auto-installs everything it needs on first run (requires internet access):

| Tool | Purpose | Auto-install |
|---|---|---|
| `masscan` | Fast port scanning | `apt install masscan` |
| `aquatone` | Screenshotting | Downloaded from GitHub releases |
| `chromium` | Headless browser for aquatone | `apt install chromium` |
| `python3` | Parses masscan output | Pre-installed on Kali |
| `unzip` | Extracts aquatone binary | `apt install unzip` |

If auto-install fails for aquatone, the script prints manual install instructions:

```bash
# Manual aquatone install
wget https://github.com/michenriksen/aquatone/releases/download/v1.7.0/aquatone_linux_amd64_v1.7.0.zip
sudo unzip aquatone_linux_amd64_v1.7.0.zip -d /usr/local/bin
sudo chmod +x /usr/local/bin/aquatone
```

---

## Installation

```bash
git clone https://github.com/arkanesec/webscout.git
cd webscout
chmod +x webscout.sh
```

---

## Usage

```bash
sudo ./webscout.sh <subnet> [output_dir]
```

```bash
# Scan a /24, save to auto-named folder
sudo ./webscout.sh 192.168.1.0/24

# Scan with a custom output directory
sudo ./webscout.sh 10.10.20.0/24 ./scan

# Scan a larger range
sudo ./webscout.sh 10.0.0.0/16 ./full_scan
```

> **Root is required** — masscan uses raw sockets which need elevated privileges.

### Arguments

| Argument | Required | Description |
|---|---|---|
| `subnet` | Yes | CIDR range to scan (e.g. `192.168.1.0/24`) |
| `output_dir` | No | Directory to save results (default: `./webscout_<timestamp>`) |

---

## Output

All results are saved to the output directory:

```
scan/
├── masscan_raw.txt       # Raw masscan results (-oL format)
├── targets.txt           # Clean list of IPs with open web ports
├── urls.txt              # Full HTTP/HTTPS URLs fed to aquatone
├── webscout.log          # Full run log
└── aquatone/
    ├── aquatone_report.html   # ← Open this in your browser
    ├── screenshots/           # PNG screenshots of every web interface
    ├── headers/               # HTTP response headers per host
    └── aquatone_urls.txt      # URLs aquatone successfully visited
```

Open the report:

```bash
firefox scan/aquatone/aquatone_report.html
```

The HTML report displays every screenshot in a grid with the URL, HTTP status code, and response headers — making it easy to spot login panels, dashboards, default pages, and misconfigured services at a glance.

---

## Troubleshooting

**masscan finds no hosts / exits with an error**

masscan may not auto-detect the correct network interface. Add `--interface` to the masscan command inside the script:

```bash
# Edit webscout.sh and add --interface to the masscan call:
masscan "$SUBNET" -p 80,443 --rate 1000 --wait 5 --interface eth0 -oL "$MASSCAN_LIST"
# Use tun0 if scanning over a VPN
```

**aquatone produces no screenshots**

Aquatone requires Chromium. Verify it's installed and in your PATH:

```bash
which chromium || which chromium-browser || which google-chrome
```

If none are found:

```bash
sudo apt install chromium
```

**Scan is too slow / too fast**

Adjust the `--rate` value in the masscan command inside the script. Higher values are faster but may overwhelm the network or trigger IDS:

```bash
--rate 500    # Conservative
--rate 1000   # Default
--rate 5000   # Aggressive (use with caution)
```

---

## Legal notice

> **Only scan networks you own or have explicit written permission to test.**
> Unauthorized port scanning and screenshotting may violate the Computer Fraud and Abuse Act (CFAA) and equivalent laws in your jurisdiction. The authors assume no liability for misuse.

---

## License

MIT

