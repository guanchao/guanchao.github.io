---
title: "Hugo + Stack 主题使用指南"
date: 2026-01-14
draft: false
description: "详细介绍如何使用 Hugo 和 Stack 主题创建和管理博客文章"
tags: 
  - Hugo
  - 教程
  - Stack
categories:
  - 技术
---

## 前言

这篇文章将介绍如何使用 Hugo 和 Stack 主题来写作和发布博客。

## 快速开始

### 创建新文章

使用以下命令创建新文章：

```bash
hugo new post/my-article/index.md
```

这会在 `content/post/` 目录下创建一个新的文章目录。

### Front Matter 说明

每篇文章开头的 YAML 格式配置称为 Front Matter：

```yaml
---
title: "文章标题"          # 必填
date: 2026-01-14           # 必填，发布日期
draft: false               # 是否为草稿
description: "文章描述"    # 文章摘要
tags:                      # 标签
  - 标签1
  - 标签2
categories:                # 分类
  - 分类名
image: "cover.jpg"         # 封面图片（可选）
---
```

## Markdown 语法

### 标题

```markdown
## 二级标题
### 三级标题
#### 四级标题
```

### 代码块

\```python
def hello():
    print("Hello, World!")
\```

效果：

```python
def hello():
    print("Hello, World!")
```

### 引用

```markdown
> 这是一段引用
```

> 这是一段引用

### 列表

```markdown
- 无序列表项 1
- 无序列表项 2

1. 有序列表项 1
2. 有序列表项 2
```

### 链接和图片

```markdown
[链接文本](https://example.com)
![图片描述](image.jpg)
```

## 添加图片

### 方法1：文章内图片

将图片放在文章同目录：

```
content/post/my-article/
├── index.md
├── image1.jpg
└── image2.png
```

然后在 markdown 中引用：

```markdown
![描述](image1.jpg)
```

### 方法2：全局图片

将图片放在 `static/img/` 目录，引用时使用：

```markdown
![描述](/img/image.jpg)
```

## 文章分类

### 使用标签（Tags）

标签用于标记文章的关键词，一篇文章可以有多个标签：

```yaml
tags:
  - Hugo
  - 教程
  - 静态博客
```

### 使用分类（Categories）

分类用于归类文章，通常一篇文章属于一个分类：

```yaml
categories:
  - 技术
```

## 写作技巧

### 使用目录

Stack 主题会自动为文章生成目录（TOC），基于文章中的标题层级。

### 数学公式

如果需要使用数学公式，在 Front Matter 中启用：

```yaml
---
math: true
---
```

然后可以使用 LaTeX 语法：

```markdown
行内公式：$E = mc^2$

块级公式：
$$
\frac{n!}{k!(n-k)!}
$$
```

### 提示框

使用引用语法配合表情符号：

```markdown
> 💡 **提示**: 这是一个提示

> ⚠️ **警告**: 这是一个警告

> ❌ **错误**: 这是一个错误信息
```

## 本地预览

在写作过程中，使用以下命令实时预览：

```bash
hugo server -D
```

- `-D` 参数会显示草稿文章
- 保存文件后浏览器会自动刷新

## 发布流程

1. **完成写作**
   ```bash
   # 确保 draft: false
   ```

2. **本地预览**
   ```bash
   hugo server
   ```

3. **提交到 Git**
   ```bash
   git add .
   git commit -m "新增文章：文章标题"
   git push
   ```

4. **自动部署**
   - GitHub Actions 会自动构建并部署
   - 几分钟后即可在网站上看到新文章

## 常见问题

### Q: 文章不显示？

A: 检查以下几点：
- `draft: false` （不是草稿）
- 日期不能是未来时间
- 文件路径正确

### Q: 图片不显示？

A: 确保：
- 图片路径正确
- 图片文件名没有特殊字符
- 使用相对路径引用

### Q: 如何删除文章？

A: 直接删除文章目录，然后提交到 Git。

## 总结

使用 Hugo + Stack 的写作流程：

1. `hugo new post/title/index.md` - 创建文章
2. 编辑 markdown 文件
3. `hugo server -D` - 本地预览
4. `git push` - 发布

就这么简单！专注于写作，其他的交给 Hugo 和 GitHub Actions 自动处理。

---

Happy Writing! ✍️
