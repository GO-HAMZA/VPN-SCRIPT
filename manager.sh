#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS="Unknown"
fi

if [[ "$OS" == "ubuntu" || "$OS" == "debian" || "$OS" == "kali" ]]; then
    CMD="apt-get update -y && apt-get install -y"
elif [[ "$OS" == "centos" || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
    CMD="yum install -y"
else
    CMD="apt-get install -y"
fi

USER_DB="/etc/xpanel/users_db.txt"
BOT_CONF="/etc/xpanel/bot.conf"
MONITOR_SCRIPT="/usr/local/bin/kp_monitor.py"
LOG_FILE="/var/log/kp_manager.log"
BACKUP_DIR="/root/backups"
MIGRATION_FILE="/root/migration_users.txt"
VENV_DIR="/etc/xpanel/venv"
PYTHON_BIN="$VENV_DIR/bin/python3"
PIP_BIN="$VENV_DIR/bin/pip3"
DB_LOCK="/etc/xpanel/.db.lock"

RED=$'\033[1;31m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'; CYAN=$'\033[1;36m'; NC=$'\033[0m'; WHITE=$'\033[1;37m'
LINE="${BLUE}===============================================${NC}"

mkdir -p /etc/xpanel "$BACKUP_DIR"
touch "$USER_DB" "$LOG_FILE" "$DB_LOCK"
[[ ! -f "$BOT_CONF" ]] && touch "$BOT_CONF"

# Ensure essential packages are installed
if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null || ! command -v virtualenv &> /dev/null; then
    $CMD python3 python3-pip python3-venv systemd-logind > /dev/null 2>&1
fi

# Create Python virtual environment if it does not exist
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

# =============================================
# EXPIRY MONITOR (PYTHON) - AGGRESSIVE KILL
# =============================================
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/usr/bin/env python3
import datetime, subprocess, os, time, fcntl
import urllib.request, urllib.parse

DB_FILE = "/etc/xpanel/users_db.txt"
LOCK_FILE = "/etc/xpanel/.db.lock"
CONF_FILE = "/etc/xpanel/bot.conf"
LOG_FILE = "/var/log/kp_manager.log"
alert_cache = {}

def load_config():
    c = {}
    try:
        for l in open(CONF_FILE):
            if "=" in l: k, v = l.strip().split("=", 1); c[k] = v.strip().replace('"', '')
    except: pass
    return c

def log_event(msg):
    try:
        timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        with open(LOG_FILE, "a") as f:
            f.write(f"[{timestamp}] {msg}\n")
    except: pass

def send_alert(msg, user_key):
    try:
        cfg = load_config()
        if cfg.get("ALERTS") != "ON": return 
        now = time.time()
        if user_key in alert_cache and now - alert_cache[user_key] < 60: return
        alert_cache[user_key] = now
        token = cfg.get("BOT_TOKEN")
        admin = cfg.get("ADMIN_ID")
        if token and admin:
            url = f"https://api.telegram.org/bot{token}/sendMessage"
            data = urllib.parse.urlencode({'chat_id': admin, 'text': msg, 'parse_mode': 'HTML'}).encode('utf-8')
            req = urllib.request.Request(url, data=data)
            urllib.request.urlopen(req, timeout=3)
    except: pass

def kill_user(user):
    os.system(f"usermod -L {user} >/dev/null 2>&1")
    os.system(f"pkill -9 -u {user} >/dev/null 2>&1")
    os.system(f"ps xaf | grep -E 'sshd|dropbear' | grep ' {user} ' | grep -v grep | awk '{{print $1}}' | xargs -r kill -9 >/dev/null 2>&1")
    os.system(f"loginctl terminate-user {user} >/dev/null 2>&1")

def check_loop():
    while True:
        try:
            with open(LOCK_FILE, "a") as lock_f:
                fcntl.flock(lock_f, fcntl.LOCK_EX)
                if os.path.exists(DB_FILE):
                    with open(DB_FILE, 'r+') as f:
                        lines = f.readlines()
                        new_lines = []
                        status_changed = False
                        now = datetime.datetime.now()
                        
                        for line in lines:
                            parts = line.strip().split('|')
                            if len(parts) < 3: continue
                            user, exp_date, exp_time = parts[0], parts[1], parts[2]

                            if "V1" in user or "Turbo" in user or user == "root":
                                new_lines.append(line); continue
                            
                            expired = False
                            if exp_date.upper() not in ["NEVER", "EXPIRED"]:
                                try:
                                    exp = datetime.datetime.strptime(f"{exp_date} {exp_time}", "%Y-%m-%d %H:%M")
                                    if now >= exp:
                                        kill_user(user)
                                        status_changed = True; expired = True
                                        log_event(f"ACCOUNT EXPIRED: {user} locked and disconnected.")
                                        send_alert(f"🔒 <b>ACCOUNT EXPIRED</b>\n\n👤 User: <code>{user}</code>\n🛑 Account forcefully disconnected.", f"{user}_exp")
                                except: pass
                            
                            if expired:
                                new_lines.append(f"{user}|EXPIRED|00:00\n")
                                continue

                            new_lines.append(line)
                        
                        if status_changed:
                            f.seek(0)
                            f.writelines(new_lines)
                            f.truncate()
                fcntl.flock(lock_f, fcntl.LOCK_UN)
        except: pass
        time.sleep(10)

if __name__ == "__main__":
    check_loop()
EOF
chmod +x "$MONITOR_SCRIPT"

cat > /etc/systemd/system/kp_monitor.service << EOF
[Unit]
Description=SSH Monitor & Alerts
After=network.target
[Service]
ExecStart=$PYTHON_BIN /usr/local/bin/kp_monitor.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kp_monitor >/dev/null 2>&1
systemctl restart kp_monitor

pause() { echo -e "\n${BLUE}PRESS [ENTER] TO RETURN...${NC}"; read; }

draw_header() {
    clear
    echo -e "${LINE}"
    echo -e "     ${BLUE}====== SSH • MANAGER ======${NC}"
    echo -e "${LINE}"
}

# =============================================
# BASH MENU FUNCTIONS
# =============================================
fun_create() {
    draw_header
    echo -ne " ${BLUE}👤 Enter Username : ${NC}"
    read u
    if [[ -z "$u" ]]; then echo -e "\n${RED} ❌ Username cannot be empty!${NC}"; pause; return; fi
    if [[ ! "$u" =~ ^[a-zA-Z0-9_]+$ ]]; then echo -e "\n${RED} ❌ Invalid Username! Use only letters and numbers.${NC}"; pause; return; fi
    if id "$u" &>/dev/null || grep -q "^$u|" "$USER_DB"; then echo -e "\n${RED} ❌ USER ALREADY EXISTS!${NC}"; pause; return; fi

    echo -ne " ${BLUE}🔑 Enter Password : ${NC}"
    read p
    if [[ -z "$p" ]]; then echo -e "\n${RED} ❌ Password cannot be empty!${NC}"; pause; return; fi

    echo -ne " ${BLUE}⏳ Set Expiry Date [Y/N] : ${NC}"
    read exp_choice
    if [[ "${exp_choice,,}" == "y" ]]; then
        echo -ne " ${BLUE}📅 Enter number of days : ${NC}"
        read CUSTOM_DAYS
        if [[ "$CUSTOM_DAYS" =~ ^[0-9]+$ ]] && [ "$CUSTOM_DAYS" -gt 0 ]; then
            START_TIMESTAMP=$(date +%s)
            SECONDS_IN_DURATION=$(( CUSTOM_DAYS * 24 * 60 * 60 ))
            EXPIRATION_TIMESTAMP=$(( START_TIMESTAMP + SECONDS_IN_DURATION ))
            d=$(date -d "@$EXPIRATION_TIMESTAMP" +"%Y-%m-%d")
            t=$(date -d "@$EXPIRATION_TIMESTAMP" +"%H:%M")
        else
            echo -e "\n${RED} ❌ Invalid number of days! Setting to NEVER.${NC}"
            sleep 2
            d="NEVER"
            t="00:00"
        fi
    else
        d="NEVER"
        t="00:00"
    fi
    
    useradd -M -s /bin/false "$u" >/dev/null 2>&1
    echo "$u:$p" | chpasswd >/dev/null 2>&1
    
    (
        flock -x 200
        echo "$u|$d|$t" >> "$USER_DB"
    ) 200>"/etc/xpanel/.db.lock"

    clear
    echo -e "${LINE}\n                 ${WHITE}ACCOUNT CREATED${NC}\n${LINE}\n"
    echo -e " ${BLUE}👤 Username :${NC} ${WHITE}$u${NC}\n ${BLUE}🔑 Password :${NC} ${WHITE}$p${NC}"
    echo -e " ${BLUE}📅 Expiry   :${NC} ${WHITE}$d${NC}\n ${BLUE}⏰ Time     :${NC} ${WHITE}$t${NC}\n\n${LINE}"
    echo -e " ${BLUE}📋 Copy     :${NC} ${WHITE}$u:$p${NC}\n${LINE}"
    pause
}

fun_renew() {
    draw_header
    echo -e "               🔄 ${BLUE}RENEW ACCOUNT${NC}\n${LINE}"
    echo -ne " ${BLUE}👤 USERNAME : ${NC}"
    read u
    if ! grep -q "^$u|" "$USER_DB"; then echo -e "\n${RED} ❌ NOT FOUND!${NC}"; pause; return; fi

    echo -ne " ${BLUE}⏳ Set Expiry Date [Y/N] : ${NC}"
    read exp_choice
    if [[ "${exp_choice,,}" == "y" ]]; then
        echo -ne " ${BLUE}📅 Enter number of days to renew : ${NC}"
        read CUSTOM_DAYS
        if [[ "$CUSTOM_DAYS" =~ ^[0-9]+$ ]] && [ "$CUSTOM_DAYS" -gt 0 ]; then
            START_TIMESTAMP=$(date +%s)
            SECONDS_IN_DURATION=$(( CUSTOM_DAYS * 24 * 60 * 60 ))
            EXPIRATION_TIMESTAMP=$(( START_TIMESTAMP + SECONDS_IN_DURATION ))
            d=$(date -d "@$EXPIRATION_TIMESTAMP" +"%Y-%m-%d")
            t=$(date -d "@$EXPIRATION_TIMESTAMP" +"%H:%M")
        else
            echo -e "\n${RED} ❌ Invalid number of days! Setting to NEVER.${NC}"
            sleep 2
            d="NEVER"
            t="23:59"
        fi
    else
        d="NEVER"; t="00:00"
    fi
    
    (
        flock -x 200
        sed -i "/^$u|/d" "$USER_DB"
        echo "$u|$d|$t" >> "$USER_DB"
    ) 200>"/etc/xpanel/.db.lock"

    usermod -U "$u" >/dev/null 2>&1
    echo -e "\n${GREEN} ✅ RENEWED SUCCESSFULLY${NC}"; pause
}

fun_remove() {
    draw_header
    echo -e "               🗑️ ${BLUE}DELETE ACCOUNT${NC}\n${LINE}"
    echo -ne " ${BLUE}👤 USERNAME : ${NC}"
    read u
    echo -ne " ${BLUE}⚠️ CONFIRM [Y/N]: ${NC}"
    read c
    if [[ "${c,,}" == "y" ]]; then
        loginctl terminate-user "$u" >/dev/null 2>&1
        pkill -KILL -u "$u" >/dev/null 2>&1
        userdel -f "$u" >/dev/null 2>&1
        (
            flock -x 200
            sed -i "/^$u|/d" "$USER_DB"
        ) 200>"/etc/xpanel/.db.lock"
        echo -e "\n${RED} 🗑️ DELETED SUCCESSFULLY${NC}"
    fi
    pause
}

fun_lock() {
    draw_header
    echo -e "               🔒 ${BLUE}LOCK ACCOUNT${NC}\n${LINE}"
    echo -ne " ${BLUE}👤 USERNAME : ${NC}"
    read u
    echo -e " ${BLUE}[1] LOCK ⛔${NC}\n ${BLUE}[2] UNLOCK 🔓${NC}"
    echo -ne " ${BLUE}SELECT: ${NC}"
    read s
    if [[ "$s" == "1" ]]; then
        usermod -L "$u" >/dev/null 2>&1; loginctl terminate-user "$u" >/dev/null 2>&1; pkill -KILL -u "$u" >/dev/null 2>&1; ps xaf | grep -E 'sshd|dropbear' | grep " $u " | grep -v grep | awk '{print $1}' | xargs -r kill -9 >/dev/null 2>&1; echo -e "\n${GREEN} ⛔ LOCKED & DISCONNECTED${NC}"
    else
        usermod -U "$u" >/dev/null 2>&1; echo -e "\n${GREEN} 🔓 UNLOCKED${NC}"
    fi
    pause
}

fun_list() {
    clear
    echo -e "${LINE}\n               📋 ${BLUE}LIST ACCOUNTS${NC}\n${LINE}"
    SHADOW_CACHE=$(cat /etc/shadow 2>/dev/null)
    while IFS='|' read -r u d t rest; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then
             if [[ "$d" == "NEVER" || "$d" == "EXPIRED" ]]; then DATE_STR="$d"; else DATE_STR="$d $t"; fi
             if echo "$SHADOW_CACHE" | grep -q "^${u}:!"; then LOCK_STAT="⛔"; else LOCK_STAT="  "; fi
             printf " ${BLUE}👤 %-12s${NC} %s ${BLUE}📅 %s${NC}\n" "$u" "$LOCK_STAT" "$DATE_STR"
        fi
    done < "$USER_DB"
    echo -e "${LINE}"
    pause
}

fun_search() {
    clear
    echo -e "${LINE}\n               🔍 ${BLUE}SEARCH ACCOUNT${NC}\n${LINE}"
    echo -ne " ${BLUE}👤 Enter Username : ${NC}"
    read search_q
    
    if [[ -z "$search_q" ]]; then 
        echo -e "\n${RED} ❌ Search cannot be empty!${NC}"
        pause; return
    fi

    results=$(grep -i "$search_q" "$USER_DB")
    
    if [[ -z "$results" ]]; then
        echo -e "\n${RED} ❌ NO USER FOUND MATCHING: ${WHITE}$search_q${NC}"
    else
        echo -e "\n${GREEN} ✅ RESULTS FOUND:${NC}\n"
        SHADOW_CACHE=$(cat /etc/shadow 2>/dev/null)
        
        while IFS='|' read -r u d t rest; do
            [[ -z "$u" ]] && continue
            if id "$u" &>/dev/null; then
                 if [[ "$d" == "NEVER" || "$d" == "EXPIRED" ]]; then DATE_STR="$d"; else DATE_STR="$d $t"; fi
                 if echo "$SHADOW_CACHE" | grep -q "^${u}:!"; then 
                     LOCK_STAT="${RED}⛔ LOCKED (EXPIRED OR BANNED)${NC}"
                 else 
                     LOCK_STAT="${GREEN}🟢 ACTIVE${NC}"
                 fi
                 echo -e " ${BLUE}👤 Username :${NC} ${WHITE}$u${NC}"
                 echo -e " ${BLUE}📊 Status   :${NC} $LOCK_STAT"
                 echo -e " ${BLUE}📅 Expiry   :${NC} ${WHITE}$DATE_STR${NC}"
                 echo -e " ${LINE}"
            fi
        done <<< "$results"
    fi
    pause
}

fun_monitor_view() {
    clear
    echo -e "${LINE}\n   ${BLUE}========== 👁 ${BLUE}LIVE SSH MONITOR =========${NC}\n${LINE}"
    
    ACTIVE_USERS_DATA=$(ps -axo user:32,comm 2>/dev/null | grep -E 'sshd|dropbear' | awk '{print $1}' | sort | uniq -c)
    
    while IFS='|' read -r u d t rest; do
        [[ -z "$u" ]] && continue
        
        if id "$u" &>/dev/null; then
             USER_CONN_COUNT=$(echo "$ACTIVE_USERS_DATA" | grep -w "$u" | awk '{print $1}')
             
             if [[ -n "$USER_CONN_COUNT" && "$USER_CONN_COUNT" -gt 0 ]]; then
                 STATUS="${GREEN}🟢 ONLINE [ ${USER_CONN_COUNT} ]${NC}"
             else
                 STATUS="${RED}🔴 OFFLINE${NC}"
             fi
             
             printf " ${BLUE}👤 %-16s${NC} %s\n" "$u" "$STATUS"
        fi
    done < "$USER_DB"
    
    echo -e "${LINE}"
    pause
}

fun_backup() {
    draw_header
    echo -e "               💾 ${BLUE}BACKUP DATA${NC}\n${LINE}"
    cp "$USER_DB" "$BACKUP_DIR/users_backup_$(date +%F).txt"
    echo -e "${GREEN} ✅ BACKUP SAVED IN $BACKUP_DIR${NC}"; pause
}

fun_export_users() {
    draw_header; echo -e "${BLUE} 📤 EXPORTING USERS...${NC}"
    cp "$USER_DB" "$MIGRATION_FILE"
    echo -e "${GREEN} ✅ EXPORT SUCCESSFUL!${NC}\n FILE: $MIGRATION_FILE\n UPLOAD THIS TO NEW SERVER."; pause
}

fun_import_users() {
    draw_header; echo -e "${BLUE} 📥 RESTORING USERS...${NC}"
    if [[ ! -f "$MIGRATION_FILE" ]]; then echo -e "${RED} ❌ FILE NOT FOUND ($MIGRATION_FILE)${NC}"; pause; return; fi
    count=0
    while IFS='|' read -r u d t rest; do
        [[ -z "$u" ]] && continue
        if ! id "$u" &>/dev/null; then
            useradd -M -s /bin/false "$u" >/dev/null 2>&1; echo "$u:12345" | chpasswd >/dev/null 2>&1
            echo -e " CREATED: ${GREEN}$u${NC}"; ((count++))
        fi
    done < "$MIGRATION_FILE"
    
    (
        flock -x 200
        cat "$MIGRATION_FILE" > "$USER_DB"
    ) 200>"/etc/xpanel/.db.lock"

    echo -e "\n${GREEN} ✅ RESTORED: $count USERS${NC}"; pause
}

fun_violations() {
    clear
    echo -e "${LINE}\n         🔔 ${BLUE}ALERTS LOG (EXPIRED LOGS)${NC}\n${LINE}\n"
    if [ -f "$LOG_FILE" ]; then
        ALERTS=$(grep "ACCOUNT EXPIRED" "$LOG_FILE" | tail -n 15)
        if [[ -z "$ALERTS" ]]; then echo -e " ${GREEN}✅ NO EXPIRED ACCOUNTS DETECTED YET.${NC}"
        else
            while read -r line; do echo -e " ${YELLOW}🕒 $line${NC}"; done <<< "$ALERTS"
        fi
    else
        echo -e " ${YELLOW}LOG FILE IS EMPTY.${NC}"
    fi
    echo -e "\n${LINE}"; pause
}

# =============================================
# TELEGRAM BOT INSTALLER (SECURE VENV)
# =============================================
fun_install_bot() {
    clear; echo -e "${BLUE}INSTALLING SECURE BOT ENVIRONMENT...${NC}"
    
    echo -ne " ${BLUE}🤖 Enter your Telegram Bot Token: ${NC}"
    read -r input_token
    if [[ -z "$input_token" ]]; then
        echo -e "${RED}❌ Token cannot be empty! Installation aborted.${NC}"; pause; return
    fi
    
    echo -ne " ${BLUE}👤 Enter your Telegram Admin ID: ${NC}"
    read -r input_id
    if [[ -z "$input_id" ]]; then
        echo -e "${RED}❌ Admin ID cannot be empty! Installation aborted.${NC}"; pause; return
    fi

    pkill -f ssh_bot.py 2>/dev/null
    systemctl stop sshbot >/dev/null 2>&1
    
    echo -e "${YELLOW}⚙️ Installing Python dependencies in Secure VENV...${NC}"
    $PIP_BIN install urllib3==1.26.15 python-telegram-bot==13.7 schedule requests >/dev/null 2>&1
    
    echo "BOT_TOKEN=\"$input_token\"" > "$BOT_CONF"
    echo "ADMIN_ID=\"$input_id\"" >> "$BOT_CONF"
    echo "ALERTS=\"ON\"" >> "$BOT_CONF"
    chmod 600 "$BOT_CONF"
    
    cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, re, fcntl, datetime
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(message)s')
CONF_FILE = "/etc/xpanel/bot.conf"
DB_FILE = "/etc/xpanel/users_db.txt"
LOCK_FILE = "/etc/xpanel/.db.lock"
LOG_FILE = "/var/log/kp_manager.log"
TLINE = "============================"

def load_config():
    c = {}
    try:
        for l in open(CONF_FILE):
            if "=" in l: k, v = l.strip().split("=", 1); c[k] = v.strip().replace('"', '')
    except: pass
    return c

cfg = load_config(); TOKEN = cfg.get("BOT_TOKEN"); ADMIN_ID = int(cfg.get("ADMIN_ID", 0))

def kill_user(user):
    os.system(f"usermod -L {user} >/dev/null 2>&1")
    os.system(f"pkill -9 -u {user} >/dev/null 2>&1")
    os.system(f"ps xaf | grep -E 'sshd|dropbear' | grep ' {user} ' | grep -v grep | awk '{{print $1}}' | xargs -r kill -9 >/dev/null 2>&1")
    os.system(f"loginctl terminate-user {user} >/dev/null 2>&1")

def get_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 CREATE", callback_data='add'), InlineKeyboardButton("🔄 RENEW", callback_data='ren')],
        [InlineKeyboardButton("🗑 DELETE", callback_data='del'), InlineKeyboardButton("🔒 LOCK/UNLOCK", callback_data='lock_menu')],
        [InlineKeyboardButton("📋 LIST ALL", callback_data='list'), InlineKeyboardButton("🔍 SEARCH", callback_data='search_menu')],
        [InlineKeyboardButton("👁 MONITOR", callback_data='onl'), InlineKeyboardButton("💾 BACKUP", callback_data='bak')],
        [InlineKeyboardButton("🔔 ALERTS", callback_data='alerts'), InlineKeyboardButton("⚙ SETTINGS", callback_data='bot_set')],
        [InlineKeyboardButton("🚪 EXIT", callback_data='close')]
    ])

def get_settings_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("💻 Server Info", callback_data='set_info')],
        [InlineKeyboardButton("🔄 Restart Monitor", callback_data='set_mon')],
        [InlineKeyboardButton("🚀 Migration", callback_data='migrate')],
        [InlineKeyboardButton("🔙 BACK", callback_data='back')]
    ])

