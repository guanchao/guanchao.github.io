# 项目初始化指南

## 📋 准备工作

### 1. 安装 Hugo

#### macOS
```bash
brew install hugo
```

#### Linux
```bash
# Ubuntu/Debian
sudo apt install hugo

# 或下载最新版本
wget https://github.com/gohugoio/hugo/releases/download/v0.121.0/hugo_extended_0.121.0_linux-amd64.deb
sudo dpkg -i hugo_extended_0.121.0_linux-amd64.deb
```

#### Windows
```powershell
choco install hugo-extended
```

#### 验证安装
```bash
hugo version
```

确保版本号 >= 0.100.0，并且是 **extended** 版本（Stack 主题需要）。

## 🚀 初始化项目

### 步骤1：初始化 Git 仓库

```bash
cd /Users/shuwoom/Desktop/shuwoom.com
git init
```

### 步骤2：添加 Stack 主题

```bash
# 将主题添加为子模块
git submodule add https://github.com/CaiJimmy/hugo-theme-stack.git themes/hugo-theme-stack
```

### 步骤3：首次提交

```bash
git add .
git commit -m "Initial commit: Hugo + Stack theme setup"
```

## 🌐 部署到 GitHub Pages

### 步骤1：创建 GitHub 仓库

1. 访问 https://github.com/new
2. 仓库名称：`guanchao.github.io`
3. 设置为 Public
4. 不要初始化 README、.gitignore 或 license（我们已经有了）

### 步骤2：连接远程仓库

```bash
git remote add origin https://github.com/guanchao/guanchao.github.io.git
git branch -M main
git push -u origin main
```

### 步骤3：配置 GitHub Pages

1. 进入仓库页面
2. 点击 **Settings** → **Pages**
3. 在 **Source** 下选择 **GitHub Actions**

### 步骤4：等待部署完成

1. 进入 **Actions** 标签页
2. 查看部署状态
3. 部署成功后，访问 `https://guanchao.github.io`

## 🔧 本地开发

### 启动开发服务器

```bash
hugo server -D
```

参数说明：
- `-D` 或 `--buildDrafts`: 包含草稿文章
- `-F` 或 `--buildFuture`: 包含未来日期的文章
- `--bind 0.0.0.0`: 允许局域网访问
- `-p 8080`: 指定端口（默认 1313）

### 创建新文章

```bash
hugo new post/my-first-post/index.md
```

### 构建生产版本

```bash
hugo --minify
```

生成的文件在 `public/` 目录。

## 📝 配置自定义域名

### 如果你有自己的域名（如 shuwoom.com）

#### 1. 在项目根目录创建 `static/CNAME` 文件

```bash
echo "shuwoom.com" > static/CNAME
```

#### 2. 修改 `hugo.toml` 中的 baseURL

```toml
baseURL = 'https://shuwoom.com/'
```

#### 3. 配置 DNS

在你的域名注册商添加以下 DNS 记录：

**方式1：使用 CNAME（推荐）**
```
CNAME  @  guanchao.github.io
```

**方式2：使用 A 记录**
```
A  @  185.199.108.153
A  @  185.199.109.153
A  @  185.199.110.153
A  @  185.199.111.153
```

#### 4. 在 GitHub 配置自定义域名

1. 仓库 Settings → Pages
2. Custom domain 输入: `shuwoom.com`
3. 勾选 Enforce HTTPS

## 🖥️ 部署到自己的 Linux 服务器

### 方式1：手动部署

```bash
# 本地构建
hugo --minify

# 上传到服务器
rsync -avz --delete public/ user@your-server.com:/var/www/html/
```

### 方式2：Git 自动部署

在服务器上设置 Git Hook：

```bash
# 服务器上
cd /var/repo
git init --bare blog.git

# 创建 post-receive hook
cat > blog.git/hooks/post-receive << 'EOF'
#!/bin/bash
GIT_WORK_TREE=/var/www/html
export GIT_WORK_TREE
git checkout -f
cd $GIT_WORK_TREE
hugo --minify
EOF

chmod +x blog.git/hooks/post-receive
```

本地添加服务器为远程仓库：

```bash
git remote add server user@your-server.com:/var/repo/blog.git
git push server main
```

### 方式3：使用 GitHub Actions 部署到服务器

修改 `.github/workflows/deploy.yml`，在最后添加：

```yaml
- name: Deploy to Server
  uses: appleboy/scp-action@master
  with:
    host: ${{ secrets.SERVER_HOST }}
    username: ${{ secrets.SERVER_USER }}
    key: ${{ secrets.SERVER_SSH_KEY }}
    source: "public/*"
    target: "/var/www/html"
```

在 GitHub 仓库 Settings → Secrets 中添加：
- `SERVER_HOST`: 服务器IP
- `SERVER_USER`: SSH用户名
- `SERVER_SSH_KEY`: SSH私钥

## 🎨 自定义配置

### 修改网站信息

编辑 `hugo.toml`：

```toml
baseURL = 'https://guanchao.github.io/'
title = '你的博客名称'

[params]
  description = "你的博客描述"
  
  [params.sidebar]
    emoji = "🎯"  # 修改侧边栏 emoji
    subtitle = "你的个性签名"
```

### 添加头像

将头像图片保存为 `static/img/avatar.png`

### 添加社交链接

在 `hugo.toml` 中添加：

```toml
[[params.sidebar.social]]
  identifier = "github"
  name = "GitHub"
  url = "https://github.com/guanchao"
```

## 🐛 常见问题

### Q: 主题没有加载？

A: 确保主题已正确添加：
```bash
git submodule update --init --recursive
```

### Q: Hugo 版本过低？

A: Stack 主题需要 Hugo Extended >= 0.87.0
```bash
hugo version
```

### Q: 部署后样式错误？

A: 检查 `hugo.toml` 中的 `baseURL` 是否正确。

### Q: GitHub Actions 部署失败？

A: 检查：
1. 仓库 Settings → Actions → General → Workflow permissions 设置为 "Read and write permissions"
2. Pages 设置中 Source 选择 "GitHub Actions"

## 📚 参考资源

- [Hugo 官方文档](https://gohugo.io/documentation/)
- [Stack 主题文档](https://stack.jimmycai.com/)
- [GitHub Pages 文档](https://docs.github.com/en/pages)
- [Markdown 语法](https://www.markdownguide.org/)

## 💡 下一步

- ✅ 项目已初始化
- ✅ 配置文件已创建
- ✅ 示例文章已添加
- ⬜ 添加主题子模块
- ⬜ 推送到 GitHub
- ⬜ 配置 GitHub Pages
- ⬜ 开始写作！

---

需要帮助？查看 [README.md](README.md) 或提交 Issue。
