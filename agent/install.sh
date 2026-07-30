#!/bin/sh
# aster-agent installer.
#
# Designed to be safe for someone who has never used Linux: pasting the same
# command twice is always fine — every run cleans up what previous runs left
# behind before doing anything. When something goes wrong the script diagnoses
# itself and prints the command that fixes it.
#
# Usage:
#   curl -fsSL <raw-url>/agent/install.sh | sudo sh -s -- --token <TOKEN>
#   ... --domain agent.example.com   hide the agent behind a real domain on 443
#   ... --status                     health report for this machine
#   ... --uninstall                  remove everything this script installed
#
#   --proxy caddy|nginx|auto   reverse proxy to use (default: auto-detect)
#   --cert /p --key /p         use an existing certificate instead of ACME
#   --force-ip                 go back to plain IP mode from domain mode
#   --listen <addr>            agent listen address (default :9977)
#   --lang zh|en               force the output language
#   --state-dir --version --repo --ghproxy --sha256      (advanced)
set -eu

REPO="maow318/astervps"
TOKEN=""
LISTEN=":9977"
STATE_DIR="/var/lib/aster-agent"
GHPROXY=""
VERSION="latest"
SHA256=""
DOMAIN=""
PROXY="auto"
CERT_PATH=""
KEY_PATH=""
FORCE_IP=0
UNINSTALL=0
STATUS=0
LANG_CHOICE=""

BIN=/usr/local/bin/aster-agent
SERVICE=aster-agent
CONF_DIR=/etc/aster-agent
TOKEN_FILE=$CONF_DIR/token
STATE_FILE=$CONF_DIR/config
NGINX_CONF=/etc/nginx/conf.d/aster-agent.conf
CADDYFILE=/etc/caddy/Caddyfile
PLIST=/Library/LaunchDaemons/cc.aster.agent.plist
DARWIN_LOG=/var/log/aster-agent.log

while [ "$#" -gt 0 ]; do
  case "$1" in
    --token) TOKEN="$2"; shift 2 ;;
    --listen) LISTEN="$2"; shift 2 ;;
    --state-dir) STATE_DIR="$2"; shift 2 ;;
    --ghproxy) GHPROXY="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --sha256) SHA256="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --proxy) PROXY="$2"; shift 2 ;;
    --cert) CERT_PATH="$2"; shift 2 ;;
    --key) KEY_PATH="$2"; shift 2 ;;
    --lang) LANG_CHOICE="$2"; shift 2 ;;
    --force-ip) FORCE_IP=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --status | --doctor) STATUS=1; shift ;;
    *) shift ;;
  esac
done

# TLS SNI and proxy site blocks are case-sensitive; DNS is not.
DOMAIN=$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')
AGENT_PORT="${LISTEN##*:}"

if [ -z "$LANG_CHOICE" ]; then
  case "${LC_ALL:-}${LC_MESSAGES:-}${LANG:-}" in
    *zh*) LANG_CHOICE=zh ;;
    *) LANG_CHOICE=en ;;
  esac
fi

say() { if [ "$LANG_CHOICE" = "zh" ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }
ok() { if [ "$LANG_CHOICE" = "zh" ]; then printf '  [OK] %s\n' "$1"; else printf '  [OK] %s\n' "$2"; fi; }
bad() { if [ "$LANG_CHOICE" = "zh" ]; then printf '  [!!] %s\n' "$1"; else printf '  [!!] %s\n' "$2"; fi; }
info() { if [ "$LANG_CHOICE" = "zh" ]; then printf '  [--] %s\n' "$1"; else printf '  [--] %s\n' "$2"; fi; }
line() { printf '%s\n' "$1"; }
fail() {
  if [ "$LANG_CHOICE" = "zh" ]; then printf '\n错误:%s\n' "$1" >&2; else printf '\nERROR: %s\n' "$2" >&2; fi
  exit 1
}

[ "$(id -u)" = 0 ] || fail "请用 root 运行(命令前面加 sudo)" "run as root (sudo)"

# ---- state: repeated runs must know what earlier runs did --------------------
SAVED_MODE=""; SAVED_DOMAIN=""; SAVED_PROXY=""; SAVED_LISTEN=""
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE" 2>/dev/null || true
  SAVED_MODE="${ASTER_MODE:-}"
  SAVED_DOMAIN="${ASTER_DOMAIN:-}"
  SAVED_PROXY="${ASTER_PROXY_KIND:-}"
  SAVED_LISTEN="${ASTER_LISTEN:-}"
fi

save_state() {
  mkdir -p "$CONF_DIR"
  cat > "$STATE_FILE" << EOF
ASTER_MODE=$1
ASTER_DOMAIN=$2
ASTER_PROXY_KIND=$3
ASTER_LISTEN=$4
EOF
  chmod 600 "$STATE_FILE"
  # Keep the in-memory view current so a diagnosis printed later in this same
  # run reports what we just configured instead of the pre-run state.
  SAVED_MODE="$1"; SAVED_DOMAIN="$2"; SAVED_PROXY="$3"; SAVED_LISTEN="$4"
}

# ---- proxy discovery --------------------------------------------------------
DOCKER_CADDY=""; DOCKER_NGINX=""
discover_docker() {
  command -v docker >/dev/null 2>&1 || return 0
  DOCKER_CADDY=$(docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null \
    | awk 'tolower($0) ~ /caddy/ {print $1; exit}') || true
  DOCKER_NGINX=$(docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null \
    | awk 'tolower($0) ~ /nginx|npm|proxy-manager/ {print $1; exit}') || true
}

docker_caddyfile() {
  docker inspect "$1" --format '{{range .Mounts}}{{.Destination}} {{.Source}}{{println}}{{end}}' 2>/dev/null \
    | awk '$1 == "/etc/caddy/Caddyfile" {print $2; exit}'
}

docker_gateway() {
  docker inspect "$1" --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{println}}{{end}}' 2>/dev/null \
    | awk 'NF {print; exit}'
}

