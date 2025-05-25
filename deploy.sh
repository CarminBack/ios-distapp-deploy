#!/bin/bash

set -e

# 基本信息（你提供的）
DOMAIN="ios.mewinyou.xyz"
EMAIL="649985538@qq.com"
IP="8.213.194.163"
USER1="carmin"
PASS1="a649985538"
USER2="tempadmin"
PASS2="a123456"

echo "开始部署 iOS 分发平台..."

# 1. 安装 Docker 和 docker-compose（如果未安装）
if ! command -v docker &>/dev/null; then
  echo "安装 Docker..."
  curl -fsSL https://get.docker.com | bash
  systemctl start docker
  systemctl enable docker
fi

if ! docker compose version &>/dev/null; then
  echo "安装 Docker Compose 插件..."
  apt-get update
  apt-get install -y docker-compose-plugin
fi

# 2. 关闭 80 和 443 端口占用，确保能申请证书
echo "释放 80 和 443 端口..."
fuser -k 80/tcp || true
fuser -k 443/tcp || true

# 3. 安装 acme.sh 并申请证书
if [ ! -d ~/.acme.sh ]; then
  echo "安装 acme.sh..."
  curl https://get.acme.sh | sh
fi

export PATH=~/.acme.sh:$PATH
echo "申请证书..."
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone --keylength ec-256 --email $EMAIL --force

# 4. 安装证书到指定位置
mkdir -p ./certs
~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
  --key-file ./certs/key.pem \
  --fullchain-file ./certs/fullchain.pem \
  --reloadcmd "echo '证书已安装'"

# 5. 准备工作目录和存储 IPA 文件目录
mkdir -p ./ipa-storage

# 6. 生成 FastAPI 服务器代码（main.py）
cat > main.py <<EOF
from fastapi import FastAPI, UploadFile, File, HTTPException, Depends
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from fastapi.responses import FileResponse
import shutil, os, secrets

app = FastAPI()
security = HTTPBasic()

USERS = {
    "${USER1}": "${PASS1}",
    "${USER2}": "${PASS2}"
}

IPA_DIR = "/app/ipa-storage"

def verify(credentials: HTTPBasicCredentials = Depends(security)):
    correct_password = USERS.get(credentials.username)
    if not correct_password or not secrets.compare_digest(credentials.password, correct_password):
        raise HTTPException(status_code=401, detail="Unauthorized")
    return credentials.username

@app.get("/")
def root():
    return {"message": "Welcome to iOS IPA Distribution"}

@app.post("/upload/")
async def upload_ipa(file: UploadFile = File(...), username: str = Depends(verify)):
    if not file.filename.endswith(".ipa"):
        raise HTTPException(status_code=400, detail="Only .ipa files allowed")
    dest_path = os.path.join(IPA_DIR, file.filename)
    with open(dest_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"filename": file.filename, "message": "Upload successful"}

@app.get("/download/{filename}")
def download_ipa(filename: str, username: str = Depends(verify)):
    file_path = os.path.join(IPA_DIR, filename)
    if not os.path.isfile(file_path):
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(path=file_path, filename=filename, media_type="application/octet-stream")

@app.get("/list")
def list_ipa(username: str = Depends(verify)):
    files = os.listdir(IPA_DIR)
    return {"files": files}
EOF

# 7. 生成 Dockerfile
cat > Dockerfile <<EOF
FROM python:3.11-slim
WORKDIR /app
COPY main.py /app/
RUN pip install fastapi uvicorn
RUN pip install "python-multipart" "aiofiles"
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

# 8. 生成 docker-compose.yml
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  ios-distapp:
    build: .
    ports:
      - "80:8000"
      - "443:8000"
    volumes:
      - ./ipa-storage:/app/ipa-storage
      - ./certs:/certs:ro
EOF

# 9. 构建并启动容器
docker compose build
docker compose up -d

echo "部署完成！请访问 https://${DOMAIN} 使用账号密码登录上传下载 IPA。"
