#!/bin/bash

set -e

# ================== CONFIG ==================

# Ports
export T_PORT=${T_PORT:-""}
export H_PORT=${H_PORT:-""}
export R_PORT=${R_PORT:-""}

# Identity & Auth
export S_ID=${S_ID:-""}
export T_PASS=${T_PASS:-"admin"}
export H_PASS=${H_PASS:-""}

# Reality Settings
export R_DOM=${R_DOM:-"www.nazhumi.com"}
export R_DOM_P=${R_DOM_P:-""}

# Core
export BIN_V=${BIN_V:-""} 
export ID_PRE=${ID_PRE:-"Srv"}
export LOG_ON=${LOG_ON:-"false"}

# Remote Res
export REM_ON=${REM_ON:-"true"}
export REM_C=${REM_C:-""}
export REM_K=${REM_K:-""}

# Timezone
if [ -n "$TZ" ]; then
    cp /usr/share/zoneinfo/"$TZ" /etc/localtime 2>/dev/null || true
    echo "$TZ" > /etc/timezone 2>/dev/null || true
fi

# ================== SETUP ==================

export W_DIR="/data"
mkdir -p "$W_DIR"

M_FILE="${W_DIR}/.m"
L_FILE="${W_DIR}/s.log"

if [[ -z "$T_PORT" && -z "$H_PORT" && -z "$R_PORT" ]]; then
  exit 1
fi

# ================== BINARY ==================

get_v() {
  local u=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/SagerNet/sing-box/releases/latest)
  local v=""
  if [ -n "$u" ]; then
    v=$(echo "$u" | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" | sed 's/v//' || true)
  fi
  if [ -z "$v" ]; then echo "1.10.7"; else echo "$v"; fi
}

if [ -z "$BIN_V" ]; then BIN_V=$(get_v); fi

AR_R=$(uname -m)
case "${AR_R}" in
    x86_64|amd64) SYS_A="amd64" ;;
    aarch64|arm64) SYS_A="arm64" ;;
    s390x) SYS_A="s390x" ;;
    *) exit 1 ;;
esac

load_bin() {
  local I_VER=""
  local B_NAM=""
  if [ -f "$M_FILE" ]; then source "$M_FILE"; fi
  local B_PATH="${W_DIR}/${B_NAM}"

  if [ "$I_VER" != "$BIN_V" ] || [ -z "$B_NAM" ] || [ ! -f "$B_PATH" ]; then
    if [ -n "$B_NAM" ]; then rm -f "$B_PATH"; fi
    
    local U="https://github.com/SagerNet/sing-box/releases/download/v${BIN_V}/sing-box-${BIN_V}-linux-${SYS_A}.tar.gz"
    local T="${W_DIR}/p.tgz"
    
    if command -v curl >/dev/null; then curl -L -sS -o "$T" "$U"; else wget -q -O "$T" "$U"; fi
    
    local T_DIR="${W_DIR}/t_ext"
    mkdir -p "$T_DIR"
    tar -xzf "$T" -C "$T_DIR"
    rm "$T"
    
    local F=$(find "$T_DIR" -type f -name "sing-box" | head -n 1)
    if [ -z "$F" ]; then rm -rf "$T_DIR"; exit 1; fi
    
    local N_NAM="x$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
    mv "$F" "${W_DIR}/${N_NAM}"
    chmod +x "${W_DIR}/${N_NAM}"
    rm -rf "$T_DIR"
    
    echo "I_VER=${BIN_V}" > "$M_FILE"
    echo "B_NAM=${N_NAM}" >> "$M_FILE"
    RUN_BIN="${W_DIR}/${N_NAM}"
  else
    RUN_BIN="${W_DIR}/${B_NAM}"
  fi
}

load_bin

# ================== AUTH ==================

U_FILE="${W_DIR}/u.dat"

# Priority: ENV > File > Generate
if [ -n "$S_ID" ]; then
  UUID="$S_ID"
  echo "$UUID" > "$U_FILE"
elif [ -f "$U_FILE" ]; then
  UUID=$(cat "$U_FILE")
