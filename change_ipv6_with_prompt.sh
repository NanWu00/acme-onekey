#!/bin/bash

# ==========================================
# IPv6 修改工具 (Enhanced Version with Menu)
# 功能：自动检测网卡，安全修改IPv6，支持临时/永久修改，提供安装/卸载功能。
# ==========================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- 全局变量 ---
SCRIPT_PATH="/usr/local/bin/change_ipv6"
ALIAS_COMMAND="ipv6"
ALIAS_LINE='alias "ipv6"="/usr/local/bin/change_ipv6"'

# --- 辅助函数 ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 1. 权限检查 ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以 root 身份运行"
        exit 1
    fi
}

# --- 2. 自动安装逻辑 ---
install_script() {
    CURRENT_PATH=$(realpath "$0")
    if [[ "$CURRENT_PATH" != "$SCRIPT_PATH" ]]; then
        log_info "正在安装脚本到系统路径..."
        cp "$CURRENT_PATH" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        
        # 添加 alias
        if ! grep -q "$ALIAS_LINE" ~/.bashrc; then
            echo "$ALIAS_LINE" >> ~/.bashrc
            log_success "快捷命令 ${GREEN}'$ALIAS_COMMAND'${NC} 已添加。请执行 '${BLUE}source ~/.bashrc${NC}' 或重新登录以生效。"
        else
            log_info "快捷命令 ${GREEN}'$ALIAS_COMMAND'${NC} 已存在。"
        fi
        
        log_success "安装完成！您以后可以直接输入 '$ALIAS_COMMAND' 来运行此脚本。"
        echo ""
    fi
}

# --- 3. 卸载脚本逻辑 ---
uninstall_script() {
    log_warn "您确定要卸载脚本和别名吗? (y/n)"
    read -r CONFIRM_UNINSTALL
    if [[ "$CONFIRM_UNINSTALL" != "y" ]]; then
        log_info "操作已取消。"
        return
    fi
    
    # 移除脚本文件
    if [[ -f "$SCRIPT_PATH" ]]; then
        rm -f "$SCRIPT_PATH"
        log_success "脚本文件已移除: $SCRIPT_PATH"
    else
        log_warn "脚本文件不存在，跳过移除。"
    fi

    # 移除别名
    if grep -q "$ALIAS_LINE" ~/.bashrc; then
        sed -i "/$ALIAS_LINE/d" ~/.bashrc
        log_success "别名 '${ALIAS_COMMAND}' 已从 ~/.bashrc 移除。"
    else
        log_warn "别名未在 ~/.bashrc 中找到，跳过移除。"
    fi

    log_success "卸载完成。请执行 '${BLUE}source ~/.bashrc${NC}' 或重新登录以完成别名移除。"
    exit 0
}

# --- 4. 环境检测 ---
detect_environment() {
    log_info "正在检测网络环境..."

    # 自动检测主要网络接口
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -z "$INTERFACE" ]]; then
        INTERFACE=$(ip -6 route | grep default | awk '{print $5}' | head -n1)
    fi

    if [[ -z "$INTERFACE" ]]; then
        log_error "无法自动检测到网络接口，请手动检查网络配置。"
        exit 1
    fi

    log_info "检测到主要接口: ${GREEN}$INTERFACE${NC}"

    # 获取当前 IPv6
    CURRENT_IPV6=$(ip -6 addr show dev "$INTERFACE" | grep "inet6" | grep "global" | awk '{print $2}' | head -n1)
    if [[ -z "$CURRENT_IPV6" ]]; then
        log_warn "当前接口没有检测到 Global IPv6 地址。"
    else
        log_info "当前 IPv6 地址: ${YELLOW}$CURRENT_IPV6${NC}"
    fi

    # 获取当前 IPv6 网关
    GATEWAY=$(ip -6 route show default dev "$INTERFACE" | awk '{print $3}' | head -n1)
    if [[ -z "$GATEWAY" ]]; then
        log_warn "未检测到默认 IPv6 网关，可能无法连接外网。"
    else
        log_info "当前 IPv6 网关: ${YELLOW}$GATEWAY${NC}"
    fi

    echo ""
}

