# Agent Skills Manager — 设计文档

> 日期：2026-06-09  
> 状态：设计完成，待实现

---

## 一、项目概述

**Agent Skills Manager** 是一个 macOS 原生应用，统一管理多个 AI Coding Agent 的 Skills/Prompts。核心理念：一个中央 Skills 仓库（`~/.agent/skills`），通过 symlink 分发到各个 Agent 的配置目录。

- **技术栈**：SwiftUI（macOS 14.0）+ Rust（C FFI cdylib）
- **参考项目**：TokenViewer（已验证的 Swift + Rust FFI 模式）

---

## 二、系统架构

```
┌─────────────────────────────────────────────────────┐
│                 Swift UI Layer                       │
│  ┌───────────┐ ┌──────────┐ ┌──────────────────┐   │
│  │ SkillsPanel│ │AgentPanel│ │Settings/SyncPanel│   │
│  │ (Tree/List)│ │(List+Tgl)│ │  (OAuth/Push)    │   │
│  └─────┬─────┘ └────┬─────┘ └────────┬─────────┘   │
│        │             │                │              │
│  ┌─────┴─────────────┴────────────────┴─────────┐   │
│  │          AppState (ObservableObject)           │   │
│  │  @Published agents / skills / gitStatus / ...  │   │
│  └──────────────────────┬────────────────────────┘   │
│                         │ C FFI (JSON 串行)            │
├─────────────────────────┼────────────────────────────┤
│              Rust Core (staticlib)                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐  │
│  │AgentReg  │ │ Scanner  │ │GitEngine │ │Watcher │  │
│  │(CRUD+    │ │(discover)│ │(git2-rs) │ │(notify)│  │
│  │ persist) │ │          │ │          │ │        │  │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └───┬────┘  │
│       │             │             │           │       │
│  ┌────┴─────────────┴─────────────┴───────────┴───┐  │
│  │              SymlinkManager                     │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

### Swift ↔ Rust 边界：C FFI

选择 **C FFI** 而非 UniFFI，理由：
- TokenViewer 已验证此模式，所有坑已知
- 本项目 API 量少（10-15 个函数），手写胶水代码量可接受
- JSON 序列化本就是数据模型所需，过 FFI 零额外成本
- 构建链最简，无需 uniffi-bindgen 依赖

内存管理规则：
- Rust 返回 `*mut c_char` → Swift 立即 `String(cString:)` 复制 → 立即 `asm_free_string()`
- 输入 `const c_char*` → 由 `withCString` 管理生命周期
- 所有 handle 访问必须经过 `CoreBridge.queue.sync { }`
- `u8` 返回值：0 = 失败，1 = 成功

---

## 三、数据模型

### AgentConfig

```rust
pub struct AgentConfig {
    pub id: String,              // "claude-code" | "custom-{uuid}"
    pub name: String,            // "Claude Code" | "My Zed"
    pub skills_path: String,     // "~/.claude/commands" (支持 ~ 展开)
    pub link_type: LinkType,     // Directory | SingleFile | Overlay
    pub is_builtin: bool,
    pub is_linked: bool,
    pub linked_skills: Vec<String>,  // 关联的 Skill ID 列表
    pub icon: Option<String>,
}

pub enum LinkType {
    Directory,    // 整个目录软链接
    SingleFile,   // 单文件生成（合并所有 SKILL.md）
    Overlay,      // 逐文件覆盖（不覆盖目标已有文件）
}
```

### SkillEntry

```rust
pub struct SkillEntry {
    pub id: String,              // 目录名 = skill id
    pub manifest: SkillManifest,
    pub source_dir: PathBuf,     // 技能源目录
    pub installed_at: DateTime<Utc>,
}