public_ip() { curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || true; }

# Docker bind-mounts a single file by inode. `sed -i` writes a new file and
# renames it over the old one, which silently detaches the mount: the container
# keeps reading the original inode forever and every reload reports "config is
# unchanged". Editing through a temp file and truncating the original keeps the
# inode — and the mount — intact.
edit_inplace() { # <file> <sed expression>
  tmp="$1.aster-tmp"
  if sed "$2" "$1" > "$tmp" 2>/dev/null; then
    cat "$tmp" > "$1"
  fi
  rm -f "$tmp"
}

# ---- cleanup: pasting the command twice must never pile up config ----------
clean_proxy_blocks() {
  cleaned=0
  if [ -f "$CADDYFILE" ] && grep -q '# aster-agent begin' "$CADDYFILE" 2>/dev/null; then
    edit_inplace "$CADDYFILE" '/# aster-agent begin/,/# aster-agent end/d'
    systemctl reload caddy >/dev/null 2>&1 || true
    cleaned=1
  fi
  discover_docker
  if [ -n "$DOCKER_CADDY" ]; then
    mounted=$(docker_caddyfile "$DOCKER_CADDY")
    if [ -n "${mounted:-}" ] && grep -q '# aster-agent begin' "$mounted" 2>/dev/null; then
      edit_inplace "$mounted" '/# aster-agent begin/,/# aster-agent end/d'
      docker exec "$DOCKER_CADDY" caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 || true
      cleaned=1
    fi
  fi
  if [ -f "$NGINX_CONF" ]; then
    rm -f "$NGINX_CONF"
    systemctl reload nginx >/dev/null 2>&1 || true
    cleaned=1
  fi
  if [ "$cleaned" = 1 ]; then
    say "已清理上一次安装留下的反向代理配置" "cleaned up the proxy config from the previous run"
  fi
  return 0
}

stop_previous() {
  if [ "$(uname -s)" = "Darwin" ]; then
    if [ -f "$PLIST" ]; then
      launchctl bootout system "$PLIST" 2>/dev/null || true
      rm -f "$PLIST"
    fi
    return 0
  fi
  if command -v systemctl >/dev/null 2>&1 && [ -f "/etc/systemd/system/$SERVICE.service" ]; then
    systemctl stop "$SERVICE" 2>/dev/null || true
    systemctl disable "$SERVICE" 2>/dev/null || true
    rm -f "/etc/systemd/system/$SERVICE.service"
    systemctl daemon-reload
  elif command -v rc-service >/dev/null 2>&1 && [ -f "/etc/init.d/$SERVICE" ]; then
    rc-service "$SERVICE" stop 2>/dev/null || true
    rc-update del "$SERVICE" default 2>/dev/null || true
    rm -f "/etc/init.d/$SERVICE"
  fi
}

if [ "$UNINSTALL" = 1 ]; then
  stop_previous
  if [ "$(uname -s)" = "Linux" ]; then clean_proxy_blocks; fi
  rm -f "$BIN" "$TOKEN_FILE" "$STATE_FILE" /etc/cron.d/aster-certbot-renew
  rmdir "$CONF_DIR" 2>/dev/null || true
  say "已卸载 aster-agent(证书目录 $STATE_DIR 保留,可手动删除)" \
      "aster-agent uninstalled (TLS state dir $STATE_DIR kept)"
  exit 0
fi

