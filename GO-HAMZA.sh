#!/bin/bash

# ✪ X - PANEL HAMZA ✪
show_banner() {
  clear
  echo -e "\e[1;36m"
  echo "██╗  ██╗ █████╗ ███╗   ███╗███████╗ █████╗"
  echo "██║  ██║██╔══██╗████╗ ████║██╔════╝██╔══██╗"
  echo "███████║███████║██╔████╔██║█████╗  ███████║"
  echo "██╔══██║██╔══██║██║╚██╔╝██║██╔══╝  ██╔══██║"
  echo "██║  ██║██║  ██║██║ ╚═╝ ██║███████╗██║  ██║"
  echo "╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝"
  echo -e "\e[0m"
  echo -e "\e[1;33m         "
  echo -e "\e[1;37m         "
  echo
}

# Set up cron job for automatic expiration check
setup_expiration_cron() {
  # Create daily expiration check script
  cat > /usr/local/bin/check_user_expiry.sh << 'EOF'
#!/bin/bash
today=$(date +%Y-%m-%d)
while IFS='|' read -r user exp _; do
  if [[ "$exp" != "never" && "$exp" < "$today" ]]; then
    if id "$user" &>/dev/null; then
      # Lock account and prevent login
      usermod -L "$user"
      echo "User $user locked (expired: $exp)"
    fi
  fi
done < /etc/xpanel/users.txt
EOF

  chmod +x /usr/local/bin/check_user_expiry.sh
  
  # Add cron job
  (crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/check_user_expiry.sh") | crontab -
  echo "Automatic expiration check setup complete!"
}

add_user() {
  read -p "Enter SSH username: " user
  read -p "Enter password: " pass
  read -p "Validity (days): " days
  read -p "Note (client name, etc.): " note
  
  # Create user account
  useradd -s /bin/false -M "$user"
  echo -e "$pass\n$pass" | passwd "$user" &> /dev/null
  
  # Set expiration date if days provided
  if [[ "$days" -gt 0 ]]; then
    exp=$(date -d "$days days" +%Y-%m-%d)
    chage -E "$exp" "$user"
  else
    exp="never"
  fi

  # Store user information
  mkdir -p /etc/xpanel
  echo "$user|$exp|$note" >> /etc/xpanel/users.txt

  # Ensure cron job exists
  if ! crontab -l | grep -q "check_user_expiry"; then
    setup_expiration_cron
  fi

  echo -e "\nUser created successfully:"
  echo "Username : $user"
  echo "Password : $pass"
  echo "Expires  : $exp"
  echo "Note     : $note"
}

renew_user() {
  read -p "Enter username to renew: " user
  if ! id "$user" &>/dev/null; then
    echo "User not found!"
    return
  fi

  read -p "Days to extend: " days
  current_exp=$(chage -l "$user" | awk -F': ' '/Account expires/{print $2}')
  
  # Handle different expiration statuses
  if [[ "$current_exp" =~ "never" ]]; then
    new_exp=$(date -d "$days days" +%Y-%m-%d)
  elif [[ "$current_exp" =~ "Jan" ]] || [[ "$current_exp" =~ "Feb" ]] || 
       [[ "$current_exp" =~ "Mar" ]] || [[ "$current_exp" =~ "Apr" ]] || 
       [[ "$current_exp" =~ "May" ]] || [[ "$current_exp" =~ "Jun" ]] || 
       [[ "$current_exp" =~ "Jul" ]] || [[ "$current_exp" =~ "Aug" ]] || 
       [[ "$current_exp" =~ "Sep" ]] || [[ "$current_exp" =~ "Oct" ]] || 
       [[ "$current_exp" =~ "Nov" ]] || [[ "$current_exp" =~ "Dec" ]]; then
    new_exp=$(date -d "$current_exp + $days days" +%Y-%m-%d)
  else
    new_exp=$(date -d "$days days" +%Y-%m-%d)
  fi

  # Update expiration date
  usermod -e "$new_exp" "$user"
  usermod -U "$user"  # Ensure account is unlocked
  
  # Update user file
  sed -i "/^$user|/d" /etc/xpanel/users.txt
  echo "$user|$new_exp|$note" >> /etc/xpanel/users.txt
  
  echo "Renewed $user until $new_exp"
}

delete_user() {
  read -p "Enter username to delete: " user

  if [[ -z "$user" ]]; then
    echo "Username cannot be empty."
    return
  fi

  if id "$user" &>/dev/null; then
    # Lock account first to prevent access
    usermod -L "$user"
    
    # Terminate all processes
    pkill -KILL -u "$user" &>/dev/null

    # Delete user
    userdel -f "$user" && echo "Deleted '$user' from system."
  fi

  # Clean user records
  if [[ -f /etc/xpanel/users.txt ]]; then
    sed -i "/^$user|/d" /etc/xpanel/users.txt
    echo "Removed '$user' from user records."
  fi
}

list_users() {
  echo -e "\e[1;34m╔════════════════════════════════════════════════════════════╗"
  echo -e "║             SSH Accounts - Expiry and Notes Only           ║"
  echo -e "╠════════════════╦════════════════╦══════════════════════════╣"
  printf "║ %-14s ║ %-14s ║ %-24s ║\n" "Username" "Expiry" "Note"
  echo -e "╠════════════════╬════════════════╬══════════════════════════╣"
  
  [[ -f /etc/xpanel/users.txt ]] && while IFS='|' read -r user exp note; do
    # Get lock status
    locked=""
    if grep -q "^${user}:" /etc/shadow && [[ $(passwd -S "$user" | awk '{print $2}') == "L" ]]; then
      locked=" (Locked)"
    fi
    
    printf "║ %-14s ║ %-14s ║ %-24s ║\n" "$user" "${exp}${locked}" "${note}"
  done < /etc/xpanel/users.txt
  
  echo -e "╚════════════════╩════════════════╩══════════════════════════╝"
  echo -e "\e[0m"
}

show_live_ssh_users() {
  echo -e "\e[1;34m╔═════════════════════════════════╗"
  echo -e "║         SSH User Status         ║"
  echo -e "╠════════════════════╦════════════╣"
  printf "║ %-18s ║ %-10s ║\n" "Username" "Status"
  echo -e "╠════════════════════╬════════════╣"
  
  declare -A online_users
  while read -r line; do
    pid=$(echo "$line" | grep -oP '(?<=pid=)\d+')
    user=$(ps -o user= -p "$pid" 2>/dev/null)
    [[ -n "$user" ]] && online_users["$user"]=1
  done < <(ss -tnp | grep sshd | grep ESTAB)
  
  [[ -f /etc/xpanel/users.txt ]] && while IFS='|' read -r user _ _; do
    if [[ ${online_users["$user"]} ]]; then
      color="\e[1;32m" # Green
      status="ONLINE"
    else
      color="\e[1;31m" # Red
      status="OFFLINE"
    fi
    printf "║ %-18s ║ ${color}%-10s\e[0m ║\n" "$user" "$status"
  done < <(awk -F'|' '{print $1}' /etc/xpanel/users.txt)
  
  echo -e "╚════════════════════╩════════════╝"
  echo -e "\e[0m"
}

install_vpn() {
  echo "Installing VPN script..."
  wget -O /tmp/vpn.sh https://raw.githubusercontent.com/ASHANTENNA/VPNScript/refs/heads/main/InstallerScript.sh
  chmod +x /tmp/vpn.sh && bash /tmp/vpn.sh
  echo "VPN Script installed."
}

install_3x_ui() {
  echo "Installing 3X-UI panel..."
  bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
}

edit_banner() {
  nano /etc/issue.net
  if ! grep -q "^Banner /etc/issue.net" /etc/ssh/sshd_config; then
    if grep -q "^#Banner" /etc/ssh/sshd_config; then
      sed -i 's|^#Banner.*|Banner /etc/issue.net|' /etc/ssh/sshd_config
    else
      echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
    fi
  fi

  if systemctl list-units --type=service | grep -q "sshd.service"; then
    systemctl restart sshd
  elif systemctl list-units --type=service | grep -q "ssh.service"; then
    systemctl restart ssh
  else
    echo -e "\e[1;31mSSH service not found. Please restart manually.\e[0m"
  fi

  echo -e "\e[1;32mBanner updated and SSH restarted.\e[0m"
}

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
        exit 1
        ;;

    *)
        error_exit "Invalid option selected. Please rerun the script and choose a valid letter."
        ;;
