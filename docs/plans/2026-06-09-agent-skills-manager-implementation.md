# Agent Skills Manager Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 从零搭建 Agent Skills Manager macOS 应用，包含 Rust 内核（C FFI）+ SwiftUI 前端

**Architecture:** Rust core (staticlib) 通过 C FFI 暴露 JSON 序列化接口，Swift 侧 CoreBridge 封装 serial queue 调用。SwiftUI 使用 NavigationSplitView 三栏布局 + ObservableObject 单例状态管理。

**Tech Stack:** SwiftUI (macOS 14.0) + Rust (C FFI, staticlib) + git2-rs + notify-rs

**参考项目:** TokenViewer (/Users/wangsw/webkong/TokenViewer/tokenviewer) — SwiftUI 模式 / Xcode 配置 / C FFI 模板

---

### Phase 1: 项目骨架搭建

---

### Task 1: 创建 Rust crate（skills-core）

**Files:**
- Create: `skills-core/Cargo.toml`
- Create: `skills-core/src/lib.rs`
- Create: `skills-core/src/models.rs`
- Create: `skills-core/src/ffi.rs`
- Create: `skills-core/src/agent_registry.rs`
- Create: `skills-core/src/scanner.rs`
- Create: `skills-core/src/symlink.rs`
- Create: `skills-core/src/git_engine.rs`
- Create: `skills-core/src/watcher.rs`

**Step 1: 创建 Cargo.toml**

```toml
[package]
name = "skills-core"
version = "0.1.0"
edition = "2021"

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

**Step 2: 创建 lib.rs 和各模块骨架文件**

每个文件只含 `pub mod` 声明或空函数骨架，确保 `cargo build` 通过。

**Step 3: 验证编译**

```bash
cd skills-core && cargo build
```
Expected: 所有模块编译通过（函数体可为 `todo!()`）。

---

### Task 2: 创建 Xcode 项目框架

**Files:**
- Create: `SkillsManager.xcodeproj/` (通过 Xcode CLI 或手写 project.pbxproj)
- Create: `macos/SkillsManager/App/SkillsManagerApp.swift`
- Create: `macos/SkillsManager/Bridge/CoreBridge.swift`
- Create: `macos/SkillsManager/Bridge/SkillsManager-Bridging-Header.h`
- Create: `macos/SkillsManager/Models/AppState.swift`
- Create: `macos/SkillsManager/Models/DataModels.swift`
- Create: `macos/SkillsManager/Views/ContentView.swift`
- Create: `macos/SkillsManager/Resources/Info.plist`
- Create: `macos/SkillsManager/Resources/SkillsManager.entitlements`

**Step 1: 创建 macOS 目录结构和所有 Swift 源文件**

参考 TokenViewer 的目录布局：`macos/SkillsManager/App/`, `Bridge/`, `Models/`, `Views/`, `Resources/`。

**Step 2: 使用 xcodebuild 创建项目或手写 pbxproj**

参考 TokenViewer 的 `project.pbxproj` 配置：
- Bundle ID: `com.skills-manager.app`
- macOS 14.0 deployment target
- Bridging header path
- Library search paths 指向 `skills-core/target/aarch64-apple-darwin/release`
- OTHER_LDFLAGS: `-force_load` + static lib
- Build Phase: "Build Rust Core" script

**Step 3: 添加空 entitlements 和 Info.plist**

Info.plist 包含基本字段（CFBundleName, LSMinimumSystemVersion 14.0 等）。entitlements 为空 `<dict/>`。

---

### Phase 2: Rust 数据模型与核心模块

---

### Task 3: 实现 models.rs（共享数据结构）

**Files:**
- Modify: `skills-core/src/models.rs`

**Step 1: 定义所有数据结构**

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentConfig {
    pub id: String,
    pub name: String,
    pub skills_path: String,
    pub link_type: LinkType,
    pub is_builtin: bool,
    pub is_linked: bool,
    pub linked_skills: Vec<String>,
    pub icon: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum LinkType {
    Directory,
    SingleFile,
    Overlay,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillManifest {
    pub name: String,
    pub description: String,
    pub tags: Vec<String>,
    pub compatible_agents: Vec<String>,
    pub version: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillEntry {
    pub id: String,
    pub manifest: SkillManifest,
    pub source_dir: String,
    pub installed_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CustomAgentInput {
    pub name: String,
    pub skills_path: String,
    pub link_type: LinkType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatus {
    pub status: String,  // "idle" | "modified" | "conflicted" | "synced"
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingChange {
    pub file_path: String,
    pub change_type: String,  // "modified" | "added" | "deleted"
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WatcherEvent {
    pub event: String,  // "new_skill" | "skill_changed" | "skill_removed"
    pub skill_id: String,
}
```