# ---- doctor -----------------------------------------------------------------
caddy_globals_note() {
  [ -f "${1:-}" ] || return 0
  if grep -qE '^[[:space:]]*auto_https[[:space:]]+off' "$1" 2>/dev/null; then
    printf 'auto_https_off'
  elif grep -qE '^[[:space:]]*tls[[:space:]]+/' "$1" 2>/dev/null; then
    printf 'explicit_certs'
  fi
}

run_doctor() {
  CHECK_DOMAIN="${DOMAIN:-$SAVED_DOMAIN}"
  say "===== Aster 体检报告 =====" "===== Aster health report ====="

  if [ -x "$BIN" ]; then
    ok "agent 程序已安装" "agent binary installed"
  else
    bad "agent 程序未安装(请重跑安装命令)" "agent binary missing (re-run the installer)"
  fi
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
    ok "agent 服务正在运行" "agent service is running"
  elif pgrep -f "aster-agent --listen" >/dev/null 2>&1; then
    ok "agent 进程正在运行" "agent process is running"
  else
    bad "agent 没有运行 —— 修复命令:systemctl restart $SERVICE" \
        "agent is not running — fix: systemctl restart $SERVICE"
  fi

  if [ "$SAVED_MODE" = "domain" ]; then
    info "当前模式:域名模式($SAVED_DOMAIN,反代 $SAVED_PROXY,监听 $SAVED_LISTEN)" \
         "mode: domain ($SAVED_DOMAIN via $SAVED_PROXY, listening on $SAVED_LISTEN)"
  elif [ -n "$SAVED_MODE" ]; then
    info "当前模式:裸 IP 模式(监听 $SAVED_LISTEN)" "mode: direct IP (listening on $SAVED_LISTEN)"
  else
    info "没有找到安装记录" "no install record found"
  fi

  if [ -z "$CHECK_DOMAIN" ]; then
    say "" ""
    say "结论:裸 IP 模式,无需域名检查。在 Aster 里用 https://本机IP:$AGENT_PORT 添加即可。" \
        "Conclusion: direct IP mode. Add https://<server-ip>:$AGENT_PORT in Aster."
    return 0
  fi

  resolved=$(getent ahosts "$CHECK_DOMAIN" 2>/dev/null | awk '{print $1; exit}' || true)
  myip=$(public_ip)
  if [ -z "$resolved" ]; then
    bad "域名 $CHECK_DOMAIN 解析不到 —— 请在域名服务商添加 A 记录指向 ${myip:-本机公网IP}" \
        "$CHECK_DOMAIN does not resolve — add an A record pointing at ${myip:-this server}"
  elif [ -n "$myip" ] && [ "$resolved" = "$myip" ]; then
    ok "域名解析正确($resolved)" "DNS points at this server ($resolved)"
  else
    info "域名解析到 $resolved,本机公网 IP 是 ${myip:-未知}(用了 CDN 代理时属正常)" \
         "resolves to $resolved, server is ${myip:-unknown} (normal behind a CDN)"
  fi

  if command -v ss >/dev/null 2>&1; then
    if ss -ltn 2>/dev/null | grep -q ':443 '; then
      ok "443 端口有服务在监听" "something is listening on 443"
    else
      bad "没有服务监听 443 —— 反向代理没启动" "nothing listens on 443 — the reverse proxy is down"
    fi
    if ss -ltn 2>/dev/null | grep -q ':80 '; then
      ok "80 端口有服务在监听(自动签发证书需要)" "something is listening on 80 (needed for certificates)"
    else
      bad "没有服务监听 80 —— 证书无法自动签发" "nothing listens on 80 — certificates cannot be issued"
    fi
  fi

  discover_docker
  target=""
  if [ -n "$DOCKER_CADDY" ]; then
    target=$(docker_caddyfile "$DOCKER_CADDY")
    info "反向代理:Docker 里的 Caddy($DOCKER_CADDY),配置 ${target:-未知}" \
         "proxy: dockerized Caddy ($DOCKER_CADDY), config ${target:-unknown}"
  elif [ -f "$CADDYFILE" ]; then
    target="$CADDYFILE"
    info "反向代理:主机 Caddy($CADDYFILE)" "proxy: host Caddy ($CADDYFILE)"
  elif [ -f "$NGINX_CONF" ]; then
    target="$NGINX_CONF"
    info "反向代理:主机 nginx($NGINX_CONF)" "proxy: host nginx ($NGINX_CONF)"
  fi
  if [ -n "$target" ] && grep -q "$CHECK_DOMAIN" "$target" 2>/dev/null; then
    ok "反代配置里已包含该域名" "the proxy config contains the domain"
  else
    bad "反代配置里没有该域名 —— 重跑一次安装命令即可写入" \
        "the domain is missing from the proxy config — re-run the installer"
  fi

  if [ -n "$target" ]; then
    note=$(caddy_globals_note "$target")
    if [ "$note" = "auto_https_off" ]; then
      bad "你的 Caddy 配置里写了 auto_https off,它永远不会自动申请证书" \
          "your Caddy config sets auto_https off — it will never request a certificate"
      say "     修复:删掉那一行,或重跑安装命令时加上 --cert /证书路径 --key /私钥路径" \
          "     fix: remove that line, or re-run with --cert /path --key /path"
    elif [ "$note" = "explicit_certs" ]; then
      info "你的 Caddy 使用手动指定的证书,脚本会沿用同样的写法" \
           "your Caddy uses explicit certificates; the installer follows suit"
    fi
  fi

  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$CHECK_DOMAIN/v1/meta" 2>/dev/null || true)
  # Distinguish "nothing answers" from "answers with an untrusted certificate":
  # a self-signed answer means TLS works but no client will accept it.
  insecure_code=""
  if [ -z "$code" ] || [ "$code" = "000" ]; then
    insecure_code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "https://$CHECK_DOMAIN/v1/meta" 2>/dev/null || true)
  fi
  say "" ""
  if [ -n "$insecure_code" ] && [ "$insecure_code" != "000" ]; then
    bad "域名有响应,但证书不被信任(是自签证书,不是权威机构签发的)" \
        "the domain answers but with an untrusted (self-signed) certificate"
    say "原因:反代配置里有 tls internal 之类的自签兜底,新域名套用了它。" \
        "Cause: a catch-all such as 'tls internal' in the proxy config covers the new domain."
    say "结论:重新粘贴一次安装命令即可 —— 新版脚本会为这个域名单独指定权威证书。" \
        "Conclusion: re-run the installer; it now pins this domain to a public issuer."
    return 0
  fi
  case "$code" in
    401 | 200)
      ok "域名可以正常访问 agent(返回 $code)" "the domain reaches the agent (HTTP $code)"
      say "结论:一切正常!在 Aster 里添加 https://$CHECK_DOMAIN 即可。" \
          "Conclusion: all good — add https://$CHECK_DOMAIN in Aster." ;;
    403)
      bad "访问返回 403,反代把这个域名挡掉了" "403 — a proxy rule blocks this domain"
      say "结论:重跑一次安装命令,脚本会自动把域名加进白名单。" \
          "Conclusion: re-run the installer; it whitelists the domain automatically." ;;
    502 | 503 | 504)
      bad "访问返回 $code,反代连不上 agent" "$code — the proxy cannot reach the agent"
      say "结论:执行 systemctl restart $SERVICE,再重跑安装命令。" \
          "Conclusion: systemctl restart $SERVICE, then re-run the installer." ;;
    *)
      bad "域名没有响应(证书可能还没签好)" "the domain does not answer (certificate may be pending)"
      say "结论:按顺序检查这三点 ——" "Conclusion: check these three things —"
      say "  1) 域名 A 记录是否指向 ${myip:-本机公网IP}" "  1) does the A record point at ${myip:-this server}"
      say "  2) 服务商防火墙/安全组是否放行 80 和 443" "  2) are ports 80 and 443 open in your firewall"
      say "  3) 等 1 分钟后重跑安装命令(脚本会自动重试签发证书)" \
          "  3) wait a minute and re-run the installer (it retries issuance)" ;;
  esac
}

