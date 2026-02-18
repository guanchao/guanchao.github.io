---
title: "OpenManus 核心实现原理深度剖析"
date: 2026-02-18
draft: false
description: "从源码层面深入分析 OpenManus 的核心实现机制，重点关注模块间关系、执行流程和关键设计决策，包括 ReAct 模式、工具调用、Prompt 系统、Flow 编排等核心设计。"
tags:
  - OpenManus
  - AI Agent
  - LLM
  - ReAct
  - 源码分析
categories:
  - Agent
  - AI
---

# OpenManus 核心实现原理深度剖析

> 本文从源码层面深入分析 OpenManus 的核心实现机制，重点关注模块间关系、执行流程和关键设计决策。

---

## 项目信息

| 项目 | 信息 |
|------|------|
| **GitHub 仓库** | [https://github.com/FoundationAgents/OpenManus](https://github.com/FoundationAgents/OpenManus) |
| **版本** | v0.1.0 |
| **许可证** | MIT License |
| **Python 版本** | 3.11 - 3.13（推荐 3.12） |
| **作者** | mannaandpoem and OpenManus Team (来自 MetaGPT) |
| **核心依赖** | pydantic, openai, browser-use, tenacity |

---

## 目录

- [一、核心架构概览](#一核心架构概览)
- [二、类继承体系：从抽象到具体](#二类继承体系从抽象到具体)
  - [2.1 Agent 继承链](#21-agent-继承链)
  - [2.2 Tool 继承链](#22-tool-继承链)
- [三、核心数据结构](#三核心数据结构)
  - [3.1 Message：对话的原子单位](#31-message对话的原子单位)
  - [3.2 Memory：Agent 的"世界观"](#32-memoryagent-的世界观)
  - [3.3 AgentState：状态机](#33-agentstate状态机)
- [四、Prompt 系统：Agent 的"灵魂"](#四prompt-系统agent-的灵魂)
  - [4.1 Prompt 架构设计](#41-prompt-架构设计)
  - [4.2 Prompt 与 Agent 的绑定机制](#42-prompt-与-agent-的绑定机制)
  - [4.3 Prompt 注入流程（核心代码分析）](#43-prompt-注入流程核心代码分析)
  - [4.4 动态 Prompt：BrowserAgent 的高级用法](#44-动态-promptbrowseragent-的高级用法)
  - [4.5 Manus 的 Prompt 动态切换](#45-manus-的-prompt-动态切换)
  - [4.6 PlanningFlow 的 Prompt 设计](#46-planningflow-的-prompt-设计)
  - [4.7 各 Agent 的 System Prompt 对比](#47-各-agent-的-system-prompt-对比)
  - [4.8 Prompt 设计原则总结](#48-prompt-设计原则总结)
  - [4.9 为什么 next_step_prompt 不放到 System Prompt？](#49-为什么-next_step_prompt-不放到-system-prompt)
- [五、核心执行流程剖析](#五核心执行流程剖析)
  - [4.1 主循环：BaseAgent.run()](#41-主循环baseagentrun)
  - [4.2 ReAct 模式：think() + act()](#42-react-模式think--act)
  - [4.3 工具调用核心：ToolCallAgent](#43-工具调用核心toolcallagent)
- [六、LLM 抽象层：统一的"大脑"接口](#六llm-抽象层统一的大脑接口)
  - [6.1 单例模式 + 多后端支持](#61-单例模式--多后端支持)
  - [6.2 核心方法：ask_tool()](#62-核心方法ask_tool)
- [七、工具系统：能力的载体](#七工具系统能力的载体)
  - [7.1 BaseTool：工具的统一接口](#71-basetool工具的统一接口)
  - [7.2 ToolCollection：工具的管理器](#72-toolcollection工具的管理器)
  - [7.3 典型工具实现：BrowserUseTool](#73-典型工具实现browserusetool)
- [八、Flow 层：多 Agent 编排](#八flow-层多-agent-编排)
  - [8.1 PlanningFlow：计划驱动的执行](#81-planningflow计划驱动的执行)
  - [8.2 计划创建过程](#82-计划创建过程)
- [九、完整执行流程图](#九完整执行流程图)
- [十、关键设计模式总结](#十关键设计模式总结)
- [十一、核心文件速查表](#十一核心文件速查表)
- [十二、扩展指南](#十二扩展指南)
- [总结](#总结)

---

## 一、核心架构概览

OpenManus 的本质是一个 **ReAct 模式的 AI Agent 框架**，其核心思想可以用一句话概括：

**"LLM 负责思考决策，工具负责执行动作，Memory 负责维护上下文，状态机负责控制流程"**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           OpenManus 核心架构                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│    ┌──────────────┐      ┌──────────────┐      ┌──────────────┐            │
│    │   入口层     │      │   Agent 层   │      │   工具层     │            │
│    │              │      │              │      │              │            │
│    │  main.py    │─────▶│  Manus       │─────▶│ ToolCollection│           │
│    │  run_flow.py│      │  ToolCallAgent│     │ BaseTool      │           │
│    │  run_mcp.py │      │  ReActAgent  │      │ BrowserUse    │           │
│    │              │      │  BaseAgent   │      │ PythonExecute │           │
│    └──────────────┘      └──────┬───────┘      └──────────────┘            │
│                                 │                                          │
│                                 │                                          │
│                    ┌────────────┼────────────┐                             │
│                    │            │            │                             │
│                    ▼            ▼            ▼                             │
│            ┌──────────┐  ┌──────────┐  ┌──────────┐                        │
│            │  Memory  │  │   LLM    │  │  State   │                        │
│            │          │  │          │  │ Machine  │                        │
│            │ messages │  │ ask_tool │  │ IDLE     │                        │
│            │ history  │  │ ask      │  │ RUNNING  │                        │
│            │          │  │          │  │ FINISHED │                        │
│            └──────────┘  └──────────┘  └──────────┘                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 二、类继承体系：从抽象到具体

### 2.1 Agent 继承链

OpenManus 采用了**模板方法模式**，通过层层继承逐步添加能力：

```
BaseModel (Pydantic)
    │
    ▼
BaseAgent (抽象基类)
    │   ├── 定义：状态机 + 执行循环
    │   ├── 核心方法：run() - 主循环骨架
    │   └── 抽象方法：step() - 留给子类实现
    │
    ▼
ReActAgent (抽象基类)
    │   ├── 拆分 step() 为 think() + act()
    │   └── 实现 ReAct 模式的基本框架
    │
    ▼
ToolCallAgent (具体实现)
    │   ├── 实现 think()：调用 LLM 决策
    │   ├── 实现 act()：执行工具调用
    │   └── 管理 ToolCollection
    │
    ├───────────────┬───────────────┬───────────────┐
    ▼               ▼               ▼               ▼
  Manus        BrowserAgent     MCPAgent        SWEAgent
  (主Agent)    (浏览器专用)    (MCP协议)      (软件工程)
```

**设计意图**：每一层只关注自己的职责，BaseAgent 管循环，ReActAgent 管思考/行动分离，ToolCallAgent 管工具调用。

### 2.2 Tool 继承链

```
BaseModel (Pydantic) + ABC
    │
    ▼
BaseTool (抽象基类)
    │   ├── 属性：name, description, parameters
    │   ├── 核心方法：execute() - 抽象，子类实现
    │   ├── 辅助方法：to_param() - 转 OpenAI 格式
    │   └── 可调用：__call__() 委托给 execute()
    │
    ├─────────┬─────────┬──────────┬──────────┬─────────┐
    ▼         ▼         ▼          ▼          ▼         ▼
Terminate  PythonExec  Bash   BrowserUse  WebSearch  Planning
```

---

## 三、核心数据结构

### 3.1 Message：对话的原子单位

```python
# app/schema.py
class Message(BaseModel):
    role: Literal["system", "user", "assistant", "tool"]
    content: Optional[str]
    tool_calls: Optional[List[ToolCall]]    # LLM 返回的工具调用请求
    tool_call_id: Optional[str]              # 工具响应时关联的调用 ID
    base64_image: Optional[str]              # 多模态图像
```

**关键点**：
- `tool_calls` 是 LLM 决定调用工具时的"指令"
- `tool_call_id` 是工具执行结果回传时的"关联 ID"
- 这两个字段构成了 Agent 与工具交互的桥梁

### 3.2 Memory：Agent 的记忆

```python
class Memory(BaseModel):
    messages: List[Message] = []
    max_messages: int = 100

    def add_message(self, message: Message):
        self.messages.append(message)
        # 超过限制时裁剪旧消息
        if len(self.messages) > self.max_messages:
            # 保留 system 消息 + 最近的消息
            ...
```

**设计意图**：Memory 是 Agent 的"短期记忆"，所有对话历史、工具输出都存在这里，LLM 的每次决策都基于完整的 Memory。

### 3.3 AgentState：状态机

```python
class AgentState(str, Enum):
    IDLE = "IDLE"         # 空闲，可以接受新任务
    RUNNING = "RUNNING"   # 执行中
    FINISHED = "FINISHED" # 任务完成
    ERROR = "ERROR"       # 出错
```

**状态转换规则**：
```
IDLE ──run()调用──▶ RUNNING ──terminate工具──▶ FINISHED
                      │
                      │──达到max_steps──▶ IDLE
                      │
                      │──异常发生──▶ ERROR
```

---

## 四、Prompt 系统：Agent 的"灵魂"

Prompt 是 Agent 行为的"灵魂"，决定了 LLM 如何理解任务、如何选择工具、如何组织输出。OpenManus 设计了一套分层的 Prompt 架构。

### 4.1 Prompt 架构设计

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Prompt 组成结构                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │ System Prompt（系统提示）                                            │   │
│   │ - 定义 Agent 的身份和角色                                            │   │
│   │ - 描述能力边界和行为准则                                             │   │
│   │ - 在每次 LLM 调用时作为第一条消息                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │ Memory Messages（历史消息）                                          │   │
│   │ - 用户输入 (role: user)                                              │   │
│   │ - LLM 响应 (role: assistant)                                         │   │
│   │ - 工具执行结果 (role: tool)                                          │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │ Next Step Prompt（下一步提示）                                       │   │
│   │ - 引导 LLM 进行下一步决策                                            │   │
│   │ - 提供工具使用指引                                                   │   │
│   │ - 在每轮循环末尾追加                                                 │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**文件组织**：所有 Prompt 定义在 `app/prompt/` 目录下：

```
app/prompt/
├── manus.py          # Manus 主 Agent 的 Prompt
├── toolcall.py       # ToolCallAgent 基础 Prompt
├── planning.py       # PlanningFlow 规划 Prompt
├── browser.py        # BrowserAgent 浏览器自动化 Prompt
├── swe.py            # SWE Agent 软件工程 Prompt
├── mcp.py            # MCP Agent Prompt
└── visualization.py  # 数据分析 Agent Prompt
```

### 4.2 Prompt 与 Agent 的绑定机制

每个 Agent 通过类属性绑定自己的 Prompt，这是一个**继承覆盖**的设计模式：

```python
# app/agent/toolcall.py —— 基类定义默认 Prompt
from app.prompt.toolcall import NEXT_STEP_PROMPT, SYSTEM_PROMPT

class ToolCallAgent(ReActAgent):
    system_prompt: str = SYSTEM_PROMPT      # "You are an agent that can execute tool calls"
    next_step_prompt: str = NEXT_STEP_PROMPT  # "If you want to stop interaction, use `terminate`..."
```

```python
# app/agent/manus.py —— 子类覆盖 Prompt
from app.prompt.manus import NEXT_STEP_PROMPT, SYSTEM_PROMPT

class Manus(ToolCallAgent):
    # 覆盖父类的 Prompt，注入工作目录
    system_prompt: str = SYSTEM_PROMPT.format(directory=config.workspace_root)
    next_step_prompt: str = NEXT_STEP_PROMPT
```

```python
# app/agent/browser.py —— BrowserAgent 使用专门的浏览器 Prompt
from app.prompt.browser import NEXT_STEP_PROMPT, SYSTEM_PROMPT

class BrowserAgent(ToolCallAgent):
    system_prompt: str = SYSTEM_PROMPT   # 复杂的 JSON 格式要求
    next_step_prompt: str = NEXT_STEP_PROMPT  # 带占位符的动态 Prompt
```

**继承链中的 Prompt 覆盖**：

```
ToolCallAgent (基础 Prompt)
    │
    ├── Manus (覆盖为全能助手 Prompt + 工作目录注入)
    │
    ├── BrowserAgent (覆盖为浏览器专用 Prompt)
    │
    └── MCPAgent (覆盖为 MCP 协议 Prompt)
```

### 4.3 Prompt 注入流程（核心代码分析）

Prompt 在 `ToolCallAgent.think()` 中被组装并发送给 LLM，这是**整个框架最核心的代码之一**：

```python
# app/agent/toolcall.py 第 39-56 行
async def think(self) -> bool:
    """Process current state and decide next actions using tools"""

    # ⭐ 关键步骤 1：将 next_step_prompt 追加到消息列表
    if self.next_step_prompt:
        user_msg = Message.user_message(self.next_step_prompt)
        self.messages += [user_msg]  # 追加到 Memory 的消息列表

    try:
        # ⭐ 关键步骤 2：调用 LLM，组装完整的消息结构
        response = await self.llm.ask_tool(
            messages=self.messages,  # Memory 中的所有历史消息
            system_msgs=(
                [Message.system_message(self.system_prompt)]  # System Prompt 作为独立参数
                if self.system_prompt
                else None
            ),
            tools=self.available_tools.to_params(),  # 工具列表
            tool_choice=self.tool_choices,           # auto/required/none
        )
    except ...
```

**消息组装的完整流程**：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    think() 中的消息组装过程                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. 追加 next_step_prompt 到 Memory                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ if self.next_step_prompt:                                           │   │
│  │     user_msg = Message.user_message(self.next_step_prompt)          │   │
│  │     self.messages += [user_msg]  # 追加到消息列表末尾                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  2. 调用 LLM API，传入三部分内容                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ await self.llm.ask_tool(                                            │   │
│  │     messages=self.messages,      # ← Memory 中的历史消息             │   │
│  │     system_msgs=[Message.system_message(self.system_prompt)],       │   │
│  │                                  # ↑ System Prompt (独立传入)        │   │
│  │     tools=self.available_tools.to_params(),  # 工具定义              │   │
│  │     tool_choice=self.tool_choices,                                  │   │
│  │ )                                                                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  3. LLM 实际收到的消息顺序                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ [                                                                   │   │
│  │   {role: "system", content: "You are OpenManus..."},  ← 第一条      │   │
│  │   {role: "user", content: "帮我写一个爬虫"},          ← Memory[0]   │   │
│  │   {role: "assistant", content: "...", tool_calls: [...]},          │   │
│  │   {role: "tool", content: "File created...", tool_call_id: "..."},  │   │
│  │   {role: "user", content: "Based on user needs..."}   ← next_step   │   │
│  │ ]                                                                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.4 动态 Prompt：BrowserAgent 的高级用法

BrowserAgent 展示了**动态 Prompt** 的高级用法——根据浏览器状态实时修改 `next_step_prompt`：

```python
# app/agent/browser.py 第 120-125 行
async def think(self) -> bool:
    """Process current state and decide next actions using tools, with browser state info added"""
    # ⭐ 动态生成 next_step_prompt，注入浏览器状态
    self.next_step_prompt = (
        await self.browser_context_helper.format_next_step_prompt()
    )
    return await super().think()  # 调用父类的 think()
```

`format_next_step_prompt()` 的实现（第 47-79 行）：

```python
# app/agent/browser.py
async def format_next_step_prompt(self) -> str:
    """Gets browser state and formats the browser prompt."""
    browser_state = await self.get_browser_state()  # 获取当前浏览器状态
    url_info, tabs_info, content_above_info, content_below_info = "", "", "", ""

    if browser_state and not browser_state.get("error"):
        # 动态提取浏览器信息
        url_info = f"\n   URL: {browser_state.get('url', 'N/A')}\n   Title: {browser_state.get('title', 'N/A')}"
        tabs = browser_state.get("tabs", [])
        if tabs:
            tabs_info = f"\n   {len(tabs)} tab(s) available"

        # 处理滚动位置信息
        pixels_above = browser_state.get("pixels_above", 0)
        pixels_below = browser_state.get("pixels_below", 0)
        if pixels_above > 0:
            content_above_info = f" ({pixels_above} pixels)"
        if pixels_below > 0:
            content_below_info = f" ({pixels_below} pixels)"

        # ⭐ 如果有截图，将其作为消息添加到 Memory
        if self._current_base64_image:
            image_message = Message.user_message(
                content="Current browser screenshot:",
                base64_image=self._current_base64_image,
            )
            self.agent.memory.add_message(image_message)

    # ⭐ 使用占位符替换，生成最终的 Prompt
    return NEXT_STEP_PROMPT.format(
        url_placeholder=url_info,
        tabs_placeholder=tabs_info,
        content_above_placeholder=content_above_info,
        content_below_placeholder=content_below_info,
        results_placeholder=results_info,
    )
```

**NEXT_STEP_PROMPT 模板**（`app/prompt/browser.py` 第 73-94 行）：

```python
NEXT_STEP_PROMPT = """
What should I do next to achieve my goal?

When you see [Current state starts here], focus on the following:
- Current URL and page title{url_placeholder}      ← 动态注入
- Available tabs{tabs_placeholder}                  ← 动态注入
- Interactive elements and their indices
- Content above{content_above_placeholder} or below{content_below_placeholder} the viewport
- Any action results or errors{results_placeholder}

For browser interactions:
- To navigate: browser_use with action="go_to_url", url="..."
- To click: browser_use with action="click_element", index=N
...
"""
```

**动态 Prompt 的执行流程**：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BrowserAgent 动态 Prompt 流程                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Step 1: 调用 think()                                                       │
│         │                                                                   │
│         ▼                                                                   │
│  Step 2: format_next_step_prompt()                                          │
│         │                                                                   │
│         ├── 获取浏览器状态 (URL, tabs, 滚动位置)                             │
│         ├── 获取页面截图 (base64)                                           │
│         └── 用占位符替换生成最终 Prompt                                      │
│         │                                                                   │
│         ▼                                                                   │
│  Step 3: 生成的 Prompt 示例                                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ "What should I do next to achieve my goal?                          │   │
│  │                                                                     │   │
│  │  When you see [Current state starts here], focus on:                │   │
│  │  - Current URL and page title                                       │   │
│  │    URL: https://example.com                                         │   │
│  │    Title: Example Domain                                            │   │
│  │  - Available tabs                                                   │   │
│  │    2 tab(s) available                                               │   │
│  │  - Content above (0 pixels) or below (500 pixels) the viewport      │   │
│  │  ..."                                                               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│         │                                                                   │
│         ▼                                                                   │
│  Step 4: 调用父类 super().think()，将动态 Prompt 发送给 LLM                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.5 Manus 的 Prompt 动态切换

Manus Agent 会根据是否在使用浏览器，**动态切换 Prompt**：

```python
# app/agent/manus.py 第 140-165 行
async def think(self) -> bool:
    """Process current state and decide next actions with appropriate context."""
    if not self._initialized:
        await self.initialize_mcp_servers()
        self._initialized = True

    # ⭐ 保存原始 Prompt
    original_prompt = self.next_step_prompt

    # ⭐ 检测最近 3 条消息中是否使用了浏览器工具
    recent_messages = self.memory.messages[-3:] if self.memory.messages else []
    browser_in_use = any(
        tc.function.name == BrowserUseTool().name
        for msg in recent_messages
        if msg.tool_calls
        for tc in msg.tool_calls
    )

    # ⭐ 如果正在使用浏览器，切换到浏览器专用 Prompt
    if browser_in_use:
        self.next_step_prompt = (
            await self.browser_context_helper.format_next_step_prompt()
        )

    result = await super().think()

    # ⭐ 恢复原始 Prompt
    self.next_step_prompt = original_prompt

    return result
```

**设计意图**：Manus 是一个"全能 Agent"，但当它使用浏览器时，需要更详细的浏览器状态信息来做决策。

### 4.6 PlanningFlow 的 Prompt 设计

PlanningFlow 使用**内联 Prompt**（直接在代码中定义），而不是从 `app/prompt/` 导入：

```python
# app/flow/planning.py 第 136-176 行
async def _create_initial_plan(self, request: str) -> None:
    """Create an initial plan based on the request using the flow's LLM and PlanningTool."""

    # ⭐ 内联定义 System Prompt
    system_message_content = (
        "You are a planning assistant. Create a concise, actionable plan with clear steps. "
        "Focus on key milestones rather than detailed sub-steps. "
        "Optimize for clarity and efficiency."
    )

    # ⭐ 如果有多个 Agent，动态添加 Agent 描述
    agents_description = []
    for key in self.executor_keys:
        if key in self.agents:
            agents_description.append({
                "name": key.upper(),
                "description": self.agents[key].description,
            })

    if len(agents_description) > 1:
        system_message_content += (
            f"\nNow we have {agents_description} agents. "
            f"The infomation of them are below: {json.dumps(agents_description)}\n"
            "When creating steps in the planning tool, please specify the agent names using the format '[agent_name]'."
        )

    system_message = Message.system_message(system_message_content)
    user_message = Message.user_message(
        f"Create a reasonable plan with clear steps to accomplish the task: {request}"
    )

    # ⭐ 调用 LLM，只提供 PlanningTool
    response = await self.llm.ask_tool(
        messages=[user_message],
        system_msgs=[system_message],
        tools=[self.planning_tool.to_param()],  # 只有一个工具
        tool_choice=ToolChoice.AUTO,
    )
```

**执行步骤时的 Prompt 构造**（第 277-293 行）：

```python
async def _execute_step(self, executor: BaseAgent, step_info: dict) -> str:
    """Execute the current step with the specified agent using agent.run()."""
    plan_status = await self._get_plan_text()  # 获取当前计划状态
    step_text = step_info.get("text", f"Step {self.current_step_index}")

    # ⭐ 构造包含计划上下文的 Prompt
    step_prompt = f"""
    CURRENT PLAN STATUS:
    {plan_status}

    YOUR CURRENT TASK:
    You are now working on step {self.current_step_index}: "{step_text}"

    Please only execute this current step using the appropriate tools.
    When you're done, provide a summary of what you accomplished.
    """

    # 调用 Agent 执行
    step_result = await executor.run(step_prompt)
```

### 4.7 各 Agent 的 System Prompt 对比

| Agent | System Prompt 特点 | 代码位置 |
|-------|-------------------|----------|
| **ToolCallAgent** | 极简："You are an agent that can execute tool calls" | `app/prompt/toolcall.py` |
| **Manus** | 全能助手 + 工作目录注入：`SYSTEM_PROMPT.format(directory=...)` | `app/prompt/manus.py` |
| **BrowserAgent** | 复杂 JSON 格式要求 + 9 条规则 | `app/prompt/browser.py` |
| **SWE Agent** | 单工具限制 + 命令行模拟 | `app/prompt/swe.py` |
| **PlanningFlow** | 内联定义 + 动态 Agent 描述 | `app/flow/planning.py` 内联 |

### 4.8 Prompt 设计原则总结

通过源码分析，可以总结出 OpenManus 的 Prompt 设计原则：

| 原则 | 代码体现 | 示例 |
|------|---------|------|
| **继承覆盖** | 子类覆盖父类的 `system_prompt` 属性 | `Manus` 覆盖 `ToolCallAgent` |
| **动态注入** | 使用 `.format()` 或占位符替换 | `SYSTEM_PROMPT.format(directory=...)` |
| **上下文感知** | 根据状态动态修改 `next_step_prompt` | `BrowserAgent` 注入浏览器状态 |
| **分离关注点** | System Prompt 定义角色，Next Step Prompt 引导决策 | 两个独立变量 |
| **多模态支持** | 支持将截图作为消息添加 | `Message.user_message(base64_image=...)` |

**Prompt 与 Agent 行为的关系**：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Prompt 如何影响 Agent 行为                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  System Prompt                    Agent 行为                                │
│  ─────────────────                ─────────────                             │
│                                                                             │
│  "全能助手"                   →   尝试处理各种类型的任务                      │
│  "工具组合"                   →   倾向于使用多个工具协作                      │
│  "JSON 格式"                  →   输出结构化数据                             │
│  "单工具限制"                 →   每次只调用一个工具                          │
│  "动态工具"                   →   先检查可用工具再使用                        │
│                                                                             │
│  Next Step Prompt                 决策引导                                  │
│  ─────────────────                ─────────────                             │
│                                                                             │
│  "proactively select"        →   主动选择工具而非等待指示                    │
│  "break down the problem"    →   分步解决复杂问题                           │
│  "explain execution results" →   每步都给出解释                             │
│  "use terminate"             →   知道何时结束                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.9 为什么 next_step_prompt 不放到 System Prompt？

一个常见的疑问：**既然 `next_step_prompt` 每次都要发送，为什么不直接放到 `system_prompt` 里？**

这涉及到 **System Prompt vs User Message** 的本质区别。

#### 4.9.1 消息位置决定权重

LLM 对**最后几条消息**的关注度最高（recency bias）：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        消息顺序与 LLM 注意力                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ [system] You are OpenManus...              ← 开头，容易被"稀释"              │
│ [user] 帮我写爬虫                                                            │
│ [assistant] 好的，我来创建文件...                                            │
│ [tool] File created: crawler.py                                             │
│ [assistant] 文件已创建...                                                    │
│ [tool] Code executed successfully                                           │
│ ...（可能有 10-20 条消息）...                                                │
│ [user] Based on user needs, proactively select...  ← 最后，权重最高          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

如果把 `next_step_prompt` 放在 `system_prompt` 中，经过多轮对话后，这个指令会被"埋"在最前面，影响力显著下降。

#### 4.9.2 静态身份 vs 动态指令

```python
# System Prompt 是静态的，初始化时就固定了
system_prompt: str = SYSTEM_PROMPT.format(directory=config.workspace_root)

# next_step_prompt 可以每轮动态变化
async def think(self) -> bool:
    # BrowserAgent：每次都重新生成，注入最新浏览器状态
    self.next_step_prompt = await self.browser_context_helper.format_next_step_prompt()
```

| 属性 | System Prompt | next_step_prompt |
|------|--------------|------------------|
| **内容** | 身份定义、能力描述、行为准则 | 当前状态、决策指引、终止条件 |
| **变化频率** | 整个会话不变 | 每轮循环可能变化 |
| **位置** | 消息列表最前面 | 消息列表最后面 |
| **作用** | 告诉 LLM "你是谁" | 告诉 LLM "你现在该做什么" |

#### 4.9.3 源码验证

```python
# app/agent/toolcall.py 第 39-56 行
async def think(self) -> bool:
    # ⭐ next_step_prompt 作为 user 消息追加到末尾
    if self.next_step_prompt:
        user_msg = Message.user_message(self.next_step_prompt)  # role: "user"
        self.messages += [user_msg]  # 追加到消息列表最后

    response = await self.llm.ask_tool(
        messages=self.messages,
        system_msgs=[Message.system_message(self.system_prompt)],  # system 单独传
        ...
    )
```

#### 4.9.4 类比理解

| 角色 | System Prompt | next_step_prompt |
|------|--------------|------------------|
| **类比** | 员工入职培训手册 | 每天早会的任务分配 |
| **频率** | 入职时发一次 | 每天早上都开 |
| **内容** | 公司文化、岗位职责、行为规范 | 今天的具体任务、注意事项 |

#### 4.9.5 如果放到 System Prompt 会怎样？

```python
# 假设这样设计（反面示例）
system_prompt = """
You are OpenManus...
[大段身份描述]
[工具列表]
[使用规则]

Based on user needs, proactively select the most appropriate tool...  ← 放这里
If you want to stop, use terminate...
"""
```

**问题**：
1. **System Prompt 臃肿**：核心指令被大段身份描述稀释
2. **无法动态注入**：无法实时注入浏览器状态、当前步骤等信息
3. **记忆衰减**：多轮对话后，LLM 对开头内容的"记忆"会减弱
4. **违背设计原则**：混淆了"身份定义"和"行动指令"的职责

#### 4.9.6 设计总结

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                  System Prompt vs next_step_prompt 的分工                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  System Prompt (role: system)          next_step_prompt (role: user)        │
│  ─────────────────────────────         ─────────────────────────────        │
│                                                                             │
│  "你是 OpenManus，一个全能助手"     vs  "现在请决定下一步行动"                 │
│  "你可以使用以下工具..."           vs  "如果任务完成，调用 terminate"          │
│  "遵循这些行为准则..."             vs  "当前浏览器 URL: https://..."          │
│                                                                             │
│  ┌─────────────────────────┐         ┌─────────────────────────┐            │
│  │ 定义"你是谁"            │         │ 指导"你现在该做什么"     │            │
│  │ 一次性、静态             │         │ 每轮、动态               │            │
│  │ 位于消息开头             │         │ 位于消息末尾             │            │
│  └─────────────────────────┘         └─────────────────────────┘            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**核心洞察**：`next_step_prompt` 作为 `user` 消息追加到末尾，是为了**保持指令的"新鲜度"和"权重"**，确保 LLM 在每轮决策时都能明确收到"该行动了"的信号，实现从"被动响应"到"主动驱动"的转变。

---

## 五、核心执行流程剖析

### 5.1 主循环：BaseAgent.run()

这是整个框架的"心脏"，理解它就理解了 OpenManus 的运作方式：

```python
# app/agent/base.py (简化版)
async def run(self, request: Optional[str] = None) -> str:
    # 1. 状态检查：只有 IDLE 状态才能启动
    if self.state != AgentState.IDLE:
        raise RuntimeError(f"Cannot run from state: {self.state}")

    # 2. 初始化：将用户请求加入 Memory
    if request:
        self.update_memory("user", request)

    results = []

    # 3. 进入运行状态（使用上下文管理器确保状态安全）
    async with self.state_context(AgentState.RUNNING):

        # 4. 主循环：步数限制 + 状态检查
        while self.current_step < self.max_steps and self.state != AgentState.FINISHED:
            self.current_step += 1

            # 5. 执行单步（子类实现）
            step_result = await self.step()

            # 6. 卡住检测：防止 Agent 陷入重复循环
            if self.is_stuck():
                self.handle_stuck_state()

            results.append(step_result)

        # 7. 步数耗尽处理
        if self.current_step >= self.max_steps:
            results.append(f"Terminated: Reached max steps ({self.max_steps})")

    # 8. 清理资源
    await SANDBOX_CLIENT.cleanup()

    return "\n".join(results)
```

**关键设计**：
- **状态上下文管理器**：`state_context()` 确保异常时状态能正确恢复
- **卡住检测**：`is_stuck()` 检测连续相同输出，`handle_stuck_state()` 注入提示让 LLM 改变策略
- **资源清理**：无论成功失败，都会清理 sandbox 等资源

### 5.2 ReAct 模式：think() + act()

```python
# app/agent/react.py
async def step(self) -> str:
    """单步执行：先思考，再行动"""
    should_act = await self.think()  # 思考：是否需要行动？
    if not should_act:
        return "Thinking complete - no action needed"
    return await self.act()          # 行动：执行决定的动作
```

**ReAct 模式的精髓**：
- **Reasoning**（推理）：LLM 分析当前状态，决定下一步
- **Acting**（行动）：执行工具调用
- 两者交替进行，形成"思考-行动-观察"的循环

### 5.3 工具调用核心：ToolCallAgent

这是最关键的实现，把 LLM 的"想法"变成"行动"：

```python
# app/agent/toolcall.py (简化版)
class ToolCallAgent(ReActAgent):
    available_tools: ToolCollection  # 可用工具集合
    tool_calls: List[ToolCall] = []  # 当前轮次的工具调用列表

    async def think(self) -> bool:
        """思考：调用 LLM 决定使用哪些工具"""

        # 1. 准备消息：Memory 中的历史 + 下一步提示
        messages = self.memory.messages.copy()
        if self.next_step_prompt:
            messages.append(Message.user_message(self.next_step_prompt))

        # 2. 调用 LLM 的工具模式 ⭐ 核心调用
        response = await self.llm.ask_tool(
            messages=messages,
            system_msgs=[Message.system_message(self.system_prompt)],
            tools=self.available_tools.to_params(),  # 工具列表转 OpenAI 格式
            tool_choice=self.tool_choices,           # auto/required/none
        )

        # 3. 提取工具调用
        self.tool_calls = response.tool_calls or []

        # 4. 将 LLM 响应加入 Memory
        assistant_msg = Message.from_tool_calls(
            content=response.content,
            tool_calls=self.tool_calls
        )
        self.memory.add_message(assistant_msg)

        # 5. 返回是否需要执行工具
        return bool(self.tool_calls)

    async def act(self) -> str:
        """行动：执行所有工具调用"""
        results = []

        for command in self.tool_calls:
            # 1. 执行工具
            result = await self.execute_tool(command)

            # 2. 将工具输出加入 Memory（作为 tool 角色的消息）
            tool_msg = Message.tool_message(
                content=result,
                tool_call_id=command.id,
                name=command.function.name,
            )
            self.memory.add_message(tool_msg)

            results.append(result)

        return "\n\n".join(results)

    async def execute_tool(self, command: ToolCall) -> str:
        """执行单个工具调用"""
        name = command.function.name
        args = json.loads(command.function.arguments)

        # 通过 ToolCollection 路由到具体工具
        result = await self.available_tools.execute(name=name, tool_input=args)

        # 处理特殊工具（如 terminate）
        await self._handle_special_tool(name=name, result=result)

        return str(result)

    async def _handle_special_tool(self, name: str, result: Any):
        """处理特殊工具，如 terminate 会终止 Agent"""
        if name.lower() in [n.lower() for n in self.special_tool_names]:
            self.state = AgentState.FINISHED  # 直接修改状态，终止循环
```

---

## 六、LLM 抽象层：统一的"大脑"接口

### 6.1 单例模式 + 多后端支持

```python
# app/llm.py (简化版)
class LLM:
    _instances: Dict[str, "LLM"] = {}  # 单例缓存

    def __new__(cls, config_name="default", llm_config=None):
        # 同一 config_name 返回同一实例，避免重复创建
        if config_name not in cls._instances:
            instance = super().__new__(cls)
            cls._instances[config_name] = instance
        return cls._instances[config_name]

    def __init__(self, config_name="default", llm_config=None):
        # 根据配置选择后端
        if self.api_type == "azure":
            self.client = AsyncAzureOpenAI(...)
        elif self.api_type == "aws":
            self.client = BedrockClient()  # 自己实现的适配器
        else:
            self.client = AsyncOpenAI(...)  # 兼容 OpenAI 及其他 API
```

### 6.2 核心方法：ask_tool()

这是 Agent 与 LLM 交互的核心接口：

```python
async def ask_tool(
    self,
    messages: List[dict],
    tools: List[dict],           # 工具定义列表
    tool_choice: str = "auto",   # auto/required/none/具体工具名
    **kwargs
) -> ChatCompletionMessage:
    """带工具调用的对话请求"""

    # 1. 格式化消息（处理图片等特殊内容）
    formatted_messages = self.format_messages(messages)

    # 2. Token 限制检查
    if self.count_tokens(formatted_messages) > self.max_tokens:
        raise TokenLimitExceeded(...)

    # 3. 调用 OpenAI API
    response = await self.client.chat.completions.create(
        model=self.model,
        messages=formatted_messages,
        tools=tools,
        tool_choice=tool_choice,
        **kwargs
    )

    # 4. 返回消息（可能包含 tool_calls）
    return response.choices[0].message
```

**返回值结构**：
```python
# 当 LLM 决定调用工具时
message.tool_calls = [
    ToolCall(
        id="call_abc123",
        function=Function(
            name="python_execute",
            arguments='{"code": "print(1+1)"}'
        )
    )
]

# 当 LLM 直接回复时
message.content = "任务已完成"
message.tool_calls = None
```

---

## 七、工具系统：能力的载体

### 7.1 BaseTool：工具的统一接口

```python
# app/tool/base.py
class BaseTool(ABC, BaseModel):
    name: str                    # 工具名称，供 LLM 引用
    description: str             # 工具描述，帮助 LLM 理解用途
    parameters: Optional[dict]   # JSON Schema，定义参数结构

    @abstractmethod
    async def execute(self, **kwargs) -> Any:
        """执行工具 - 子类必须实现"""
        pass

    async def __call__(self, **kwargs) -> Any:
        """使工具可调用"""
        return await self.execute(**kwargs)

    def to_param(self) -> Dict:
        """转换为 OpenAI function calling 格式"""
        return {
            "type": "function",
            "function": {
                "name": self.name,
                "description": self.description,
                "parameters": self.parameters,
            },
        }
```

### 7.2 ToolCollection：工具的管理器

```python
# app/tool/tool_collection.py
class ToolCollection:
    def __init__(self, *tools: BaseTool):
        self.tools = tools
        self.tool_map = {tool.name: tool for tool in tools}

    def to_params(self) -> List[Dict]:
        """转换所有工具为 API 参数格式"""
        return [tool.to_param() for tool in self.tools]

    async def execute(self, *, name: str, tool_input: Dict) -> ToolResult:
        """按名称执行工具"""
        tool = self.tool_map.get(name)
        if not tool:
            return ToolFailure(error=f"Tool {name} is invalid")
        return await tool(**tool_input)

    def add_tool(self, tool: BaseTool):
        """动态添加工具"""
        if tool.name not in self.tool_map:
            self.tools += (tool,)
            self.tool_map[tool.name] = tool
```

### 7.3 典型工具实现：BrowserUseTool

以浏览器工具为例，看工具如何实现：

```python
# app/tool/browser_use_tool.py (简化版)
class BrowserUseTool(BaseTool):
    name: str = "browser_use"
    description: str = "浏览器自动化工具..."
    parameters: dict = {
        "type": "object",
        "properties": {
            "action": {
                "type": "string",
                "enum": ["go_to_url", "click_element", "input_text", ...],
            },
            "url": {"type": "string"},
            "index": {"type": "integer"},
            # ... 更多参数
        },
        "required": ["action"],
    }

    # 内部状态
    browser: Optional[BrowserUseBrowser] = None
    context: Optional[BrowserContext] = None
    lock: asyncio.Lock  # 防止并发问题

    async def execute(self, action: str, **kwargs) -> ToolResult:
        async with self.lock:
            # 确保浏览器已初始化
            context = await self._ensure_browser_initialized()

            # 根据 action 分发到具体操作
            if action == "go_to_url":
                page = await context.get_current_page()
                await page.goto(kwargs["url"])
                return ToolResult(output=f"Navigated to {kwargs['url']}")

            elif action == "click_element":
                element = await context.get_dom_element_by_index(kwargs["index"])
                await context._click_element_node(element)
                return ToolResult(output=f"Clicked element at index {kwargs['index']}")

            elif action == "extract_content":
                # 特殊：用 LLM 提取页面内容
                page = await context.get_current_page()
                content = markdownify(await page.content())

                # 调用 LLM 做结构化提取
                response = await self.llm.ask_tool(
                    messages=[{"role": "system", "content": f"Extract: {kwargs['goal']}\n{content}"}],
                    tools=[extraction_function],
                    tool_choice="required",
                )
                return ToolResult(output=str(response))

            # ... 更多 action
```

**设计亮点**：
- **锁机制**：`asyncio.Lock` 确保浏览器操作的原子性
- **延迟初始化**：`_ensure_browser_initialized()` 按需创建浏览器
- **LLM 嵌套调用**：`extract_content` 内部再次调用 LLM 做智能提取

---

## 八、Flow 层：多 Agent 编排

### 8.1 PlanningFlow：计划驱动的执行

```python
# app/flow/planning.py (简化版)
class PlanningFlow(BaseFlow):
    llm: LLM                          # 独立的 LLM，用于规划
    planning_tool: PlanningTool       # 计划管理工具
    agents: Dict[str, BaseAgent]      # 多个执行 Agent

    async def execute(self, input_text: str) -> str:
        # 1. 创建计划
        await self._create_initial_plan(input_text)

        result = ""
        while True:
            # 2. 获取当前步骤
            step_index, step_info = await self._get_current_step_info()

            if step_index is None:
                # 3. 所有步骤完成，生成总结
                result += await self._finalize_plan()
                break

            # 4. 选择合适的 Agent 执行当前步骤
            executor = self.get_executor(step_info.get("type"))
            step_result = await self._execute_step(executor, step_info)
            result += step_result

            # 5. 检查是否需要终止
            if executor.state == AgentState.FINISHED:
                break

        return result
```

### 8.2 计划创建过程

```python
async def _create_initial_plan(self, request: str):
    """用 LLM + PlanningTool 生成计划"""

    # 1. 构造系统提示
    system_message = Message.system_message(
        "You are a planning assistant. Create a concise, actionable plan..."
    )

    # 2. 用户请求
    user_message = Message.user_message(
        f"Create a plan to accomplish: {request}"
    )

    # 3. 调用 LLM，让它使用 PlanningTool
    response = await self.llm.ask_tool(
        messages=[user_message],
        system_msgs=[system_message],
        tools=[self.planning_tool.to_param()],  # 只提供 planning 工具
        tool_choice=ToolChoice.AUTO,
    )

    # 4. 执行 LLM 返回的工具调用
    if response.tool_calls:
        for tool_call in response.tool_calls:
            args = json.loads(tool_call.function.arguments)
            args["plan_id"] = self.active_plan_id
            await self.planning_tool.execute(**args)
```

**核心思想**：把"规划"也当作一个工具调用，LLM 通过调用 `PlanningTool.create` 来生成计划。

---

## 九、完整执行流程图

```
用户输入: "帮我写一个 Python 爬虫"
            │
            ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  main.py                                                                  │
│  agent = await Manus.create()                                             │
│  result = await agent.run("帮我写一个 Python 爬虫")                         │
└───────────────────────────────────────────────────────────────────────────┘
            │
            ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  BaseAgent.run()                                                          │
│                                                                           │
│  1. 状态检查: IDLE → RUNNING                                               │
│  2. Memory.add_message(user_message("帮我写一个 Python 爬虫"))             │
│  3. 进入主循环                                                             │
└───────────────────────────────────────────────────────────────────────────┘
            │
            ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  while current_step < max_steps and state != FINISHED:                    │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ Step 1: ReActAgent.step()                                           │  │
│  │                                                                     │  │
│  │ ┌─────────────────────────────────────────────────────────────────┐ │  │
│  │ │ ToolCallAgent.think()                                           │ │  │
│  │ │                                                                 │ │  │
│  │ │ messages = [                                                    │ │  │
│  │ │   {role: "user", content: "帮我写一个 Python 爬虫"}              │ │  │
│  │ │ ]                                                               │ │  │
│  │ │                                                                 │ │  │
│  │ │ response = await llm.ask_tool(                                  │ │  │
│  │ │   messages=messages,                                            │ │  │
│  │ │   tools=[python_execute, browser_use, str_replace_editor, ...]  │ │  │
│  │ │ )                                                               │ │  │
│  │ │                                                                 │ │  │
│  │ │ # LLM 返回:                                                     │ │  │
│  │ │ response.tool_calls = [                                         │ │  │
│  │ │   ToolCall(                                                     │ │  │
│  │ │     id="call_001",                                              │ │  │
│  │ │     function=Function(                                          │ │  │
│  │ │       name="str_replace_editor",                                │ │  │
│  │ │       arguments='{"command":"create","path":"crawler.py",...}'  │ │  │
│  │ │     )                                                           │ │  │
│  │ │   )                                                             │ │  │
│  │ │ ]                                                               │ │  │
│  │ │                                                                 │ │  │
│  │ │ Memory.add_message(assistant_message_with_tool_calls)           │ │  │
│  │ │ return True  # 需要执行工具                                      │ │  │
│  │ └─────────────────────────────────────────────────────────────────┘ │  │
│  │                                                                     │  │
│  │ ┌─────────────────────────────────────────────────────────────────┐ │  │
│  │ │ ToolCallAgent.act()                                             │ │  │
│  │ │                                                                 │ │  │
│  │ │ for tool_call in self.tool_calls:                               │ │  │
│  │ │   result = await available_tools.execute(                       │ │  │
│  │ │     name="str_replace_editor",                                  │ │  │
│  │ │     tool_input={...}                                            │ │  │
│  │ │   )                                                             │ │  │
│  │ │   # 工具执行：创建 crawler.py 文件                               │ │  │
│  │ │                                                                 │ │  │
│  │ │   Memory.add_message(tool_message(                              │ │  │
│  │ │     content="File created: crawler.py",                         │ │  │
│  │ │     tool_call_id="call_001"                                     │ │  │
│  │ │   ))                                                            │ │  │
│  │ └─────────────────────────────────────────────────────────────────┘ │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ Step 2: 继续循环...                                                 │  │
│  │ LLM 看到工具执行结果，决定下一步                                     │  │
│  │ 可能：继续修改代码 / 测试运行 / 调用 terminate 结束                  │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ Step N: LLM 调用 terminate 工具                                     │  │
│  │ _handle_special_tool() → self.state = FINISHED                      │  │
│  │ 循环退出                                                            │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────┘
            │
            ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  清理资源 + 返回结果                                                       │
│  await SANDBOX_CLIENT.cleanup()                                           │
│  return "Step 1: ...\nStep 2: ...\n..."                                   │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 十、关键设计模式总结

| 设计模式 | 应用位置 | 解决的问题 |
|---------|---------|-----------|
| **模板方法** | `BaseAgent.run()` → `step()` | 定义执行骨架，子类实现具体步骤 |
| **策略模式** | `think()` / `act()` 分离 | 思考和行动策略可独立变化 |
| **单例模式** | `LLM._instances` | 避免重复创建 LLM 客户端 |
| **工厂方法** | `Manus.create()` | 异步初始化（MCP 连接等） |
| **组合模式** | `ToolCollection` | 统一管理多个工具 |
| **状态模式** | `AgentState` | 管理 Agent 生命周期 |
| **上下文管理器** | `state_context()` | 安全的状态转换 |
| **观察者模式** | Memory 记录历史 | LLM 基于完整上下文决策 |

---

## 十一、核心文件速查表

| 模块 | 文件路径 | 核心职责 |
|------|---------|---------|
| 入口 | `main.py` | CLI 入口，创建 Manus 并执行 |
| Agent 基类 | `app/agent/base.py` | 状态机 + 主循环 |
| ReAct Agent | `app/agent/react.py` | think + act 分离 |
| 工具调用 Agent | `app/agent/toolcall.py` | LLM 工具调用 + 执行 |
| 主 Agent | `app/agent/manus.py` | 默认工具集 + MCP 支持 |
| 工具基类 | `app/tool/base.py` | 工具统一接口 |
| 工具集合 | `app/tool/tool_collection.py` | 工具管理与路由 |
| 数据结构 | `app/schema.py` | Message, Memory, State |
| LLM 层 | `app/llm.py` | 多后端 LLM 封装 |
| Flow 基类 | `app/flow/base.py` | 多 Agent 编排基类 |
| 计划 Flow | `app/flow/planning.py` | 计划驱动执行 |
| **Prompt 目录** | `app/prompt/` | **所有 Agent 的 Prompt 定义** |
| Manus Prompt | `app/prompt/manus.py` | 主 Agent 的系统提示 |
| Browser Prompt | `app/prompt/browser.py` | 浏览器 Agent 的结构化提示 |
| Planning Prompt | `app/prompt/planning.py` | 规划 Agent 的提示 |
| SWE Prompt | `app/prompt/swe.py` | 软件工程 Agent 的提示 |

---

## 十二、扩展指南

### 添加新工具

```python
# 1. 创建工具类
class MyTool(BaseTool):
    name: str = "my_tool"
    description: str = "我的自定义工具"
    parameters: dict = {
        "type": "object",
        "properties": {
            "param1": {"type": "string", "description": "参数1"}
        },
        "required": ["param1"]
    }

    async def execute(self, param1: str, **kwargs) -> ToolResult:
        # 实现工具逻辑
        result = do_something(param1)
        return ToolResult(output=result)

# 2. 在 Agent 中注册
class MyAgent(ToolCallAgent):
    available_tools: ToolCollection = ToolCollection(
        MyTool(),
        Terminate(),
    )
```

### 添加新 Agent

```python
class MyAgent(ToolCallAgent):
    name: str = "MyAgent"
    description: str = "专门做某事的 Agent"

    system_prompt: str = "你是一个专门做某事的助手..."
    next_step_prompt: str = "请决定下一步行动..."

    available_tools: ToolCollection = ToolCollection(
        SomeTool(),
        AnotherTool(),
        Terminate(),
    )

    # 可选：覆盖 think() 或 act() 添加自定义逻辑
    async def think(self) -> bool:
        # 自定义思考逻辑
        return await super().think()
```

---

## 总结

OpenManus 的核心实现可以归纳为：

1. **分层架构**：入口层 → Agent 层 → 工具层 → LLM 层，职责清晰
2. **ReAct 模式**：think-act 循环，LLM 决策 + 工具执行交替进行
3. **统一抽象**：BaseTool 统一工具接口，LLM 类统一模型接口
4. **状态机控制**：AgentState 管理生命周期，确保流程可控
5. **Memory 驱动**：所有决策基于完整的对话历史

理解了这些核心机制，你就能轻松阅读源码、扩展功能、甚至构建自己的 Agent 框架。