**Step 2: cargo build 验证序列化正确**

---

### Task 4: 实现 agent_registry.rs

**Files:**
- Modify: `skills-core/src/agent_registry.rs`

实现函数：
1. `builtin_agents()` — 返回 5 个内置 Agent
2. `AgentRegistry::new(config_dir)` — 加载内置 + agents.json
3. `add_custom(&mut self, input: CustomAgentInput) -> Result<AgentConfig, String>`
4. `remove_custom(&mut self, id: &str) -> Result<(), String>`
5. `link_skill(&mut self, agent_id: &str, skill_id: &str) -> Result<(), String>`
6. `unlink_skill(&mut self, agent_id: &str, skill_id: &str) -> Result<(), String>`
7. `all(&self) -> Vec<AgentConfig>`
8. `find(&self, id: &str) -> Option<&AgentConfig>`
9. `expand_path(raw: &str) -> Result<PathBuf, String>`
10. `persist(&self) -> Result<(), String>` — 写 agents.json

---

### Task 5: 实现 scanner.rs

**Files:**
- Modify: `skills-core/src/scanner.rs`

实现函数：
1. `Scanner::new(source_root: PathBuf)`
2. `scan_all(&self) -> Result<Vec<SkillEntry>, String>` — walkdir 一级，解析 manifest.json + SKILL.md
3. `detect_new(&self, known: &HashSet<String>) -> Vec<SkillEntry>` — 过滤新 skill
4. `validate_skill_dir(path: &Path) -> bool` — 检查 manifest.json 和 SKILL.md

**Step 3: 在 skills-core 根目录创建测试数据**

创建 `test-fixtures/skills/code-review/` 含 SKILL.md 和 manifest.json，用于手动测试 scanner。

---

### Task 6: 实现 symlink.rs

**Files:**
- Modify: `skills-core/src/symlink.rs`

实现函数：
1. `SymlinkManager::new(source_root: PathBuf)`
2. `create_skill_link(&self, agent: &AgentConfig, skill_id: &str) -> Result<(), String>` — 根据 link_type 分发
3. `link_directory(source, target)` — 目录级 symlink + 备份
4. `link_single_file(source, target)` — 合并 SKILL.md 到单文件
5. `link_overlay(source, target)` — 逐文件 symlink
6. `remove_skill_link(&self, agent: &AgentConfig, skill_id: &str) -> Result<(), String>`
7. `remove_all_links(&self, agent: &AgentConfig) -> Result<(), String>` — 移除 Agent 所有 symlink

---

### Task 7: 实现 git_engine.rs (MVP 版)

**Files:**
- Modify: `skills-core/src/git_engine.rs`

**MVP 实现**: 先支持本地仓库的 stage + commit + push（暂不处理 OAuth clone，Phase 1 用已有仓库）：

1. `GitEngine::new(repo_path: &Path) -> Result<Self, String>`
2. `get_status(&self) -> Result<GitStatus, String>` — git2::Status
3. `stage_and_push(&self, message: &str) -> Result<(), String>` — add → commit → push
4. `get_pending_changes(&self) -> Result<Vec<PendingChange>, String>`

---

### Task 8: 实现 watcher.rs (MVP 版)

**Files:**
- Modify: `skills-core/src/watcher.rs`

**MVP 实现**: 触发时直接执行传入的闭包（Rust 侧闭包，暂不跨 FFI 回调）：

