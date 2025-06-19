#!/bin/sh

#set -x

check_repo() {
    printf "\033[32;1mChecking OpenWrt repo availability...\033[0m\n"
    opkg update | grep -q "Failed to download" && printf "\033[32;1mopkg failed. Check internet or date. Command for force ntp sync: ntpd -p ptbtime1.ptb.de\033[0m\n" && exit 1
}

route_vpn() {
cat << EOF > /etc/hotplug.d/iface/30-vpnroute
#!/bin/sh

ip route add table vpn default dev awg0
EOF

    cp /etc/hotplug.d/iface/30-vpnroute /etc/hotplug.d/net/30-vpnroute
}

add_mark() {
    grep -q "99 vpn" /etc/iproute2/rt_tables || echo '99 vpn' >> /etc/iproute2/rt_tables
    
    if ! uci show network | grep -q mark0x1; then
        printf "\033[32;1mConfigure mark rule\033[0m\n"
        uci add network rule
        uci set network.@rule[-1].name='mark0x1'
        uci set network.@rule[-1].mark='0x1'
        uci set network.@rule[-1].priority='100'
        uci set network.@rule[-1].lookup='vpn'
        uci commit
    fi
}

load_awg_config() {
    if [ ! -f "/etc/auto_awg_git.conf" ]; then
        printf "\033[31;1mConfig file /etc/auto_awg_git.conf not found!\033[0m\n"
        exit 1
    fi

    printf "\033[32;1mLoading AWG configuration from GitHub...\033[0m\n"
    
    # Load configuration variables
    source /etc/auto_awg_git.conf
    
    if [ -z "$GIT_TOKEN" ] || [ -z "$REPO_RAW_URL" ]; then
        printf "\033[31;1mGIT_TOKEN or REPO_RAW_URL not set in config file!\033[0m\n"
        exit 1
    fi

    # Download AWG config
    AWG_CONFIG_FILE="/tmp/awg.conf"
    if ! curl -H "Authorization: token $GIT_TOKEN" -o "$AWG_CONFIG_FILE" "$REPO_RAW_URL"; then
        printf "\033[31;1mFailed to download AWG config from GitHub!\033[0m\n"
        exit 1
    fi

    if [ ! -f "$AWG_CONFIG_FILE" ]; then
        printf "\033[31;1mAWG config file was not downloaded!\033[0m\n"
        exit 1
    fi

    printf "\033[32;1mAWG config downloaded successfully\033[0m\n"
}

