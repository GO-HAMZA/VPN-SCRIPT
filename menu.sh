#!/bin/bash

# COLORS
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # NO COLOR

WORK_DIR=$(pwd)

# INSTALL PROTOCOLS (NEW OPTION 1)
install_protocols() {
    clear
    echo -e "${CYAN}=== INSTALL PROTOCOLS ===${NC}"
    echo -e "${YELLOW}>> DOWNLOADING AND RUNNING INSTALLER SCRIPT...${NC}"
    
    # تنفيذ الأمر الذي طلبته
    rm -rf InstallerScript.sh && wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/refs/heads/main/InstallerScript.sh -O InstallerScript.sh && chmod +x InstallerScript.sh && ./InstallerScript.sh
    
    echo -e "\n${GREEN}✅ PROTOCOLS SCRIPT FINISHED.${NC}"
    echo -e "PRESS [ENTER] TO RETURN..."
    read
}

# INSTALL WS FOR SSH
install_ws_ssh() {
    clear
    echo -e "${CYAN}=== SETUP WEBSOCKET-GO FOR SSH ===${NC}"
    if [ ! -f "$WORK_DIR/WebSocket-GO" ]; then
        echo -e "${RED}❌ ERROR: 'WebSocket-GO' NOT FOUND IN $WORK_DIR${NC}"
        echo -e "PRESS [ENTER] TO RETURN..."
        read
        return
    fi
    chmod 777 "$WORK_DIR/WebSocket-GO"
    read -rp "ENTER LISTENING PORT FOR WS (DEFAULT: 80): " ws_port
    ws_port=${ws_port:-80}
    read -rp "ENTER TARGET SSH PORT (DEFAULT: 22): " ssh_port
    ssh_port=${ssh_port:-22}

    echo -e "${YELLOW}>> CREATING SYSTEMD SERVICE (WS-SSH)...${NC}"
    sudo tee /etc/systemd/system/ws-ssh.service > /dev/null <<EOF
[Unit]
Description=WEBSOCKET-GO FOR SSH
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/WebSocket-GO -listenAddr :$ws_port -targetAddr 127.0.0.1:$ssh_port
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ws-ssh
    sudo systemctl restart ws-ssh

    echo -e "${GREEN}✅ WEBSOCKET-GO FOR SSH IS RUNNING ON PORT $ws_port (TARGET: $ssh_port)${NC}"
    echo -e "PRESS [ENTER] TO RETURN..."
    read
}

