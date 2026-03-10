#!/usr/bin/env bash
# =============================================================================
#  webscout.sh — Masscan + Aquatone web recon pipeline
#
#  Usage:
#    chmod +x webscout.sh
#    sudo ./webscout.sh <subnet> [output_dir]
#
#  Examples:
#    sudo ./webscout.sh 192.168.1.0/24
#    sudo ./webscout.sh 10.0.0.0/16 ./my_report
#
#  Dependencies:
#    masscan   — sudo apt install masscan
#    aquatone  — https://github.com/michenriksen/aquatone/releases
#                place binary in /usr/local/bin/aquatone or $PATH
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Banner ────────────────────────────────────────────────────────────────────
banner() {
cat << 'EOF'

  ██╗    ██╗███████╗██████╗ ███████╗ ██████╗ ██████╗ ██╗   ██╗████████╗
  ██║    ██║██╔════╝██╔══██╗██╔════╝██╔════╝██╔═══██╗██║   ██║╚══██╔══╝
  ██║ █╗ ██║█████╗  ██████╔╝███████╗██║     ██║   ██║██║   ██║   ██║
  ██║███╗██║██╔══╝  ██╔══██╗╚════██║██║     ██║   ██║██║   ██║   ██║
  ╚███╔███╔╝███████╗██████╔╝███████║╚██████╗╚██████╔╝╚██████╔╝   ██║
   ╚══╝╚══╝ ╚══════╝╚═════╝ ╚══════╝ ╚═════╝ ╚═════╝  ╚═════╝    ╚═╝
Masscan + Aquatone Web Recon Pipeline created by 4rk4n3 |  use responsibly

EOF
}

# ── Logging helpers ───────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[*]${RESET} $*"; }
success() { echo -e "${GREEN}[+]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
error()   { echo -e "${RED}[✗]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

# ── Dependency checks + auto-install ─────────────────────────────────────────
install_aquatone() {
    info "aquatone not found — attempting auto-install..."

    # Ensure unzip is available
    if ! command -v unzip &>/dev/null; then
        info "Installing unzip..."
        apt-get install -y unzip &>/dev/null || die "Could not install unzip. Run: sudo apt install unzip"
    fi

    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  arch="linux_amd64" ;;
        aarch64) arch="linux_arm64" ;;
        armv7*)  arch="linux_arm" ;;
        *)       die "Unsupported arch: $arch" ;;
    esac

    local tmpdir
    tmpdir=$(mktemp -d)
    local zip_path="$tmpdir/aquatone.zip"

    # Try to fetch the latest release tag from GitHub API
    info "Fetching latest aquatone release info..."
    local latest_url="https://api.github.com/repos/michenriksen/aquatone/releases/latest"
    local release_json=""

    if command -v curl &>/dev/null; then
        release_json=$(curl -sf "$latest_url" 2>/dev/null || true)
    elif command -v wget &>/dev/null; then
        release_json=$(wget -qO- "$latest_url" 2>/dev/null || true)
    fi

    # Parse download URL from JSON (grep fallback — no jq needed)
    local download_url=""
    if [[ -n "$release_json" ]]; then
        download_url=$(echo "$release_json" | grep -o ""browser_download_url": *"[^"]*${arch}[^"]*\.zip"" | grep -o 'https://[^"]*' | head -1)
    fi

    # Fallback to known-good URL if API failed
    if [[ -z "$download_url" ]]; then
        warn "Could not fetch release info from GitHub API — falling back to v1.7.0"
        download_url="https://github.com/michenriksen/aquatone/releases/download/v1.7.0/aquatone_${arch}_v1.7.0.zip"
    fi

    info "Downloading: $download_url"
    local dl_ok=false
    if command -v curl &>/dev/null; then
        curl -fL "$download_url" -o "$zip_path" 2>/dev/null && dl_ok=true
    fi
    if [[ "$dl_ok" == false ]] && command -v wget &>/dev/null; then
        wget -q "$download_url" -O "$zip_path" 2>/dev/null && dl_ok=true
    fi

    if [[ "$dl_ok" == false ]] || [[ ! -s "$zip_path" ]]; then
        rm -rf "$tmpdir"
        echo ""
        error "Auto-install failed. Install aquatone manually:"
        echo -e "    ${CYAN}1.${RESET} Go to: https://github.com/michenriksen/aquatone/releases"
        echo -e "    ${CYAN}2.${RESET} Download the linux_amd64 zip"
        echo -e "    ${CYAN}3.${RESET} Run: sudo unzip aquatone_*.zip -d /usr/local/bin && sudo chmod +x /usr/local/bin/aquatone"
        echo ""
        exit 1
    fi

    unzip -q "$zip_path" -d "$tmpdir" || die "Failed to unzip aquatone."
    mv "$tmpdir/aquatone" /usr/local/bin/aquatone
    chmod +x /usr/local/bin/aquatone
    rm -rf "$tmpdir"

    success "aquatone installed → $(aquatone --version 2>/dev/null | head -1 || echo '/usr/local/bin/aquatone')"
}