parse_awg_config() {
    AWG_CONFIG_FILE="/tmp/awg.conf"
    
    if [ ! -f "$AWG_CONFIG_FILE" ]; then
        printf "\033[31;1mAWG config file not found!\033[0m\n"
        exit 1
    fi

    printf "\033[32;1mParsing AWG configuration...\033[0m\n"

    # Parse [Interface] section
    AWG_IP=$(awk '/^\[Interface\]$/,/^\[.*\]$/ { if(/^Address/) { gsub(/Address = /, ""); print; exit } }' "$AWG_CONFIG_FILE")
    AWG_PRIVATE_KEY=$(awk '/^\[Interface\]$/,/^\[.*\]$/ { if(/^PrivateKey/) { gsub(/PrivateKey = /, ""); print; exit } }' "$AWG_CONFIG_FILE")
    AWG_JC=$(awk '/^\[Interface\]$/,/^\[.*\]$/ { if(/^Jc/) { gsub(/Jc = /, ""); print; exit } }' "$AWG_CONFIG_FILE")
    AWG_JMIN=$(awk '/^\[Interface\]$/,/^\[.*\]$/ { if(/^Jmin/) { gsub(/Jmin = /, ""); print; exit } }' "$AWG_CONFIG_FILE")
    AWG_JMAX=$(awk '/^\[Interface\]$/,/^\[.*\]$/ { if(/^Jmax/) { gsub(/Jmax = /, ""); print; exit } }' "$AWG_CONFIG_FILE")
    AWG_S1=$(awk '/^\[Interface\]$/,/^\[.*\]$/ { if(/^S1/) { gsub(/S1 = /, ""); print; exit } }' "$AWG_CONFIG_FILE")
    AWG_S2=$(awk '/^\[Interface\]$/,/^\[.*\]$/ { if(/^S2/) { gsub(/S2 = /, ""); print; exit } }' "$AWG_CONFIG_FILE")
    AWG_H1=$(awk '/^\[Interface\]$/,/^\[.*\]$/ { if(/^H1/) { gsub(/H1 = /, ""); print; exit } }' "$AWG_CONFIG_FILE")
    AWG_H2=$(awk '/^\[Interface\]$/,/^\[.*\]$/ { if(/^H2/) { gsub(/H2 = /, ""); print; exit } }' "$AWG_CONFIG_FILE")
    AWG_H3=$(awk '/^\[Interface\]$/,/^\[.*\]$/ { if(/^H3/) { gsub(/H3 = /, ""); print; exit } }' "$AWG_CONFIG_FILE")
    AWG_H4=$(awk '/^\[Interface\]$/,/^\[.*\]$/ { if(/^H4/) { gsub(/H4 = /, ""); print; exit } }' "$AWG_CONFIG_FILE")

    # Parse [Peer] section
    AWG_PUBLIC_KEY=$(awk '/^\[Peer\]$/,/^\[.*\]$/ { if(/^PublicKey/) { gsub(/PublicKey = /, ""); print; exit } }' "$AWG_CONFIG_FILE")
    AWG_PRESHARED_KEY=$(awk '/^\[Peer\]$/,/^\[.*\]$/ { if(/^PresharedKey/) { gsub(/PresharedKey = /, ""); print; exit } }' "$AWG_CONFIG_FILE")
    AWG_ENDPOINT_FULL=$(awk '/^\[Peer\]$/,/^\[.*\]$/ { if(/^Endpoint/) { gsub(/Endpoint = /, ""); print; exit } }' "$AWG_CONFIG_FILE")
    
    # Parse endpoint host and port
    AWG_ENDPOINT=$(echo "$AWG_ENDPOINT_FULL" | cut -d':' -f1)
    AWG_ENDPOINT_PORT=$(echo "$AWG_ENDPOINT_FULL" | cut -d':' -f2)

    # Validate parsed values
    if [ -z "$AWG_IP" ] || [ -z "$AWG_PRIVATE_KEY" ] || [ -z "$AWG_PUBLIC_KEY" ] || [ -z "$AWG_ENDPOINT" ]; then
        printf "\033[31;1mFailed to parse required AWG configuration values!\033[0m\n"
        exit 1
    fi

    printf "\033[32;1mAWG configuration parsed successfully\033[0m\n"
    printf "\033[33;1mAddress: $AWG_IP\033[0m\n"
    printf "\033[33;1mEndpoint: $AWG_ENDPOINT:$AWG_ENDPOINT_PORT\033[0m\n"
    
    # Clean up temporary file
    rm -f "$AWG_CONFIG_FILE"
}

install_awg_packages() {
    # Получение pkgarch с наибольшим приоритетом
    PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')

    TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 1)
    SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 2)
    VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
    PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
    BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"

    AWG_DIR="/tmp/amneziawg"
    mkdir -p "$AWG_DIR"

    if opkg list-installed | grep -q amneziawg-tools; then
        echo "amneziawg-tools already installed"
    else
        AMNEZIAWG_TOOLS_FILENAME="amneziawg-tools${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${AMNEZIAWG_TOOLS_FILENAME}"
        curl -L -o "$AWG_DIR/$AMNEZIAWG_TOOLS_FILENAME" "$DOWNLOAD_URL"

        if [ $? -eq 0 ]; then
            echo "amneziawg-tools file downloaded successfully"
        else
            echo "Error downloading amneziawg-tools. Please, install amneziawg-tools manually and run the script again"
            exit 1
        fi

        opkg install "$AWG_DIR/$AMNEZIAWG_TOOLS_FILENAME"

        if [ $? -eq 0 ]; then
            echo "amneziawg-tools file downloaded successfully"
        else
            echo "Error installing amneziawg-tools. Please, install amneziawg-tools manually and run the script again"
            exit 1
        fi
    fi
    
    if opkg list-installed | grep -q kmod-amneziawg; then
        echo "kmod-amneziawg already installed"
    else
        KMOD_AMNEZIAWG_FILENAME="kmod-amneziawg${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${KMOD_AMNEZIAWG_FILENAME}"
        curl -L -o "$AWG_DIR/$KMOD_AMNEZIAWG_FILENAME" "$DOWNLOAD_URL"

        if [ $? -eq 0 ]; then
            echo "kmod-amneziawg file downloaded successfully"
        else
            echo "Error downloading kmod-amneziawg. Please, install kmod-amneziawg manually and run the script again"
            exit 1
        fi
        
        opkg install "$AWG_DIR/$KMOD_AMNEZIAWG_FILENAME"

        if [ $? -eq 0 ]; then
            echo "kmod-amneziawg file downloaded successfully"
        else
            echo "Error installing kmod-amneziawg. Please, install kmod-amneziawg manually and run the script again"
            exit 1
        fi
    fi
    
    if opkg list-installed | grep -q luci-app-amneziawg; then
        echo "luci-app-amneziawg already installed"
    else
        LUCI_APP_AMNEZIAWG_FILENAME="luci-app-amneziawg${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${LUCI_APP_AMNEZIAWG_FILENAME}"
        curl -L -o "$AWG_DIR/$LUCI_APP_AMNEZIAWG_FILENAME" "$DOWNLOAD_URL"

        if [ $? -eq 0 ]; then
            echo "luci-app-amneziawg file downloaded successfully"
        else
            echo "Error downloading luci-app-amneziawg. Please, install luci-app-amneziawg manually and run the script again"
            exit 1
        fi

        opkg install "$AWG_DIR/$LUCI_APP_AMNEZIAWG_FILENAME"

        if [ $? -eq 0 ]; then
            echo "luci-app-amneziawg file downloaded successfully"
        else
            echo "Error installing luci-app-amneziawg. Please, install luci-app-amneziawg manually and run the script again"
            exit 1
        fi
    fi

    rm -rf "$AWG_DIR"
}