1. `Watcher::start(source_root: &Path, on_event: impl Fn(WatcherEvent) + Send + 'static) -> Result<Self, String>`
2. 使用 notify-rs + macos_kqueue 监听 source_root
3. 过滤 SKILL.md 事件，去抖 500ms
4. 触发时调用 on_event 闭包
5. `Watcher::stop(&self)` — Drop 时自动停止

---

### Phase 3: Rust FFI 层

---

### Task 9: 实现 ffi.rs

**Files:**
- Modify: `skills-core/src/ffi.rs`

实现所有 C FFI 函数：

```rust
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

pub struct CoreHandle {
    pub registry: AgentRegistry,
    pub scanner: Scanner,
    pub symlink: SymlinkManager,
    pub git: Option<GitEngine>,
    pub watcher: Option<Watcher>,
    pub config_dir: PathBuf,
}

// 内存管理
#[no_mangle] pub extern "C" fn asm_init(source_root: *const c_char) -> *mut CoreHandle
#[no_mangle] pub extern "C" fn asm_destroy(handle: *mut CoreHandle)
#[no_mangle] pub extern "C" fn asm_free_string(ptr: *mut c_char)
#[no_mangle] pub extern "C" fn asm_expand_path(path: *const c_char) -> *mut c_char

// Agent 管理
#[no_mangle] pub extern "C" fn asm_list_agents(handle: *mut CoreHandle) -> *mut c_char
#[no_mangle] pub extern "C" fn asm_add_custom_agent(handle: *mut CoreHandle, json: *const c_char) -> *mut c_char
#[no_mangle] pub extern "C" fn asm_remove_custom_agent(handle: *mut CoreHandle, agent_id: *const c_char) -> u8

// Skill 管理
#[no_mangle] pub extern "C" fn asm_list_skills(handle: *mut CoreHandle) -> *mut c_char
#[no_mangle] pub extern "C" fn asm_get_skill(handle: *mut CoreHandle, skill_id: *const c_char) -> *mut c_char
#[no_mangle] pub extern "C" fn asm_delete_skill(handle: *mut CoreHandle, skill_id: *const c_char) -> u8

// Symlink 操作
#[no_mangle] pub extern "C" fn asm_create_symlink(handle: *mut CoreHandle, agent_id: *const c_char, skill_id: *const c_char) -> u8
#[no_mangle] pub extern "C" fn asm_remove_symlink(handle: *mut CoreHandle, agent_id: *const c_char, skill_id: *const c_char) -> u8

// Git 同步
#[no_mangle] pub extern "C" fn asm_get_git_status(handle: *mut CoreHandle) -> *mut c_char
#[no_mangle] pub extern "C" fn asm_stage_and_push(handle: *mut CoreHandle) -> *mut c_char
#[no_mangle] pub extern "C" fn asm_get_pending_changes(handle: *mut CoreHandle) -> *mut c_char

// 文件监控 (MVP: callback 参数预留，先不做跨 FFI 回调)
#[no_mangle] pub extern "C" fn asm_start_watcher(handle: *mut CoreHandle) -> u8
#[no_mangle] pub extern "C" fn asm_stop_watcher(handle: *mut CoreHandle)
```

模式：所有返回 `*mut c_char` 的函数内部用 `serde_json::to_string` + `CString::new`，调用方负责 `asm_free_string`。返回 `u8` 的函数 0=失败 1=成功。

---

### Phase 4: Swift 桥接层

---

### Task 10: 实现 Swift DataModels

**Files:**
- Modify: `macos/SkillsManager/Models/DataModels.swift`

实现与 Rust 侧对应的 Codable structs：

