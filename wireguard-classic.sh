#!/bin/bash
#
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                                                                          ║
# ║       W I R E G U A R D   V P N   M A N A G E R  —  v 0 . 5              ║
# ║                                                                          ║
# ║               Быстрый · Современный · Безопасный                         ║
# ║                                                                          ║
# ║                                                                          ║
# ╚══════════════════════════════════════════════════════════════════════════╝

set -o pipefail
set -u
umask 077

# ─── Цвета ─────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
	RED=$'\033[0;31m'
	GREEN=$'\033[0;32m'
	YELLOW=$'\033[0;33m'
	BLUE=$'\033[0;34m'
	MAGENTA=$'\033[0;35m'
	CYAN=$'\033[0;36m'
	WHITE=$'\033[1;37m'
	GRAY=$'\033[0;90m'
	BOLD=$'\033[1m'
	DIM=$'\033[2m'
	BLINK=$'\033[5m'
	REVERSE=$'\033[7m'
	NC=$'\033[0m'
else
	RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''
	WHITE=''; GRAY=''; BOLD=''; DIM=''; BLINK=''; REVERSE=''; NC=''
fi

# ─── Глобальные переменные ─────────────────────────────────────────────────
SERVER_PUB_IP=""
SERVER_PUB_NIC=""
SERVER_NIC=""
SERVER_WG_NIC=""
SERVER_WG_IPV4=""
SERVER_WG_IPV6=""
SERVER_PORT=""
SERVER_PRIV_KEY=""
SERVER_PUB_KEY=""
CLIENT_DNS_1=""
CLIENT_DNS_2=""
ALLOWED_IPS=""
ENABLE_IPV6=1
DISABLE_IPV6_SYSCTL=0
OS=""
VERSION_ID=""
SUDO_USER="${SUDO_USER:-}"
RANDOM_PORT=""
DEFAULT_AIPS=""
ADDR_LINE=""
FW4=""
FW6=""
WG_RUNNING=0

# ─── Версия ────────────────────────────────────────────────────────────────
WG_MANAGER_VERSION="0.5"
WG_MANAGER_DATE="2025"

# ─── Базовый вывод ─────────────────────────────────────────────────────────
msg()  { printf '%s\n' "$*"; }
info() { printf '%b\n' "${CYAN}ℹ${NC}  $*"; }
ok()   { printf '%b\n' "${GREEN}✔${NC}  $*"; }
warn() { printf '%b\n' "${YELLOW}⚠${NC}  $*"; }
err()  { printf '%b\n' "${RED}✖${NC}  $*" >&2; }
hr()   { printf '%b\n' "${GRAY}──────────────────────────────────────────────────────────────────${NC}"; }
hr_thin() { printf '%b\n' "${GRAY}┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${NC}"; }