pub struct SkillManifest {
    pub name: String,
    pub description: String,
    pub tags: Vec<String>,
    pub compatible_agents: Vec<String>,  // ["*"] | ["claude-code", "cursor"]
    pub version: String,
}
```

### Skill 目录结构

Skills 源仓库使用扁平化 + manifest.json 分类：

```
~/.agent/skills/
├── code-review/
│   ├── SKILL.md
│   └── manifest.json   {"name":"code-review","description":"...","tags":["development"],"compatible_agents":["*"],"version":"1.0"}
├── commit-message/
│   ├── SKILL.md
│   └── manifest.json
└── refactor-large-file/
    ├── SKILL.md
    └── manifest.json
```

### 内置 Agent 列表

代码内硬编码，支持 5 个主流 Agent：

| ID | Name | skills_path | link_type |
|----|------|-------------|-----------|
| claude-code | Claude Code | ~/.claude/commands | Directory |
| cursor | Cursor | ~/.cursor/rules | Directory |
| windsurf | Windsurf | ~/.windsurf/memories | Directory |
| copilot | GitHub Copilot | ~/.github/copilot-instructions.md | SingleFile |
| zed | Zed AI | ~/.config/zed/prompts | Directory |

### 持久化策略

| 文件 | 路径 | 内容 |
|------|------|------|
| 自定义 Agent | `~/.agent/agents.json` | `Vec<AgentConfig>`（仅 custom 部分） |
| 用户配置 | `~/.agent/config.json` | `{ source_root, default_link_type }` |
| OAuth Token | macOS Keychain | `com.skills-manager.github-token` |

---

## 四、Agent ↔ Skill 关联模型

每个 Agent 独立维护自己的 `linked_skills` 列表。Toggle 开关控制单个 Agent 对单个 Skill 的链接状态。

```
AgentRegistry
  ├── claude-code  → linked_skills: ["code-review", "commit-msg", "refactor"]
  ├── cursor       → linked_skills: ["code-review"]
  └── custom-zed   → linked_skills: []
```

### 新 Skill 安装流程

1. Scanner 检测到新 skill 目录（含 manifest.json + SKILL.md）
2. Watcher 回调 → AppState.pendingNewSkill = Some(skill)
3. SwiftUI 弹出 Sheet，展示新 skill 信息 + 兼容 Agent 列表
4. 用户勾选要启用的 Agent（兼容 Agent 默认勾选）
5. 确认后：更新 linked_skills + SymlinkManager 创建链接

### 删除 Skill 流程

1. 用户点击删除 → 确认对话框
2. Rust 端：移除 skill 目录 + 清理所有 Agent 的 symlink + 更新 linked_skills
3. SwiftUI 刷新列表

---

## 五、核心 Rust 模块

### 1. AgentRegistry (agent_registry.rs)

```
AgentRegistry::new(config_dir)
├── 加载内置 Agent（硬编码 5 个）
├── 加载 agents.json → 自定义 Agent
└── 合并返回 Vec<AgentConfig>

add_custom(input)   → 校验路径 → 生成 UUID → persist agents.json
remove_custom(id)   → 从 custom 列表移除 → persist
toggle_skill_link(agent_id, skill_id, enabled) → 更新 linked_skills → persist
all()               → builtin + custom 合并列表
find(id)            → Option<&AgentConfig>
```

> 预留扩展：后续可支持更多内置 Agent、导入导出配置等。

### 2. Scanner (scanner.rs)

```
Scanner::new(source_root)
scan_all()          → walkdir 一级子目录 → 解析 manifest.json + SKILL.md → Vec<SkillEntry>
detect_new()        → 对比上次扫描 → 返回新增 Skill
validate_skill_dir() → 检查 manifest.json + SKILL.md 存在
```

### 3. SymlinkManager (symlink.rs)

三种链接策略：

- **Directory**：`symlink(source_root/skill_id → agent.skills_path/skill_id)`
- **SingleFile**：合并所有 SKILL.md 内容 → 写入单一文件（如 copilot-instructions.md）
- **Overlay**：逐文件 symlink，不覆盖目标已有文件

链接前备份策略：如果目标已存在真实目录，自动重命名为 `.bak` 后缀。

### 4. GitEngine (git_engine.rs)

```
GitEngine::new(repo_url, source_root, auth)
├── AuthMethod::Anonymous（公共仓库） / OAuth(token)（私有仓库）
└── 首次 clone，后续 open

