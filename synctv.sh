#!/usr/bin/env bash
# ============================================================================
# SyncTV One-Click Installation Script
# 支持: 普通VPS, NAT VPS, Alpine Linux, FreeBSD/Serv00/HostUno
# ============================================================================

set -e

# ========================= 颜色定义 =========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ========================= 全局变量 =========================
SCRIPT_VERSION="1.0.0"
SYNCTV_REPO="synctv-org/synctv"
GH_PROXY="${GH_PROXY:-}"
DEFAULT_PORT=8080

# 路径变量 (将在检测后设置)
INSTALL_DIR=""
BIN_PATH=""
DATA_DIR=""
SERVICE_TYPE=""  # systemd, openrc, daemon

# ========================= 工具函数 =========================
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
 ____                    _______     __
/ ___| _   _ _ __   ___ |_   _\ \   / /
\___ \| | | | '_ \ / __|  | |  \ \ / / 
 ___) | |_| | | | | (__   | |   \ V /  
|____/ \__, |_| |_|\___|  |_|    \_/   
       |___/                           
    Easy Installation Script
EOF
    echo -e "${NC}"
    echo -e "${WHITE}Version: ${SCRIPT_VERSION}${NC}"
    echo ""
}

confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local yn
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -r -p "$prompt" yn
    yn=${yn:-$default}
    
    case "$yn" in
        [Yy]* ) return 0;;
        * ) return 1;;
    esac
}

# ========================= 环境检测 =========================
detect_os() {
    OS=""
    case "$(uname -s)" in
        Linux*)
            OS="linux"
            # 检测是否为Alpine (musl libc)
            if [ -f /etc/alpine-release ]; then
                OS_TYPE="alpine"
            elif [ -f /etc/os-release ]; then
                . /etc/os-release
                OS_TYPE="$ID"
            else
                OS_TYPE="linux"
            fi
            ;;
        FreeBSD*)
            OS="freebsd"
            OS_TYPE="freebsd"
            ;;
        Darwin*)
            OS="darwin"
            OS_TYPE="macos"
            ;;
        *)
            log_error "不支持的操作系统: $(uname -s)"
            exit 1
            ;;
    esac
    
    log_info "检测到操作系统: ${OS} (${OS_TYPE})"
}

detect_arch() {
    ARCH=""
    MICRO=""
    
    case "$(uname -m)" in
        x86_64|amd64)
            ARCH="amd64"
            # 检测微架构级别
            if [ -f /proc/cpuinfo ]; then
                MICRO=$(detect_amd64_micro)
            fi
            ;;
        i?86|x86)
            ARCH="386"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7*|armv6*|arm*)
            ARCH="arm"
            ;;
        *)
            log_error "不支持的架构: $(uname -m)"
            exit 1
            ;;
    esac
    
    log_info "检测到CPU架构: ${ARCH}${MICRO:+ (${MICRO})}"
}