configure_amneziawg() {
    printf "\033[32;1mConfigure Amnezia WireGuard\033[0m\n"

    # Load and parse AWG configuration from GitHub
    load_awg_config
    parse_awg_config

    install_awg_packages

    route_vpn

    # Use parsed configuration instead of manual input
    printf "\033[32;1mConfiguring AWG interface with loaded settings...\033[0m\n"
    
    uci set network.awg0=interface
    uci set network.awg0.proto='amneziawg'
    uci set network.awg0.private_key="$AWG_PRIVATE_KEY"
    uci set network.awg0.listen_port='51820'
    uci set network.awg0.addresses="$AWG_IP"

    uci set network.awg0.awg_jc="$AWG_JC"
    uci set network.awg0.awg_jmin="$AWG_JMIN"
    uci set network.awg0.awg_jmax="$AWG_JMAX"
    uci set network.awg0.awg_s1="$AWG_S1"
    uci set network.awg0.awg_s2="$AWG_S2"
    uci set network.awg0.awg_h1="$AWG_H1"
    uci set network.awg0.awg_h2="$AWG_H2"
    uci set network.awg0.awg_h3="$AWG_H3"
    uci set network.awg0.awg_h4="$AWG_H4"

    if ! uci show network | grep -q amneziawg_awg0; then
        uci add network amneziawg_awg0
    fi

    uci set network.@amneziawg_awg0[0]=amneziawg_awg0
    uci set network.@amneziawg_awg0[0].name='awg0_client'
    uci set network.@amneziawg_awg0[0].public_key="$AWG_PUBLIC_KEY"
    uci set network.@amneziawg_awg0[0].preshared_key="$AWG_PRESHARED_KEY"
    uci set network.@amneziawg_awg0[0].route_allowed_ips='0'
    uci set network.@amneziawg_awg0[0].persistent_keepalive='25'
    uci set network.@amneziawg_awg0[0].endpoint_host="$AWG_ENDPOINT"
    uci set network.@amneziawg_awg0[0].allowed_ips='0.0.0.0/0'
    uci set network.@amneziawg_awg0[0].endpoint_port="$AWG_ENDPOINT_PORT"
    uci commit
}

dnsmasqfull() {
    if opkg list-installed | grep -q dnsmasq-full; then
        printf "\033[32;1mdnsmasq-full already installed\033[0m\n"
    else
        printf "\033[32;1mInstalled dnsmasq-full\033[0m\n"
        cd /tmp/ && opkg download dnsmasq-full
        opkg remove dnsmasq && opkg install dnsmasq-full --cache /tmp/

        [ -f /etc/config/dhcp-opkg ] && cp /etc/config/dhcp /etc/config/dhcp-old && mv /etc/config/dhcp-opkg /etc/config/dhcp
    fi
}

dnsmasqconfdir() {
    if [ $VERSION_ID -ge 24 ]; then
        if uci get dhcp.@dnsmasq[0].confdir | grep -q /tmp/dnsmasq.d; then
            printf "\033[32;1mconfdir already set\033[0m\n"
        else
            printf "\033[32;1mSetting confdir\033[0m\n"
            uci set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
            uci commit dhcp
        fi
    fi
}

