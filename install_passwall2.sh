#!/bin/sh
# =============================================================================
# install_passwall2.sh
# Скрипт автоматической установки PassWall2 на OpenWrt 25+ (apk/opkg)
# Архитектура: aarch64_cortex-a53 (и другие)
#
# Использование на роутере:
#   cd /tmp
#   wget https://<your_host>/install_passwall2.sh
#   sh install_passwall2.sh              # автоопределение версии
#   sh install_passwall2.sh 26.5.1-1     # конкретная версия (тег)
#   sh install_passwall2.sh --no-deps    # без зависимостей
# =============================================================================



REPO="Openwrt-Passwall/openwrt-passwall2"
ARCH=""
ARCH_APK=""
ARCH_IPK=""
INSTALL_DIR="/tmp/passwall2_install"
LANG_CODE="ru"

PW2_TAG=""
PW2_VERSION=""
PW2_RELEASE=""
SKIP_DEPS=0


# --- Цвета ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
log_warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

# --- Получение тега последнего релиза ---
get_latest_version() {
    log_info "Получение информации о последнем релизе с GitHub..."

    # Способ 1: GitHub API + jsonfilter
    if command -v jsonfilter >/dev/null 2>&1; then
        local api_url="https://api.github.com/repos/${REPO}/releases/latest"
        PW2_TAG=$(curl -sk --max-time 20 "$api_url" 2>/dev/null | jsonfilter -e '@.tag_name' 2>/dev/null) || true
        if [ -n "${PW2_TAG}" ]; then
            log_info "Найден тег через API+jsonfilter: ${PW2_TAG}"
            parse_tag
            return 0
        fi
    fi

    # Способ 2: GitHub API + python
    if command -v python >/dev/null 2>&1; then
        local api_url="https://api.github.com/repos/${REPO}/releases/latest"
        PW2_TAG=$(curl -sk --max-time 20 "$api_url" 2>/dev/null | python -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null) || true
        if [ -n "${PW2_TAG}" ]; then
            log_info "Найден тег через API+python: ${PW2_TAG}"
            parse_tag
            return 0
        fi
    fi

    # Способ 3: HTTP redirect (Location header)
    local loc
    loc=$(curl -skI --max-time 20 -o /dev/null -w '%{redirect_url}' "https://github.com/${REPO}/releases/latest" 2>/dev/null) || loc=""
    if [ -n "${loc}" ]; then
        PW2_TAG=$(echo "${loc}" | sed 's|.*/tag/||;s/\?.*//')
        if [ -n "${PW2_TAG}" ] && [ "${PW2_TAG}" != "${loc}" ]; then
            log_info "Найден тег через redirect: ${PW2_TAG}"
            parse_tag
            return 0
        fi
    fi

    # Способ 4: wget redirect
    loc=$(wget -q --no-check-certificate --timeout=20 -O /dev/null --server-response "https://github.com/${REPO}/releases/latest" 2>&1 | grep '^Location:' | sed 's/.*Location: //' | tr -d '\r') || loc=""
    if [ -n "${loc}" ]; then
        PW2_TAG=$(echo "${loc}" | sed 's|.*/tag/||;s/\?.*//')
        if [ -n "${PW2_TAG}" ]; then
            log_info "Найден тег через wget redirect: ${PW2_TAG}"
            parse_tag
            return 0
        fi
    fi

    # Способ 5: HTML парсинг через wget
    local html
    html=$(wget -q --no-check-certificate --timeout=20 -O - "https://github.com/${REPO}/releases/latest" 2>/dev/null) || html=""
    if [ -n "${html}" ]; then
        PW2_TAG=$(echo "${html}" | tr '"' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$' | head -1)
        if [ -z "${PW2_TAG}" ]; then
            PW2_TAG=$(echo "${html}" | tr '"' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        fi
        if [ -n "${PW2_TAG}" ]; then
            log_info "Найден тег через HTML: ${PW2_TAG}"
            parse_tag
            return 0
        fi
    fi

    log_error "Не удалось определить версию релиза!"
    log_error "Укажите версию вручную: sh $0 <тег>  (пример: sh $0 26.5.1-1)"
    exit 1
}

# --- Парсинг тега ---
parse_tag() {
    local tag="${PW2_TAG}"
    local release_part

    # Извлекаем числовой суффикс после последнего дефиса
    release_part=$(echo "${tag}" | sed 's/.*-//')

    if echo "${release_part}" | grep -qE '^[0-9]+$'; then
        PW2_VERSION=$(echo "${tag}" | sed 's/-[0-9]*$//')
        PW2_RELEASE="${release_part}"
    else
        PW2_VERSION="${tag}"
        PW2_RELEASE=""
    fi

    log_info "Версия: ${PW2_VERSION}, Релиз: ${PW2_RELEASE:-none}"
}

# --- Определение архитектуры ---
detect_arch() {
    local machine
    local owrt_arch

    machine=$(uname -m 2>/dev/null)
    owrt_arch=$(grep DISTRIB_ARCH /etc/openwrt_release 2>/dev/null | cut -d= -f2 | tr -d '"')

    # Сначала используем OpenWrt ARCH если доступен
    case "${owrt_arch}" in
        aarch64_generic)
            ARCH_APK="aarch64_generic"
            ARCH_IPK="aarch64_generic"
            ;;

        aarch64_cortex-a53)
            ARCH_APK="aarch64_cortex-a53"
            ARCH_IPK="aarch64_cortex-a53"
            ;;

        aarch64_cortex-a72)
            ARCH_APK="aarch64_cortex-a72"
            ARCH_IPK="aarch64_cortex-a72"
            ;;

        arm_cortex-a15_neon-vfpv4|\
        arm_cortex-a9_neon|\
        arm_cortex-a8_vfpv3|\
        arm_cortex-a5_vfpv4|\
        arm_cortex-a7|\
        mips_4kec|\
        mips_mips32|\
        mipsel_24kc|\
        mipsel_74kc|\
        mipsel_mips32|\
        x86_64|\
        i386)

            ARCH_APK="${owrt_arch}"
            ARCH_IPK="${owrt_arch}"
            ;;
    esac

    # Если OpenWrt ARCH не найден — fallback
    if [ -z "${ARCH_APK}" ] || [ -z "${ARCH_IPK}" ]; then
        case "${machine}" in
            x86_64)
                ARCH_APK="x86_64"
                ARCH_IPK="x86_64"
                ;;

            aarch64)
                ARCH_APK="aarch64_generic"
                ARCH_IPK="aarch64_generic"
                ;;

            armv7l)
                ARCH_APK="arm_cortex-a7"
                ARCH_IPK="arm_cortex-a7"
                ;;

            i686)
                ARCH_APK="i386"
                ARCH_IPK="i386"
                ;;

            mips)
                ARCH_APK="mips_mips32"
                ARCH_IPK="mips_mips32"
                ;;

            mipsel)
                ARCH_APK="mipsel_mips32"
                ARCH_IPK="mipsel_mips32"
                ;;

            *)
                ARCH_APK="${machine}"
                ARCH_IPK="${machine}"
                ;;
        esac
    fi

    log_info "OpenWrt ARCH: ${owrt_arch:-unknown}"
    log_info "Архитектура APK: ${ARCH_APK}"
    log_info "Архитектура IPK: ${ARCH_IPK}"
}