check_deps() {
    # masscan — hard requirement
    if ! command -v masscan &>/dev/null; then
        info "masscan not found — installing..."
        apt-get install -y masscan &>/dev/null || die "Failed to install masscan. Run: sudo apt install masscan"
        success "masscan installed."
    fi

    # aquatone — auto-install if missing
    if ! command -v aquatone &>/dev/null; then
        install_aquatone
    fi

    # chromium or google-chrome required by aquatone for screenshots
    if ! command -v chromium &>/dev/null && ! command -v chromium-browser &>/dev/null && ! command -v google-chrome &>/dev/null; then
        info "Chromium not found — installing (required by aquatone)..."
        apt-get install -y chromium &>/dev/null ||         apt-get install -y chromium-browser &>/dev/null ||         die "Failed to install chromium. Run: sudo apt install chromium"
        success "Chromium installed."
    fi
}

# ── Root check ────────────────────────────────────────────────────────────────
check_root() {
    [[ $EUID -eq 0 ]] || die "masscan requires root. Run with: sudo $0 $*"
}

# ── Args ──────────────────────────────────────────────────────────────────────
usage() {
    echo -e "Usage: ${BOLD}sudo $0 <subnet> [output_dir]${RESET}"
    echo -e "  subnet      CIDR range to scan  (e.g. 192.168.1.0/24)"
    echo -e "  output_dir  Where to save results (default: ./webscout_<timestamp>)"
    exit 1
}

