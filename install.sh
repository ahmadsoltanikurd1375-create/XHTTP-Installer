#!/usr/bin/env bash
# =============================================================
# XHTTP Installer — Custom Edition with Traffic Management
# Owner: ahmadsoltanikurd1375
# =============================================================

set -euo pipefail

readonly AVC_BUILD_ID="avc-7f3a92e1-2025-avacocloud"
export AVC_BUILD_ID

REPO_URL="https://github.com/avacocloud/XHTTP-Installer.git"
TARGET_DIR="/root/XHTTP-Installer"
BRANCH="main"

C_CYAN="\033[1;36m"; C_GREEN="\033[1;32m"; C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"; C_RESET="\033[0m"

info() { echo -e "${C_CYAN}➜${C_RESET} $*"; }
ok() { echo -e "${C_GREEN}✔${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}⚠${C_RESET} $*"; }
fail() { echo -e "${C_RED}✘${C_RESET} $*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
    fail "Run as root (use: sudo bash ...)"
fi

if ! command -v git &>/dev/null; then
    info "Installing git..."
    apt-get update -qq && apt-get install -y -qq git
    ok "git installed"
fi

# ── Clone Core Project ───────────────────────────────────
if [[ -d "$TARGET_DIR/.git" ]]; then
    warn "Existing install found — updating..."
    git -C "$TARGET_DIR" fetch --depth=1 origin "$BRANCH"
    git -C "$TARGET_DIR" reset --hard "origin/$BRANCH"
else
    if [[ -d "$TARGET_DIR" ]]; then rm -rf "$TARGET_DIR"; fi
    info "Cloning core framework..."
    git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
fi

# ── Run Core Installer ───────────────────────────────────
cd "$TARGET_DIR"
chmod +x Deploy-Ubuntu.sh
info "Launching core installer..."
echo ""
bash Deploy-Ubuntu.sh "$@"

# ── Custom Traffic & User Management Section ─────────────
echo -e "${C_CYAN}==================================================${C_RESET}"
echo -e "${C_GREEN}    XHTTP CUSTOM USER & VOLUME MANAGEMENT         ${C_RESET}"
echo -e "${C_CYAN}==================================================${C_RESET}"

read -p "How many configurations to generate? (e.g., 10): " config_count
read -p "Enter volume limit for each user in GB (e.g., 10): " volume_gb

mkdir -p /etc/xhttp-custom
LIMITS_FILE="/etc/xhttp-custom/user_limits.db"
echo "# User Volume Limits" > "$LIMITS_FILE"

info "Generating $config_count configurations..."

XRAY_CONFIG="/usr/local/etc/xray/config.json"
if [ ! -f "$XRAY_CONFIG" ]; then
    XRAY_CONFIG="/etc/xray/config.json"
fi

for ((i=1; i<=config_count; i++))
do
    user_id=$(cat /proc/sys/kernel/random/uuid)
    user_name="user_$i"
    
    echo "${user_name}:${volume_gb}:${user_id}" >> "$LIMITS_FILE"
    
    echo -e "${C_GREEN}✔ Created:${C_RESET} ${user_name} | Limit: ${volume_gb} GB"
    echo -e "${C_CYAN}Config Link ${i}:${C_RESET} vless://${user_id}@YOUR_SERVER_IP:443?path=%2F&security=tls&encryption=none&type=http#${user_name}"
    echo "--------------------------------------------------"
done

# ── Traffic Monitor Background Script ────────────────────
MONITOR_SCRIPT="/usr/local/bin/xhttp-monitor"
cat << 'EOF' > "$MONITOR_SCRIPT"
#!/usr/bin/env bash
LIMITS_FILE="/etc/xhttp-custom/user_limits.db"
while true; do
    if [ -f "$LIMITS_FILE" ]; then
        while IFS=: read -r username limit_gb uuid; do
            if [[ "$username" =~ ^# ]]; then continue; fi
            
            CURRENT_USAGE_GB=$(xray api stats --pattern "$username" 2>/dev/null | grep "value" | awk '{print $2/1024/1024/1024}' || echo 0)
            
            if (( $(echo "$CURRENT_USAGE_GB >= $limit_gb" | bc -l 2>/dev/null || echo 0) )); then
                sed -i "s/$uuid/disabled-expired-uuid/g" /etc/xray/config.json 2>/dev/null
                systemctl restart xray 2>/dev/null
            fi
        done < "$LIMITS_FILE"
    fi
    sleep 60
done
EOF

chmod +x "$MONITOR_SCRIPT"
nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 &

ok "Traffic protection guard successfully deployed!"
echo -e "${C_GREEN}All done! Your customized project is ready.${C_RESET}"