def get_back_btn():
    return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]])

def start(u, c):
    if u.effective_user.id == ADMIN_ID: u.message.reply_text(f"⚡ <b>SSH MANAGER V 10</b>", parse_mode=ParseMode.HTML, reply_markup=get_menu())

def btn(u, c):
    q = u.callback_query; q.answer(); d = q.data
    if d == 'close':
        try: q.message.delete()
        except: pass
        return
    if d == 'back': c.user_data.clear(); q.edit_message_text(f"⚡ <b>SSH MANAGER V 10</b>", parse_mode=ParseMode.HTML, reply_markup=get_menu()); return
    try:
        if d == 'add':
            c.user_data['act'] = 'add_u'
            q.edit_message_text("👤 <b>Send the New Username in chat:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'add_yes':
            c.user_data['act'] = 'a_datetime'
            q.edit_message_text(f"👤 Username : <code>{c.user_data['u']}</code>\n🔑 Password  : <code>{c.user_data['p']}</code>\n\n📅 <b>Enter number of days:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'add_no':
            usr = c.user_data['u']; pwd = c.user_data['p']; dt = "NEVER"; tm = "00:00"
            subprocess.run(["useradd", "-M", "-s", "/bin/false", usr], stdout=subprocess.DEVNULL)
            subprocess.run(["chpasswd"], input=f"{usr}:{pwd}".encode(), stdout=subprocess.DEVNULL)
            
            with open(LOCK_FILE, "a") as lock_f:
                fcntl.flock(lock_f, fcntl.LOCK_EX)
                with open(DB_FILE, 'a') as f:
                    f.write(f"{usr}|{dt}|{tm}\n")
                fcntl.flock(lock_f, fcntl.LOCK_UN)
                
            resp = (f"<b>{TLINE}</b>\n           <b>ACCOUNT CREATED</b>          \n<b>{TLINE}</b>\n\n👤 Username : <code>{usr}</code>\n🔑 Password : <code>{pwd}</code>\n📅 Expiry   : <code>{dt}</code>\n⏰ Time     : <code>{tm}</code>\n\n<b>{TLINE}</b>\n📋 Copy     : <code>{usr}:{pwd}</code>\n<b>{TLINE}</b>")
            q.edit_message_text(resp, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            c.user_data.clear()

        elif d == 'ren': 
            c.user_data['act']='r_user'
            q.edit_message_text("🔄 <b>Enter Username :</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'ren_yes':
            c.user_data['act'] = 'r_val'
            q.edit_message_text("📅 <b>Enter number of days to renew:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'ren_no':
            usr = c.user_data.get('ru')
            with open(LOCK_FILE, "a") as lock_f:
                fcntl.flock(lock_f, fcntl.LOCK_EX)
                with open(DB_FILE, 'r+') as f:
                    lines = [l for l in f.readlines() if not l.startswith(f"{usr}|")]
                    lines.append(f"{usr}|NEVER|00:00\n")
                    f.seek(0); f.writelines(lines); f.truncate()
                fcntl.flock(lock_f, fcntl.LOCK_UN)
                
            subprocess.run(["usermod", "-U", usr], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            q.edit_message_text(f"✅ <b>RENEWED & UNLOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'del': 
            c.user_data['act']='d1'
            q.edit_message_text("🗑️ <b>Username to Delete:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'del_yes':
            usr = c.user_data.get('del_u')
            if usr:
                kill_user(usr)
                subprocess.run(["userdel", "-f", usr], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if os.path.exists(DB_FILE):
                    with open(LOCK_FILE, "a") as lock_f:
                        fcntl.flock(lock_f, fcntl.LOCK_EX)
                        with open(DB_FILE, 'r+') as f:
                            lines = [l for l in f.readlines() if not l.startswith(f"{usr}|")]
                            f.seek(0); f.writelines(lines); f.truncate()
                        fcntl.flock(lock_f, fcntl.LOCK_UN)
                q.edit_message_text(f"🗑️ <b>DELETED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
                
        elif d == 'del_no':
            q.edit_message_text("❌ <b>Deletion Cancelled.</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'lock_menu':
            c.user_data['act']='lu_user'
            q.edit_message_text("🔒/🔓 <b>Enter Username :</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d.startswith('do_lock_'):
            usr = d.split('_', 2)[2]
            kill_user(usr)
            q.edit_message_text(f"⛔ <b>LOCKED & DISCONNECTED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d.startswith('do_unlock_'):
            usr = d.split('_', 2)[2]
            subprocess.run(["usermod", "-U", usr], stdout=subprocess.DEVNULL)
            q.edit_message_text(f"🔓 <b>UNLOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'search_menu':
            c.user_data['act'] = 'search_u'
            q.edit_message_text("🔍 <b>Enter Username :</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'list':
            if os.path.exists(DB_FILE):
                try: shadow_data = open('/etc/shadow', 'r').read()
                except: shadow_data = ""
                
                valid_lines = [l.strip().split('|') for l in open(DB_FILE) if len(l.strip().split('|')) >= 3 and "root" not in l]
                if not valid_lines:
                    q.edit_message_text("No users found.", reply_markup=get_back_btn())
                    return
                
                chunk_size = 50
                chunks = [valid_lines[i:i + chunk_size] for i in range(0, len(valid_lines), chunk_size)]
                
                for idx, chunk in enumerate(chunks):
                    total_pages = len(chunks)
                    if total_pages > 1:
                        pg_str = f"ALL USERS ({idx+1}/{total_pages})"
                        sp_l = max(0, (28 - len(pg_str)) // 2)
                        sp_r = max(0, 28 - len(pg_str) - sp_l)
                        header = f"<b>{TLINE}</b>\n{' '*sp_l}<b>{pg_str}</b>{' '*sp_r}\n<b>{TLINE}</b>\n\n"
                    else:
                        header = f"<b>{TLINE}</b>\n         <b>ALL USERS</b>         \n<b>{TLINE}</b>\n\n"
                        
                    body = header
                    for p in chunk:
                        usr, date, tm = p[0], p[1], p[2]
                        date_str = date if date in ["NEVER", "EXPIRED"] else f"{date} {tm}"
                        lock_icon = " ⛔" if f"\n{usr}:!" in shadow_data or shadow_data.startswith(f"{usr}:!") else ""
                        body += f"👤 <code>{usr}</code>{lock_icon}\n📅 <code>{date_str}</code>\n\n"
                    
                    if idx == 0:
                        q.edit_message_text(body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if total_pages == 1 else None)
                    else:
                        c.bot.send_message(chat_id=u.effective_chat.id, text=body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if idx == total_pages - 1 else None)
            else:
                q.edit_message_text("No users found.", reply_markup=get_back_btn())

        elif d == 'onl':
            if os.path.exists(DB_FILE):
                try:
                    active_users_raw = subprocess.getoutput("ps -axo user:32,comm | grep -E 'sshd|dropbear' | awk '{print $1}'").split()
                    active_set = set(active_users_raw)
                except: active_set = set()
                
                valid_lines = [l.strip().split('|')[0] for l in open(DB_FILE) if len(l.strip().split('|')) >= 3 and "root" not in l]
                if not valid_lines:
                    q.edit_message_text("No users found.", reply_markup=get_back_btn())
                    return
                
                chunk_size = 100
                chunks = [valid_lines[i:i + chunk_size] for i in range(0, len(valid_lines), chunk_size)]
                
                for idx, chunk in enumerate(chunks):
                    total_pages = len(chunks)
                    if total_pages > 1:
                        pg_str = f"LIVE MONITOR ({idx+1}/{total_pages})"
                        sp_l = max(0, (28 - len(pg_str)) // 2)
                        sp_r = max(0, 28 - len(pg_str) - sp_l)
                        header = f"<b>{TLINE}</b>\n{' '*sp_l}<b>{pg_str}</b>{' '*sp_r}\n<b>{TLINE}</b>\n\n"
                    else:
                        header = f"<b>{TLINE}</b>\n        <b>LIVE MONITOR</b>        \n<b>{TLINE}</b>\n\n"
                        
                    body = header
                    for usr in chunk:
                        st = "🟢 ONLINE" if usr in active_set else "🔴 OFFLINE"
                        body += f"👤 <code>{usr}</code>\n{st}\n\n"
                    
                    if idx == 0:
                        q.edit_message_text(body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if total_pages == 1 else None)
                    else:
                        c.bot.send_message(chat_id=u.effective_chat.id, text=body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if idx == total_pages - 1 else None)
            else:
                q.edit_message_text("No users found.", reply_markup=get_back_btn())
                
        elif d == 'alerts':
            if os.path.exists(LOG_FILE):
                try:
                    alerts_raw = subprocess.getoutput(f"grep 'ACCOUNT EXPIRED' {LOG_FILE} | tail -n 15")
                    if not alerts_raw.strip():
                        msg = "✅ <b>NO EXPIRED ACCOUNTS YET.</b>"
                    else:
                        msg = "🔔 <b>ALERTS LOG (EXPIRED)</b>\n\n"
                        for l in alerts_raw.split('\n'):
                            if l.strip(): msg += f"🕒 {l}\n"
                except:
                    msg = "Error reading log."
            else:
                msg = "⚠️ <b>LOG FILE IS EMPTY.</b>"
            q.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'bak':
            if os.path.exists(DB_FILE): c.bot.send_document(ADMIN_ID, open(DB_FILE, 'rb'))
            q.edit_message_text("✅ <b>DATA SAVED & SENT!</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'bot_set':
            q.edit_message_text("⚙️ <b>SETTINGS</b>\nChoose an option:", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'set_info':
            try:
                up = subprocess.getoutput("uptime -p")
                ram = subprocess.getoutput("free -m | awk 'NR==2{printf \"%.2f%%\", $3*100/$2 }'")
                cpu = subprocess.getoutput("top -bn1 | grep load | awk '{printf \"%.2f%%\", $(NF-2)}'")
                msg = f"💻 <b>SERVER INFO</b>\n\n⏱ <b>Uptime:</b> {up}\n🧠 <b>RAM:</b> {ram}\n⚙️ <b>CPU Load:</b> {cpu}"
            except: msg = "💻 <b>SERVER INFO</b>\nError fetching info."
            q.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'set_mon':
            subprocess.run(["systemctl", "restart", "kp_monitor"])
            q.edit_message_text("✅ <b>Monitor Restarted!</b>", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'migrate':
            if os.path.exists(DB_FILE):
                subprocess.run(["cp", DB_FILE, "/root/migration_users.txt"])
                c.bot.send_document(ADMIN_ID, open("/root/migration_users.txt", 'rb'), caption="🚀 <b>MIGRATION FILE</b>", parse_mode=ParseMode.HTML)
                q.edit_message_text("✅ <b>MIGRATION FILE SENT!</b>", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
    except: pass

def txt(u, c):
    if u.effective_user.id != ADMIN_ID: return
    msg = u.message.text; act = c.user_data.get('act')
    try:
        if act == 'add_u':
            usr = msg.strip()
            if not re.match(r"^[a-zA-Z0-9_]+$", usr):
                u.message.reply_text("❌ <b>Invalid Username! Use only letters and numbers.</b> Try again:", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
                return
                
            if subprocess.run(["id", usr], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0 or (os.path.exists(DB_FILE) and f"{usr}|" in open(DB_FILE).read()):
                u.message.reply_text("❌ <b>User already exists!</b> Try another username:", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            else:
                c.user_data['u'] = usr
                c.user_data['act'] = 'add_p'
                u.message.reply_text(f"👤 Username: <code>{usr}</code>\n\n🔑 <b>Send the Password for this user:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
                
        elif act == 'add_p':
            c.user_data['p'] = msg.strip()
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🟢 YES", callback_data='add_yes'), InlineKeyboardButton("🔴 NO", callback_data='add_no')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            u.message.reply_text(f"👤 Username: <code>{c.user_data['u']}</code>\n🔑 Password: <code>{c.user_data['p']}</code>\n\n⏳ <b>Set Expiry Date by Days?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
            c.user_data['act'] = ''

        elif act == 'lu_user':
            usr = msg.strip()
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🔒 LOCK", callback_data=f"do_lock_{usr}"), InlineKeyboardButton("🔓 UNLOCK", callback_data=f"do_unlock_{usr}")],[InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            u.message.reply_text(f"Select action for <b>{usr}</b>:", parse_mode=ParseMode.HTML, reply_markup=kb)
            c.user_data['act'] = ''
        
        elif act == 'r_user':
            c.user_data['ru'] = msg.strip()
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🟢 YES", callback_data='ren_yes'), InlineKeyboardButton("🔴 NO", callback_data='ren_no')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            u.message.reply_text(f"⏳ <b>Set Expiry Date by Days for {msg}?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
            c.user_data['act'] = ''

        elif act == 'search_u':
            search_q = msg.strip().lower()
            if os.path.exists(DB_FILE):
                try: shadow_data = open('/etc/shadow', 'r').read()
                except: shadow_data = ""
                
                results = []
                for l in open(DB_FILE):
                    parts = l.strip().split('|')
                    if len(parts) >= 3 and search_q in parts[0].lower() and "root" not in parts[0]:
                        usr, date, tm = parts[0], parts[1], parts[2]
                        date_str = date if date in ["NEVER", "EXPIRED"] else f"{date} {tm}"
                        if f"\n{usr}:!" in shadow_data or shadow_data.startswith(f"{usr}:!"):
                            lock_stat = "⛔ LOCKED"
                        else:
                            lock_stat = "🟢 ACTIVE"
                        results.append(f"👤 <code>{usr}</code>\n📊 {lock_stat}\n📅 <code>{date_str}</code>\n")
                
                if results:
                    reply_text = f"✅ <b>RESULTS FOUND:</b>\n\n" + "\n".join(results[:10])
                    if len(results) > 10: reply_text += f"\n...and {len(results)-10} more."
                else:
                    reply_text = f"❌ <b>NO USER FOUND MATCHING:</b> {msg.strip()}"
            else:
                reply_text = "No database found."
                
            u.message.reply_text(reply_text, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            c.user_data['act'] = ''

        elif act == 'a_datetime':
            usr = c.user_data['u']; pwd = c.user_data['p']
            msg_str = msg.strip()
            
            if msg_str.isdigit() and int(msg_str) > 0:
                exp_date = datetime.datetime.now() + datetime.timedelta(days=int(msg_str))
                d = exp_date.strftime("%Y-%m-%d")
                t = exp_date.strftime("%H:%M")
            else:
                d = "NEVER"; t = "00:00"
            
            subprocess.run(["useradd", "-M", "-s", "/bin/false", usr], stdout=subprocess.DEVNULL)
            subprocess.run(["chpasswd"], input=f"{usr}:{pwd}".encode(), stdout=subprocess.DEVNULL)
            
            with open(LOCK_FILE, "a") as lock_f:
                fcntl.flock(lock_f, fcntl.LOCK_EX)
                with open(DB_FILE, 'a') as f:
                    f.write(f"{usr}|{d}|{t}\n")
                fcntl.flock(lock_f, fcntl.LOCK_UN)
                
            resp = (f"<b>{TLINE}</b>\n           <b>ACCOUNT CREATED</b>          \n<b>{TLINE}</b>\n\n👤 Username : <code>{usr}</code>\n🔑 Password : <code>{pwd}</code>\n📅 Expiry   : <code>{d}</code>\n⏰ Time     : <code>{t}</code>\n\n<b>{TLINE}</b>\n📋 Copy     : <code>{usr}:{pwd}</code>\n<b>{TLINE}</b>")
            u.message.reply_text(resp, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            c.user_data.clear()
            
        elif act == 'r_val':
            usr = c.user_data.get('ru')
            msg_str = msg.strip()
            
            if msg_str.isdigit() and int(msg_str) > 0:
                exp_date = datetime.datetime.now() + datetime.timedelta(days=int(msg_str))
                d = exp_date.strftime("%Y-%m-%d")
                t = exp_date.strftime("%H:%M")
            else:
                d = "NEVER"; t = "23:59"
            
            with open(LOCK_FILE, "a") as lock_f:
                fcntl.flock(lock_f, fcntl.LOCK_EX)
                with open(DB_FILE, 'r+') as f:
                    lines = [l for l in f.readlines() if not l.startswith(f"{usr}|")]
                    lines.append(f"{usr}|{d}|{t}\n")
                    f.seek(0); f.writelines(lines); f.truncate()
                fcntl.flock(lock_f, fcntl.LOCK_UN)
                
            subprocess.run(["usermod", "-U", usr], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            u.message.reply_text(f"✅ <b>RENEWED & UNLOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif act == 'd1':
            usr_to_del = msg.strip()
            c.user_data['del_u'] = usr_to_del
            kb = InlineKeyboardMarkup([
                [InlineKeyboardButton("🟢 YES", callback_data='del_yes'), InlineKeyboardButton("🔴 NO", callback_data='del_no')],
                [InlineKeyboardButton("🔙 BACK", callback_data='back')]
            ])
            u.message.reply_text(f"⚠️ <b>Are you sure you want to delete</b> <code>{usr_to_del}</code><b>?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
            c.user_data['act'] = ''
            
    except: pass

def main():
    if not TOKEN: return
    up = Updater(TOKEN, use_context=True)
    up.dispatcher.add_handler(CommandHandler('start', start))
    up.dispatcher.add_handler(CallbackQueryHandler(btn)); up.dispatcher.add_handler(MessageHandler(Filters.text, txt))
    up.start_polling(); up.idle()
if __name__ == '__main__': main()
EOF
    cat > /etc/systemd/system/sshbot.service << EOF
[Unit]
Description=SSH Telegram Bot Service
After=network.target
[Service]
Type=simple
ExecStart=$PYTHON_BIN /root/ssh_bot.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable sshbot >/dev/null 2>&1; systemctl restart sshbot
    
    echo -e "\n${GREEN}✅ SECURE BOT INSTALLED!${NC}"
    echo -e "${YELLOW}👉 Go to your Telegram Bot and send /start${NC}"
    pause
}

# =============================================
# SETTINGS MENU
# =============================================
fun_settings() {
    while true; do
        draw_header
        echo -e "            ⚙️ ${BLUE}SETTINGS & TOOLS${NC}\n${LINE}"
        echo -e "  ${BLUE}[1] 🛠️ INSTALL TELEGRAM BOT${NC}"
        echo -e "  ${BLUE}[2] 🌍 SET TIMEZONE${NC}"
        echo -e "  ${BLUE}[3] 📤 EXPORT USERS${NC}"
        echo -e "  ${BLUE}[4] 📥 RESTORE USERS${NC}"
        echo -e "  ${BLUE}[0] 🔙 BACK${NC}\n${LINE}"
        echo -ne "  ${BLUE}SELECT: ${NC}"
        read s
        case "$s" in
            1) fun_install_bot ;;
            2) 
                echo -ne " ${BLUE}🌍 Enter Timezone : ${NC}"
                read tz
                if timedatectl set-timezone "$tz" 2>/dev/null; then
                    echo -e "\n${GREEN} ✅ TIMEZONE SET TO $tz${NC}"; pause
                else
                    echo -e "\n${RED} ❌ INVALID TIMEZONE!${NC}"; pause
                fi
                ;;
            3) fun_export_users ;;
            4) fun_import_users ;;
            0) break ;;
            *) echo -e "\n${RED} INVALID OPTION!${NC}" ; sleep 1 ;;
        esac
    done
}

# =============================================
# MAIN MENU
# =============================================
while true; do
    draw_header
    echo -e "  ${BLUE}[01] 👤 CREATE ACCOUNT${NC}"
    echo -e "  ${BLUE}[02] 🔄 RENEW ACCOUNT${NC}"
    echo -e "  ${BLUE}[03] 🗑 DELETE ACCOUNT${NC}"
    echo -e "  ${BLUE}[04] ⛔ LOCK ACCOUNT${NC}"
    echo -e "  ${BLUE}[05] 📋 LIST ACCOUNTS${NC}"
    echo -e "  ${BLUE}[06] 🔍 SEARCH ACCOUNT${NC}"
    echo -e "  ${BLUE}[07] 👁 MONITOR ACCOUNT${NC}"
    echo -e "  ${BLUE}[08] 💾 BACKUP DATA${NC}"
    echo -e "  ${BLUE}[09] 🔔 EXPIRED ACCOUNTS${NC}"
    echo -e "  ${BLUE}[10] ⚙️ SETTINGS${NC}"
    echo -e "  ${BLUE}[00] ↪️ EXIT${NC}\n${LINE}"
    echo -ne "  ${BLUE}SELECT:${NC} "
    read o
    case "$o" in
        1|01) fun_create ;; 
        2|02) fun_renew ;; 
        3|03) fun_remove ;; 
        4|04) fun_lock ;;
        5|05) fun_list ;; 
        6|06) fun_search ;; 
        7|07) fun_monitor_view ;; 
        8|08) fun_backup ;; 
        9|09) fun_violations ;; 
        10) fun_settings ;;  
        0|00) clear; exit 0 ;;
        *) echo -e "\n${RED} INVALID OPTION!${NC}" ; sleep 1 ;;
    esac
done