```swift
struct AgentConfig: Codable, Identifiable {
    let id: String
    let name: String
    let skillsPath: String
    let linkType: LinkType
    let isBuiltin: Bool
    var isLinked: Bool
    var linkedSkills: [String]
    let icon: String?
}

enum LinkType: String, Codable {
    case directory = "Directory"
    case singleFile = "SingleFile"
    case overlay = "Overlay"
}

struct SkillEntry: Codable, Identifiable {
    let id: String
    let manifest: SkillManifest
    let sourceDir: String
    let installedAt: String
}

struct SkillManifest: Codable {
    let name: String
    let description: String
    let tags: [String]
    let compatibleAgents: [String]
    let version: String
}

struct CustomAgentInput: Codable {
    let name: String
    let skillsPath: String
    let linkType: LinkType
}

struct GitStatusInfo: Codable {
    let status: String
    let message: String?
}

struct PendingChange: Codable, Identifiable {
    var id: String { filePath }
    let filePath: String
    let changeType: String
}

struct WatcherEvent: Codable {
    let event: String
    let skillId: String
}
```

使用 `CodingKeys` 将 Rust 的 snake_case 映射到 Swift 的 camelCase。

---

### Task 11: 实现 CoreBridge.swift

**Files:**
- Modify: `macos/SkillsManager/Bridge/CoreBridge.swift`

参考 TokenViewer 的 CoreBridge 模式：
- Serial `DispatchQueue` (label: "com.skills-manager.core")
- 所有 FFI 调用经 `queue.sync { }`
- 每个方法：调用 FFI → `String(cString:)` 复制 → `asm_free_string()` → JSONDecoder

```swift
final class CoreBridge: @unchecked Sendable {
    static let shared = CoreBridge()
    private let handle: UnsafeMutableRawPointer
    private let queue = DispatchQueue(label: "com.skills-manager.core")

    init() { ... }  // asm_init()
    deinit { asm_destroy(handle) }

    func listAgents() -> [AgentConfig] { ... }
    func addCustomAgent(_ input: CustomAgentInput) -> AgentConfig? { ... }
    func removeCustomAgent(_ id: String) -> Bool { ... }
    func listSkills() -> [SkillEntry] { ... }
    func getSkill(_ id: String) -> SkillEntry? { ... }
    func deleteSkill(_ id: String) -> Bool { ... }
    func createSymlink(agentId: String, skillId: String) -> Bool { ... }
    func removeSymlink(agentId: String, skillId: String) -> Bool { ... }
    func getGitStatus() -> GitStatusInfo? { ... }
    func stageAndPush() -> GitStatusInfo? { ... }
    func getPendingChanges() -> [PendingChange] { ... }
    func startWatcher() -> Bool { ... }
    func stopWatcher() { ... }
}
```

---

### Task 12: 创建 Bridging Header

**Files:**
- Modify: `macos/SkillsManager/Bridge/SkillsManager-Bridging-Header.h`

声明所有 `asm_*` C 函数原型，与 `ffi.rs` 一一对应。

---

### Phase 5: Swift UI 层

---

### Task 13: 实现 AppState (ObservableObject)

**Files:**
- Modify: `macos/SkillsManager/Models/AppState.swift`

```swift
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var agents: [AgentConfig] = []
    @Published var skills: [SkillEntry] = []
    @Published var gitStatus: GitStatusInfo = GitStatusInfo(status: "idle", message: nil)
    @Published var pendingChanges: [PendingChange] = []
    @Published var pendingNewSkill: SkillEntry? = nil
    @Published var isLoading = false

    private let core = CoreBridge.shared

    func loadInitialData() { ... }
    func toggleSkillLink(skillId: String, agentId: String, enabled: Bool) { ... }
    func deleteSkill(skillId: String) { ... }
    func pushChanges() { ... }
    func addCustomAgent(_ input: CustomAgentInput) { ... }
    func removeCustomAgent(_ id: String) { ... }
    func refresh() { ... }
}
```

---

### Task 14: 实现 SkillsManagerApp.swift (App 入口)