# [БАГ 4 исправлен] strlen_visual без лишней обёртки
strlen_visual() {
	local s="$1" stripped
	stripped=$(printf '%s' "$s" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g')
	printf '%s' "${#stripped}"
}

box() {
	local text="$1"
	local len; len=$(strlen_visual "$text")
	[[ -z $len || $len -lt 1 ]] && len=10
	local line; line=$(printf '─%.0s' $(seq 1 $((len + 4))))
	printf '\n%b┌%s┐%b\n' "$CYAN" "$line" "$NC"
	printf '%b│%b  %b%s%b  %b│%b\n' "$CYAN" "$NC" "$BOLD" "$text" "$NC" "$CYAN" "$NC"
	printf '%b└%s┘%b\n\n' "$CYAN" "$line" "$NC"
}

# Двойная рамка для важных заголовков
box_double() {
	local text="$1"
	local len; len=$(strlen_visual "$text")
	[[ -z $len || $len -lt 1 ]] && len=10
	local line; line=$(printf '═%.0s' $(seq 1 $((len + 4))))
	printf '\n%b╔%s╗%b\n' "$MAGENTA" "$line" "$NC"
	printf '%b║%b  %b%s%b  %b║%b\n' "$MAGENTA" "$NC" "$BOLD$WHITE" "$text" "$NC" "$MAGENTA" "$NC"
	printf '%b╚%s╝%b\n\n' "$MAGENTA" "$line" "$NC"
}

banner() {
	clear
	local W=68
	printf '%b' "$CYAN"
	printf '  ╔'; printf '═%.0s' $(seq 1 $((W-4))); printf '╗\n'
	printf '  ║%*s║\n' $((W-4)) ''
	printf '  ║%b%s%b║\n' \
		"$(printf '%*s' $(( (W-4 - 46) / 2 )) '')" \
		"${BOLD}${WHITE}  W I R E G U A R D     V P N    M A N A G E R  ${NC}${CYAN}" \
		"$(printf '%*s' $(( (W-4 - 46 + 1) / 2 )) '')"
	printf '%b' "$CYAN"
	printf '  ║%*s║\n' $((W-4)) ''
	printf '  ║%b%-*s%b║\n' \
		"$DIM" \
		$((W-4)) \
		"$(printf '%*s' $(( (W-4 - 36) / 2 )) '')Быстрый  ·  Современный  ·  Безопасный" \
		"$NC$CYAN"
	printf '  ║%*s║\n' $((W-4)) ''
	printf '  ╚'; printf '═%.0s' $(seq 1 $((W-4))); printf '╝\n'
	printf '%b' "$NC"
	printf '%b  v%s%b\n\n' "$GRAY" "$WG_MANAGER_VERSION" "$NC"
}

confirm() {
	local prompt="$1" default="${2:-n}" reply hint
	[[ $default == y ]] && hint="${GREEN}[Д${NC}/${DIM}н]${NC}" || hint="${DIM}[д/${NC}${RED}Н]${NC}"
	read -rp "$(printf '%b?%b %s %b%s%b ' "$YELLOW" "$NC" "$prompt" "$BOLD" "$hint" "$NC")" reply || reply=""
	reply=${reply:-$default}
	[[ ${reply,,} == y* || ${reply,,} == д* ]]
}

pause() {
	echo
	read -n1 -r -p "$(printf '%b  Нажмите любую клавишу для продолжения…%b' "$DIM" "$NC")" || true
	echo
}

# ─── Проверки ──────────────────────────────────────────────────────────────

# [БАГ 5 исправлен] installPackages корректно передаёт exit-код
installPackages() {
	if ! "$@"; then
		local code=$?
		err "Не удалось установить пакеты: $*"
		msg "Проверьте подключение к интернету и источники пакетов."
		exit $code
	fi
}

isRoot() {
	if [[ ${EUID} -ne 0 ]]; then
		err "Скрипт нужно запускать от пользователя root."
		exit 1
	fi
}

checkVirt() {
	local VIRT=""
	if command -v virt-what &>/dev/null; then
		VIRT=$(virt-what 2>/dev/null || echo "")
	else
		VIRT=$(systemd-detect-virt 2>/dev/null || echo "")
	fi
	if [[ ${VIRT} == "openvz" ]]; then
		err "OpenVZ не поддерживается."; exit 1
	fi
	if [[ ${VIRT} == "lxc" ]]; then
		err "LXC пока не поддерживается."
		msg "WireGuard может работать в LXC, но модуль ядра должен быть на хосте."
		exit 1
	fi
}

checkOS() {
	# shellcheck disable=SC1091
	source /etc/os-release
	OS="${ID:-}"
	VERSION_ID="${VERSION_ID:-0}"
	if [[ ${OS} == "debian" || ${OS} == "raspbian" ]]; then
		[[ ${VERSION_ID%%.*} -lt 10 ]] && {
			err "Debian ${VERSION_ID} не поддерживается (нужно ≥10)."; exit 1
		}
		OS=debian
	elif [[ ${OS} == "ubuntu" ]]; then
		local YEAR; YEAR=$(echo "${VERSION_ID}" | cut -d'.' -f1)
		[[ ${YEAR} -lt 18 ]] && {
			err "Ubuntu ${VERSION_ID} не поддерживается (нужно ≥18.04)."; exit 1
		}
	elif [[ ${OS} == "fedora" ]]; then
		[[ ${VERSION_ID%%.*} -lt 32 ]] && {
			err "Fedora ${VERSION_ID} не поддерживается (нужно ≥32)."; exit 1
		}
	elif [[ ${OS} == 'centos' || ${OS} == 'almalinux' || ${OS} == 'rocky' ]]; then
		[[ ${VERSION_ID} == 7* ]] && {
			err "CentOS 7 не поддерживается (нужно ≥8)."; exit 1
		}
	elif [[ -e /etc/oracle-release ]]; then
		OS=oracle
	elif [[ -e /etc/arch-release ]]; then
		OS=arch
	elif [[ -e /etc/alpine-release ]]; then
		OS=alpine
		command -v virt-what &>/dev/null || apk add --quiet virt-what 2>/dev/null || true
	else
		err "Дистрибутив не поддерживается."
		msg "Поддерживаются: Debian, Ubuntu, Fedora, CentOS, AlmaLinux, Rocky, Oracle, Arch, Alpine."
		exit 1
	fi
}

getHomeDirForClient() {
	local CLIENT_NAME=$1
	[[ -z $CLIENT_NAME ]] && {
		err "getHomeDirForClient(): требуется имя клиента"; exit 1
	}
	if [[ -e /home/${CLIENT_NAME} ]]; then
		echo "/home/${CLIENT_NAME}"
	elif [[ -n ${SUDO_USER} && ${SUDO_USER} != root ]]; then
		echo "/home/${SUDO_USER}"
	else
		echo "/root"
	fi
}

countClients() {
	local conf="${1:-/etc/wireguard/${SERVER_WG_NIC}.conf}"
	[[ -r $conf ]] || { echo 0; return; }
	local n
	n=$(grep -c -E "^### Client " "$conf" 2>/dev/null || echo 0)
	echo "${n:-0}"
}

# Подсчёт активных пиров через wg show
countActivePeers() {
	command -v wg &>/dev/null || { echo 0; return; }
	local n
	n=$(wg show "${SERVER_WG_NIC}" peers 2>/dev/null | wc -l || echo 0)
	echo "${n:-0}"
}

initialCheck() { isRoot; checkOS; checkVirt; }

# ─── Шаги установки ────────────────────────────────────────────────────────
installQuestions() {
	# Вспомогательная функция: читать значение с дефолтом и валидацией
	# prompt_default VAR "Подсказка" "дефолт" regex [min max]
	_ask() {
		local -n _var=$1
		local prompt="$2" default="$3" regex="${4:-}" _min="${5:-}" _max="${6:-}" _tmp
		while true; do
			read -rp "$(printf '  %b%s%b %b[%s]%b : ' "$WHITE" "$prompt" "$NC" "$GREEN" "$default" "$NC")" _tmp || _tmp=""
			[[ -z $_tmp ]] && _tmp="$default"
			if [[ -n $regex && ! $_tmp =~ $regex ]]; then
				warn "  Некорректный формат. Попробуйте снова."; continue
			fi
			if [[ -n $_min ]] && (( _tmp < _min || _tmp > _max )); then
				warn "  Значение должно быть от $_min до $_max."; continue
			fi
			break
		done
		_var="$_tmp"
	}

	banner
	box_double "Первичная настройка WireGuard"
	printf '%b  Нажмите %bEnter%b%b для принятия значения по умолчанию.\n'   "$DIM" "$NC$BOLD" "$NC" "$DIM"
	printf '  Всё можно изменить позже: /etc/wireguard/<iface>.conf и /etc/wireguard/params%b\n\n' "$NC"

	# ── Шаг 1/8: Публичный IP ─────────────────────────────────────────────
	hr
	printf '\n%b  [1/8]%b ' "$CYAN$BOLD" "$NC"
	info "${BOLD}Публичный IP сервера${NC} — адрес, по которому клиенты будут подключаться."
	local _auto_ip
	_auto_ip=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	[[ -z $_auto_ip ]] && _auto_ip=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	[[ -z $_auto_ip ]] && _auto_ip="0.0.0.0"
	while true; do
		read -rp "$(printf '  %bПубличный IP%b %b[%s]%b : ' "$WHITE" "$NC" "$GREEN" "$_auto_ip" "$NC")" _tmp || _tmp=""
		[[ -z $_tmp ]] && _tmp="$_auto_ip"
		[[ -n $_tmp ]] && break
		warn "  IP-адрес не может быть пустым."
	done
	SERVER_PUB_IP="$_tmp"

	# ── Шаг 2/8: Внешний NIC ──────────────────────────────────────────────
	hr
	printf '\n%b  [2/8]%b ' "$CYAN$BOLD" "$NC"
	info "${BOLD}Внешний сетевой интерфейс${NC} — через него идёт интернет (для NAT/MASQUERADE)."
	SERVER_NIC="$(ip -4 route ls | awk '/default/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)"
	printf '  %bОбнаружен: %b%s%b\n' "$DIM" "$NC$BOLD" "${SERVER_NIC:-не определён}" "$NC"
	while true; do
		read -rp "$(printf '  %bВнешний интерфейс%b %b[%s]%b : ' "$WHITE" "$NC" "$GREEN" "${SERVER_NIC:-eth0}" "$NC")" _tmp || _tmp=""
		[[ -z $_tmp ]] && _tmp="${SERVER_NIC:-eth0}"
		if [[ $_tmp =~ ^[a-zA-Z0-9_.-]+$ ]]; then
			SERVER_PUB_NIC="$_tmp"; break
		fi
		warn "  Некорректное имя интерфейса."
	done

	# ── Шаг 3/8: WG NIC ───────────────────────────────────────────────────
	hr
	printf '\n%b  [3/8]%b ' "$CYAN$BOLD" "$NC"
	info "${BOLD}Имя WireGuard-интерфейса${NC} — имя туннеля, обычно wg0 (латиница, цифры, _)."
	while true; do
		read -rp "$(printf '  %bИмя WG-интерфейса%b %b[wg0]%b : ' "$WHITE" "$NC" "$GREEN" "$NC")" _tmp || _tmp=""
		[[ -z $_tmp ]] && _tmp="wg0"
		if [[ $_tmp =~ ^[a-zA-Z0-9_]+$ && ${#_tmp} -lt 16 ]]; then
			SERVER_WG_NIC="$_tmp"; break
		fi
		warn "  Только латиница, цифры и _; не более 15 символов."
	done

	# ── Шаг 4/8: IPv4 в туннеле ───────────────────────────────────────────
	hr
	printf '\n%b  [4/8]%b ' "$CYAN$BOLD" "$NC"
	info "${BOLD}IPv4 сервера внутри туннеля${NC} — приватный адрес (обычно 10.x.x.1)."
	while true; do
		read -rp "$(printf '  %bIPv4 в VPN%b %b[10.66.66.1]%b : ' "$WHITE" "$NC" "$GREEN" "$NC")" _tmp || _tmp=""
		[[ -z $_tmp ]] && _tmp="10.66.66.1"
		if [[ $_tmp =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
			SERVER_WG_IPV4="$_tmp"; break
		fi
		warn "  Введите корректный IPv4-адрес."
	done

	# ── Шаг 5/8: Порт ─────────────────────────────────────────────────────
	hr
	printf '\n%b  [5/8]%b ' "$CYAN$BOLD" "$NC"
	info "${BOLD}UDP-порт WireGuard${NC} — порт, который будут использовать клиенты. По умолчанию случайный."
	RANDOM_PORT=$(shuf -i49152-65535 -n1)
	while true; do
		read -rp "$(printf '  %bПорт (1–65535)%b %b[%s]%b : ' "$WHITE" "$NC" "$GREEN" "${RANDOM_PORT}" "$NC")" _tmp || _tmp=""
		[[ -z $_tmp ]] && _tmp="${RANDOM_PORT}"
		if [[ $_tmp =~ ^[0-9]+$ ]] && (( _tmp >= 1 && _tmp <= 65535 )); then
			SERVER_PORT="$_tmp"; break
		fi
		warn "  Порт должен быть числом от 1 до 65535."
	done

	# ── Шаг 6/8: IPv6 ─────────────────────────────────────────────────────
	hr
	printf '\n%b  [6/8]%b ' "$CYAN$BOLD" "$NC"
	info "${BOLD}IPv6 внутри VPN-туннеля${NC} — включить для проксирования IPv6-трафика клиентов."
	if confirm "  Включить IPv6 внутри туннеля?" y; then
		ENABLE_IPV6=1
		while true; do
			read -rp "$(printf '  %bIPv6 в VPN%b %b[fd42:42:42::1]%b : ' "$WHITE" "$NC" "$GREEN" "$NC")" _tmp || _tmp=""
			[[ -z $_tmp ]] && _tmp="fd42:42:42::1"
			if [[ $_tmp == *:* ]]; then
				SERVER_WG_IPV6="$_tmp"; break
			fi
			warn "  Введите корректный IPv6-адрес (должен содержать «:»)."
		done
		DISABLE_IPV6_SYSCTL=0
	else
		ENABLE_IPV6=0
		SERVER_WG_IPV6=""
		warn "  IPv6 внутри туннеля отключён."
		if confirm "  Отключить IPv6 глобально через sysctl?" n; then
			DISABLE_IPV6_SYSCTL=1
			warn "  IPv6 будет отключён через /etc/sysctl.d/wg.conf."
		else
			DISABLE_IPV6_SYSCTL=0
		fi
	fi

	# ── Шаг 7/8: DNS ──────────────────────────────────────────────────────
	hr
	printf '\n%b  [7/8]%b ' "$CYAN$BOLD" "$NC"
	info "${BOLD}DNS-серверы для клиентов${NC} — будут прописаны в каждом клиентском конфиге."
	printf '%b  Популярные варианты:\n'                                    "$DIM"
	printf '    1.1.1.1 / 1.0.0.1  — Cloudflare (быстрый, приватный)\n'
	printf '    8.8.8.8 / 8.8.4.4  — Google\n'
	printf '    9.9.9.9 / 149.112.112.112 — Quad9 (фильтрация угроз)%b\n' "$NC"
	while true; do
		read -rp "$(printf '  %bОсновной DNS%b %b[1.1.1.1]%b : ' "$WHITE" "$NC" "$GREEN" "$NC")" _tmp || _tmp=""
		[[ -z $_tmp ]] && _tmp="1.1.1.1"
		if [[ $_tmp =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
			CLIENT_DNS_1="$_tmp"; break
		fi
		warn "  Введите корректный IPv4-адрес DNS."
	done
	while true; do
		read -rp "$(printf '  %bРезервный DNS%b %b[1.0.0.1]%b (Enter — тот же): ' "$WHITE" "$NC" "$GREEN" "$NC")" _tmp || _tmp=""
		[[ -z $_tmp ]] && _tmp="1.0.0.1"
		if [[ $_tmp =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
			CLIENT_DNS_2="$_tmp"; break
		fi
		warn "  Введите корректный IPv4-адрес DNS."
	done

	# ── Шаг 8/8: AllowedIPs ──────────────────────────────────────────────
	hr
	printf '\n%b  [8/8]%b ' "$CYAN$BOLD" "$NC"
	info "${BOLD}AllowedIPs${NC} — какой трафик клиента пойдёт в VPN."
	printf '%b  •  0.0.0.0/0,::/0     — весь трафик через VPN (full-tunnel)\n' "$DIM"
	printf '  •  10.66.66.0/24,…   — только VPN-подсеть (split-tunnel)%b\n' "$NC"
	if [[ ${ENABLE_IPV6} -eq 1 ]]; then
		DEFAULT_AIPS='0.0.0.0/0,::/0'
	else
		DEFAULT_AIPS='0.0.0.0/0'
	fi
	read -rp "$(printf '  %bAllowedIPs%b %b[%s]%b : ' "$WHITE" "$NC" "$GREEN" "${DEFAULT_AIPS}" "$NC")" ALLOWED_IPS || ALLOWED_IPS=""
	[[ -z ${ALLOWED_IPS} ]] && ALLOWED_IPS="${DEFAULT_AIPS}"

	# ── Сводка перед установкой ─────────────────────────────────────────────
	echo
	hr
	box "Сводка перед установкой"
	local _IPV6_STATUS
	[[ ${ENABLE_IPV6} -eq 1 ]] \
		&& _IPV6_STATUS="$(printf '%bВкл%b  (%s/64)' "$GREEN" "$NC" "${SERVER_WG_IPV6}")" \
		|| _IPV6_STATUS="$(printf '%bВыкл%b' "$RED" "$NC")"

	printf '  %b%-22s%b %s\n'  "$BOLD" "Публичный адрес:"    "$NC" "${SERVER_PUB_IP}"
	printf '  %b%-22s%b %s\n'  "$BOLD" "UDP-порт:"           "$NC" "${SERVER_PORT}"
	printf '  %b%-22s%b %s\n'  "$BOLD" "Внешний интерфейс:"  "$NC" "${SERVER_PUB_NIC}"
	printf '  %b%-22s%b %s\n'  "$BOLD" "WG-интерфейс:"       "$NC" "${SERVER_WG_NIC}"
	printf '  %b%-22s%b %s/24\n' "$BOLD" "IP сервера (VPN):" "$NC" "${SERVER_WG_IPV4}"
	printf '  %b%-22s%b %b\n'  "$BOLD" "IPv6 в туннеле:"     "$NC" "${_IPV6_STATUS}"
	[[ ${DISABLE_IPV6_SYSCTL} -eq 1 ]] && \
		printf '  %b%-22s%b %bотключён через sysctl%b\n' "$BOLD" "IPv6 системно:" "$NC" "$YELLOW" "$NC"
	printf '  %b%-22s%b %s / %s\n' "$BOLD" "DNS клиентов:" "$NC" "${CLIENT_DNS_1}" "${CLIENT_DNS_2}"
	printf '  %b%-22s%b %s\n'  "$BOLD" "AllowedIPs:"         "$NC" "${ALLOWED_IPS}"
	echo
	confirm "Всё верно, начинаем установку?" y || { err "Установка отменена."; exit 1; }
}

# ─── Установка WireGuard ────────────────────────────────────────────────────
installWireGuard() {
	installQuestions

	info "Устанавливаем пакеты для ${BOLD}${OS}${NC}…"
	case "${OS}" in
		ubuntu|debian)
			if [[ ${OS} == debian && ${VERSION_ID%%.*} -le 10 ]]; then
				if ! grep -rqs "^deb .* buster-backports" /etc/apt/; then
					echo "deb http://deb.debian.org/debian buster-backports main" \
						>/etc/apt/sources.list.d/backports.list
				fi
				apt-get update
				installPackages apt-get install -y iptables resolvconf qrencode
				installPackages apt-get install -y -t buster-backports wireguard
			else
				apt-get update
				installPackages apt-get install -y wireguard iptables resolvconf qrencode
			fi ;;
		fedora)
			if [[ ${VERSION_ID%%.*} -lt 32 ]]; then
				installPackages dnf install -y dnf-plugins-core
				dnf copr enable -y jdoss/wireguard
				installPackages dnf install -y wireguard-dkms
			fi
			installPackages dnf install -y wireguard-tools iptables qrencode ;;
		centos|almalinux|rocky)
			if [[ ${VERSION_ID} == 8* ]]; then
				installPackages yum install -y epel-release elrepo-release
				installPackages yum install -y kmod-wireguard
			fi
			installPackages yum install -y wireguard-tools iptables
			yum install -y qrencode || warn "qrencode недоступен — QR-коды будут пропущены." ;;
		oracle)
			installPackages dnf install -y oraclelinux-developer-release-el8
			dnf config-manager --disable -y ol8_developer
			dnf config-manager --enable -y ol8_developer_UEKR6
			dnf config-manager --save -y --setopt=ol8_developer_UEKR6.includepkgs='wireguard-tools*'
			installPackages dnf install -y wireguard-tools qrencode iptables ;;
		arch) installPackages pacman -S --needed --noconfirm wireguard-tools qrencode ;;
		alpine)
			apk update
			installPackages apk add wireguard-tools iptables libqrencode-tools ;;
	esac

	if ! command -v wg &>/dev/null; then
		err "Установка WireGuard не удалась — команда «wg» не найдена."
		exit 1
	fi

	mkdir -p /etc/wireguard
	chmod 700 /etc/wireguard

	SERVER_PRIV_KEY=$(wg genkey)
	SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)

	{
		echo "SERVER_PUB_IP=${SERVER_PUB_IP}"
		echo "SERVER_PUB_NIC=${SERVER_PUB_NIC}"
		echo "SERVER_WG_NIC=${SERVER_WG_NIC}"
		echo "SERVER_WG_IPV4=${SERVER_WG_IPV4}"
		echo "SERVER_WG_IPV6=${SERVER_WG_IPV6}"
		echo "SERVER_PORT=${SERVER_PORT}"
		echo "SERVER_PRIV_KEY=${SERVER_PRIV_KEY}"
		echo "SERVER_PUB_KEY=${SERVER_PUB_KEY}"
		echo "CLIENT_DNS_1=${CLIENT_DNS_1}"
		echo "CLIENT_DNS_2=${CLIENT_DNS_2}"
		echo "ALLOWED_IPS=${ALLOWED_IPS}"
		echo "ENABLE_IPV6=${ENABLE_IPV6}"
		echo "DISABLE_IPV6_SYSCTL=${DISABLE_IPV6_SYSCTL}"
	} >/etc/wireguard/params

	local WG_CONF="/etc/wireguard/${SERVER_WG_NIC}.conf"
	if [[ ${ENABLE_IPV6} -eq 1 ]]; then
		ADDR_LINE="${SERVER_WG_IPV4}/24,${SERVER_WG_IPV6}/64"
	else
		ADDR_LINE="${SERVER_WG_IPV4}/24"
	fi
	{
		echo "[Interface]"
		echo "Address = ${ADDR_LINE}"
		echo "ListenPort = ${SERVER_PORT}"
		echo "PrivateKey = ${SERVER_PRIV_KEY}"
	} >"${WG_CONF}"

	if pgrep firewalld >/dev/null 2>&1; then
		FW4=$(echo "${SERVER_WG_IPV4}" | cut -d'.' -f1-3)".0"
		{
			printf 'PostUp = firewall-cmd --zone=public --add-interface=%s && firewall-cmd --add-port %s/udp && firewall-cmd --add-rich-rule='"'"'rule family=ipv4 source address=%s/24 masquerade'"'" \
				"${SERVER_WG_NIC}" "${SERVER_PORT}" "${FW4}"
			if [[ ${ENABLE_IPV6} -eq 1 ]]; then
				FW6=$(echo "${SERVER_WG_IPV6}" | sed 's/:[^:]*$/:0/')
				printf " && firewall-cmd --add-rich-rule='rule family=ipv6 source address=%s/64 masquerade'\n" "${FW6}"
			else
				printf '\n'
			fi
			printf 'PostDown = firewall-cmd --zone=public --remove-interface=%s && firewall-cmd --remove-port %s/udp && firewall-cmd --remove-rich-rule='"'"'rule family=ipv4 source address=%s/24 masquerade'"'" \
				"${SERVER_WG_NIC}" "${SERVER_PORT}" "${FW4}"
			if [[ ${ENABLE_IPV6} -eq 1 ]]; then
				printf " && firewall-cmd --remove-rich-rule='rule family=ipv6 source address=%s/64 masquerade'\n" "${FW6}"
			else
				printf '\n'
			fi
		} >>"${WG_CONF}"
	else
		{
			echo "PostUp = iptables -I INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT"
			echo "PostUp = iptables -I FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT"
			echo "PostUp = iptables -I FORWARD -i ${SERVER_WG_NIC} -j ACCEPT"
			echo "PostUp = iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE"
			echo "PostDown = iptables -D INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT"
			echo "PostDown = iptables -D FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT"
			echo "PostDown = iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT"
			echo "PostDown = iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE"
			if [[ ${ENABLE_IPV6} -eq 1 ]]; then
				echo "PostUp = ip6tables -I FORWARD -i ${SERVER_WG_NIC} -j ACCEPT"
				echo "PostUp = ip6tables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE"
				echo "PostDown = ip6tables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT"
				echo "PostDown = ip6tables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE"
			fi
		} >>"${WG_CONF}"
	fi

	{
		echo "net.ipv4.ip_forward = 1"
		[[ ${ENABLE_IPV6} -eq 1 ]] && echo "net.ipv6.conf.all.forwarding = 1"
		if [[ ${DISABLE_IPV6_SYSCTL} -eq 1 ]]; then
			echo "net.ipv6.conf.all.disable_ipv6 = 1"
			echo "net.ipv6.conf.default.disable_ipv6 = 1"
			echo "net.ipv6.conf.lo.disable_ipv6 = 1"
		fi
	} >/etc/sysctl.d/wg.conf

	chmod 600 /etc/wireguard/*.conf 2>/dev/null || true

	if [[ ${OS} == 'alpine' ]]; then
		sysctl -p /etc/sysctl.d/wg.conf
		rc-update add sysctl
		ln -sf /etc/init.d/wg-quick "/etc/init.d/wg-quick.${SERVER_WG_NIC}"
		rc-service "wg-quick.${SERVER_WG_NIC}" start
		rc-update add "wg-quick.${SERVER_WG_NIC}"
	else
		sysctl --system >/dev/null
		systemctl start "wg-quick@${SERVER_WG_NIC}"
		systemctl enable "wg-quick@${SERVER_WG_NIC}"
	fi

	ok "Сервер WireGuard установлен."
	echo
	info "Сейчас будет создан первый клиент."
	newClient

	# [БАГ 6 исправлен] Проверяем статус ПОСЛЕ старта службы
	if [[ ${OS} == 'alpine' ]]; then
		rc-service --quiet "wg-quick.${SERVER_WG_NIC}" status &>/dev/null
		WG_RUNNING=$?
	else
		systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"
		WG_RUNNING=$?
	fi
	if [[ ${WG_RUNNING} -ne 0 ]]; then
		warn "Похоже, WireGuard не запущен."
		warn "Если видите «Cannot find device ${SERVER_WG_NIC}» — перезагрузите сервер."
	else
		ok "WireGuard успешно запущен."
	fi
}

# ─── Управление клиентами ──────────────────────────────────────────────────
newClient() {
	local SERVER_PUB_IP_FMT="${SERVER_PUB_IP}"
	if [[ ${SERVER_PUB_IP_FMT} =~ : && ${SERVER_PUB_IP_FMT} != *"["* ]]; then
		SERVER_PUB_IP_FMT="[${SERVER_PUB_IP_FMT}]"
	fi
	local ENDPOINT="${SERVER_PUB_IP_FMT}:${SERVER_PORT}"
	local CONF="/etc/wireguard/${SERVER_WG_NIC}.conf"

	box "Добавление нового клиента"
	info "Имя: латиница, цифры, дефис и подчёркивание; до 15 символов."

	# [БАГ 7 исправлен] CLIENT_EXISTS инициализируется как "" (не 0/1)
	local CLIENT_NAME="" CLIENT_EXISTS
	while true; do
		read -rp "$(printf '  Имя клиента: ')" CLIENT_NAME
		[[ -z $CLIENT_NAME ]] && { warn "Имя не может быть пустым."; continue; }
		if [[ ! ${CLIENT_NAME} =~ ^[a-zA-Z0-9_-]+$ ]]; then
			warn "Допустимы только латиница, цифры, дефис и подчёркивание."; continue
		fi
		if [[ ${#CLIENT_NAME} -ge 16 ]]; then
			warn "Имя слишком длинное (максимум 15 символов)."; continue
		fi
		CLIENT_EXISTS=$(grep -c -E "^### Client ${CLIENT_NAME}\$" "${CONF}" 2>/dev/null || true)
		CLIENT_EXISTS="${CLIENT_EXISTS//[$'\t\r\n ']}"   # убираем пробелы и переводы строк
		CLIENT_EXISTS="${CLIENT_EXISTS:-0}"
		if [[ ! ${CLIENT_EXISTS} =~ ^[0-9]+$ ]]; then CLIENT_EXISTS=0; fi
		if [[ ${CLIENT_EXISTS} -ne 0 ]]; then
			warn "Клиент «${CLIENT_NAME}» уже существует, выберите другое имя."; continue
		fi
		break
	done

	# Свободный .X
	local DOT_IP="" FOUND=0 i
	for i in {2..254}; do
		if ! grep -q "${SERVER_WG_IPV4%.*}\.${i}" "${CONF}"; then
			DOT_IP=$i; FOUND=1; break
		fi
	done
	if [[ ${FOUND} -eq 0 ]]; then
		err "Подсеть исчерпана (максимум 253 клиента)."; return 1
	fi

	local BASE_IP="${SERVER_WG_IPV4%.*}"
	local CLIENT_WG_IPV4="" IPV4_EXISTS
	info "Предлагаемый адрес: ${BOLD}${BASE_IP}.${DOT_IP}${NC} (нажмите Enter для принятия)"
	while true; do
		read -rp "$(printf '  %bIPv4 клиента%b (%s.?) %b[%s]%b : ' \
			"$WHITE" "$NC" "${BASE_IP}" "$GREEN" "${DOT_IP}" "$NC")" _dot || _dot=""
		local CUR_DOT="${_dot:-${DOT_IP}}"
		if [[ ! ${CUR_DOT} =~ ^[0-9]+$ ]] || (( CUR_DOT < 2 || CUR_DOT > 254 )); then
			warn "Введите число в диапазоне 2–254."; continue
		fi
		CLIENT_WG_IPV4="${BASE_IP}.${CUR_DOT}"
		IPV4_EXISTS=$(grep -c "${CLIENT_WG_IPV4}/32" "${CONF}" 2>/dev/null || true)
		IPV4_EXISTS="${IPV4_EXISTS//[$'\t\r\n ']}"
		IPV4_EXISTS="${IPV4_EXISTS:-0}"
		if [[ ! ${IPV4_EXISTS} =~ ^[0-9]+$ ]]; then IPV4_EXISTS=0; fi
		if [[ ${IPV4_EXISTS} -ne 0 ]]; then
			warn "Этот IPv4 уже занят."; continue
		fi
		DOT_IP="${CUR_DOT}"; break
	done

	local CLIENT_WG_IPV6="" CLIENT_ADDR=""
	if [[ ${ENABLE_IPV6} -eq 1 && -n ${SERVER_WG_IPV6} ]]; then
		local IPV6_BASE V6_SUFFIX="${DOT_IP}" IPV6_EXISTS
		IPV6_BASE=$(echo "${SERVER_WG_IPV6}" | awk -F '::' '{print $1}')
		while true; do
			read -rp "$(printf '  %bIPv6 клиента%b (%s::?) %b[%s]%b : ' \
				"$WHITE" "$NC" "${IPV6_BASE}" "$GREEN" "${DOT_IP}" "$NC")" _v6 || _v6=""
			V6_SUFFIX="${_v6:-${DOT_IP}}"
			CLIENT_WG_IPV6="${IPV6_BASE}::${V6_SUFFIX}"
			IPV6_EXISTS=$(grep -c "${CLIENT_WG_IPV6}/128" "${CONF}" 2>/dev/null || true)
			IPV6_EXISTS="${IPV6_EXISTS//[$'\t\r\n ']}"
			IPV6_EXISTS="${IPV6_EXISTS:-0}"
			if [[ ! ${IPV6_EXISTS} =~ ^[0-9]+$ ]]; then IPV6_EXISTS=0; fi
			if [[ ${IPV6_EXISTS} -ne 0 ]]; then
				warn "Этот IPv6 уже занят."; continue
			fi
			break
		done
		CLIENT_ADDR="${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128"
	else
		CLIENT_ADDR="${CLIENT_WG_IPV4}/32"
	fi

	local CLIENT_PRIV_KEY CLIENT_PUB_KEY CLIENT_PRE_SHARED_KEY
	CLIENT_PRIV_KEY=$(wg genkey)
	CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | wg pubkey)
	CLIENT_PRE_SHARED_KEY=$(wg genpsk)

	local HOME_DIR CLIENT_FILE DNS_LINE
	HOME_DIR=$(getHomeDirForClient "${CLIENT_NAME}")
	CLIENT_FILE="${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

	if [[ -n ${CLIENT_DNS_2} && ${CLIENT_DNS_2} != "${CLIENT_DNS_1}" ]]; then
		DNS_LINE="${CLIENT_DNS_1},${CLIENT_DNS_2}"
	else
		DNS_LINE="${CLIENT_DNS_1}"
	fi

	(
		umask 077
		cat >"${CLIENT_FILE}" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_ADDR}
DNS = ${DNS_LINE}

# Раскомментируйте, чтобы задать MTU вручную
# (см. https://github.com/nitred/nr-wg-mtu-finder)
# MTU = 1420

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
Endpoint = ${ENDPOINT}
AllowedIPs = ${ALLOWED_IPS}
EOF
	)

	{
		echo
		echo "### Client ${CLIENT_NAME}"
		echo "[Peer]"
		echo "PublicKey = ${CLIENT_PUB_KEY}"
		echo "PresharedKey = ${CLIENT_PRE_SHARED_KEY}"
		if [[ ${ENABLE_IPV6} -eq 1 && -n ${SERVER_WG_IPV6} ]]; then
			echo "AllowedIPs = ${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128"
		else
			echo "AllowedIPs = ${CLIENT_WG_IPV4}/32"
		fi
	} >>"${CONF}"

	wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}") || \
		warn "Не удалось перезагрузить конфиг — возможно интерфейс не активен."

	showClientQR "${CLIENT_FILE}"
	ok "Конфиг клиента сохранён: ${BOLD}${CLIENT_FILE}${NC}"
}

showClientQR() {
	local FILE="$1"
	if [[ ! -r $FILE ]]; then
		err "Файл конфигурации не найден: ${FILE}"; return 1
	fi
	if ! command -v qrencode &>/dev/null; then
		warn "qrencode не установлен — QR-код пропущен."
		return 0
	fi

	# Читаем содержимое в переменную, чтобы передать одинаковый поток
	# во все вызовы qrencode (повторный read из файла на некоторых ФС
	# мог давать пустой ввод и «битый» QR при повторном просмотре).
	local PAYLOAD
	PAYLOAD=$(cat -- "${FILE}")
	if [[ -z ${PAYLOAD} ]]; then
		err "Конфиг пуст или недоступен для чтения: ${FILE}"
		return 1
	fi

	printf '\n%b  ┌─ Отсканируйте QR-код приложением WireGuard ─┐%b\n' "$GREEN" "$NC"
	# Полный сброс атрибутов терминала перед выводом QR,
	# иначе остаточные ANSI-цвета (например, от box/info) делают
	# код неконтрастным и нечитаемым камерой при повторном вызове.
	printf '\033[0m\n'

	# Пробуем форматы по убыванию совместимости:
	#   utf8   — сплошные unicode-блоки без ANSI-цветов (лучше всего сканируется)
	#   ansiutf8i — инверсный ansi (для светлых терминалов)
	#   ansiutf8  — последний фолбэк
	local QR_OK=0
	for FMT in utf8 ansiutf8i ansiutf8; do
		if printf '%s' "${PAYLOAD}" | qrencode -t "${FMT}" -l L 2>/dev/null; then
			QR_OK=1
			break
		fi
	done
	if [[ ${QR_OK} -eq 0 ]]; then
		warn "Не удалось сгенерировать QR в терминале (старая версия qrencode?)."
	fi

	printf '\033[0m\n'
	printf '%b  └──────────────────────────────────────────────┘%b\n\n' "$GREEN" "$NC"

	local PNG="${FILE%.conf}.png"
	if printf '%s' "${PAYLOAD}" | qrencode -t png -l L -o "${PNG}" 2>/dev/null; then
		chmod 600 "${PNG}"
		info "QR также сохранён в PNG: ${BOLD}${PNG}${NC}"
	fi
	echo
}

listClients() {
	local CONF="/etc/wireguard/${SERVER_WG_NIC}.conf"
	local N; N=$(countClients "$CONF")
	if [[ ${N} -eq 0 ]]; then
		warn "Список клиентов пуст."
		return 1
	fi
	box "Существующие клиенты (${N})"
	local i=1
	while IFS= read -r name; do
		printf '  %b%2d)%b  %b%s%b\n' "$CYAN" "$i" "$NC" "$BOLD" "$name" "$NC"
		(( i++ ))
	done < <(grep -E "^### Client " "${CONF}" | cut -d ' ' -f 3)
	echo
}

showClient() {
	local CONF="/etc/wireguard/${SERVER_WG_NIC}.conf"
	local N; N=$(countClients "$CONF")
	[[ ${N} -eq 0 ]] && { warn "Нет клиентов для отображения."; return 1; }

	listClients
	local NUM=""
	until [[ ${NUM} =~ ^[0-9]+$ ]] && (( NUM >= 1 && NUM <= N )); do
		read -rp "$(printf '  Выберите клиента [1-%d]: ' "$N")" NUM
	done
	local NAME HOME_DIR FILE
	NAME=$(grep -E "^### Client " "${CONF}" | cut -d ' ' -f 3 | sed -n "${NUM}p")
	HOME_DIR=$(getHomeDirForClient "${NAME}")
	FILE="${HOME_DIR}/${SERVER_WG_NIC}-client-${NAME}.conf"
	if [[ ! -f $FILE ]]; then
		err "Файл конфигурации для «${NAME}» отсутствует: ${FILE}"
		return 1
	fi
	box "Клиент: ${NAME}"
	showClientQR "${FILE}"
	info "Путь к файлу: ${FILE}"
}

revokeClient() {
	local CONF="/etc/wireguard/${SERVER_WG_NIC}.conf"
	local N; N=$(countClients "$CONF")
	[[ ${N} -eq 0 ]] && { warn "Нет клиентов для удаления."; return 1; }

	box "Удаление клиента"
	local i=1
	while IFS= read -r name; do
		printf '  %b%2d)%b  %s\n' "$YELLOW" "$i" "$NC" "$name"
		(( i++ ))
	done < <(grep -E "^### Client " "${CONF}" | cut -d ' ' -f 3)
	echo

	local NUM=""
	until [[ ${NUM} =~ ^[0-9]+$ ]] && (( NUM >= 1 && NUM <= N )); do
		read -rp "$(printf '  Выберите клиента для удаления [1-%d]: ' "$N")" NUM
	done
	local NAME HOME_DIR
	NAME=$(grep -E "^### Client " "${CONF}" | cut -d ' ' -f 3 | sed -n "${NUM}p")

	echo
	printf '%b  ⚠  Удаление клиента «%s» необратимо!%b\n' "$YELLOW$BOLD" "${NAME}" "$NC"
	confirm "  Действительно удалить «${NAME}»?" n || { msg "  Отменено."; return 0; }

	sed -i "/^### Client ${NAME}\$/,/^[[:space:]]*\$/d" "${CONF}"
	HOME_DIR=$(getHomeDirForClient "${NAME}")
	rm -f "${HOME_DIR}/${SERVER_WG_NIC}-client-${NAME}.conf" \
	      "${HOME_DIR}/${SERVER_WG_NIC}-client-${NAME}.png"
	wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}") || \
		warn "Не удалось перезагрузить конфиг — возможно интерфейс не активен."
	ok "Клиент «${NAME}» удалён."
}

# НОВЫЙ ПУНКТ: смена DNS для существующего клиента
changeDnsClient() {
	local CONF="/etc/wireguard/${SERVER_WG_NIC}.conf"
	local N; N=$(countClients "$CONF")
	[[ ${N} -eq 0 ]] && { warn "Нет клиентов для изменения."; return 1; }

	box "Смена DNS клиента"
	listClients

	local NUM=""
	until [[ ${NUM} =~ ^[0-9]+$ ]] && (( NUM >= 1 && NUM <= N )); do
		read -rp "$(printf '  Выберите клиента [1-%d]: ' "$N")" NUM
	done
	local NAME HOME_DIR FILE
	NAME=$(grep -E "^### Client " "${CONF}" | cut -d ' ' -f 3 | sed -n "${NUM}p")
	HOME_DIR=$(getHomeDirForClient "${NAME}")
	FILE="${HOME_DIR}/${SERVER_WG_NIC}-client-${NAME}.conf"
	if [[ ! -f $FILE ]]; then
		err "Файл конфигурации для «${NAME}» отсутствует: ${FILE}"
		return 1
	fi

	local CUR_DNS NEW_DNS1 NEW_DNS2
	CUR_DNS=$(grep -E "^DNS\s*=" "${FILE}" | head -1 | cut -d'=' -f2 | tr -d ' ')
	info "Текущий DNS: ${BOLD}${CUR_DNS}${NC}"

	NEW_DNS1=""
	until [[ ${NEW_DNS1} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; do
		read -rp "$(printf '  Новый основной DNS: ')" NEW_DNS1
	done
	read -rp "$(printf '  Новый резервный DNS (Enter — тот же): ')" NEW_DNS2 || NEW_DNS2=""
	[[ -z ${NEW_DNS2} ]] && NEW_DNS2="${NEW_DNS1}"

	local NEW_DNS_LINE="${NEW_DNS1}"
	[[ ${NEW_DNS2} != "${NEW_DNS1}" ]] && NEW_DNS_LINE="${NEW_DNS1},${NEW_DNS2}"

	sed -i "s|^DNS = .*|DNS = ${NEW_DNS_LINE}|" "${FILE}"
	ok "DNS клиента «${NAME}» обновлён: ${BOLD}${NEW_DNS_LINE}${NC}"
	warn "Клиенту нужно переимпортировать конфиг (новый QR ниже)."
	showClientQR "${FILE}"
}

restartWg() {
	box "Перезапуск службы WireGuard"
	if [[ ${OS} == 'alpine' ]]; then
		rc-service "wg-quick.${SERVER_WG_NIC}" restart && ok "Служба перезапущена."
	else
		systemctl restart "wg-quick@${SERVER_WG_NIC}" && ok "Служба перезапущена."
	fi
}

statusWg() {
	box "Статус WireGuard"
	if command -v wg &>/dev/null; then
		wg show "${SERVER_WG_NIC}" 2>/dev/null || warn "Интерфейс ${SERVER_WG_NIC} не активен."
	fi
	echo
	if [[ ${OS} == 'alpine' ]]; then
		rc-service "wg-quick.${SERVER_WG_NIC}" status || true
	else
		systemctl --no-pager status "wg-quick@${SERVER_WG_NIC}" 2>/dev/null | head -n 12 || true
	fi
}

uninstallWg() {
	box_double "Полное удаление WireGuard"
	printf '%b  ██  ВНИМАНИЕ! Это действие необратимо!  ██%b\n\n' "$RED$BOLD" "$NC"
	warn "  Будут удалены WireGuard и ВСЯ конфигурация в /etc/wireguard."
	warn "  Все клиентские конфиги и ключи будут уничтожены навсегда."
	echo
	confirm "  Вы абсолютно уверены? Продолжить?" n || { msg "  Отменено."; return 0; }
	echo
	confirm "  Последнее предупреждение — удалить WireGuard?" n || { msg "  Отменено."; return 0; }

	if [[ ${OS} == 'alpine' ]]; then
		rc-service "wg-quick.${SERVER_WG_NIC}" stop || true
		rc-update del "wg-quick.${SERVER_WG_NIC}" || true
		unlink "/etc/init.d/wg-quick.${SERVER_WG_NIC}" 2>/dev/null || true
		rc-update del sysctl || true
	else
		systemctl stop "wg-quick@${SERVER_WG_NIC}" || true
		systemctl disable "wg-quick@${SERVER_WG_NIC}" || true
	fi

	case "${OS}" in
		ubuntu|debian) apt-get remove -y wireguard wireguard-tools qrencode || true ;;
		fedora)
			dnf remove -y --noautoremove wireguard-tools qrencode || true
			if [[ ${VERSION_ID%%.*} -lt 32 ]]; then
				dnf remove -y --noautoremove wireguard-dkms || true
				dnf copr disable -y jdoss/wireguard || true
			fi ;;
		centos|almalinux|rocky)
			yum remove -y --noautoremove wireguard-tools || true
			[[ ${VERSION_ID} == 8* ]] && yum remove -y --noautoremove kmod-wireguard qrencode || true ;;
		oracle) yum remove -y --noautoremove wireguard-tools qrencode || true ;;
		arch)   pacman -Rs --noconfirm wireguard-tools qrencode || true ;;
		alpine) apk del wireguard-tools libqrencode libqrencode-tools || true ;;
	esac

	rm -rf /etc/wireguard
	rm -f /etc/sysctl.d/wg.conf

	sysctl --system >/dev/null 2>&1 || true

	# [БАГ 6 исправлен] Проверяем статус ПОСЛЕ удаления
	if [[ ${OS} == 'alpine' ]]; then
		rc-service --quiet "wg-quick.${SERVER_WG_NIC}" status &>/dev/null
		WG_RUNNING=$?
	else
		systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}" 2>/dev/null
		WG_RUNNING=$?
	fi

	if [[ ${WG_RUNNING} -eq 0 ]]; then
		err "Не удалось полностью удалить WireGuard."
		exit 1
	else
		ok "WireGuard успешно удалён."
		exit 0
	fi
}

showAbout() {
	banner
	box_double "О программе"
	printf '  %bWireGuard VPN Manager%b  v%s\n' "$BOLD$WHITE" "$NC" "${WG_MANAGER_VERSION}"
	printf '  %bГод: %b%s\n\n' "$DIM" "$NC" "${WG_MANAGER_DATE}"
	printf '  %bОписание:%b\n' "$BOLD" "$NC"
	printf '  Менеджер установки и управления WireGuard VPN-сервером.\n'
	printf '  Поддерживает Debian, Ubuntu, Fedora, CentOS, AlmaLinux,\n'
	printf '  Rocky, Oracle Linux, Arch Linux, Alpine Linux.\n\n'
	hr_thin
	printf '\n  %bФункции:%b\n' "$BOLD" "$NC"
	printf '  %b✓%b  Автоустановка WireGuard с мастером настройки\n' "$GREEN" "$NC"
	printf '  %b✓%b  Создание неограниченного числа клиентов\n' "$GREEN" "$NC"
	printf '  %b✓%b  QR-коды для быстрого подключения с телефона\n' "$GREEN" "$NC"
	printf '  %b✓%b  Поддержка IPv4 и IPv6 в туннеле\n' "$GREEN" "$NC"
	printf '  %b✓%b  Интеграция с firewalld и iptables\n' "$GREEN" "$NC"
	printf '  %b✓%b  Смена DNS без пересоздания клиента\n' "$GREEN" "$NC"
	printf '  %b✓%b  Полное удаление с очисткой конфигурации\n\n' "$GREEN" "$NC"
	hr_thin
	printf '\n  %bТребования:%b root-доступ, systemd или OpenRC, ядро ≥5.6\n\n' "$BOLD" "$NC"
}

# ─── Главное меню (цикл вместо рекурсии) ───────────────────────────────────
manageMenu() {
	# [УЛУЧШение: рекурсия → while true]
	while true; do
		banner

		# Защита переменных
		: "${SERVER_PUB_IP:=<не задан>}"
		: "${SERVER_PORT:=<не задан>}"
		: "${SERVER_WG_NIC:=wg0}"

		# Статус сервиса
		local STATUS_TXT STATUS_COLOR IS_ACTIVE=0
		if [[ ${OS} == 'alpine' ]]; then
			if rc-service --quiet "wg-quick.${SERVER_WG_NIC}" status &>/dev/null; then
				STATUS_TXT="● работает"; STATUS_COLOR="$GREEN"; IS_ACTIVE=1
			else
				STATUS_TXT="● остановлен"; STATUS_COLOR="$RED"
			fi
		else
			if systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"; then
				STATUS_TXT="● работает"; STATUS_COLOR="$GREEN"; IS_ACTIVE=1
			else
				STATUS_TXT="● остановлен"; STATUS_COLOR="$RED"
			fi
		fi

		local N; N=$(countClients)
		local ACTIVE_P=""
		if [[ ${IS_ACTIVE} -eq 1 ]]; then
			ACTIVE_P=$(countActivePeers)
		fi

		# ── Информационная панель ────────────────────────────────────────
		printf '  %b┌─────────────────────────────────────────────────────────────┐%b\n' "$BLUE" "$NC"
		printf '  %b│%b  %-18s %b%-30s%b  %b│%b\n' \
			"$BLUE" "$NC" "Сервер:" "$WHITE" "${SERVER_PUB_IP}:${SERVER_PORT}" "$NC" "$BLUE" "$NC"
		printf '  %b│%b  %-18s %b%-30s%b  %b│%b\n' \
			"$BLUE" "$NC" "Интерфейс:" "$WHITE" "${SERVER_WG_NIC}" "$NC" "$BLUE" "$NC"
		printf '  %b│%b  %-18s %b%-10s%b  Статус: %b%-20s%b  %b│%b\n' \
			"$BLUE" "$NC" \
			"Клиентов:" "$WHITE" "${N}" "$NC" \
			"${STATUS_COLOR}" "${STATUS_TXT}" "$NC" \
			"$BLUE" "$NC"
		if [[ -n ${ACTIVE_P} ]]; then
			printf '  %b│%b  %-18s %b%-30s%b  %b│%b\n' \
				"$BLUE" "$NC" "Активных пиров:" "$CYAN" "${ACTIVE_P}" "$NC" "$BLUE" "$NC"
		fi
		printf '  %b└─────────────────────────────────────────────────────────────┘%b\n\n' "$BLUE" "$NC"

		# ── Меню ─────────────────────────────────────────────────────────
		printf '  %b╔═══════════════════════════════════════╗%b\n' "$CYAN" "$NC"
		printf '  %b║%b   %bУПРАВЛЕНИЕ КЛИЕНТАМИ%b                %b║%b\n' "$CYAN" "$NC" "$BOLD$WHITE" "$NC" "$CYAN" "$NC"
		printf '  %b╠═══════════════════════════════════════╣%b\n' "$CYAN" "$NC"
		printf '  %b║%b  %b1)%b  Добавить нового клиента           %b║%b\n' "$CYAN" "$NC" "$GREEN$BOLD" "$NC" "$CYAN" "$NC"
		printf '  %b║%b  %b2)%b  Показать список клиентов          %b║%b\n' "$CYAN" "$NC" "$GREEN$BOLD" "$NC" "$CYAN" "$NC"
		printf '  %b║%b  %b3)%b  Показать конфиг и QR клиента      %b║%b\n' "$CYAN" "$NC" "$GREEN$BOLD" "$NC" "$CYAN" "$NC"
		printf '  %b║%b  %b4)%b  Удалить клиента                   %b║%b\n' "$CYAN" "$NC" "$YELLOW$BOLD" "$NC" "$CYAN" "$NC"
		printf '  %b║%b  %b5)%b  Сменить DNS клиента               %b║%b\n' "$CYAN" "$NC" "$BLUE$BOLD" "$NC" "$CYAN" "$NC"
		printf '  %b╠═══════════════════════════════════════╣%b\n' "$CYAN" "$NC"
		printf '  %b║%b   %bСЕРВЕР%b                               %b║%b\n' "$CYAN" "$NC" "$BOLD$WHITE" "$NC" "$CYAN" "$NC"
		printf '  %b╠═══════════════════════════════════════╣%b\n' "$CYAN" "$NC"
		printf '  %b║%b  %b6)%b  Показать статус сервера           %b║%b\n' "$CYAN" "$NC" "$BLUE$BOLD" "$NC" "$CYAN" "$NC"
		printf '  %b║%b  %b7)%b  Перезапустить службу              %b║%b\n' "$CYAN" "$NC" "$BLUE$BOLD" "$NC" "$CYAN" "$NC"
		printf '  %b╠═══════════════════════════════════════╣%b\n' "$CYAN" "$NC"
		printf '  %b║%b   %bОПАСНАЯ ЗОНА%b                         %b║%b\n' "$CYAN" "$NC" "$BOLD$RED" "$NC" "$CYAN" "$NC"
		printf '  %b╠═══════════════════════════════════════╣%b\n' "$CYAN" "$NC"
		printf '  %b║%b  %b8)%b  Удалить WireGuard полностью       %b║%b\n' "$CYAN" "$NC" "$RED$BOLD" "$NC" "$CYAN" "$NC"
		printf '  %b╠═══════════════════════════════════════╣%b\n' "$CYAN" "$NC"
		printf '  %b║%b  %b9)%b  О программе                       %b║%b\n' "$CYAN" "$NC" "$GRAY$BOLD" "$NC" "$CYAN" "$NC"
		printf '  %b║%b  %b0)%b  Выход                             %b║%b\n' "$CYAN" "$NC" "$GRAY$BOLD" "$NC" "$CYAN" "$NC"
		printf '  %b╚═══════════════════════════════════════╝%b\n\n' "$CYAN" "$NC"

		local OPT=""
		until [[ ${OPT} =~ ^[0-9]$ ]]; do
			read -rp "$(printf '  %b▶%b Выберите пункт меню [0-9]: ' "$CYAN$BOLD" "$NC")" OPT
		done

		case "${OPT}" in
			1) newClient ;;
			2) listClients ;;
			3) showClient ;;
			4) revokeClient ;;
			5) changeDnsClient ;;
			6) statusWg ;;
			7) restartWg ;;
			8) uninstallWg ;;
			9) showAbout ;;
			0) echo; ok "До встречи!"; exit 0 ;;
		esac

		pause
	done
}

# ─── Точка входа ───────────────────────────────────────────────────────────
initialCheck

if [[ -e /etc/wireguard/params ]]; then
	# shellcheck disable=SC1091
	source /etc/wireguard/params
	: "${ENABLE_IPV6:=1}"
	: "${DISABLE_IPV6_SYSCTL:=0}"
	: "${SERVER_WG_NIC:=wg0}"
	manageMenu
else
	installWireGuard
fi
