#!/data/data/com.termux/files/usr/bin/bash -e

[ -z "$TERM" ] && export TERM=xterm-256color
BASE_URL="https://image-nethunter.kali.org/nethunter-fs/kali-weekly/"
USERNAME="kali"
SYS_ARCH="arm64"

ask() {
    while true; do
        if [ "${2:-}" = "Y" ]; then
            prompt="Y/n"
            default=Y
        elif [ "${2:-}" = "N" ]; then
            prompt="y/N"
            default=N
        else
            prompt="y/n"
            default=
        fi
        printf "${light_cyan}\n[?] "
        read -p "$1 [$prompt] " REPLY
        [ -z "$REPLY" ] && REPLY=$default
        printf "${reset}"
        case "$REPLY" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac
    done
}

set_strings() {
    printf "${blue}[*] Selecting NetHunter image ...${reset}\n"
    echo "[1] NetHunter ARM64 (full)"
    echo "[2] NetHunter ARM64 (minimal)"
    echo "[3] NetHunter ARM64 (nano)"
    read -p "Enter the image you want to install: " wimg
    case "$wimg" in
        1) wimg="full" ;;
        2) wimg="minimal" ;;
        3) wimg="nano" ;;
        *) wimg="full" ;;
    esac
    CHROOT="kali-${SYS_ARCH}"
    fetch_latest_image
}

fetch_latest_image() {
    printf "${blue}[*] Fetching latest NetHunter image ...${reset}\n"
    IMAGE_LIST=$(curl -s "${BASE_URL}" | grep -o 'kali-nethunter-[0-9]\{4\}\.W[0-9]\{1,2\}-rolling-rootfs-'${wimg}'-'${SYS_ARCH}'.tar.xz' | sort -r)
    if [ -z "$IMAGE_LIST" ]; then
        printf "${red}[!] Failed to fetch image list. Check network or URL.${reset}\n"
        exit 1
    fi
    IMAGE_NAME=$(echo "$IMAGE_LIST" | head -n 1)
    SHA_NAME="${IMAGE_NAME}.sha512sum"
    printf "${blue}[*] Latest image: ${IMAGE_NAME}${reset}\n"
}

prepare_fs() {
    unset KEEP_CHROOT
    if [ -d "${CHROOT}" ]; then
        if ask "Existing rootfs directory found. Delete and create a new one?" "N"; then
            rm -rf "${CHROOT}"
        else
            KEEP_CHROOT=1
        fi
    fi
}

cleanup() {
    if [ -f "${IMAGE_NAME}" ]; then
        if ask "Delete downloaded rootfs file?" "N"; then
            rm -f "${IMAGE_NAME}"
            [ -f "${SHA_NAME}" ] && rm -f "${SHA_NAME}"
        fi
    fi
}

check_dependencies() {
    printf "${blue}\n[*] Checking package dependencies...${reset}\n"
    apt-get update -y &> /dev/null || apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" dist-upgrade -y &> /dev/null
    for i in proot tar wget curl; do
        if [ -e "${PREFIX}/bin/$i" ]; then
            echo "  $i is OK"
        else
            printf "Installing ${i}...\n"
            apt install -y "$i" || {
                printf "${red}ERROR: Failed to install ${i}.\nExiting.\n${reset}"
                exit 1
            }
        fi
    done
    apt upgrade -y &> /dev/null
}

get_url() {
    ROOTFS_URL="${BASE_URL}${IMAGE_NAME}"
    SHA_URL="${BASE_URL}${SHA_NAME}"
}

get_rootfs() {
    unset KEEP_IMAGE
    if [ -f "${IMAGE_NAME}" ]; then
        if ask "Existing image file found. Delete and download a new one?" "N"; then
            rm -f "${IMAGE_NAME}"
        else
            printf "${yellow}[!] Using existing rootfs archive${reset}\n"
            KEEP_IMAGE=1
            return
        fi
    fi
    printf "${blue}[*] Downloading rootfs...${reset}\n"
    get_url
    wget --continue "${ROOTFS_URL}" || {
        printf "${red}[!] Download failed. Check network or URL.${reset}\n"
        exit 1
    }
}

check_sha_url() {
    if ! curl --head --silent --fail "${SHA_URL}" > /dev/null; then
        printf "${yellow}[!] SHA_URL does not exist or is unreachable${reset}\n"
        return 1
    fi
    return 0
}

