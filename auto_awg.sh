#!/bin/sh
set -e  # exit on error

# ────────── GLOBAL SETTINGS — change if needed ──────────
echo "→ Reading Git credentials and URL from /etc/auto_awg_git.conf"
if [ -f /etc/auto_awg_git.conf ]; then
    export $(cat /etc/auto_awg_git.conf | xargs)
    echo "   ✓ Credentials loaded"
    echo "   GIT_TOKEN: $GIT_TOKEN"
    echo "   REPO_RAW_URL: $REPO_RAW_URL"
else
    echo "✖️  No /etc/auto_awg_git.conf found with credentials"
    exit 1
fi

# ────────── FETCHING CONFIG ──────────
echo "→ Fetching awg.conf from GitHub"
TMP_CONF="/tmp/awg.conf"
if ! curl -H "Authorization: token $GIT_TOKEN" -sSfL "$REPO_RAW_URL" -o "$TMP_CONF"; then
    echo "✖️  Failed to download awg.conf"
    exit 1
else
    echo "   ✓ awg.conf downloaded successfully"
fi

# ────────── PARSING CONFIG ──────────
echo "→ Parsing awg.conf"

clean() {
    sed 's/\r//;s/^ *//;s/ *$//'
}

# Parse configuration values
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

# Sanity check to ensure all required fields are present
for v in AWG_PRIVATE_KEY AWG_PUBLIC_KEY AWG_IP AWG_ENDPOINT AWG_ENDPOINT_PORT AWG_JC; do
    [ -z "$(eval echo \\$$v)" ] && { echo "✖️  $v not found in awg.conf"; exit 1; }
done
echo "   ✓ awg.conf parsed OK"

# ────────── CONFIGURING AWG0 ──────────
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

if ! uci show network | grep -q amneziawg_awg0; then 
    uci add network amneziawg_awg0
fi

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

# ────────── RESTART NETWORK ──────────
echo "→ Restarting network"
/etc/init.d/network restart

echo "✔️  AmneziaWG setup completed"
