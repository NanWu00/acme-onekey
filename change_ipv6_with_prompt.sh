#!/bin/bash

# ==========================================
# IPv6 管理工具 (v3.0 Auto-Update)
# 功能：自动/静态/临时 IPv6 配置，智能安装与卸载
# ==========================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- 全局配置 ---
SCRIPT_PATH="/usr/local/bin/change_ipv6"
# 请确保此 URL 是您仓库中该脚本的 RAW 地址
DOWNLOAD_URL="https://raw.githubusercontent.com/NanWu00/acme-onekey/refs/heads/main/change_ipv6_with_prompt.sh"

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

# --- 2. 智能安装逻辑 (支持 curl 管道运行) ---
install_script() {
    # 检查脚本文件是否存在，或是否大小为0（防止空文件）
    if [[ ! -s "$SCRIPT_PATH" ]]; then
        echo ""
        log_info "检测到脚本未安装，正在下载并安装..."
        
        # 创建目录（如果不存在）
        mkdir -p $(dirname "$SCRIPT_PATH")

        # 下载文件
        if command -v curl &> /dev/null; then
            curl -sSL "$DOWNLOAD_URL" -o "$SCRIPT_PATH"
        elif command -v wget &> /dev/null; then
            wget -qO "$SCRIPT_PATH" "$DOWNLOAD_URL"
        else
            log_error "未找到 curl 或 wget，无法自动安装。"
            return
        fi

        if [[ -s "$SCRIPT_PATH" ]]; then
            chmod +x "$SCRIPT_PATH"
            log_success "脚本已安装到: $SCRIPT_PATH"
            
            # 配置别名
            sed -i '/alias "ipv6"=/d' ~/.bashrc
            sed -i '/alias "change ipv6"=/d' ~/.bashrc
            echo 'alias "ipv6"="/usr/local/bin/change_ipv6"' >> ~/.bashrc
            
            log_success "别名 'ipv6' 已设置。"
            log_warn "提示：初次安装，请执行 'source ~/.bashrc' 或重新登录以激活快捷命令。"
            echo ""
        else
            log_error "下载失败，请检查网络或 URL。"
            exit 1
        fi
    fi
}

# --- 3. 卸载脚本 ---
uninstall_script() {
    echo -e "\n${RED}========== 卸载向导 ==========${NC}"
    read -p "确认卸载脚本及别名? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then return; fi
    
    rm -f "$SCRIPT_PATH"
    sed -i '/alias "ipv6"=/d' ~/.bashrc
    sed -i '/alias "change ipv6"=/d' ~/.bashrc
    
    log_success "卸载完成！"
    log_info "脚本文件已删除，别名已清理。"
    log_info "无需额外操作，'ipv6' 命令已失效。"
    exit 0
}

# --- 4. 环境检测 ---
detect_environment() {
    # 检测接口
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -z "$INTERFACE" ]]; then
        INTERFACE=$(ip -6 route | grep default | awk '{print $5}' | head -n1)
    fi

    if [[ -z "$INTERFACE" ]]; then
        log_error "无法检测到网络接口。"
        exit 1
    fi

    # 检测当前 IPv6 和网关
    CURRENT_IPV6=$(ip -6 addr show dev "$INTERFACE" | grep "inet6" | grep "global" | awk '{print $2}' | head -n1)
    GATEWAY=$(ip -6 route show default dev "$INTERFACE" | awk '{print $3}' | head -n1)
}

# --- 5. 输入处理 ---
prompt_new_ipv6() {
    echo ""
    log_info "当前接口: ${GREEN}$INTERFACE${NC}"
    while true; do
        echo -e "${BLUE}请输入新的 IPv6 地址 (例如: 2001:db8::1/64)${NC}"
        read -p "IPv6 Address: " NEW_IPV6_INPUT
        NEW_IPV6_INPUT=$(echo "$NEW_IPV6_INPUT" | xargs)
        [[ -z "$NEW_IPV6_INPUT" ]] && continue
        
        # 简单校验
        if [[ ! "$NEW_IPV6_INPUT" =~ : ]]; then
             log_error "格式错误。"
             continue
        fi
        break
    done

    if [[ "$NEW_IPV6_INPUT" == *"/"* ]]; then
        NEW_IPV6_FULL="$NEW_IPV6_INPUT"
    else
        NEW_IPV6_FULL="${NEW_IPV6_INPUT}/64"
    fi
}

# --- 6. 临时修改 ---
apply_temporary_change() {
    prompt_new_ipv6
    log_info "正在应用临时修改..."
    
    [[ -n "$CURRENT_IPV6" ]] && ip -6 addr del "$CURRENT_IPV6" dev "$INTERFACE" 2>/dev/null
    
    if ip -6 addr add "$NEW_IPV6_FULL" dev "$INTERFACE"; then
        log_success "临时 IP 已添加。"
        # 尝试恢复网关
        [[ -n "$GATEWAY" ]] && ip -6 route add default via "$GATEWAY" dev "$INTERFACE" 2>/dev/null
        verify_connectivity
    else
        log_error "添加失败。"
    fi
}