**Files:**
- Modify: `macos/SkillsManager/App/SkillsManagerApp.swift`

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.loadInitialData()
    }
    func applicationWillTerminate(_ notification: Notification) {
        CoreBridge.shared.stopWatcher()
    }
}
```

---

### Task 15: 实现 ContentView（三栏布局）

**Files:**
- Modify: `macos/SkillsManager/Views/ContentView.swift`

```swift
struct ContentView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var selectedTab: SidebarTab = .skills

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentArea
        } detail: {
            detailArea
        }
    }

    enum SidebarTab: String, CaseIterable {
        case agents, skills, sync
    }

    @ViewBuilder
    private var sidebar: some View { ... }
    @ViewBuilder
    private var contentArea: some View { ... }
    @ViewBuilder
    private var detailArea: some View { ... }
}
```

---

### Task 16: 实现 SkillsListView（核心页面）

**Files:**
- Create: `macos/SkillsManager/Views/SkillsPanel/SkillsListView.swift`

核心交互页面：
- 每行显示 Skill 名称 + 描述 + Agent 标签
- 标签点击 toggle symlink
- 删除按钮 + 确认对话框
- 搜索 + 过滤（全部/已启用/按 Agent/按 tag）

---

### Task 17: 实现 AgentsListView

**Files:**
- Create: `macos/SkillsManager/Views/AgentsPanel/AgentsListView.swift`

- 展示内置 + 自定义 Agent
- 每行显示 linked skills 数量
- "添加 Agent" 触发 Sheet
- Toggle 启用/禁用

---

### Task 18: 实现 AddAgentSheet

**Files:**
- Create: `macos/SkillsManager/Views/AgentsPanel/AddAgentSheet.swift`

- 名称输入 + 路径输入（支持 ~）
- 链接方式 Picker（Directory/SingleFile/Overlay）
- NSOpenPanel 选择按钮
- 实时路径展开预览
- 确认按钮
- 路径有效性指示

---

### Task 19: 实现 SyncView

**Files:**
- Create: `macos/SkillsManager/Views/SyncPanel/SyncView.swift`

- 显示 Git 状态
- 未推送修改列表
- "推送修改" 按钮
- "登录 GitHub" 入口（MVP 可占位）

---

### Task 20: 实现 SettingsView

**Files:**
- Create: `macos/SkillsManager/Views/Settings/SettingsView.swift`

- Source root 路径设置
- GitHub 仓库 URL 设置
- 默认链接方式设置

---

### Phase 6: 构建集成与验证

---

### Task 21: 配置 Xcode Build Phase

**Files:**
- Modify: `SkillsManager.xcodeproj/project.pbxproj`

- 添加 "Build Rust Core" Run Script Phase
- 脚本内容：`cd skills-core && cargo build --release --target aarch64-apple-darwin` (Release) / 不带 `--release` (Debug)
- 确保 Phase 在 "Compile Sources" 之前执行

---

### Task 22: 端到端验证

1. `cargo build --release --target aarch64-apple-darwin` 在 skills-core 目录通过
2. Xcode Build (⌘B) 通过
3. App 启动后能列出 5 个内置 Agent
4. 能在 test-fixtures 目录创建示例 skill 并导入

---

### Task 23: 创建打包脚本

**Files:**
- Create: `scripts/release.sh`
- Create: `scripts/self_signed_codesign.sh`
- Create: `scripts/version.env`

参考 TokenViewer 的 `scripts/` 目录结构和 release.sh。

---

## 实施顺序依赖关系

```
Phase 1 (Task 1-2)     ← 项目骨架，无依赖
    │
Phase 2 (Task 3-8)     ← 依赖 Task 1 models.rs
    │
Phase 3 (Task 9)       ← 依赖 Phase 2 全部模块
    │
Phase 4 (Task 10-12)  ← 依赖 Task 9 ffi.rs
    │
Phase 5 (Task 13-20)  ← 依赖 Phase 4 (CoreBridge) + Phase 2 (DataModels)
    │
Phase 6 (Task 21-23)  ← 依赖全部前序
```

`task_in_parallel` 标记：Phase 2 内的 Task 4（agent_registry）、Task 5（scanner）、Task 6（symlink）可以并行开发（它们只依赖 Task 3 models.rs）。Task 7（git_engine）和 Task 8（watcher）也可并行。

Phase 5 内的 Task 16（SkillsListView）、Task 17（AgentsListView）、Task 19（SyncView）可并行开发（都只依赖 AppState）。
