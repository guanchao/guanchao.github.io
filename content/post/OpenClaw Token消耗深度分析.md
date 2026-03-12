---
title: "OpenClaw Token 消耗深度分析 — Agent 系统的 Token \"原罪\""
date: 2026-03-12
draft: false
description: "深入分析 OpenClaw 项目中 Token 的消耗来源、估算机制、优化策略及其实现细节。Token 消耗直接决定了 AI Agent 系统的运行成本，是生产级 Agent 系统中最关键的工程考量之一。"
tags: 
  - OpenClaw
  - AI Agent
  - LLM
  - Token优化
  - 成本分析
  - 源码分析
categories:
  - Agent
  - AI
  - 性能优化
---

# 🦞 OpenClaw Token 消耗深度分析 — Agent 系统的 Token "原罪"

> 本文档深入分析 OpenClaw 项目中 Token 的消耗来源、估算机制、优化策略及其实现细节。Token 消耗直接决定了 AI Agent 系统的运行成本，是生产级 Agent 系统中最关键的工程考量之一。

| 项目信息 | 详情 |
|---------|------|
| **分析版本** | `v2026.1.30` |
| **关联文章** | [OpenClaw 开源项目深度分析](./OpenClaw%20(原ClawdBot)%20开源项目深度分析.md) |

## 目录

