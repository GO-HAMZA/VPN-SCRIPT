#!/bin/bash

is_number() {
    [[ $1 =~ ^[0-9]+$ ]]
}

YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
NC='\033[0m'

if [ "$(whoami)" != "root" ]; then
    echo -e "${RED}Error: This script must be run as root.${NC}"
    exit 1
fi

MARKER="### CUSTOM COLOR BLOCK ###"
TEXT_TO_ADD='
'"$MARKER"'
YELLOW='\''\033[1;33m'\''
RED='\''\033[1;31m'\''
CYAN='\''\033[1;36m'\''
GREEN='\''\033[1;32m'\''
NC='\''\033[0m'\''
'"$MARKER"'
'

if ! grep -Fq "$MARKER" ~/.bashrc; then
    echo "$TEXT_TO_ADD" >> ~/.bashrc
fi

cd /root

# ==========================================
# الواجهة الجديدة (MAIN MENU)
# ==========================================
show_menu() {
    clear
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "             ${GREEN}⚡ VPN TUNNEL INSTALLER V 2.0 ⚡${NC}"
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "  ${YELLOW}[01]${NC} 🚀 INSTALL UDP HYSTERIA"
    echo -e "  ${YELLOW}[02]${NC} 🌐 INSTALL SSH WSS"
    echo -e "  ${YELLOW}[03]${NC} 🔌 INSTALL SSH HTTP - WS"
    echo -e "  ${YELLOW}[04]${NC} 📡 INSTALL DNSTT DoH & DoT"
    echo -e "  ${YELLOW}[05]${NC} ⚙️ INSTALL VPS AGN"
    echo -e "  ${YELLOW}[06]${NC} 🔗 INSTALL DNS2TCP"
    echo -e "  ${YELLOW}[07]${NC} 🕹️ INSTALL BADVPN UDPGW - 7300"
    echo -e "  ${YELLOW}[08]${NC} 🔒 INSTALL SSH SSL"
    echo -e "  ${YELLOW}[09]${NC} 🔑 INSTALL SSH GO"
    echo -e "  ${YELLOW}[00]${NC} 🚪 EXIT"
    echo -e "${CYAN}=========================================================${NC}"
    echo -ne "${GREEN}SELECT: ${NC}"
}

while true; do
    show_menu
    read -r input

    case $input in
        1|01)
            clear
            echo -e "${YELLOW}Installing UDP Hysteria V1.3.5 ...${NC}"
            apt -y update && apt -y upgrade
            apt -y install wget nano net-tools openssl iptables-persistent screen lsof
            rm -rf hy
            mkdir hy
            cd hy
            wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/ashhysteria-linux-amd64
            chmod 755 ashhysteria-linux-amd64
            openssl ecparam -genkey -name prime256v1 -out ca.key
            openssl req -new -x509 -days 36500 -key ca.key -out ca.crt -subj "/CN=bing.com"
            while true; do
                echo -e "${YELLOW}Obfs : ${NC}\c"
                read obfs
                if [ ! -z "$obfs" ]; then break; fi
            done
            while true; do
                echo -e "${YELLOW}Auth Str : ${NC}\c"
                read auth_str
                if [ ! -z "$auth_str" ]; then break; fi
            done
            while true; do
                echo -e "${YELLOW}Remote UDP Port : ${NC}\c"
                read remote_udp_port
                if is_number "$remote_udp_port" && [ "$remote_udp_port" -ge 1 ] && [ "$remote_udp_port" -le 65534 ]; then
                    break
                else
                    echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65534.${NC}"
                fi
            done
            file_path="/root/hy/config.json"
            json_content='{"listen":":'"$remote_udp_port"'","protocol":"udp","cert":"/root/hy/ca.crt","key":"/root/hy/ca.key","up":"100 Mbps","up_mbps":100,"down":"100 Mbps","down_mbps":100,"disable_udp":false,"obfs":"'"$obfs"'","auth_str":"'"$auth_str"'"}'
            echo "$json_content" > "$file_path"
            if [ ! -e "$file_path" ]; then
                echo -e "${RED}Error: Unable to save the config.json file${NC}"
                exit 1
            fi
            sudo debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v4 boolean true"
            sudo debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v6 boolean true"

            echo -e "${YELLOW}Bind multiple UDP Ports? (y/n): ${NC}\c"
            read bind
            if [ "$bind" = "y" ]; then
                while true; do
                    echo -e "${YELLOW}Binding UDP Ports : from port : ${NC}\c"
                    read first_number
                    if is_number "$first_number" && [ "$first_number" -ge 1 ] && [ "$first_number" -le 65534 ]; then
                      break
                    else
                        echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65534.${NC}"
                    fi
                done
                while true; do
                    echo -e "${YELLOW}Binding UDP Ports : from port : $first_number to port : ${NC}\c"
                    read second_number
                    if is_number "$second_number" && [ "$second_number" -gt "$first_number" ] && [ "$second_number" -lt 65536 ]; then
                        break
                    else
                        echo -e "${RED}Invalid input. Please enter a valid number greater than $first_number and less than 65536.${NC}"
                    fi
                done
                #Remove old rules
                iptables -t nat -L --line-numbers | awk -v var="$first_number:$second_number" '$0 ~ var {print $1}' | tac | xargs -r -I {} iptables -t nat -D PREROUTING {}
                ip6tables -t nat -L --line-numbers | awk -v var="$first_number:$second_number" '$0 ~ var {print $1}' | tac | xargs -r -I {} ip6tables -t nat -D PREROUTING {}
            
                iptables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport "$first_number":"$second_number" -j DNAT --to-destination :$remote_udp_port
                ip6tables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport "$first_number":"$second_number" -j DNAT --to-destination :$remote_udp_port
            fi
            sysctl net.ipv4.conf.all.rp_filter=0
            sysctl net.ipv4.conf.$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1).rp_filter=0 
            echo "net.ipv4.ip_forward = 1
            net.ipv4.conf.all.rp_filter=0
            net.ipv4.conf.$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1).rp_filter=0" > /etc/sysctl.conf
            sysctl -p
            iptables-save > /etc/iptables/rules.v4
            ip6tables-save > /etc/iptables/rules.v6
            echo -e "${YELLOW}Run in background or foreground service ? (b/f): ${NC}\c"
            read bind
            if [ "$bind" = "b" ]; then
                screen -dmS hy ./ashhysteria-linux-amd64 server --log-level 0
            else
                json_content=$(cat <<-EOF
[Unit]
Description=Daemonize UDP Hysteria V1 Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/hy/ashhysteria-linux-amd64 server -c /root/hy/config.json --log-level 0
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
)
                echo "$json_content" > /etc/systemd/system/hy.service
                systemctl start hy
                systemctl enable hy
            fi
            lsof -i :"$remote_udp_port"
            echo -e "\n${GREEN}UDP Hysteria V1.3.5 installed successfully, please check the logs above${NC}"
            echo -e "IP Address : \c"; curl -s ipv4.icanhazip.com
            echo "Obfs : '$obfs'"
            echo "Auth str : '$auth_str'"
            exit 0
            ;;
        2|02)
            clear
            echo -e "${YELLOW}Installing ASH WSS...${NC}"
            apt -y update && apt -y upgrade
            apt -y install openssl lsof screen
            while true; do
                echo -e "${YELLOW}Remote WSS Port : ${NC}\c"
                read wss_port
                if is_number "$wss_port" && [ "$wss_port" -ge 1 ] && [ "$wss_port" -le 65535 ]; then
                    break
                else
                    echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
                fi
            done
            while true; do
                echo -e "${YELLOW}Target TCP Port : ${NC}\c"
                read target_port
                if is_number "$target_port" && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
                    break
                else
                    echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
                fi
            done
            rm -rf ashwss
            mkdir ashwss
            cd ashwss
            wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/ashwebsocketsni-linux-amd64
            chmod 755 ashwebsocketsni-linux-amd64
            openssl genrsa -out stunnel.key 2048
            openssl req -new -key stunnel.key -x509 -days 1000 -out stunnel.crt
            cat stunnel.crt stunnel.key > stunnel.pem
            rm -rf stunnel.crt
            echo -e "${YELLOW}Run in background or foreground service ? (b/f): ${NC}\c"
            read bind
            if [ "$bind" = "b" ]; then
                screen -dmS ashwss ./ashwebsocketsni-linux-amd64 -listen :$wss_port -forward 127.0.0.1:$target_port -private_key stunnel.pem -public_key stunnel.key
            else
                json_content=$(cat <<-EOF
[Unit]
Description=Daemonize ASH WSS Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/ashwss/ashwebsocketsni-linux-amd64 -listen :$wss_port -forward 127.0.0.1:$target_port -private_key /root/ashwss/stunnel.pem -public_key /root/ashwss/stunnel.key
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
)
                echo "$json_content" > /etc/systemd/system/ashwss.service
                systemctl start ashwss
                systemctl enable ashwss
            fi
            lsof -i :"$wss_port"
            echo -e "\n${GREEN}ASH WSS Installed Successfully${NC}"
            exit 0
            ;;
        3|03)
            clear
            echo -e "${YELLOW}Installing ASH HTTP + WS...${NC}"
            apt -y update && apt -y upgrade
            apt -y install iptables-persistent wget screen lsof
            while true; do
                echo -e "${YELLOW}Remote HTTP Port : ${NC}\c"
                read http_port
                if is_number "$http_port" && [ "$http_port" -ge 1 ] && [ "$http_port" -le 65535 ]; then
                    break
                else
                    echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
                fi
            done
            while true; do
                echo -e "${YELLOW}Target HTTP Port : ${NC}\c"
                read target_port
                if is_number "$target_port" && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
                    break
                else
                    echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
                fi
            done
            echo -e "${YELLOW}Bind multiple TCP Ports? (y/n): ${NC}\c"
            read bind
            if [ "$bind" = "y" ]; then
                while true; do
                echo -e "${YELLOW}Binding TCP Ports : from port : ${NC}\c"
                read first_number
                    if is_number "$first_number" && [ "$first_number" -ge 1 ] && [ "$first_number" -le 65534 ]; then
                        break
                    else
                        echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65534.${NC}"
                    fi
                done
                while true; do
                    echo -e "${YELLOW}Binding TCP Ports : from port : $first_number to port : ${NC}\c"
                    read second_number
                    if is_number "$second_number" && [ "$second_number" -gt "$first_number" ] && [ "$second_number" -lt 65536 ]; then
                        break
                    else
                        echo -e "${RED}Invalid input. Please enter a valid number greater than $first_number and less than 65536.${NC}"
                    fi
                done
                iptables -t nat -A PREROUTING -p tcp --dport "$first_number":"$second_number" -j REDIRECT --to-port "$http_port"
                iptables-save > /etc/iptables/rules.v4
            fi
            rm -rf ashhttp
            mkdir ashhttp
            cd ashhttp
            http_script="/root/ashhttp/ashhttpproxy-linux-amd64"
            wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/ashhttpproxy-linux-amd64
            chmod 755 ashhttpproxy-linux-amd64

            echo -e "${YELLOW}Run in background or foreground service ? (b/f): ${NC}\c"
            read bind
            if [ "$bind" = "b" ]; then
                screen -dmS ashhttp ./ashhttpproxy-linux-amd64 -listen :$http_port -forward 127.0.0.1:$target_port
            else
                json_content=$(cat <<-EOF
[Unit]
Description=Daemonize ASH HTTP Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/ashhttp/ashhttpproxy-linux-amd64 -listen :$http_port -forward 127.0.0.1:$target_port
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
)
                echo "$json_content" > /etc/systemd/system/ashhttp.service
                systemctl start ashhttp
                systemctl enable ashhttp
            fi

            lsof -i :"$http_port"
            echo -e "\n${GREEN}ASH HTTP + WS installed successfully${NC}"
            exit 0
            ;;
        4|04)
            clear
            echo -e "${YELLOW}Installing DNSTT, DoH and DoT ...${NC}"
            apt -y update && apt -y upgrade
            apt -y install iptables-persistent wget screen lsof
            rm -rf dnstt
            mkdir dnstt
            cd dnstt
            wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/dnstt-server
            chmod 755 dnstt-server
            wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/server.key
            wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/server.pub
            echo -e "${CYAN}=========================${NC}"
            cat server.pub
            echo -e "${CYAN}=========================${NC}"
            echo -e "${YELLOW}Copy the pubkey above and press Enter when done${NC}"
            read
            echo -e "${YELLOW}Enter your Nameserver : ${NC}\c"
            read ns
            iptables -I INPUT -p udp --dport 5300 -j ACCEPT
            iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
            iptables-save > /etc/iptables/rules.v4

            while true; do
                echo -e "${YELLOW}Target TCP Port : ${NC}\c"
                read target_port
                if is_number "$target_port" && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
                    break
                else
                    echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
                fi
            done

            echo -e "${YELLOW}Run in background or foreground service ? (b/f): ${NC}\c"
            read bind
            if [ "$bind" = "b" ]; then
                screen -dmS slowdns ./dnstt-server -udp :5300 -privkey-file server.key $ns 127.0.0.1:$target_port
            else
                json_content=$(cat <<-EOF
[Unit]
Description=Daemonize DNSTT Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/dnstt/dnstt-server -udp :5300 -privkey-file /root/dnstt/server.key $ns 127.0.0.1:$target_port
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
)
                echo "$json_content" > /etc/systemd/system/dnstt.service
                systemctl start dnstt
                systemctl enable dnstt
            fi

            lsof -i :5300
            echo -e "\n${GREEN}DNSTT installation completed${NC}"
            exit 0
            ;;
        5|05)
            clear
            echo -e "${RED}No longer available${NC}"
            sleep 2
            # Uncomment if you want the AGN script to run:
            # rm -rf install-without-key.sh; apt update; apt install curl bc; wget https://github.com/khaledagn/VPS-AGN_English_Official/raw/main/installer/install-without-key.sh; chmod 777 install-without-key.sh; ./install-without-key.sh --start
            # exit 0
            ;;
        6|06)
            clear
            echo -e "${CYAN}Before you continue, make sure that :${NC}"
            echo -e "${YELLOW}- No program uses UDP Port 53${NC}"
            echo -e "${YELLOW}- DNSTT is not running${NC}"
            echo -e "${YELLOW}- iptables doesn't forward the port 53 to another port${NC}"
            echo -e "${CYAN}Press Enter to continue...${NC}"
            read
            apt -y update && apt -y upgrade
            apt -y install screen lsof dns2tcp nano
            echo -e "${YELLOW}In this step, you will uncomment DNS and write DNS=1.1.1.1 and uncomment DNSStubListener and write DNSStubListener=no${NC}"
            echo -e "${CYAN}Press Enter to open nano...${NC}"
            read
            nano /etc/systemd/resolved.conf
            echo -e "${YELLOW}By tapping 'Enter', you make sure that you have uncommented DNS=1.1.1.1 and DNSStubListener=no${NC}"
            read
            systemctl restart systemd-resolved
            mkdir -p dns2tcp
            cd dns2tcp
            mkdir -p /var/empty
            mkdir -p /var/empty/dns2tcp
            echo -e "${YELLOW}Your Nameserver: ${NC}\c"; read nameserver
            echo -e "${YELLOW}Your key: ${NC}\c"; read key
            
            while true; do
                echo -e "${YELLOW}Target TCP Port : ${NC}\c"
                read target_port
                if is_number "$target_port" && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
                    break
                else
                    echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
                fi
            done
            file_path="/root/dns2tcp/dns2tcpdrc"
            json_content=$(cat <<EOF
listen = 0.0.0.0
port = 53
user = ashtunnel
chroot = /var/empty/dns2tcp/
domain = $nameserver
key = $key
resources = ssh:127.0.0.1:$target_port
EOF
)
            echo "$json_content" > "$file_path"

            echo -e "${YELLOW}Run in background or foreground service ? (b/f): ${NC}\c"
            read bind
            if [ "$bind" = "b" ]; then
                dns2tcpd -d 1 -f dns2tcpdrc &
            else
                json_content=$(cat <<-EOF
[Unit]
Description=Daemonize DNS2TCP Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/usr/bin/dns2tcpd -d 1 -F -f /root/dns2tcp/dns2tcpdrc
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
)
                echo "$json_content" > /etc/systemd/system/dns2tcp.service
                systemctl start dns2tcp
                systemctl enable dns2tcp
            fi
            echo -e "${YELLOW}In the next step, add nameserver 1.1.1.1 to the coming file if there is only nameserver 127.0.0.1 or nameserver 127.0.0.53${NC}"
            echo -e "${CYAN}Press Enter to open nano...${NC}"
            read
            nano /etc/resolv.conf
            echo -e "${YELLOW}By tapping 'Enter', you make sure that you have added nameserver 1.1.1.1${NC}"
            read
            lsof -i :53
            echo -e "\n${GREEN}DNS2TCP server installed sucessfully${NC}"
            exit 0
            ;;
        7|07)
            clear
            echo -e "${YELLOW}Installing BadVPN UDPGW...${NC}"
            apt -y update && apt -y upgrade
            apt -y install wget lsof
            rm -rf badvpn
            mkdir badvpn
            cd badvpn
            wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/badvpn-udpgw
            chmod 755 badvpn-udpgw
            json_content=$(cat <<-EOF
[Unit]
Description=Daemonize BadVPN UDPGW Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/badvpn/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10 --loglevel 0
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
)
            echo "$json_content" > /etc/systemd/system/badvpn.service
            systemctl start badvpn
            systemctl enable badvpn
            lsof -i :7300
            echo -e "\n${GREEN}BadVPN UDPGW Installed Successfully${NC}"
            exit 0
            ;;
        8|08)
            clear
            echo -e "${YELLOW}Installing ASH SSL...${NC}"
            apt -y update && apt -y upgrade
            apt -y install openssl lsof screen
            while true; do
                echo -e "${YELLOW}Remote SSL Port : ${NC}\c"
                read ssl_port
                if is_number "$ssl_port" && [ "$ssl_port" -ge 1 ] && [ "$ssl_port" -le 65535 ]; then
                    break
                else
                    echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
                fi
            done
            while true; do
                echo -e "${YELLOW}Target TCP Port : ${NC}\c"
                read target_port
                if is_number "$target_port" && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
                    break
                else
                    echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
                fi
            done
            rm -rf ashssl
            mkdir ashssl
            cd ashssl
            wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/ashsslproxy-linux-amd64
            chmod 755 ashsslproxy-linux-amd64
            openssl genrsa -out stunnel.key 2048
            openssl req -new -key stunnel.key -x509 -days 1000 -out stunnel.crt
            cat stunnel.crt stunnel.key > stunnel.pem
            rm -rf stunnel.crt
            echo -e "${YELLOW}Run in background or foreground service ? (b/f): ${NC}\c"
            read bind
            if [ "$bind" = "b" ]; then
                screen -dmS ashssl ./ashsslproxy-linux-amd64 -listen :$ssl_port -forward 127.0.0.1:$target_port -private_key stunnel.pem -public_key stunnel.key
            else
                json_content=$(cat <<-EOF
[Unit]
Description=Daemonize ASH SSL Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/ashssl/ashsslproxy-linux-amd64 -listen :$ssl_port -forward 127.0.0.1:$target_port -private_key /root/ashssl/stunnel.pem -public_key /root/ashssl/stunnel.key
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
)
                echo "$json_content" > /etc/systemd/system/ashssl.service
                systemctl start ashssl
                systemctl enable ashssl
            fi
            lsof -i :"$ssl_port"
            echo -e "\n${GREEN}ASH SSL Installed Successfully${NC}"
            exit 0
            ;;
        9|09)
            clear
            echo -e "${RED}[Warning]${YELLOW} This version of SSH is only for tunneling, it has anti-torrent features."
            echo "It doesn't come with shell environment support, so do NOT ever replace it with your"
            echo "current SSH and use it only for tunneling, otherwise you will lose access for your shell.${NC}"
            echo -e "${CYAN}Press enter to accept and continue...${NC}"
            read
            echo -e "${YELLOW}Installing ASH SSH...${NC}"
            apt -y update && apt -y upgrade
            apt -y install lsof screen
            while true; do
                echo -e "${YELLOW}Remote SSH Port : ${NC}\c"
                read ssh_port
                if is_number "$ssh_port" && [ "$ssh_port" -ge 1 ] && [ "$ssh_port" -le 65535 ]; then
                    break
                else
                    echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
                fi
            done
            rm -rf ashssh
            mkdir ashssh
            cd ashssh
            wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/ashssh-linux-amd64
            chmod 755 ashssh-linux-amd64
            echo -e "${YELLOW}Run in background or foreground service ? (b/f): ${NC}\c"
            read bind
            if [ "$bind" = "b" ]; then
                screen -dmS ashssh ./ashssh-linux-amd64 -listen :$ssh_port -hostkey /etc/ssh/ssh_host_rsa_key
            else
                json_content=$(cat <<-EOF
[Unit]
Description=Daemonize ASH SSH Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/ashssh/ashssh-linux-amd64 -listen :$ssh_port -hostkey /etc/ssh/ssh_host_rsa_key
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
)
                echo "$json_content" > /etc/systemd/system/ashssh.service
                systemctl start ashssh
                systemctl enable ashssh
            fi
            lsof -i :"$ssh_port"
            echo -e "\n${GREEN}ASH SSH Installed Successfully${NC}"
            exit 0
            ;;
        0|00)
            clear
            echo -e "${YELLOW}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please enter a valid number.${NC}"
            sleep 1
            ;;
    esac
done