if [ "$STATUS" = 1 ]; then
  run_doctor
  exit 0
fi

# ---- install ----------------------------------------------------------------
[ -n "$TOKEN" ] || fail "缺少 --token(请在 Aster 的添加机器窗口里复制完整命令)" \
                        "--token is required (copy the whole command from Aster)"
command -v curl >/dev/null 2>&1 || fail "系统缺少 curl,请先安装 curl" "curl is required"

case "$(uname -s)" in
  Linux) PLATFORM=linux ;;
  Darwin) PLATFORM=darwin ;;
  *) fail "不支持的系统:$(uname -s)" "unsupported system: $(uname -s)" ;;
esac
case "$(uname -m)" in
  x86_64) ARCH=amd64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  armv7* | armv6*) ARCH=arm ;;
  i386 | i686) ARCH=386 ;;
  *) fail "不支持的 CPU 架构:$(uname -m)" "unsupported architecture: $(uname -m)" ;;
esac

# Someone pasting the plain command again must not silently lose domain mode.
if [ -z "$DOMAIN" ] && [ "$SAVED_MODE" = "domain" ] && [ "$FORCE_IP" = 0 ]; then
  DOMAIN="$SAVED_DOMAIN"
  say "检测到这台机器已经是域名模式($DOMAIN),已自动保留该设置。" \
      "this machine is already in domain mode ($DOMAIN); keeping it."
  say "如果确实要改回裸 IP 模式,请在命令末尾加 --force-ip" \
      "add --force-ip if you really want plain IP mode"