[[ $# -lt 1 ]] && usage

check_root "$@"
check_deps

SUBNET="$1"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${2:-./webscout_${TIMESTAMP}}"

# ── Setup output directory ────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

MASSCAN_LIST="$OUTPUT_DIR/masscan_raw.txt"
TARGET_LIST="$OUTPUT_DIR/targets.txt"
URL_LIST="$OUTPUT_DIR/urls.txt"
AQUATONE_DIR="$OUTPUT_DIR/aquatone"
LOG_FILE="$OUTPUT_DIR/webscout.log"

mkdir -p "$AQUATONE_DIR"

# Tee all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# ── Print banner + config ─────────────────────────────────────────────────────
banner
echo -e "${BOLD}  Subnet       :${RESET} $SUBNET"
echo -e "${BOLD}  Ports        :${RESET} 80, 443"
echo -e "${BOLD}  Output dir   :${RESET} $OUTPUT_DIR"
echo -e "${BOLD}  Started      :${RESET} $(date)"
echo ""

# ── Stage 1: Masscan ─────────────────────────────────────────────────────────
info "Stage 1/3 — Running masscan on $SUBNET (ports 80, 443)..."

# -oL writes results line-by-line as they arrive — reliable even with 0 results
set +e
masscan "$SUBNET" \
    -p 80,443 \
    --rate 1000 \
    --wait 5 \
    -oL "$MASSCAN_LIST"

MASSCAN_EXIT=$?
set -e

if [[ $MASSCAN_EXIT -ne 0 ]]; then
    die "masscan exited with code $MASSCAN_EXIT — check output above. Common causes:\n    • masscan not in PATH\n    • interface not detected (try adding: --interface eth0)\n    • subnet unreachable"
fi

# -oL always creates the file (even if empty), so check line count
MASSCAN_HITS=$(grep -c "^open" "$MASSCAN_LIST" 2>/dev/null || echo 0)
info "masscan found $MASSCAN_HITS open port(s)."

success "Masscan complete. Raw results: $MASSCAN_LIST"

# ── Stage 2: Parse results → target list + URL list ──────────────────────────
info "Stage 2/3 — Parsing results and building target list..."

# Parse masscan -oL list format:
#   open tcp 80 192.168.1.1 <timestamp>
python3 - "$MASSCAN_LIST" "$TARGET_LIST" "$URL_LIST" << 'PYEOF'
import sys

list_path, target_path, url_path = sys.argv[1], sys.argv[2], sys.argv[3]

hosts_80  = set()
hosts_443 = set()

try:
    with open(list_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # format: open tcp <port> <ip> <timestamp>
            parts = line.split()
            if len(parts) >= 4 and parts[0] == "open":
                port = parts[2]
                ip   = parts[3]
                if port == "80":
                    hosts_80.add(ip)
                elif port == "443":
                    hosts_443.add(ip)
except Exception as e:
    print(f"[!] Parse error: {e}", file=sys.stderr)
    sys.exit(1)

all_hosts = hosts_80 | hosts_443

with open(target_path, "w") as tf:
    for ip in sorted(all_hosts):
        tf.write(ip + "\n")

with open(url_path, "w") as uf:
    for ip in sorted(hosts_443):
        uf.write(f"https://{ip}\n")
    for ip in sorted(hosts_80 - hosts_443):
        uf.write(f"http://{ip}\n")

print(f"  Hosts with port 80  : {len(hosts_80)}")
print(f"  Hosts with port 443 : {len(hosts_443)}")
print(f"  Total unique hosts  : {len(all_hosts)}")
PYEOF

TOTAL=$(wc -l < "$TARGET_LIST" | tr -d ' ')

if [[ "$TOTAL" -eq 0 ]]; then
    warn "No hosts found with ports 80 or 443 open."
    warn "Try increasing --rate or check that the subnet is reachable."
    exit 0
fi

success "Found $TOTAL host(s) with web ports open."
success "Target list saved: $TARGET_LIST"
success "URL list saved:    $URL_LIST"
echo ""
info "Targets:"
while IFS= read -r ip; do
    echo "    $(grep -c "^$ip$" "$TARGET_LIST" &>/dev/null && echo '' )  $ip"
done < "$TARGET_LIST"
echo ""

# ── Stage 3: Aquatone ─────────────────────────────────────────────────────────
info "Stage 3/3 — Running aquatone to capture screenshots..."

cat "$URL_LIST" | aquatone \
    -out "$AQUATONE_DIR" \
    -screenshot-timeout 15000 \
    -http-timeout 8000 \
    -scan-timeout 5000 \
    -silent

# ── Final summary ─────────────────────────────────────────────────────────────
REPORT="$AQUATONE_DIR/aquatone_report.html"
SCREENSHOT_COUNT=$(find "$AQUATONE_DIR/screenshots" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo -e "${BOLD}$(printf '=%.0s' {1..60})${RESET}"
echo -e "${BOLD}  SCAN COMPLETE${RESET}"
echo -e "${BOLD}$(printf '=%.0s' {1..60})${RESET}"
echo -e "  Subnet scanned  : $SUBNET"
echo -e "  Hosts found     : $TOTAL"
echo -e "  Screenshots     : $SCREENSHOT_COUNT"
echo -e "  Target list     : $TARGET_LIST"
echo -e "  URL list        : $URL_LIST"
echo -e "  Aquatone report : $REPORT"
echo -e "  Log             : $LOG_FILE"
echo -e "  Finished        : $(date)"
echo -e "${BOLD}$(printf '=%.0s' {1..60})${RESET}"
echo ""

if [[ -f "$REPORT" ]]; then
    success "Open your report: ${BOLD}$REPORT${RESET}"
else
    warn "Aquatone report not found — check $AQUATONE_DIR for output."
fi