detect_amd64_micro() {
    # 检测 AMD64 微架构级别 (v1-v4)
    local level=""
    if command -v awk &> /dev/null && [ -f /proc/cpuinfo ]; then
        level=$(awk '
        BEGIN {
            while (!/flags/) if (getline < "/proc/cpuinfo" != 1) exit 1
            if (/lm/&&/cmov/&&/cx8/&&/fpu/&&/fxsr/&&/mmx/&&/syscall/&&/sse2/) level = 1
            if (level == 1 && /cx16/&&/lahf/&&/popcnt/&&/sse4_1/&&/sse4_2/&&/ssse3/) level = 2
            if (level == 2 && /avx/&&/avx2/&&/bmi1/&&/bmi2/&&/f16c/&&/fma/&&/abm/&&/movbe/&&/xsave/) level = 3
            if (level == 3 && /avx512f/&&/avx512bw/&&/avx512cd/&&/avx512dq/&&/avx512vl/) level = 4
            if (level > 0) { print "v" level; exit 0 }
            exit 1
        }' 2>/dev/null)
    fi
    echo "$level"
}

detect_init_system() {
    SERVICE_TYPE=""
    
    if [ "$OS" = "freebsd" ]; then
        SERVICE_TYPE="daemon"
    elif [ "$OS_TYPE" = "alpine" ]; then
        if command -v rc-service &> /dev/null; then
            SERVICE_TYPE="openrc"
        else
            SERVICE_TYPE="daemon"
        fi
    elif command -v systemctl &> /dev/null && systemctl --version &> /dev/null 2>&1; then
        SERVICE_TYPE="systemd"
    elif command -v rc-service &> /dev/null; then
        SERVICE_TYPE="openrc"
    else
        SERVICE_TYPE="daemon"
    fi
    
    log_info "检测到服务管理: ${SERVICE_TYPE}"
}

detect_privileges() {
    IS_ROOT=false
    if [ "$(id -u)" -eq 0 ]; then
        IS_ROOT=true
    fi
    
    log_info "运行权限: $([ "$IS_ROOT" = true ] && echo '管理员 (root)' || echo '普通用户')"
}

setup_paths() {
    if [ "$IS_ROOT" = true ] && [ "$OS" != "freebsd" ]; then
        # 系统级安装
        INSTALL_DIR="/usr/bin"
        BIN_PATH="/usr/bin/synctv"
        DATA_DIR="/opt/synctv"
        CONFIG_DIR="/opt/synctv"
    else
        # 用户级安装 (非root或FreeBSD/Serv00)
        INSTALL_DIR="$HOME/synctv/bin"
        BIN_PATH="$HOME/synctv/bin/synctv"
        DATA_DIR="$HOME/synctv/data"
        CONFIG_DIR="$HOME/synctv"
        SERVICE_TYPE="daemon"  # 强制使用daemon模式
    fi
    
    log_info "安装目录: ${INSTALL_DIR}"
    log_info "数据目录: ${DATA_DIR}"
}

detect_download_tool() {
    DOWNLOAD_TOOL=""
    if command -v curl &> /dev/null; then
        DOWNLOAD_TOOL="curl"
    elif command -v wget &> /dev/null; then
        DOWNLOAD_TOOL="wget"
    else
        log_error "未找到 curl 或 wget，请先安装下载工具"
        exit 1
    fi
    log_info "下载工具: ${DOWNLOAD_TOOL}"
}

# ========================= 下载函数 =========================
download_file() {
    local url="$1"
    local output="$2"
    
    log_info "下载: ${url}"
    
    case "$DOWNLOAD_TOOL" in
        curl)
            if ! curl -fsSL --connect-timeout 30 -o "$output" "$url"; then
                return 1
            fi
            ;;
        wget)
            if ! wget -q --timeout=30 -O "$output" "$url"; then
                return 1
            fi
            ;;
    esac
    return 0
}

get_latest_version() {
    local api_url="https://api.github.com/repos/${SYNCTV_REPO}/releases/latest"
    local version=""
    
    log_info "获取最新版本..."
    
    case "$DOWNLOAD_TOOL" in
        curl)
            version=$(curl -fsSL --connect-timeout 10 "$api_url" 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
            ;;
        wget)
            version=$(wget -qO- --timeout=10 "$api_url" 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
            ;;
    esac
    
    if [ -z "$version" ]; then
        log_warn "无法获取最新版本，使用默认: latest"
        echo "latest"
    else
        echo "$version"
    fi
}

build_download_url() {
    local version="$1"
    local binary_name="synctv-${OS}-${ARCH}"
    
    # 添加微架构后缀
    if [ -n "$MICRO" ] && [ "$ARCH" = "amd64" ]; then
        binary_name="${binary_name}-${MICRO}"
    fi
    
    local base_url="https://github.com/${SYNCTV_REPO}/releases"
    
    if [[ "$version" == v* ]]; then
        echo "${GH_PROXY}${base_url}/download/${version}/${binary_name}"
    else
        echo "${GH_PROXY}${base_url}/${version}/download/${binary_name}"
    fi
}

