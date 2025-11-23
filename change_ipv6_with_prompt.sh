#!/bin/bash

# 下载并保存脚本到 /usr/local/bin/change_ipv6
echo "正在下载 change_ipv6 脚本..."
curl -sSL https://raw.githubusercontent.com/NanWu00/acme-onekey/refs/heads/main/change_ipv6_with_prompt.sh -o /usr/local/bin/change_ipv6

# 给下载的脚本添加执行权限
echo "为脚本添加执行权限..."
sudo chmod +x /usr/local/bin/change_ipv6

# 创建快捷命令 (使 change ipv6 可以执行)
if ! grep -q "change ipv6" ~/.bashrc; then
    echo 'alias "change ipv6"="/usr/local/bin/change_ipv6"' >> ~/.bashrc
    echo "快捷命令已创建：change ipv6"
else
    echo "快捷命令已经存在：change ipv6"
fi

# 让 alias 立即生效
source ~/.bashrc

# 提示用户输入新的 IPv6 地址
echo "请输入新的 IPv6 地址（前缀保持 /128）："
read NEW_IPV6

# 确保输入不为空
if [[ -z "$NEW_IPV6" ]]; then
    echo "错误：IPv6 地址不能为空！"
    exit 1
fi

# 网络接口名称
INTERFACE="enp0s3"

# 删除当前的 IPv6 地址（确保是旧的地址）
OLD_IPV6=$(ip -6 addr show dev $INTERFACE | grep "inet6" | awk '{print $2}')
echo "当前 IPv6 地址是：$OLD_IPV6"
ip -6 addr del $OLD_IPV6 dev $INTERFACE

# 为网络接口添加新的 IPv6 地址（保持前缀为 /128）
ip -6 addr add $NEW_IPV6/128 dev $INTERFACE

# 更新路由，确保保持原来的网关
GATEWAY=$(ip -6 route show dev $INTERFACE | grep default | awk '{print $3}')
ip -6 route replace default via $GATEWAY dev $INTERFACE

# 重新启动网络服务使配置生效
systemctl restart networking

# 输出新的配置
echo "新的 IPv6 地址: $NEW_IPV6 已成功配置到 $INTERFACE"
echo "当前路由设置:"
ip -6 route show dev $INTERFACE
