#!/bin/bash

# ==========================================
# IPv6 修改工具 (Optimized Version)
# 功能：自动检测网卡，支持永久/临时修改，智能卸载
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
# 定义准确的别名行，用于 grep 和 sed 匹配
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
    # 目标安装路径
    local INSTALL_PATH="/usr/local/bin/change_ipv6"
    # 您的脚本在 GitHub 上的真实 RAW 地址
    local DOWNLOAD_URL="https://raw.githubusercontent.com/NanWu00/acme-onekey/refs/heads/main/change_ipv6_with_prompt.sh"

    # 检查脚本是否已经存在于安装路径
    if [[ ! -f "$INSTALL_PATH" ]]; then
        log_info "检测到脚本未安装，正在下载并安装到系统路径..."
        
        # 尝试下载 (支持 curl 和 wget)
        if command -v curl &> /dev/null; then
            curl -sSL "$DOWNLOAD_URL" -o "$INSTALL_PATH"
        elif command -v wget &> /dev/null; then
            wget -qO "$INSTALL_PATH" "$DOWNLOAD_URL"
        else
            log_error "未找到 curl 或 wget，无法自动安装脚本。"
            return
        fi

        # 赋予执行权限
        chmod +x "$INSTALL_PATH"
        log_success "脚本文件已安装到: $INSTALL_PATH"

        # 配置别名
        # 先清理旧的，防止重复
        sed -i '/alias "ipv6"=/d' ~/.bashrc
        sed -i '/alias "change ipv6"=/d' ~/.bashrc
        
        # 写入新别名
        echo 'alias "ipv6"="/usr/local/bin/change_ipv6"' >> ~/.bashrc
        
        log_success "别名 'ipv6' 已添加！"
        log_warn "请执行 'source ~/.bashrc' 使别名在当前窗口生效，或重新登录 SSH。"
        echo ""
    else
        # 如果文件已存在，但用户是通过 curl 运行的，可能是在更新
        # 这里可以加一个简单的版本检查或跳过，目前保持简单，不做多余操作
        : 
    fi
}

# --- 3. 卸载脚本逻辑 (增强版) ---
uninstall_script() {
    echo -e "\n${RED}========== 卸载向导 ==========${NC}"
    log_warn "此操作将执行以下清理："
    echo "1. 删除脚本文件: $SCRIPT_PATH"
    echo "2. 移除 ~/.bashrc 中的 'ipv6' 别名"
    echo "3. 移除系统中的旧别名残留"
    
    read -p "确认卸载? (y/n): " CONFIRM_UNINSTALL
    if [[ "$CONFIRM_UNINSTALL" != "y" ]]; then
        log_info "操作已取消。"
        return
    fi
    
    # 1. 移除脚本文件
    if [[ -f "$SCRIPT_PATH" ]]; then
        rm -f "$SCRIPT_PATH"
        log_success "脚本文件已删除。"
    else
        log_warn "脚本文件不存在，跳过。"
    fi

    # 2. 清理 .bashrc 中的别名 (包括可能存在的旧版本别名)
    # 删除 'alias "ipv6"...'
    sed -i '/alias "ipv6"=/d' ~/.bashrc
    # 删除可能残留的 'alias "change ipv6"...'
    sed -i '/alias "change ipv6"=/d' ~/.bashrc
    
    log_success "配置文件 (.bashrc) 已清理。"

    # 3. 尝试在当前脚本环境中取消别名 (虽然不影响父shell，但为了逻辑完整)
    unalias ipv6 2>/dev/null

    echo ""
    log_success "✅ 卸载完成！"
    log_info "现在输入 'ipv6' 命令将不再生效 (提示 'No such file')。"
    log_info "下次重新登录 SSH 后，别名定义将彻底从内存中消失。"
    exit 0
}

# --- 4. 环境检测 ---
detect_environment() {
    # 自动检测主要网络接口
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -z "$INTERFACE" ]]; then
        INTERFACE=$(ip -6 route | grep default | awk '{print $5}' | head -n1)
    fi

    if [[ -z "$INTERFACE" ]]; then
        log_error "无法自动检测到网络接口，请手动检查网络配置。"
        exit 1
    fi

    # 获取当前 IPv6
    CURRENT_IPV6=$(ip -6 addr show dev "$INTERFACE" | grep "inet6" | grep "global" | awk '{print $2}' | head -n1)
    # 获取当前 IPv6 网关
    GATEWAY=$(ip -6 route show default dev "$INTERFACE" | awk '{print $3}' | head -n1)
}

# --- 5. 用户交互获取新的 IPv6 ---
prompt_new_ipv6() {
    echo ""
    log_info "当前接口: ${GREEN}$INTERFACE${NC}"
    if [[ -n "$CURRENT_IPV6" ]]; then
        echo -e "当前 IP: ${YELLOW}$CURRENT_IPV6${NC}"
    fi
    
    while true; do
        echo -e "${BLUE}请输入新的 IPv6 地址 (例如: 2001:db8::1/64)${NC}"
        read -p "IPv6 Address: " NEW_IPV6_INPUT
        
        NEW_IPV6_INPUT=$(echo "$NEW_IPV6_INPUT" | xargs) # 去除空格

        if [[ -z "$NEW_IPV6_INPUT" ]]; then
            log_error "输入不能为空。"
            continue
        fi

        # 基础格式校验
        if [[ ! "$NEW_IPV6_INPUT" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}(/[0-9]{1,3})?$ ]]; then
             log_error "格式错误，请检查。"
             read -p "是否强制使用? (y/n): " CONFIRM
             [[ "$CONFIRM" != "y" ]] && continue
        fi
        
        break
    done

    # 默认补全 /64
    if [[ "$NEW_IPV6_INPUT" == *"/"* ]]; then
        NEW_IPV6_FULL="$NEW_IPV6_INPUT"
    else
        NEW_IPV6_FULL="${NEW_IPV6_INPUT}/64"
    fi
}