# ========================= 安装函数 =========================
install_synctv() {
    local version="${1:-latest}"
    
    # 获取实际版本号
    if [ "$version" = "latest" ]; then
        version=$(get_latest_version)
    fi
    
    log_info "安装 SyncTV ${version}..."
    
    # 创建临时目录
    local tmp_dir
    tmp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t 'synctv-install')
    trap 'rm -rf "$tmp_dir"' EXIT
    
    # 构建下载URL
    local download_url
    download_url=$(build_download_url "$version")
    
    # 下载二进制文件
    log_info "下载 SyncTV 二进制文件..."
    if ! download_file "$download_url" "$tmp_dir/synctv"; then
        log_error "下载失败: $download_url"
        
        # 尝试不带微架构后缀
        if [ -n "$MICRO" ]; then
            log_warn "尝试下载通用版本..."
            MICRO=""
            download_url=$(build_download_url "$version")
            if ! download_file "$download_url" "$tmp_dir/synctv"; then
                log_error "下载失败"
                exit 1
            fi
        else
            exit 1
        fi
    fi
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$DATA_DIR"
    
    # 安装二进制文件
    log_info "安装二进制文件到 ${BIN_PATH}..."
    cp "$tmp_dir/synctv" "${BIN_PATH}.new"
    chmod 755 "${BIN_PATH}.new"
    
    if [ "$IS_ROOT" = true ]; then
        chown root:root "${BIN_PATH}.new" 2>/dev/null || true
    fi
    
    mv "${BIN_PATH}.new" "$BIN_PATH"
    
    log_success "SyncTV ${version} 安装成功!"
    
    # 设置服务
    setup_service
}

# ========================= 服务管理 =========================
setup_service() {
    case "$SERVICE_TYPE" in
        systemd)
            setup_systemd_service
            ;;
        openrc)
            setup_openrc_service
            ;;
        daemon)
            setup_daemon_info
            ;;
    esac
}

setup_systemd_service() {
    if [ ! -d "/etc/systemd/system" ]; then
        log_warn "systemd 目录不存在，跳过服务安装"
        return
    fi
    
    if [ -f "/etc/systemd/system/synctv.service" ]; then
        log_info "systemd 服务已存在"
        systemctl daemon-reload
        return
    fi
    
    log_info "创建 systemd 服务..."
    
    cat > /etc/systemd/system/synctv.service << EOF
[Unit]
Description=SyncTV Service
After=network.target

[Service]
Type=simple
ExecStart=${BIN_PATH} server --data-dir ${DATA_DIR}
WorkingDirectory=${DATA_DIR}
Restart=on-failure
RestartSec=5
User=$([ "$IS_ROOT" = true ] && echo "root" || echo "$USER")

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    log_success "systemd 服务创建成功"
    log_info "启动命令: systemctl start synctv"
    log_info "开机自启: systemctl enable synctv"
}

setup_openrc_service() {
    if [ ! -d "/etc/init.d" ]; then
        log_warn "OpenRC 目录不存在，跳过服务安装"
        return
    fi
    
    if [ -f "/etc/init.d/synctv" ]; then
        log_info "OpenRC 服务已存在"
        return
    fi
    
    log_info "创建 OpenRC 服务..."
    
    cat > /etc/init.d/synctv << EOF
#!/sbin/openrc-run

name="synctv"
description="SyncTV Service"
command="${BIN_PATH}"
command_args="server --data-dir ${DATA_DIR}"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
directory="${DATA_DIR}"

depend() {
    need net
    after firewall
}
EOF
    
    chmod +x /etc/init.d/synctv
    log_success "OpenRC 服务创建成功"
    log_info "启动命令: rc-service synctv start"
    log_info "开机自启: rc-update add synctv default"
}