fi
if [ "$FORCE_IP" = 1 ]; then DOMAIN=""; fi

PROXY_KIND=""
GATEWAY=""
AUTO_HTTPS_OFF=0
DOMAIN_MANUAL=0

if [ -n "$DOMAIN" ]; then
  [ "$PLATFORM" = "linux" ] || fail "域名模式仅支持 Linux 服务器" "--domain is Linux-only"
  case "$PROXY" in caddy | nginx | auto) ;; *) PROXY=auto ;; esac
  dpkg --configure -a >/dev/null 2>&1 || true
  discover_docker
  case "$PROXY" in
    caddy)
      if command -v caddy >/dev/null 2>&1; then PROXY_KIND=caddy-host
      elif [ -n "$DOCKER_CADDY" ]; then PROXY_KIND=caddy-docker
      else PROXY_KIND=install-caddy; fi ;;
    nginx)
      if command -v nginx >/dev/null 2>&1; then PROXY_KIND=nginx-host
      elif [ -n "$DOCKER_NGINX" ]; then PROXY_KIND=nginx-docker
      else PROXY_KIND=install-caddy; fi ;;
    *)
      if command -v caddy >/dev/null 2>&1; then PROXY_KIND=caddy-host
      elif [ -n "$DOCKER_CADDY" ]; then PROXY_KIND=caddy-docker
      elif command -v nginx >/dev/null 2>&1; then PROXY_KIND=nginx-host
      elif [ -n "$DOCKER_NGINX" ]; then PROXY_KIND=nginx-docker
      else PROXY_KIND=install-caddy; fi ;;
  esac

  case "$PROXY_KIND" in
    caddy-docker)
      systemctl disable --now caddy >/dev/null 2>&1 || true
      GATEWAY=$(docker_gateway "$DOCKER_CADDY")
      [ -n "$GATEWAY" ] || fail "无法获取 Docker 网关地址" "cannot determine the docker gateway"
      LISTEN="$GATEWAY:$AGENT_PORT"
      say "检测到 Docker 里的 Caddy:$DOCKER_CADDY" "found dockerized Caddy: $DOCKER_CADDY" ;;
    nginx-docker)
      GATEWAY=$(docker_gateway "$DOCKER_NGINX")
      [ -n "$GATEWAY" ] || fail "无法获取 Docker 网关地址" "cannot determine the docker gateway"
      LISTEN="$GATEWAY:$AGENT_PORT"
      say "检测到 Docker 里的 nginx:$DOCKER_NGINX" "found dockerized nginx: $DOCKER_NGINX" ;;
    *)
      LISTEN="127.0.0.1:$AGENT_PORT" ;;
  esac

  say "部署方式:域名模式($DOMAIN)" "deployment: domain mode ($DOMAIN)"
  resolved=$(getent ahosts "$DOMAIN" 2>/dev/null | awk '{print $1; exit}' || true)
  if [ -z "$resolved" ]; then
    myip=$(public_ip)
    fail "域名 $DOMAIN 还没有解析生效。请先到域名服务商添加一条 A 记录:主机记录填域名前缀,值填 ${myip:-本机公网IP},保存后等几分钟再重新粘贴本命令。" \
         "$DOMAIN does not resolve yet. Add an A record pointing at ${myip:-this server}, wait a few minutes and paste this command again."
  fi
fi

stop_previous
if [ "$PLATFORM" = "linux" ]; then clean_proxy_blocks; fi

ASSET="aster-agent-$PLATFORM-$ARCH"
if [ "$VERSION" = "latest" ]; then
  URL="https://github.com/$REPO/releases/latest/download/$ASSET"
else
  URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET"
fi
FALLBACK_URL="https://raw.githubusercontent.com/$REPO/dist/$ASSET"
if [ -n "$GHPROXY" ]; then
  URL="$GHPROXY/$URL"
  FALLBACK_URL="$GHPROXY/$FALLBACK_URL"
fi

say "正在下载 agent…" "downloading the agent..."
if ! curl -fL --progress-bar -o "$BIN.tmp" "$URL" 2>/dev/null; then
  curl -fL --progress-bar -o "$BIN.tmp" "$FALLBACK_URL" \
    || fail "下载失败,请检查服务器网络后重新粘贴本命令" "download failed; check the network and retry"
fi
if [ -n "$SHA256" ]; then
  if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL=$(sha256sum "$BIN.tmp" | cut -d' ' -f1)
  else
    ACTUAL=$(shasum -a 256 "$BIN.tmp" | cut -d' ' -f1)
  fi
  if [ "$ACTUAL" != "$SHA256" ]; then
    rm -f "$BIN.tmp"
    fail "文件校验失败,已中止" "sha256 mismatch"
  fi
