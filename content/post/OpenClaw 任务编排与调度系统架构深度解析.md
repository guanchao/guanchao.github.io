---
title: "OpenClaw 任务编排与调度系统架构深度解析"
date: 2026-04-01
draft: false
description: "深入剖析 OpenClaw 的任务编排与调度系统架构，涵盖 ClawFlow 流程编排、Task Registry 任务注册表、Command Queue 命令队列、Cron Service 定时任务等核心组件的设计原理与实现机制。"
tags:
  - OpenClaw
  - 任务调度
  - 工作流编排
  - 分布式系统
  - 源码分析
categories:
  - 系统架构
  - 源码分析
---

# OpenClaw 任务编排与调度系统架构深度解析

> **源码版本信息**
> 
> | 项目 | 值 |
> |------|-----|
> | **仓库地址** | https://github.com/openclaw/openclaw |
> | **分支** | `main` |
> | **版本标签** | `v2026.3.31-95-gcb131a7938` |
> | **提交哈希** | `cb131a79385a829af5ec5fbd5aab682c922c5668` |
> | **提交时间** | 2026-04-01 03:18:35 +0100 |
> | **文档生成时间** | 2026年4月1日 |

## 目录

- [1. 概述](#1-概述)
- [2. 系统架构总览](#2-系统架构总览)
- [3. ClawFlow 流程编排层](#3-clawflow-流程编排层)
  - [3.1 解决的核心问题](#31-解决的核心问题)
  - [3.2 设计理念](#32-设计理念)
  - [3.3 核心概念](#33-核心概念)
  - [3.4 运行时 API](#34-运行时-api)
  - [3.5 与 Task 的关系](#35-与-task-的关系)
  - [3.6 CLI 命令](#36-cli-命令)
  - [3.7 使用模式](#37-使用模式)
  - [3.8 ClawFlow、Lobster、ACPX 三者关系](#38-clawflowlobsteracpx-三者关系)
    - [架构层次关系图](#架构层次关系图)
    - [三者的核心定位](#三者的核心定位)
    - [任务关系定义的区别](#任务关系定义的区别)
    - [使用场景选择](#使用场景选择)
  - [3.9 阻塞状态处理](#39-阻塞状态处理)
- [4. 后台任务注册表 (Task Registry)](#4-后台任务注册表-task-registry)
  - [4.1 核心数据结构](#41-核心数据结构)
  - [4.2 任务生命周期](#42-任务生命周期)
  - [4.3 持久化存储](#43-持久化存储)
  - [4.4 任务维护与清理](#44-任务维护与清理)
- [5. 命令队列系统 (Command Queue)](#5-命令队列系统-command-queue)
  - [5.1 设计目标](#51-设计目标)
  - [5.2 多通道并行架构](#52-多通道并行架构)
  - [5.3 核心实现机制](#53-核心实现机制)
- [6. 定时任务系统 (Cron Service)](#6-定时任务系统-cron-service)
  - [6.1 调度类型](#61-调度类型)
  - [6.2 任务负载类型](#62-任务负载类型)
  - [6.3 服务架构](#63-服务架构)
- [7. 消息跟进队列 (Followup Queue)](#7-消息跟进队列-followup-queue)
  - [7.1 队列模式](#71-队列模式)
  - [7.2 去重机制](#72-去重机制)
  - [7.3 排空策略](#73-排空策略)
- [8. 任务执行器 (Task Executor)](#8-任务执行器-task-executor)
- [9. 各组件协作流程](#9-各组件协作流程)
- [10. 设计亮点与最佳实践](#10-设计亮点与最佳实践)
- [11. 总结](#11-总结)

---

## 1. 概述

OpenClaw 实现了一套完整的**多层次任务编排与调度系统**，涵盖从高层工作流编排到底层命令执行的完整链路。

### 系统组成

本文档将深入分析以下核心组件：

| 层级 | 组件 | 职责 |
|------|------|------|
| **编排层** | ClawFlow | Flow 身份管理、状态追踪、等待机制 |
| **编排层** | Lobster DSL | 声明式工作流定义、数据流编排 |
| **编排层** | ACPX | AI 自主决策的动态任务编排 |
| **调度层** | Task Registry | 后台任务注册、状态管理、通知投递 |
| **调度层** | Command Queue | 命令序列化、多通道并行处理 |
| **调度层** | Cron Service | 定时任务调度、周期性执行 |
| **调度层** | Followup Queue | 消息跟进、去重、批量处理 |
| **执行层** | Task Executor | 任务创建、执行、状态更新 |

### 核心设计理念

1. **分层架构**：从低级命令队列到高级任务编排的清晰分层
2. **持久化优先**：关键任务状态使用 SQLite 持久化存储
3. **可观测性**：完整的任务状态追踪和审计能力
4. **弹性设计**：支持任务取消、超时处理、失败重试

---

## 2. 系统架构总览

```
┌─────────────────────────────────────────────────────────────────────┐
│                      任务流管理体系架构                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │            编排层 (Lobster / ACPX / TypeScript)              │    │
│  │     - 分支逻辑、业务规则、条件判断                           │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│                              ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                 ClawFlow (流程编排层)                         │    │
│  │     - Flow 身份与状态管理                                    │    │
│  │     - Owner Session 上下文                                   │    │
│  │     - 等待状态与输出传递                                     │    │
│  │     - CLI: openclaw flows list|show|cancel                   │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│                              ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                  Task Registry (任务注册表)                   │    │
│  │     - 后台任务记录与追踪                                      │    │
│  │     - 任务状态管理                                           │    │
│  │     - 通知投递                                               │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│         ┌───────────────────┼───────────────────┐                   │
│         ▼                   ▼                   ▼                   │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐          │
│  │ Cron Service │    │Command Queue│    │ Followup Queue  │          │
│  │  (定时任务)   │    │ (命令队列)  │    │   (跟进队列)    │          │
│  └─────────────┘    └─────────────┘    └─────────────────┘          │
│         │                   │                   │                   │
│         └───────────────────┼───────────────────┘                   │
│                             ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                   Task Executor (任务执行器)                  │    │
│  │     - 任务创建与启动                                         │    │
│  │     - 状态更新与完成                                         │    │
│  │     - 错误处理与取消                                         │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                             │                                       │
│                             ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                 SQLite Storage (持久化存储)                   │    │
│  │     $OPENCLAW_STATE_DIR/tasks/runs.sqlite                    │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 任务来源分类

| 来源 | 运行时类型 | 默认通知策略 | 描述 |
|------|-----------|-------------|------|
| ACP 后台运行 | `acp` | `done_only` | AI Control Plane 发起的后台任务 |
| 子代理编排 | `subagent` | `done_only` | 子代理执行的独立任务 |
| 定时任务 | `cron` | `silent` | Cron 服务调度的周期性任务 |
| CLI 操作 | `cli` | `done_only` | 命令行发起的任务 |

---

## 3. ClawFlow 流程编排层

ClawFlow 是 OpenClaw 在 **2026.3.31 版本** 引入的流程编排层，位于 Background Tasks 之上，提供作业级别的任务分组和控制能力。

### 3.1 解决的核心问题

在引入 ClawFlow 之前，OpenClaw 的后台任务系统存在以下痛点：

#### 问题 1：所有者上下文丢失

当任务被分离（detach）到后台运行时，任务完成后不知道应该把结果发回哪个会话：

```
用户 (Telegram) 请求: "帮我处理邮件"
        │
        ▼ 分离任务
   后台 Task (处理中...)
        │
        ▼ 完成！但是...
   ❌ 任务不知道应该把结果发回哪个会话
   ❌ 用户收不到完成通知
   ❌ 上下文丢失
```

**ClawFlow 解决方案**：通过 `ownerSessionKey` 保持所有者上下文，任务完成后自动路由回正确的会话。

#### 问题 2：多步骤任务缺乏关联

复杂任务往往需要多个步骤，但这些步骤看起来是孤立的：

```
Task 1: 收集数据  ──→  完成 ✓
Task 2: 分析数据  ──→  完成 ✓
Task 3: 生成报告  ──→  失败 ✗

问题：
❌ 三个任务看起来是独立的，无法知道它们属于同一个"作业"
❌ Task 3 失败了，但 Task 1/2 的结果怎么传递给重试？
❌ 想取消整个作业，需要分别取消每个任务
❌ 无法查看整体进度
```

**ClawFlow 解决方案**：Flow 作为作业级别的包装器，把相关任务组织在一起，支持输出传递和整体控制。

#### 问题 3：等待状态不透明

长时间运行的任务需要等待子任务或外部事件，但系统只显示"运行中"：

```
Task: 处理 PR 审核
     ├── 获取 PR 详情  ✓
     ├── AI 分析代码   (运行中...)
     └── 发送评论      (等待中)

问题：
❌ 系统只知道任务在"运行中"，但不知道具体在等什么
❌ 运维人员无法判断任务是卡住了还是正常等待
```

**ClawFlow 解决方案**：显式的 `waitTarget` 跟踪，清晰记录在等待什么。

#### 问题 4：阻塞状态无法持久化

任务因权限、配额等原因被阻塞时，重启后信息丢失：

```
Task: 发送大量邮件
     └── 阻塞：达到 API 配额限制

问题：
❌ 重启后阻塞原因丢失
❌ 解决问题后无法干净地重试
```

**ClawFlow 解决方案**：`blocked` 状态和 `blockedSummary` 持久化到 SQLite，支持干净重试。

#### 问题对比总结

| 问题 | 没有 ClawFlow | 有 ClawFlow |
|------|--------------|-------------|
| **所有者上下文** | 任务完成后不知道回复给谁 | `ownerSessionKey` 保持返回通道 |
| **任务关联** | 多个相关任务是孤立的 | Flow 把相关任务组织成一个作业 |
| **等待状态** | 只知道"运行中"，不知道等什么 | 显式的 `waitTarget` 跟踪 |
| **阻塞持久化** | 阻塞原因丢失，无法干净重试 | `blocked` 状态和 `blockedSummary` 持久化 |

> **核心价值**：ClawFlow 让"分离的后台工作能够找到回家的路"——无论任务在后台运行多久、经历多少步骤，最终结果都能正确地返回给发起请求的用户。

### 3.2 设计理念

ClawFlow 是一个**运行时基底（Runtime Substrate）**，而非工作流语言。它的核心设计理念是：

```
┌─────────────────────────────────────────────────────────────────────┐
│                        编排层 (Authoring Layer)                      │
│                                                                      │
│    ┌───────────┐    ┌───────────┐    ┌───────────┐    ┌─────────┐  │
│    │  Lobster  │    │   ACPX    │    │ TypeScript│    │  Skills │  │
│    │ (DSL语言) │    │ (AI控制)  │    │  Helpers  │    │(技能包) │  │
│    └─────┬─────┘    └─────┬─────┘    └─────┬─────┘    └────┬────┘  │
│          │                │                │               │        │
│          └────────────────┴────────────────┴───────────────┘        │
│                                    │                                 │
├────────────────────────────────────┼─────────────────────────────────┤
│                                    ▼                                 │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                 ClawFlow Runtime Substrate                   │    │
│  │                                                              │    │
│  │  拥有:                          不拥有:                      │    │
│  │  • Flow 身份标识                • 分支逻辑                   │    │
│  │  • Owner Session 上下文         • 业务逻辑                   │    │
│  │  • 等待状态                     • 条件判断                   │    │
│  │  • 小型持久化输出               • 循环控制                   │    │
│  │  • 完成/失败/取消/阻塞状态                                   │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                    │                                 │
├────────────────────────────────────┼─────────────────────────────────┤
│                                    ▼                                 │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                     Task Registry                            │    │
│  │                   (后台任务注册表)                            │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**关键设计决策**：
- ClawFlow 只负责流程身份、状态管理和返回上下文
- 分支逻辑、业务规则放在上层编排层（Lobster、ACPX、代码）
- 保持运行时基底轻量，支持多种编排方式

### 3.3 核心概念

#### Flow（流程）

Flow 是一个作业级别的包装器，将相关的 Task 运行组织在一起：

```typescript
// Flow 核心属性
type Flow = {
  flowId: string;              // 流程唯一标识
  ownerSessionKey: string;     // 所有者会话键（返回上下文）
  goal?: string;               // 流程目标描述
  currentStep?: string;        // 当前步骤
  status: FlowStatus;          // 流程状态
  waitTarget?: string;         // 等待目标（等待中的任务或事件）
  outputs?: Record<string, unknown>; // 步骤间传递的小型输出
  blockedSummary?: string;     // 阻塞原因（如有）
  createdAt: number;           // 创建时间
  updatedAt: number;           // 更新时间
};

// Flow 状态
type FlowStatus = 
  | "active"     // 活跃中
  | "waiting"    // 等待中（等待子任务或外部事件）
  | "blocked"    // 阻塞（需要人工干预）
  | "finished"   // 已完成
  | "failed"     // 失败
  | "cancelled"; // 已取消
```

#### Flow 与 Task 的层次关系

```
┌─────────────────────────────────────────────────────────────────┐
│                         ClawFlow                                 │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                      Flow                                │    │
│  │  flowId: "flow-inbox-triage-001"                        │    │
│  │  ownerSessionKey: "agent:main:telegram:user123"         │    │
│  │  goal: "Triage inbox messages"                          │    │
│  │  currentStep: "classify"                                │    │
│  │                                                          │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │    │
│  │  │   Task 1    │  │   Task 2    │  │   Task 3    │     │    │
│  │  │ (classify)  │  │ (route)     │  │ (notify)    │     │    │
│  │  │ status:done │  │ status:run  │  │ status:wait │     │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘     │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.4 运行时 API

ClawFlow 提供一组简洁的运行时 API，供上层编排层调用：

```typescript
// 文档定义的运行时接口 (docs/automation/clawflow.md)

// 创建新流程
createFlow(params: {
  ownerSessionKey: string;
  goal?: string;
}): Flow;

// 在流程中运行任务
runTaskInFlow(params: {
  flowId: string;
  runtime: TaskRuntime;
  task: string;
  currentStep?: string;
}): TaskRecord;

// 设置流程为等待状态
setFlowWaiting(params: {
  flowId: string;
  waitTarget: string;
}): void;

// 设置流程输出（步骤间传递数据）
setFlowOutput(params: {
  flowId: string;
  key: string;
  value: unknown;
}): void;

// 追加流程输出
appendFlowOutput(params: {
  flowId: string;
  key: string;
  value: unknown;
}): void;

// 发送流程更新到所有者
emitFlowUpdate(params: {
  flowId: string;
  message: string;
}): void;

// 恢复流程执行
resumeFlow(params: {
  flowId: string;
  currentStep?: string;
}): void;

// 完成流程
finishFlow(params: {
  flowId: string;
  summary?: string;
}): void;

// 标记流程失败
failFlow(params: {
  flowId: string;
  error: string;
}): void;
```

### 3.5 与 Task 的关系

ClawFlow 和 Task Registry 的职责划分：

| 层次 | 组件 | 职责 |
|------|------|------|
| **作业层** | ClawFlow | 流程身份、所有者上下文、步骤跟踪、输出传递 |
| **执行层** | Task Registry | 单个任务记录、状态追踪、通知投递 |

#### 单任务 Flow（自动同步）

对于简单的分离运行，系统会自动创建单任务 Flow：

```typescript
// ACP 或 Subagent 发起的分离运行
// 系统自动包装为单任务 Flow
const task = createRunningTaskRun({
  runtime: "acp",
  task: "Process email",
  // ... 其他参数
});

// 系统内部自动创建关联的 Flow
// 使任务可以通过父会话返回结果
```

#### 多任务 Flow（显式创建）

对于复杂的多步骤工作，需要显式创建 Flow：

```typescript
// 显式创建多任务流程
const flow = createFlow({
  ownerSessionKey: "agent:main:telegram:user123",
  goal: "Process weekly report",
});

// 第一步：收集数据
const collectTask = runTaskInFlow({
  flowId: flow.flowId,
  runtime: "acp",
  task: "Collect metrics from all sources",
  currentStep: "collect",
});

// 等待第一步完成
setFlowWaiting({ flowId: flow.flowId, waitTarget: collectTask.taskId });

// ... 第一步完成后 ...

// 恢复并开始第二步
resumeFlow({ flowId: flow.flowId, currentStep: "analyze" });
const analyzeTask = runTaskInFlow({
  flowId: flow.flowId,
  runtime: "acp",
  task: "Analyze collected metrics",
  currentStep: "analyze",
});

// 传递中间结果
setFlowOutput({
  flowId: flow.flowId,
  key: "metrics",
  value: { total: 1500, growth: 0.12 },
});

// 完成流程
finishFlow({ flowId: flow.flowId, summary: "Weekly report generated" });
```

### 3.6 CLI 命令

ClawFlow 提供简洁的 CLI 管理界面：

```bash
# 列出所有流程
openclaw flows list
openclaw flows list --status blocked  # 只显示阻塞的流程
openclaw flows list --json            # JSON 格式输出

# 查看单个流程详情
openclaw flows show <flow-id>
openclaw flows show <owner-session-key>  # 也支持按所有者会话查找
openclaw flows show <lookup> --json

# 取消流程（同时取消所有活跃的子任务）
openclaw flows cancel <flow-id>
```

#### `flows show` 输出示例

```
Flow: flow-inbox-triage-001
Status: waiting
Owner: agent:main:telegram:user123
Goal: Triage inbox messages
Current Step: classify
Wait Target: task-abc123

Output Keys: classification, routeDecision

Linked Tasks:
  task-abc123  running   Classify incoming messages
  task-def456  succeeded Filter spam messages
```

### 3.7 使用模式

#### 串行 vs 并行：设计决策

**ClawFlow 设计为线性（串行）优先**，这是一个有意为之的架构决策：

```
┌─────────────────────────────────────────────────────────────────────┐
│                     ClawFlow 架构分层                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              编排层 (Authoring Layer)                         │   │
│  │                                                               │   │
│  │   负责：分支逻辑、条件判断、并行控制、业务规则                │   │
│  │                                                               │   │
│  │   ┌───────────┐  ┌───────────┐  ┌───────────┐                │   │
│  │   │  Lobster  │  │   ACPX    │  │ TypeScript│                │   │
│  │   │ (条件/审批)│  │ (AI决策)  │  │ (并发控制)│                │   │
│  │   └───────────┘  └───────────┘  └───────────┘                │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                              │                                       │
│                              ▼                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              ClawFlow Runtime Substrate                       │   │
│  │                                                               │   │
│  │   负责：Flow 身份、等待状态、输出传递、返回上下文             │   │
│  │   不负责：分支、循环、并行 ← 这些由上层处理                   │   │
│  │                                                               │   │
│  │   推荐模式: Step 1 → Step 2 → Step 3 → 完成                  │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**为什么选择线性优先？**

| 考量 | 说明 |
|------|------|
| **简单性** | 线性流程更容易理解、调试和恢复 |
| **可预测性** | 步骤顺序确定，状态转换清晰 |
| **灵活性** | 并行逻辑由上层编排层按需实现 |
| **分离关注点** | ClawFlow 专注于身份和上下文，不绑定特定编排模型 |

**如果需要并行任务怎么办？**

在上层编排层实现。例如，TypeScript 代码可以使用 `runTasksWithConcurrency` 并发启动多个任务：

```typescript
// 上层编排代码示例：并行执行多个任务
import { runTasksWithConcurrency } from "./utils/run-with-concurrency.js";

const flow = createFlow({ ownerSessionKey: "..." });

// 并行启动 3 个任务
const { results } = await runTasksWithConcurrency({
  tasks: [
    () => runTaskInFlow({ flowId: flow.flowId, task: "Fetch data A", ... }),
    () => runTaskInFlow({ flowId: flow.flowId, task: "Fetch data B", ... }),
    () => runTaskInFlow({ flowId: flow.flowId, task: "Fetch data C", ... }),
  ],
  limit: 3,  // 并发数
});

// 等待所有任务完成后继续
// ...
```

#### 编排方式对比

目前 OpenClaw **没有图形化拖拽界面**，编排完全通过文本/代码方式实现：

| 编排方式 | 类型 | 描述 | 适用场景 |
|---------|------|------|----------|
| **Lobster DSL** | YAML/文本 | 工作流语言，支持步骤、条件、审批门 | 确定性多步骤流程 |
| **ACPX** | AI 控制 | AI 动态决策流程走向 | 需要智能判断的场景 |
| **TypeScript** | 代码 | 直接调用 ClawFlow API | 复杂业务逻辑、并行控制 |
| **Skills** | 技能包 | 预定义的工作流模板 | 常见任务模式复用 |
| **CLI** | 命令行 | 手动管理和调试 | 运维和排查 |

```
┌─────────────────────────────────────────────────────────────────┐
│                     编排方式对比                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Lobster DSL (.lobster 文件)         TypeScript 代码            │
│  ─────────────────────────           ──────────────────         │
│  name: inbox-triage                  const flow = createFlow(); │
│  steps:                              runTaskInFlow({...});      │
│    - id: fetch                       setFlowWaiting({...});     │
│      command: gog.gmail.search       resumeFlow({...});         │
│    - id: classify                    finishFlow({...});         │
│      command: llm-task...                                       │
│      stdin: $fetch.stdout                                       │
│    - id: approve                                                │
│      approval: required                                         │
│                                                                  │
│  优点：声明式、可审计、审批内置      优点：灵活、可并行、可测试  │
│  缺点：表达能力有限                  缺点：需要编码             │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ❌ 目前不支持：                                                 │
│  • 图形化拖拽编排界面                                           │
│  • 可视化流程设计器                                             │
│  • 低代码/无代码工作流编辑                                      │
│                                                                  │
│  ⚠️  未来可能：                                                  │
│  • Control UI 中的流程可视化（只读查看）                        │
│  • Lobster 文件的图形化预览                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### Lobster vs ACPX：谁来生成工作流？

**两者都不是由 Agent 自动生成完整的工作流定义**，但它们的工作模式有本质区别：

##### Lobster DSL - 需要预定义，AI 负责调用

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Lobster 工作流的创建和执行                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  创建阶段（需要人工介入）：                                          │
│  ────────────────────────                                           │
│                                                                      │
│  方式 1: 用户/开发者手写 .lobster 文件                              │
│  ┌─────────────────────────────────────────────────────┐            │
│  │  # inbox-triage.lobster                             │            │
│  │  name: inbox-triage                                  │            │
│  │  steps:                                              │            │
│  │    - id: collect                                     │            │
│  │      command: inbox list --json                      │            │
│  │    - id: approve                                     │            │
│  │      command: inbox apply --approve                  │            │
│  │      approval: required                              │            │
│  └─────────────────────────────────────────────────────┘            │
│                                                                      │
│  方式 2: AI 可以帮你写（但需要你请求和保存）                        │
│  用户: "帮我写一个处理邮件的 Lobster 工作流"                        │
│  AI: 生成 .lobster 文件内容 → 用户保存 → 后续可调用                │
│                                                                      │
│  方式 3: 内联管道字符串（AI 可以动态构造简单管道）                  │
│  ┌─────────────────────────────────────────────────────┐            │
│  │  {                                                   │            │
│  │    "action": "run",                                  │            │
│  │    "pipeline": "cmd1 | cmd2 | approve --prompt '?'" │ ← AI构造  │
│  │  }                                                   │            │
│  └─────────────────────────────────────────────────────┘            │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  执行阶段（AI 自动调用）：                                           │
│  ───────────────────────                                            │
│                                                                      │
│  用户: "帮我整理今天的邮件"                                         │
│       │                                                              │
│       ▼                                                              │
│  AI 决定调用 lobster 工具：                                         │
│  ┌─────────────────────────────────────────────────────┐            │
│  │  lobster.run({                                       │            │
│  │    pipeline: "inbox-triage.lobster",  ← 调用预定义  │            │
│  │    argsJson: '{"limit": 20}'                         │            │
│  │  })                                                  │            │
│  └─────────────────────────────────────────────────────┘            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Lobster 的设计哲学**：

| 特点 | 说明 |
|------|------|
| **确定性** | 流程是数据（YAML），可审计、可重放 |
| **预定义** | `.lobster` 文件需要提前编写好 |
| **AI 可辅助创建** | AI 可以帮你生成 `.lobster` 文件内容，但需要你保存 |
| **AI 负责调用** | 执行时 AI 选择合适的工作流并调用 |
| **不是动态生成** | AI 不会在运行时即时生成复杂工作流 |

> **文档原话**: "Your assistant can build the tools that manage itself. Ask for a workflow, and 30 minutes later you have a CLI plus pipelines that run as one call."

##### ACPX - AI 完全自主控制执行流程

ACPX（ACP eXternal runtime）是连接外部 AI 编码助手（如 Codex、Claude Code、Cursor、Gemini）的运行时后端：

```
┌─────────────────────────────────────────────────────────────────────┐
│                     ACPX 的 AI 驱动执行                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  用户请求: "帮我重构这个代码库的错误处理"                           │
│       │                                                              │
│       ▼                                                              │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │           AI 运行时 (ACPX - Codex/Claude/Cursor)            │    │
│  │                                                              │    │
│  │  AI 自主决策下一步：                                        │    │
│  │  1. 先搜索所有 try/catch 块                                 │    │
│  │  2. 分析错误处理模式                                        │    │
│  │  3. 提出重构方案                                            │    │
│  │  4. 逐个修改文件                                            │    │
│  │  5. 运行测试验证                                            │    │
│  │                                                              │    │
│  │  ↑ 流程完全由 AI 动态决定                                   │    │
│  │  ↑ 没有预定义的工作流文件                                   │    │
│  │  ↑ AI 实时判断下一步做什么                                  │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  特点：                                                              │
│  • AI 实时决策流程走向，不需要预定义工作流                         │
│  • 适合探索性、复杂判断、编码任务                                  │
│  • 但不确定性高、token 消耗大、难以审计                           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

##### 两种模式对比总结

| 维度 | Lobster DSL | ACPX |
|------|-------------|------|
| **工作流定义者** | 用户/开发者（AI 可辅助） | AI 实时决策 |
| **定义时机** | 提前编写 | 运行时动态 |
| **流程确定性** | 确定性（数据驱动） | 不确定性（AI 判断） |
| **AI 的角色** | 调用者/参数传递 | 完全控制者 |
| **适合场景** | 重复性、可审计任务 | 探索性、复杂判断任务 |

> 更多关于三者的架构关系、执行模型、详细对比，请参见 [3.8 ClawFlow、Lobster、ACPX 三者关系](#38-clawflowlobsteracpx-三者关系)。

##### 用户需要做什么？

**使用 Lobster**：
1. 编写 `.lobster` 工作流文件（或让 AI 帮你生成文件内容后保存）
2. 在配置中启用 `lobster` 工具：`tools.alsoAllow: ["lobster"]`
3. 告诉 AI 什么时候该用哪个工作流，或让 AI 自己判断

**使用 ACPX**：
1. 配置 ACP 运行时后端（安装 codex/claude CLI 等）
2. 设置权限和安全策略
3. 描述任务目标，让 AI 自己决定怎么做

##### AI 辅助创建工作流的模式

虽然 Lobster 需要预定义，但 AI 可以帮助创建这些定义：

```
用户: "我需要一个处理 GitHub PR 的工作流"
      │
      ▼
AI 可以帮你：
1. 设计工作流逻辑
2. 生成 .lobster 文件内容
3. 甚至帮你写配套的 CLI 工具（如 `pr-cli review --json`）
      │
      ▼
用户保存这些文件到项目中
      │
      ▼
以后用户说 "帮我审核 PR"
      │
      ▼
AI 自动调用 pr-review.lobster 工作流
```

这种模式结合了两种方法的优点：
- **创建时**：利用 AI 的能力快速生成工作流定义
- **执行时**：使用确定性的 Lobster 运行时，保证可审计和可重放

#### Lobster 工作流示例

Lobster 是 ClawFlow 之上的编排层，支持条件、审批和步骤间数据传递：

```yaml
# skills/clawflow/examples/inbox-triage.lobster
name: inbox-triage
steps:
  - id: fetch
    command: gog.gmail.search --query 'newer_than:1d' --max 20

  - id: classify
    command: openclaw.invoke --tool llm-task --action json --args-json '{...}'
    stdin: $fetch.stdout  # 步骤间数据传递

  - id: post_business
    command: slack-route --bucket business
    stdin: $classify.stdout
    condition: $classify.json.items[0].route == "business"  # 条件分支

  - id: approve_action
    command: inbox apply --approve
    approval: required  # 审批门：需要人工确认才能继续

  - id: execute
    command: inbox apply --execute
    condition: $approve_action.approved
```

**Lobster 特点：**
- **一次调用代替多次**: AI 只需一次工具调用，Lobster 执行完整流程
- **审批内置**: `approval: required` 暂停流程等待人工确认
- **可恢复**: 审批通过后使用 `resumeToken` 继续执行
- **确定性**: 流程是数据，可审计、可重放

#### 推荐的线性模式

ClawFlow 的设计倾向于**线性流程**：

```
┌────────────┐     ┌────────────┐     ┌────────────┐
│ Create     │     │ Run Task   │     │ Wait for   │
│ Flow       │ ──▶ │ in Flow    │ ──▶ │ Completion │
└────────────┘     └────────────┘     └─────┬──────┘
                                            │
     ┌──────────────────────────────────────┘
     ▼
┌────────────┐     ┌────────────┐     ┌────────────┐
│ Resume     │     │ Run Next   │     │ Finish     │
│ Flow       │ ──▶ │ Task       │ ──▶ │ Flow       │
└────────────┘     └────────────┘     └────────────┘
```

#### 典型使用场景

| 场景 | 描述 | Flow 类型 |
|------|------|----------|
| 简单后台任务 | 单个 ACP/Subagent 任务 | 单任务 Flow（自动） |
| 邮箱分类处理 | 分类 → 路由 → 通知 | 多任务 Flow |
| PR 审核流程 | 获取 → 分析 → 评论 | 多任务 Flow |
| 定期报告生成 | 收集 → 分析 → 格式化 → 发送 | 多任务 Flow |
| 工单处理 | 接收 → 分类 → 分配 → 跟进 | 多任务 Flow |

### 3.8 ClawFlow、Lobster、ACPX 三者关系

#### 架构层次关系图

```
┌─────────────────────────────────────────────────────────────────────┐
│                         架构层次关系                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              编排层 (Authoring Layer) - "怎么编排流程"        │   │
│  │                                                               │   │
│  │   ┌───────────────┐           ┌───────────────┐              │   │
│  │   │   Lobster     │           │     ACPX      │              │   │
│  │   │   (DSL语言)   │           │  (AI运行时)   │              │   │
│  │   │               │           │               │              │   │
│  │   │ • 预定义工作流│           │ • AI实时决策  │              │   │
│  │   │ • 确定性执行  │           │ • 动态流程    │              │   │
│  │   │ • 内置审批门  │           │ • 外部AI接入  │              │   │
│  │   └───────┬───────┘           └───────┬───────┘              │   │
│  │           │                           │                       │   │
│  └───────────┼───────────────────────────┼───────────────────────┘   │
│              │                           │                           │
│              │   都调用 ClawFlow API     │                           │
│              └─────────────┬─────────────┘                           │
│                            ▼                                         │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │           ClawFlow (Runtime Substrate) - "流程基础设施"       │   │
│  │                                                               │   │
│  │   提供：                                                      │   │
│  │   • Flow 身份标识 (flowId)                                   │   │
│  │   • Owner Session 上下文 (返回通道)                          │   │
│  │   • 等待状态跟踪 (waitTarget)                                │   │
│  │   • 步骤间输出传递 (outputs)                                 │   │
│  │   • 完成/失败/阻塞状态                                       │   │
│  │                                                               │   │
│  │   不提供：分支逻辑、业务规则、条件判断（由上层负责）         │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                            │                                         │
│                            ▼                                         │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                  Task Registry (任务注册表)                   │   │
│  │                  Command Queue (命令队列)                     │   │
│  │                  SQLite Storage (持久化)                      │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### 三者的核心定位

| 组件 | 定位 | 类比 |
|------|------|------|
| **ClawFlow** | 运行时基底 (Runtime Substrate) | 操作系统内核 |
| **Lobster** | 编排语言 (DSL) | 脚本语言 |
| **ACPX** | AI 运行时后端 | AI 驱动的执行引擎 |

#### 各组件详解

##### ClawFlow：基础设施层

ClawFlow **不是**工作流语言，而是一个**运行时基底**，提供：

```typescript
// ClawFlow 提供的核心能力
createFlow()        // 创建流程身份
runTaskInFlow()     // 在流程中运行任务
setFlowWaiting()    // 设置等待状态
setFlowOutput()     // 传递步骤间数据
finishFlow()        // 完成流程
```

**关键点**：ClawFlow 只管"流程是谁的、当前在哪、结果发回哪"，**不管"流程怎么走"**。

##### Lobster：声明式编排层

Lobster 是一种 **DSL (Domain Specific Language)**，用 YAML 定义工作流：

```yaml
# Lobster 定义流程"怎么走"
name: inbox-triage
steps:
  - id: fetch
    command: gog.gmail.search
  - id: classify
    command: llm-task
    stdin: $fetch.stdout      # 步骤间数据传递
  - id: approve
    approval: required        # 内置审批门
```

**Lobster 调用 ClawFlow**：执行时，Lobster 运行时会调用 `createFlow()`、`runTaskInFlow()` 等 ClawFlow API。

##### ACPX：AI 驱动编排层

ACPX 连接外部 AI 编码助手（Codex、Claude Code、Cursor 等），让 **AI 实时决定流程走向**：

```
用户: "帮我重构错误处理"
       │
       ▼
ACPX Session:
  AI 自主决策:
  1. 搜索所有 try/catch    ← AI 决定
  2. 分析错误模式          ← AI 决定  
  3. 提出重构方案          ← AI 决定
  4. 修改文件              ← AI 决定
  5. 运行测试              ← AI 决定
```

**ACPX 也调用 ClawFlow**：每个 ACP Session 可以关联到一个 Flow，确保结果能返回给用户。

#### 任务关系定义的区别

三者对于"任务关系"的处理方式完全不同：

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   ClawFlow                                                       │
│   ────────                                                       │
│   • 不定义任务关系                                               │
│   • 只记录任务归属于哪个 Flow                                    │
│   • 关系 = "这些任务属于同一批"                                  │
│                                                                  │
│   Task A ─┐                                                      │
│   Task B ─┼─► Flow (只知道归属，不知道顺序)                     │
│   Task C ─┘                                                      │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Lobster                                                        │
│   ───────                                                        │
│   • 预先定义任务关系（YAML 文件）                                │
│   • 编写时确定：顺序、数据流、条件、审批                         │
│   • 关系 = "按剧本执行"                                          │
│                                                                  │
│   Step 1 ──► Step 2 ──► Step 3 ──► Step 4                       │
│   (预先定义好的流水线)                                           │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ACPX                                                           │
│   ────                                                           │
│   • 不预先定义任务关系                                           │
│   • AI 运行时决定：下一步做什么、怎么做                          │
│   • 关系 = "AI 即兴发挥"                                         │
│                                                                  │
│   Turn 1 ──?──► Turn 2 ──?──► Turn 3 ──?──► ...                 │
│   (每一步由 AI 根据上一步结果决定)                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

##### ClawFlow：只记录关联，不定义流程

```typescript
// ClawFlow 做的事情：
const flow = createFlow({
  ownerSessionKey: "agent:main:telegram:user123",  // 记录"结果发给谁"
  goal: "处理邮件",                                 // 记录"这个流程是干嘛的"
});

// 把任务"挂"到流程上
const task1 = runTaskInFlow({ flowId: flow.flowId, task: "收集数据" });
const task2 = runTaskInFlow({ flowId: flow.flowId, task: "分析数据" });
const task3 = runTaskInFlow({ flowId: flow.flowId, task: "生成报告" });

// ClawFlow 只知道这 3 个任务属于同一个 Flow
// 但它 **不知道** task2 要等 task1 完成才能开始
// 这个顺序逻辑由调用者（Lobster/ACPX/代码）控制
```

##### Lobster：定义真正的依赖和顺序

```yaml
# Lobster 定义的是"流程逻辑"
name: process-email
steps:
  - id: collect           # 步骤 1
    command: fetch-emails
    
  - id: analyze           # 步骤 2 - 隐式依赖 collect 完成
    command: analyze-data
    stdin: $collect.stdout  # 数据依赖：用 collect 的输出
    
  - id: approve           # 步骤 3 - 需要人工审批
    approval: required
    
  - id: report            # 步骤 4 - 条件执行
    command: generate-report
    condition: $approve.approved  # 只有审批通过才执行
```

**Lobster 知道**：
- 执行顺序：collect → analyze → approve → report
- 数据流向：collect.stdout → analyze.stdin
- 审批控制：approve 暂停等人确认
- 条件分支：approve.approved 才执行 report

##### ACPX：AI 实时决策

```
┌──────────────────────────────────────────────────────────────┐
│  ACPX Session 开始                                           │
│                                                              │
│  Turn 1: AI 思考 → "我需要先搜索所有 try/catch"             │
│          执行: search_content("try.*catch")                  │
│                                                              │
│  Turn 2: AI 思考 → "找到 15 个，我来分析模式"               │
│          执行: read_file(多个文件)                           │
│                                                              │
│  Turn 3: AI 思考 → "发现 3 种错误处理模式，需要统一"        │
│          执行: replace_in_file(文件1)                        │
│                                                              │
│  Turn 4: AI 思考 → "文件1改完了，改文件2"                   │
│          执行: replace_in_file(文件2)                        │
│                                                              │
│  Turn N: AI 思考 → "都改完了，跑测试验证"                   │
│          执行: execute_command("npm test")                   │
│                                                              │
│  Turn N+1: AI 思考 → "测试通过，任务完成"                   │
│            结束 Session                                      │
└──────────────────────────────────────────────────────────────┘

❓ 每一步做什么？—— AI 实时决定，不是预先定义的
```

#### Lobster 如何与 ClawFlow 协作

```
┌─────────────────────────────────────────────────────────────────────┐
│                  Lobster 执行过程                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Lobster 读取 .lobster 文件，解析出 steps                        │
│                                                                      │
│  2. Lobster 调用 ClawFlow 创建 Flow：                               │
│     ┌──────────────────────────────────────────┐                    │
│     │  createFlow({                            │                    │
│     │    ownerSessionKey: "telegram:user123",  │                    │
│     │    goal: "process-email"                 │                    │
│     │  })                                      │                    │
│     └──────────────────────────────────────────┘                    │
│                                                                      │
│  3. Lobster 按顺序执行每个 step：                                   │
│                                                                      │
│     Step 1: collect                                                 │
│     ┌──────────────────────────────────────────┐                    │
│     │  runTaskInFlow({ flowId, task: "fetch"}) │ ← 调用 ClawFlow    │
│     │  等待完成...                              │                    │
│     │  收集输出 → 存入 $collect.stdout         │                    │
│     └──────────────────────────────────────────┘                    │
│                          │                                           │
│                          ▼ Lobster 控制"等完再继续"                 │
│     Step 2: analyze                                                 │
│     ┌──────────────────────────────────────────┐                    │
│     │  检查 stdin: $collect.stdout             │ ← Lobster 处理     │
│     │  runTaskInFlow({ flowId, task: "analyze"})│ ← 调用 ClawFlow   │
│     │  传入 collect 的输出作为输入              │                    │
│     └──────────────────────────────────────────┘                    │
│                          │                                           │
│                          ▼ Lobster 控制"等完再继续"                 │
│     Step 3: approve                                                 │
│     ┌──────────────────────────────────────────┐                    │
│     │  setFlowWaiting({ waitTarget: "human" }) │ ← 调用 ClawFlow    │
│     │  暂停，等待人工审批...                    │ ← Lobster 处理     │
│     └──────────────────────────────────────────┘                    │
│                          │                                           │
│                          ▼ 审批通过后                                │
│     Step 4: report (condition: $approve.approved)                   │
│     ┌──────────────────────────────────────────┐                    │
│     │  if (!approved) skip;                    │ ← Lobster 判断     │
│     │  runTaskInFlow({ flowId, task: "report"})│ ← 调用 ClawFlow    │
│     └──────────────────────────────────────────┘                    │
│                                                                      │
│  4. Lobster 调用 ClawFlow 完成 Flow：                               │
│     ┌──────────────────────────────────────────┐                    │
│     │  finishFlow({ flowId, summary: "done" }) │                    │
│     └──────────────────────────────────────────┘                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### ACPX 如何与 ClawFlow 协作

```
┌─────────────────────────────────────────────────────────────────────┐
│                  ACPX 与 ClawFlow 的协作                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. ACPX 收到用户请求，创建 Session                                 │
│     ┌──────────────────────────────────────────┐                    │
│     │  sessionKey = "agent:codex:acp:user123"  │                    │
│     └──────────────────────────────────────────┘                    │
│                                                                      │
│  2. ACPX 可以（可选）关联到 ClawFlow：                              │
│     ┌──────────────────────────────────────────┐                    │
│     │  createFlow({                            │                    │
│     │    ownerSessionKey: sessionKey,          │                    │
│     │    goal: "重构错误处理"                   │                    │
│     │  })                                      │                    │
│     └──────────────────────────────────────────┘                    │
│                                                                      │
│  3. AI 执行多个 Turn，每个 Turn 可能调用工具：                      │
│                                                                      │
│     Turn 1: AI → search_content()                                   │
│     Turn 2: AI → read_file()                                        │
│     Turn 3: AI → replace_in_file()  ← 可以关联到 Flow               │
│     Turn 4: AI → execute_command()                                  │
│                                                                      │
│     ❗ ACPX 的 Turn 顺序由 AI 决定，不是预定义的                    │
│                                                                      │
│  4. Session 结束，结果通过 ClawFlow 返回给用户                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### 三者关系总结

| 组件 | 核心职责 | 任务关系 |
|------|---------|---------|
| **ClawFlow** | "这些任务属于同一个作业，完成后结果发给谁" | 不定义关系，只记录归属 |
| **Lobster** | "这些任务按什么顺序执行，数据怎么传递，什么条件执行" | **预先定义**：YAML 写好顺序、数据流、条件 |
| **ACPX** | "让 AI 自己决定怎么完成任务" | **不预先定义**：AI 运行时根据结果决定下一步 |

**一句话概括**：

> **ClawFlow 是"路基"，Lobster 和 ACPX 是"路上跑的不同类型的车"。**

**类比说明**：
- **ClawFlow** = 快递单（记录寄件人、收件人、包裹清单）
- **Lobster** = 按食谱做菜（步骤写好了，照着做）
- **ACPX** = 大厨即兴烹饪（看冰箱有什么，边做边决定下一步）

两个编排层（Lobster/ACPX）都依赖 ClawFlow 提供的基础能力，但它们的**编排方式**完全不同：一个是"按剧本演"，一个是"即兴发挥"。

#### Lobster vs ACPX 详细对比

| 维度 | Lobster DSL | ACPX |
|------|-------------|------|
| **工作流定义者** | 用户/开发者（AI 可辅助） | AI 实时决策 |
| **定义时机** | 提前编写 | 运行时动态 |
| **流程确定性** | 确定性（数据驱动） | 不确定性（AI 判断） |
| **AI 的角色** | 调用者/参数传递 | 完全控制者 |
| **适合场景** | 重复性、可审计任务 | 探索性、复杂判断任务 |
| **Token 消耗** | 低（一次调用） | 高（多轮对话） |
| **审批控制** | 内置 `approval:` 门 | 需要额外实现 |
| **可预测性** | 高 | 低 |
| **可审计性** | 高（流程是数据） | 低（流程是 AI 思维链） |
| **并行模式** | 管道内串行，多管道可并行 | Session 内串行，多 Session 可并行 |
| **最小执行单元** | Step（步骤） | Turn（轮次） |
| **数据传递** | `$step.stdout` 语法 | AI 的上下文记忆 |
| **条件判断** | `condition:` 配置 | AI 自主判断 |

#### 使用场景选择

```
┌─────────────────────────────────────────────────────────────────┐
│                     何时用什么？                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  需要可审计、可重放的确定性流程？                               │
│  ──────────────────────────────                                 │
│       │                                                         │
│       └──► 用 Lobster DSL                                       │
│            • 定时任务                                           │
│            • 审批流程                                           │
│            • 重复性操作                                         │
│                                                                  │
│  需要 AI 智能判断、探索性任务？                                 │
│  ────────────────────────────                                   │
│       │                                                         │
│       └──► 用 ACPX                                              │
│            • 代码重构                                           │
│            • 问题排查                                           │
│            • 复杂编码任务                                       │
│                                                                  │
│  需要自定义复杂逻辑？                                           │
│  ─────────────────                                              │
│       │                                                         │
│       └──► 直接用 TypeScript 调用 ClawFlow API                  │
│            • 并行控制                                           │
│            • 复杂业务逻辑                                       │
│            • 自定义编排                                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.9 阻塞状态处理

当 Flow 遇到需要人工干预的情况时，进入 `blocked` 状态：

```typescript
// 任务因权限问题阻塞
// 系统自动将关联的 Flow 标记为 blocked
// 并设置 blockedSummary

// 用户可以通过 CLI 查看阻塞原因
// openclaw flows show <flow-id>

// 解决阻塞后，可以重试或取消
// openclaw flows cancel <flow-id>
```

---

## 4. 后台任务注册表 (Task Registry)

后台任务注册表是 OpenClaw 的**活动追踪账本**，负责记录所有在主会话之外运行的分离工作。

### 4.1 核心数据结构

#### TaskRecord - 任务记录

```typescript
// 文件: src/tasks/task-registry.types.ts

export type TaskRuntime = "subagent" | "acp" | "cli" | "cron";

export type TaskStatus =
  | "queued"      // 排队中
  | "running"     // 运行中
  | "succeeded"   // 成功
  | "failed"      // 失败
  | "timed_out"   // 超时
  | "cancelled"   // 已取消
  | "lost";       // 丢失（会话消失）

export type TaskRecord = {
  taskId: string;              // 唯一标识符 (UUID)
  runtime: TaskRuntime;        // 运行时类型
  sourceId?: string;           // 来源标识
  requesterSessionKey: string; // 请求者会话键
  ownerKey: string;            // 所有者键
  scopeKind: TaskScopeKind;    // 作用域类型 (session | system)
  childSessionKey?: string;    // 子会话键
  parentTaskId?: string;       // 父任务ID
  agentId?: string;            // 代理ID
  runId?: string;              // 运行ID
  label?: string;              // 标签
  task: string;                // 任务描述
  status: TaskStatus;          // 当前状态
  deliveryStatus: TaskDeliveryStatus; // 投递状态
  notifyPolicy: TaskNotifyPolicy;     // 通知策略
  createdAt: number;           // 创建时间
  startedAt?: number;          // 开始时间
  endedAt?: number;            // 结束时间
  lastEventAt?: number;        // 最后事件时间
  cleanupAfter?: number;       // 清理时间点
  error?: string;              // 错误信息
  progressSummary?: string;    // 进度摘要
  terminalSummary?: string;    // 终态摘要
  terminalOutcome?: TaskTerminalOutcome; // 终态结果
};
```

#### 通知策略

```typescript
export type TaskNotifyPolicy = 
  | "done_only"      // 仅在完成时通知
  | "state_changes"  // 状态变化时通知
  | "silent";        // 静默（不通知）
```

#### 投递状态

```typescript
export type TaskDeliveryStatus =
  | "pending"        // 待投递
  | "delivered"      // 已投递
  | "session_queued" // 已入队到会话
  | "failed"         // 投递失败
  | "parent_missing" // 父级缺失
  | "not_applicable"; // 不适用
```

### 4.2 任务生命周期

```
                    ┌──────────────────────────────────────────────────────┐
                    │                    任务生命周期                        │
                    └──────────────────────────────────────────────────────┘
                                           │
                                           ▼
                                    ┌─────────────┐
                                    │   queued    │ ◄─── createTaskRecord()
                                    │   (排队中)   │
                                    └──────┬──────┘
                                           │ startTaskRunByRunId()
                                           ▼
                                    ┌─────────────┐
                    ┌───────────────│   running   │───────────────┐
                    │               │   (运行中)   │               │
                    │               └──────┬──────┘               │
                    │                      │                      │
          超时/取消 │    ┌─────────────────┼─────────────────┐    │ 会话丢失
                    │    │                 │                 │    │
                    ▼    ▼                 ▼                 ▼    ▼
              ┌──────────┐          ┌──────────┐       ┌──────────┐
              │timed_out │          │succeeded │       │   lost   │
              │cancelled │          │ failed   │       │  (丢失)  │
              │  (终止)  │          │ (完成)   │       └──────────┘
              └──────────┘          └──────────┘
                    │                      │                 │
                    └──────────────────────┴─────────────────┘
                                           │
                                           ▼
                              7天后自动清理 (TASK_RETENTION_MS)
```

#### 状态转换函数

```typescript
// 创建排队任务
createQueuedTaskRun(params): TaskRecord

// 创建运行中任务
createRunningTaskRun(params): TaskRecord

// 标记任务运行中
startTaskRunByRunId(params): TaskRecord[]

// 记录进度
recordTaskRunProgressByRunId(params): TaskRecord[]

// 标记任务完成
completeTaskRunByRunId(params): TaskRecord[]

// 标记任务失败
failTaskRunByRunId(params): TaskRecord[]

// 标记任务丢失
markTaskRunLostById(params): TaskRecord | null
```

### 4.3 持久化存储

任务记录使用 SQLite 数据库进行持久化存储，提供 ACID 事务保证。

#### 数据库架构

```sql
-- 任务运行表
CREATE TABLE task_runs (
  task_id TEXT PRIMARY KEY,
  runtime TEXT NOT NULL,
  source_id TEXT,
  owner_key TEXT NOT NULL,
  scope_kind TEXT NOT NULL,
  child_session_key TEXT,
  parent_task_id TEXT,
  agent_id TEXT,
  run_id TEXT,
  label TEXT,
  task TEXT NOT NULL,
  status TEXT NOT NULL,
  delivery_status TEXT NOT NULL,
  notify_policy TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  started_at INTEGER,
  ended_at INTEGER,
  last_event_at INTEGER,
  cleanup_after INTEGER,
  error TEXT,
  progress_summary TEXT,
  terminal_summary TEXT,
  terminal_outcome TEXT
);

-- 任务投递状态表
CREATE TABLE task_delivery_state (
  task_id TEXT PRIMARY KEY,
  requester_origin_json TEXT,
  last_notified_event_at INTEGER
);

-- 索引优化
CREATE INDEX idx_task_runs_run_id ON task_runs(run_id);
CREATE INDEX idx_task_runs_status ON task_runs(status);
CREATE INDEX idx_task_runs_runtime_status ON task_runs(runtime, status);
CREATE INDEX idx_task_runs_cleanup_after ON task_runs(cleanup_after);
CREATE INDEX idx_task_runs_owner_key ON task_runs(owner_key);
```

#### 存储配置

```typescript
// 文件: src/tasks/task-registry.store.sqlite.ts

// WAL 模式提升并发性能
db.exec(`PRAGMA journal_mode = WAL;`);

// 完全同步确保数据安全
db.exec(`PRAGMA synchronous = FULL;`);

// 繁忙超时处理
db.exec(`PRAGMA busy_timeout = 5000;`);
```

### 4.4 任务维护与清理

```typescript
// 文件: src/tasks/task-registry.maintenance.ts

// 核心配置常量
const TASK_RECONCILE_GRACE_MS = 5 * 60_000;  // 5分钟宽限期
const TASK_RETENTION_MS = 7 * 24 * 60 * 60_000;  // 7天保留期
const TASK_SWEEP_INTERVAL_MS = 60_000;  // 60秒清理间隔

// 维护摘要
export type TaskRegistryMaintenanceSummary = {
  reconciled: number;    // 协调数（标记为丢失）
  cleanupStamped: number; // 标记清理时间戳数
  pruned: number;        // 清理数
};
```

#### 维护流程

1. **协调检查**：检测活跃任务是否有对应的后台会话
2. **丢失标记**：将无后台会话的任务标记为 `lost`
3. **清理标记**：为终态任务设置 `cleanupAfter` 时间戳
4. **过期清理**：删除超过保留期的终态任务

```typescript
export function runTaskRegistryMaintenance(): TaskRegistryMaintenanceSummary {
  const now = Date.now();
  let reconciled = 0, cleanupStamped = 0, pruned = 0;
  
  for (const task of listTaskRecords()) {
    // 1. 检查是否应标记为丢失
    if (shouldMarkLost(task, now)) {
      markTaskLost(task, now);
      reconciled += 1;
      continue;
    }
    
    // 2. 检查是否应清理
    if (shouldPruneTerminalTask(task, now)) {
      deleteTaskRecordById(task.taskId);
      pruned += 1;
      continue;
    }
    
    // 3. 标记清理时间
    if (shouldStampCleanupAfter(task)) {
      setTaskCleanupAfterById({
        taskId: task.taskId,
        cleanupAfter: resolveCleanupAfter(task),
      });
      cleanupStamped += 1;
    }
  }
  
  return { reconciled, cleanupStamped, pruned };
}
```

---

## 5. 命令队列系统 (Command Queue)

命令队列提供**进程内命令执行序列化**，是 OpenClaw 任务执行的基础设施层。

### 5.1 设计目标

1. **串行保证**：默认 "main" 通道保持命令串行执行
2. **并行支持**：额外通道支持低风险并行（如 cron 任务）
3. **隔离性**：避免不同类型任务之间的 stdin/日志交叉

### 5.2 多通道并行架构

```typescript
// 文件: src/process/lanes.ts

export const enum CommandLane {
  Main = "main",       // 主通道 - 串行执行
  Cron = "cron",       // Cron 通道 - 定时任务
  Subagent = "subagent", // 子代理通道
  Nested = "nested",   // 嵌套通道
}
```

#### 通道状态管理

```typescript
// 文件: src/process/command-queue.ts

type LaneState = {
  lane: string;           // 通道名称
  queue: QueueEntry[];    // 等待队列
  activeTaskIds: Set<number>; // 活跃任务ID集合
  maxConcurrent: number;  // 最大并发数
  draining: boolean;      // 是否正在排空
  generation: number;     // 代数（用于重启恢复）
};
```

### 5.3 核心实现机制

#### 入队与排空

```typescript
export function enqueueCommandInLane<T>(
  lane: string,
  task: () => Promise<T>,
  opts?: {
    warnAfterMs?: number;
    onWait?: (waitMs: number, queuedAhead: number) => void;
  },
): Promise<T> {
  const queueState = getQueueState();
  
  // 网关排空时拒绝新任务
  if (queueState.gatewayDraining) {
    return Promise.reject(new GatewayDrainingError());
  }
  
  const state = getLaneState(lane);
  
  return new Promise<T>((resolve, reject) => {
    state.queue.push({
      task: () => task(),
      resolve,
      reject,
      enqueuedAt: Date.now(),
      warnAfterMs: opts?.warnAfterMs ?? 2_000,
      onWait: opts?.onWait,
    });
    drainLane(lane);
  });
}
```

#### 排空泵机制

```typescript
function drainLane(lane: string) {
  const state = getLaneState(lane);
  if (state.draining) return;
  state.draining = true;

  const pump = () => {
    try {
      while (state.activeTaskIds.size < state.maxConcurrent 
             && state.queue.length > 0) {
        const entry = state.queue.shift()!;
        const taskId = getQueueState().nextTaskId++;
        state.activeTaskIds.add(taskId);
        
        void (async () => {
          try {
            const result = await entry.task();
            if (completeTask(state, taskId, taskGeneration)) {
              pump(); // 继续泵送下一个
            }
            entry.resolve(result);
          } catch (err) {
            if (completeTask(state, taskId, taskGeneration)) {
              pump();
            }
            entry.reject(err);
          }
        })();
      }
    } finally {
      state.draining = false;
    }
  };

  pump();
}
```

#### 重启恢复机制

```typescript
/**
 * 重置所有通道运行时状态为空闲。
 * 用于 SIGUSR1 进程内重启后，中断的任务 finally 块可能未运行，
 * 遗留的活跃任务ID会永久阻塞新工作的排空。
 */
export function resetAllLanes(): void {
  const queueState = getQueueState();
  queueState.gatewayDraining = false;
  const lanesToDrain: string[] = [];
  
  for (const state of queueState.lanes.values()) {
    state.generation += 1;  // 递增代数使旧完成无效
    state.activeTaskIds.clear();
    state.draining = false;
    if (state.queue.length > 0) {
      lanesToDrain.push(state.lane);
    }
  }
  
  // 重置后立即排空保留的队列项
  for (const lane of lanesToDrain) {
    drainLane(lane);
  }
}
```

---

## 6. 定时任务系统 (Cron Service)

定时任务系统提供完整的周期性任务调度能力。

### 6.1 调度类型

```typescript
// 文件: src/cron/types.ts

export type CronSchedule =
  // 一次性任务 - 指定时间点执行
  | { kind: "at"; at: string }
  
  // 周期性任务 - 固定间隔执行
  | { kind: "every"; everyMs: number; anchorMs?: number }
  
  // Cron 表达式 - 标准 cron 语法
  | {
      kind: "cron";
      expr: string;       // Cron 表达式
      tz?: string;        // 时区
      staggerMs?: number; // 随机抖动窗口
    };
```

#### 调度计算示例

```typescript
// 文件: src/cron/schedule.ts

export function computeNextRunAtMs(
  schedule: CronSchedule, 
  nowMs: number
): number | undefined {
  
  // 一次性任务
  if (schedule.kind === "at") {
    const atMs = parseAbsoluteTimeMs(schedule.at);
    return atMs > nowMs ? atMs : undefined;
  }

  // 周期性任务
  if (schedule.kind === "every") {
    const everyMs = Math.max(1, Math.floor(schedule.everyMs));
    const anchor = schedule.anchorMs ?? nowMs;
    if (nowMs < anchor) return anchor;
    
    const elapsed = nowMs - anchor;
    const steps = Math.ceil(elapsed / everyMs);
    return anchor + steps * everyMs;
  }

  // Cron 表达式
  const cron = resolveCachedCron(schedule.expr, schedule.tz);
  return cron.nextRun(new Date(nowMs))?.getTime();
}
```

### 6.2 任务负载类型

```typescript
export type CronPayload = 
  // 系统事件 - 注入文本到会话
  | { kind: "systemEvent"; text: string }
  
  // 代理回合 - 运行独立代理
  | {
      kind: "agentTurn";
      message: string;
      model?: string;
      thinking?: string;
      timeoutSeconds?: number;
      deliver?: boolean;
      channel?: CronMessageChannel;
      to?: string;
    };
```

### 6.3 服务架构

```typescript
// 文件: src/cron/service.ts

export class CronService {
  private readonly state;
  
  constructor(deps: CronServiceDeps) {
    this.state = createCronServiceState(deps);
  }

  // 启动服务
  async start() {
    await ops.start(this.state);
  }

  // 停止服务
  stop() {
    ops.stop(this.state);
  }

  // 获取状态
  async status(): Promise<CronStatusSummary> {
    return await ops.status(this.state);
  }

  // 列出任务
  async list(opts?: { includeDisabled?: boolean }): Promise<CronJob[]> {
    return await ops.list(this.state, opts);
  }

  // 添加任务
  async add(input: CronJobCreate): Promise<CronJob> {
    return await ops.add(this.state, input);
  }

  // 更新任务
  async update(id: string, patch: CronJobPatch): Promise<CronJob> {
    return await ops.update(this.state, id, patch);
  }

  // 删除任务
  async remove(id: string): Promise<CronRemoveResult> {
    return await ops.remove(this.state, id);
  }

  // 立即运行
  async run(id: string, mode?: "due" | "force") {
    return await ops.run(this.state, id, mode);
  }
}
```

#### 服务状态

```typescript
export type CronServiceState = {
  deps: CronServiceDepsInternal;
  store: CronStoreFile | null;  // 任务存储
  timer: NodeJS.Timeout | null; // 调度定时器
  running: boolean;             // 运行状态
  op: Promise<unknown>;         // 当前操作
  warnedDisabled: boolean;      // 禁用警告标记
  storeLoadedAtMs: number | null;
  storeFileMtimeMs: number | null;
};
```

---

## 7. 消息跟进队列 (Followup Queue)

消息跟进队列用于管理用户消息的排队处理，确保在代理繁忙时消息不丢失。

### 7.1 队列模式

```typescript
// 文件: src/auto-reply/reply/queue/types.ts

export type QueueMode = 
  | "interrupt"  // 中断模式 - 新消息打断当前处理
  | "collect";   // 收集模式 - 收集所有消息后批量处理

export type QueueDropPolicy = 
  | "oldest"     // 丢弃最旧的
  | "newest";    // 丢弃最新的
```

### 7.2 去重机制

```typescript
// 文件: src/auto-reply/reply/queue/enqueue.ts

export type QueueDedupeMode = 
  | "none"        // 不去重
  | "message-id"  // 按消息ID去重
  | "prompt";     // 按提示内容去重

// 去重缓存配置
const RECENT_QUEUE_MESSAGE_IDS = resolveGlobalDedupeCache(
  RECENT_QUEUE_MESSAGE_IDS_KEY, 
  {
    ttlMs: 5 * 60 * 1000,  // 5分钟TTL
    maxSize: 10_000,        // 最大10000条
  }
);

// 去重键构建
function buildRecentMessageIdKey(run: FollowupRun, queueKey: string): string {
  return JSON.stringify([
    "queue",
    queueKey,
    run.originatingChannel ?? "",
    run.originatingTo ?? "",
    run.originatingAccountId ?? "",
    run.originatingThreadId ?? "",
    run.messageId,
  ]);
}
```

### 7.3 排空策略

```typescript
// 文件: src/auto-reply/reply/queue/drain.ts

export function scheduleFollowupDrain(
  key: string,
  runFollowup: (run: FollowupRun) => Promise<void>,
): void {
  const queue = beginQueueDrain(FOLLOWUP_QUEUES, key);
  if (!queue) return;

  void (async () => {
    try {
      while (queue.items.length > 0 || queue.droppedCount > 0) {
        await waitForQueueDebounce(queue);
        
        if (queue.mode === "collect") {
          // 收集模式：检查跨通道情况
          const isCrossChannel = hasCrossChannelItems(
            queue.items, 
            resolveCrossChannelKey
          );
          
          // 批量收集处理
          const collectDrainResult = await drainCollectQueueStep({
            collectState,
            isCrossChannel,
            items: queue.items,
            run: runFollowup,
          });
          
          if (collectDrainResult !== "continue") break;
          continue;
        }

        // 中断模式：逐个处理
        if (!(await drainNextQueueItem(queue.items, runFollowup))) {
          break;
        }
      }
    } finally {
      queue.draining = false;
      if (queue.items.length === 0) {
        FOLLOWUP_QUEUES.delete(key);
      }
    }
  })();
}
```

---

## 8. 任务执行器 (Task Executor)

任务执行器是连接任务注册表和具体执行逻辑的桥梁。

### 核心 API

```typescript
// 文件: src/tasks/task-executor.ts

// 创建排队任务
export function createQueuedTaskRun(params: {
  runtime: TaskRuntime;
  sourceId?: string;
  requesterSessionKey?: string;
  ownerKey?: string;
  scopeKind?: TaskScopeKind;
  childSessionKey?: string;
  parentTaskId?: string;
  agentId?: string;
  runId?: string;
  label?: string;
  task: string;
  notifyPolicy?: TaskNotifyPolicy;
}): TaskRecord {
  return createTaskRecord({
    ...params,
    status: "queued",
  });
}

// 启动任务
export function startTaskRunByRunId(params: {
  runId: string;
  runtime?: TaskRuntime;
  sessionKey?: string;
  startedAt?: number;
  progressSummary?: string | null;
}) {
  return markTaskRunningByRunId(params);
}

// 完成任务
export function completeTaskRunByRunId(params: {
  runId: string;
  endedAt: number;
  terminalSummary?: string | null;
  terminalOutcome?: TaskTerminalOutcome | null;
}) {
  return markTaskTerminalByRunId({
    ...params,
    status: "succeeded",
  });
}

// 失败任务
export function failTaskRunByRunId(params: {
  runId: string;
  status?: "failed" | "timed_out" | "cancelled";
  endedAt: number;
  error?: string;
}) {
  return markTaskTerminalByRunId({
    ...params,
    status: params.status ?? "failed",
  });
}

// 取消任务
export async function cancelDetachedTaskRunById(params: { 
  cfg: OpenClawConfig; 
  taskId: string 
}) {
  return cancelTaskById(params);
}
```

---

## 9. 各组件协作流程

### 典型任务执行流程

```
用户请求
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│                       消息路由层                             │
│   根据请求类型分发到对应处理器                                │
└─────────────────────────────────────────────────────────────┘
    │
    ├──────────────┬──────────────┬──────────────┐
    ▼              ▼              ▼              ▼
┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐
│直接回复│   │后台任务│   │定时任务│   │子代理  │
└────────┘   └───┬────┘   └───┬────┘   └───┬────┘
                 │            │            │
                 ▼            ▼            ▼
    ┌────────────────────────────────────────────┐
    │            Task Registry                    │
    │   createTaskRecord() → status: queued      │
    └───────────────────────┬────────────────────┘
                            │
                            ▼
    ┌────────────────────────────────────────────┐
    │            Command Queue                    │
    │   enqueueCommandInLane(lane, task)         │
    └───────────────────────┬────────────────────┘
                            │
                            ▼
    ┌────────────────────────────────────────────┐
    │            Task Executor                    │
    │   startTaskRunByRunId() → status: running  │
    └───────────────────────┬────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
    ┌─────────────────┐         ┌─────────────────┐
    │   执行成功       │         │   执行失败       │
    │completeTaskRun()│         │  failTaskRun()  │
    │status: succeeded│         │status: failed   │
    └─────────────────┘         └─────────────────┘
              │                           │
              └─────────────┬─────────────┘
                            ▼
    ┌────────────────────────────────────────────┐
    │            通知投递                          │
    │   maybeDeliverTaskTerminalUpdate()         │
    └───────────────────────┬────────────────────┘
                            │
                            ▼
    ┌────────────────────────────────────────────┐
    │            清理维护                          │
    │   7天后自动清理终态任务记录                   │
    └────────────────────────────────────────────┘
```

### 定时任务调度流程

```
┌─────────────────────────────────────────────────────────────┐
│                     Cron Service                             │
└─────────────────────────────────────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
    ┌─────────────────┐         ┌─────────────────┐
    │   at 类型        │         │  every/cron     │
    │   一次性执行     │         │  周期性执行      │
    └────────┬────────┘         └────────┬────────┘
              │                           │
              └─────────────┬─────────────┘
                            │ computeNextRunAtMs()
                            ▼
              ┌────────────────────────┐
              │   等待下次执行时间      │
              │   armNextTimer()       │
              └───────────┬────────────┘
                          │ 时间到达
                          ▼
              ┌────────────────────────┐
              │   创建任务记录          │
              │   runtime: "cron"      │
              └───────────┬────────────┘
                          │
                          ▼
              ┌────────────────────────┐
              │   执行负载             │
              │  systemEvent/agentTurn │
              └───────────┬────────────┘
                          │
                          ▼
              ┌────────────────────────┐
              │   更新任务状态          │
              │   记录执行结果          │
              └───────────┬────────────┘
                          │
                          ▼
              ┌────────────────────────┐
              │   重新调度              │
              │   (非一次性任务)        │
              └────────────────────────┘
```

---

## 10. 设计亮点与最佳实践

### 10.1 全局单例模式

使用 Symbol 作为键确保跨模块共享状态：

```typescript
const COMMAND_QUEUE_STATE_KEY = Symbol.for("openclaw.commandQueueState");

function getQueueState() {
  return resolveGlobalSingleton(COMMAND_QUEUE_STATE_KEY, () => ({
    gatewayDraining: false,
    lanes: new Map<string, LaneState>(),
    nextTaskId: 1,
  }));
}
```

### 10.2 代数机制防止过期完成

```typescript
function completeTask(state: LaneState, taskId: number, taskGeneration: number): boolean {
  // 如果代数不匹配，说明是旧的完成回调，忽略
  if (taskGeneration !== state.generation) {
    return false;
  }
  state.activeTaskIds.delete(taskId);
  return true;
}
```

### 10.3 优雅降级

网关排空时快速失败：

```typescript
export class GatewayDrainingError extends Error {
  constructor() {
    super("Gateway is draining for restart; new tasks are not accepted");
    this.name = "GatewayDrainingError";
  }
}

if (queueState.gatewayDraining) {
  return Promise.reject(new GatewayDrainingError());
}
```

### 10.4 事务保证

SQLite 写操作使用事务：

```typescript
function withWriteTransaction(write: (statements: TaskRegistryStatements) => void) {
  const { db, statements } = openTaskRegistryDatabase();
  db.exec("BEGIN IMMEDIATE");
  try {
    write(statements);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}
```

### 10.5 索引优化

针对常见查询模式建立索引：

```sql
CREATE INDEX idx_task_runs_run_id ON task_runs(run_id);
CREATE INDEX idx_task_runs_status ON task_runs(status);
CREATE INDEX idx_task_runs_runtime_status ON task_runs(runtime, status);
CREATE INDEX idx_task_runs_cleanup_after ON task_runs(cleanup_after);
CREATE INDEX idx_task_runs_owner_key ON task_runs(owner_key);
```

---

## 11. 总结

OpenClaw 的任务流管理体系是一个设计精良的多层架构系统：

### 核心特点

| 层次 | 组件 | 职责 |
|------|------|------|
| **编排层** | ClawFlow | 流程身份、所有者上下文、步骤跟踪、等待状态、输出传递 |
| **记录层** | Task Registry | 任务生命周期追踪、状态管理、通知投递 |
| **执行层** | Command Queue | 命令序列化、多通道并行、排空控制 |
| **调度层** | Cron Service | 定时任务调度、多种调度模式支持 |
| **队列层** | Followup Queue | 消息排队、去重、批量处理 |
| **存储层** | SQLite Store | 持久化存储、事务保证、索引优化 |

### 技术亮点

1. **分层解耦**：各层职责清晰，易于维护和扩展
2. **持久化保证**：使用 SQLite + WAL 模式确保数据安全
3. **弹性设计**：支持任务取消、超时、重试、丢失检测
4. **可观测性**：完整的任务状态追踪和审计能力
5. **性能优化**：索引优化、缓存机制、并行处理
6. **智能并发**：ACPX 采用 "Session 内串行，Session 间并行" 模型，兼顾上下文连贯性和多用户并发

### 并发执行模型总结

| 组件 | 并行模式 | 说明 |
|------|---------|------|
| **ClawFlow** | 线性优先 | 流程内步骤串行，并行由上层编排层控制 |
| **Lobster** | 管道内串行 | 单个管道串行执行，可启动多个独立管道 |
| **ACPX** | Session 内串行，Session 间并行 | 同一 Session 保证顺序，不同 Session 可并发（通过 `maxConcurrentSessions` 配置） |
| **Command Queue** | 通道内串行，通道间并行 | Main 通道串行，Cron/Subagent 通道可并行 |
| **Task Registry** | 支持多任务并行追踪 | 纯记录层，不控制执行顺序 |

### CLI 命令参考

```bash
# 流程管理 (ClawFlow)
openclaw flows list          # 列出所有流程
openclaw flows list --status blocked  # 只显示阻塞的流程
openclaw flows show <id>     # 查看流程详情（支持 flow-id 或 owner-session-key）
openclaw flows cancel <id>   # 取消流程及其子任务

# 任务管理
openclaw tasks list          # 列出所有任务
openclaw tasks show <id>     # 查看任务详情
openclaw tasks cancel <id>   # 取消运行中的任务
openclaw tasks audit         # 运行健康审计

# 定时任务管理
openclaw cron list           # 列出定时任务
openclaw cron add <spec>     # 添加定时任务
openclaw cron update <id>    # 更新定时任务
openclaw cron remove <id>    # 删除定时任务
openclaw cron run <id>       # 立即运行
```

---

*基于 OpenClaw 源码深度分析*