setup_daemon_info() {
    log_info "使用后台进程模式 (适用于FreeBSD/非root用户)"
    
    # 创建启动脚本
    cat > "${CONFIG_DIR}/start.sh" << EOF
#!/bin/bash
cd "${DATA_DIR}"
nohup "${BIN_PATH}" server --data-dir "${DATA_DIR}" > "${DATA_DIR}/synctv.log" 2>&1 &
echo \$! > "${DATA_DIR}/synctv.pid"
echo "SyncTV 已启动, PID: \$(cat ${DATA_DIR}/synctv.pid)"
EOF
    chmod +x "${CONFIG_DIR}/start.sh"
    
    # 创建停止脚本
    cat > "${CONFIG_DIR}/stop.sh" << EOF
#!/bin/bash
if [ -f "${DATA_DIR}/synctv.pid" ]; then
    pid=\$(cat "${DATA_DIR}/synctv.pid")
    if kill -0 "\$pid" 2>/dev/null; then
        kill "\$pid"
        rm -f "${DATA_DIR}/synctv.pid"
        echo "SyncTV 已停止"
    else
        echo "进程不存在"
        rm -f "${DATA_DIR}/synctv.pid"
    fi
else
    echo "PID 文件不存在"
    # 尝试通过进程名查找
    pkill -f "${BIN_PATH}" 2>/dev/null && echo "SyncTV 已停止" || echo "未找到运行中的进程"
fi
EOF
    chmod +x "${CONFIG_DIR}/stop.sh"
    
    log_success "启动脚本已创建"
    log_info "启动: ${CONFIG_DIR}/start.sh"
    log_info "停止: ${CONFIG_DIR}/stop.sh"
}

# ========================= 服务控制 =========================
start_service() {
    log_info "启动 SyncTV..."
    
    case "$SERVICE_TYPE" in
        systemd)
            systemctl start synctv
            sleep 2
            if systemctl is-active --quiet synctv; then
                log_success "SyncTV 已启动"
            else
                log_error "启动失败,请检查日志: journalctl -u synctv"
            fi
            ;;
        openrc)
            rc-service synctv start
            ;;
        daemon)
            if [ -f "${CONFIG_DIR}/start.sh" ]; then
                bash "${CONFIG_DIR}/start.sh"
            else
                cd "$DATA_DIR"
                nohup "$BIN_PATH" server --data-dir "$DATA_DIR" > "$DATA_DIR/synctv.log" 2>&1 &
                echo $! > "$DATA_DIR/synctv.pid"
                log_success "SyncTV 已启动, PID: $(cat $DATA_DIR/synctv.pid)"
            fi
            ;;
    esac
}

stop_service() {
    log_info "停止 SyncTV..."
    
    case "$SERVICE_TYPE" in
        systemd)
            systemctl stop synctv
            log_success "SyncTV 已停止"
            ;;
        openrc)
            rc-service synctv stop
            ;;
        daemon)
            if [ -f "${CONFIG_DIR}/stop.sh" ]; then
                bash "${CONFIG_DIR}/stop.sh"
            elif [ -f "${DATA_DIR}/synctv.pid" ]; then
                local pid
                pid=$(cat "${DATA_DIR}/synctv.pid")
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid"
                    rm -f "${DATA_DIR}/synctv.pid"
                    log_success "SyncTV 已停止"
                else
                    log_warn "进程不存在"
                fi
            else
                pkill -f "$BIN_PATH" 2>/dev/null && log_success "SyncTV 已停止" || log_warn "未找到运行中的进程"
            fi
            ;;
    esac
}

restart_service() {
    log_info "重启 SyncTV..."
    stop_service
    sleep 2
    start_service
}

service_status() {
    log_info "检查 SyncTV 状态..."
    
    case "$SERVICE_TYPE" in
        systemd)
            systemctl status synctv --no-pager 2>/dev/null || log_warn "服务未安装或未运行"
            ;;
        openrc)
            rc-service synctv status 2>/dev/null || log_warn "服务未安装或未运行"
            ;;
        daemon)
            if [ -f "${DATA_DIR}/synctv.pid" ]; then
                local pid
                pid=$(cat "${DATA_DIR}/synctv.pid")
                if kill -0 "$pid" 2>/dev/null; then
                    log_success "SyncTV 运行中, PID: $pid"
                else
                    log_warn "PID 文件存在但进程未运行"
                fi
            else
                if pgrep -f "$BIN_PATH" > /dev/null; then
                    log_success "SyncTV 运行中"
                else
                    log_warn "SyncTV 未运行"
                fi
            fi
            ;;
    esac
}