# INSTALL WS FOR TROJAN + XRAY
install_ws_trojan() {
    clear
    echo -e "${CYAN}=== SETUP WEBSOCKET-GO FOR TROJAN ===${NC}"
    if [ ! -f "$WORK_DIR/WebSocket-GO" ]; then
        echo -e "${RED}❌ ERROR: 'WebSocket-GO' NOT FOUND IN $WORK_DIR${NC}"
        echo -e "PRESS [ENTER] TO RETURN..."
        read
        return
    fi
    chmod 777 "$WORK_DIR/WebSocket-GO"

    read -rp "ENTER LISTENING PORT FOR WS (DEFAULT: 8080): " ws_port
    ws_port=${ws_port:-8080}
    read -rp "ENTER A PASSWORD FOR TROJAN CLIENTS: " trojan_password
    read -rp "ENTER XRAY BACKEND PORT (DEFAULT: 2000): " port
    port=${port:-2000}

    echo -e "\n${YELLOW}>> INSTALLING XRAY-CORE & DEPENDENCIES...${NC}"
    sudo apt update && sudo apt install -y curl unzip net-tools
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

    sudo systemctl stop xray
    sudo mkdir -p /usr/local/etc/xray

    echo -e "${YELLOW}>> WRITING XRAY CONFIG...${NC}"
    sudo tee /usr/local/etc/xray/config.json > /dev/null <<EOF
{
  "inbounds": [
    {
      "tag": "trojan-inbound",
      "listen": "127.0.0.1",
      "port": $port,
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

    sudo systemctl daemon-reload
    sudo systemctl enable xray
    sudo systemctl restart xray

    echo -e "${YELLOW}>> CREATING SYSTEMD SERVICE (WS-TROJAN)...${NC}"
    sudo tee /etc/systemd/system/ws-trojan.service > /dev/null <<EOF
[Unit]
Description=WEBSOCKET-GO FOR TROJAN
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/WebSocket-GO -listenAddr :$ws_port -targetAddr 127.0.0.1:$port
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ws-trojan
    sudo systemctl restart ws-trojan

    echo -e "${GREEN}✅ WEBSOCKET-GO FOR TROJAN IS RUNNING ON PORT $ws_port (BACKEND: $port)${NC}"
    echo -e "🔹 TROJAN PASSWORD: $trojan_password"
    echo -e "PRESS [ENTER] TO RETURN..."
    read
}

# KILL PORT
kill_port() {
    clear
    echo -e "${CYAN}=== KILL A SPECIFIC PORT ===${NC}"
    read -rp "ENTER THE PORT NUMBER YOU WANT TO KILL (E.G., 80 OR 8080): " k_port
    if [[ -n "$k_port" && "$k_port" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}KILLING PROCESSES ON PORT $k_port...${NC}"
        sudo fuser -k -n tcp "$k_port" 2>/dev/null
        echo -e "${GREEN}✅ PORT $k_port HAS BEEN FREED SUCCESSFULLY.${NC}"
    else
        echo -e "${RED}INVALID PORT NUMBER.${NC}"
    fi
    echo -e "PRESS [ENTER] TO RETURN..."
    read
}

# UNINSTALL SERVICES
uninstall_services() {
    clear
    echo -e "${RED}=== UNINSTALL SERVICES ===${NC}"
    read -rp "ARE YOU SURE YOU WANT TO STOP AND REMOVE WS AND XRAY SERVICES? (Y/N): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo -e "${YELLOW}STOPPING SERVICES...${NC}"
        sudo systemctl stop ws-ssh ws-trojan xray 2>/dev/null
        sudo systemctl disable ws-ssh ws-trojan xray 2>/dev/null
        echo -e "${YELLOW}REMOVING SYSTEMD FILES...${NC}"
        sudo rm -f /etc/systemd/system/ws-ssh.service
        sudo rm -f /etc/systemd/system/ws-trojan.service
        sudo systemctl daemon-reload
        echo -e "${GREEN}✅ SERVICES HAVE BEEN UNINSTALLED AND STOPPED CLEANLY.${NC}"
    else
        echo -e "${YELLOW}UNINSTALLATION CANCELLED.${NC}"
    fi
    echo -e "PRESS [ENTER] TO RETURN..."
    read
}

# MAIN MENU LOOP 
while true; do
    clear
    echo -e "${CYAN}=================================${NC}"
    echo -e "${CYAN}  [01] ⚙️ INSTALL PROTOCOLS${NC}"
    echo -e "${CYAN}  [02] 💻 INSTALL WS FOR SSH${NC}"
    echo -e "${CYAN}  [03] 🛡️ INSTALL WS FOR TROJAN${NC}"
    echo -e "${CYAN}  [04] 📊 VIEW SERVICES STATUS${NC}"
    echo -e "${CYAN}  [05] ❌ KILL A SPECIFIC PORT${NC}"
    echo -e "${CYAN}  [06] 🗑️ UNINSTALL & REMOVE SERVICES${NC}"
    echo -e "${CYAN}  [00] 🚪 EXIT${NC}"
    echo -e "${CYAN}=================================${NC}"
    read -rp ">> CHOOSE AN OPTION: " choice

    case $choice in
        01|1) install_protocols ;;
        02|2) install_ws_ssh ;;
        03|3) install_ws_trojan ;;
        04|4)
           clear
           echo -e "${CYAN}--- WS SSH STATUS ---${NC}"
           sudo systemctl status ws-ssh --no-pager | head -n 5
           echo -e "\n${CYAN}--- WS TROJAN STATUS ---${NC}"
           sudo systemctl status ws-trojan --no-pager | head -n 5
           echo -e "\n${CYAN}--- XRAY STATUS ---${NC}"
           sudo systemctl status xray --no-pager | head -n 5
           echo -e "\nPRESS [ENTER] TO RETURN..."
           read
           ;;
        05|5) kill_port ;;
        06|6) uninstall_services ;;
        00|0) echo -e "\n${YELLOW}GOODBYE!${NC}\n"; exit 0 ;;
        *) echo -e "\n${RED}INVALID OPTION, PLEASE TRY AGAIN.${NC}"; sleep 2 ;;
    esac
done