# --- Определение пакетного менеджера ---
detect_pkg_manager() {
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        log_info "Пакетный менеджер: apk"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
        log_info "Пакетный менеджер: opkg"
    else
        log_error "Не найден пакетный менеджер (apk или opkg)!"
        exit 1
    fi
}

# --- Проверка платформы ---
check_platform() {
    log_info "Проверка платформы..."
    if [ -f /etc/openwrt_release ]; then
        local desc arch target
        desc=$(grep DISTRIB_DESCRIPTION /etc/openwrt_release 2>/dev/null | cut -d= -f2 | tr -d '"')
        arch=$(grep DISTRIB_ARCH /etc/openwrt_release 2>/dev/null | cut -d= -f2 | tr -d '"')
        target=$(grep DISTRIB_TARGET /etc/openwrt_release 2>/dev/null | cut -d= -f2 | tr -d '"')
        log_info "OpenWrt: ${desc:-unknown}"
        log_info "Архитектура: ${arch:-unknown}"
        log_info "Target: ${target:-unknown}"
    fi
    log_info "uname -m: $(uname -m 2>/dev/null || echo unknown)"
}

# --- Создание рабочей директории ---
setup_workdir() {
    log_info "Рабочая директория: ${INSTALL_DIR}"
    rm -rf "${INSTALL_DIR}"
    mkdir -p "${INSTALL_DIR}"
}

