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

install_dns() {
  echo "Installing HAMZA DNS script..."
  curl -O /tmp/dns.sh https://raw.githubusercontent.com/hamzascript/X-SCRIPT/main/hamza-dns.sh
  chmod +x /tmp/dns.sh && bash /tmp/dns.sh
  echo "DNS Script installed."
}

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
    9) install_dns ;;
    10) setup_expiration_cron ;;
    0) echo "Goodbye!" && exit 0 ;;
    *) echo "Invalid option." ;;
  esac

  echo
  read -p "Press Enter to return to menu..."
done
