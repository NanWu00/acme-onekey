#!/bin/bash

# 网络接口名称
INTERFACE="enp0s3"

# 提示用户输入新的IPv6地址
echo "请输入新的 IPv6 地址（前缀保持 /128）："
read NEW_IPV6

# 确保输入不为空
if [[ -z "$NEW_IPV6" ]]; then
    echo "错误：IPv6 地址不能为空！"
    exit 1
fi

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