# --- Скачивание файла ---
download_file() {
    local url="$1"
    local dest="$2"
    local name
    name=$(basename "${dest}")

    log_info "Скачивание: ${name}"

    # GitHub требует Accept header для бинарного контента через API/redirect
    if command -v curl >/dev/null 2>&1; then
        if curl -skL --max-time 120 \
            -H "Accept: application/octet-stream" \
            -o "${dest}" "${url}" 2>/dev/null; then
            local size
            size=$(wc -c < "${dest}" 2>/dev/null || echo 0)
            # Проверяем минимальный размер (APK минимум ~10KB)
            if [ "${size}" -lt 1000 ]; then
                log_error "  Файл слишком маленький (${size} байт), вероятно 404"
                rm -f "${dest}"
                return 1
            fi
            log_info "  OK: ${name} (${size} байт)"
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --no-check-certificate --timeout=120 \
            --header="Accept: application/octet-stream" \
            -O "${dest}" "${url}" 2>/dev/null; then
            local size
            size=$(wc -c < "${dest}" 2>/dev/null || echo 0)
            if [ "${size}" -lt 1000 ]; then
                log_error "  Файл слишком маленький (${size} байт)"
                rm -f "${dest}"
                return 1
            fi
            log_info "  OK: ${name} (${size} байт)"
            return 0
        fi
    fi

    log_error "  Ошибка скачивания: ${url}"
    return 1
}