fi
mkdir -p "$(dirname "$BIN")"
chmod 755 "$BIN.tmp"
mv "$BIN.tmp" "$BIN"
mkdir -p "$STATE_DIR" "$CONF_DIR"

umask_previous=$(umask)
umask 077
printf '%s' "$TOKEN" > "$TOKEN_FILE"
umask "$umask_previous"
chmod 600 "$TOKEN_FILE"

if [ "$PLATFORM" = "darwin" ]; then
  cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>cc.aster.agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN</string>
    <string>--listen</string><string>$LISTEN</string>
    <string>--token-file</string><string>$TOKEN_FILE</string>
    <string>--state-dir</string><string>$STATE_DIR</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$DARWIN_LOG</string>
  <key>StandardErrorPath</key><string>$DARWIN_LOG</string>
</dict>
</plist>
EOF
  launchctl bootstrap system "$PLIST"
  sleep 2
  FINGERPRINT=$(grep -o 'fingerprint: [0-9a-f]*' "$DARWIN_LOG" 2>/dev/null | tail -1 | cut -d' ' -f2 || true)
elif command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  cat > "/etc/systemd/system/$SERVICE.service" << EOF
[Unit]
Description=Aster Agent
After=network-online.target

[Service]
ExecStart=$BIN --listen $LISTEN --token-file $TOKEN_FILE --state-dir $STATE_DIR
Restart=always
RestartSec=3
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "$SERVICE" >/dev/null 2>&1
  sleep 2
  FINGERPRINT=$(journalctl -u "$SERVICE" --no-pager 2>/dev/null | grep -o 'fingerprint: [0-9a-f]*' | tail -1 | cut -d' ' -f2 || true)
elif command -v rc-service >/dev/null 2>&1; then
  cat > "/etc/init.d/$SERVICE" << EOF
#!/sbin/openrc-run
name="Aster Agent"
command="$BIN"
command_args="--listen $LISTEN --token-file $TOKEN_FILE --state-dir $STATE_DIR"
command_background=true
pidfile="/run/$SERVICE.pid"
output_log="/var/log/$SERVICE.log"
error_log="/var/log/$SERVICE.log"
depend() { need net; }
EOF
  chmod +x "/etc/init.d/$SERVICE"
  rc-update add "$SERVICE" default
  rc-service "$SERVICE" start
  sleep 2
  FINGERPRINT=$(grep -o 'fingerprint: [0-9a-f]*' "/var/log/$SERVICE.log" 2>/dev/null | tail -1 | cut -d' ' -f2 || true)
else
  fail "没有找到支持的服务管理器(systemd 或 OpenRC)" "no supported init system found"
fi

# ---- reverse proxy ----------------------------------------------------------
# Existing configs guard themselves with host lists in two flavours:
#   @not_known  not host a b c      -> everything else gets 403
#   @known_hosts    host a b c      -> only these are allowed through
# Both must learn about the new domain, otherwise the ACME challenge (plain
# HTTP on port 80) is answered with 403 and no certificate is ever issued.
allow_in_whitelists() {
  touched=0
  if grep -q "not host" "$1" 2>/dev/null; then
    if ! grep "not host" "$1" | grep -q "$DOMAIN"; then
      edit_inplace "$1" "/not host/ s/\$/ $DOMAIN/"
      touched=1
    fi
  fi
  if grep -qE '^[[:space:]]*@[A-Za-z_]+[[:space:]]+host[[:space:]]' "$1" 2>/dev/null; then
    if ! grep -E '^[[:space:]]*@[A-Za-z_]+[[:space:]]+host[[:space:]]' "$1" | grep -q "$DOMAIN"; then
      edit_inplace "$1" "/^[[:space:]]*@[A-Za-z_]*[[:space:]]*host[[:space:]]/ s/\$/ $DOMAIN/"
      touched=1
    fi
  fi
  if [ "$touched" = 1 ]; then
    say "已把 $DOMAIN 加入原有配置的域名白名单" "added $DOMAIN to the existing host whitelists"
  fi
}

