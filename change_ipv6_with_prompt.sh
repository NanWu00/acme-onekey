#!/bin/bash

# ==========================================
# IPv6 修改工具 (Enhanced Version)
# 功能：自动检测网卡，安全修改IPv6，验证连通性
# ==========================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- 辅助函数 ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 1. 权限检查 ---
if [[ $EUID -ne 0 ]]; then
   log_error "此脚本必须以 root 身份运行"
   exit 1
fi

# --- 2. 自动安装逻辑 (可选) ---
SCRIPT_PATH="/usr/local/bin/change_ipv6"
CURRENT_PATH=$(realpath "$0")

if [[ "$CURRENT_PATH" != "$SCRIPT_PATH" ]]; then
    log_info "正在安装脚本到系统路径..."
    cp "$CURRENT_PATH" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    # 添加 alias
    if ! grep -q "change ipv6" ~/.bashrc; then
        echo 'alias "change ipv6"="/usr/local/bin/change_ipv6"' >> ~/.bashrc
        log_success "快捷命令已添加。请执行 'source ~/.bashrc' 或重新登录以生效。"
    else
        log_info "快捷命令已存在。"
    fi
    
    log_success "安装完成！您以后可以直接输入 'change ipv6' 来运行此脚本。"
    echo ""
fi

# --- 3. 环境检测 ---
log_info "正在检测网络环境..."

# 自动检测主要网络接口
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [[ -z "$INTERFACE" ]]; then
    # 尝试 IPv6 路由
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
GATEWAY=$(ip -6 route show default dev "$INTERFACE" | awk '{print $3}')
if [[ -z "$GATEWAY" ]]; then
    log_warn "未检测到默认 IPv6 网关，可能无法连接外网。"
else
    log_info "当前 IPv6 网关: ${YELLOW}$GATEWAY${NC}"
fi

echo ""

# --- 4. 用户交互 ---
while true; do
    echo -e "${BLUE}请输入新的 IPv6 地址 (例如: 2001:db8::1)${NC}"
    read -p "IPv6 Address: " NEW_IPV6_INPUT
    
    # 简单格式清理
    NEW_IPV6_INPUT=$(echo "$NEW_IPV6_INPUT" | xargs)

    if [[ -z "$NEW_IPV6_INPUT" ]]; then
        log_error "输入不能为空，请重新输入。"
        continue
    fi

    # 简单的 IPv6 格式校验 (利用 ipcalc 或 grep)
    # 这里使用 grep 进行基础正则匹配
    if [[ ! "$NEW_IPV6_INPUT" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
         log_error "IPv6 地址格式看起来不正确，请检查。"
         read -p "是否确认使用此地址? (y/n): " CONFIRM
         if [[ "$CONFIRM" != "y" ]]; then
             continue
         fi
    fi
    
    break
done

# 确保地址带上前缀长度，默认 /64 或 /128，这里沿用原脚本逻辑 /128
# 如果用户输入了 /xx，则使用用户的，否则默认 /128
if [[ "$NEW_IPV6_INPUT" == *"/"* ]]; then
    NEW_IPV6_FULL="$NEW_IPV6_INPUT"
else
    NEW_IPV6_FULL="${NEW_IPV6_INPUT}/128"
fi

echo ""
log_info "准备将 IPv6 修改为: ${GREEN}$NEW_IPV6_FULL${NC}"
read -p "按回车键确认执行，按 Ctrl+C 取消..."

# --- 5. 执行修改 ---
log_info "正在应用更改..."

# 删除旧地址 (如果有)
if [[ -n "$CURRENT_IPV6" ]]; then
    ip -6 addr del "$CURRENT_IPV6" dev "$INTERFACE" 2>/dev/null || true
fi

# 添加新地址
if ip -6 addr add "$NEW_IPV6_FULL" dev "$INTERFACE"; then
    log_success "IP 地址添加成功。"
else
    log_error "IP 地址添加失败！"
    exit 1
fi

# 恢复网关 (如果之前有网关且被删除了，通常 addr del 不会删路由，但为了保险)
if [[ -n "$GATEWAY" ]]; then
    # 检查路由是否存在
    if ! ip -6 route show default | grep -q "$GATEWAY"; then
        log_info "正在恢复默认网关..."
        ip -6 route add default via "$GATEWAY" dev "$INTERFACE" || log_warn "网关恢复失败，请手动检查。"
    fi
fi

# --- 6. 验证 ---
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

echo ""
echo -e "${YELLOW}[注意] 此修改为临时生效 (Runtime)。重启 VPS 后会失效。${NC}"
echo -e "${YELLOW}       如需永久生效，请修改 /etc/network/interfaces 或 /etc/netplan/ 配置文件。${NC}"