# --- Скачивание всех файлов ---
download_files() {
    local BASE="https://github.com/${REPO}/releases/download/${PW2_TAG}"
    local failed=0

    if [ "${PKG_MANAGER}" = "apk" ]; then
        log_info "Скачивание для ${ARCH_APK} (тег: ${PW2_TAG})..."
    else
        log_info "Скачивание для ${ARCH_IPK} (тег: ${PW2_TAG})..."
    fi
    log_info ""

    if [ "${PKG_MANAGER}" = "apk" ]; then
        # APK: luci-app-passwall2-{VERSION}-r{RELEASE}.apk
        if [ -n "${PW2_RELEASE}" ]; then
            download_file "${BASE}/luci-app-passwall2-${PW2_VERSION}-r${PW2_RELEASE}.apk" \
                "${INSTALL_DIR}/luci-app-passwall2.apk" || failed=1
        else
            download_file "${BASE}/luci-app-passwall2-${PW2_VERSION}.apk" \
                "${INSTALL_DIR}/luci-app-passwall2.apk" || failed=1
        fi

        # i18n: luci-i18n-passwall2-{LANG}-{VERSION}.apk (без -rN!)
        if [ -n "${LANG_CODE}" ]; then
            download_file "${BASE}/luci-i18n-passwall2-${LANG_CODE}-${PW2_VERSION}.apk" \
                "${INSTALL_DIR}/luci-i18n-passwall2-${LANG_CODE}.apk" || failed=1
        fi

        # Зависимости
        download_file "${BASE}/passwall_packages_apk_${ARCH_APK}.zip" \
            "${INSTALL_DIR}/passwall_packages.zip" || failed=1
    else
        # IPK: luci-app-passwall2_{VERSION}-r{RELEASE}_all.ipk
        if [ -n "${PW2_RELEASE}" ]; then
            download_file "${BASE}/luci-app-passwall2_${PW2_VERSION}-r${PW2_RELEASE}_all.ipk" \
                "${INSTALL_DIR}/luci-app-passwall2.ipk" || failed=1
        else
            download_file "${BASE}/luci-app-passwall2_${PW2_VERSION}_all.ipk" \
                "${INSTALL_DIR}/luci-app-passwall2.ipk" || failed=1
        fi

        if [ -n "${LANG_CODE}" ]; then
            download_file "${BASE}/luci-i18n-passwall2-${LANG_CODE}_${PW2_VERSION}_all.ipk" \
                "${INSTALL_DIR}/luci-i18n-passwall2-${LANG_CODE}.ipk" || failed=1
        fi

        download_file "${BASE}/passwall_packages_ipk_${ARCH_IPK}.zip" \
            "${INSTALL_DIR}/passwall_packages.zip" || failed=1
    fi

    if [ "${failed}" = "1" ]; then
        log_error "Ошибка скачивания некоторых файлов!"
        exit 1
    fi

    log_info ""
    log_info "Файлы скачаны:"
    ls -lh "${INSTALL_DIR}/"
}

# --- Проверка установлен ли пакет ---
is_installed() {
    local pkg="$1"
    local ver="$2"
    if [ "${PKG_MANAGER}" = "apk" ]; then
        if apk info --installed 2>/dev/null | grep -qx "${pkg}"; then
            if [ -n "${ver}" ]; then
                local installed_ver
                installed_ver=$(apk info --installed 2>/dev/null | grep "^${pkg}-" | sed "s/^${pkg}-//")
                if [ "${installed_ver}" = "${ver}" ]; then
                    return 0
                fi
            else
                return 0
            fi
        fi
    else
        if opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
            return 0
        fi
    fi
    return 1
}

# --- Установка базовых системных зависимостей ---
install_base_deps() {
    log_info "Установка базовых системных зависимостей..."

    if [ "${PKG_MANAGER}" = "apk" ]; then
        apk update >/dev/null 2>&1

        # Собираем недостающие пакеты
        local missing=""
        local pkgs="coreutils-base64 coreutils-nohup curl \
            libuci-lua lua luci-compat luci-lib-jsonc lyaml resolveip unzip kmod-nft-socket kmod-nft-nat kmod-nft-tproxy"

        for pkg in ${pkgs}; do
            if ! apk info --installed  "${pkg}"; then
                missing="${missing} ${pkg}"
                log_info "  Нужен: ${pkg}"
            fi
        done

        # ip-full: проверяем по-другому (альтернатива busybox ip)
        if ! command -v ip_full >/dev/null 2>&1 && [ ! -e /usr/libexec/ip-full ]; then
            if ! apk info --installed 2>/dev/null | grep -q "^ip-full$"; then
                missing="${missing} ip-full"
                log_info "  Нужен: ip-full"
            fi
        fi

        if [ -n "${missing}" ]; then
            log_info "Установка: ${missing}"
            apk add --no-cache ${missing} >/dev/null 2>/dev/null || {
                log_warn "Некоторые базовые пакеты не установились, пробуем по одному..."
                for pkg in ${missing}; do
                    apk add --no-cache "${pkg}"  log_warn "  Пропуск: ${pkg}"
                done
            }
        else
            log_info "Все базовые пакеты уже установлены."
        fi

        

    else
        opkg update >/dev/null 2>&1
        local missing=""
        local pkgs="coreutils-base64 coreutils-nohup curl \
            libuci-lua lua luci-compat luci-lib-jsonc lyaml resolveip unzip kmod-nft-socket kmod-nft-nat kmod-nft-tproxy"

        for pkg in ${pkgs}; do
            if ! opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
                missing="${missing} ${pkg}"
            fi
        done

        if [ -n "${missing}" ]; then
            for pkg in ${missing}; do
                opkg install "${pkg}" 2>/dev/null || log_warn "  Пропуск: ${pkg}"
            done
        fi
    fi
}