# --- 5. 用户交互获取新的 IPv6 ---
prompt_new_ipv6() {
    while true; do
        echo -e "${BLUE}请输入新的 IPv6 地址 (例如: 2001:db8::1/64)${NC}"
        read -p "IPv6 Address: " NEW_IPV6_INPUT
        
        # 简单格式清理
        NEW_IPV6_INPUT=$(echo "$NEW_IPV6_INPUT" | xargs)

        if [[ -z "$NEW_IPV6_INPUT" ]]; then
            log_error "输入不能为空，请重新输入。"
            continue
        fi

        # 简单的 IPv6 格式校验 (基础正则匹配)
        if [[ ! "$NEW_IPV6_INPUT" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}(/[0-9]{1,3})?$ ]]; then
             log_error "IPv6 地址格式看起来不正确，请检查。"
             read -p "是否确认使用此地址? (y/n): " CONFIRM
             if [[ "$CONFIRM" != "y" ]]; then
                 continue
             fi
        fi
        
        break
    done

    # 确保地址带上前缀长度，默认 /64
    if [[ "$NEW_IPV6_INPUT" == *"/"* ]]; then
        NEW_IPV6_FULL="$NEW_IPV6_INPUT"
    else
        NEW_IPV6_FULL="${NEW_IPV6_INPUT}/64" # 默认使用 /64，更常见
    fi
}

# --- 6. 执行临时修改 ---
apply_temporary_change() {
    prompt_new_ipv6
    
    echo ""
    log_info "准备将 IPv6 ${YELLOW}临时${NC}修改为: ${GREEN}$NEW_IPV6_FULL${NC} 在接口 $INTERFACE"
    read -p "按回车键确认执行，按 Ctrl+C 取消..."

    log_info "正在应用更改..."

    # 删除旧地址 (如果有)
    if [[ -n "$CURRENT_IPV6" ]]; then
        log_info "正在删除旧地址: $CURRENT_IPV6"
        ip -6 addr del "$CURRENT_IPV6" dev "$INTERFACE" 2>/dev/null || true
    fi

    # 添加新地址
    if ip -6 addr add "$NEW_IPV6_FULL" dev "$INTERFACE"; then
        log_success "IP 地址添加成功。"
    else
        log_error "IP 地址添加失败！"
        exit 1
    fi

    # 恢复网关 (如果有网关)
    if [[ -n "$GATEWAY" ]]; then
        # 检查路由是否存在
        if ! ip -6 route show default | grep -q "$GATEWAY"; then
            log_info "正在恢复默认网关..."
            ip -6 route add default via "$GATEWAY" dev "$INTERFACE" || log_warn "网关恢复失败，请手动检查。"
        fi
    fi

    log_success "临时修改完成。重启 VPS 后会失效。"
    verify_connectivity
}

# --- 7. 执行永久修改 (NetworkManager/netplan/interfaces 兼容) ---
apply_permanent_change() {
    prompt_new_ipv6
    
    echo ""
    log_info "准备将 IPv6 ${RED}永久${NC}修改为: ${GREEN}$NEW_IPV6_FULL${NC} 在接口 $INTERFACE"
    log_warn "此操作将尝试修改系统网络配置文件，请谨慎操作！"
    read -p "按回车键确认执行，按 Ctrl+C 取消..."
    
    # 尝试检测配置文件类型
    if command -v nmcli &> /dev/null; then
        # 倾向于使用 NetworkManager (CentOS/RHEL/Modern Ubuntu)
        log_info "检测到 NetworkManager (nmcli)，尝试使用其进行配置..."
        if nmcli connection modify "$INTERFACE" ipv6.addresses "$NEW_IPV6_FULL" ipv6.method manual; then
            nmcli connection up "$INTERFACE" || log_warn "NetworkManager 重启接口失败，请手动检查。"
            log_success "IPv6 地址已通过 NetworkManager 永久配置。"
        else
            log_error "NetworkManager 配置失败。尝试 Netplan..."
            configure_netplan "$NEW_IPV6_FULL"
        fi
    elif [[ -d "/etc/netplan" ]]; then
        # Netplan (Modern Ubuntu)
        configure_netplan "$NEW_IPV6_FULL"
    elif [[ -f "/etc/network/interfaces" ]]; then
        # Debian/Ubuntu 传统模式
        configure_interfaces "$NEW_IPV6_FULL"
    else
        log_error "无法确定合适的网络配置文件类型 (NetworkManager/Netplan/Interfaces)。"
        log_error "请手动修改您的网络配置文件以实现永久生效。"
        exit 1
    fi
    
    # 立即临时应用，即使永久配置成功，也立即在运行时生效
    log_info "立即在运行时应用新地址..."
    if [[ -n "$CURRENT_IPV6" ]]; then
        ip -6 addr del "$CURRENT_IPV6" dev "$INTERFACE" 2>/dev/null || true
    fi
    ip -6 addr add "$NEW_IPV6_FULL" dev "$INTERFACE" || log_error "运行时地址添加失败。"

    verify_connectivity
    log_success "永久配置完成。请注意，**网关设置可能需要手动或通过系统配置工具完成**。"
}