# --- 6. 执行临时修改 ---
apply_temporary_change() {
    prompt_new_ipv6
    
    echo ""
    log_info "正在应用 [临时修改]..."
    
    # 删旧
    if [[ -n "$CURRENT_IPV6" ]]; then
        ip -6 addr del "$CURRENT_IPV6" dev "$INTERFACE" 2>/dev/null || true
    fi

    # 加新
    if ip -6 addr add "$NEW_IPV6_FULL" dev "$INTERFACE"; then
        log_success "临时 IP 已生效。"
    else
        log_error "IP 添加失败！"
        exit 1
    fi

    # 修复网关
    if [[ -n "$GATEWAY" ]]; then
        if ! ip -6 route show default | grep -q "$GATEWAY"; then
            ip -6 route add default via "$GATEWAY" dev "$INTERFACE" || true
        fi
    fi

    verify_connectivity
}

# --- 7. 执行永久修改 (智能判断) ---
apply_permanent_change() {
    prompt_new_ipv6
    
    echo ""
    log_warn "即将修改系统配置文件以实现 [永久生效]。"
    read -p "确认执行? (y/n): " CONFIRM_PERM
    if [[ "$CONFIRM_PERM" != "y" ]]; then return; fi
    
    # 1. NetworkManager
    if command -v nmcli &> /dev/null && nmcli device status | grep -q "$INTERFACE"; then
        log_info "检测到 NetworkManager，正在配置..."
        nmcli connection modify "$INTERFACE" ipv6.addresses "$NEW_IPV6_FULL" ipv6.method manual
        nmcli connection up "$INTERFACE"
        log_success "NetworkManager 配置完成。"
        
    # 2. Netplan (Ubuntu 18.04+)
    elif [[ -d "/etc/netplan" ]]; then
        log_info "检测到 Netplan，正在生成配置..."
        NETPLAN_FILE="/etc/netplan/01-ipv6-static.yaml"
cat > "$NETPLAN_FILE" << EOF
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp6: false
      addresses:
        - $NEW_IPV6_FULL
      # routes:
      #   - to: default
      #     via: YOUR_GATEWAY
EOF
        netplan apply
        log_success "Netplan 配置已应用 (网关需手动检查 YAML)。"

    # 3. /etc/network/interfaces (Debian/Old Ubuntu)
    elif [[ -f "/etc/network/interfaces" ]]; then
        log_info "检测到 interfaces 文件，正在追加配置..."
        cp "/etc/network/interfaces" "/etc/network/interfaces.bak"
cat >> "/etc/network/interfaces" << EOF

# Added by ipv6 script
iface $INTERFACE inet6 static
address ${NEW_IPV6_FULL%%/*}
netmask ${NEW_IPV6_FULL##*/}
# gateway YOUR_GATEWAY
EOF
        # 尝试立即生效
        if [[ -n "$CURRENT_IPV6" ]]; then ip -6 addr del "$CURRENT_IPV6" dev "$INTERFACE" 2>/dev/null; fi
        ip -6 addr add "$NEW_IPV6_FULL" dev "$INTERFACE"
        
        log_success "Interfaces 配置已添加 (需重启网络服务或机器以完全验证)。"
    else
        log_error "未识别的网络配置系统，请手动修改。"
        exit 1
    fi
    
    verify_connectivity
}

# --- 8. 验证 ---
verify_connectivity() {
    echo ""
    log_info "验证连通性 (Ping Google IPv6)..."
    if ping6 -c 2 -W 2 google.com &> /dev/null; then
        log_success "网络通畅！"
    else
        log_warn "Ping 失败。请检查网关设置或防火墙。"
        if [[ -n "$GATEWAY" ]]; then
            log_info "尝试 Ping 网关 ($GATEWAY)..."
            ping6 -c 2 -W 2 "$GATEWAY"
        fi
    fi
}

# --- 9. 主菜单 ---
main_menu() {
    check_root
    
    # 自安装检查
    if [[ "$0" == *change_ipv6* ]]; then
        install_script
    fi

    detect_environment

    while true; do
        echo -e "\n${BLUE}========== IPv6 管理工具 ==========${NC}"
        echo -e "当前 IP: ${YELLOW}${CURRENT_IPV6:-未检测到}${NC}"
        echo "---"
        echo -e "1. ${GREEN}永久更改 IP${NC} (推荐)"
        echo -e "2. ${YELLOW}临时更改 IP${NC} (重启失效)"
        echo -e "3. ${RED}卸载脚本${NC} (移除别名和文件)"
        echo -e "0. 退出"
        echo "---"
        read -p "请输入选项 [0-3]: " CHOICE
        
        case "$CHOICE" in
            1) apply_permanent_change ;;
            2) apply_temporary_change ;;
            3) uninstall_script ;;
            0) exit 0 ;;
            *) log_error "无效选项" ;;
        esac
        
        echo ""
        read -p "按回车键返回菜单..."
    done
}

main_menu
