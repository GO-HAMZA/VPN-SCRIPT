#!/bin/bash

# Colors for output
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BLUE='\033[1;34m'
NC='\033[0m'

# Function to print boxed header
print_box() {
    local msg="$1"
    local width=50
    local len=${#msg}
    local padding=$(( (width - len - 2) / 2 ))
    local pad_str=$(printf '%*s' "$padding" | tr ' ' ' ')
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${CYAN}|${pad_str}${msg}${pad_str}${NC}"
    echo -e "${CYAN}==================================================${NC}"
    echo
}

error_exit() {
    echo -e "${YELLOW}ERROR: $1${NC}" >&2
    exit 1
}

success() {
    echo -e "${CYAN}SUCCESS: $1${NC}"
}

if [ "$EUID" -ne 0 ]; then
    error_exit "THIS SCRIPT MUST BE RUN AS ROOT. USE SUDO."
fi

# Main menu
print_box "DNSTT SETUP MENU"
echo -e "${BLUE}A - INSTALL DNSTT${NC}"
echo -e "${BLUE}B - STOP SERVICES${NC}"
echo -e "${BLUE}C - ACTIVE SERVICES${NC}"
echo -e "${BLUE}D - PREVIOUS INSTALLATION INFO${NC}"
echo -e "${BLUE}E - EXIT${NC}"
echo
read -p "CHOOSE AN OPTION (A-E): " choice
choice=$(echo "$choice" | tr '[:lower:]' '[:upper:]')
echo

case $choice in
    A)
        # Clean up previous DNSTT configurations
        print_box "CLEANING UP PREVIOUS CONFIGURATIONS"
        pkill -f dnstt-server 2>/dev/null
        systemctl stop dnstt.service 2>/dev/null
        systemctl disable dnstt.service 2>/dev/null
        rm -f /etc/systemd/system/dnstt.service
        systemctl daemon-reload 2>/dev/null
        screen -ls | grep dnstt | awk '{print $1}' | xargs -I {} screen -X -S {} quit 2>/dev/null
        rm -rf /root/dnstt
        iptables -F
        iptables -t nat -F
        iptables-save > /etc/iptables/rules.v4 2>/dev/null
        success "PREVIOUS CONFIGURATIONS CLEARED."

        print_box "INSTALLING DNSTT FOR TUNNELING"

        if ! systemctl is-active --quiet sshd; then
            error_exit "SSH SERVER (SSHD) IS NOT RUNNING. START IT WITH 'systemctl start sshd'."
        fi

        echo -e "${YELLOW}UPDATING AND INSTALLING PACKAGES...${NC}"
        apt -y update && apt -y upgrade || error_exit "FAILED TO UPDATE/UPGRADE PACKAGES."
        apt -y install iptables-persistent wget screen lsof || error_exit "FAILED TO INSTALL REQUIRED PACKAGES."
        success "PACKAGES INSTALLED SUCCESSFULLY."

        mkdir /root/dnstt || error_exit "FAILED TO CREATE /root/dnstt DIRECTORY."
        cd /root/dnstt || error_exit "FAILED TO CHANGE TO /root/dnstt DIRECTORY."

        echo -e "${YELLOW}DOWNLOADING DNSTT SERVER FILES...${NC}"
        wget https://raw.githubusercontent.com/hamzascript/DNS-X/main/dnstt-server || error_exit "FAILED TO DOWNLOAD dnstt-server."
        chmod 755 dnstt-server
        wget https://raw.githubusercontent.com/hamzascript/DNS-X/main/server.key || error_exit "FAILED TO DOWNLOAD server.key."
        wget https://raw.githubusercontent.com/hamzascript/DNS-X/main/server.pub || error_exit "FAILED TO DOWNLOAD server.pub."
        success "FILES DOWNLOADED SUCCESSFULLY."

        print_box "PUBLIC KEY (server.pub)"
        echo -e "${CYAN}"
        cat server.pub || error_exit "FAILED TO READ server.pub."
        echo -e "${NC}"
        read -p "COPY THE PUBKEY ABOVE AND PRESS ENTER WHEN DONE: "

        print_box "ENTER NAMESERVER"
        echo -e "${YELLOW}"
        read -p "ENTER YOUR NAMESERVER: " ns
        echo -e "${NC}"
        if [ -z "$ns" ]; then
            error_exit "NAMESERVER CANNOT BE EMPTY."
        fi

        print_box "SELECT CONNECTION MODE"
        echo -e "${YELLOW}1 - SSH SOCKS${NC}"
        echo -e "${YELLOW}2 - SSH MOD${NC}"
        echo -e "${YELLOW}3 - 3X-UI MOD${NC}"
        read -p "ENTER YOUR CHOICE (1-3): " mode
        case $mode in
            1)
                TARGET="127.0.0.1:1080"
                PORT=1080
                MODE_NAME="SSH SOCKS"
                ;;
            2)
                TARGET="127.0.0.1:22"
                PORT=22
                MODE_NAME="SSH MOD"
                ;;
            3)
                TARGET="127.0.0.1:2500"
                PORT=2500
                MODE_NAME="X-UI MOD"
                ;;
            *)
                error_exit "INVALID MODE SELECTED."
                ;;
        esac
        echo -e "${YELLOW}SELECTED MODE: $MODE_NAME${NC}"

        print_box "CONFIGURING FIREWALL"
        iptables -I INPUT -p udp --dport 5300 -j ACCEPT || error_exit "FAILED TO SET IPTABLES INPUT RULE."
        iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 || error_exit "FAILED TO SET IPTABLES NAT RULE."
        iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT || error_exit "FAILED TO ALLOW TCP PORT $PORT."
        iptables-save > /etc/iptables/rules.v4 || error_exit "FAILED TO SAVE IPTABLES RULES."
        success "FIREWALL CONFIGURED SUCCESSFULLY."

        print_box "SELECT BACKGROUND MODE"
        echo -e "${YELLOW}1 - SYSTEMD${NC}"
        echo -e "${YELLOW}2 - NOHUP${NC}"
        echo -e "${YELLOW}3 - SCREEN${NC}"
        read -p "ENTER YOUR CHOICE (1-3): " bind
        echo -e "${NC}"
        case $bind in
            1)
                cat <<EOF > /etc/systemd/system/dnstt.service
