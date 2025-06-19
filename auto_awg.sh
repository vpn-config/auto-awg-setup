#!/bin/sh
set -e  # exit on error

# ────────── GLOBAL SETTINGS — change if needed ──────────
echo "→ Reading Git credentials and URL from /etc/auto_awg_git.conf"
[ -f /etc/auto_awg_git.conf ] && . /etc/auto_awg_git.conf || {
    echo "✖️  No /etc/auto_awg_git.conf found with credentials"; exit 1;
}

echo "→ Fetching awg.conf from GitHub"
TMP_CONF="/tmp/awg.conf"
CURL_OPTS="-sSfL"
[ -n "$GIT_TOKEN" ] && CURL_OPTS="-H Authorization:token $GIT_TOKEN $CURL_OPTS"

# download the config
if ! curl $CURL_OPTS "$REPO_RAW_URL" -o "$TMP_CONF"; then
    echo "✖️  Failed to download awg.conf"; exit 1;
else
    echo "   ✓ awg.conf downloaded successfully"
fi

# parse key-value pairs (remove CR, spaces)
echo "→ Parsing awg.conf"
clean() { sed 's/\r//;s/^ *//;s/ *$//'; }
AWG_PRIVATE_KEY=$(grep -E '^PrivateKey' "$TMP_CONF" | cut -d= -f2 | clean)
AWG_IP=$(grep -E '^Address' "$TMP_CONF" | cut -d= -f2 | clean)
ENDPOINT_LINE=$(grep -E '^Endpoint' "$TMP_CONF" | cut -d= -f2 | clean)
AWG_ENDPOINT=${ENDPOINT_LINE%:*}
AWG_ENDPOINT_PORT=${ENDPOINT_LINE#*:}
AWG_PUBLIC_KEY=$(grep -E '^PublicKey' "$TMP_CONF" | cut -d= -f2 | clean)
AWG_PRESHARED_KEY=$(grep -E '^PresharedKey' "$TMP_CONF" | cut -d= -f2 | clean)
AWG_JC=$(grep -E '^Jc' "$TMP_CONF" | cut -d= -f2 | clean)
AWG_JMIN=$(grep -E '^Jmin' "$TMP_CONF" | cut -d= -f2 | clean)
AWG_JMAX=$(grep -E '^Jmax' "$TMP_CONF" | cut -d= -f2 | clean)
AWG_S1=$(grep -E '^S1' "$TMP_CONF" | cut -d= -f2 | clean)
AWG_S2=$(grep -E '^S2' "$TMP_CONF" | cut -d= -f2 | clean)
AWG_H1=$(grep -E '^H1' "$TMP_CONF" | cut -d= -f2 | clean)
AWG_H2=$(grep -E '^H2' "$TMP_CONF" | cut -d= -f2 | clean)
AWG_H3=$(grep -E '^H3' "$TMP_CONF" | cut -d= -f2 | clean)
AWG_H4=$(grep -E '^H4' "$TMP_CONF" | cut -d= -f2 | clean)

# sanity check
for v in AWG_PRIVATE_KEY AWG_PUBLIC_KEY AWG_IP AWG_ENDPOINT AWG_ENDPOINT_PORT AWG_JC; do
    [ -z "$(eval echo \\$$v)" ] && { echo "✖️  $v not found in awg.conf"; exit 1; }
done
echo "   ✓ awg.conf parsed OK"

echo "→ Installing AmneziaWG packages (if absent)"
PKGARCH=$(opkg print-architecture | awk 'BEGIN{m=0}{if($3>m){m=$3;a=$2}}END{print a}')
TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d/ -f1)
SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d/ -f2)
VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
SUFFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
BASE="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v${VERSION}"
for p in amneziawg-tools kmod-amneziawg luci-app-amneziawg; do
    opkg list-installed | grep -q $p && continue
    FILE="$p$SUFFIX"; URL="$BASE/$FILE"
    echo "   → downloading $FILE"
    curl -sSfL "$URL" -o "/tmp/$FILE"
    opkg install "/tmp/$FILE"
    rm -f "/tmp/$FILE"
done

echo "→ Configuring awg0 via UCI"
uci set network.awg0=interface
uci set network.awg0.proto='amneziawg'
uci set network.awg0.private_key="$AWG_PRIVATE_KEY"
uci set network.awg0.listen_port='51820'
uci set network.awg0.addresses="$AWG_IP"

uci set network.awg0.awg_jc=$AWG_JC
uci set network.awg0.awg_jmin=$AWG_JMIN
uci set network.awg0.awg_jmax=$AWG_JMAX
uci set network.awg0.awg_s1=$AWG_S1
uci set network.awg0.awg_s2=$AWG_S2
uci set network.awg0.awg_h1=$AWG_H1
uci set network.awg0.awg_h2=$AWG_H2
uci set network.awg0.awg_h3=$AWG_H3
uci set network.awg0.awg_h4=$AWG_H4

if ! uci show network | grep -q amneziawg_awg0; then uci add network amneziawg_awg0; fi
uci set network.@amneziawg_awg0[0]=amneziawg_awg0
uci set network.@amneziawg_awg0[0].name='awg0_client'
uci set network.@amneziawg_awg0[0].public_key="$AWG_PUBLIC_KEY"
[ -n "$AWG_PRESHARED_KEY" ] && uci set network.@amneziawg_awg0[0].preshared_key="$AWG_PRESHARED_KEY"
uci set network.@amneziawg_awg0[0].route_allowed_ips='0'
uci set network.@amneziawg_awg0[0].persistent_keepalive='25'
uci set network.@amneziawg_awg0[0].endpoint_host="$AWG_ENDPOINT"
uci set network.@amneziawg_awg0[0].allowed_ips='0.0.0.0/0'
uci set network.@amneziawg_awg0[0].endpoint_port="$AWG_ENDPOINT_PORT"
uci commit network

echo "→ Configuring firewall zone 'awg'"
if ! uci show firewall | grep -q "@zone.*name='awg'"; then
    uci add firewall zone
    uci set firewall.@zone[-1].name='awg'
    uci set firewall.@zone[-1].network='awg0'
    uci set firewall.@zone[-1].forward='REJECT'
    uci set firewall.@zone[-1].output='ACCEPT'
    uci set firewall.@zone[-1].input='REJECT'
    uci set firewall.@zone[-1].masq='1'
    uci set firewall.@zone[-1].mtu_fix='1'
    uci set firewall.@zone[-1].family='ipv4'
    uci commit firewall
fi

echo "→ Restarting network"
/etc/init.d/network restart

echo "✔️  AmneziaWG setup completed"
