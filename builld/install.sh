#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CURRENT_DIR=$(
    cd "$(dirname "$0")" || exit
    pwd
)

function log() {
    message="[1Panel Log]: $1 "
    case "$1" in
    *"fail"* | *"mistake"* | *"Please use root or sudo Permissions run this script"*)
        echo -e "${RED}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
        ;;
    *"success"*)
        echo -e "${GREEN}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
        ;;
    *"ignore"* | *"continue"*)
        echo -e "${YELLOW}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
        ;;
    *)
        echo -e "${BLUE}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
        ;;
    esac
}
echo
cat <<EOF
 ██╗    ██████╗  █████╗ ███╗   ██╗███████╗██╗     
███║    ██╔══██╗██╔══██╗████╗  ██║██╔════╝██║     
╚██║    ██████╔╝███████║██╔██╗ ██║█████╗  ██║     
 ██║    ██╔═══╝ ██╔══██║██║╚██╗██║██╔══╝  ██║     
 ██║    ██║     ██║  ██║██║ ╚████║███████╗███████╗
 ╚═╝    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝
EOF

log "======================= Start installation ======================="

function Check_Root() {
    if [[ $EUID -ne 0 ]]; then
        log "Please use root or sudo Permissions run this script"
        exit 1
    fi
}

function Prepare_System() {
    if which 1panel >/dev/null 2>&1; then
        log "1Panel Already installed in your system, skip installation process"
        exit 1
    fi
}

