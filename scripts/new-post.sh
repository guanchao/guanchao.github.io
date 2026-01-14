#!/bin/bash
# 快速创建新文章的脚本

# 检查是否提供了文章标题
if [ -z "$1" ]; then
    echo "用法: ./scripts/new-post.sh \"文章标题\""
    echo "示例: ./scripts/new-post.sh \"我的第一篇博客\""
    exit 1
fi

# 将标题转换为 URL 友好的格式（小写，空格替换为连字符）
TITLE="$1"
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

# 创建文章
hugo new "post/${SLUG}/index.md"

echo "✅ 文章已创建: content/post/${SLUG}/index.md"
echo "📝 开始编辑你的文章吧！"
echo ""
echo "提示："
echo "  - 本地预览: hugo server -D"
echo "  - 发布时记得设置 draft: false"