esac

# Create system folders and files
mkdir -p /etc/xpanel
touch /etc/xpanel/users.txt
chmod 600 /etc/xpanel/users.txt

# Main menu
while true; do
  show_banner
  echo -e "\e[1;34m[1] Install VPN Protocols\e[0m"
  echo -e "\e[1;34m[2] Install 3X-UI Panel\e[0m"
  echo -e "\e[1;34m[3] Create SSH Account\e[0m"
  echo -e "\e[1;34m[4] Renew SSH Account\e[0m"
  echo -e "\e[1;34m[5] Delete SSH Account\e[0m"
  echo -e "\e[1;34m[6] List SSH Accounts\e[0m"
  echo -e "\e[1;34m[7] Check SSH User Status\e[0m"
  echo -e "\e[1;34m[8] Edit Server Message\e[0m"
  echo -e "\e[1;34m[9] DNSTT Manager\e[0m"
  echo -e "\e[1;34m[10] Setup Auto Expiration\e[0m"
  echo -e "\e[1;34m[0] Exit\e[0m"
  echo -e "\e[1;34m──────────────────────────────────────────────\e[0m"
  read -p $'\e[1;34mChoose an option: \e[0m' opt

  case "$opt" in
    1) install_vpn ;;
    2) install_3x_ui ;;
    3) add_user ;;
    4) renew_user ;;
    5) delete_user ;;
    6) list_users ;;
    7) show_live_ssh_users ;;
    8) edit_banner ;;
    9) dnstt_menu ;;
    10) setup_expiration_cron ;;
    0) echo "Goodbye!" && exit 0 ;;
    *) echo "Invalid option." ;;
  esac

  echo
  read -p "Press Enter to return to menu..."
done