function Set_Dir() {
    if read -t 120 -p "set up 1Panel Installation directory (default/opt）：" PANEL_BASE_DIR; then
        if [[ "$PANEL_BASE_DIR" != "" ]]; then
            if [[ "$PANEL_BASE_DIR" != /* ]]; then
                log "Please enter the full path of the directory"
                Set_Dir
            fi

            if [[ ! -d $PANEL_BASE_DIR ]]; then
                mkdir -p "$PANEL_BASE_DIR"
                log "The installation path you choose is $PANEL_BASE_DIR"
            fi
        else
            PANEL_BASE_DIR=/opt
            log "The installation path you choose is $PANEL_BASE_DIR"
        fi
    else
        PANEL_BASE_DIR=/opt
        log "(Set timeout, use the default installation path /opt)"
    fi
}

ACCELERATOR_URL="https://docker.1panelproxy.com"
DAEMON_JSON="/etc/docker/daemon.json"
BACKUP_FILE="/etc/docker/daemon.json.1panel_bak"

function create_daemon_json() {
    log "Create a new configuration file ${DAEMON_JSON}..."
    mkdir -p /etc/docker
    echo '{
        "registry-mirrors": ["'"$ACCELERATOR_URL"'"]
    }' | tee "$DAEMON_JSON" >/dev/null
    log "The acceleration configuration of the mirror has been added."
}

function configure_accelerator() {
    read -p "Do you configure the mirror acceleration?(y/n): " configure_accelerator
    if [[ "$configure_accelerator" == "y" ]]; then
        if [ -f "$DAEMON_JSON" ]; then
            log "The configuration file already exists, and we will backup the existing configuration file as ${BACKUP_FILE} And create a new configuration file."
            cp "$DAEMON_JSON" "$BACKUP_FILE"
            create_daemon_json
        else
            create_daemon_json
        fi

        log "Are restarting Docker Server..."
        systemctl daemon-reload
        systemctl restart docker
        log "Docker The service has been successfully restarted."
    else
        log "Unpaiched mirror acceleration."
    fi
}

function Install_Docker() {
    if which docker >/dev/null 2>&1; then
        log "The docker has been installed, and the installation steps are skipped"
        configure_accelerator
    else
        log "... Online installation docker"

        if [[ $(curl -s ipinfo.io/country) == "CN" ]]; then
            sources=(
                "https://mirrors.aliyun.com/docker-ce"
                "https://mirrors.tencent.com/docker-ce"
                "https://mirrors.163.com/docker-ce"
                "https://mirrors.cernet.edu.cn/docker-ce"
            )

            docker_install_scripts=(
                "https://get.docker.com"
                "https://testingcf.jsdelivr.net/gh/docker/docker-install@master/install.sh"
                "https://cdn.jsdelivr.net/gh/docker/docker-install@master/install.sh"
                "https://fastly.jsdelivr.net/gh/docker/docker-install@master/install.sh"
                "https://gcore.jsdelivr.net/gh/docker/docker-install@master/install.sh"
                "https://raw.githubusercontent.com/docker/docker-install/master/install.sh"
            )

            get_average_delay() {
                local source=$1
                local total_delay=0
                local iterations=2
                local timeout=2

                for ((i = 0; i < iterations; i++)); do
                    delay=$(curl -o /dev/null -s -m $timeout -w "%{time_total}\n" "$source")
                    if [ $? -ne 0 ]; then
                        delay=$timeout
                    fi
                    total_delay=$(awk "BEGIN {print $total_delay + $delay}")
                done

                average_delay=$(awk "BEGIN {print $total_delay / $iterations}")
                echo "$average_delay"
            }

            min_delay=99999999
            selected_source=""

            for source in "${sources[@]}"; do
                average_delay=$(get_average_delay "$source" &)

                if (($(awk 'BEGIN { print '"$average_delay"' < '"$min_delay"' }'))); then
                    min_delay=$average_delay
                    selected_source=$source
                fi
            done
            wait

            if [ -n "$selected_source" ]; then
                log "Choose the source with the lowest delay $Selected_source, delay to $min_delay Second"
                export DOWNLOAD_URL="$selected_source"

                for alt_source in "${docker_install_scripts[@]}"; do
                    log "Try alternative link $alt_source download Docker Installation script..."
                    if curl -fsSL --retry 2 --retry-delay 3 --connect-timeout 5 --max-time 10 "$alt_source" -o get-docker.sh; then
                        log "Successful $alt_source Download and install script"
                        break
                    else
                        log "from $alt_source Download the installation script failed, try the next alternative link"
                    fi
                done

                if [ ! -f "get-docker.sh" ]; then
                    log "All downloads have failed.You can try to install manually Docker, run the following command:"
                    log "bash <(curl -sSL https://linuxmirrors.cn/docker.sh)"
                    exit 1
                fi

                sh get-docker.sh 2>&1 | tee -a ${CURRENT_DIR}/install.log

                docker_config_folder="/etc/docker"
                if [[ ! -d "$docker_config_folder" ]]; then
                    mkdir -p "$docker_config_folder"
                fi

                docker version >/dev/null 2>&1
                if [[ $? -ne 0 ]]; then
                    log "docker Failed to install\n, you can try to install with an offline package. For specific installation steps, please refer to the following links: https://1panel.cn/docs/installation/package_installation/"
                    exit 1
                else
                    log "docker Successful installation"
                    systemctl enable docker 2>&1 | tee -a "${CURRENT_DIR}"/install.log
                    configure_accelerator
                fi
            else
                log "Unable to choose source for installation"
                exit 1
            fi
        else
            log "Non -non -Chinese regions, no need to change the source"
            export DOWNLOAD_URL="https://download.docker.com"
            curl -fsSL "https://get.docker.com" -o get-docker.sh
            sh get-docker.sh 2>&1 | tee -a "${CURRENT_DIR}"/install.log

            log "... start up docker"
            systemctl enable docker
            systemctl daemon-reload
            systemctl start docker 2>&1 | tee -a "${CURRENT_DIR}"/install.log

            docker_config_folder="/etc/docker"
            if [[ ! -d "$docker_config_folder" ]]; then
                mkdir -p "$docker_config_folder"
            fi

            docker version >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                log "docker Failed to install\n, you can try to use the installation package for installation. For specific installation steps, please refer to the following links: https://1panel.cn/docs/installation/package_installation/"
                exit 1
            else
                log "docker Successful installation"
            fi
        fi
    fi
}

function Install_Compose() {
    docker-compose version >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        log "... Online installation docker-compose"

        arch=$(uname -m)
        if [ "$arch" == 'armv7l' ]; then
            arch='armv7'
        fi
        curl -L https://resource.fit2cloud.com/docker/compose/releases/download/v2.26.1/docker-compose-$(uname -s | tr A-Z a-z)-"$arch" -o /usr/local/bin/docker-compose 2>&1 | tee -a "${CURRENT_DIR}"/install.log
        if [[ ! -f /usr/local/bin/docker-compose ]]; then
            log "docker-compose The download failed, please try again"
            exit 1
        fi
        chmod +x /usr/local/bin/docker-compose
        ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

        docker-compose version >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            log "docker-compose Failed to install"
            exit 1
        else
            log "docker-compose Successful installation"
        fi
    else
        compose_v=$(docker-compose -v)
        if [[ $compose_v =~ 'docker-compose' ]]; then
            read -p "Detects installed Docker Compose outdated version (need to be greater than equal to v2.0.0 Version), upgrade [y/n] : " UPGRADE_DOCKER_COMPOSE
            if [[ "$UPGRADE_DOCKER_COMPOSE" == "Y" ]] || [[ "$UPGRADE_DOCKER_COMPOSE" == "y" ]]; then
                rm -rf /usr/local/bin/docker-compose /usr/bin/docker-compose
                Install_Compose
            else
                log "Docker Compose Version $compose_v，It may affect the normal use of the application store"
            fi
        else
            log "Detect Docker Compose Has been installed, skip installation steps"
        fi
    fi
}

function Set_Port() {
    DEFAULT_PORT=$(expr $RANDOM % 55535 + 10000)

    while true; do
        read -p "Set 1panel port (default $DEFAULT_PORT）：" PANEL_PORT

        if [[ "$PANEL_PORT" == "" ]]; then
            PANEL_PORT=$DEFAULT_PORT
        fi

        if ! [[ "$PANEL_PORT" =~ ^[1-9][0-9]{0,4}$ && "$PANEL_PORT" -le 65535 ]]; then
            log "Error: The port number of input must be between 1 and 65535"
            continue
        fi

        if command -v ss >/dev/null 2>&1; then
            if ss -tlun | grep -q ":$PANEL_PORT " >/dev/null 2>&1; then
                log "port $PANEL_PORT is already in-use, please re-enter..."
                continue
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tlun | grep -q ":$PANEL_PORT " >/dev/null 2>&1; then
                log "port $PANEL_PORT is already in-use, please re-enter..."
                continue
            fi
        fi

        log "The port you set is:$PANEL_PORT"
        break
    done
}

function Set_Firewall() {
    if which firewall-cmd >/dev/null 2>&1; then
        if systemctl status firewalld | grep -q "Active: active" >/dev/null 2>&1; then
            log "Firewall open $PANEL_PORT port"
            firewall-cmd --zone=public --add-port="$PANEL_PORT"/tcp --permanent
            firewall-cmd --reload
        else
            log "The firewall is not opened, and the port is open"
        fi
    fi

    if which ufw >/dev/null 2>&1; then
        if systemctl status ufw | grep -q "Active: active" >/dev/null 2>&1; then
            log "Firewall open $PANEL_PORT port"
            ufw allow "$PANEL_PORT"/tcp
            ufw reload
        else
            log "The ufw is in active"
        fi
    fi
}

function Set_Entrance() {
    DEFAULT_ENTRANCE=$(cat /dev/urandom | head -n 16 | md5sum | head -c 10)

    while true; do
        read -p "set up 1Panel Security entrance (default $DEFAULT_ENTRANCE）：" PANEL_ENTRANCE
        if [[ "$PANEL_ENTRANCE" == "" ]]; then
            PANEL_ENTRANCE=$DEFAULT_ENTRANCE
        fi

        if [[ ! "$PANEL_ENTRANCE" =~ ^[a-zA-Z0-9_]{3,30}$ ]]; then
            log "Error: The safe entrance of the panel only supports letters, numbers, down lines, length 3-30 Bit"
            continue
        fi

        log "The security entrance you set is:$PANEL_ENTRANCE"
        break
    done
}

function Set_Username() {
    DEFAULT_USERNAME=$(cat /dev/urandom | head -n 16 | md5sum | head -c 10)

    while true; do
        read -p "set up 1Panel Panel user (default $DEFAULT_USERNAME）：" PANEL_USERNAME

        if [[ "$PANEL_USERNAME" == "" ]]; then
            PANEL_USERNAME=$DEFAULT_USERNAME
        fi

        if [[ ! "$PANEL_USERNAME" =~ ^[a-zA-Z0-9_]{3,30}$ ]]; then
            log "Error: panel users only support letters, numbers, and lower lines, 3-30 bits in length"
            continue
        fi

        log "The panel users you set are:$PANEL_USERNAME"
        break
    done
}

function passwd() {
    charcount='0'
    reply=''
    while :; do
        char=$(
            stty cbreak -echo
            dd if=/dev/tty bs=1 count=1 2>/dev/null
            stty -cbreak echo
        )
        case $char in
        "$(printenv '\000')")
            break
            ;;
        "$(printf '\177')" | "$(printf '\b')")
            if [ $charcount -gt 0 ]; then
                printf '\b \b'
                reply="${reply%?}"
                charcount=$((charcount - 1))
            else
                printf ''
            fi
            ;;
        "$(printf '\033')") ;;
        *)
            printf '*'
            reply="${reply}${char}"
            charcount=$((charcount + 1))
            ;;
        esac
    done
    printf '\n' >&2
}

function Set_Password() {
    DEFAULT_PASSWORD=$(cat /dev/urandom | head -n 16 | md5sum | head -c 10)

    while true; do
        log "Set the 1Panel panel password, and return directly to the car after the setting is completed to continue (default $DEFAULT_PASSWORD）："
        passwd
        PANEL_PASSWORD=$reply
        if [[ "$PANEL_PASSWORD" == "" ]]; then
            PANEL_PASSWORD=$DEFAULT_PASSWORD
        fi

        if [[ ! "$PANEL_PASSWORD" =~ ^[a-zA-Z0-9_!@#$%*,.?]{8,30}$ ]]; then
            log "Error: The panel password only supports letters, numbers, special characters (!@#$%*_ ,.?), 8-30 bits"
            continue
        fi

        break
    done
}

function Init_Panel() {
    log "Configuration 1Panel Service"

    RUN_BASE_DIR=$PANEL_BASE_DIR/1panel
    mkdir -p "$RUN_BASE_DIR"
    rm -rf "$RUN_BASE_DIR:?/*"

    cd "${CURRENT_DIR}" || exit

    cp ./1panel /usr/local/bin && chmod +x /usr/local/bin/1panel
    if [[ ! -f /usr/bin/1panel ]]; then
        ln -s /usr/local/bin/1panel /usr/bin/1panel >/dev/null 2>&1
    fi

    cp ./1pctl /usr/local/bin && chmod +x /usr/local/bin/1pctl
    sed -i -e "s#BASE_DIR=.*#BASE_DIR=${PANEL_BASE_DIR}#g" /usr/local/bin/1pctl
    sed -i -e "s#ORIGINAL_PORT=.*#ORIGINAL_PORT=${PANEL_PORT}#g" /usr/local/bin/1pctl
    sed -i -e "s#ORIGINAL_USERNAME=.*#ORIGINAL_USERNAME=${PANEL_USERNAME}#g" /usr/local/bin/1pctl
    ESCAPED_PANEL_PASSWORD=$(echo "$PANEL_PASSWORD" | sed 's/[!@#$%*_,.?]/\\&/g')
    sed -i -e "s#ORIGINAL_PASSWORD=.*#ORIGINAL_PASSWORD=${ESCAPED_PANEL_PASSWORD}#g" /usr/local/bin/1pctl
    sed -i -e "s#ORIGINAL_ENTRANCE=.*#ORIGINAL_ENTRANCE=${PANEL_ENTRANCE}#g" /usr/local/bin/1pctl
    if [[ ! -f /usr/bin/1pctl ]]; then
        ln -s /usr/local/bin/1pctl /usr/bin/1pctl >/dev/null 2>&1
    fi

    cp ./1panel.service /etc/systemd/system

    systemctl enable 1panel
    systemctl daemon-reload 2>&1 | tee -a "${CURRENT_DIR}"/install.log

    log "Start the 1panel service"
    systemctl start 1panel | tee -a "${CURRENT_DIR}"/install.log

    for b in {1..30}; do
        sleep 3
        service_status=$(systemctl status 1panel 2>&1 | grep Active)
        if [[ $service_status == *running* ]]; then
            log "1Panel The service is successful!"
            break
        else
            log "1Panel The service starts errors!"
            exit 1
        fi
    done
    sed -i -e "s#ORIGINAL_PASSWORD=.*#ORIGINAL_PASSWORD=\*\*\*\*\*\*\*\*\*\*#g" /usr/local/bin/1pctl
}

function Get_Ip() {
    active_interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $5}')
    if [[ -z $active_interface ]]; then
        LOCAL_IP="127.0.0.1"
    else
        LOCAL_IP=$(ip -4 addr show dev "$active_interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    fi

    PUBLIC_IP=$(curl -s https://api64.ipify.org)
    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP="N/A"
    fi
    if echo "$PUBLIC_IP" | grep -q ":"; then
        PUBLIC_IP=[${PUBLIC_IP}]
        1pctl listen-ip ipv6
    fi
}

function Show_Result() {
    log ""
    log "=================Thank you for your patience, the installation has been completed=================="
    log ""
    log "Please use the browser to access the panel:"
    log "External network address: http://$PUBLIC_IP:$PANEL_PORT/$PANEL_ENTRANCE"
    log "Intranet address: http://$LOCAL_IP:$PANEL_PORT/$PANEL_ENTRANCE"
    log "Panel user: $PANEL_USERNAME"
    log "Panel password: $PANEL_PASSWORD"
    log ""
    log "Project official website: https://1panel.cn"
    log "Project documentation: https://1panel.cn/docs"
    log "Code warehouse: https://github.com/1Panel-dev/1Panel"
    log ""
    log "If you use the cloud server, please go to the security group to open $PANEL_PORT port"
    log ""
    log "For your server security, you will not be able to see your password after you leave this interface, please keep your password in mind."
    log ""
    log "================================================================"
}

function main() {
    Check_Root
    Prepare_System
    Set_Dir
    Install_Docker
    Install_Compose
    Set_Port
    Set_Firewall
    Set_Entrance
    Set_Username
    Set_Password
    Init_Panel
    Get_Ip
    Show_Result
}
main