[Unit]
Description=Daemonize DNSTT Tunnel Server ($MODE_NAME)
Wants=network.target
After=network.target
[Service]
ExecStart=/root/dnstt/dnstt-server -udp :5300 -privkey-file /root/dnstt/server.key $ns $TARGET
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
                systemctl daemon-reload || error_exit "FAILED TO RELOAD SYSTEMD DAEMON."
                systemctl start dnstt || error_exit "FAILED TO START dnstt SERVICE."
                systemctl enable dnstt || error_exit "FAILED TO ENABLE dnstt SERVICE."
                success "DNSTT SERVICE STARTED WITH SYSTEMD."
                ;;
            2)
                nohup ./dnstt-server -udp :5300 -privkey-file server.key "$ns" "$TARGET" > dnstt.log 2>&1 &
                sleep 2
                ps -p $! > /dev/null || error_exit "FAILED TO START dnstt-server WITH NOHUP."
                success "DNSTT STARTED WITH NOHUP."
                ;;
            3)
                screen -dmS dnstt ./dnstt-server -udp :5300 -privkey-file server.key "$ns" "$TARGET" || error_exit "FAILED TO START dnstt-server IN SCREEN."
                success "DNSTT STARTED WITH SCREEN."
                ;;
            *)
                error_exit "INVALID BACKGROUND MODE SELECTED."
                ;;
        esac

        print_box "CHECKING PORT 5300"
        lsof -i :5300 || echo -e "${YELLOW}WARNING: PORT 5300 IS NOT IN USE. CHECK IF dnstt-server IS RUNNING.${NC}"

        print_box "INSTALLATION COMPLETE"
        echo -e "${YELLOW}NAMESERVER: $ns${NC}"
        echo -e "${YELLOW}MODE: $MODE_NAME${NC}"
        echo -e "${YELLOW}PUBLIC KEY SAVED AT: /root/dnstt/server.pub${NC}"
        exit 0
        ;;

    B)
        print_box "Stopping DNSTT Services"
        pkill -f dnstt-server 2>/dev/null
        systemctl stop dnstt.service 2>/dev/null
        systemctl disable dnstt.service 2>/dev/null
        rm -f /etc/systemd/system/dnstt.service
        systemctl daemon-reload 2>/dev/null
        screen -ls | grep dnstt | awk '{print $1}' | xargs -I {} screen -X -S {} quit 2>/dev/null
        echo -e "${CYAN}All DNSTT services stopped.${NC}"
        exit 0
        ;;

    C)
        print_box "Active DNSTT Services"
        pgrep -a dnstt-server && echo -e "${CYAN}dnstt-server is running.${NC}" || echo -e "${YELLOW}dnstt-server is not active.${NC}"
        systemctl status dnstt.service --no-pager | grep -E "Active|Loaded"
        screen -ls | grep dnstt && echo -e "${CYAN}Screen session for dnstt exists.${NC}" || echo -e "${YELLOW}No screen session for dnstt.${NC}"
        exit 0
        ;;

    D)
        print_box "Previous Installation Info"
        if [ -f /root/dnstt/server.pub ]; then
            echo -e "${CYAN}Reading saved configuration...${NC}"
            echo
            if [ -f /etc/systemd/system/dnstt.service ]; then
                config_line=$(grep ExecStart /etc/systemd/system/dnstt.service)
            elif [ -f /root/dnstt/dnstt.log ]; then
                config_line=$(grep dnstt-server /root/dnstt/dnstt.log | head -n1)
            else
                config_line=""
            fi
            ns=$(echo "$config_line" | awk '{print $(NF-1)}')
            target=$(echo "$config_line" | awk '{print $NF}')
            port=$(echo "$target" | cut -d ':' -f2)
            mode_name="UNKNOWN"
            if [[ "$port" == "22" ]]; then
            mode_name="SSH MOD"
            elif [[ "$port" == "1080" ]]; then
            mode_name="SSH SOCKS"
            elif [[ "$port" == "2500" ]]; then
            mode_name="X-UI MOD"
            fi
            echo -e "${YELLOW}Nameserver (Domain):${NC}\n\n $ns\n"
            echo -e "${YELLOW}Connection Mode:${NC} $mode_name"
            echo -e "${YELLOW}Target Port:${NC} $port\n"
            echo -e "${YELLOW}Public Key:${NC}"
            cat /root/dnstt/server.pub
            echo
        else
            echo -e "${YELLOW}No previous installation found.${NC}"
        fi
        exit 0
        ;;

    E)
        echo -e "${CYAN}Exiting...${NC}"
        exit 0
        ;;

    *)
        error_exit "Invalid option selected. Please rerun the script and choose a valid letter."
        ;;
esac