verify_sha() {
    if [ -z "$KEEP_IMAGE" ]; then
        printf "\n${blue}[*] Verifying integrity of rootfs...${reset}\n"
        if [ -f "${SHA_NAME}" ]; then
            sha512sum -c "${SHA_NAME}" || {
                printf "${red}Rootfs corrupted. Please run this installer again or download the file manually\n${reset}"
                exit 1
            }
        else
            printf "${yellow}[!] SHA file not found. Cannot verify integrity.${reset}\n"
            return 1
        fi
    fi
}

get_sha() {
    if [ -z "$KEEP_IMAGE" ]; then
        printf "\n${blue}[*] Getting SHA ...${reset}\n"
        get_url
        [ -f "${SHA_NAME}" ] && rm -f "${SHA_NAME}"
        if check_sha_url; then
            printf "${blue}[+] SHA_URL exists. Downloading...${reset}\n"
            wget --continue "${SHA_URL}" || {
                printf "${yellow}[!] Failed to download SHA file. Skipping verification.${reset}\n"
                return 1
            }
            verify_sha
        else
            printf "${yellow}[!] SHA_URL does not exist. Skipping verification.${reset}\n"
        fi
    fi
}

extract_rootfs() {
    if [ -z "$KEEP_CHROOT" ]; then
        printf "\n${blue}[*] Extracting rootfs...${reset}\n"
        mkdir -p "${CHROOT}"
        proot --link2symlink tar -xf "${IMAGE_NAME}" -C "${CHROOT}" 2> /dev/null || {
            printf "${red}[!] Extraction failed.${reset}\n"
            exit 1
        }
    else
        printf "${yellow}[!] Using existing rootfs directory${reset}\n"
    fi
}

create_launcher() {
    NH_LAUNCHER="${PREFIX}/bin/nethunter"
    NH_SHORTCUT="${PREFIX}/bin/nh"
    cat > "${NH_LAUNCHER}" <<- EOF
#!/data/data/com.termux/files/usr/bin/bash -e
cd \${HOME}
unset LD_PRELOAD
[ ! -f ${CHROOT}/root/.version ] && touch ${CHROOT}/root/.version
user="${USERNAME}"
home="/home/\${user}"
start="sudo -u kali /bin/bash"
 अगर grep -q "kali" ${CHROOT}/etc/passwd; then
    KALIUSR="1"
else
    KALIUSR="0"
fi
if [[ \${KALIUSR} == "0" || ("\$#" != "0" && ("\$1" == "-r" || "\$1" == "-R")) ]]; then
    user="root"
    home="/\${user}"
    start="/bin/bash --login"
    [[ "\$#" != "0" && ("\$1" == "-r" || "\$1" == "-R") ]] && shift
fi
cmdline="proot \\
        --link2symlink \\
        -0 \\
        -r ${CHROOT} \\
        -b /dev \\
        -b /proc \\
        -b /sdcard \\
        -b ${CHROOT}\${home}:/dev/shm \\
        -w \${home} \\
           /usr/bin/env -i \\
           HOME=\${home} \\
           PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin \\
           TERM=\${TERM} \\
           LANG=C.UTF-8 \\
           \${start}"
cmd="\$@"
if [ "\$#" == "0" ]; then
    exec \${cmdline}
else
    \${cmdline} -c "\${cmd}"
fi
EOF
    chmod 700 "${NH_LAUNCHER}"
    [ -L "${NH_SHORTCUT}" ] && rm -f "${NH_SHORTCUT}"
    [ ! -f "${NH_SHORTCUT}" ] && ln -s "${NH_LAUNCHER}" "${NH_SHORTCUT}" >/dev/null
}

check_kex() {
    if [ "$wimg" = "nano" ] || [ "$wimg" = "minimal" ]; then
        nh sudo apt update && nh sudo apt install -y tightvncserver kali-desktop-xfce
    fi
}