add_zone() {
    if uci show firewall | grep -q "@zone.*name='awg'"; then
        printf "\033[32;1mZone already exist\033[0m\n"
    else
        printf "\033[32;1mCreate zone\033[0m\n"

        # Delete existing zones
        zone_awg_id=$(uci show firewall | grep -E '@zone.*awg0' | awk -F '[][{}]' '{print $2}' | head -n 1)
        if [ "$zone_awg_id" == 0 ] || [ "$zone_awg_id" == 1 ]; then
            printf "\033[32;1mawg0 zone has an identifier of 0 or 1. That's not ok. Fix your firewall. lan and wan zones should have identifiers 0 and 1. \033[0m\n"
            exit 1
        fi
        if [ ! -z "$zone_awg_id" ]; then
            while uci -q delete firewall.@zone[$zone_awg_id]; do :; done
        fi

        uci add firewall zone
        uci set firewall.@zone[-1].name="awg"
        uci set firewall.@zone[-1].network='awg0'
        uci set firewall.@zone[-1].forward='REJECT'
        uci set firewall.@zone[-1].output='ACCEPT'
        uci set firewall.@zone[-1].input='REJECT'
        uci set firewall.@zone[-1].masq='1'
        uci set firewall.@zone[-1].mtu_fix='1'
        uci set firewall.@zone[-1].family='ipv4'
        uci commit firewall
    fi
    
    if uci show firewall | grep -q "@forwarding.*name='awg-lan'"; then
        printf "\033[32;1mForwarding already configured\033[0m\n"
    else
        printf "\033[32;1mConfigured forwarding\033[0m\n"
        
        uci add firewall forwarding
        uci set firewall.@forwarding[-1]=forwarding
        uci set firewall.@forwarding[-1].name="awg-lan"
        uci set firewall.@forwarding[-1].dest="awg"
        uci set firewall.@forwarding[-1].src='lan'
        uci set firewall.@forwarding[-1].family='ipv4'
        uci commit firewall
    fi
}

add_set() {
    if uci show firewall | grep -q "@ipset.*name='vpn_domains'"; then
        printf "\033[32;1mSet already exist\033[0m\n"
    else
        printf "\033[32;1mCreate set\033[0m\n"
        uci add firewall ipset
        uci set firewall.@ipset[-1].name='vpn_domains'
        uci set firewall.@ipset[-1].match='dst_net'
        uci commit
    fi
    if uci show firewall | grep -q "@rule.*name='mark_domains'"; then
        printf "\033[32;1mRule for set already exist\033[0m\n"
    else
        printf "\033[32;1mCreate rule set\033[0m\n"
        uci add firewall rule
        uci set firewall.@rule[-1]=rule
        uci set firewall.@rule[-1].name='mark_domains'
        uci set firewall.@rule[-1].src='lan'
        uci set firewall.@rule[-1].dest='*'
        uci set firewall.@rule[-1].proto='all'
        uci set firewall.@rule[-1].ipset='vpn_domains'
        uci set firewall.@rule[-1].set_mark='0x1'
        uci set firewall.@rule[-1].target='MARK'
        uci set firewall.@rule[-1].family='ipv4'
        uci commit
    fi
}

add_packages() {
    for package in curl nano; do
        if opkg list-installed | grep -q "^$package "; then
            printf "\033[32;1m$package already installed\033[0m\n"
        else
            printf "\033[32;1mInstalling $package...\033[0m\n"
            opkg install "$package"
            
            if "$package" --version >/dev/null 2>&1; then
                printf "\033[32;1m$package was successfully installed and available\033[0m\n"
            else
                printf "\033[31;1mError: failed to install $package\033[0m\n"
                exit 1
            fi
        fi
    done
}


# System Details
MODEL=$(cat /tmp/sysinfo/model)
source /etc/os-release
printf "\033[34;1mModel: $MODEL\033[0m\n"
printf "\033[34;1mVersion: $OPENWRT_RELEASE\033[0m\n"

VERSION_ID=$(echo $VERSION | awk -F. '{print $1}')

if [ "$VERSION_ID" -ne 23 ] && [ "$VERSION_ID" -ne 24 ]; then
    printf "\033[31;1mScript only support OpenWrt 23.05 and 24.10\033[0m\n"
    echo "For OpenWrt 21.02 and 22.03 you can:"
    echo "1) Use ansible https://github.com/itdoginfo/domain-routing-openwrt"
    echo "2) Configure manually. Old manual: https://itdog.info/tochechnaya-marshrutizaciya-na-routere-s-openwrt-wireguard-i-dnscrypt/"
    exit 1
fi

printf "\033[31;1mAll actions performed here cannot be rolled back automatically.\033[0m\n"
printf "\033[32;1mThis script will configure your router for AmneziaWG only.\033[0m\n"

check_repo

add_packages

configure_amneziawg

add_mark

add_zone

add_set

dnsmasqfull

dnsmasqconfdir

printf "\033[32;1mRestart network\033[0m\n"
/etc/init.d/network restart

printf "\033[32;1mDone\033[0m\n"