# A config with auto_https off (or explicit certificate paths) will never issue
# a certificate for a new site, so mirror whatever it already does.
tls_line() {
  if [ -n "$CERT_PATH" ] && [ -n "$KEY_PATH" ]; then
    printf '  tls %s %s' "$CERT_PATH" "$KEY_PATH"
    return 0
  fi
  [ -f "${1:-}" ] || return 0
  if grep -qE '^[[:space:]]*auto_https[[:space:]]+off' "$1" 2>/dev/null; then
    existing=$(grep -oE 'tls[[:space:]]+/[^ ]+[[:space:]]+/[^ ]+' "$1" 2>/dev/null | head -1)
    if [ -n "$existing" ]; then
      printf '  %s' "$existing"
      return 0
    fi
    AUTO_HTTPS_OFF=1
    return 0
  fi
  # A catch-all "tls internal" makes Caddy hand out its own untrusted
  # certificate for any name without an explicit policy — the TLS handshake
  # then succeeds but no client trusts it. Pin our site to a public issuer.
  if grep -qE '^[[:space:]]*tls[[:space:]]+internal' "$1" 2>/dev/null; then
    account=$(grep -oE '^[[:space:]]*email[[:space:]]+\S+' "$1" 2>/dev/null | head -1 | awk '{print $2}')
    if [ -n "$account" ]; then
      printf '  tls %s' "$account"
    else
      printf '  tls {\n    issuer acme\n  }'
    fi
    say "检测到配置里有 tls internal(自签兜底),已为本域名单独指定权威证书签发" \
        "found a catch-all 'tls internal'; pinning this domain to a public certificate issuer"
  fi
}

write_caddy_block() {
  edit_inplace "$1" '/# aster-agent begin/,/# aster-agent end/d'
  allow_in_whitelists "$1"
  extra=$(tls_line "$1")
  {
    printf '# aster-agent begin\n'
    printf '%s {\n' "$DOMAIN"
    if [ -n "$extra" ]; then printf '%s\n' "$extra"; fi
    printf '  reverse_proxy https://%s {\n' "$2"
    printf '    transport http {\n      tls_insecure_skip_verify\n    }\n'
    printf '  }\n}\n'
    printf '# aster-agent end\n'
  } >> "$1"
}

install_caddy_pkg() {
  say "正在安装 Caddy(慢速服务器可能要几分钟,请不要关闭窗口)" \
      "installing Caddy (may take a few minutes on slow servers)"
  command -v apt-get >/dev/null 2>&1 \
    || fail "无法自动安装 Caddy,请先手动安装 caddy 或 nginx 再重试" \
            "cannot auto-install Caddy; install caddy or nginx first"
  apt-get update -q
  apt-get install -y -q debian-keyring debian-archive-keyring apt-transport-https gnupg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -q && apt-get install -y -q caddy
}

setup_nginx_host() {
  cat > "$NGINX_CONF" << EOF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        proxy_pass https://127.0.0.1:$AGENT_PORT;
        proxy_ssl_verify off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
  nginx -t >/dev/null 2>&1 || fail "nginx 配置检查未通过" "nginx config test failed"
  systemctl reload nginx 2>/dev/null || systemctl restart nginx
  if ! command -v certbot >/dev/null 2>&1; then
    say "正在安装 certbot(用于申请证书)" "installing certbot"
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -q && apt-get install -y -q certbot python3-certbot-nginx
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y -q certbot python3-certbot-nginx
    elif command -v yum >/dev/null 2>&1; then
      yum install -y -q certbot python3-certbot-nginx
    else
      fail "无法自动安装 certbot" "cannot install certbot automatically"
    fi
  fi
  say "正在申请证书…" "requesting the certificate..."
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos \
    --register-unsafely-without-email --redirect --keep-until-expiring >/dev/null 2>&1 \
    || fail "证书申请失败(通常是 80 端口没放行或域名还没解析生效),处理后重新粘贴本命令即可" \
            "certificate issuance failed (usually port 80 blocked or DNS not live)"
  if ! systemctl list-timers 2>/dev/null | grep -q certbot; then
    if [ -d /etc/cron.d ]; then
      printf '0 3 * * * root certbot renew --quiet --deploy-hook "systemctl reload nginx"\n' \
        > /etc/cron.d/aster-certbot-renew
    fi
  fi
  say "nginx 与证书配置完成,到期会自动续期" "nginx and certificate configured; renewal is automatic"
}