create_kex_launcher() {
    KEX_LAUNCHER="${CHROOT}/usr/bin/kex"
    cat > "${KEX_LAUNCHER}" <<- EOF
#!/bin/bash
start-kex() {
    [ ! -f ~/.vnc/passwd ] && passwd-kex
    USR=\$(whoami)
    [ "\$USR" == "root" ] && SCREEN=":2" || SCREEN=":1"
    export MOZ_FAKE_NO_SANDBOX=1 HOME=\${HOME} USER=\${USR}
    LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libgcc_s.so.1 nohup vncserver \$SCREEN >/dev/null 2>&1 </dev/null
    starting_kex=1
    return 0
}
stop-kex() {
    vncserver -kill :1 | sed s/"Xtigervnc"/"NetHunter KeX"/
    vncserver -kill :2 | sed s/"Xtigervnc"/"NetHunter KeX"/
    return \$?
}
passwd-kex() {
    vncpasswd
    return \$?
}
status-kex() {
    sessions=\$(vncserver -list | sed s/"TigerVNC"/"NetHunter KeX"/)
    if [[ \$sessions == *"590"* ]]; then
        printf "\n\${sessions}\n\nYou can use the KeX client to connect to any of these displays.\n\n"
    else
        [ ! -z \$starting_kex ] && printf '\nError starting the KeX server.\nPlease try "nethunter kex kill" or restart your termux session and try again.\n\n'
    fi
    return 0
}
kill-kex() {
    pkill Xtigervnc
    return \$?
}
case \$1 in
    start) start-kex ;;
    stop) stop-kex ;;
    status) status-kex ;;
    passwd) passwd-kex ;;
    kill) kill-kex ;;
    *) stop-kex; start-kex; status-kex ;;
esac
EOF
    chmod 700 "${KEX_LAUNCHER}"
}

fix_profile_bash() {
    [ -f "${CHROOT}/root/.bash_profile" ] && sed -i '/if/,/fi/d' "${CHROOT}/root/.bash_profile"
}

fix_resolv_conf() {
    echo "nameserver 9.9.9.9" > "${CHROOT}/etc/resolv.conf"
    echo "nameserver 149.112.112.112" >> "${CHROOT}/etc/resolv.conf"
}

fix_sudo() {
    chmod +s "${CHROOT}/usr/bin/sudo" "${CHROOT}/usr/bin/su"
    echo "kali    ALL=(ALL:ALL) ALL" > "${CHROOT}/etc/sudoers.d/kali"
    echo "Set disable_coredump false" > "${CHROOT}/etc/sudo.conf"
}

fix_uid() {
    USRID=$(id -u)
    GRPID=$(id -g)
    nh -r usermod -u "${USRID}" kali 2>/dev/null
    nh -r groupmod -g "${GRPID}" kali 2>/dev/null
}

print_banner() {
    clear
    printf "${blue}##################################################\n"
    printf "${blue}##                                              ##\n"
    printf "${blue}##  88      a8P         db        88        88  ##\n"
    printf "${blue}##  88    .88'         d88b       88        88  ##\n"
    printf "${blue}##  88   88'          d8''8b      88        88  ##\n"
    printf "${blue}##  88 d88           d8'  '8b     88        88  ##\n"
    printf "${blue}##  8888'88.        d8YaaaaY8b    88        88  ##\n"
    printf "${blue}##  88P   Y8b      d8''''''''8b   88        88  ##\n"
    printf "${blue}##  88     '88.   d8'        '8b  88        88  ##\n"
    printf "${blue}##  88       Y8b d8'          '8b 888888888 88  ##\n"
    printf "${blue}##                                              ##\n"
    printf "${blue}####  ############# NetHunter ####################${reset}\n\n"
}

red='\033[1;31m'
green='\033[1;32m'
yellow='\033[1;33m'
blue='\033[1;34m'
light_cyan='\033[1;96m'
reset='\033[0m'

cd "${HOME}"
print_banner
set_strings
prepare_fs
check_dependencies
get_rootfs
get_sha
extract_rootfs
create_launcher
cleanup
printf "\n${blue}[*] Configuring NetHunter for Termux ...\n"
fix_profile_bash
fix_resolv_conf
fix_sudo
check_kex
create_kex_launcher
fix_uid
print_banner
printf "${green}[=] Kali NetHunter for Termux installed successfully${reset}\n\n"
printf "${green}[+] To start Kali NetHunter, type:${reset}\n"
printf "${green}[+] nethunter             # To start NetHunter CLI${reset}\n"
printf "${green}[+] nethunter kex passwd  # To set the KeX password${reset}\n"
printf "${green}[+] nethunter kex &       # To start NetHunter GUI${reset}\n"
printf "${green}[+] nethunter kex stop    # To stop NetHunter GUI${reset}\n"
printf "${green}[+] nethunter -r          # To run NetHunter as root${reset}\n"
printf "${green}[+] nh                    # Shortcut for nethunter${reset}\n\n"
