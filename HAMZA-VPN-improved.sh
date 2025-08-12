#!/bin/bash

# ✪ X - PANEL HAMZA - Improved Version ✪

# Check if dialog is installed, if not, install it
if ! command -v dialog &> /dev/null; then
    echo "dialog not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y dialog
fi

# Global variables for colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_banner() {
  dialog --clear --backtitle "X-PANEL HAMZA" \
  --title "HAMZA VPN SCRIPT" \
  --msgbox "
██╗  ██╗ █████╗ ███╗   ███╗███████╗ █████╗
██║  ██║██╔══██╗████╗ ████║██╔════╝██╔══██╗
███████║███████║██╔████╔██║█████╗  ███████║
██╔══██║██╔══██║██║╚██╔╝██║██╔══╝  ██╔══██║
██║  ██║██║  ██║██║ ╚═╝ ██║███████╗██║  ██║
╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝

         Welcome to HAMZA VPN Management Script
" 15 60
}

setup_expiration_cron() {
  dialog --infobox "Setting up automatic expiration check..." 4 50
  # Create daily expiration check script
  cat > /usr/local/bin/check_user_expiry.sh << EOF
#!/bin/bash
today=$(date +%Y-%m-%d)
while IFS='|' read -r user exp _;
do
  if [[ "$exp" != "never" && "$exp" < "$today" ]]; then
    if id "$user" &>/dev/null; then
      usermod -L "$user"
      echo "User $user locked (expired: $exp)"
    fi
  fi
done < /etc/xpanel/users.txt
EOF

  chmod +x /usr/local/bin/check_user_expiry.sh
  
  # Add cron job
  (crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/check_user_expiry.sh") | crontab -
  dialog --msgbox "Automatic expiration check setup complete!" 6 50
}

add_user() {
  local user pass days note exp

  user=$(dialog --inputbox "Enter SSH username:" 8 40 2>&1 >/dev/tty)
  if [[ -z "$user" ]]; then dialog --msgbox "Username cannot be empty!" 5 40; return; fi

  pass=$(dialog --passwordbox "Enter password:" 8 40 2>&1 >/dev/tty)
  if [[ -z "$pass" ]]; then dialog --msgbox "Password cannot be empty!" 5 40; return; fi

  days=$(dialog --inputbox "Validity (days, 0 for never):" 8 40 2>&1 >/dev/tty)
  if ! [[ "$days" =~ ^[0-9]+$ ]]; then dialog --msgbox "Invalid days! Must be a number." 5 40; return; fi

  note=$(dialog --inputbox "Note (client name, etc.):" 8 40 2>&1 >/dev/tty)

  # Create user account
  if id "$user" &>/dev/null; then
    dialog --msgbox "User '$user' already exists!" 5 40
    return
  fi
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

  dialog --msgbox "
User created successfully:
Username : $user
Password : $pass
Expires  : $exp
Note     : $note
" 10 50
}

renew_user() {
  local user days current_exp new_exp

  user=$(dialog --inputbox "Enter username to renew:" 8 40 2>&1 >/dev/tty)
  if [[ -z "$user" ]]; then dialog --msgbox "Username cannot be empty!" 5 40; return; fi

  if ! id "$user" &>/dev/null; then
    dialog --msgbox "User '$user' not found!" 5 40
    return
  fi

  days=$(dialog --inputbox "Days to extend:" 8 40 2>&1 >/dev/tty)
  if ! [[ "$days" =~ ^[0-9]+$ ]]; then dialog --msgbox "Invalid days! Must be a number." 5 40; return; fi

  current_exp=$(chage -l "$user" | awk -F': ' '/Account expires/{print $2}')
  
  if [[ "$current_exp" =~ "never" ]]; then
    new_exp=$(date -d "$days days" +%Y-%m-%d)
  else
    # Convert current_exp to YYYY-MM-DD format for consistent date arithmetic
    current_exp_formatted=$(date -d "$current_exp" +%Y-%m-%d 2>/dev/null)
    if [[ $? -ne 0 ]]; then
      dialog --msgbox "Could not parse current expiration date for $user. Please check manually." 7 60
      return
    fi
    new_exp=$(date -d "$current_exp_formatted + $days days" +%Y-%m-%d)
  fi

  usermod -e "$new_exp" "$user"
  usermod -U "$user"  # Ensure account is unlocked
  
  # Update user file
  local note=$(grep "^$user|" /etc/xpanel/users.txt | cut -d'|' -f3)
  sed -i "/^$user|/d" /etc/xpanel/users.txt
  echo "$user|$new_exp|$note" >> /etc/xpanel/users.txt
  
  dialog --msgbox "Renewed $user until $new_exp" 6 50
}

delete_user() {
  local user
  user=$(dialog --inputbox "Enter username to delete:" 8 40 2>&1 >/dev/tty)
  if [[ -z "$user" ]]; then dialog --msgbox "Username cannot be empty!" 5 40; return; fi

  if ! id "$user" &>/dev/null; then
    dialog --msgbox "User '$user' not found!" 5 40
    return
  fi

  if (dialog --title "Confirm Deletion" --yesno "Are you sure you want to delete user '$user'?" 7 60); then
    usermod -L "$user"
    pkill -KILL -u "$user" &>/dev/null
    userdel -f "$user" && dialog --msgbox "Deleted '$user' from system." 5 40

    if [[ -f /etc/xpanel/users.txt ]]; then
      sed -i "/^$user|/d" /etc/xpanel/users.txt
      dialog --msgbox "Removed '$user' from user records." 5 40
    fi
  else
    dialog --msgbox "User deletion cancelled." 5 40
  fi
}

list_users() {
  local user_data=""
  if [[ -f /etc/xpanel/users.txt ]]; then
    while IFS='|' read -r user exp note; do
      local locked=""
      if grep -q "^${user}:" /etc/shadow && [[ $(passwd -S "$user" | awk '{print $2}') == "L" ]]; then
        locked=" (Locked)"
      fi
      user_data+="$user\t${exp}${locked}\t$note\n"
    done < /etc/xpanel/users.txt
  fi

  if [[ -z "$user_data" ]]; then
    dialog --msgbox "No SSH accounts found." 5 40
  else
    dialog --title "SSH Accounts" --msgbox "Username\tExpiry\tNote\n--------------------------------------------------\n$user_data" 20 70
  fi
}

show_live_ssh_users() {
  local user_status=""
  declare -A user_connections

  # Get all active SSH connections and count them per user
  # Using 'who' for simplicity, 'ss' can be more robust but complex to parse for user
  while read -r line; do
    user=$(echo "$line" | awk '{print $1}')
    if [[ -n "$user" ]]; then
      user_connections["$user"]=$((user_connections["$user"] + 1))
    fi
  done < <(who | grep "pts/") 
  
  if [[ -f /etc/xpanel/users.txt ]]; then
    while IFS='|' read -r user _ _ ; do
      local connections=${user_connections["$user"]:-0}
      if [[ $connections -gt 0 ]]; then
        user_status+="$user\t${GREEN}ONLINE ($connections)${NC}\n"
      else
        user_status+="$user\t${RED}OFFLINE${NC}\n"
      fi
    done < <(awk -F'|' '{print $1}' /etc/xpanel/users.txt)
  fi

  if [[ -z "$user_status" ]]; then
    dialog --msgbox "No SSH users to display status for." 5 50
  else
    dialog --title "SSH User Status" --msgbox "Username\tStatus (Connections)\n----------------------------------\n$user_status" 20 50
  fi
}

install_vpn() {
  dialog --infobox "Installing VPN script..." 4 50
  wget -O /tmp/vpn.sh https://raw.githubusercontent.com/ASHANTENNA/VPNScript/refs/heads/main/InstallerScript.sh
  chmod +x /tmp/vpn.sh && bash /tmp/vpn.sh
  dialog --msgbox "VPN Script installation finished." 6 50
}

install_3x_ui() {
  dialog --infobox "Installing 3X-UI panel..." 4 50
  bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
  dialog --msgbox "3X-UI Panel installation finished." 6 50
}

edit_banner() {
  dialog --infobox "Opening nano for /etc/issue.net..." 4 50
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
    dialog --msgbox "Banner updated and sshd restarted." 6 50
  elif systemctl list-units --type=service | grep -q "ssh.service"; then
    systemctl restart ssh
    dialog --msgbox "Banner updated and ssh restarted." 6 50
  else
    dialog --msgbox "SSH service not found. Please restart manually." 6 50
  fi
}

install_dns() {
  dialog --infobox "Installing HAMZA DNS script..." 4 50
  curl -s -o /tmp/dns.sh https://raw.githubusercontent.com/hamzascript/X-SCRIPT/main/hamza-dns.sh
  chmod +x /tmp/dns.sh && bash /tmp/dns.sh
  dialog --msgbox "DNS Script installation finished." 6 50
}

# Create system folders and files
mkdir -p /etc/xpanel
touch /etc/xpanel/users.txt
chmod 600 /etc/xpanel/users.txt

# Main menu
while true; do
  exec 3>&1
  selection=$(dialog --clear --backtitle "X-PANEL HAMZA" \
    --title "MAIN MENU" \
    --menu "Choose an option:" 15 60 10 \
    "1" "Install VPN Protocols" \
    "2" "Install 3X-UI Panel" \
    "3" "Create SSH Account" \
    "4" "Renew SSH Account" \
    "5" "Delete SSH Account" \
    "6" "List SSH Accounts" \
    "7" "Check SSH User Status" \
    "8" "Edit Server Message" \
    "9" "DNSTT Manager" \
    "10" "Setup Auto Expiration" \
    "0" "Exit" 2>&1 1>&3)
  exit_status=$?
  exec 3>&-

  if [[ $exit_status -ne 0 ]]; then # User pressed Cancel or Esc
    dialog --msgbox "Goodbye!" 5 40
    break
  fi

  case $selection in
    1) install_vpn ;;
    2) install_3x_ui ;;
    3) add_user ;;
    4) renew_user ;;
    5) delete_user ;;
    6) list_users ;;
    7) show_live_ssh_users ;;
    8) edit_banner ;;
    9) install_dns ;;
    10) setup_expiration_cron ;;
    0) dialog --msgbox "Goodbye!" 5 40 && break ;;
    *) dialog --msgbox "Invalid option." 5 40 ;;
  esac
done