# --- Установка зависимостей из zip ---
install_zip_deps() {
    if [ ! -f "${INSTALL_DIR}/passwall_packages.zip" ]; then
        log_warn "Архив зависимостей отсутствует — пропускаем распаковку."
        return 0
    fi

    log_info "Распаковка зависимостей из zip..."

    cd "${INSTALL_DIR}"

    if ! command -v unzip >/dev/null 2>&1; then
        log_warn "unzip не найден..."
        if [ "${PKG_MANAGER}" = "apk" ]; then
            apk add --no-cache unzip >/dev/null 2>&1
        else
            opkg install unzip >/dev/null 2>&1
        fi
    fi

    unzip -o -q passwall_packages.zip -d packages/ 2>/dev/null

    if [ ! -d "${INSTALL_DIR}/packages" ] || [ -z "$(ls "${INSTALL_DIR}/packages" 2>/dev/null)" ]; then
        log_warn "Zip не распаковался, зависимости из стандартных репо."
        return 0
    fi

    if [ "${PKG_MANAGER}" = "apk" ]; then
        log_info "Установка зависимостей из zip (apk)..."
        cd packages
        # Собираем только те .apk, которых еще нет в системе.
        # Базовые зависимости (curl, unzip и др.) уже установлены на этапе install_base_deps.
        local to_install=""
        for f in *.apk; do
            [ -f "$f" ] || continue
            local pkg_name
            pkg_name=$(echo "$f" | sed 's/-[0-9~].*\.apk$//')
            if ! apk info --installed 2>/dev/null | grep -q "^${pkg_name}-"; then
                to_install="${to_install} ${f}"
            fi
        done

        if [ -n "${to_install}" ]; then
            if apk add --allow-untrusted --no-cache ${to_install} >/dev/null 2>/dev/null; then
                log_info "  Зависимости из zip установлены."
            else
                log_warn "  Некоторые пакеты из zip не установились (возможно, уже есть в системе)"
            fi
        else
            log_info "  Все пакеты из архива уже установлены."
        fi
        cd "${INSTALL_DIR}"
    else
        log_info "Установка зависимостей из zip (ipkg)..."
        cd packages
        for pkg in *.ipk; do
            [ -f "$pkg" ] || continue
            log_info "  Установка: ${pkg}"
            opkg install "${pkg}" --force-overwrite --force-depends 2>/dev/null || log_warn "  Пропуск: ${pkg}"
        done
        cd "${INSTALL_DIR}"
    fi
}

# --- Установка основного пакета ---
install_passwall2() {
    log_info "Установка PassWall2..."
    cd "${INSTALL_DIR}"

    if [ "${PKG_MANAGER}" = "apk" ]; then
        apk add --allow-untrusted --force-overwrite --no-cache luci-app-passwall2.apk || {
            log_error "Не удалось установить luci-app-passwall2!"
            exit 1
        }
        [ -n "${LANG_CODE}" ] && [ -f "luci-i18n-passwall2-${LANG_CODE}.apk" ] && \
            apk add --allow-untrusted --force-overwrite --no-cache "luci-i18n-passwall2-${LANG_CODE}.apk" 2>/dev/null || true
    else
        opkg install luci-app-passwall2.ipk --force-overwrite --force-depends || {
            log_error "Не удалось установить luci-app-passwall2!"
            exit 1
        }
        [ -n "${LANG_CODE}" ] && [ -f "luci-i18n-passwall2-${LANG_CODE}.ipk" ] && \
            opkg install "luci-i18n-passwall2-${LANG_CODE}.ipk" --force-overwrite --force-depends 2>/dev/null || true
    fi
    log_info "PassWall2 установлен."
}

