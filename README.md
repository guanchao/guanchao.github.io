# Shuwoom的博客

基于 Hugo + Stack 主题搭建的个人博客，自动部署到 GitHub Pages。

## 🚀 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/guanchao/guanchao.github.io.git
cd shuwoom.github.io
```

### 2. 初始化主题

```bash
git submodule update --init --recursive
```

### 3. 本地预览

首先确保已安装 Hugo (推荐使用 extended 版本):

```bash
# macOS
brew install hugo

# 或下载二进制文件
# https://github.com/gohugoio/hugo/releases
```

启动本地服务器：

```bash
hugo server -D
```

然后在浏览器访问 `http://localhost:1313`

## ✍️ 写作指南

### 创建新文章

```bash
hugo new post/my-new-post/index.md
```

文章会创建在 `content/post/my-new-post/index.md`

### 文章格式

```markdown
---
title: "文章标题"
date: 2026-01-14
draft: false
description: "文章描述"
tags: 
  - 标签1
  - 标签2
categories:
  - 分类
image: ""
---

## 正文开始

这里是文章内容...
```

### 添加图片

将图片放在文章同目录下：

```
content/
└── post/
    └── my-post/
        ├── index.md
        └── image.jpg
```

在 markdown 中引用：

```markdown
![描述](image.jpg)
```

## 📦 部署

### GitHub Pages 自动部署

1. **创建 GitHub 仓库**
   - 仓库名：`username.github.io` (将 username 替换为你的 GitHub 用户名)

2. **推送代码**
   ```bash
   git remote add origin https://github.com/guanchao/guanchao.github.io.git
   git add .
   git commit -m "Initial commit"
   git push -u origin main
   ```

3. **配置 GitHub Pages**
   - 进入仓库的 Settings → Pages
   - Source 选择 "GitHub Actions"

4. **完成！**
   - 每次推送到 main 分支，GitHub Actions 会自动构建并部署
   - 访问 `https://guanchao.github.io` 查看博客

### 手动构建

```bash
hugo
```

生成的静态文件在 `public/` 目录，可以部署到任何静态托管服务。

## 🔧 配置说明

主要配置文件是 `hugo.toml`：

- `baseURL`: 网站地址
- `title`: 网站标题
- `params.sidebar`: 侧边栏配置
- `menu`: 菜单配置

## 📁 目录结构

```
.
├── archetypes/          # 文章模板
├── content/             # 内容目录
│   ├── page/           # 页面（关于、归档等）
│   └── post/           # 博客文章
├── static/             # 静态资源
├── themes/             # 主题
│   └── hugo-theme-stack/
├── .github/            # GitHub Actions 配置
├── hugo.toml           # Hugo 配置文件
└── README.md
```

## 🎨 自定义

### 修改头像

1. 将头像图片放到 `static/img/avatar.png`
2. 或修改 `hugo.toml` 中的 `params.sidebar.avatar.src`

### 修改主题颜色

编辑 `assets/scss/custom.scss` (需要创建此文件)

### 添加社交链接

在 `hugo.toml` 中添加：

```toml
[[params.sidebar.social]]
  identifier = "github"
  name = "GitHub"
  url = "https://github.com/shuwoom"
  params:
    icon = "brand-github"
```

## 📝 常用命令

```bash
# 本地预览（包含草稿）
hugo server -D

# 构建生产版本
hugo

# 创建新文章
hugo new post/title/index.md

# 更新主题
git submodule update --remote --merge
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可

本项目采用 MIT 许可证。

---

💡 **提示**: 修改 `hugo.toml` 和这个 README 中的个人信息（邮箱、GitHub 用户名等）。