get_status()        → Idle / Modified / Conflicted / Pushing / Synced
stage_and_push()    → git add -A → commit → pull --rebase → push
get_pending_changes() → Vec<(file_path, status)>
```

### 5. Watcher (watcher.rs)

```
Watcher::start(source_root, callback)
├── notify-rs + macos_kqueue 监听 source_root 递归变化
├── 过滤：只关心 SKILL.md 的 Create/Modify/Delete 事件
├── 事件去抖：500ms 内合并（防编辑器临时文件）
└── 回调传递 JSON：{"event":"skill_changed","skill_id":"code-review"}
```

---

## 六、Swift UI 设计

### App 入口（参考 TokenViewer）

```swift
@main
struct SkillsManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        Settings { SettingsView() }
    }
}
```

### 状态管理

单例 `@MainActor ObservableObject` 模式（参考 TokenViewer 的 ViewModel 模式）：

```swift
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var agents: [AgentConfig] = []
    @Published var skills: [SkillEntry] = []
    @Published var gitStatus: GitStatus = .idle
    @Published var pendingChanges: [PendingChange] = []
    @Published var pendingNewSkill: SkillEntry? = nil
}
```

### 窗口布局

`NavigationSplitView` 三栏布局：

```
┌────────────┬───────────────────┬───────────────────────┐
│  Sidebar   │    Content Area   │   Detail / Inspector  │
│  📦 Agents  │                   │                       │
│  🧩 Skills  │                   │                       │
│  ⚙️ Sync    │                   │                       │
└────────────┴───────────────────┴───────────────────────┘
```

### Skills 管理页面（核心页面）

每一行展示：

```
┌─────────────────────────────────────────────────────┐
│ Skill                    │ Agents                    │ ... │
├──────────────────────────┼───────────────────────────┤ ... │
│ 📝 code-review           │ [Claude✓][Cursor✓][Zed ] │ 🗑  │
│ Review code quality      │                            │     │
└──────────────────────────┴───────────────────────────┘     │
```

- **Agent 标签切换**：绿色实心 = 已链接，灰色空心 = 未链接。点击直接切换 symlink
- **过滤**：全部 / 已启用 / 未链接 / 按 Agent 筛选 / 按 tag 筛选
- **删除**：确认对话框 → Rust 端删除目录 + 清理链接

### Agent 管理页面

- 展示所有 Agent（内置 + 自定义），每行显示 link 状态和关联 skill 数量
- 添加自定义 Agent：Sheet 输入名称 + 路径（支持 `~` 展开）+ 链接方式
- 内置 Agent 不可删除，仅 toggle 启用/禁用

### Sync 页面

- 显示 Git 同步状态 + 未推送修改列表
- 用户手动点击"推送修改"触发 Rust GitEngine
- OAuth 登录 GitHub（macOS Keychain 存储 token）

---

## 七、构建配置

### 目录结构

```
agent-skills-manager/
├── SkillsManager.xcodeproj
├── macos/SkillsManager/          # Swift 主 App
│   ├── App/SkillsManagerApp.swift
│   ├── Views/SkillsPanel/, AgentsPanel/, SyncPanel/
│   ├── Models/AppState.swift, DataModels.swift
│   ├── Bridge/CoreBridge.swift, SkillsManager-Bridging-Header.h
│   └── Resources/Info.plist, SkillsManager.entitlements
├── skills-core/                  # Rust 内核
│   ├── Cargo.toml
│   └── src/ffi.rs, models.rs, agent_registry.rs, scanner.rs,
│          symlink.rs, git_engine.rs, watcher.rs
└── scripts/release.sh, self_signed_codesign.sh, version.env
```

### Xcode Build Settings

| Setting | Value |
|---------|-------|
| `MACOSX_DEPLOYMENT_TARGET` | `14.0` |
| `SWIFT_VERSION` | `5.0` |
| `LIBRARY_SEARCH_PATHS` | `$(PROJECT_DIR)/../skills-core/target/aarch64-apple-darwin/release` |
| `OTHER_LDFLAGS` | `-force_load` + static lib + `-framework Security` |
| `SWIFT_OBJC_BRIDGING_HEADER` | `SkillsManager/Bridge/SkillsManager-Bridging-Header.h` |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.skills-manager.app` |
| `CODE_SIGN_ENTITLEMENTS` | `SkillsManager/Resources/SkillsManager.entitlements` |

