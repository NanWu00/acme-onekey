#!/bin/bash
# ============================================
# 一键申请并安装 ACME SSL 证书脚本
# 作者：hluneko
# 适用系统：Debian / Ubuntu
# ============================================

echo "🚀 开始安装 acme.sh 证书申请环境..."

# 1. 安装 acme.sh
if ! command -v acme.sh &> /dev/null; then
    echo "📦 正在安装 acme.sh ..."
    curl https://get.acme.sh | sh -s email=hluneko01@gmail.com
else
    echo "✅ acme.sh 已安装，跳过此步骤。"
fi

# 2. 安装 socat
echo "📦 安装 socat..."
sudo apt update -y && sudo apt install -y socat

# 3. 添加软链接
if [ ! -f "/usr/local/bin/acme.sh" ]; then
    echo "🔗 创建软链接..."
    ln -s /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
fi

# 4. 切换到 Let's Encrypt CA
echo "🌐 切换默认 CA 到 Let's Encrypt..."
acme.sh --set-default-ca --server letsencrypt

# 5. 输入域名
echo "请输入要申请证书的域名（例如：example.com）"
read -p "👉 域名: " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "❌ 未输入域名，脚本退出。"
    exit 1
fi

# 6. 申请并安装证书
echo "🔐 正在申请证书，请稍候..."
acme.sh --issue -d "$DOMAIN" --standalone -k ec-256

if [ $? -ne 0 ]; then
    echo "❌ 证书申请失败，请检查端口占用或域名解析。"
    exit 1
fi

echo "📥 正在安装证书..."
acme.sh --installcert -d "$DOMAIN" \
    --key-file /root/private.key \
    --fullchain-file /root/cert.crt

echo "✅ 证书已安装完成！"
echo "🔑 私钥文件路径：/root/private.key"
echo "📄 证书文件路径：/root/cert.crt"
echo "🎉 全部步骤执行完毕！"