# --- Пост-установка ---
post_install() {
    log_info "Пост-установочная настройка..."

    # uci-defaults
    [ -x /usr/share/passwall2/uci_defaults.sh ] && {
        log_info "Применение настроек по умолчанию..."
        /usr/share/passwall2/uci_defaults.sh 2>/dev/null || true
    }

    # ucitrack
    [ -e /etc/config/ucitrack ] && uci -q batch <<'EOF'
delete ucitrack.@passwall2[-1] 2>/dev/null
add ucitrack passwall2
set ucitrack.@passwall2[-1].init=passwall2
delete ucitrack.@passwall2_server[-1] 2>/dev/null
add ucitrack passwall2_server
set ucitrack.@passwall2_server[-1].init=passwall2_server
commit ucitrack
EOF

    # firewall
    [ -e /etc/config/firewall ] && uci -q batch <<'EOF'
delete firewall.passwall2
set firewall.passwall2=include
set firewall.passwall2.type='script'
set firewall.passwall2.path='/var/etc/passwall2.include'
delete firewall.passwall2_server
set firewall.passwall2_server=include
set firewall.passwall2_server.type='script'
set firewall.passwall2_server.path='/var/etc/passwall2_server.include'
set dhcp.@dnsmasq[0].localuse=1
commit dhcp
set uhttpd.main.max_requests=50
commit uhttpd
if [ -x "/sbin/fw3" ]; then
    uci -q set firewall.passwall2.reload='1'
    uci -q set firewall.passwall2_server.reload='1'
else
    uci -q delete firewall.passwall2.reload
    uci -q delete firewall.passwall2.fw4_compatible
    uci -q delete firewall.passwall2_server.reload
    uci -q delete firewall.passwall2_server.fw4_compatible
fi
uci commit firewall
EOF

    # restart LuCI
    [ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart 2>/dev/null

    log_info ""
    log_info "============================================"
    log_info "  PassWall2 v${PW2_VERSION} установлен!"
    log_info "============================================"
    log_info "  Далее: Сервисы -> PassWall2 в LuCI"
    log_info "  Логи: /tmp/log/passwall2.log"
    log_info ""
}

# --- Очистка ---
cleanup() {
    rm -rf "${INSTALL_DIR}"
}

# --- Аргументы ---
case "${1:-}" in
    --no-deps) SKIP_DEPS=1; shift ;;
    --clean)   rm -rf "${INSTALL_DIR}"; echo "Очищено."; exit 0 ;;
    --help|-h)
        echo "Использование: sh $0 [ОПЦИЯ] [ВЕРСИЯ]"
        echo "  --no-deps    Без зависимостей"
        echo "  --clean      Очистка"
        echo "  --help       Справка"
        echo "  ВЕРСИЯ       Тег релиза (пример: 26.5.1-1)"
        exit 0 ;;
    *) [ -n "${1:-}" ] && PW2_TAG="${1}" ;;
esac
check_platform
detect_arch
detect_pkg_manager
install_base_deps

setup_workdir

# --- Получение версии ---
if [ -z "${PW2_TAG}" ]; then
    get_latest_version
else
    log_info "Версия: ${PW2_TAG}"
    parse_tag
fi

# --- Запуск ---
log_info "=== PassWall2 v${PW2_VERSION} (тег: ${PW2_TAG}) ==="
log_info ""



if [ "${SKIP_DEPS:-0}" != "1" ]; then
    
    download_files
    install_zip_deps
else
    download_files
    log_warn "Зависимости пропущены!"
fi



install_passwall2
post_install
cleanup

exit 0