- [一、Token 消耗的全景视图](#一token-消耗的全景视图)
  - [1.1 为什么 Token 消耗如此重要](#11-为什么-token-消耗如此重要)
  - [1.2 Token 消耗的六大来源](#12-token-消耗的六大来源)
  - [1.3 单次请求的 Token 构成](#13-单次请求的-token-构成)
- [二、消耗源一：System Prompt（系统提示词）](#二消耗源一system-prompt系统提示词)
  - [2.1 系统提示词的 Token 构成](#21-系统提示词的-token-构成)
  - [2.2 动态内容的 Token 影响](#22-动态内容的-token-影响)
  - [2.3 Prompt Mode 对 Token 的影响](#23-prompt-mode-对-token-的影响)
- [三、消耗源二：工具定义（Tool Schema）](#三消耗源二工具定义tool-schema)
  - [3.1 工具定义的 Token 开销](#31-工具定义的-token-开销)
  - [3.2 核心工具列表](#32-核心工具列表)
- [四、消耗源三：Agentic Loop（多轮工具调用循环）](#四消耗源三agentic-loop多轮工具调用循环)
  - [4.1 Agentic Loop 的 Token 放大效应](#41-agentic-loop-的-token-放大效应)
  - [4.2 累积消耗的数学模型](#42-累积消耗的数学模型)
  - [4.3 工具结果的 Token 消耗](#43-工具结果的-token-消耗)
- [五、消耗源四：对话历史累积](#五消耗源四对话历史累积)
  - [5.1 历史消息的滚雪球效应](#51-历史消息的滚雪球效应)
  - [5.2 历史轮次限制机制](#52-历史轮次限制机制)
- [六、消耗源五：记忆检索](#六消耗源五记忆检索)
  - [6.1 记忆搜索的 Token 开销](#61-记忆搜索的-token-开销)
  - [6.2 memory_get 的精准获取](#62-memory_get-的精准获取)
  - [6.3 优化反思：两步记忆检索的 Token 浪费问题](#63-优化反思两步记忆检索的-token-浪费问题)
- [七、消耗源六：Compaction 压缩机制本身](#七消耗源六compaction-压缩机制本身)
  - [7.1 压缩的悖论：花费 Token 来节省 Token](#71-压缩的悖论花费-token-来节省-token)
  - [7.2 分阶段摘要的额外 API 调用](#72-分阶段摘要的额外-api-调用)
- [八、Token 消耗量化建模](#八token-消耗量化建模)
  - [8.1 单次交互的 Token 构成公式](#81-单次交互的-token-构成公式)
  - [8.2 典型场景消耗估算](#82-典型场景消耗估算)
  - [8.3 长会话的累积消耗](#83-长会话的累积消耗)
- [九、Token 估算与追踪机制](#九token-估算与追踪机制)
  - [9.1 Token 估算方法](#91-token-估算方法)
  - [9.2 Usage 追踪与标准化](#92-usage-追踪与标准化)
  - [9.3 Cache Trace 诊断](#93-cache-trace-诊断)
- [十、现有优化机制分析](#十现有优化机制分析)
  - [10.1 Context Pruning（上下文裁剪）](#101-context-pruning上下文裁剪)
  - [10.2 Compaction Safeguard（压缩安全机制）](#102-compaction-safeguard压缩安全机制)
  - [10.3 上下文窗口保护](#103-上下文窗口保护)
  - [10.4 Prompt Caching（提示缓存）](#104-prompt-caching提示缓存)
  - [10.5 历史轮次限制](#105-历史轮次限制)
- [十一、潜在优化方向](#十一潜在优化方向)
  - [11.1 已实现的优化总结](#111-已实现的优化总结)
  - [11.2 可探索的优化方向](#112-可探索的优化方向)
- [十二、Agent 系统的 Token "原罪"](#十二agent-系统的-token-原罪)
  - [12.1 LLM 无状态——每轮调用必须重传完整上下文](#121-llm-无状态每轮调用必须重传完整上下文)
  - [12.2 Agentic Loop——Token 乘数效应](#122-agentic-looptoken-乘数效应)
  - [12.3 对话历史——滚雪球效应](#123-对话历史滚雪球效应)
  - [12.4 工具生态——越强大越昂贵](#124-工具生态越强大越昂贵)
  - [12.5 OpenClaw 在行业中的优化水平](#125-openclaw-在行业中的优化水平)
  - [12.6 未来破局方向](#126-未来破局方向)
- [十三、总结与关键数字](#十三总结与关键数字)

---

## 一、Token 消耗的全景视图

### 1.1 为什么 Token 消耗如此重要

在 AI Agent 系统中，**Token 是唯一的运行成本单位**。与传统软件不同，Agent 系统的每一次"思考"都需要向 LLM 发送完整的上下文，并按 Token 计费。理解 Token 消耗的来源和优化方式，是构建可持续运行的 Agent 系统的关键。

**成本公式**：
```
总成本 = Σ (input_tokens × 输入单价 + output_tokens × 输出单价)
```

以 Claude Opus 4.5 为例（OpenClaw 默认模型）：
- 输入：$15 / 1M tokens
- 输出：$75 / 1M tokens
- 带缓存的输入：$1.5 / 1M tokens（缓存命中时仅 10% 成本）

这意味着**每一个不必要的 Token 都在烧钱**，而 Agent 的多轮交互特性使得 Token 消耗成倍放大。

### 1.2 Token 消耗的六大来源

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    单次 LLM API 调用的 Token 构成                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────┐            │
│  │              Input Tokens (输入 Token)                    │            │
│  │                                                          │            │
│  │  ① System Prompt (系统提示词)          ~3,000-8,000 tokens │            │
│  │  ② Tool Definitions (工具定义)         ~2,000-5,000 tokens │            │
│  │  ③ Conversation History (对话历史)     0 ~ 200,000 tokens  │            │
│  │  ④ Memory Retrieval (记忆检索结果)     0 ~ 2,000 tokens    │            │
│  │  ⑤ Bootstrap Files (上下文文件)        0 ~ 10,000 tokens   │            │
│  │  ⑥ Current User Message (当前消息)     ~50-500 tokens      │            │
│  │                                                          │            │
│  └─────────────────────────────────────────────────────────┘            │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────┐            │
│  │             Output Tokens (输出 Token)                    │            │
│  │                                                          │            │
│  │  ⑦ Assistant Response (助手回复)       ~100-2,000 tokens   │            │
│  │  ⑧ Tool Calls (工具调用请求)           ~50-500 per call    │            │
│  │  ⑨ Thinking (推理过程)                 0 ~ 5,000 tokens    │            │
│  │                                                          │            │
│  └─────────────────────────────────────────────────────────┘            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.3 单次请求的 Token 构成

**关键洞察**：在 Agent 系统中，输入 Token **远大于**输出 Token。因为每次 API 调用都需要发送完整的上下文（系统提示词 + 工具定义 + 历史消息 + 当前消息），而输出通常只有几百个 Token。

```
典型 Token 分布（第 N 轮对话）:

Input:  ████████████████████████████████████████████  95%
Output: ██                                             5%

其中 Input 内部构成:
System Prompt:  ████                           ~15%
Tool Schema:    ███                            ~10%
History:        ████████████████████████████   ~65%
Current Msg:    █                              ~5%
Bootstrap:      ██                             ~5%
```

---

## 二、消耗源一：System Prompt（系统提示词）

### 2.1 系统提示词的 Token 构成

**文件**: `src/agents/system-prompt.ts`

OpenClaw 的系统提示词采用**模块化构建**，由多个独立的 Section 拼接而成：

```typescript
// 系统提示词的核心构建函数
export function buildAgentSystemPrompt(params: { ... }) {
  const lines = [
    "You are a personal assistant running inside OpenClaw.",  // 身份声明
    "",
    "## Tooling",           // 工具说明
    ...toolLines,           // 每个工具一行描述
    "",
    "## Tool Call Style",   // 工具调用风格
    ...                     // 叙述指南
    "",
    ...buildSafetySection(),        // 安全规则
    "## OpenClaw CLI Quick Reference", // CLI 参考
    ...skillsSection,               // Skills 系统
    ...memorySection,               // 记忆系统
    ...docsSection,                 // 文档参考
    ...                             // Messaging, Voice, Workspace 等
    "# Project Context",            // 项目上下文文件
    ...contextFiles,                // AGENTS.md, SOUL.md 等
    "## Silent Replies",            // 静默回复规则
    "## Heartbeats",                // 心跳检测
    "## Runtime",                   // 运行时信息
  ];
  return lines.filter(Boolean).join("\n");
}
```

**各模块的 Token 估算**：

| 模块 | 大致 Token 数 | 是否必需 | 备注 |
|------|--------------|---------|------|
| Identity (身份声明) | ~20 | ✅ 是 | 固定一行 |
| Tooling (工具列表) | ~500-800 | ✅ 是 | 取决于启用的工具数 |
| Tool Call Style | ~100 | ✅ 是 | 叙述风格指南 |
| Safety | ~120 | ✅ 是 | 安全约束 |
| CLI Reference | ~100 | 否 | CLI 命令参考 |
| Skills | ~200-500 | 否 | 取决于可用 Skills 数量 |
| Memory Recall | ~60 | 否 | 仅在启用记忆时 |
| Messaging | ~200-400 | 否 | 消息系统指南 |
| Docs | ~80 | 否 | 文档路径 |
| Workspace | ~50 | ✅ 是 | 工作目录 |
| Project Context | ~500-5,000+ | 否 | **变量最大的部分** |
| Silent Replies | ~120 | 否 | 静默回复规则 |
| Heartbeats | ~80 | 否 | 心跳规则 |
| Runtime | ~80 | ✅ 是 | 运行时元数据 |
| **总计** | **~2,000-8,000+** | — | **视配置而定** |

### 2.2 动态内容的 Token 影响

系统提示词中最大的变量是 **Project Context**（项目上下文文件）。这些文件（如 `AGENTS.md`、`SOUL.md`、`USER.md`）的内容会被完整注入到系统提示词中：

```typescript
// 上下文文件注入
if (contextFiles.length > 0) {
  lines.push("# Project Context", "");
  for (const file of contextFiles) {
    lines.push(`## ${file.path}`, "", file.content, "");
  }
}
```

以本项目为例，`AGENTS.md` 文件约有 **300+ 行**，注入后可能消耗 **3,000-5,000 tokens**。这意味着**每一次 API 调用**都会重复发送这些内容。

### 2.3 Prompt Mode 对 Token 的影响

OpenClaw 支持三种提示模式，以针对不同场景控制 Token 消耗：

```typescript
export type PromptMode = "full" | "minimal" | "none";
```

| 模式 | 适用场景 | 包含的模块 | Token 消耗 |
|------|---------|----------|----------|
| `full` | 主 Agent | 所有模块 | ~2,000-8,000+ |
| `minimal` | 子 Agent | 工具、安全、工作空间、沙箱、运行时 | ~800-1,500 |
| `none` | 最小化 | 仅身份声明 | ~20 |

```typescript
// "none" 模式：极致节省
if (promptMode === "none") {
  return "You are a personal assistant running inside OpenClaw.";
}
```

**关键洞察**：子 Agent（`minimal` 模式）通过裁剪 Skills、Memory、Messaging、Docs 等模块，可以节省约 **50-70%** 的系统提示词 Token。

---

## 三、消耗源二：工具定义（Tool Schema）

### 3.1 工具定义的 Token 开销

每个工具的 JSON Schema 定义会作为 API 请求的一部分发送给 LLM。工具定义包括：

- **工具名称** (`name`)
- **工具描述** (`description`)
- **参数 Schema** (`parameters`)

以 `memory_search` 工具为例：

```typescript
{
  name: "memory_search",
  description: "Mandatory recall step: semantically search MEMORY.md + memory/*.md ...",
  parameters: Type.Object({
    query: Type.String(),
    maxResults: Type.Optional(Type.Number()),
    minScore: Type.Optional(Type.Number()),
  }),
}
```

每个工具定义大约消耗 **100-300 tokens**。

### 3.2 核心工具列表

OpenClaw 内置了大量工具，**所有启用的工具定义都会在每次 API 调用中发送**：

| 工具名 | 描述 Token 估算 | Schema Token 估算 | 合计 |
|--------|---------------|------------------|------|
| read | ~30 | ~80 | ~110 |
| write | ~30 | ~100 | ~130 |
| edit | ~50 | ~150 | ~200 |
| apply_patch | ~40 | ~120 | ~160 |
| grep | ~40 | ~100 | ~140 |
| find | ~30 | ~80 | ~110 |
| ls | ~20 | ~60 | ~80 |
| exec | ~60 | ~200 | ~260 |
| process | ~40 | ~100 | ~140 |
| web_search | ~30 | ~80 | ~110 |
| web_fetch | ~40 | ~100 | ~140 |
| browser | ~30 | ~150 | ~180 |
| memory_search | ~60 | ~80 | ~140 |
| memory_get | ~50 | ~80 | ~130 |
| message | ~50 | ~200 | ~250 |
| session_status | ~60 | ~100 | ~160 |
| cron | ~80 | ~150 | ~230 |
| 其他工具 (约 5-8 个) | ~200-400 | ~400-800 | ~600-1200 |
| **总计 (全部启用)** | — | — | **~3,000-5,000** |

**关键洞察**：工具定义是一个**固定开销**，无论用户是否使用这些工具，它们都会占用输入 Token。这是 Agent 系统的"税"。

---

## 四、消耗源三：Agentic Loop（多轮工具调用循环）

### 4.1 Agentic Loop 的 Token 放大效应

这是 Agent 系统中 **Token 消耗最大的隐性成本**。当 LLM 决定调用工具时，会触发多轮 API 调用：

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     Agentic Loop 的 Token 放大效应                        │
└──────────────────────────────────────────────────────────────────────────┘

第 1 轮 API 调用:
  Input:  [System Prompt] + [Tool Defs] + [History] + [User Msg]
  Output: [Tool Call: read file "src/main.ts"]
  Token:  Input ~15,000 + Output ~100 = 15,100

第 2 轮 API 调用 (工具结果返回后):
  Input:  [System Prompt] + [Tool Defs] + [History] + [User Msg]
        + [Tool Call] + [Tool Result: file content ~500 lines]
  Output: [Tool Call: edit file "src/main.ts"]
  Token:  Input ~20,000 + Output ~200 = 20,200

第 3 轮 API 调用 (又一个工具结果):
  Input:  [System Prompt] + [Tool Defs] + [History] + [User Msg]
        + [Tool Call 1] + [Tool Result 1]
        + [Tool Call 2] + [Tool Result 2]
  Output: [Final Response: "文件已修改"]
  Token:  Input ~25,000 + Output ~100 = 25,100

总 Token 消耗: 15,100 + 20,200 + 25,100 = 60,400 tokens
```

### 4.2 累积消耗的数学模型

假设一次用户交互触发 `N` 轮工具调用：

```
Base = System Prompt + Tool Defs + History + User Message
ToolResult(i) = 第 i 个工具的结果大小

单次交互总 Input Token = Σ(i=1 to N+1) [Base + Σ(j=1 to i-1)(ToolCall(j) + ToolResult(j))]

简化为:
Total ≈ (N+1) × Base + N × (N+1) / 2 × AvgToolResult
```

**这是一个 O(N²) 的增长模式**！每多一轮工具调用，不仅要发送新的工具结果，还要**重新发送之前所有轮次的内容**。

| 工具调用轮数 (N) | Base=10K 时的总 Input Token | 每轮 ToolResult=2K 时 |
|-----------------|--------------------------|---------------------|
| 1 | 20,000 | 22,000 |
| 3 | 40,000 | 52,000 |
| 5 | 60,000 | 90,000 |
| 10 | 110,000 | 220,000 |
| 20 | 210,000 | 630,000 |

### 4.3 工具结果的 Token 消耗

不同工具返回的结果大小差异极大：

| 工具 | 典型返回大小 | Token 估算 |
|------|------------|----------|
| `ls` (列目录) | 500-2,000 chars | 125-500 |
| `grep` (搜索) | 1,000-10,000 chars | 250-2,500 |
| `read` (读文件) | 2,000-50,000 chars | 500-12,500 |
| `exec` (执行命令) | 100-20,000 chars | 25-5,000 |
| `web_fetch` (网页) | 5,000-100,000 chars | 1,250-25,000 |
| `web_search` (搜索) | 2,000-10,000 chars | 500-2,500 |
| `memory_search` (记忆) | 500-5,000 chars | 125-1,250 |

**`read` 和 `web_fetch` 是 Token 消耗的重灾区**，一个大文件可能一次消耗 10,000+ tokens。

---

## 五、消耗源四：对话历史累积

### 5.1 历史消息的滚雪球效应

OpenClaw 使用 JSONL 文件存储对话历史，**每次 API 调用都会发送完整的历史记录**（在裁剪/压缩之前）：

```
会话开始时:
  History = 0 tokens

第 1 轮后:
  History = User(1) + Assistant(1) = ~300 tokens

第 5 轮后:
  History = 5 × (User + Assistant + ToolCalls + ToolResults) = ~5,000 tokens

第 20 轮后:
  History = 20 × (User + Assistant + ToolCalls + ToolResults) = ~20,000-50,000 tokens

第 50 轮后 (长会话):
  History = 50 × (...) = ~50,000-150,000 tokens  ← 可能接近上下文窗口上限！
```

**这就是为什么 OpenClaw 需要 Context Pruning 和 Compaction 机制**。

### 5.2 历史轮次限制机制

**文件**: `src/agents/pi-embedded-runner/history.ts`

OpenClaw 提供了简单直接的历史轮次限制：

```typescript
export function limitHistoryTurns(
  messages: AgentMessage[],
  limit: number | undefined,
): AgentMessage[] {
  if (!limit || limit <= 0 || messages.length === 0) {
    return messages;
  }
  // 从后向前扫描，保留最后 N 个用户轮次
  let userCount = 0;
  let lastUserIndex = messages.length;
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === "user") {
      userCount++;
      if (userCount > limit) {
        return messages.slice(lastUserIndex);
      }
      lastUserIndex = i;
    }
  }
  return messages;
}
```

配置示例：

```typescript
// 通过渠道配置设置历史限制
config.channels.telegram.dmHistoryLimit = 50;   // 全局限制
config.channels.telegram.dms["user123"].historyLimit = 100; // 用户特定限制
```

**Token 节省效果**：如果限制为 50 轮，且平均每轮 1,000 tokens，则最大历史 Token 数被限制在 ~50,000 tokens，避免了无限增长。

---

## 六、消耗源五：记忆检索

### 6.1 记忆搜索的 Token 开销

**文件**: `src/agents/tools/memory-tool.ts`

当 Agent 决定使用 `memory_search` 工具时，会产生双重 Token 消耗：

1. **向量嵌入调用**：将查询文本转换为向量（通常使用独立的嵌入模型，消耗少量 Token）
2. **搜索结果注入**：搜索到的记忆片段作为工具结果注入到上下文中

```typescript
// memory_search 工具定义
{
  name: "memory_search",
  description: "Mandatory recall step: semantically search MEMORY.md + memory/*.md ...",
  execute: async (_toolCallId, params) => {
    const results = await manager.search(query, { maxResults, minScore });
    return jsonResult({
      results,       // 搜索到的记忆片段
      provider,      // 提供商信息
      model,         // 模型信息
    });
  },
}
```

**记忆搜索的 Token 成本**：

| 组成部分 | Token 消耗 |
|---------|----------|
| 工具调用请求 (LLM 输出) | ~50-100 |
| 嵌入模型调用 | ~20-50 (独立计费) |
| 搜索结果 (工具返回) | ~200-2,000 |
| **额外的 API 轮次** | 整个上下文重发一次 |

### 6.2 memory_get 的精准获取

OpenClaw 设计了 `memory_get` 工具来减少不必要的 Token 消耗：

```typescript
{
  name: "memory_get",
  description: "Safe snippet read from MEMORY.md, memory/*.md ... " +
    "use after memory_search to pull only the needed lines and keep context small.",
  parameters: {
    path: Type.String(),
    from: Type.Optional(Type.Number()),   // 起始行号
    lines: Type.Optional(Type.Number()),  // 读取行数
  },
}
```

**设计意图**：先用 `memory_search` 定位（返回摘要+行号），再用 `memory_get` 精准读取需要的几行。这比直接读取整个文件节省了大量 Token。

### 6.3 优化反思：两步记忆检索的 Token 浪费问题

#### 6.3.1 当前方案的调用流程（3 轮 LLM 调用）

当前 OpenClaw 的记忆检索设计为**两个独立的工具**，LLM 需要分步调用：

```
┌──────────────────────────────────────────────────────────────────────────┐
│                  当前方案：两步记忆检索的 Token 消耗                        │
└──────────────────────────────────────────────────────────────────────────┘

第 1 轮 API 调用: LLM 决定调用 memory_search
  Input:  [System Prompt] + [Tool Defs] + [History] + [User Msg]
  Output: [Tool Call: memory_search("之前的决定")]
  Token:  Input ~15,000 + Output ~80 = ~15,080

      ↓ 执行 memory_search，返回 snippet + 行号

第 2 轮 API 调用: LLM 看到搜索结果，决定调用 memory_get
  Input:  [System Prompt] + [Tool Defs] + [History] + [User Msg]
        + [Tool Call 1] + [Tool Result 1: search results]
  Output: [Tool Call: memory_get("memory/2024-01.md", from=42, lines=10)]
  Token:  Input ~16,500 + Output ~100 = ~16,600

      ↓ 执行 memory_get，返回精准内容

第 3 轮 API 调用: LLM 拿到记忆内容，生成最终回复
  Input:  [System Prompt] + [Tool Defs] + [History] + [User Msg]
        + [Tool Call 1] + [Tool Result 1]
        + [Tool Call 2] + [Tool Result 2: memory content]
  Output: [Final Response]
  Token:  Input ~17,500 + Output ~300 = ~17,800

────────────────────────────
记忆检索总 Token 消耗: ~49,480 tokens
其中因多轮调用而重复发送的 Base 开销: ~15,000 × 2 = ~30,000 tokens (浪费)
```

#### 6.3.2 核心问题：memory_search 已经包含了足够的信息

深入分析源码可以发现一个关键事实：

**`memory_search` 返回的结果已经包含了 snippet（代码片段）**，每个结果最多 700 个字符：

```typescript
// src/memory/manager.ts
const SNIPPET_MAX_CHARS = 700;  // ← 每个搜索结果的片段上限

// MemorySearchResult 的完整结构
export type MemorySearchResult = {
  path: string;        // 文件路径
  startLine: number;   // 起始行号
  endLine: number;     // 结束行号
  score: number;       // 相似度得分
  snippet: string;     // ← 已经包含了片段内容！最多 700 字符
  source: MemorySource; // 来源类型
};
```

而 `memory_get` 的 `readFile` 方法本质上只是一个简单的文件读取 + 行号切片：

```typescript
// src/memory/manager.ts - readFile 方法
async readFile(params: {
  relPath: string;
  from?: number;
  lines?: number;
}): Promise<{ text: string; path: string }> {
  // ... 路径校验 ...
  const content = await fs.readFile(absPath, "utf-8");
  if (!params.from && !params.lines) {
    return { text: content, path: relPath };  // 返回整个文件
  }
  const lines = content.split("\n");
  const start = Math.max(1, params.from ?? 1);
  const count = Math.max(1, params.lines ?? lines.length);
  const slice = lines.slice(start - 1, start - 1 + count);
  return { text: slice.join("\n"), path: relPath };  // 返回指定行范围
}
```

**这意味着**：`memory_get` 做的事情完全可以在 `memory_search` 的 execute 函数内部直接完成——拿到搜索结果后，立即读取完整的相关片段，一次性返回给 LLM。

#### 6.3.3 优化方案：合并为单步记忆检索

**核心思路**：在 `memory_search` 工具内部，拿到向量搜索结果后，自动调用 `readFile` 获取完整的上下文内容，直接返回最终可用的记忆信息。

```typescript
// 优化后的 memory_search 工具（伪代码）
{
  name: "memory_search",
  description: "Search and retrieve memory content in one step...",
  execute: async (_toolCallId, params) => {
    const query = readStringParam(params, "query", { required: true });
    const { manager } = await getMemorySearchManager({ cfg, agentId });

    // Step 1: 向量搜索（与现在相同）
    const searchResults = await manager.search(query, { maxResults, minScore });

    // Step 2: ✨ 自动获取完整内容（替代 LLM 手动调用 memory_get）
    const enrichedResults = await Promise.all(
      searchResults.map(async (result) => {
        // 如果 snippet 已经足够完整，直接使用
        if (result.snippet.length < SNIPPET_MAX_CHARS * 0.9) {
          return { ...result, fullText: result.snippet };
        }
        // 否则读取完整的上下文行
        try {
          const full = await manager.readFile({
            relPath: result.path,
            from: result.startLine,
            lines: result.endLine - result.startLine + 1,
          });
          return { ...result, fullText: full.text };
        } catch {
          return { ...result, fullText: result.snippet };
        }
      })
    );

    return jsonResult({ results: enrichedResults, provider, model });
  },
}
```

优化后的调用流程：

```
┌──────────────────────────────────────────────────────────────────────────┐
│                  优化方案：单步记忆检索的 Token 消耗                        │
└──────────────────────────────────────────────────────────────────────────┘

第 1 轮 API 调用: LLM 决定调用 memory_search
  Input:  [System Prompt] + [Tool Defs] + [History] + [User Msg]
  Output: [Tool Call: memory_search("之前的决定")]
  Token:  Input ~15,000 + Output ~80 = ~15,080

      ↓ memory_search 内部自动完成搜索 + 内容获取

第 2 轮 API 调用: LLM 直接拿到完整记忆内容，生成最终回复
  Input:  [System Prompt] + [Tool Defs] + [History] + [User Msg]
        + [Tool Call] + [Tool Result: 完整记忆内容]
  Output: [Final Response]
  Token:  Input ~17,000 + Output ~300 = ~17,300

────────────────────────────
记忆检索总 Token 消耗: ~32,380 tokens
节省: ~49,480 - ~32,380 = ~17,100 tokens (节省 ~34.6%)
```

#### 6.3.4 量化对比

| 指标 | 当前两步方案 | 优化单步方案 | 节省 |
|------|-------------|-------------|------|
| LLM API 调用次数 | 3 轮 | 2 轮 | **-1 轮** |
| Base 重复发送次数 | 3 次 | 2 次 | **-1 次** |
| 记忆检索总 Token | ~49,480 | ~32,380 | **~34.6%** |
| 工具结果总大小 | 搜索结果 + 精读内容 | 合并结果 | 略大（但避免了一轮 Base 重发） |
| 用户感知延迟 | 3 次 LLM 等待 | 2 次 LLM 等待 | **减少一次往返延迟** |

**以 Claude Opus 4.5 计价**：
- 当前方案: ~49,480 tokens × $15/1M ≈ $0.74
- 优化方案: ~32,380 tokens × $15/1M ≈ $0.49
- **每次记忆检索节省约 $0.25**

#### 6.3.5 为什么 OpenClaw 选择了两步方案？

尽管单步方案在 Token 效率上更优，OpenClaw 选择两步设计可能基于以下考量：

**1. 精准控制权交给 LLM**

两步方案让 LLM 在看到 `memory_search` 的摘要结果后，能够**智能判断**是否真的需要获取完整内容：

```
memory_search 返回 5 条结果
  → LLM 判断：只有第 2 条和第 4 条相关
  → 只对这 2 条调用 memory_get
  → 节省了读取另外 3 条的 Token

vs 单步方案：
  → 自动获取全部 5 条的完整内容
  → 可能有 3 条是不需要的
```

**2. snippet 在大多数场景已经足够**

`SNIPPET_MAX_CHARS = 700` 字符（约 175 tokens）的摘要片段，在很多场景下已经包含了 LLM 需要的信息。如果 snippet 足够，LLM 可以直接回答而**不调用 memory_get**：

```
实际调用模式（根据系统提示词暗示的流程）：
  约 60% 的情况：memory_search 的 snippet 已足够 → 2 轮调用
  约 40% 的情况：需要 memory_get 获取更多内容 → 3 轮调用
```

**3. 保持工具职责单一（SRP 原则）**

- `memory_search`：负责"搜索定位"（轻量级）
- `memory_get`：负责"精准获取"（可控读取量）

合并后的工具会变得更复杂，且默认行为的选择（读多少行？读几条结果？）需要更多参数配置。

**4. 避免不必要的文件 I/O**

如果 `memory_search` 自动为每条结果读取完整文件内容，在结果较多时会产生不必要的文件读取开销。虽然文件 I/O 相比 LLM API 调用的延迟可以忽略不计，但在资源受限环境下仍然是一个考量。

#### 6.3.6 折中方案建议

一种更优雅的折中方案是：**增大 `SNIPPET_MAX_CHARS` 的值，减少 `memory_get` 的调用概率**。

```typescript
// 当前值
const SNIPPET_MAX_CHARS = 700;    // 约 175 tokens/条结果

// 建议调整为
const SNIPPET_MAX_CHARS = 2000;   // 约 500 tokens/条结果
```

**效果分析**：

| 方案 | 搜索结果大小 (5 条) | 需要 memory_get 的概率 | 期望总 Token |
|------|-------------------|----------------------|-------------|
| 当前 (700 chars) | ~875 tokens | ~40% | ~42,000 |
| 增大 (2000 chars) | ~2,500 tokens | ~10% | ~35,000 |
| 单步合并 | ~2,500 tokens | 0% | ~32,380 |

增大 snippet 是一个**无需改变架构、兼容性最好**的优化方式，可以在保留两步灵活性的同时，大幅减少 `memory_get` 的调用频率。

---

## 七、消耗源六：Compaction 压缩机制本身

### 7.1 压缩的悖论：花费 Token 来节省 Token

Compaction（对话历史压缩）是 OpenClaw 处理长会话的核心机制，但**压缩本身需要消耗大量 Token**：

```
┌────────────────────────────────────────────────────────────────────┐
│                Compaction 的 Token 消耗结构                          │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  触发: 上下文接近/超过模型的 Context Window 限制                      │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Step 1: 分块 (splitMessagesByTokenShare)                   │    │
│  │  将历史消息按 Token 均分为 2 份                               │    │
│  │  Token 消耗: 0 (纯计算)                                     │    │
│  └────────────────────────────────────────────────────────────┘    │
│                         │                                          │
│                         ▼                                          │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Step 2: 分别摘要 (summarizeWithFallback)                   │    │
│  │  对每个分块调用 LLM 生成摘要                                 │    │
│  │  Token 消耗: 每块 Input ~50K + Output ~2K                   │    │
│  │  总计: 2 × (50K + 2K) = ~104K tokens ⚠️                    │    │
│  └────────────────────────────────────────────────────────────┘    │
│                         │                                          │
│                         ▼                                          │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Step 3: 合并摘要 (MERGE_SUMMARIES_INSTRUCTIONS)            │    │
│  │  将分块摘要合并为最终摘要                                     │    │
│  │  Token 消耗: Input ~4K + Output ~2K = ~6K tokens            │    │
│  └────────────────────────────────────────────────────────────┘    │
│                         │                                          │
│                         ▼                                          │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Step 4: 可能的降级处理 (pruneHistoryForContextShare)        │    │
│  │  如果新内容超过历史预算(50%)，裁剪旧消息再摘要               │    │
│  │  Token 消耗: 额外 ~50-100K tokens                           │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                    │
│  📊 单次 Compaction 总消耗: ~110K - 210K tokens                    │
│  💰 按 Claude Opus 4.5 计: ~$1.65 - $3.15                         │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### 7.2 分阶段摘要的额外 API 调用

**文件**: `src/agents/compaction.ts`

```typescript
export async function summarizeInStages(params: {
  messages: AgentMessage[];
  model: NonNullable<ExtensionContext["model"]>;
  apiKey: string;
  signal: AbortSignal;
  reserveTokens: number;
  maxChunkTokens: number;
  contextWindow: number;
  ...
}): Promise<string> {
  // 1. 分块
  const splits = splitMessagesByTokenShare(messages, parts);

  // 2. 对每个分块生成摘要（每个都是一次独立的 API 调用！）
  for (const chunk of splits) {
    partialSummaries.push(
      await summarizeWithFallback({ ...params, messages: chunk })
    );
  }

  // 3. 合并摘要（又一次 API 调用！）
  return summarizeWithFallback({
    ...params,
    messages: summaryMessages,
    customInstructions: mergeInstructions,
  });
}
```

**Compaction Safeguard 的额外消耗**：

```typescript
// src/agents/pi-extensions/compaction-safeguard.ts
api.on("session_before_compact", async (event, ctx) => {
  // 可能需要先摘要被裁剪的消息
  if (pruned.droppedMessagesList.length > 0) {
    droppedSummary = await summarizeInStages({...});  // 额外的 API 调用
  }
  // 主摘要
  const historySummary = await summarizeInStages({...});  // 又一轮 API 调用
  // 如果是分割轮次，还要摘要前缀
  if (preparation.isSplitTurn) {
    const prefixSummary = await summarizeInStages({...});  // 再一轮！
  }
});
```

**最坏情况下，一次 Compaction 可能触发 5-7 次 LLM API 调用**。

---

## 八、Token 消耗量化建模

### 8.1 单次交互的 Token 构成公式

```
单次交互总 Token = (N+1) × Base + ToolOverhead + OutputTokens

其中:
  Base = SystemPrompt + ToolDefs + History + BootstrapFiles
  N = 工具调用轮数
  ToolOverhead = Σ(i=1 to N) [ToolCall(i) + ToolResult(i)] × 重复发送因子
  OutputTokens = FinalReply + Σ(ToolCallOutputs)
```

### 8.2 典型场景消耗估算

**场景 1：简单问答（无工具调用）**

```
System Prompt:    3,000 tokens
Tool Definitions: 3,500 tokens
History (5 轮):   3,000 tokens
User Message:       100 tokens
────────────────────────────
Input Total:      9,600 tokens
Output:             200 tokens
────────────────────────────
💰 总计:          ~9,800 tokens (~$0.16)
```

**场景 2：读取文件并修改（3 轮工具调用）**

```
API Call 1: (LLM 决定读文件)
  Input:  9,600 tokens
  Output:   100 tokens (tool call: read)

API Call 2: (读取结果返回，LLM 决定编辑)
  Input:  9,600 + 100 + 3,000 = 12,700 tokens
  Output:   300 tokens (tool call: edit)

API Call 3: (编辑结果返回，LLM 生成回复)
  Input:  12,700 + 300 + 200 = 13,200 tokens
  Output:   200 tokens (final reply)

────────────────────────────
Input Total:  35,500 tokens
Output Total:    600 tokens
────────────────────────────
💰 总计: ~36,100 tokens (~$0.58)
```

**场景 3：复杂任务（10 轮工具调用，长历史）**

```
Base:                 30,000 tokens (含 20K 历史)
工具结果平均大小:       3,000 tokens/轮
工具调用次数:          10 轮

Input: 11 × 30,000 + 10×11/2 × 3,000 = 330,000 + 165,000 = 495,000 tokens
Output: ~3,000 tokens

────────────────────────────
💰 总计: ~498,000 tokens (~$7.72)
```

### 8.3 长会话的累积消耗

假设一个持续 50 轮的会话，每轮平均 3 次工具调用：

```
轮次 1-10:   History 小，平均每轮 ~30K tokens → ~300K
轮次 11-20:  History 增长，平均每轮 ~60K tokens → ~600K
轮次 21-30:  Context Pruning 开始生效，平均每轮 ~80K tokens → ~800K
轮次 31-40:  Compaction 触发 2-3 次，额外 ~500K tokens → ~1,300K
轮次 41-50:  稳态运行，平均每轮 ~70K tokens → ~700K

50 轮会话总消耗: ~3.7M tokens
💰 按 Claude Opus 4.5: ~$55 (无缓存) 或 ~$15 (高缓存命中率)
```

---

## 九、Token 估算与追踪机制

### 9.1 Token 估算方法

OpenClaw 使用基于字符数的近似估算，而非精确的 Tokenizer：

**文件**: `src/agents/pi-extensions/context-pruning/pruner.ts`

```typescript
const CHARS_PER_TOKEN_ESTIMATE = 4;        // 每个 Token 约 4 个字符
const IMAGE_CHAR_ESTIMATE = 8_000;         // 图片按 8000 字符估算
```

**文件**: `src/agents/compaction.ts`

```typescript
export const SAFETY_MARGIN = 1.2;  // 20% 安全边界，补偿估算不精确

export function estimateMessagesTokens(messages: AgentMessage[]): number {
  return messages.reduce((sum, message) => sum + estimateTokens(message), 0);
}
```

**消息字符估算逻辑**：

```typescript
function estimateMessageChars(message: AgentMessage): number {
  if (message.role === "user") {
    // 文本: 直接取字符长度
    // 图片: 每张 8,000 字符
  }
  if (message.role === "assistant") {
    // text: 字符长度
    // thinking: 字符长度
    // toolCall: JSON.stringify(arguments).length
  }
  if (message.role === "toolResult") {
    // text: 字符长度
    // image: 每张 8,000 字符
  }
  return 256;  // 未知类型的默认值
}
```

**估算精度分析**：

| 语言/内容类型 | 实际 chars/token | 估算误差 |
|-------------|-----------------|---------|
| 英文文本 | ~4.0 | ~0% |
| 中文文本 | ~1.5-2.0 | **+50-100% 高估** |
| 代码 | ~3.0-3.5 | ~15% |
| JSON | ~3.5-4.0 | ~0-10% |
| 图片 | 不确定 | 依赖模型实现 |

**关键洞察**：对于中文内容，`CHARS_PER_TOKEN_ESTIMATE = 4` 会显著高估字符到 Token 的比率，这意味着裁剪机制会**比预期更早触发**（在某种程度上是保守安全的）。

### 9.2 Usage 追踪与标准化

**文件**: `src/agents/usage.ts`

OpenClaw 实现了一个统一的 Usage 标准化层，兼容多个 LLM 提供商的不同命名：

```typescript
export type UsageLike = {
  // Anthropic 风格
  input?: number;
  output?: number;
  cacheRead?: number;
  cacheWrite?: number;

  // OpenAI 风格
  inputTokens?: number;
  outputTokens?: number;
  promptTokens?: number;
  completionTokens?: number;

  // API 响应风格 (snake_case)
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
  total_tokens?: number;
};
```

标准化后的输出：

```typescript
export type NormalizedUsage = {
  input?: number;      // 输入 Token 数
  output?: number;     // 输出 Token 数
  cacheRead?: number;  // 缓存读取 Token 数
  cacheWrite?: number; // 缓存写入 Token 数
  total?: number;      // 总 Token 数
};
```

**辅助函数 `derivePromptTokens`**：

```typescript
export function derivePromptTokens(usage?: {
  input?: number;
  cacheRead?: number;
  cacheWrite?: number;
}): number | undefined {
  const sum = (usage.input ?? 0) + (usage.cacheRead ?? 0) + (usage.cacheWrite ?? 0);
  return sum > 0 ? sum : undefined;
}
```

这个函数计算**实际的 Prompt Token 总量**（包括缓存命中和缓存写入的部分），用于了解真实的上下文大小。

### 9.3 Cache Trace 诊断

**文件**: `src/agents/cache-trace.ts`

OpenClaw 提供了专门的缓存跟踪诊断工具：

```typescript
export type CacheTraceStage =
  | "session:loaded"     // 会话加载
  | "session:sanitized"  // 会话清理后
  | "session:limited"    // 历史限制后
  | "prompt:before"      // 发送前
  | "prompt:images"      // 图片处理
  | "stream:context"     // 流式上下文
  | "session:after";     // 会话结束后
```

**启用方式**：

```bash
# 通过环境变量启用
OPENCLAW_CACHE_TRACE=1

# 或通过配置文件
diagnostics:
  cacheTrace:
    enabled: true
    filePath: "~/.openclaw/logs/cache-trace.jsonl"
    includeMessages: true
    includePrompt: true
    includeSystem: true
```

诊断数据包括每次 API 调用的：
- 消息数量和角色分布
- 系统提示词的 SHA-256 摘要
- 消息内容的指纹（用于判断缓存是否命中）
- 完整的上下文快照（可选）

---

## 十、现有优化机制分析

### 10.1 Context Pruning（上下文裁剪）

**文件**: `src/agents/pi-extensions/context-pruning/`

这是 OpenClaw 的**实时 Token 优化引擎**，在每次 API 调用前对工具结果进行裁剪。

**核心配置参数**：

```typescript
export const DEFAULT_CONTEXT_PRUNING_SETTINGS: EffectiveContextPruningSettings = {
  mode: "cache-ttl",
  ttlMs: 5 * 60 * 1000,           // 5 分钟 TTL
  keepLastAssistants: 3,           // 保护最后 3 个 assistant 回复
  softTrimRatio: 0.3,             // 占 30% 上下文时触发软裁剪
  hardClearRatio: 0.5,            // 占 50% 上下文时触发硬清除
  minPrunableToolChars: 50_000,   // 最小可裁剪字符数
  softTrim: {
    maxChars: 4_000,              // 超过 4000 字符触发
    headChars: 1_500,             // 保留开头 1500 字符
    tailChars: 1_500,             // 保留结尾 1500 字符
  },
  hardClear: {
    enabled: true,
    placeholder: "[Old tool result content cleared]",
  },
};
```

**两级裁剪策略详解**：

```
上下文占用比例 (ratio = totalChars / charWindow)
              │
              ▼
   ratio < 0.3 ──────────────→ 不裁剪 (Token 充裕)
              │
              ▼
  0.3 ≤ ratio < 0.5 ─────────→ 软裁剪 (Soft Trim)
              │                  • 保留工具结果的头 1500 + 尾 1500 字符
              │                  • 中间内容标记为 "..."
              │                  • 典型节省: 50-80% 单条工具结果
              ▼
    ratio ≥ 0.5 ─────────────→ 硬清除 (Hard Clear)
                                 • 替换为 "[Old tool result content cleared]"
                                 • 典型节省: 95%+ 单条工具结果

保护规则:
  ✅ 保护最后 3 个 assistant 回复关联的工具结果
  ✅ 保护首个 user 消息之前的所有内容 (bootstrap files)
  ✅ 跳过包含图片的工具结果
```

**Token 节省效果估算**：

| 场景 | 无裁剪 | 软裁剪后 | 硬清除后 | 节省比例 |
|------|--------|---------|---------|---------|
| 读取 500 行文件 | ~5,000 tokens | ~750 tokens | ~10 tokens | 85-99% |
| exec 长输出 | ~3,000 tokens | ~750 tokens | ~10 tokens | 75-99% |
| web_fetch 网页 | ~10,000 tokens | ~750 tokens | ~10 tokens | 92-99% |

### 10.2 Compaction Safeguard（压缩安全机制）

**文件**: `src/agents/pi-extensions/compaction-safeguard.ts`

当上下文即将溢出时，Compaction 机制通过生成摘要来压缩历史：

```typescript
api.on("session_before_compact", async (event, ctx) => {
  // 1. 计算自适应分块比例
  const adaptiveRatio = computeAdaptiveChunkRatio(allMessages, contextWindowTokens);
  // 当消息较大时，使用更小的分块避免超出模型限制
  // 范围: 0.15 (MIN_CHUNK_RATIO) ~ 0.4 (BASE_CHUNK_RATIO)

  // 2. 裁剪超量历史
  if (newContentTokens > maxHistoryTokens) {
    const pruned = pruneHistoryForContextShare({
      messages: messagesToSummarize,
      maxContextTokens: contextWindowTokens,
      maxHistoryShare: 0.5,  // 历史最多占 50%
    });
  }

  // 3. 分阶段摘要
  const historySummary = await summarizeInStages({...});

  // 4. 附加文件操作和工具失败信息
  summary += toolFailureSection;
  summary += fileOpsSummary;
});
```

**关键常量的 Token 含义**：

```typescript
BASE_CHUNK_RATIO = 0.4;     // 每个分块最多占 40% 上下文 = 80K tokens (200K 窗口)
MIN_CHUNK_RATIO = 0.15;     // 最小分块 = 30K tokens
SAFETY_MARGIN = 1.2;        // 20% 安全边界
maxHistoryShare = 0.5;       // 历史压缩后最多占 50% 上下文 = 100K tokens
```

### 10.3 上下文窗口保护

**文件**: `src/agents/context-window-guard.ts`

```typescript
CONTEXT_WINDOW_HARD_MIN_TOKENS = 16_000;    // 低于此值直接拒绝使用该模型
CONTEXT_WINDOW_WARN_BELOW_TOKENS = 32_000;  // 低于此值发出警告
```

**上下文窗口解析优先级**：

```
1. modelsConfig (用户在配置中指定的上下文大小)
2. model metadata (模型自带的上下文大小)
3. agentContextTokens (Agent 配置的上下文上限)
4. default (默认值: 200,000)
```

```typescript
export function resolveContextWindowInfo(params: {
  cfg, provider, modelId, modelContextWindow, defaultTokens
}): ContextWindowInfo {
  // 1. 优先使用用户配置的 contextWindow
  const fromModelsConfig = findModelConfig(cfg, provider, modelId)?.contextWindow;
  // 2. 其次使用模型元数据
  const fromModel = params.modelContextWindow;
  // 3. 如果 agentContextTokens 更小，使用它作为上限
  const capTokens = cfg?.agents?.defaults?.contextTokens;
  if (capTokens && capTokens < baseInfo.tokens) {
    return { tokens: capTokens, source: "agentContextTokens" };
  }
}
```

### 10.4 Prompt Caching（提示缓存）

**文件**: `src/agents/pi-embedded-runner/extra-params.ts`

OpenClaw 支持 Anthropic 的 Prompt Caching 机制，这是**最有效的 Token 成本优化**：

```typescript
type CacheRetention = "none" | "short" | "long";

function resolveCacheRetention(
  extraParams: Record<string, unknown> | undefined,
  provider: string,
): CacheRetention | undefined {
  if (provider !== "anthropic") return undefined;  // 仅 Anthropic 支持

  // 新配置: cacheRetention
  if (newVal === "short" || newVal === "long") return newVal;

  // 旧配置兼容: cacheControlTtl
  if (legacy === "5m") return "short";   // 5 分钟缓存
  if (legacy === "1h") return "long";    // 1 小时缓存
}
```

**Prompt Caching 的 Token 成本影响**：

```
无缓存:
  200K input tokens × $15/1M = $3.00/次

缓存命中 (假设 90% 命中率):
  20K 新 tokens × $15/1M + 180K 缓存 tokens × $1.5/1M = $0.30 + $0.27 = $0.57/次

节省: $3.00 - $0.57 = $2.43/次 (81% 成本节省!)
```

**缓存命中的前提条件**：
- 系统提示词保持不变 ← 模块化设计保证了这一点
- 历史消息前缀保持不变 ← 只有最新消息变化
- 使用相同的模型 ← 通常满足

### 10.5 历史轮次限制

**文件**: `src/agents/pi-embedded-runner/history.ts`

这是最粗粒度但最直接的优化——直接丢弃旧轮次：

```typescript
export function limitHistoryTurns(
  messages: AgentMessage[],
  limit: number | undefined,
): AgentMessage[] {
  // 保留最后 N 个用户轮次（及其关联的 assistant 回复和工具调用）
  // 超出的部分直接丢弃（不生成摘要）
}
```

**成本-质量权衡**：

| 限制 | Token 上限 | 记忆损失 | 适用场景 |
|------|----------|---------|---------|
| 无限制 | ~200K | 无 | 需要完整上下文的任务 |
| 100 轮 | ~100K | 低 | 长期运行的助手 |
| 50 轮 | ~50K | 中 | 日常对话 |
| 20 轮 | ~20K | 高 | 成本敏感场景 |
| 10 轮 | ~10K | 很高 | 极低成本需求 |

---

## 十一、潜在优化方向

### 11.1 已实现的优化总结

| 优化机制 | 节省效果 | 副作用 |
|---------|---------|--------|
| Context Pruning (软裁剪) | ~50-80% 旧工具结果 | 丢失中间细节 |
| Context Pruning (硬清除) | ~95%+ 旧工具结果 | 完全丢失旧工具结果 |
| Compaction (摘要压缩) | ~70-90% 旧历史 | 需要额外 API 调用; 摘要可能丢失细节 |
| History Limit (轮次限制) | 防止无限增长 | 丢失旧对话上下文 |
| Prompt Caching | ~80% 输入成本 | 仅 Anthropic 支持; 需保持前缀稳定 |
| Prompt Mode (minimal/none) | ~50-70% 系统提示词 | 子 Agent 功能受限 |
| Bootstrap 保护 | 保证关键文件不被裁剪 | 占用固定 Token |

### 11.2 可探索的优化方向

**1. 工具定义的按需加载**

当前所有工具定义在每次调用时全部发送。可以根据对话上下文动态选择相关工具子集：

```
当前: 每次发送 ~20 个工具定义 = ~4,000 tokens
优化: 根据意图预判只发送 5-8 个 = ~1,500 tokens
节省: ~2,500 tokens/次
```

**2. 系统提示词压缩**

- 使用更简洁的指令表述
- 将不常用的规则移到按需加载的 Skills 中
- 根据渠道类型动态裁剪不相关的 Section

**3. 更精确的 Token 估算**

当前使用 `CHARS_PER_TOKEN_ESTIMATE = 4` 的粗略估算，可以：
- 针对不同语言使用不同系数
- 使用快速 Tokenizer (如 tiktoken) 进行精确计数
- 对估算误差进行自适应校正

**4. 增量上下文发送**

理论上，如果 LLM API 支持增量更新（而非每次发送完整上下文），可以极大减少 Token 消耗。目前的 API 设计要求每次都发送完整上下文。

**5. 智能工具结果压缩**

不是简单的头尾截断，而是使用轻量级模型对工具结果进行语义压缩，保留关键信息。

**6. 多级缓存策略**

- L1: Prompt Cache (API 级别，已实现)
- L2: 语义缓存 (相似查询复用)
- L3: 工具结果缓存 (相同输入复用)

---

## 十二、Agent 系统的 Token "原罪"

> 前面十一章我们深入剖析了 OpenClaw 的 Token 消耗来源与优化策略。但退一步来看，**烧 Token 不是 OpenClaw 的 Bug，而是所有 Agent 系统的"原罪"。** 本章从 OpenClaw 这一个例出发，反思 Agent 系统在 Token 消耗上的共性问题，以及未来可能的破局方向。

### 12.1 LLM 无状态——每轮调用必须重传完整上下文

这是所有 Agent 系统烧 Token 的**根本原因**。

LLM 本质上是一个**无记忆的纯函数**：

```
LLM(完整上下文) → 回复
```

不同于传统服务器可以用 Session/Cookie 保持状态，LLM 的每一次 API 调用都必须重新发送：

```
┌─────────────────────────────────────────────────────────────────────────┐
│                   每轮 API 调用的固定 "Base 成本"                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   System Prompt (系统指令)        ~3,000-8,000 tokens    ← 每次都发     │
│   Tool Definitions (工具定义)     ~3,000-5,000 tokens    ← 每次都发     │
│   Bootstrap Files (上下文文件)    ~2,000-5,000 tokens    ← 每次都发     │
│   对话历史 (所有历史消息)          ~1,000-∞ tokens        ← 持续增长     │
│                                                                         │
│   合计 Base 成本: ~10,000-20,000+ tokens / 轮                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**这不是 OpenClaw 的问题，而是 LLM API 的工作方式决定的。** 无论你用的是 LangChain、AutoGPT、CrewAI、Dify 还是 OpenClaw，只要底层调用的是 LLM API，这个 Base 成本就跑不掉。

**类比**：想象你每次打电话都要先把整本通讯录念一遍，然后再说正事——这就是 LLM 当前的工作方式。

### 12.2 Agentic Loop——Token 乘数效应

这是 Agent 系统区别于普通 ChatBot 的**最烧钱的特性**。

```
┌─────────────────────────────────────────────────────────────────────────┐
│            普通 ChatBot vs Agent 系统的 Token 消耗对比                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  普通 ChatBot:                                                          │
│    用户问 → LLM 答                                                      │
│    = 1 轮 API 调用                                                      │
│    ≈ 15,000 tokens                                                      │
│                                                                         │
│  Agent 系统:                                                            │
│    用户问 → LLM 思考 → 调工具A → 看结果 → 调工具B → 看结果 → 最终回答     │
│    = 3-5 轮 API 调用                                                    │
│    ≈ 50,000-80,000 tokens                                               │
│                                                                         │
│  复杂 Agent 任务:                                                       │
│    搜索记忆 → 读取文件 → 分析内容 → 搜索网页 → 综合推理 → 回答            │
│    = 5-10 轮 API 调用                                                   │
│    ≈ 100,000-200,000 tokens                                             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**关键洞察**：每多一轮工具调用，不仅增加了该轮本身的成本，还要**重新发送之前所有轮次的累积结果**。这就是 Token 消耗呈 O(N²) 增长的原因：

```
第 1 轮: Base                              = 15,000 tokens
第 2 轮: Base + 第1轮结果                    = 16,500 tokens
第 3 轮: Base + 第1轮结果 + 第2轮结果         = 18,000 tokens
第 4 轮: Base + 第1轮 + 第2轮 + 第3轮结果     = 19,500 tokens
第 5 轮: Base + 第1轮 + 第2轮 + 第3轮 + 第4轮  = 21,000 tokens
─────────────────────────────────────────────────
5 轮总消耗: 90,000 tokens（而非 5 × 15,000 = 75,000）
```

这就是为什么"让 Agent 帮你搜一下"看起来是一个简单操作，背后却消耗了大量 Token。

### 12.3 对话历史——滚雪球效应

所有多轮对话系统都面临的问题：**历史越长，每轮成本越高**。

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    对话历史的滚雪球增长曲线                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Token ▲                                                                │
│  消耗  │                                              ╱ 无优化          │
│        │                                           ╱                    │
│  100K  │                                        ╱                       │
│        │                                     ╱                          │
│   80K  │                                  ╱                             │
│        │                               ╱     ╱ 有 Compaction           │
│   60K  │                            ╱     ╱                             │
│        │                         ╱     ╱                                │
│   40K  │                      ╱     ╱                                   │
│        │                   ╱     ╱                                      │
│   20K  │                ╱  ╱╱                                           │
│        │          ╱╱╱╱╱                                                 │
│   15K  │───╱╱╱╱                                                         │
│        └──────────────────────────────────────────────────▶ 对话轮次     │
│            1    5    10   15   20   25   30   35   40                   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

- **不做任何处理**：Token 线性增长，20 轮后轻松突破 100K
- **有 Compaction**：增长到阈值后压缩回落，但压缩本身也消耗 Token
- **无论哪种方式**：长对话必然比短对话贵——这是所有 Agent 的共性

### 12.4 工具生态——越强大越昂贵

Agent 的核心价值在于**能使用工具**，但工具越多、越强大，Token 消耗也越高：

| Agent 能力 | 代价 |
|-----------|------|
| 能搜索记忆 | +2 个工具定义 + 多轮检索调用 |
| 能读写文件 | +2 个工具定义 + 文件内容进入上下文 |
| 能搜索网页 | +1 个工具定义 + 网页内容（往往很大） |
| 能执行代码 | +1 个工具定义 + 代码 + 执行结果 |
| 能操作数据库 | +1 个工具定义 + SQL + 查询结果 |

**每个工具定义**约占 200-500 tokens，10 个工具就是 2,000-5,000 tokens 的**固定税**。这就是为什么功能全面的 Agent（如 OpenClaw、Claude Code）比简单的 ChatBot 贵得多——**你在为"能力"付费**。

### 12.5 OpenClaw 在行业中的优化水平

尽管烧 Token 是 Agent 的通病，各框架的优化水平差异很大。以下是 OpenClaw 与其他主流框架的对比：

```
┌─────────────────────────────────────────────────────────────────────────┐
│               Agent 框架 Token 优化能力对比                               │
├──────────────┬──────────┬──────────┬──────────┬──────────┬──────────────┤
│   优化手段    │ OpenClaw │ LangChain│  AutoGPT │  CrewAI  │ 简单 Agent   │
├──────────────┼──────────┼──────────┼──────────┼──────────┼──────────────┤
│ Prompt Cache │   ✅     │   ⚠️    │    ❌    │   ❌     │     ❌       │
│ Compaction   │   ✅     │   ⚠️    │    ⚠️   │   ❌     │     ❌       │
│ 上下文裁剪    │   ✅     │   ⚠️    │    ⚠️   │   ⚠️    │     ❌       │
│ 工具结果压缩  │   ✅     │   ❌    │    ❌    │   ❌     │     ❌       │
│ 历史轮次限制  │   ✅     │   ✅    │    ⚠️   │   ✅     │     ❌       │
│ Token 追踪   │   ✅     │   ✅    │    ⚠️   │   ⚠️    │     ❌       │
│ 记忆 snippet │   ✅     │   ❌    │    ❌    │   ❌     │     ❌       │
├──────────────┼──────────┼──────────┼──────────┼──────────┼──────────────┤
│ 综合优化程度  │  ⭐⭐⭐⭐ │  ⭐⭐⭐  │  ⭐⭐    │  ⭐⭐    │    ⭐        │
└──────────────┴──────────┴──────────┴──────────┴──────────┴──────────────┘

✅ = 已实现且较完善   ⚠️ = 部分实现或较简单   ❌ = 未实现
```

**OpenClaw 在 Token 优化方面处于行业前列**，尤其是 Prompt Caching + Compaction + 上下文裁剪的组合，形成了一套完整的 Token 生命周期管理体系。但即使如此，它也无法从根本上消除 Agent 架构带来的 Token 消耗。

### 12.6 未来破局方向

要从根本上解决 Agent 系统的 Token 消耗问题，需要 LLM 基础设施层面的架构变革：

**1. 有状态推理（Stateful Inference）**

```
当前:  Client → [完整上下文 50K tokens] → LLM API → 回复
未来:  Client → [增量消息 200 tokens]   → LLM API(session_id) → 回复
                                          ↑ 服务端维持状态
```

如果 LLM 服务端能像传统 Web Session 一样维持对话状态，每次只需要发送增量消息，Token 消耗将降低一个数量级。目前 Google Gemini 的 Context Caching 和 Anthropic 的 Prompt Caching 已经在朝这个方向迈进，但离真正的有状态推理还有距离。

**2. 增量上下文协议（Delta Context Protocol）**

```
当前:  每轮发送 [System + Tools + 全部历史 + 新消息]  = 50K tokens
未来:  首轮发送 [System + Tools + 首条消息]            = 15K tokens
       后续发送 [session_ref + 增量 diff]              = 500 tokens
```

只传输与上一轮相比的**变化部分**，而非每次都重传完整上下文。

**3. 模型效率提升与成本下降**

```
2023:  GPT-4     输入 $30/1M tokens
2024:  GPT-4o    输入 $5/1M tokens      ← 6x 降价
2024:  Claude 3.5 Sonnet 输入 $3/1M tokens
2025:  预期进一步降低...
```

随着模型推理效率提升和硬件成本下降，即使 Token 消耗量不变，**绝对成本**也会持续降低。

**4. 更高效的上下文表示**

- **结构化压缩**：将对话历史压缩为更紧凑的中间表示
- **知识蒸馏缓存**：将常用工具结果和记忆预编码为更短的 Token 序列
- **分层注意力**：让 LLM 对不同部分的上下文使用不同精度的注意力

**核心结论**：

> Agent 系统的 Token 高消耗是当前 LLM 架构的**结构性限制**，不是任何单一框架的设计缺陷。OpenClaw 已经在应用层做了大量优化，但真正的突破需要等待 LLM 基础设施的演进。在此之前，**精细的 Token 管理工程**（如 OpenClaw 所展示的）是唯一的应对策略。

---

## 十三、总结与关键数字

### 关键常量速查表

| 常量 | 值 | 来源文件 | 作用 |
|------|-----|---------|------|
| `DEFAULT_CONTEXT_TOKENS` | 200,000 | `defaults.ts` | 默认上下文窗口大小 |
| `CONTEXT_WINDOW_HARD_MIN_TOKENS` | 16,000 | `context-window-guard.ts` | 模型最小上下文要求 |
| `CONTEXT_WINDOW_WARN_BELOW_TOKENS` | 32,000 | `context-window-guard.ts` | 低上下文警告阈值 |
| `CHARS_PER_TOKEN_ESTIMATE` | 4 | `pruner.ts` | 字符到 Token 的估算比例 |
| `IMAGE_CHAR_ESTIMATE` | 8,000 | `pruner.ts` | 图片的字符等价估算 |
| `BASE_CHUNK_RATIO` | 0.4 | `compaction.ts` | 压缩分块基础比例 |
| `MIN_CHUNK_RATIO` | 0.15 | `compaction.ts` | 压缩分块最小比例 |
| `SAFETY_MARGIN` | 1.2 | `compaction.ts` | Token 估算安全边界(20%) |
| `softTrimRatio` | 0.3 | `settings.ts` | 软裁剪触发阈值(30%) |
| `hardClearRatio` | 0.5 | `settings.ts` | 硬清除触发阈值(50%) |
| `maxHistoryShare` | 0.5 | `compaction-safeguard.ts` | 历史最大占比(50%) |
| `keepLastAssistants` | 3 | `settings.ts` | 保护的最近 assistant 数 |
| `softTrim.maxChars` | 4,000 | `settings.ts` | 软裁剪字符阈值 |
| `softTrim.headChars` | 1,500 | `settings.ts` | 软裁剪保留头部字符 |
| `softTrim.tailChars` | 1,500 | `settings.ts` | 软裁剪保留尾部字符 |
| `minPrunableToolChars` | 50,000 | `settings.ts` | 最小可裁剪字符数 |
| `DEFAULT_PARTS` | 2 | `compaction.ts` | 默认分块数 |

### Token 消耗层级图谱

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Token 消耗从高到低排序                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  🔴 超高消耗 (>100K tokens/次)                                           │
│     • Compaction 压缩 (多次 LLM 调用)                                    │
│     • 长会话的累积历史 (未压缩时)                                         │
│                                                                         │
│  🟠 高消耗 (10K-100K tokens/次)                                          │
│     • Agentic Loop 多轮调用 (累积效应)                                    │
│     • 大文件读取/网页抓取 (工具结果)                                      │
│                                                                         │
│  🟡 中等消耗 (1K-10K tokens/次)                                          │
│     • System Prompt (每次调用)                                            │
│     • Tool Definitions (每次调用)                                        │
│     • Bootstrap Files (AGENTS.md 等)                                     │
│                                                                         │
│  🟢 低消耗 (<1K tokens/次)                                               │
│     • 用户消息                                                           │
│     • 记忆搜索结果                                                       │
│     • 助手最终回复                                                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 核心结论

1. **烧 Token 是 Agent 系统的"原罪"，不是 OpenClaw 的 Bug**：LLM 无状态 + 按 Token 计费的架构决定了所有 Agent 系统都逃不掉高消耗。

2. **Agentic Loop 是 Token 消耗的最大放大器**：N 轮工具调用导致 O(N²) 的 Token 增长，这是 Agent 系统与普通 ChatBot 最本质的区别。

3. **历史累积是长期成本的主要驱动力**：没有 Pruning/Compaction，Token 消耗会无限增长直到撑爆上下文窗口。

4. **Compaction 是必要的"投资"**：虽然单次压缩消耗 ~100-200K tokens，但它使得长会话能够持续运行，是"花小钱省大钱"。

5. **Prompt Caching 是最高效的优化**：高达 80%+ 的输入成本节省，且不损失任何信息。

6. **精准的 Token 管理是工程艺术**：OpenClaw 通过多层机制（估算 → 裁剪 → 压缩 → 保护 → 缓存）构建了一个完整的 Token 生命周期管理体系。

7. **真正的突破在于 LLM 基础设施演进**：有状态推理、增量上下文协议、持续降价——这些基础设施层面的变革才能从根本上解决 Agent 系统的 Token 消耗问题。

---

> 📝 **注**: 本文档中的 Token 消耗估算基于对源码的静态分析和典型使用模式的推算。实际消耗会因模型、语言、任务复杂度等因素而有显著差异。建议使用 OpenClaw 内置的 Cache Trace 诊断工具（`OPENCLAW_CACHE_TRACE=1`）获取精确的 Token 使用数据。
