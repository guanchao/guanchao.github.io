---
title: "Gemini CLI Agent 实现原理深度解析"
date: 2026-01-14
draft: false
description: "深入剖析 Gemini CLI 项目的 Agent 实现原理，帮助开发者理解 LLM Agent 的核心机制，包括 Agent Loop、Tool Calling、上下文管理等关键技术。"
tags: 
  - Gemini
  - AI Agent
  - LLM
  - CLI
  - 源码分析
categories:
  - 技术
  - AI
---

> 本文档深入剖析 Gemini CLI 项目的 Agent 实现原理，帮助开发者理解 LLM Agent 的核心机制。

---

## 📌 代码版本说明

**本文档分析的代码版本信息**：

| 项目信息 | 详情 |
|---------|------|
| **项目名称** | @google/gemini-cli |
| **版本** | `0.21.0-nightly.20251220.41a1a3eed` |
| **最新标签** | `v0.1.12` |
| **Git Commit** | `e6344a8c2478b14e2be1e865f6253a01e3fd4a70` |
| **提交日期** | 2025-12-23 16:10:46 -0500 |
| **提交说明** | Security: Project-level hook warnings (#15470) |
| **代码仓库** | [https://github.com/google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) |
| **Node.js 版本要求** | >=20.0.0 |

### 版本注意事项

⚠️ **重要提示**：

1. **代码持续更新**：Gemini CLI 是一个活跃开发的项目，代码结构和实现细节可能会随版本更新而变化。
   
2. **文档有效期**：本文档基于 **2025年12月23日** 的代码快照编写，如果你使用的是更新的版本，部分实现细节可能已经改变。

3. **如何验证版本**：
   ```bash
   # 克隆仓库
   git clone https://github.com/google-gemini/gemini-cli.git
   cd gemini-cli
   
   # 查看当前版本
   cat package.json | grep '"version"'
   
   # 切换到本文档对应的 commit（如果需要完全一致）
   git checkout e6344a8c2478b14e2be1e865f6253a01e3fd4a70
   ```

4. **核心概念稳定**：尽管实现细节可能变化，但本文档讲解的**核心概念**（Agent Loop、Tool Calling、Function Declarations、历史压缩等）是相对稳定的架构设计。

5. **推荐学习方式**：
   - 优先理解核心概念和设计思想
   - 使用本文档作为指引，对照你的代码版本进行学习
   - 如果发现差异，可以查看项目的 [CHANGELOG](https://github.com/google-gemini/gemini-cli/releases) 了解变更

---

## 目录

1. [整体架构概览](#一整体架构概览)
2. [核心工作流程 (Agent Loop)](#二核心工作流程agent-loop)
3. [工具调用系统 (Tool Calling)](#三工具调用系统tool-calling)
4. [上下文管理](#四上下文管理)
   - 1. [历史压缩 - ChatCompressionService](#1-历史压缩---chatcompressionservice-详细剖析)
     - 1.1 [压缩触发机制](#11-压缩触发机制)
     - 1.2 [核心实现流程](#12-核心实现流程)
     - 1.3 [Token计数机制](#13-token计数机制)
     - 1.4 [压缩提示词](#14-压缩提示词)
     - 1.5 [压缩状态管理](#15-压缩状态管理)
     - 1.6 [压缩示例](#16-压缩示例)
     - 1.7 [多次压缩机制（递归压缩）](#17-多次压缩机制递归压缩)
     - 1.8 [性能优化技巧](#18-性能优化技巧)
     - 1.9 [压缩的挑战与解决方案](#19-压缩的挑战与解决方案)
     - 1.10 [压缩时机](#110-压缩时机)
5. [System Prompt 结构详解](#五system-prompt-结构详解)
   - 5.1 [概述](#51-概述)
   - 5.2 [完整结构](#52-完整结构)
   - 5.3 [各模块详解](#53-各模块详解)
   - 5.4 [动态生成逻辑](#54-动态生成逻辑)
   - 5.5 [自定义 System Prompt](#55-自定义-system-prompt)
   - 5.6 [实际示例](#56-实际示例)
   - 5.7 [与 Gemini API 的交互](#57-与-gemini-api-的交互)
   - 5.8 [设计哲学](#58-设计哲学)
6. [完整调用链示例](#六完整调用链示例)
7. [与传统程序的区别](#七与传统程序的区别)
8. [学习建议](#八学习建议)
   - 1. [学习路径](#1-学习路径)
   - 2. [实践建议](#2-实践建议)
   - 3. [关键技术点深入](#3-关键技术点深入)
   - 4. [扩展阅读](#4-扩展阅读)
   - 5. [常见问题](#5-常见问题)
9. [附录：内置工具列表](#九附录内置工具列表)

---

## 一、整体架构概览

Gemini CLI 是一个**多轮对话 AI Agent**，核心思想类似于：

```go
// Go 伪代码理解
for turn := 0; turn < maxTurns; turn++ {
    response := callLLMAPI(context, history)
    
    if response.HasToolCalls() {
        results := executeTools(response.ToolCalls)
        history.Append(results)
        continue  // 继续下一轮
    }
    
    return response.Text  // 结束
}
```

但实际实现要复杂得多，包含以下核心模块：

### 架构图

```
┌─────────────────────────────────────────────────────────┐
│                    CLI Layer (Ink UI)                    │
│  gemini.tsx → AppContainer → App → Components           │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                   Core Agent Layer                       │
│  GeminiClient ─→ Turn ─→ GeminiChat ─→ ContentGenerator │
│       ↓              ↓                                   │
│  LoopDetector  CoreToolScheduler                         │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│               Tools & Services Layer                     │
│  ToolRegistry  │  FileSystem  │  IDE  │  MCP  │ Agents  │
│  ReadFile      │  Git         │ VSCode│ Server│ A2A     │
│  Shell         │  Discovery   │ Zed   │Client │SubAgent │
└─────────────────────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              Cross-Cutting Concerns                      │
│  Hooks  │ Policy  │ Telemetry │ Context │ Compression   │
└─────────────────────────────────────────────────────────┘
```

### 核心模块职责

| 模块 | 路径 | 核心职责 |
|------|------|---------|
| **CLI 入口** | `packages/cli/src/` | UI 渲染、用户交互、命令处理 |
| **Agent 核心** | `packages/core/src/core/` | 对话管理、API 交互、流程控制 |
| **工具系统** | `packages/core/src/tools/` | 工具定义、执行、生命周期管理 |
| **配置管理** | `packages/core/src/config/` | 全局配置、模型管理、扩展加载 |
| **上下文服务** | `packages/core/src/services/` | 文件发现、Git、会话记录、压缩 |
| **Hook 系统** | `packages/core/src/hooks/` | 事件拦截、扩展点、策略注入 |
| **策略引擎** | `packages/core/src/policy/` | 权限控制、工具审批、安全策略 |
| **IDE 集成** | `packages/core/src/ide/` | VSCode/Zed 集成、上下文同步 |

---

## 二、核心工作流程(Agent Loop)

### 1. 主控制流 - GeminiClient

**文件**: `packages/core/src/core/client.ts`

这是 Agent 的"大脑"，负责整个对话的生命周期。

#### TypeScript 实现

```typescript
async *sendMessageStream(
  request: PartListUnion,
  signal: AbortSignal,
  prompt_id: string,
  turns: number = 100,  // 最多100轮
): AsyncGenerator<ServerGeminiStreamEvent, Turn>
```

**关键逻辑**:

```typescript
// 1. 触发 BeforeAgent Hook
await this.hookEventHandler.fire('BeforeAgent', ...)

// 2. Agent Loop (最多100轮)
while (turnCount < maxTurns) {
  // 2.1 检测循环(防止死循环)
  this.loopDetectionService.checkForLoop(request)
  
  // 2.2 压缩历史(如果超过token限制)
  if (needsCompression) {
    await this.chatCompressionService.compress()
  }
  
  // 2.3 注入IDE上下文(如VSCode光标位置)
  if (ideContextEnabled) {
    ideContext = await this.ideContextService.getContext()
  }
  
  // 2.4 创建Turn执行单轮对话
  const turn = new Turn(this.geminiChat, ...)
  const turnGenerator = turn.run(request, signal)
  
  // 2.5 流式输出事件
  for await (const event of turnGenerator) {
    yield event  // Content/ToolCall/Error等事件
  }
  
  // 2.6 检查是否需要继续
  if (turn.nextSpeaker !== 'model') {
    break  // 用户需要响应,或已完成
  }
  
  turnCount++
}

// 3. 触发 AfterAgent Hook
await this.hookEventHandler.fire('AfterAgent', ...)
```

#### Go 语言类比

```go
type GeminiClient struct {
    chat              *GeminiChat
    loopDetector      *LoopDetectionService
    compressionSvc    *ChatCompressionService
    hookEventHandler  *HookEventHandler
}

func (c *GeminiClient) SendMessageStream(
    ctx context.Context, 
    request Request,
) <-chan Event {
    eventCh := make(chan Event)
    
    go func() {
        defer close(eventCh)
        
        // BeforeAgent Hook
        c.hookEventHandler.Fire("BeforeAgent", request)
        
        for turn := 0; turn < maxTurns; turn++ {
            // 检测循环
            if err := c.loopDetector.Check(request); err != nil {
                eventCh <- ErrorEvent{err}
                return
            }
            
            // 压缩历史
            if c.needsCompression() {
                c.compressionSvc.Compress(ctx)
            }
            
            // 执行单轮
            turnEvents := c.executeTurn(ctx, request)
            for event := range turnEvents {
                eventCh <- event
            }
            
            // 检查是否继续
            if !shouldContinue {
                break
            }
        }
        
        // AfterAgent Hook
        c.hookEventHandler.Fire("AfterAgent", nil)
    }()
    
    return eventCh
}
```

---

### 2. 单轮执行 - Turn

**文件**: `packages/core/src/core/turn.ts`

每个 Turn 代表一次"用户→模型→工具→模型"的完整交互。

#### TypeScript 实现

```typescript
async *run(
  request: PartListUnion,
  signal: AbortSignal,
): AsyncGenerator<TurnEvent, void>
```

**执行流程**:

```typescript
// 1. 调用 GeminiChat 获取模型响应
const chatGenerator = this.geminiChat.sendMessageStream(request, signal)

for await (const chunk of chatGenerator) {
  if (chunk.type === 'text') {
    yield { type: 'Content', content: chunk.text }
  }
  
  if (chunk.type === 'functionCall') {
    // 2. 收集所有工具调用
    toolCalls.push(chunk.functionCall)
  }
  
  if (chunk.type === 'thought') {
    yield { type: 'Thought', content: chunk.thought }
  }
}

// 3. 批量执行工具
if (toolCalls.length > 0) {
  const scheduler = new CoreToolScheduler(...)
  const results = await scheduler.scheduleBatch(toolCalls, signal)
  
  // 4. 返回工具结果给模型
  yield* results  // ToolCallRequest/Response 事件
}

// 5. 检查 next_speaker
this.nextSpeaker = response.nextSpeaker || 'user'
```

#### Go 语言类比

```go
type Turn struct {
    chat      *GeminiChat
    scheduler *CoreToolScheduler
}

func (t *Turn) Run(ctx context.Context, req Request) <-chan TurnEvent {
    eventCh := make(chan TurnEvent)
    
    go func() {
        defer close(eventCh)
        
        // 1. 调用模型API
        response := t.chat.SendMessage(ctx, req)
        
        // 2. 流式输出文本
        for chunk := range response.Stream {
            eventCh <- ContentEvent{chunk.Text}
        }
        
        // 3. 执行工具
        if len(response.ToolCalls) > 0 {
            results := t.scheduler.ExecuteBatch(ctx, response.ToolCalls)
            for result := range results {
                eventCh <- ToolCallEvent{result}
            }
        }
    }()
    
    return eventCh
}
```

---

### 3. API通信层 - GeminiChat

**文件**: `packages/core/src/core/geminiChat.ts`

这是与 Gemini API 交互的核心封装。

#### 核心职责

1. **历史管理**: 维护对话历史(`user`/`model`角色交替)
2. **API调用**: 通过 `ContentGenerator` 调用 Gemini API
3. **重试机制**: 处理 `InvalidStreamError`(最多重试2次)
4. **Hook触发**: `BeforeModel`/`AfterModel`/`BeforeToolSelection`

#### TypeScript 实现

```typescript
async *sendMessageStream(
  request: PartListUnion,
  signal: AbortSignal,
): AsyncGenerator<GeminiChatChunk>
```

**核心代码**:

```typescript
// 1. 触发 BeforeModel Hook(可修改请求)
await this.fireBeforeModelHook(request)

// 2. 调用 Gemini API
const generator = await this.contentGenerator.generateContentStream({
  contents: this.history,  // 历史记录
  tools: this.toolRegistry.getToolDeclarations(),  // 工具声明
  systemInstruction: this.systemPrompt,
}, promptId)

// 3. 流式处理响应
for await (const chunk of generator) {
  if (chunk.candidates[0]?.content?.parts) {
    for (const part of chunk.candidates[0].content.parts) {
      if (part.text) {
        yield { type: 'text', text: part.text }
      }
      if (part.functionCall) {
        yield { type: 'functionCall', functionCall: part.functionCall }
      }
      if (part.thought) {
        yield { type: 'thought', thought: part.thought }
      }
    }
  }
}

// 4. 触发 AfterModel Hook
await this.fireAfterModelHook(response)

// 5. 更新历史
this.history.push({ role: 'model', parts: response.parts })
```

#### Go 语言类比

```go
type GeminiChat struct {
    history       []Message
    contentGen    ContentGenerator
    toolRegistry  *ToolRegistry
    hookHandler   *HookEventHandler
}

type Message struct {
    Role  string  // "user" or "model"
    Parts []Part
}

func (g *GeminiChat) SendMessageStream(
    ctx context.Context, 
    req Request,
) <-chan Chunk {
    chunkCh := make(chan Chunk)
    
    go func() {
        defer close(chunkCh)
        
        // 1. 触发 BeforeModel Hook
        g.hookHandler.Fire("BeforeModel", req)
        
        // 2. 调用API
        apiReq := &genai.GenerateContentRequest{
            Contents: g.history,
            Tools:    g.toolRegistry.GetDeclarations(),
        }
        stream := g.contentGen.GenerateContentStream(ctx, apiReq)
        
        // 3. 流式处理
        for {
            chunk, err := stream.Recv()
            if err == io.EOF {
                break
            }
            
            for _, part := range chunk.Parts {
                switch part.Type {
                case "text":
                    chunkCh <- TextChunk{part.Text}
                case "functionCall":
                    chunkCh <- FunctionCallChunk{part.FunctionCall}
                }
            }
        }
        
        // 4. 更新历史
        g.history = append(g.history, Message{
            Role:  "model",
            Parts: response.Parts,
        })
    }()
    
    return chunkCh
}
```

---

## 三、工具调用系统(Tool Calling)

这是 Agent 能力的核心！模型不仅返回文本，还能调用"工具"来执行操作。

### 1. 工具定义 - DeclarativeTool

**文件**: `packages/core/src/tools/tools.ts`

工具采用 **Builder + Command 模式**。

#### TypeScript 实现

```typescript
// 工具定义(声明式)
class ReadFileTool extends BaseDeclarativeTool {
  name = 'read_file'
  description = 'Read contents of a file'
  
  // JSON Schema参数定义
  parameters = {
    type: 'object',
    properties: {
      file_path: { type: 'string', description: 'Path to file' },
      offset: { type: 'number', description: 'Start line' },
      limit: { type: 'number', description: 'Number of lines' },
    },
    required: ['file_path'],
  }
  
  // 构建可执行实例
  build(params: ReadFileToolParams): ToolInvocation {
    return new ReadFileToolInvocation(this.config, params)
  }
}

// 工具调用(命令式)
class ReadFileToolInvocation extends BaseToolInvocation {
  async execute(signal: AbortSignal): Promise<ToolResult> {
    // 实际执行逻辑
    const content = await fs.readFile(this.params.file_path, 'utf-8')
    return {
      llmContent: { text: content },  // 返回给LLM
      returnDisplay: 'File read successfully',  // 用户界面显示
    }
  }
  
  // 是否需要用户确认
  shouldConfirmExecute(): boolean {
    return false  // 读文件不需要确认
  }
}
```

#### Go 语言类比

```go
// 工具接口
type Tool interface {
    Name() string
    Description() string
    Parameters() *jsonschema.Schema
    Build(params map[string]any) ToolInvocation
}

type ToolInvocation interface {
    Execute(ctx context.Context) (ToolResult, error)
    ShouldConfirm() bool
    GetDescription() string
}

// 具体实现
type ReadFileTool struct {
    config *Config
}

func (t *ReadFileTool) Name() string {
    return "read_file"
}

func (t *ReadFileTool) Description() string {
    return "Read contents of a file"
}

func (t *ReadFileTool) Parameters() *jsonschema.Schema {
    return &jsonschema.Schema{
        Type: "object",
        Properties: map[string]*jsonschema.Schema{
            "file_path": {Type: "string", Description: "Path to file"},
            "offset":    {Type: "number", Description: "Start line"},
            "limit":     {Type: "number", Description: "Number of lines"},
        },
        Required: []string{"file_path"},
    }
}

func (t *ReadFileTool) Build(params map[string]any) ToolInvocation {
    return &ReadFileInvocation{
        config:   t.config,
        filePath: params["file_path"].(string),
        offset:   int(params["offset"].(float64)),
    }
}

type ReadFileInvocation struct {
    config   *Config
    filePath string
    offset   int
}

func (i *ReadFileInvocation) Execute(ctx context.Context) (ToolResult, error) {
    content, err := os.ReadFile(i.filePath)
    if err != nil {
        return ToolResult{}, err
    }
    
    return ToolResult{
        LLMContent:    string(content),
        ReturnDisplay: "File read successfully",
    }, nil
}

func (i *ReadFileInvocation) ShouldConfirm() bool {
    return false
}
```

---

### 2. 工具调度器 - CoreToolScheduler

**文件**: `packages/core/src/core/coreToolScheduler.ts`

负责工具的**并发执行**和**生命周期管理**。

#### 工具状态机

```
validating → scheduled → executing → success
                ↓            ↓           ↓
           waiting      cancelled    error
```

#### TypeScript 实现

```typescript
async scheduleBatch(
  toolCalls: FunctionCall[],
  signal: AbortSignal,
): Promise<ToolCallResponse[]>
```

**执行流程**:

```typescript
// 1. 验证阶段(Validating)
for (const toolCall of toolCalls) {
  yield {
    type: 'ToolCallRequest',
    status: 'validating',
    id: toolCall.id,
    name: toolCall.name,
  }
  
  // 验证参数
  const tool = this.toolRegistry.getTool(toolCall.name)
  const invocation = tool.build(toolCall.args)
  
  // 2. 调度阶段(Scheduled)
  yield {
    type: 'ToolCallRequest',
    status: 'scheduled',
    id: toolCall.id,
  }
}

// 3. 并发执行(Executing)
const results = await Promise.all(
  invocations.map(async (invocation) => {
    // 检查是否需要确认
    if (await invocation.shouldConfirmExecute(signal)) {
      yield { type: 'ToolCallRequest', status: 'waiting', ... }
      
      // 等待用户确认
      const outcome = await waitForConfirmation()
      if (outcome === 'reject') {
        return { status: 'cancelled' }
      }
    }
    
    yield { type: 'ToolCallRequest', status: 'executing', ... }
    
    // 执行工具(带Hook)
    const result = await executeToolWithHooks(
      invocation,
      signal,
      this.config,
      this.messageBus,
    )
    
    yield {
      type: 'ToolCallResponse',
      status: 'success',
      result: result,
    }
    
    return result
  }),
)

return results
```

#### Go 语言类比

```go
type CoreToolScheduler struct {
    toolRegistry *ToolRegistry
    messageBus   *MessageBus
    config       *Config
}

type ToolCallState string

const (
    StateValidating ToolCallState = "validating"
    StateScheduled  ToolCallState = "scheduled"
    StateWaiting    ToolCallState = "waiting"
    StateExecuting  ToolCallState = "executing"
    StateSuccess    ToolCallState = "success"
    StateError      ToolCallState = "error"
)

func (s *CoreToolScheduler) ScheduleBatch(
    ctx context.Context,
    toolCalls []FunctionCall,
) <-chan ToolCallEvent {
    eventCh := make(chan ToolCallEvent, 100)
    
    go func() {
        defer close(eventCh)
        
        // 1. 验证阶段
        invocations := make([]ToolInvocation, 0, len(toolCalls))
        for _, call := range toolCalls {
            eventCh <- ToolCallEvent{State: StateValidating, ID: call.ID}
            
            tool := s.toolRegistry.GetTool(call.Name)
            inv := tool.Build(call.Args)
            invocations = append(invocations, inv)
            
            eventCh <- ToolCallEvent{State: StateScheduled, ID: call.ID}
        }
        
        // 2. 并发执行
        var wg sync.WaitGroup
        for _, inv := range invocations {
            wg.Add(1)
            go func(inv ToolInvocation) {
                defer wg.Done()
                
                // 检查确认
                if inv.ShouldConfirm() {
                    eventCh <- ToolCallEvent{State: StateWaiting}
                    outcome := s.waitForConfirmation(ctx)
                    if outcome == "reject" {
                        return
                    }
                }
                
                // 执行
                eventCh <- ToolCallEvent{State: StateExecuting}
                result, err := inv.Execute(ctx)
                if err != nil {
                    eventCh <- ToolCallEvent{State: StateError, Error: err}
                    return
                }
                
                eventCh <- ToolCallEvent{State: StateSuccess, Result: result}
            }(inv)
        }
        
        wg.Wait()
    }()
    
    return eventCh
}
```

---

### 3. Hook系统 - 扩展机制

**文件**: `packages/core/src/hooks/hookSystem.ts`

Hook允许在关键节点**拦截和修改**行为，类似Go的中间件。

#### TypeScript 实现

```typescript
// Hook类型
type HookType = 
  | 'BeforeAgent'   // Agent开始前
  | 'AfterAgent'    // Agent结束后
  | 'BeforeModel'   // 调用API前
  | 'AfterModel'    // API返回后
  | 'BeforeTool'    // 工具执行前
  | 'AfterTool'     // 工具执行后
  | 'ToolNotification'  // 工具请求时

// Hook定义
interface Hook {
  name: string
  type: HookType
  execute(context: HookContext): Promise<HookResult>
}

// 使用示例
class LoggingHook implements Hook {
  type = 'BeforeTool'
  
  async execute(context: HookContext): Promise<HookResult> {
    console.log(`Tool: ${context.toolName}, Args: ${context.args}`)
    return { proceed: true }  // 继续执行
  }
}

// 触发Hook
await hookEventHandler.fire('BeforeTool', {
  toolName: 'read_file',
  args: { file_path: 'test.txt' },
})
```

#### Go 语言类比

```go
type HookType string

const (
    BeforeAgent HookType = "BeforeAgent"
    BeforeTool  HookType = "BeforeTool"
    AfterTool   HookType = "AfterTool"
)

type Hook interface {
    Type() HookType
    Execute(ctx context.Context, data HookContext) (HookResult, error)
}

type HookEventHandler struct {
    hooks map[HookType][]Hook
}

func (h *HookEventHandler) Fire(
    ctx context.Context, 
    hookType HookType, 
    data HookContext,
) error {
    for _, hook := range h.hooks[hookType] {
        result, err := hook.Execute(ctx, data)
        if err != nil {
            return err
        }
        if !result.Proceed {
            return errors.New("hook rejected execution")
        }
    }
    return nil
}

// 使用示例 - 中间件模式
func executeToolWithHooks(
    ctx context.Context,
    inv ToolInvocation,
    hooks *HookEventHandler,
) (ToolResult, error) {
    // Before Hook
    if err := hooks.Fire(ctx, BeforeTool, HookContext{
        ToolName: inv.Name(),
    }); err != nil {
        return ToolResult{}, err
    }
    
    // 执行工具
    result, err := inv.Execute(ctx)
    
    // After Hook
    hooks.Fire(ctx, AfterTool, HookContext{
        ToolName: inv.Name(),
        Result:   result,
    })
    
    return result, err
}
```

---

## 四、上下文管理

### 1. 历史压缩 - ChatCompressionService (详细剖析)

**文件**: `packages/core/src/services/chatCompressionService.ts`

当对话历史太长时，自动压缩。这是 Gemini CLI 最重要的上下文管理机制之一。

---

#### 1.1 压缩触发机制

**触发条件**:
```typescript
// 默认配置常量
const DEFAULT_COMPRESSION_TOKEN_THRESHOLD = 0.5;  // 达到模型限制的50%时触发
const COMPRESSION_PRESERVE_THRESHOLD = 0.3;        // 保留最近30%的历史

// 触发判断
if (originalTokenCount >= threshold * tokenLimit(model)) {
  // 触发压缩
}
```

**两种触发方式**:
1. **自动触发**: Token数量达到阈值（默认50%）
2. **手动触发**: 用户通过命令强制压缩

---

#### 1.2 核心实现流程

##### TypeScript 实现

```typescript
async compress(
  chat: GeminiChat,
  promptId: string,
  force: boolean,  // 是否强制压缩
  model: string,
  config: Config,
  hasFailedCompressionAttempt: boolean,  // 是否之前失败过
): Promise<{ newHistory: Content[] | null; info: ChatCompressionInfo }>
```

**完整流程**:

```typescript
// 第1步: 前置检查
const curatedHistory = chat.getHistory(true);  // 获取精选历史

// 如果历史为空 或 之前失败过且非强制，直接返回
if (curatedHistory.length === 0 || (hasFailedCompressionAttempt && !force)) {
  return { newHistory: null, info: { compressionStatus: NOOP } };
}

// 第2步: 触发 PreCompress Hook
await firePreCompressHook(messageBus, force ? Manual : Auto);

// 第3步: 检查是否需要压缩
const originalTokenCount = chat.getLastPromptTokenCount();
if (!force && originalTokenCount < threshold * tokenLimit(model)) {
  return { newHistory: null, info: { compressionStatus: NOOP } };
}

// 第4步: 计算分割点（保留最近30%的历史）
const splitPoint = findCompressSplitPoint(
  curatedHistory,
  1 - COMPRESSION_PRESERVE_THRESHOLD,  // 0.7，即压缩70%
);

const historyToCompress = curatedHistory.slice(0, splitPoint);
const historyToKeep = curatedHistory.slice(splitPoint);

// 第5步: 调用LLM生成压缩摘要
const summaryResponse = await config.getBaseLlmClient().generateContent({
  modelConfigKey: { model: 'chat-compression-2.5-pro' },
  contents: [
    ...historyToCompress,
    {
      role: 'user',
      parts: [{
        text: 'First, reason in your scratchpad. Then, generate the <state_snapshot>.'
      }]
    }
  ],
  systemInstruction: { text: getCompressionPrompt() },  // 专门的压缩提示词
});
const summary = getResponseText(summaryResponse) ?? '';

// 第6步: 构建新历史
const extraHistory: Content[] = [
  {
    role: 'user',
    parts: [{ text: summary }],  // 压缩后的摘要
  },
  {
    role: 'model',
    parts: [{ text: 'Got it. Thanks for the additional context!' }],
  },
  ...historyToKeep,  // 保留的最近历史
];

// 第7步: 计算新的Token数量
const fullNewHistory = await getInitialChatHistory(config, extraHistory);
const newTokenCount = await calculateRequestTokenCount(
  fullNewHistory.flatMap((c) => c.parts || []),
  config.getContentGenerator(),
  model,
);

// 第8步: 验证压缩效果
if (newTokenCount > originalTokenCount) {
  // 压缩失败：Token反而增加了！
  return {
    newHistory: null,
    info: {
      compressionStatus: COMPRESSION_FAILED_INFLATED_TOKEN_COUNT,
      originalTokenCount,
      newTokenCount,
    }
  };
} else {
  // 压缩成功
  return {
    newHistory: extraHistory,
    info: {
      compressionStatus: COMPRESSED,
      originalTokenCount,
      newTokenCount,
    }
  };
}
```

---

#### 1.3 分割点计算算法

**目标**: 找到一个合适的分割点，既能压缩足够多的历史，又不会破坏对话结构。

```typescript
function findCompressSplitPoint(
  contents: Content[],
  fraction: number,  // 要压缩的比例（0.7 = 70%）
): number {
  const charCounts = contents.map(c => JSON.stringify(c).length);
  const totalCharCount = charCounts.reduce((a, b) => a + b, 0);
  const targetCharCount = totalCharCount * fraction;

  let lastSplitPoint = 0;
  let cumulativeCharCount = 0;
  
  for (let i = 0; i < contents.length; i++) {
    const content = contents[i];
    
    // 只能在用户消息处分割（且不能是工具响应）
    if (
      content.role === 'user' &&
      !content.parts?.some(part => !!part.functionResponse)
    ) {
      if (cumulativeCharCount >= targetCharCount) {
        return i;  // 找到合适的分割点
      }
      lastSplitPoint = i;
    }
    
    cumulativeCharCount += charCounts[i];
  }

  // 检查是否可以压缩全部历史
  const lastContent = contents[contents.length - 1];
  if (
    lastContent?.role === 'model' &&
    !lastContent?.parts?.some(part => part.functionCall)
  ) {
    return contents.length;  // 可以压缩所有
  }

  return lastSplitPoint;  // 返回最后一个有效分割点
}
```

**关键规则**:
1. **只能在用户消息处分割**: 保持对话完整性
2. **不能分割工具响应**: `functionResponse` 必须和前面的 `functionCall` 配对
3. **不能在工具调用处结束**: 如果最后是 `functionCall`，不能压缩到这里

---

#### 1.4 压缩提示词 (Compression Prompt)

这是压缩的核心！使用专门设计的提示词引导模型生成结构化摘要。

**完整提示词**:

```xml
You are the component that summarizes internal chat history into a given structure.

When the conversation history grows too large, you will be invoked to distill 
the entire history into a concise, structured XML snapshot. This snapshot is 
CRITICAL, as it will become the agent's *only* memory of the past. The agent 
will resume its work based solely on this snapshot. All crucial details, plans, 
errors, and user directives MUST be preserved.

First, you will think through the entire history in a private <scratchpad>. 
Review the user's overall goal, the agent's actions, tool outputs, file 
modifications, and any unresolved questions. Identify every piece of information 
that is essential for future actions.

After your reasoning is complete, generate the final <state_snapshot> XML object. 
Be incredibly dense with information. Omit any irrelevant conversational filler.

The structure MUST be as follows:

<state_snapshot>
    <overall_goal>
        <!-- A single, concise sentence describing the user's high-level objective. -->
        <!-- Example: "Refactor the authentication service to use a new JWT library." -->
    </overall_goal>

    <key_knowledge>
        <!-- Crucial facts, conventions, and constraints the agent must remember. -->
        <!-- Example:
         - Build Command: `npm run build`
         - Testing: Tests are run with `npm test`. Test files must end in `.test.ts`.
         - API Endpoint: The primary API endpoint is `https://api.example.com/v2`.
        -->
    </key_knowledge>

    <file_system_state>
        <!-- List files that have been created, read, modified, or deleted. -->
        <!-- Example:
         - CWD: `/home/user/project/src`
         - READ: `package.json` - Confirmed 'axios' is a dependency.
         - MODIFIED: `services/auth.ts` - Replaced 'jsonwebtoken' with 'jose'.
         - CREATED: `tests/new-feature.test.ts` - Initial test structure.
        -->
    </file_system_state>

    <recent_actions>
        <!-- A summary of the last few significant agent actions and their outcomes. -->
        <!-- Example:
         - Ran `grep 'old_function'` which returned 3 results in 2 files.
         - Ran `npm run test`, which failed due to a snapshot mismatch.
         - Ran `ls -F static/` and discovered image assets are stored as `.webp`.
        -->
    </recent_actions>

    <current_plan>
        <!-- The agent's step-by-step plan. Mark completed steps. -->
        <!-- Example:
         1. [DONE] Identify all files using the deprecated 'UserAPI'.
         2. [IN PROGRESS] Refactor `src/components/UserProfile.tsx`.
         3. [TODO] Refactor the remaining files.
         4. [TODO] Update tests to reflect the API change.
        -->
    </current_plan>
</state_snapshot>
```

**设计亮点**:
1. **结构化输出**: XML格式便于解析和验证
2. **多维度信息**: 目标、知识、文件状态、行动、计划
3. **Scratchpad思考**: 让模型先推理再总结，提高质量
4. **密集信息**: 强调"incredibly dense"，避免废话

##### 关键技术：Scratchpad（暂存板）机制

**什么是 Scratchpad？**

Scratchpad 是一种 **Chain-of-Thought (CoT) 提示技术**，让 LLM 在给出最终答案前，先在"草稿纸"上进行**私有推理**。

**核心概念**：

```xml
<scratchpad>
  这里是 LLM 的"内心独白"
  - 分析问题
  - 整理信息
  - 推理逻辑
  - 自我质疑
  （这部分内容会被丢弃，不会进入最终输出）
</scratchpad>

<state_snapshot>
  这里是最终的结构化输出
  （这部分才是真正需要的结果）
</state_snapshot>
```

**在压缩中的应用**：

看代码第 **188-189 行**：

```typescript:186-189:packages/core/src/services/chatCompressionService.ts
parts: [
  {
    text: 'First, reason in your scratchpad. Then, generate the <state_snapshot>.',
  },
]
```

以及 System Prompt 第 **399 行**：

```typescript:399:packages/core/src/core/prompts.ts
First, you will think through the entire history in a private <scratchpad>. 
Review the user's overall goal, the agent's actions, tool outputs, file 
modifications, and any unresolved questions. Identify every piece of information 
that is essential for future actions.
```

**工作流程**：

```
1. LLM 收到压缩任务
   ↓
2. 在 <scratchpad> 中思考：
   - "用户的总体目标是什么？"
   - "关键的技术栈信息有哪些？"
   - "哪些文件被修改了？为什么？"
   - "当前卡在哪一步？"
   - "什么信息是必须保留的？"
   ↓
3. 思考完成后，生成 <state_snapshot>
   - 只包含提炼后的关键信息
   - 结构化、密集、无废话
```

**实际示例**：

假设要压缩 70 轮对话（创建 React 登录功能），LLM 的输出可能是：

```xml
<scratchpad>
让我回顾整个对话历史...

用户的目标：在现有 React 项目中添加登录功能

关键信息：
- 项目使用 React 18.2 + TypeScript 5.0
- 测试命令是 npm test
- API 地址是 https://api.example.com

文件操作：
- 读取了 package.json (确认依赖)
- 创建了 Login.tsx (登录组件)
- 修改了 App.tsx (添加路由)
- 创建了 auth.test.ts (测试)

最近动作：
- 运行了 npm test，12个测试通过
- 发现需要添加 JWT 存储
- 用户要求添加受保护路由

当前计划：
- ✅ 创建登录组件 (已完成)
- ✅ 添加路由 (已完成)
- ⏸️ JWT 存储 (待做)
- ⏸️ 受保护路由 (待做)

必须保留的信息已梳理清楚，现在生成最终摘要...
</scratchpad>

<state_snapshot>
  <overall_goal>在 React 项目中实现完整的登录认证系统</overall_goal>
  
  <key_knowledge>
    - React 18.2, TypeScript 5.0
    - Test command: npm test
    - API: https://api.example.com
  </key_knowledge>
  
  <file_system_state>
    - CWD: /home/user/project/src
    - READ: package.json - Confirmed 'react-router-dom' available
    - CREATED: components/Login.tsx - Basic login form with validation
    - MODIFIED: App.tsx - Added routing logic
    - CREATED: tests/auth.test.ts - 12 tests passing
  </file_system_state>
  
  <recent_actions>
    - Created Login component with email/password validation
    - Added React Router v6 integration
    - Ran tests: 12/12 passing
  </recent_actions>
  
  <current_plan>
    1. [DONE] Create Login component
    2. [DONE] Add routing
    3. [TODO] Implement JWT storage in localStorage
    4. [TODO] Add protected route wrapper component
  </current_plan>
</state_snapshot>
```

**为什么需要 Scratchpad？**

| 优势 | 说明 |
|------|------|
| **提高质量** | 通过显式推理，减少遗漏关键信息 |
| **结构化思考** | 强制 LLM 系统性地审查历史 |
| **避免幻觉** | 先思考再输出，减少随意编造 |
| **可调试** | 如果压缩质量差，可以查看 scratchpad 找原因 |
| **模拟人类** | 类似人类做笔记时先草稿再正式写 |

**Scratchpad 在其他场景的应用**：

1. **Codebase Investigator Agent** (代码库调查子 Agent):

```typescript:113-122:packages/core/src/agents/codebase-investigator.ts
## Scratchpad Management
**This is your most critical function. Your scratchpad is your memory and your plan.**
1. **Initialization:** On your very first turn, you **MUST** create the `<scratchpad>` section.
2. **Constant Updates:** After **every** `<OBSERVATION>`, you **MUST** update the scratchpad.
   * Mark checklist items as complete: `[x]`.
   * Add new checklist items as you trace the architecture.
   * **Explicitly log questions in `Questions to Resolve`**
   * Record `Key Findings` with file paths and notes
   * Update `Irrelevant Paths to Ignore` to avoid re-investigating dead ends.
3. **Thinking on Paper:** The scratchpad must show your reasoning process
```

在这个 Agent 中，scratchpad 用作：
- **任务清单**：追踪调查进度
- **问题列表**：记录未解决的疑问
- **关键发现**：记录重要代码位置
- **思维日志**：展示推理过程

**总结**：

Scratchpad 是一种简单但强大的技术，通过在 XML 标签中"思考"，让 LLM 的输出更可靠、更结构化。在压缩场景中，它确保了摘要的全面性和准确性。

---

#### 1.5 压缩状态管理

**状态枚举**:

```typescript
enum CompressionStatus {
  COMPRESSED = 1,                           // 压缩成功
  COMPRESSION_FAILED_INFLATED_TOKEN_COUNT,  // 失败：Token反增
  NOOP,                                     // 无需压缩
}

interface ChatCompressionInfo {
  originalTokenCount: number;
  newTokenCount: number;
  compressionStatus: CompressionStatus;
}
```

**在 GeminiClient 中的集成**:

```typescript
class GeminiClient {
  private hasFailedCompressionAttempt = false;  // 失败标记
  
  async tryCompressChat(
    prompt_id: string,
    force: boolean = false,
  ): Promise<ChatCompressionInfo> {
    const { newHistory, info } = await this.compressionService.compress(
      this.getChat(),
      prompt_id,
      force,
      model,
      this.config,
      this.hasFailedCompressionAttempt,
    );

    if (info.compressionStatus === COMPRESSION_FAILED_INFLATED_TOKEN_COUNT) {
      // 记录失败（除非是强制压缩）
      this.hasFailedCompressionAttempt = !force;
    } else if (info.compressionStatus === COMPRESSED) {
      if (newHistory) {
        // 替换聊天历史
        this.chat = await this.startChat(newHistory);
        this.updateTelemetryTokenCount();
        this.forceFullIdeContext = true;  // 强制重新发送IDE上下文
      }
    }

    return info;
  }
}
```

**失败保护机制**:
- 如果压缩失败（Token反增），标记 `hasFailedCompressionAttempt = true`
- 后续自动压缩会跳过，直到用户强制压缩
- 避免陷入"压缩-失败-再压缩"的死循环

---

#### 1.6 压缩示例

**压缩前历史**（约1000个Token）:

```json
[
  { "role": "user", "parts": [{"text": "Read package.json"}] },
  { "role": "model", "parts": [{"functionCall": {...}}] },
  { "role": "tool", "parts": [{"functionResponse": {"content": "..."}}] },
  { "role": "model", "parts": [{"text": "I see you have React 18..."}] },
  { "role": "user", "parts": [{"text": "Add a new component"}] },
  { "role": "model", "parts": [{"functionCall": {...}}] },
  // ... 大量历史 ...
  { "role": "user", "parts": [{"text": "Run tests"}] },
  { "role": "model", "parts": [{"text": "Let me run the tests..."}] }
]
```

**压缩后历史**（约400个Token）:

```json
[
  {
    "role": "user",
    "parts": [{
      "text": "<state_snapshot>\n  <overall_goal>Add authentication to React app</overall_goal>\n  <key_knowledge>\n    - React 18.2, TypeScript 5.0\n    - Test with: npm test\n    - API: https://api.example.com\n  </key_knowledge>\n  <file_system_state>\n    - READ: package.json, src/App.tsx\n    - CREATED: src/components/Login.tsx\n    - MODIFIED: src/index.tsx - Added routing\n  </file_system_state>\n  <recent_actions>\n    - Created Login component with form validation\n    - Added React Router v6\n    - Tests passing (12/12)\n  </recent_actions>\n  <current_plan>\n    1. [DONE] Create Login component\n    2. [DONE] Add routing\n    3. [TODO] Implement JWT storage\n    4. [TODO] Add protected routes\n  </current_plan>\n</state_snapshot>"
    }]
  },
  {
    "role": "model",
    "parts": [{"text": "Got it. Thanks for the additional context!"}]
  },
  // 保留最近30%的原始历史
  { "role": "user", "parts": [{"text": "Run tests"}] },
  { "role": "model", "parts": [{"text": "Let me run the tests..."}] }
]
```

**压缩效果**:
- **Token减少**: 1000 → 400（60%压缩率）
- **信息保留**: 所有关键信息都在XML摘要中
- **上下文连续**: 保留最近对话，过渡自然

##### 为什么需要 "Got it" 消息？

这条看似简单的确认消息有 **4 个关键作用**：

**1. 保持对话结构的完整性** 🔄

```typescript
// ❌ 如果没有 "Got it"
[
  { role: 'user', parts: [{ text: '<state_snapshot>...' }] },  // 摘要
  { role: 'user', parts: [{ text: 'Run tests' }] },           // 连续两个user！违反格式
]

// ✅ 有了 "Got it"
[
  { role: 'user', parts: [{ text: '<state_snapshot>...' }] },        // 摘要
  { role: 'model', parts: [{ text: 'Got it. Thanks...' }] },        // model回应
  { role: 'user', parts: [{ text: 'Run tests' }] },                 // user继续
]
```

**原因**: `historyToKeep`（保留的最近30%历史）很可能以 `user` 消息开头，因为分割点算法倾向于在用户消息处分割。如果没有 model 的回应，就会出现两个连续的 user 消息，违反 Gemini API 的对话格式要求。

**2. 模拟自然的对话流程** 💬

从 LLM 的角度看，摘要是用户提供的**新上下文信息**，model 应该确认收到：

```
User: "Here's what happened before: <state_snapshot>..."
Model: "Got it. Thanks for the additional context!"  ← 表示理解了上下文
User: "Now run the tests..."
Model: "Sure, let me run the tests..."
```

这让对话更**自然、连贯**，避免了突兀的信息注入。

**3. 符合 Gemini API 的对话模型设计** ⚙️

从 `extractCuratedHistory` 的实现可以看出，对话历史是按 **user-model 对** 来组织的：

```typescript:151-178:packages/core/src/core/geminiChat.ts
function extractCuratedHistory(comprehensiveHistory: Content[]): Content[] {
  while (i < length) {
    if (comprehensiveHistory[i].role === 'user') {
      curatedHistory.push(comprehensiveHistory[i]);  // user消息直接加入
      i++;
    } else {
      // model消息需要成对出现并验证有效性
      const modelOutput: Content[] = [];
      while (i < length && comprehensiveHistory[i].role === 'model') {
        modelOutput.push(comprehensiveHistory[i]);
        // 验证model消息的有效性
        i++;
      }
      if (isValid) {
        curatedHistory.push(...modelOutput);
      }
    }
  }
}
```

这表明每个 user 消息后应该跟随 model 的回应，形成完整的对话轮次。

**4. 防止语义混淆** 🎭

如果没有确认消息，LLM 可能无法正确理解摘要与后续对话的关系：

```typescript
// ❌ 没有确认，语义不清晰
[
  { role: 'user', parts: [{ text: '<state_snapshot>包含了bug信息</state_snapshot>' }] },
  { role: 'user', parts: [{ text: 'Fix the bug' }] }  // LLM可能困惑：这是新话题还是延续？
]

// ✅ 有确认，语义明确
[
  { role: 'user', parts: [{ text: '<state_snapshot>包含了bug信息</state_snapshot>' }] },
  { role: 'model', parts: [{ text: 'Got it. Thanks for the additional context!' }] },
  { role: 'user', parts: [{ text: 'Fix the bug' }] }  // LLM清楚：之前的摘要已确认，现在执行任务
]
```

**总结**: "Got it" 消息是**对话状态管理**中的关键粘合剂，确保压缩后的历史在结构、语义和 API 兼容性上都是正确的。

---

#### 1.7 多次压缩机制（递归压缩）

**重要特性**: 压缩会将之前的摘要 + 新的历史对话一起重新压缩！

##### 第一次压缩

假设有 1000 条消息，Token 超过阈值：

```typescript
// 原始历史
curatedHistory = [消息1, 消息2, ..., 消息1000]

// 计算分割点（压缩70%）
splitPoint = 700
historyToCompress = [消息1 ~ 消息700]    // 前70%压缩
historyToKeep = [消息701 ~ 消息1000]      // 后30%保留

// 调用LLM压缩
summary_1 = compress(消息1 ~ 消息700)

// 新历史结构
newHistory = [
  { role: 'user', parts: [{ text: summary_1 }] },        // 压缩摘要
  { role: 'model', parts: [{ text: 'Got it...' }] },    // 确认消息
  消息701, 消息702, ..., 消息1000                         // 保留的历史
]
```

**结果**: `摘要1 + 300条消息`

##### 第二次压缩

继续对话，又生成了 500 条新消息，再次触发压缩：

```typescript
// 当前历史（包含上次的摘要！）
curatedHistory = [
  { role: 'user', parts: [{ text: summary_1 }] },        // 上次的摘要
  { role: 'model', parts: [{ text: 'Got it...' }] },
  消息701, 消息702, ..., 消息1500                         // 后续所有对话
]

// 计算分割点（压缩70%）
splitPoint = 560  // 约70%的位置
historyToCompress = [
  summary_1,                                             // 包含上次摘要！
  确认消息,
  消息701 ~ 消息1140
]
historyToKeep = [消息1141 ~ 消息1500]                    // 后30%保留

// 再次调用LLM压缩（将摘要+历史一起压缩）
summary_2 = compress([summary_1, 确认消息, 消息701 ~ 消息1140])

// 新历史结构
newHistory = [
  { role: 'user', parts: [{ text: summary_2 }] },        // 新的压缩摘要
  { role: 'model', parts: [{ text: 'Got it...' }] },
  消息1141, 消息1142, ..., 消息1500                       // 保留的历史
]
```

**结果**: `摘要2 (包含了摘要1的内容) + 360条消息`

##### 关键代码证据

```typescript:166-167:packages/core/src/services/chatCompressionService.ts
// 获取的是完整的当前历史
const historyToCompress = curatedHistory.slice(0, splitPoint);
const historyToKeep = curatedHistory.slice(splitPoint);
```

**curatedHistory** 始终包含：
- **如果有过压缩**: 上次的摘要消息对（user role + model role）
- **所有后续的对话历史**

所以每次压缩都会：
1. 将 **上次摘要 + 新对话** 一起送给 LLM
2. LLM 生成一个 **新的综合摘要**
3. **旧摘要被新摘要替换**

##### 压缩次数示例

| 压缩次数 | 输入内容 | 输出摘要 | 效果 |
|---------|---------|---------|------|
| 第1次 | 消息1-700 | 摘要1 | 初始压缩 |
| 第2次 | **摘要1** + 消息701-1140 | **摘要2** | 摘要递归 |
| 第3次 | **摘要2** + 消息1141-1580 | **摘要3** | 再次递归 |
| 第N次 | **摘要N-1** + 新消息 | **摘要N** | 持续递归 |

##### 递归压缩的优势

1. **信息累积**: 每次新摘要都包含历史摘要的精华
2. **Token控制**: 始终保持在阈值以下
3. **无限对话**: 理论上可以支持无限长的对话
4. **上下文连贯**: 重要信息不会丢失，会在摘要中传递

##### 递归压缩的挑战

1. **信息衰减**: 多次压缩后，早期细节可能被过度抽象
2. **摘要质量**: 依赖LLM的理解能力，可能出现偏差
3. **压缩失败**: 如果新摘要比旧摘要+历史还大，会拒绝压缩

---

#### 1.8 性能优化技巧

1. **使用轻量级模型**: 压缩时使用 `gemini-2.5-flash`，更快更便宜
2. **批量压缩**: 只在必要时压缩，避免频繁调用
3. **失败缓存**: 记录失败状态，避免重复尝试
4. **增量压缩**: 只压缩旧历史，保留最近30%

---

#### 1.9 压缩的挑战与解决方案

| 挑战 | 解决方案 |
|------|---------|
| **信息丢失** | 结构化XML格式，强制包含关键信息 |
| **压缩失败** | Token反增时拒绝压缩，标记失败状态 |
| **破坏对话** | 智能分割点算法，只在安全位置切割 |
| **性能开销** | 使用Flash模型，异步压缩 |
| **多轮对话** | 保留最近30%历史，保持连续性 |

---

#### 1.10 压缩时机

在 `GeminiClient.sendMessageStream()` 中：

```typescript
// Agent Loop 开始前检查
const compressionInfo = await this.tryCompressChat(prompt_id, false);

if (compressionInfo.compressionStatus === CompressionStatus.COMPRESSED) {
  // 发送压缩事件给UI
  yield {
    type: GeminiEventType.ChatCompressed,
    value: compressionInfo,
  };
}
```

**时机选择**:
- 在每轮对话**之前**检查
- 在调用API**之前**压缩
- 确保模型总是使用压缩后的上下文

---

### 小结

历史压缩是 Gemini CLI 处理长对话的核心机制：

1. **自动触发**: 超过50%的Token限制时
2. **智能分割**: 保留30%最近历史
3. **结构化摘要**: 使用XML格式的5个维度
4. **安全验证**: Token反增则拒绝压缩
5. **失败保护**: 避免无限重试

这种设计让 Agent 能够进行长时间、多轮次的复杂任务，而不会因为上下文限制而失败。

---

## 五、System Prompt 结构详解

### 5.1 概述

每次单轮执行时，发送给 LLM 的 System Prompt 由多个模块化的部分组成，动态根据配置和环境生成。

**生成函数**: `getCoreSystemPrompt(config, userMemory)`  
**位置**: `packages/core/src/core/prompts.ts`

### 5.2 完整结构

System Prompt 由以下**有序模块**组成：

```typescript
const orderedPrompts = [
  'preamble',              // 序言：Agent 角色定义
  'coreMandates',          // 核心规则：编码约定、库使用、风格等
  'primaryWorkflows',      // 主要工作流：软件工程任务、新应用开发
  'operationalGuidelines', // 操作指南：Shell优化、语气风格、安全规则
  'sandbox',               // 沙盒信息：运行环境限制
  'git',                   // Git规则：提交规范、命令使用
  'finalReminder',         // 最终提醒：核心职能总结
]
```

最后附加 **User Memory**（用户记忆）。

---

### 5.3 各模块详解

#### 1. Preamble（序言）

定义 Agent 的基本身份和目标。

```text
You are <interactive/non-interactive> CLI agent specializing in software 
engineering tasks. Your primary goal is to help users safely and efficiently, 
adhering strictly to the following instructions and utilizing your available tools.
```

**动态部分**：
- Interactive mode：用户可交互，可以问问题
- Non-interactive mode：自主完成任务，不等待用户输入

---

#### 2. Core Mandates（核心规则）

最重要的行为准则，约束 Agent 的所有操作。

**关键规则**：

```markdown
# Core Mandates

- **Conventions:** 严格遵守项目现有约定
- **Libraries/Frameworks:** 永远不要假设库可用，必须验证
- **Style & Structure:** 模仿现有代码风格和架构模式
- **Idiomatic Changes:** 确保修改自然融入代码
- **Comments:** 谨慎添加注释，只解释"为什么"
- **Proactiveness:** 主动添加测试确保质量
- **Confirm Ambiguity:** (交互模式) 模糊请求时先确认
- **Handle Ambiguity:** (非交互模式) 不超出请求范围
- **Explaining Changes:** 完成修改后不提供总结(除非被问)
- **Do Not revert changes:** 不要回退更改(除非出错或被要求)
- **Do not call tools in silence:** (Gemini 3) 调用工具前简短说明
- **Continue the work:** (非交互模式) 尽力完成，不问用户
```

还包括 **Agent Registry 的目录上下文**（如果有子 Agent 注册）。

---

#### 3. Primary Workflows（主要工作流）

定义两类核心任务的执行流程。

##### 3.1 Software Engineering Tasks（软件工程任务）

**根据配置有 4 种变体**：

| 变体 | 条件 | 特点 |
|------|------|------|
| `primaryWorkflows_prefix_ci_todo` | CodebaseInvestigator + TodoTool | 复杂任务先委托子Agent调查，使用Todo追踪 |
| `primaryWorkflows_prefix_ci` | 只有 CodebaseInvestigator | 复杂任务先委托子Agent调查 |
| `primaryWorkflows_todo` | 只有 TodoTool | 使用Todo分解任务 |
| `primaryWorkflows_prefix` | 两者都没有 | 基础流程 |

**标准流程**（以基础版为例）：

```markdown
1. **Understand:** 
   - 思考用户请求和代码库上下文
   - 使用 grep/glob/read_file 工具理解结构和约定
   - 并行调用多个工具

2. **Plan:** 
   - 基于理解构建连贯计划
   - 与用户分享简明计划
   - 包含迭代开发和单元测试

3. **Implement:** 
   - 使用 edit/write/shell 等工具
   - 严格遵守项目约定

4. **Verify (Tests):** 
   - 使用项目测试流程验证
   - 从 README/package.json 识别测试命令
   - 永远不要假设标准测试命令

5. **Verify (Standards):** 
   - ⚠️ 非常重要：运行项目的 build/lint/typecheck 命令
   - 确保代码质量和规范

6. **Finalize:** 
   - 验证通过后任务完成
   - 不删除或回退任何更改(包括测试文件)
```

**CodebaseInvestigator 变体的差异**：

```markdown
1. **Understand & Strategize:** 
   - 复杂重构/系统分析时，**首要行动**是委托给 CodebaseInvestigatorAgent
   - 简单搜索直接用 grep/glob
2. **Plan:** 
   - 如果使用了 CodebaseInvestigator，**必须**将其输出作为计划基础
```

##### 3.2 New Applications（新应用开发）

完整的应用程序开发工作流。

```markdown
**Goal:** 自主实现视觉吸引、功能完整的原型

1. **Understand Requirements:** 
   - 分析核心功能、UX、视觉、平台、约束
   - (交互模式) 缺少关键信息时提问

2. **Propose Plan:** 
   - 提供清晰的高级总结，包括：
     * 应用类型和核心目的
     * 关键技术栈
     * 主要功能和交互方式
     * 视觉设计和 UX 方法
     * 占位资源策略
   - 默认技术选择：
     * 前端: React/Angular + Bootstrap + Material Design
     * 后端: Node.js/Express 或 Python/FastAPI
     * 全栈: Next.js 或 Django/Flask + React
     * CLI: Python 或 Go
     * 移动: Compose Multiplatform 或 Flutter
     * 3D游戏: Three.js
     * 2D游戏: HTML/CSS/JavaScript

3. **User Approval:** (交互模式) 获取用户批准
   **Implementation:** (非交互模式) 直接开始

4. **Implementation:** 
   - 自主实现每个功能和设计元素
   - 使用 shell 脚手架 (npm init, create-react-app)
   - 主动创建/获取占位资源(图像、图标、精灵、3D模型)
   - 如果能生成简单资源(纯色方块、立方体)就生成
   - 标明占位符类型和替换建议

5. **Verify:** 
   - 对照原始请求和计划审查
   - 修复bug、偏差和占位符
   - 确保样式、交互、原型质量
   - ⚠️ 最重要：构建应用并确保无编译错误

6. **Solicit Feedback:** (交互模式) 提供启动说明并请求反馈
```

---

#### 4. Operational Guidelines（操作指南）

运行时的具体操作规范。

##### 4.1 Shell Tool Output Token Efficiency（可选）

如果 `config.getEnableShellOutputEfficiency()` 为 true：

```markdown
## Shell tool output token efficiency:

⚠️ 避免过度 Token 消耗的关键指南

- 优先使用减少输出的命令标志
- 最小化工具输出 Token，同时保留必要信息
- 预期输出多时使用 quiet/silent 标志
- 权衡输出详细度和信息需求
- 长输出重定向到临时文件: command > <temp_dir>/out.log 2> <temp_dir>/err.log
- 命令运行后用 grep/tail/head 检查临时文件
- 完成后删除临时文件
```

##### 4.2 Tone and Style（语气和风格）

```markdown
- **Concise & Direct:** 专业、直接、简洁的 CLI 风格
- **Minimal Output:** 每次回复尽量少于 3 行文本(工具调用/代码生成除外)
- **Clarity over Brevity:** 必要时优先清晰度
- **No Chitchat:** (Gemini 2.x) 避免闲聊、开场白、结束语
- **Formatting:** 使用 GitHub-flavored Markdown，等宽字体渲染
- **Tools vs. Text:** 工具用于操作，文本只用于沟通
- **Handling Inability:** 无法完成时简短说明(1-2句)，提供替代方案
```

##### 4.3 Security and Safety Rules

```markdown
- **Explain Critical Commands:** 
  修改文件系统/代码库/系统状态的命令前，必须简要说明目的和影响
  优先用户理解和安全
  不需要请求权限(用户会看到确认对话框)

- **Security First:** 
  应用安全最佳实践
  永远不要引入暴露/记录/提交密钥的代码
```

##### 4.4 Tool Usage

```markdown
- **Parallelism:** 独立工具调用并行执行
- **Command Execution:** 使用 shell 工具执行命令，记住安全规则
- **Background Processes:** 
  * (交互模式) 不太可能自行停止的命令用 &，不确定时问用户
  * (非交互模式) 不太可能自行停止的命令用 &
- **Interactive Commands:** 
  * (交互模式) 优先非交互命令，但有些命令只能交互(ssh/vim)
    执行交互命令时告知用户可按 ctrl+f 聚焦 shell 输入
  * (非交互模式) 只执行非交互命令
- **Remembering Facts:** 
  使用 memory 工具记住用户相关事实/偏好
  仅用于用户特定信息，不用于项目上下文
  (交互模式) 不确定时可以问"Should I remember that for you?"
- **Respect User Confirmations:** 
  用户取消工具调用时尊重选择，不再尝试
  仅当用户后续明确请求时才能再次调用
  用户取消时假设善意，询问是否有替代方案
```

##### 4.5 Interaction Details

```markdown
- **Help Command:** 用户可用 /help 显示帮助
- **Feedback:** 报告bug或反馈用 /bug 命令
```

---

#### 5. Sandbox（沙盒信息）

根据 `process.env.SANDBOX` 动态生成。

**3 种情况**：

**1. macOS Seatbelt (`SANDBOX=sandbox-exec`)**：

```markdown
# macOS Seatbelt
你在 macOS Seatbelt 下运行，项目目录外和系统临时目录外的文件访问受限，
主机资源(如端口)访问受限。

遇到可能由 Seatbelt 导致的失败(如 'Operation not permitted')时：
- 向用户报告错误
- 解释为什么可能是 Seatbelt 导致
- 说明用户可能需要调整 Seatbelt 配置
```

**2. 通用沙盒 (`SANDBOX=任意非空值`)**：

```markdown
# Sandbox
你在沙盒容器中运行，项目目录外和系统临时目录外的文件访问受限，
主机资源访问受限。

遇到可能由沙盒导致的失败时：
- 报告错误
- 解释为什么可能是沙盒导致
- 说明用户可能需要调整沙盒配置
```

**3. 沙盒外 (无 `SANDBOX` 环境变量)**：

```markdown
# Outside of Sandbox
你直接在用户系统上运行，未使用沙盒容器。

对于特别可能修改项目目录外或系统临时目录外的关键命令：
- 解释命令时(按照 Explain Critical Commands 规则)
- 提醒用户考虑启用沙盒
```

---

#### 6. Git（Git 规则）

如果当前目录是 Git 仓库，添加此模块。

```markdown
# Git Repository

当前工作目录由 Git 仓库管理

**提交准备流程**：
1. 使用 shell 命令收集信息：
   - git status: 确保所有相关文件被追踪和暂存，必要时 git add
   - git diff HEAD: 查看所有更改(包括未暂存)
     * git diff --staged: 只查看暂存更改(部分提交或用户要求时)
   - git log -n 3: 查看最近提交消息，匹配风格(详细度、格式、签名行等)

2. 尽可能合并 shell 命令节省时间/步骤：
   git status && git diff HEAD && git log -n 3

3. 总是提出草稿提交消息，永远不要只是让用户提供完整消息

4. 提交消息清晰、简洁，更侧重"为什么"而不是"什么"

5. (交互模式) 保持用户知情，必要时询问澄清或确认

6. 每次提交后运行 git status 确认成功

7. 提交失败时，永远不要在未被要求时尝试绕过问题

8. 永远不要在未被明确要求时推送到远程仓库
```

---

#### 7. Final Reminder（最终提醒）

总结核心职能。

```markdown
# Final Reminder

你的核心功能是高效和安全的协助。
平衡极致简洁与关键的清晰度需求，尤其关于安全和潜在系统修改。
始终优先用户控制和项目约定。
永远不要假设文件内容；而是使用 read_file 确保不做广泛假设。
最后，你是一个 Agent - 请持续进行直到用户查询完全解决。
```

---

#### 8. User Memory（用户记忆）

最后附加用户记忆(如果存在)。

```markdown
---

<用户记忆内容>
```

**来源**：
- JIT Context 模式：`config.getGlobalMemory()`
- 普通模式：`config.getUserMemory()`

---

### 5.4 动态生成逻辑

```typescript
// 根据配置选择工作流变体
if (enableCodebaseInvestigator && enableWriteTodosTool) {
  orderedPrompts.push('primaryWorkflows_prefix_ci_todo');
} else if (enableCodebaseInvestigator) {
  orderedPrompts.push('primaryWorkflows_prefix_ci');
} else if (enableWriteTodosTool) {
  orderedPrompts.push('primaryWorkflows_todo');
} else {
  orderedPrompts.push('primaryWorkflows_prefix');
}

// 过滤被禁用的模块
const enabledPrompts = orderedPrompts.filter((key) => {
  const envVar = process.env[`GEMINI_PROMPT_${key.toUpperCase()}`];
  return envVar !== '0' && envVar !== 'false';
});

// 拼接最终 prompt
basePrompt = enabledPrompts.map((key) => promptConfig[key]).join('\n');

// 添加用户记忆
return `${basePrompt}${memorySuffix}`;
```

---

### 5.5 自定义 System Prompt

**方式 1：通过环境变量覆盖**

```bash
export GEMINI_SYSTEM_MD=true          # 使用 ~/.gemini/system.md
export GEMINI_SYSTEM_MD=/path/to/custom.md  # 使用自定义文件
```

**方式 2：导出当前 System Prompt**

```bash
export GEMINI_WRITE_SYSTEM_MD=true    # 写入 ~/.gemini/system.md
export GEMINI_WRITE_SYSTEM_MD=/path/to/output.md  # 写入自定义路径
```

**方式 3：禁用特定模块**

```bash
export GEMINI_PROMPT_GIT=false         # 禁用 Git 规则
export GEMINI_PROMPT_SANDBOX=0         # 禁用沙盒信息
```

---

### 5.6 实际示例

**交互模式 + CodebaseInvestigator + TodoTool + Git 仓库**：

```markdown
You are an interactive CLI agent specializing in software engineering tasks...

# Core Mandates
- Conventions: ...
- Libraries/Frameworks: ...
[... 其他核心规则 ...]

# Primary Workflows

## Software Engineering Tasks
1. **Understand & Strategize:** 
   - 复杂任务时委托给 CodebaseInvestigatorAgent
   - 简单搜索直接用 grep/glob
2. **Plan:** 
   - 基于 CodebaseInvestigator 输出构建计划
   - 使用 write_todos 工具追踪进度
[... 后续步骤 ...]

## New Applications
[... 应用开发流程 ...]

# Operational Guidelines
## Tone and Style
- Concise & Direct: ...
[... 其他操作指南 ...]

## Security and Safety Rules
[... 安全规则 ...]

## Tool Usage
[... 工具使用规则 ...]

# Git Repository
- 当前工作目录由 Git 仓库管理
[... Git 规则 ...]

# Final Reminder
你的核心功能是高效和安全的协助...

---

用户偏好: 使用 4 空格缩进，优先 TypeScript
最近项目: ~/work/myproject
```

---

### 5.7 与 Gemini API 的交互

System Prompt 和工具声明分别通过不同参数传递给 Gemini API：

#### 1. System Instruction（文本指令）

```typescript
const systemInstruction = getCoreSystemPrompt(config, userMemory);

const chat = new GeminiChat(
  config,
  systemInstruction,  // ← System Prompt（文本）
  tools,              // ← 工具声明（结构化）
  history,
);

// 每次 API 调用时发送
await contentGenerator.generateContent({
  model: 'gemini-2.0-flash',
  config: {
    systemInstruction: { text: systemInstruction },  // 文本指令
    // ...
  },
  contents: history,
  tools: tools,  // 工具声明
});
```

**关键特性**：
- System Instruction 在整个会话中**持久存在**
- 每轮对话都会带上 System Instruction
- 可以通过 `setSystemInstruction()` 动态更新

---

#### 2. 工具声明（Function Declarations）

**重要说明**：工具的使用方法**不是**在 System Prompt 文本中描述的，而是通过 Gemini API 的 **`tools` 参数**传递的结构化 **Function Declarations**。

##### 工具声明的生成流程

```typescript:196-198:packages/core/src/core/client.ts
const toolRegistry = this.config.getToolRegistry();
const toolDeclarations = toolRegistry.getFunctionDeclarations();
const tools: Tool[] = [{ functionDeclarations: toolDeclarations }];
```

每个工具都实现了 `schema` 属性，返回 `FunctionDeclaration`：

```typescript:351-357:packages/core/src/tools/tools.ts
get schema(): FunctionDeclaration {
  return {
    name: this.name,                           // 工具名称
    description: this.description,             // 工具描述
    parametersJsonSchema: this.parameterSchema, // 参数 JSON Schema
  };
}
```

##### 实际示例：read_file 工具

```typescript
// ReadFileTool 的声明
{
  name: 'read_file',
  description: 'Reads a file from the local filesystem. You can access any file directly by using this tool.',
  parametersJsonSchema: {
    type: 'object',
    properties: {
      filePath: {
        type: 'string',
        description: 'REQUIRED: The path of the file to read. Must point to a specific file, NOT a directory.'
      },
      offset: {
        type: 'number',
        description: 'The line number to start reading from.'
      },
      limit: {
        type: 'number',
        description: 'The number of lines to read.'
      }
    },
    required: ['filePath']
  }
}
```

##### 工具声明传递给 API

```typescript
// GeminiChat 构造函数
const chat = model.startChat({
  systemInstruction: systemInstruction,  // 文本指令
  tools: [
    {
      functionDeclarations: [
        {
          name: 'read_file',
          description: 'Reads a file from the local filesystem...',
          parametersJsonSchema: { /* JSON Schema */ }
        },
        {
          name: 'search_content',
          description: 'A powerful search tool built on ripgrep...',
          parametersJsonSchema: { /* JSON Schema */ }
        },
        // ... 所有其他工具
      ]
    }
  ],
  history: history,
});
```

##### LLM 如何使用工具

Gemini API 会：
1. **理解 System Prompt**：知道自己是一个 CLI Agent，应该使用工具完成任务
2. **查看 Function Declarations**：知道有哪些工具可用、每个工具的功能和参数
3. **返回 Function Call**：当需要使用工具时，返回结构化的函数调用

```json
// LLM 的响应
{
  "candidates": [{
    "content": {
      "parts": [
        {
          "functionCall": {
            "name": "read_file",
            "args": {
              "filePath": "/path/to/file.txt",
              "offset": 10,
              "limit": 50
            }
          }
        }
      ]
    }
  }]
}
```

##### 工具声明的优势

| 特性 | 说明 |
|------|------|
| **结构化** | JSON Schema 精确定义参数类型和约束 |
| **类型安全** | LLM 知道参数的确切类型（string/number/boolean/object/array） |
| **自动验证** | Gemini API 会验证 LLM 返回的参数是否符合 Schema |
| **Token 高效** | 工具声明不占用 System Prompt 的 Token |
| **动态更新** | 可以运行时增删工具（通过 ToolRegistry） |
| **描述内嵌** | 每个参数都有 `description`，LLM 知道如何使用 |

##### 为什么不在 System Prompt 中描述工具？

**旧方法（不推荐）**：
```markdown
## Available Tools

1. **read_file**: Reads a file from the local filesystem.
   - Parameters:
     - filePath (string, required): The path of the file to read
     - offset (number, optional): The line number to start reading from
     - limit (number, optional): The number of lines to read
   
2. **search_content**: Search for text patterns using ripgrep...
```

**问题**：
- ❌ 占用大量 System Prompt Token
- ❌ 格式不统一，LLM 可能理解错误
- ❌ 无法自动验证参数
- ❌ 难以动态增删工具
- ❌ 描述冗长，影响其他指令的权重

**新方法（Function Declarations）**：
- ✅ 结构化传递，Gemini API 原生支持
- ✅ 自动类型检查和参数验证
- ✅ LLM 训练时已经优化了工具调用能力
- ✅ 不占用 System Prompt 的 Token 配额
- ✅ 可以动态注册/卸载工具

---

### 5.8 设计哲学

1. **模块化**：每个模块独立可禁用
2. **动态适配**：根据环境和配置调整
3. **安全优先**：明确的安全和确认规则
4. **项目感知**：Git、沙盒、项目约定
5. **用户可控**：交互/非交互模式切换
6. **扩展性**：易于添加新模块和规则

---

## 六、完整调用链示例

用户输入: `"Read the file test.txt and run tests"`

```
1. CLI入口 (gemini.tsx)
   ↓ 用户输入
   
2. GeminiClient.sendMessageStream()
   ↓ BeforeAgent Hook
   ↓ 创建Turn
   
3. Turn.run()
   ↓ 调用GeminiChat
   
4. GeminiChat.sendMessageStream()
   ↓ BeforeModel Hook
   ↓ 发送请求到Gemini API
   
5. Gemini API响应
   {
     "candidates": [{
       "content": {
         "parts": [
           { 
             "functionCall": { 
               "name": "read_file", 
               "args": { "file_path": "test.txt" }
             }
           },
           { 
             "functionCall": {
               "name": "shell",
               "args": { "command": "npm test" }
             }
           }
         ]
       }
     }]
   }
   ↓ AfterModel Hook
   
6. CoreToolScheduler.scheduleBatch()
   ↓ 验证工具调用
   ↓ BeforeTool Hook (read_file)
   ↓ 执行 ReadFileInvocation.execute()
   ↓ AfterTool Hook (read_file)
   ↓
   ↓ BeforeTool Hook (shell)
   ↓ 用户确认 (shell需要确认)
   ↓ 执行 ShellInvocation.execute()
   ↓ AfterTool Hook (shell)
   
7. 返回工具结果给API
   {
     "contents": [
       { "role": "model", "parts": [{ "functionCall": {...} }] },
       { "role": "tool", "parts": [
           { "functionResponse": { "name": "read_file", "response": {...} }},
           { "functionResponse": { "name": "shell", "response": {...} }}
       ]}
     ]
   }
   
8. API再次响应(第2轮)
   {
     "candidates": [{
       "content": {
         "parts": [
           { "text": "I've read test.txt and run the tests. All tests passed!" }
         ]
       }
     }]
   }
   
9. 检查 next_speaker = 'user'
   ↓ AfterAgent Hook
   ↓ 返回最终结果
```

---

## 七、与传统程序的区别

| 传统程序 | AI Agent |
|---------|----------|
| 固定流程 | 动态决策(LLM) |
| 直接函数调用 | 工具声明+API选择 |
| 单次执行 | 多轮对话循环 |
| 确定性输出 | 概率性输出 |
| 代码逻辑 | 自然语言指令 |

### 核心差异

- **决策权在模型**: 程序只提供工具，模型决定调用哪些工具
- **多轮交互**: 类似REPL，但每轮都可能执行多个操作
- **上下文累积**: 历史对话影响后续决策

---

## 八、学习建议

### 1. 学习路径

#### 阶段一：理解核心概念（1-2天）

1. **先看这份文档的前三章**
   - 整体架构概览
   - 核心工作流程 (Agent Loop)
   - 工具调用系统

2. **理解 LLM Agent 的本质**
   - Agent 不是传统程序，而是"LLM + 工具"的组合
   - LLM 负责决策（调用什么工具、传什么参数）
   - 程序负责执行（实现工具、返回结果）
   - 多轮对话循环是核心机制

3. **理解 Function Calling**
   - Gemini API 的 `tools` 参数（Function Declarations）
   - LLM 如何返回 `functionCall`
   - 程序如何执行工具并返回 `functionResponse`

#### 阶段二：深入核心实现（3-5天）

4. **阅读核心文件（按顺序）**
   1. `packages/core/src/core/client.ts` - Agent 主循环
   2. `packages/core/src/core/turn.ts` - 单轮执行逻辑
   3. `packages/core/src/tools/tools.ts` - 工具抽象层
   4. `packages/core/src/tools/read-file.ts` - 简单工具示例
   5. `packages/core/src/tools/shell.ts` - 复杂工具示例
   6. `packages/core/src/core/geminiChat.ts` - API 通信层
   7. `packages/core/src/core/coreToolScheduler.ts` - 工具调度器

5. **追踪一次完整调用**
   - 在关键点加 `console.log`
   - 观察：用户输入 → LLM 决策 → 工具执行 → 结果返回 → LLM 总结
   - 使用浏览器调试工具或 VSCode 调试器

6. **理解上下文管理（重点）**
   - 历史压缩的触发时机和算法
   - Scratchpad 和 "Got it" 消息的作用
   - Token 计数和限制机制

#### 阶段三：理解高级特性（3-5天）

7. **Hook 系统（切面编程）**
   - `packages/core/src/hooks/hookSystem.ts`
   - BeforeTool / AfterTool / BeforeAgent / AfterAgent
   - 实际应用场景：日志记录、权限控制、数据转换

8. **System Prompt 设计（Prompt 工程）**
   - 阅读第五章的完整内容
   - 理解每个模块的作用
   - 尝试修改 System Prompt 观察效果

9. **工具注册与动态管理**
   - `ToolRegistry` 的实现
   - 如何动态增删工具
   - 工具的依赖注入和生命周期

### 2. 实践建议

#### 动手实践 1：实现一个简单工具

```typescript
// 实现一个"计算器"工具
class CalculatorTool extends DeclarativeTool {
  name = 'calculator'
  description = 'Evaluate a mathematical expression'
  parameterSchema = {
    type: 'object',
    properties: {
      expression: {
        type: 'string',
        description: 'Mathematical expression to evaluate (e.g., "2 + 3 * 4")'
      }
    },
    required: ['expression']
  }

  async execute({ expression }: { expression: string }) {
    try {
      const result = eval(expression) // 注意：生产环境要用安全的 math parser
      return { result }
    } catch (error) {
      return { error: error.message }
    }
  }
}
```

#### 动手实践 2：追踪多轮对话

在 `client.ts` 的关键位置添加日志：

```typescript
// 在 runAgent() 中
console.log('=== Turn', turn, '===')
console.log('Current history length:', this.chat.getHistory().length)

// 在 turn.ts 中
console.log('LLM response:', response)
console.log('Function calls:', functionCalls)
```

然后运行一个复杂任务，观察：
- 每轮 LLM 的决策
- 工具的执行结果
- 历史的累积和压缩

#### 动手实践 3：自定义 System Prompt

创建一个自定义的 System Prompt：

```typescript
const customSystemPrompt = `
你是一个专注于代码审查的 AI 助手。
在执行任何文件操作前，你必须：
1. 先使用 read_file 读取文件
2. 分析代码质量和潜在问题
3. 给出改进建议
4. 征得用户同意后再修改

你的回复应该简洁、专业，重点关注代码质量。
`

const config = new Config({
  systemPrompt: customSystemPrompt,
  // ...
})
```

观察 Agent 的行为变化。

### 3. 关键技术点深入

#### 3.1 Agent Loop 的终止条件

理解这些条件：
- `next_speaker = 'user'`（LLM 认为任务完成）
- `maxTurns` 达到上限
- 用户中断 (Ctrl+C)
- 循环检测（LLM 重复相同的操作）

#### 3.2 工具系统的设计模式

- **Builder 模式**：`ToolBuilder` 构造复杂工具
- **Command 模式**：`ToolInvocation` 封装执行请求
- **策略模式**：不同工具有不同的执行策略
- **装饰器模式**：Hook 系统在工具外包装一层

#### 3.3 事件驱动架构

理解异步事件流：
```typescript
async function* runAgent() {
  yield { type: 'start' }
  for (const turn of turns) {
    yield { type: 'turn_start', turn }
    yield* executeTurn(turn)  // 嵌套的 Generator
    yield { type: 'turn_end', turn }
  }
  yield { type: 'end' }
}
```

### 4. 扩展阅读

#### 官方文档
- [Gemini API - Function Calling](https://ai.google.dev/docs/function_calling)
- [Prompt Engineering Guide](https://www.promptingguide.ai/)

#### 相关项目
- [LangChain](https://github.com/langchain-ai/langchain) - Python/JS 的 LLM 框架
- [AutoGPT](https://github.com/Significant-Gravitas/AutoGPT) - 自主 Agent 实现
- [OpenDevin](https://github.com/OpenDevin/OpenDevin) - 代码生成 Agent

#### 论文
- [ReAct: Synergizing Reasoning and Acting in Language Models](https://arxiv.org/abs/2210.03629)
- [Toolformer: Language Models Can Teach Themselves to Use Tools](https://arxiv.org/abs/2302.04761)

### 5. 常见问题

#### Q1: 为什么 Agent 有时会"死循环"？

**原因**：
- LLM 没有意识到任务已经完成
- 工具返回的结果不清晰，导致 LLM 重复尝试
- System Prompt 没有明确说明何时应该停止

**解决方案**：
- 实现循环检测机制（检测重复的工具调用）
- 优化工具的返回格式（明确的成功/失败消息）
- 在 System Prompt 中说明终止条件

#### Q2: 如何控制 Token 消耗？

**策略**：
- 启用历史压缩（自动）
- 限制工具返回的数据量（如文件只读取关键部分）
- 使用 Scratchpad 模式（中间结果不占历史）
- 设置 `maxContextTokens` 限制

#### Q3: 如何让 Agent 更"聪明"？

**方法**：
- 优化 System Prompt（更清晰的指令和示例）
- 改进工具的 `description`（让 LLM 知道何时用哪个工具）
- 在工具返回中包含更多上下文信息
- 使用 Hook 系统注入额外的推理步骤

#### Q4: 如何调试 Agent 的行为？

**技巧**：
- 打印每轮的 `history`（看 LLM 接收到了什么）
- 打印 `functionCall` 和 `functionResponse`（看工具调用）
- 使用 Hook 系统注入调试信息
- 查看 `messageBus` 的事件流

---

## 九、附录：内置工具列表

| 工具类别 | 工具名称 | 文件 | 功能 |
|---------|---------|------|------|
| **文件操作** | ReadFileTool | `read-file.ts` | 读取文件内容 |
| | WriteFileTool | `write-file.ts` | 写入文件 |
| | EditTool | `edit.ts` | 编辑文件（diff 模式）|
| | SmartEditTool | `smart-edit.ts` | 智能编辑（搜索替换）|
| **搜索** | GlobTool | `glob.ts` | 文件名匹配 |
| | GrepTool | `grep.ts` | 文本搜索 |
| | RipGrepTool | `ripGrep.ts` | 高性能搜索（使用 ripgrep）|
| **Shell** | ShellTool | `shell.ts` | 执行 shell 命令 |
| **Web** | WebFetchTool | `web-fetch.ts` | HTTP 请求 |
| | WebSearchTool | `web-search.ts` | 网络搜索 |
| **记忆** | MemoryTool | `memoryTool.ts` | 保存/检索记忆 |
| **MCP** | MCP 工具 | `mcp-tool.ts` | Model Context Protocol 集成 |

---

## 总结

Gemini CLI 的核心实现可以概括为：

1. **Agent Loop**: 多轮对话循环，直到任务完成
   - LLM 通过 `next_speaker` 控制循环终止
   - 每轮执行 Turn → 工具调用 → 结果返回

2. **Tool Calling**: 模型选择工具，程序执行工具
   - Function Declarations 定义工具（JSON Schema）
   - LLM 返回 `functionCall`，程序执行并返回 `functionResponse`
   - 支持并行调用多个工具

3. **Hook System**: 在关键节点拦截和修改行为
   - BeforeTool / AfterTool / BeforeAgent / AfterAgent
   - 切面编程思想，不侵入核心逻辑

4. **Context Management**: 管理历史、Token 限制
   - 历史压缩（递归压缩 + Scratchpad）
   - "Got it" 消息优化
   - Token 计数和限制

5. **System Prompt**: 指导 LLM 的行为准则
   - 多模块组合（工具调用、安全、规则等）
   - 与 Function Declarations 分离
   - 动态生成和自定义

### 核心设计思想

- **声明式编程**：工具通过 JSON Schema 声明，而非代码调用
- **事件驱动**：AsyncGenerator 实现流式事件处理
- **关注点分离**：System Prompt（指令）和 Function Declarations（工具）分离
- **可扩展性**：Hook 系统和 ToolRegistry 支持动态扩展

### 学习价值

理解 Gemini CLI 的实现，你将掌握：
- ✅ 如何构建 LLM Agent 系统
- ✅ Function Calling 的最佳实践
- ✅ Prompt 工程的实战技巧
- ✅ 复杂异步系统的架构设计
- ✅ 工具抽象和动态调度机制

希望这份文档能帮助你深入理解 Gemini CLI 的实现原理！🚀
