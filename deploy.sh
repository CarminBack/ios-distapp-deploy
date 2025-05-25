#12131
#!/bin/bash
set -e

# 基本变量
DOMAIN="ios.mewinyou.xyz"
EMAIL="649985538@qq.com"
GIT_REPO="https://github.com/CarminBack/ios-distapp-deploy.git"
APP_DIR="/opt/ios-distapp"
FORMAL_USER="carmin"
FORMAL_PASS="a649985538"
TEMP_USER="tempadmin"
TEMP_PASS="a123456"

echo "Step 1: 安装必要软件"
apt update
apt install -y docker.io docker-compose socat curl

echo "Step 2: 停止占用 80/443 端口的服务"
fuser -k 80/tcp || true
fuser -k 443/tcp || true

echo "Step 3: 安装 acme.sh 申请证书"
curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --set-default-ca --server zerossl

echo "Step 4: 申请域名证书"
~/.acme.sh/acme.sh --issue --standalone -d $DOMAIN --email $EMAIL --force

echo "Step 5: 安装证书到系统目录"
mkdir -p /etc/ssl/$DOMAIN
~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
--key-file /etc/ssl/$DOMAIN/key.pem \
--fullchain-file /etc/ssl/$DOMAIN/cert.pem \
--reloadcmd "docker restart ios-distapp || true"

echo "Step 6: 拉取最新项目代码"
rm -rf $APP_DIR
git clone $GIT_REPO $APP_DIR

cd $APP_DIR

echo "Step 7: 生成配置.env文件"
cat > .env <<EOF
FORMAL_USER=$FORMAL_USER
FORMAL_PASS=$FORMAL_PASS
TEMP_USER=$TEMP_USER
TEMP_PASS=$TEMP_PASS
DOMAIN=$DOMAIN
EMAIL=$EMAIL
EOF

echo "Step 8: 启动 Docker 容器"
docker compose down || true
docker compose up -d --build

echo "部署完成！访问 https://$DOMAIN 检查服务状态。"