# --- 7.1 Netplan 配置函数 ---
configure_netplan() {
    local IPV6_ADDR="$1"
    local NETPLAN_FILE="/etc/netplan/01-custom-ipv6.yaml"
    log_info "正在创建 Netplan 配置文件: $NETPLAN_FILE"
    
    # Netplan YAML 配置内容
cat > "$NETPLAN_FILE" << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: true
      dhcp6: false # 关闭自动获取IPv6
      addresses:
        - $IPV6_ADDR
      # gateway6 字段已被废弃，现在使用 routes
      # routes:
      #   - to: default
      #     via: <Your_Gateway_Here>
EOF
    
    log_warn "请注意，Netplan 网关配置需要手动完成。目前配置为静态地址。"
    log_info "应用 Netplan 配置..."
    if netplan apply; then
        log_success "Netplan 配置应用成功！"
    else
        log_error "Netplan 应用配置失败。请检查 YAML 文件语法。"
        exit 1
    fi
}

# --- 7.2 Debian/Ubuntu Interfaces 配置函数 ---
configure_interfaces() {
    local IPV6_ADDR="$1"
    local INTERFACES_FILE="/etc/network/interfaces"
    log_info "正在修改传统 Interfaces 配置文件: $INTERFACES_FILE"

    if grep -q "iface $INTERFACE inet6 static" "$INTERFACES_FILE"; then
        log_warn "Interfaces 文件中已存在静态 IPv6 配置，请手动修改以避免冲突。"
    else
        # 备份并添加配置
        cp "$INTERFACES_FILE" "$INTERFACES_FILE.bak.$(date +%Y%m%d%H%M%S)"
        
cat >> "$INTERFACES_FILE" << EOF

# --- Added by change_ipv6 script ---
iface $INTERFACE inet6 static
address ${IPV6_ADDR%%/*}
netmask ${IPV6_ADDR##*/}
# gateway 字段需要手动添加
# gateway <Your_Gateway_Here>
# --- End of change_ipv6 script ---
EOF
        log_warn "已将配置添加到 $INTERFACES_FILE 末尾，请手动检查网关配置。"
        log_info "尝试重启网络服务..."
        systemctl restart networking || log_warn "重启网络服务失败，请手动检查配置并执行 'systemctl restart networking'"
        log_success "Interfaces 配置添加完成！"
    fi
}

# --- 8. 验证 ---
verify_connectivity() {
    echo ""
    log_info "正在验证网络连通性 (Ping google.com)..."
    if ping6 -c 3 -W 2 google.com &> /dev/null; then
        log_success "网络连通性测试通过！"
    else
        log_warn "无法 Ping 通 Google IPv6，请检查网关或地址是否正确。"
        log_info "尝试 Ping 网关..."
        if [[ -n "$GATEWAY" ]]; then
            ping6 -c 3 -W 2 "$GATEWAY"
        fi
    fi

    echo ""
    log_info "当前接口状态:"
    ip -6 addr show dev "$INTERFACE" | grep inet6
}

# --- 9. 主菜单 ---
main_menu() {
    check_root
    
    # 如果脚本是通过文件名直接执行的，则先执行安装逻辑
    if [[ "$0" == *change_ipv6* ]]; then
        install_script
    fi

    detect_environment

    while true; do
        echo -e "\n${BLUE}========== IPv6 配置工具菜单 ==========${NC}"
        echo -e "接口: ${GREEN}$INTERFACE${NC}"
        echo -e "当前地址: ${YELLOW}${CURRENT_IPV6:-未检测到}${NC}"
        echo "---"
        echo -e "1) ${GREEN}临时更改${NC} IPv6 地址 (重启后失效)"
        echo -e "2) ${RED}永久更改${NC} IPv6 地址 (写入配置文件)"
        echo -e "3) ${YELLOW}卸载脚本${NC} (移除文件和别名)"
        echo -e "4) ${BLUE}退出${NC}"
        echo "---"
        read -p "请选择操作 (1-4): " CHOICE
        
        case "$CHOICE" in
            1)
                apply_temporary_change
                ;;
            2)
                apply_permanent_change
                ;;
            3)
                uninstall_script
                ;;
            4)
                log_info "退出脚本。"
                exit 0
                ;;
            *)
                log_error "无效的选择，请重新输入。"
                ;;
        esac
    done
}

# --- 脚本执行入口 ---
main_menu