### Build Phase Script

```bash
#!/bin/bash
export PATH="$HOME/.cargo/bin:$PATH"
cd "$PROJECT_DIR/../skills-core"
if [ "$CONFIGURATION" = "Release" ]; then
    cargo build --release --target aarch64-apple-darwin
else
    cargo build --target aarch64-apple-darwin
fi
```

### Cargo.toml

```toml
[lib]
crate-type = ["staticlib"]

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
git2 = { version = "0.19", features = ["ssh"] }
notify = { version = "6", features = ["macos_kqueue"] }
walkdir = "2"
dirs = "5"
uuid = { version = "1", features = ["v4"] }
chrono = { version = "0.4", features = ["serde"] }
```

---

## 八、关键决策汇总

| 决策点 | 选择 | 理由 |
|--------|------|------|
| Swift ↔ Rust 绑定 | C FFI | TokenViewer 已验证，API 量少，构建简单 |
| Skills 目录结构 | 扁平 + manifest.json | 目录浅，元数据管分类 |
| Source root 路径 | 用户可自定义 | 不硬编码 `~/.agent/skills` |
| GitHub 仓库类型 | 公共 + 私有双支持 | 公共匿名 clone，私有 OAuth |
| 私有仓库认证 | macOS Keychain + OAuth | 原生体验，系统级安全 |
| Git 冲突处理 | 标准 git merge | 利用 git2-rs 三路合并 |
| 文件监控行为 | 实时暂存 + 手动提交 | UI 显示变更数，用户点击推送 |
| 新 Skill 安装 | 用户选择关联 Agent | 不完全自动同步，给用户控制权 |
| Agent ↔ Skill 关系 | Agent 独立 linked_skills | 灵活按 Agent 控制，非全量同步 |
| Skill 格式 | 不做格式转换 | App 是文件管理器，格式由用户决定 |

---

## 九、FFI 函数清单

| C 函数 | 功能 |
|--------|------|
| `asm_init(source_root)` | 初始化 CoreHandle |
| `asm_destroy(handle)` | 销毁句柄 |
| `asm_list_agents(handle)` | 返回所有 Agent JSON |
| `asm_add_custom_agent(handle, json)` | 添加自定义 Agent |
| `asm_remove_custom_agent(handle, id)` | 删除自定义 Agent |
| `asm_list_skills(handle)` | 返回所有 Skill JSON |
| `asm_get_skill(handle, id)` | 获取单个 Skill |
| `asm_delete_skill(handle, id)` | 删除 Skill 及链接 |
| `asm_create_symlink(handle, agent_id, skill_id)` | 创建软链接 |
| `asm_remove_symlink(handle, agent_id, skill_id)` | 移除软链接 |
| `asm_get_git_status(handle)` | 获取 Git 状态 |
| `asm_stage_and_push(handle)` | Commit + Push |
| `asm_get_pending_changes(handle)` | 获取未提交变更列表 |
| `asm_start_watcher(handle, callback)` | 启动文件监控 |
| `asm_stop_watcher(handle)` | 停止文件监控 |
| `asm_free_string(ptr)` | 释放 C 字符串 |
| `asm_expand_path(path)` | 展开 `~` 为完整路径 |