view_logs() {
    log_info "查看 SyncTV 日志..."
    
    case "$SERVICE_TYPE" in
        systemd)
            journalctl -u synctv -f --no-pager -n 50
            ;;
        openrc)
            if [ -f "/var/log/synctv.log" ]; then
                tail -f /var/log/synctv.log
            else
                log_warn "日志文件不存在"
            fi
            ;;
        daemon)
            if [ -f "${DATA_DIR}/synctv.log" ]; then
                tail -f "${DATA_DIR}/synctv.log"
            else
                log_warn "日志文件不存在"
            fi
            ;;
    esac
}

enable_autostart() {
    log_info "设置开机自启..."
    
    case "$SERVICE_TYPE" in
        systemd)
            systemctl enable synctv
            log_success "已启用开机自启"
            ;;
        openrc)
            rc-update add synctv default
            log_success "已启用开机自启"
            ;;
        daemon)
            log_warn "后台模式不支持自动设置开机自启"
            log_info "请手动将以下命令添加到启动脚本 (如 ~/.bashrc 或 crontab):"
            echo "  @reboot ${CONFIG_DIR}/start.sh"
            ;;
    esac
}

# ========================= 版本管理 =========================
get_current_version() {
    if [ -x "$BIN_PATH" ]; then
        "$BIN_PATH" version 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown"
    else
        echo "未安装"
    fi
}

upgrade_synctv() {
    local current_version
    current_version=$(get_current_version)
    
    if [ "$current_version" = "未安装" ]; then
        log_error "SyncTV 未安装，请先安装"
        return 1
    fi
    
    local latest_version
    latest_version=$(get_latest_version)
    
    log_info "当前版本: ${current_version}"
    log_info "最新版本: ${latest_version}"
    
    if [ "$current_version" = "$latest_version" ]; then
        log_success "已是最新版本"
        return 0
    fi
    
    if confirm "是否升级到 ${latest_version}?"; then
        # 停止服务
        stop_service 2>/dev/null || true
        
        # 安装新版本
        install_synctv "$latest_version"
        
        # 启动服务
        start_service
    fi
}

# ========================= 卸载 =========================
uninstall_synctv() {
    log_warn "即将卸载 SyncTV"
    
    if ! confirm "确认卸载? 这将删除二进制文件和服务配置"; then
        log_info "取消卸载"
        return
    fi
    
    # 停止服务
    stop_service 2>/dev/null || true
    
    # 删除服务
    case "$SERVICE_TYPE" in
        systemd)
            systemctl disable synctv 2>/dev/null || true
            rm -f /etc/systemd/system/synctv.service
            systemctl daemon-reload
            ;;
        openrc)
            rc-update del synctv default 2>/dev/null || true
            rm -f /etc/init.d/synctv
            ;;
    esac
    
    # 删除二进制文件
    rm -f "$BIN_PATH"
    
    # 询问是否删除数据
    if confirm "是否删除数据目录 (${DATA_DIR})?" "n"; then
        rm -rf "$DATA_DIR"
        log_info "数据目录已删除"
    fi
    
    # 删除启动脚本
    rm -f "${CONFIG_DIR}/start.sh" "${CONFIG_DIR}/stop.sh" 2>/dev/null || true
    
    log_success "SyncTV 已卸载"
}

