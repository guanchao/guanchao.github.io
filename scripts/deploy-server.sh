#!/bin/bash
# 部署到自己服务器的脚本

# 配置项（请根据实际情况修改）
SERVER_USER="your_user"
SERVER_HOST="your_server_ip"
SERVER_PATH="/var/www/html"

echo "🔨 开始构建..."
hugo --minify

if [ $? -ne 0 ]; then
    echo "❌ 构建失败！"
    exit 1
fi

echo "✅ 构建完成！"
echo ""
echo "📤 上传到服务器 ${SERVER_USER}@${SERVER_HOST}..."

rsync -avz --delete \
    --exclude '.git' \
    --exclude '.DS_Store' \
    public/ ${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}

if [ $? -eq 0 ]; then
    echo "✅ 部署成功！"
    echo "🌐 访问你的网站查看更新"
else
    echo "❌ 部署失败！"
    exit 1
fi
