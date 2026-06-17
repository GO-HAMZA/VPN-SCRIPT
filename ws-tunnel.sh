#!/bin/bash

# ==========================================
# COLOR CONFIGURATION
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
L_BLUE='\033[1;36m' # LIGHT BLUE
NC='\033[0m' # NO COLOR

# ==========================================
# HELPER: PAUSE BEFORE RETURNING TO MENU
# ==========================================
function pause_menu() {
    echo
    read -rp "PRESS ENTER TO RETURN TO MAIN MENU..."
}

# ==========================================
# PREPARE SYSTEM AND DOWNLOAD WEBSOCKET-VPN
# ==========================================
function prepare_system_and_download() {
    echo -e "${YELLOW}🔄 UPDATING SYSTEM AND INSTALLING DEPENDENCIES${NC}"
    sudo apt update -y > /dev/null 2>&1
    sudo apt install curl unzip -y > /dev/null 2>&1

    if [ ! -f "/usr/local/bin/WebSocket-VPN" ]; then
        echo -e "${YELLOW}⬇️ DOWNLOADING WEBSOCKET-VPN FROM GITHUB${NC}"
        curl -s -o WebSocket-VPN https://raw.githubusercontent.com/GO-HAMZA/VPN-SCRIPT/main/WebSocket-VPN
        
        chmod 777 WebSocket-VPN
        sudo mv WebSocket-VPN /usr/local/bin/WebSocket-VPN
        echo -e "${GREEN}✅ WEBSOCKET-VPN DOWNLOADED AND READY!${NC}"
    fi
}

# ==========================================
# 1. INSTALL SSH WS
# ==========================================
function install_ssh_ws() {
    clear
    echo -e "${L_BLUE}========================================${NC}"
    echo -e "${CYAN}        INSTALL SSH OVER WEBSOCKET      ${NC}"
    echo -e "${L_BLUE}========================================${NC}"
    
    prepare_system_and_download
    
    echo
    read -rp "🌐 LISTEN PORT [DEFAULT 80]: " ws_port
    ws_port=${ws_port:-80}
    
    read -rp "⚙️ TARGET PORT [DEFAULT 22]: " ssh_port
    ssh_port=${ssh_port:-22}

    echo
    echo -e "${YELLOW}⚙️ CREATING SYSTEMD SERVICE FOR SSH-WS...${NC}"
    sudo tee /etc/systemd/system/ssh-ws.service > /dev/null <<EOF
[Unit]
Description=SSH WebSocket Tunnel
After=network.target ssh.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/WebSocket-VPN -listenAddr :$ws_port -targetAddr 127.0.0.1:$ssh_port
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ssh-ws > /dev/null 2>&1
    sudo systemctl restart ssh-ws

    echo
    echo -e "${GREEN}✅ SSH WS INSTALLED SUCCESSFULLY!${NC}"
    echo -e "EXTERNAL PORT : ${CYAN}$ws_port${NC}"
    echo -e "TARGET PORT   : ${CYAN}$ssh_port (SSH)${NC}"
    echo -e "SERVICE NAME  : ${CYAN}SSH-WS${NC}"
    
    pause_menu
}

# ==========================================
# 2. INSTALL TROJAN WS
# ==========================================
function install_trojan_ws() {
    clear
    echo -e "${L_BLUE}========================================${NC}"
    echo -e "${CYAN}       INSTALL TROJAN OVER WEBSOCKET    ${NC}"
    echo -e "${L_BLUE}========================================${NC}"
    
    prepare_system_and_download
    
    echo
    read -rp "🔑 TROJAN PASSWORD: " trojan_password
    read -rp "🌐 LISTEN PORT [DEFAULT 8080]: " ws_port
    ws_port=${ws_port:-8080}
    
    read -rp "⚙️ TARGET PORT [DEFAULT 2000]: " xray_port
    xray_port=${xray_port:-2000}

    listen_ip="127.0.0.1"

    echo
    echo -e "${YELLOW}📦 INSTALLING XRAY CORE...${NC}"
    curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh | sudo bash -s -- install > /dev/null 2>&1

    sudo systemctl stop xray > /dev/null 2>&1
    sudo mkdir -p /usr/local/etc/xray

    echo -e "${YELLOW}⚙️ CONFIGURING XRAY...${NC}"
    sudo tee /usr/local/etc/xray/config.json > /dev/null <<EOF
{
  "inbounds": [
    {
      "tag": "trojan-inbound",
      "listen": "$listen_ip",
      "port": $xray_port,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "$trojan_password"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

    echo -e "${YELLOW}⚙️ CREATING SYSTEMD SERVICE FOR TROJAN-WS...${NC}"
    sudo tee /etc/systemd/system/trojan-ws.service > /dev/null <<EOF
[Unit]
Description=Trojan WebSocket Tunnel
After=network.target xray.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/WebSocket-VPN -listenAddr :$ws_port -targetAddr 127.0.0.1:$xray_port
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable xray > /dev/null 2>&1
    sudo systemctl restart xray
    sudo systemctl enable trojan-ws > /dev/null 2>&1
    sudo systemctl restart trojan-ws

    echo
    echo -e "${GREEN}✅ TROJAN WS INSTALLED SUCCESSFULLY!${NC}"
    echo -e "EXTERNAL PORT   : ${CYAN}$ws_port${NC}"
    echo -e "XRAY LOCAL PORT : ${CYAN}$xray_port${NC}"
    echo -e "TROJAN PASSWORD : ${CYAN}$trojan_password${NC}"
    echo -e "SERVICE NAMES   : ${CYAN}XRAY, TROJAN-WS${NC}"
    
    pause_menu
}

# ==========================================
# 3. RESTART SERVICES
# ==========================================
function restart_services() {
    clear
    echo -e "${L_BLUE}========================================${NC}"
    echo -e "${CYAN}             RESTART SERVICES           ${NC}"
    echo -e "${L_BLUE}========================================${NC}"
    echo -e "  ${YELLOW}1.${NC} RESTART SSH WS"
    echo -e "  ${YELLOW}2.${NC} RESTART TROJAN WS (XRAY)"
    echo
    read -rp "SELECT THE SERVICE TO RESTART [1-2]: " srv_choice
    
    echo
    case $srv_choice in
        1|01)
            echo -e "${YELLOW}🔄 RESTARTING SSH-WS SERVICE...${NC}"
            sudo systemctl restart ssh-ws
            echo -e "${GREEN}✅ SSH-WS RESTARTED SUCCESSFULLY!${NC}"
            ;;
        2|02)
            echo -e "${YELLOW}🔄 RESTARTING XRAY AND TROJAN-WS SERVICES...${NC}"
            sudo systemctl restart xray
            sudo systemctl restart trojan-ws
            echo -e "${GREEN}✅ TROJAN-WS AND XRAY RESTARTED SUCCESSFULLY!${NC}"
            ;;
        *)
            echo -e "${RED}❌ INVALID CHOICE!${NC}"
            ;;
    esac
    
    pause_menu
}