if [ -n "$DOMAIN" ]; then
  case "$PROXY_KIND" in
    install-caddy)
      install_caddy_pkg
      touch "$CADDYFILE"
      write_caddy_block "$CADDYFILE" "127.0.0.1:$AGENT_PORT"
      systemctl enable --now caddy >/dev/null 2>&1 || true
      systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy \
        || fail "Caddy 启动失败,请运行 journalctl -u caddy 查看原因" "caddy failed to start" ;;
    caddy-host)
      touch "$CADDYFILE"
      write_caddy_block "$CADDYFILE" "127.0.0.1:$AGENT_PORT"
      systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy \
        || fail "Caddy 启动失败,请运行 journalctl -u caddy 查看原因" "caddy failed to start" ;;
    caddy-docker)
      CADDYFILE_HOST=$(docker_caddyfile "$DOCKER_CADDY")
      [ -n "$CADDYFILE_HOST" ] \
        || fail "找到了 Caddy 容器但没找到它的配置文件挂载,需要手动配置反向代理" \
                "found the Caddy container but not its Caddyfile mount"
      say "正在更新 $CADDYFILE_HOST" "updating $CADDYFILE_HOST"
      write_caddy_block "$CADDYFILE_HOST" "$GATEWAY:$AGENT_PORT"
      # An earlier tool may already have detached the bind mount (see
      # edit_inplace): confirm the container really sees the new config and
      # restart it — which re-resolves the mount — when it does not.
      if ! docker exec "$DOCKER_CADDY" grep -q "$DOMAIN" /etc/caddy/Caddyfile 2>/dev/null; then
        say "容器还看不到新配置(挂载已失效),正在重启 Caddy 容器修复" \
            "the container cannot see the new config (stale bind mount); restarting it"
        docker restart "$DOCKER_CADDY" >/dev/null 2>&1 \
          || fail "无法重启 Caddy 容器" "could not restart the Caddy container"
        sleep 4
        docker exec "$DOCKER_CADDY" grep -q "$DOMAIN" /etc/caddy/Caddyfile 2>/dev/null \
          || fail "容器内的配置文件与宿主机文件不一致,请检查 $DOCKER_CADDY 的挂载设置" \
                  "the container's config still differs from the host file; check the mounts of $DOCKER_CADDY"
      else
        docker exec "$DOCKER_CADDY" caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 \
          || docker restart "$DOCKER_CADDY" >/dev/null 2>&1 \
          || fail "无法重载 Caddy 容器" "could not reload the Caddy container"
      fi ;;
    nginx-host) setup_nginx_host ;;
    nginx-docker)
      say "" ""
      say "你的 nginx 运行在 Docker 里,自动改配置风险太高,请手动添加反向代理:" \
          "your nginx runs in Docker; add the proxy entry manually:"
      say "  上游地址:https://$GATEWAY:$AGENT_PORT" "  upstream: https://$GATEWAY:$AGENT_PORT"
      say "  域名:$DOMAIN(并在面板里为它申请证书)" "  domain: $DOMAIN (request a certificate for it)"
      DOMAIN_MANUAL=1 ;;
  esac

  if [ "$AUTO_HTTPS_OFF" = 1 ]; then
    say "" ""
    say "注意:你的 Caddy 配置里有 auto_https off,它不会自动申请证书。" \
        "Note: your Caddy config sets auto_https off, so no certificate is issued."
    say "请重新粘贴本命令并加上证书路径,例如:--cert /etc/ssl/a.pem --key /etc/ssl/a.key" \
        "Re-run this command with --cert /path/cert.pem --key /path/key.pem"
  fi

  save_state domain "$DOMAIN" "$PROXY_KIND" "$LISTEN"
else
  save_state ip "" "" "$LISTEN"
fi

# ---- verify -----------------------------------------------------------------
VERIFIED=0
if [ -n "$DOMAIN" ] && [ "$DOMAIN_MANUAL" != 1 ]; then
  say "" ""
  say "正在验证域名能否访问(首次申请证书通常需要 30-60 秒,请稍候)" \
      "verifying the domain (the first certificate usually takes 30-60 s)"
  attempt=0
  while [ "$attempt" -lt 24 ]; do
    attempt=$((attempt + 1))
    CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "https://$DOMAIN/v1/meta" 2>/dev/null || true)
    if [ "$CODE" = "401" ] || [ "$CODE" = "200" ]; then
      VERIFIED=1
      break
    fi
    if [ $((attempt % 4)) = 0 ]; then
      say "  仍在等待证书签发…(已等 $((attempt * 5)) 秒)" "  still waiting for the certificate... ($((attempt * 5))s)"
    fi
    sleep 5
  done
fi

line ""
line "=========================================="
if [ -n "$DOMAIN" ]; then
  if [ "$VERIFIED" = 1 ]; then
    say "部署成功!请在 Aster 里用下面这个地址添加机器:" "Ready. Add this machine in Aster with:"
    line "   https://$DOMAIN"
    say "(不需要比对指纹,证书会自动验证)" "(no fingerprint step; the certificate verifies automatically)"
  elif [ "$DOMAIN_MANUAL" = 1 ]; then
    say "agent 已安装,反向代理请按上面的说明手动配置。" \
        "Agent installed; finish the proxy setup manually (see above)."
  else
    say "agent 已装好,但域名还访问不通。下面是自动体检结果:" \
        "Agent installed, but the domain does not answer yet. Automatic diagnosis:"
    line ""
    run_doctor
  fi
else
  say "安装完成,agent 正在 $LISTEN 上运行。" "Installed; the agent is running on $LISTEN."
  if [ -n "${FINGERPRINT:-}" ]; then
    say "请在 Aster 里核对这个指纹:" "Compare this fingerprint in Aster:"
    line "   $FINGERPRINT"
  fi
fi
line "=========================================="
