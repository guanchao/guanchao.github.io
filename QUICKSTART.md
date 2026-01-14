# 🚀 快速开始指南

5分钟搭建你的 Hugo 博客！

## 第一步：安装 Hugo

```bash
# macOS
brew install hugo

# 验证安装
hugo version
```

确保版本显示包含 "extended"。

## 第二步：初始化项目

```bash
cd shuwoom.com

# 添加 Stack 主题（作为 git 子模块）
git submodule add https://github.com/CaiJimmy/hugo-theme-stack.git themes/hugo-theme-stack

# 或者如果你已经克隆了项目
git submodule update --init --recursive
```

## 第三步：本地预览

```bash
hugo server -D
```

打开浏览器访问：http://localhost:1313

你应该能看到博客已经运行了！🎉

## 第四步：写第一篇文章

### 方式1：使用脚本（推荐）

```bash
./scripts/new-post.sh "我的第一篇文章"
```

### 方式2：使用 Hugo 命令

```bash
hugo new post/my-first-post/index.md
```

然后编辑 `content/post/my-first-post/index.md`：

```markdown
---
title: "我的第一篇文章"
date: 2026-01-14
draft: false  # 改为 false 表示发布
description: "这是我的第一篇博客文章"
tags: 
  - 开始
categories:
  - 日常
---

## 你好，世界！

这是我的第一篇博客文章。

我可以写任何想写的内容...
```

保存后，浏览器会自动刷新显示新文章。

## 第五步：部署到 GitHub Pages

### 1. 创建 GitHub 仓库

访问 https://github.com/new

- 仓库名：`你的用户名.github.io`（例如：`shuwoom.github.io`）
- 类型：Public
- 不要勾选任何初始化选项

### 2. 推送代码

```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/你的用户名/你的用户名.github.io.git
git push -u origin main
```

### 3. 配置 GitHub Pages

1. 进入仓库的 **Settings**
2. 点击左侧 **Pages**
3. **Source** 选择 **GitHub Actions**
4. 进入仓库的 **Settings** → **Actions** → **General**
5. **Workflow permissions** 选择 **Read and write permissions**
6. 点击 **Save**

### 4. 触发部署

推送代码后会自动触发部署：

```bash
git push
```

查看部署状态：进入仓库的 **Actions** 标签页

部署成功后（约2-3分钟），访问：`https://你的用户名.github.io`

## 🎉 完成！

现在你有了一个可以工作的博客！

## 日常使用

### 写新文章

```bash
# 创建文章
./scripts/new-post.sh "文章标题"

# 本地预览
hugo server -D

# 发布（推送到 GitHub）
git add .
git commit -m "新增文章：文章标题"
git push
```

### 添加图片

将图片放在文章同目录：

```
content/post/my-post/
├── index.md
└── image.jpg
```

在 markdown 中引用：

```markdown
![描述](image.jpg)
```

## 自定义配置

### 修改网站标题和描述

编辑 `hugo.toml`：

```toml
title = '你的博客名称'

[params]
  description = "你的博客描述"
```

### 添加头像

将你的头像保存为 `static/img/avatar.png`

### 修改个人信息

编辑 `content/page/about/index.md`

## 常用命令

```bash
# 本地预览（包含草稿）
hugo server -D

# 创建新文章
hugo new post/title/index.md

# 构建静态文件
hugo

# 查看 Hugo 版本
hugo version
```

## 需要帮助？

- 📖 查看 [README.md](README.md) - 完整文档
- 🔧 查看 [SETUP.md](SETUP.md) - 详细设置指南
- 📝 查看 [Hugo 使用指南](content/post/hugo-tutorial/index.md) - 写作教程

## 下一步

- [ ] 修改 `hugo.toml` 中的个人信息
- [ ] 替换头像图片
- [ ] 编辑"关于"页面
- [ ] 写更多文章
- [ ] 自定义主题样式

---

Happy Blogging! ✍️