# ==========================================
# 4. CHECK SERVICE STATUS
# ==========================================
function check_status() {
    clear
    echo -e "${L_BLUE}========================================${NC}"
    echo -e "${CYAN}           CHECK SERVICE STATUS         ${NC}"
    echo -e "${L_BLUE}========================================${NC}"
    echo -e "  ${YELLOW}[01]${NC} STATUS OF SSH WS"
    echo -e "  ${YELLOW}[02]${NC} STATUS OF TROJAN WS"
    echo
    read -rp "SELECT THE SERVICE TO CHECK [1-2]: " stat_choice
    
    echo
    case $stat_choice in
        1|01)
            echo -e "${YELLOW}ℹ️ FETCHING SSH-WS STATUS...${NC}"
            sudo systemctl status ssh-ws --no-pager
            ;;
        2|02)
            echo -e "${YELLOW}ℹ️ FETCHING TROJAN-WS AND XRAY STATUS...${NC}"
            sudo systemctl status trojan-ws --no-pager
            echo -e "${L_BLUE}----------------------------------------${NC}"
            sudo systemctl status xray --no-pager
            ;;
        *)
            echo -e "${RED}❌ INVALID CHOICE!${NC}"
            ;;
    esac
    
    pause_menu
}

# ==========================================
# 5. UNINSTALL ALL SERVICES
# ==========================================
function uninstall_all() {
    clear
    echo -e "${L_BLUE}========================================${NC}"
    echo -e "${RED}          UNINSTALL & CLEAN UP          ${NC}"
    echo -e "${L_BLUE}========================================${NC}"
    echo -e "${YELLOW}STOPPING AND REMOVING ALL SERVICES...${NC}"
    
    sudo systemctl stop ssh-ws trojan-ws xray 2>/dev/null
    sudo systemctl disable ssh-ws trojan-ws xray 2>/dev/null
    
    sudo rm -f /etc/systemd/system/ssh-ws.service
    sudo rm -f /etc/systemd/system/trojan-ws.service
    
    sudo rm -f /usr/local/bin/WebSocket-VPN
    
    sudo systemctl daemon-reload
    echo
    echo -e "${GREEN}✅ ALL CUSTOM SERVICES AND FILES HAVE BEEN COMPLETELY REMOVED.${NC}"
    
    pause_menu
}

# ==========================================
# MAIN MENU
# ==========================================
while true; do
    clear # THIS CLEARS THE SCREEN SO ONLY THE MENU IS VISIBLE
    echo -e "${L_BLUE}========================================${NC}"
    echo -e "${GREEN}       V P N   I N S T A L L E R        ${NC}"
    echo -e "${L_BLUE}========================================${NC}"
    echo -e "  ${YELLOW}[01]${NC} INSTALL SSH WS"
    echo -e "  ${YELLOW}[02]${NC} INSTALL TROJAN WS"
    echo -e "  ${YELLOW}[03]${NC} RESTART SERVICES"
    echo -e "  ${YELLOW}[04]${NC} CHECK SERVICE STATUS"
    echo -e "  ${YELLOW}[05]${NC} UNINSTALL SERVICES"
    echo -e "  ${YELLOW}[00]${NC} EXIT"
    echo -e "${L_BLUE}========================================${NC}"
    read -rp "➡️ [0-5]: " choice

    case $choice in
        1|01) install_ssh_ws ;;
        2|02) install_trojan_ws ;;
        3|03) restart_services ;;
        4|04) check_status ;;
        5|05) uninstall_all ;;
        0|00)
            echo -e "${YELLOW}EXITING...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ INVALID OPTION! PLEASE TRY AGAIN.${NC}"
            sleep 2
            ;;
    esac
done