else
  UUID=$("$RUN_BIN" generate uuid 2>/dev/null)
  if [ -z "$UUID" ] && [ -f /proc/sys/kernel/random/uuid ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
  fi
  if [ -z "$UUID" ] && command -v uuidgen >/dev/null; then
    UUID=$(uuidgen)
  fi
  echo "$UUID" > "$U_FILE"
fi

if [ -z "$H_PASS" ]; then H_PASS="$UUID"; fi

K_FILE="${W_DIR}/k.dat"
if [ -f "$K_FILE" ]; then
  P_KEY=$(grep "PrivateKey:" "$K_FILE" | awk '{print $2}')
  PUB_K=$(grep "PublicKey:" "$K_FILE" | awk '{print $2}')
else
  kout=$("$RUN_BIN" generate reality-keypair)
  echo "$kout" > "$K_FILE"
  P_KEY=$(echo "$kout" | awk '/PrivateKey:/ {print $2}')
  PUB_K=$(echo "$kout" | awk '/PublicKey:/ {print $2}')
fi

# ================== SEC ==================

C_PEM="${W_DIR}/c.pem"
K_PEM="${W_DIR}/k.key"

sec_check() {
  local TC="${W_DIR}/tc.tmp"
  local TK="${W_DIR}/tk.tmp"
  local OK=0

  if [ "$REM_ON" == "true" ]; then
    for i in {1..2}; do
      if curl -L -sS -o "$TC" "$REM_C" && curl -L -sS -o "$TK" "$REM_K"; then
        if [ -s "$TC" ] && [ -s "$TK" ]; then
          mv -f "$TC" "$C_PEM"
          mv -f "$TK" "$K_PEM"
          chmod 600 "$K_PEM"
          OK=1
          break
        fi
      fi
      [ $i -lt 2 ] && sleep 1
    done
    rm -f "$TC" "$TK"
    if [ $OK -eq 1 ]; then return; fi
  fi

  if [ -s "$C_PEM" ] && [ -s "$K_PEM" ]; then return; fi

  local P=$("$RUN_BIN" generate tls-keypair bing.com 2>/dev/null)
  echo "$P" | awk '/BEGIN PRIVATE KEY/,/END PRIVATE KEY/' > "$K_PEM"
  echo "$P" | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > "$C_PEM"
  chmod 600 "$K_PEM"
}

sec_check

# ================== CONF ==================

TMP_J="${W_DIR}/t.json"
> "$TMP_J"

add_s() {
  if [ -s "$TMP_J" ]; then echo "," >> "$TMP_J"; fi
}

if [ -n "$T_PORT" ] && [ "$T_PORT" != "0" ]; then
  cat >> "$TMP_J" <<EOF
    {
      "type": "tuic",
      "tag": "t-in",
      "listen": "::",
      "listen_port": $T_PORT,
      "users": [{"uuid": "$UUID", "password": "$T_PASS"}],
      "congestion_control": "bbr",
      "tls": {"enabled": true, "alpn": ["h3"], "certificate_path": "$C_PEM", "key_path": "$K_PEM"}
    }
EOF
fi

if [ -n "$H_PORT" ] && [ "$H_PORT" != "0" ]; then
  add_s
  cat >> "$TMP_J" <<EOF
    {
      "type": "hysteria2",
      "tag": "h-in",
      "listen": "::",
      "listen_port": $H_PORT,
      "users": [{"password": "$H_PASS"}],
      "masquerade": "https://bing.com",
      "tls": {"enabled": true, "alpn": ["h3"], "certificate_path": "$C_PEM", "key_path": "$K_PEM"}
    }
EOF
fi

if [ -n "$R_PORT" ] && [ "$R_PORT" != "0" ]; then
  add_s
  cat >> "$TMP_J" <<EOF
    {
      "type": "vless",
      "tag": "r-in",
      "listen": "::",
      "listen_port": $R_PORT,
      "users": [{"uuid": "$UUID", "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": "$R_DOM",
        "reality": {
          "enabled": true,
          "handshake": {"server": "$R_DOM", "server_port": $R_DOM_P},
          "private_key": "$P_KEY",
          "short_id": [""]
        }
      }
    }
EOF
fi

if [ "$LOG_ON" == "true" ]; then
  LB="\"log\": { \"disabled\": false, \"level\": \"info\", \"output\": \"$L_FILE\" },"
else
  LB="\"log\": { \"disabled\": true },"
fi

FINAL_C="${W_DIR}/c.json"
cat > "$FINAL_C" <<EOF
{
  $LB
  "inbounds": [
$(cat "$TMP_J")
  ],
  "outbounds": [{"type": "direct"}]
}
EOF
rm "$TMP_J"

# ================== EXEC ==================

"$RUN_BIN" run -c "$FINAL_C" >/dev/null 2>&1 &
PID=$!

# ================== EXPORT ==================

HIP=$(curl -s --max-time 3 ipv4.ip.sb || echo "0.0.0.0")
EXP="${W_DIR}/e.dat"
> "$EXP"

if [ -n "$T_PORT" ] && [ "$T_PORT" != "0" ]; then
  echo "tuic://${UUID}:${T_PASS}@${HIP}:${T_PORT}?sni=bing.com&alpn=h3&congestion_control=bbr&allowInsecure=1#${ID_PRE}-T" >> "$EXP"
fi
if [ -n "$H_PORT" ] && [ "$H_PORT" != "0" ]; then
  echo "hysteria2://${H_PASS}@${HIP}:${H_PORT}/?sni=bing.com&insecure=1#${ID_PRE}-H" >> "$EXP"
fi
if [ -n "$R_PORT" ] && [ "$R_PORT" != "0" ]; then
  echo "vless://${UUID}@${HIP}:${R_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${R_DOM}&fp=firefox&pbk=${PUB_K}&type=tcp#${ID_PRE}-R" >> "$EXP"
fi

if [ -s "$EXP" ]; then
    B64=$(base64 "$EXP" | tr -d '\n')
    echo "$B64" > "${W_DIR}/tk.b64"
    echo -e "\n=== DATA START ===\n$B64\n=== DATA END ==="
fi

# ================== LOOP ==================

loop_svc() {
  local LD=-1
  local RC=0
  local MR=5

  while true; do
    if [ -f "$L_FILE" ]; then
      local FS=$(stat -c%s "$L_FILE" 2>/dev/null || echo 0)
      if [ "$FS" -gt 5242880 ]; then echo "." > "$L_FILE"; fi
    fi

    if ! kill -0 "$PID" > /dev/null 2>&1; then
      if [ "$RC" -ge "$MR" ]; then exit 1; fi
      sleep 3
      "$RUN_BIN" run -c "$FINAL_C" >/dev/null 2>&1 &
      PID=$!
      ((RC++))
    else
      RC=0
    fi

    if date -u >/dev/null 2>&1; then
        H=$(date +%H); M=$(date +%M); D=$(date +%d)
    else
        NOW=$(date +%s); BJT=$((NOW + 28800))
        H=$(( (BJT / 3600) % 24 ))
        M=$(( (BJT / 60) % 60 ))
        D=$(( BJT / 86400 ))
    fi

    if [ "$H" -eq 02 ] && [ "$M" -eq 20 ] && [ "$D" -ne "$LD" ]; then
      LD=$D
      kill "$PID" 2>/dev/null || true
      sleep 2
    fi
    
    sleep 10
  done
}

loop_svc
