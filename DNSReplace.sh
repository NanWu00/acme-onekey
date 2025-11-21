#!/bin/bash

# 定义颜色和表情
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# 检查是否是 root 用户
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ 哎呀，需要 root 权限才能修改系统文件哦！${PLAIN}"
   echo -e "${YELLOW}👉 请输入: sudo bash $0${PLAIN}"
   exit 1
fi

clear
echo -e "${GREEN}==============================================${PLAIN}"
echo -e "${GREEN}      🌟 强力 DNS 修改小助手 (防重置版) 🌟      ${PLAIN}"
echo -e "${GREEN}==============================================${PLAIN}"
echo -e "你的系统 DNS 总是被云厂商重置？交给我吧！💪"
echo ""
echo -e "${YELLOW}请选择一个模式：${PLAIN}"
echo -e "  1. 🚀 极速推荐 (Cloudflare + Google 混合, 最稳)"
echo -e "     -> IPv4: 1.1.1.1, 8.8.8.8"
echo -e "     -> IPv6: 2606:4700:4700::1111 (预留)"
echo -e "  2. ✍️ 自定义输入 (我想自己填 IP)"
echo -e "  3. 💊 后悔药 (解锁文件并恢复默认, 允许系统修改)"
echo ""
read -p "请选择 (输入数字并回车): " choice

# 核心修改函数
function update_dns() {
    local dns1=$1
    local dns2=$2
    local dns3=$3
    local dns4=$4

    echo ""
    echo -e "${YELLOW}🔧 正在解除旧文件的锁定...${PLAIN}"
    chattr -i /etc/resolv.conf 2>/dev/null
    
    echo -e "${YELLOW}🗑️  正在清理旧的系统 DNS 配置...${PLAIN}"
    rm -f /etc/resolv.conf

    echo -e "${YELLOW}📝 正在写入新的 DNS 配置...${PLAIN}"
    cat > /etc/resolv.conf <<EOF
nameserver $dns1
nameserver $dns2
nameserver $dns3
nameserver $dns4
options timeout:2 attempts:3 rotate
EOF

    echo -e "${YELLOW}🔒 正在施加魔法锁定文件 (防止 GCP 重置)...${PLAIN}"
    chattr +i /etc/resolv.conf

    echo ""
    echo -e "${GREEN}🎉 大功告成！DNS 修改成功！${PLAIN}"
    echo -e "当前 /etc/resolv.conf 内容如下："
    echo -e "${GREEN}---------------------------------${PLAIN}"
    cat /etc/resolv.conf
    echo -e "${GREEN}---------------------------------${PLAIN}"
}

case $choice in
    1)
        echo -e "${GREEN}✨ 你选择了推荐配置，这就为你安排！${PLAIN}"
        # 包含了 Cloudflare 和 Google 的 IPv4/IPv6
        update_dns "1.1.1.1" "8.8.8.8" "2606:4700:4700::1111" "2001:4860:4860::8888"
        ;;
    2)
        echo ""
        read -p "👉 请输入主 DNS (IPv4，例如 1.1.1.1): " custom_dns1
        read -p "👉 请输入备 DNS (IPv4，例如 8.8.8.8): " custom_dns2
        
        # 简单的非空检查
        if [[ -z "$custom_dns1" ]]; then
            echo -e "${RED}❌ 主 DNS 不能为空哦！退出脚本。${PLAIN}"
            exit 1
        fi
        if [[ -z "$custom_dns2" ]]; then
            custom_dns2="8.8.4.4" # 默认备用
        fi
        
        echo -e "${GREEN}✨ 收到！正在配置你指定的 DNS...${PLAIN}"
        # 这里如果不填 IPv6 就留空，脚本逻辑也能跑
        update_dns "$custom_dns1" "$custom_dns2" "" ""
        ;;
    3)
        echo ""
        echo -e "${YELLOW}🔓 正在解除锁定并尝试恢复...${PLAIN}"
        chattr -i /etc/resolv.conf
        # 重新链接回 systemd (大部分 Ubuntu 的默认路径)
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
        
        echo -e "${GREEN}✅ 锁定已解除！${PLAIN}"
        echo -e "文件已恢复为软链接，重启服务器后 Google 的配置将重新生效。"
        ;;
    *)
        echo -e "${RED}❌ 输错啦，请输入 1, 2 或 3 哦！${PLAIN}"
        exit 1
        ;;
esac