# ========================= 端口配置 =========================
configure_port() {
    local current_port="$DEFAULT_PORT"
    
    echo ""
    echo -e "${CYAN}端口配置${NC}"
    echo "当前默认端口: ${current_port}"
    echo ""
    read -r -p "请输入新端口 [直接回车使用默认]: " new_port
    
    if [ -z "$new_port" ]; then
        new_port="$current_port"
    fi
    
    # 验证端口
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        log_error "无效端口号"
        return 1
    fi
    
    log_info "将使用端口: ${new_port}"
    
    # 更新服务配置
    if [ "$SERVICE_TYPE" = "systemd" ] && [ -f "/etc/systemd/system/synctv.service" ]; then
        sed -i "s|ExecStart=.*|ExecStart=${BIN_PATH} server --data-dir ${DATA_DIR} --server-http-port ${new_port}|" /etc/systemd/system/synctv.service
        systemctl daemon-reload
        log_success "systemd 服务配置已更新"
    fi
    
    # 更新daemon模式启动脚本
    if [ -f "${CONFIG_DIR}/start.sh" ]; then
        sed -i "s|server --data-dir.*|server --data-dir \"${DATA_DIR}\" --server-http-port ${new_port} > \"${DATA_DIR}/synctv.log\" 2>\&1 \&|" "${CONFIG_DIR}/start.sh"
        log_success "启动脚本已更新"
    fi
    
    log_info "重启服务以应用更改: 重启后访问 http://服务器IP:${new_port}"
}

# ========================= 主菜单 =========================
show_menu() {
    local current_version
    current_version=$(get_current_version)
    
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}       SyncTV 管理面板${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -e "  当前版本: ${GREEN}${current_version}${NC}"
    echo -e "  安装目录: ${BIN_PATH}"
    echo -e "  数据目录: ${DATA_DIR}"
    echo -e "  服务模式: ${SERVICE_TYPE}"
    echo ""
    echo -e "${YELLOW}  1.${NC} 安装/重装 SyncTV"
    echo -e "${YELLOW}  2.${NC} 升级 SyncTV"
    echo -e "${YELLOW}  3.${NC} 启动服务"
    echo -e "${YELLOW}  4.${NC} 停止服务"
    echo -e "${YELLOW}  5.${NC} 重启服务"
    echo -e "${YELLOW}  6.${NC} 查看状态"
    echo -e "${YELLOW}  7.${NC} 查看日志"
    echo -e "${YELLOW}  8.${NC} 设置开机自启"
    echo -e "${YELLOW}  9.${NC} 配置端口 (NAT VPS)"
    echo -e "${YELLOW} 10.${NC} 卸载 SyncTV"
    echo -e "${YELLOW}  0.${NC} 退出"
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

# ========================= 主程序 =========================
main() {
    print_banner
    
    # 环境检测
    detect_os
    detect_arch
    detect_privileges
    detect_init_system
    setup_paths
    detect_download_tool
    
    echo ""
    
    # 命令行模式
    if [ $# -gt 0 ]; then
        case "$1" in
            install)
                install_synctv "${2:-latest}"
                ;;
            upgrade)
                upgrade_synctv
                ;;
            start)
                start_service
                ;;
            stop)
                stop_service
                ;;
            restart)
                restart_service
                ;;
            status)
                service_status
                ;;
            logs)
                view_logs
                ;;
            uninstall)
                uninstall_synctv
                ;;
            version)
                echo "SyncTV: $(get_current_version)"
                echo "Script: ${SCRIPT_VERSION}"
                ;;
            *)
                echo "用法: $0 {install|upgrade|start|stop|restart|status|logs|uninstall|version}"
                exit 1
                ;;
        esac
        exit 0
    fi
    
    # 交互式菜单
    while true; do
        show_menu
        read -r -p "请选择操作 [0-10]: " choice
        
        case "$choice" in
            1)
                install_synctv
                ;;
            2)
                upgrade_synctv
                ;;
            3)
                start_service
                ;;
            4)
                stop_service
                ;;
            5)
                restart_service
                ;;
            6)
                service_status
                ;;
            7)
                view_logs
                ;;
            8)
                enable_autostart
                ;;
            9)
                configure_port
                ;;
            10)
                uninstall_synctv
                ;;
            0)
                log_info "再见!"
                exit 0
                ;;
            *)
                log_error "无效选择"
                ;;
        esac
        
        echo ""
        read -r -p "按 Enter 继续..."
    done
}

main "$@"