# --- 7. 永久静态修改 ---
apply_permanent_change() {
    prompt_new_ipv6
    echo ""
    log_warn "正在修改配置文件设置为 [静态 IPv6]..."
    
    # NetworkManager
    if command -v nmcli &> /dev/null && nmcli device status | grep -q "$INTERFACE"; then
        nmcli connection modify "$INTERFACE" ipv6.addresses "$NEW_IPV6_FULL" ipv6.method manual
        nmcli connection up "$INTERFACE"
        log_success "NetworkManager 配置已更新。"

    # Netplan
    elif [[ -d "/etc/netplan" ]]; then
        local FILE="/etc/netplan/01-ipv6-static.yaml"
cat > "$FILE" << EOF
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp6: false
      accept-ra: false
      addresses:
        - $NEW_IPV6_FULL
EOF
        netplan apply
        log_success "Netplan 配置已更新 ($FILE)。"

    # Interfaces
    elif [[ -f "/etc/network/interfaces" ]]; then
        # 先清理旧配置
        sed -i '/# Added by ipv6 script/,/# End of ipv6 script/d' "/etc/network/interfaces"
        
        cp "/etc/network/interfaces" "/etc/network/interfaces.bak"
cat >> "/etc/network/interfaces" << EOF

# Added by ipv6 script
iface $INTERFACE inet6 static
address ${NEW_IPV6_FULL%%/*}
netmask ${NEW_IPV6_FULL##*/}
# gateway YOUR_GATEWAY_HERE
# End of ipv6 script
EOF
        # 尝试重载 (不一定成功，建议重启)
        ip -6 addr flush dev "$INTERFACE"
        if [[ -f /etc/init.d/networking ]]; then /etc/init.d/networking restart; fi
        ip -6 addr add "$NEW_IPV6_FULL" dev "$INTERFACE"
        log_success "Interfaces 配置已添加 (建议重启服务器验证)。"
    else
        log_error "未识别的配置系统。"
        return
    fi
    verify_connectivity
}

# --- 8. 自动获取 IPv6 (NEW) ---
apply_auto_ipv6() {
    echo ""
    log_info "正在将 IPv6 恢复为 [自动获取 (DHCP/SLAAC)]..."
    read -p "确认执行? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then return; fi

    # NetworkManager
    if command -v nmcli &> /dev/null && nmcli device status | grep -q "$INTERFACE"; then
        # 清除静态地址并设为 auto
        nmcli connection modify "$INTERFACE" ipv6.method auto ipv6.addresses "" ipv6.gateway ""
        nmcli connection up "$INTERFACE"
        log_success "NetworkManager 已设置为自动获取。"

    # Netplan
    elif [[ -d "/etc/netplan" ]]; then
        # 覆盖之前的静态配置文件
        local FILE="/etc/netplan/01-ipv6-static.yaml"
cat > "$FILE" << EOF
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp6: true
      accept-ra: true
EOF
        netplan apply
        log_success "Netplan 已设置为自动获取。"

    # Interfaces
    elif [[ -f "/etc/network/interfaces" ]]; then
        # 删除脚本添加的静态块
        sed -i '/# Added by ipv6 script/,/# End of ipv6 script/d' "/etc/network/interfaces"
        
        # 追加自动配置 (可选，通常删除静态配置后系统默认会尝试 auto，这里显式添加以防万一)
        # 注意：如果主配置里已经有 iface inet6 auto，这里可能会冲突，所以更安全的做法是只删除静态块
        # 或者是追加一个 auto 块
cat >> "/etc/network/interfaces" << EOF

# Added by ipv6 script
iface $INTERFACE inet6 auto
# End of ipv6 script
EOF
        log_success "Interfaces 已恢复为自动配置 (需重启生效)。"
        log_warn "正在尝试刷新网络..."
        systemctl restart networking 2>/dev/null || /etc/init.d/networking restart 2>/dev/null
    else
        log_error "无法自动配置，请手动修改配置文件。"
        return
    fi
    
    verify_connectivity
}

# --- 9. 验证 ---
verify_connectivity() {
    echo ""
    log_info "检查网络连通性..."
    sleep 2 # 等待接口重置
    if ping6 -c 2 -W 2 google.com &> /dev/null; then
        log_success "IPv6 网络通畅！"
    else
        log_warn "Ping 失败。如果是自动获取，可能需要等待几秒或重启。"
    fi
}

# --- 10. 主菜单 ---
main_menu() {
    check_root
    
    # 无论如何运行，先确保安装和下载
    install_script

    detect_environment

    while true; do
        echo -e "\n${BLUE}========== IPv6 配置工具 ==========${NC}"
        echo -e "接口: ${GREEN}$INTERFACE${NC} | 当前IP: ${YELLOW}${CURRENT_IPV6:-未检测到}${NC}"
        echo "---"
        echo -e "1. ${GREEN}设置静态 IP (永久)${NC}"
        echo -e "2. ${YELLOW}设置静态 IP (临时)${NC}"
        echo -e "3. ${BLUE}设置自动获取 (DHCP/SLAAC)${NC}"
        echo -e "4. ${RED}卸载脚本${NC}"
        echo -e "0. 退出"
        echo "---"
        read -p "请选择 [0-4]: " CHOICE
        
        case "$CHOICE" in
            1) apply_permanent_change ;;
            2) apply_temporary_change ;;
            3) apply_auto_ipv6 ;;
            4) uninstall_script ;;
            0) exit 0 ;;
            *) log_error "无效输入" ;;
        esac
        echo ""
        read -p "按回车继续..."
    done
}

main_menu
