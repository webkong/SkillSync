import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { Apple, ArrowDown, Check, ExternalLink, Github, GitPullRequest, Layers, RefreshCw, Share2, Eye, FolderTree, Zap } from "lucide-react";
import "./styles.css";

const SITE_URL = "https://skillsync.webkong.top";
const GITHUB_REPO_URL = "https://github.com/webkong/SkillSync";
const DMG_DOWNLOAD_URL = "https://github.com/webkong/SkillSync/releases/latest/download/SkillSync.dmg";
const LANGUAGE_STORAGE_KEY = "skillsync-site-language";

const AGENT_LIST = [
  "Claude Code", "Cursor", "Codex", "Windsurf", "Copilot",
  "OpenClaw", "Opencode", "Gemini CLI", "CodeBuddy", "Kiro",
  "Qoder", "Hermes", "Trae", "Zed", "Antigravity",
  "Kimi", "Grok", "WorkBuddy", "Roocode", "Kilo Code",
  "KiloCLI", "Goose", "OhMyPi", "Pi", "Craft",
];

const copy = {
  en: {
    htmlLang: "en",
    pageTitle: "SkillSync - Unified Skill Management for AI Coding Agents",
    pageDescription:
      "SkillSync is a free, native macOS menu-bar app that centrally manages AI coding agent skills and prompts across 25+ tools — Claude Code, Cursor, Copilot, Windsurf and more.",
    pageKeywords:
      "AI skills manager, prompt management macOS, Claude Code skills, Cursor prompts, coding agent skills, skill sync, macOS menu bar app",
    brandHome: "SkillSync home",
    nav: {
      features: "Features",
      providers: "Agents",
      about: "About",
      github: "GitHub",
      download: "Download free",
      language: "中文",
      languageLabel: "Switch language",
    },
    hero: {
      title: "Unified skill management for AI coding agents",
      description:
        "SkillSync lives in your menu bar and centrally manages skills and prompts across 25+ AI coding tools. Move, organize, and sync — all from one place.",
      primary: "Download for macOS",
      secondary: "See features",
      proof: ["Free", "25+ agents", "Local-first"],
      previewLabel: "SkillSync menu-bar panel preview",
    },
    features: [
      {
        icon: FolderTree,
        title: "Centralize all skills",
        text: "Move scattered skill files from every agent into a single ~/.agent/skills directory. One source of truth for all your prompts.",
      },
      {
        icon: Share2,
        title: "Distribute via symlinks",
        text: "Choose from 3 strategies — Directory, SingleFile, or Overlay — to share skills across agents while keeping each tool working normally.",
      },
      {
        icon: GitPullRequest,
        title: "Git sync built in",
        text: "Push and pull your skill collection to any Git repository. PAT authentication for GitHub, GitLab, or self-hosted servers.",
      },
      {
        icon: Eye,
        title: "Real-time file watching",
        text: "New or changed skill files are detected instantly. The app maintains an SQLite index so nothing gets lost.",
      },
    ],
    story: {
      title: "Your skills, under one roof.",
      description:
        "When you use multiple AI coding agents, skills and prompts end up scattered across different directories. SkillSync brings everything together — without breaking any of your existing workflows.",
      timeline: [
        "Skills are scattered across agent directories",
        "SkillSync moves them to a central source directory",
        "Symlinks keep every agent working seamlessly",
        "Git sync backs everything up and enables sharing",
      ],
    },
    linkTypes: {
      title: "Three symlink strategies",
      description: "Each agent supports a link type that matches how it reads skill files.",
      types: [
        { name: "Directory", desc: "Symlink the whole directory — agent reads all skills inside." },
        { name: "SingleFile", desc: "Merge all skills into one file at the agent's skills path." },
        { name: "Overlay", desc: "Symlink individual skill files for fine-grained control." },
      ],
    },
    agents: {
      title: "25 supported agents",
      description: "SkillSync works with the AI coding tools you already use — out of the box.",
    },
    footer: {
      download: "Download DMG",
      copyright: "\u00a9 2026 webkong. All rights reserved.",
    },
  },
  zh: {
    htmlLang: "zh-CN",
    pageTitle: "SkillSync - AI 编程助手技能统一管理工具",
    pageDescription:
      "SkillSync 是一款免费的原生 macOS 菜单栏应用，统一管理 25+ 个 AI 编程工具的技能和提示词 — 包括 Claude Code、Cursor、Copilot、Windsurf 等。",
    pageKeywords:
      "AI 技能管理, 提示词管理 macOS, Claude Code 技能, Cursor 提示词, 编程助手技能, 技能同步, macOS 菜单栏应用",
    brandHome: "SkillSync 官网首页",
    nav: {
      features: "功能",
      providers: "支持工具",
      about: "关于",
      github: "GitHub",
      download: "免费下载",
      language: "EN",
      languageLabel: "切换语言",
    },
    hero: {
      title: "AI 编程助手技能，统一管理",
      description:
        "SkillSync 驻守在菜单栏，统一管理 25+ 个 AI 编程工具的技能与提示词。移动、整理、同步——一个工具全部搞定。",
      primary: "下载 macOS 版本",
      secondary: "查看功能",
      proof: ["永久免费", "支持 25+ 工具", "本地优先"],
      previewLabel: "SkillSync 菜单栏面板预览",
    },
    features: [
      {
        icon: FolderTree,
        title: "集中管理所有技能",
        text: "将分散在各个 Agent 目录下的技能文件统一移动到 ~/.agent/skills。一个目录，管理所有提示词。",
      },
      {
        icon: Share2,
        title: "通过符号链接分发",
        text: "三种链接策略——目录、单文件、覆盖——灵活共享技能，同时保持每个工具正常工作。",
      },
      {
        icon: GitPullRequest,
        title: "内置 Git 同步",
        text: "一键推拉技能集到任意 Git 仓库。支持 GitHub、GitLab 和自托管服务器的 PAT 认证。",
      },
      {
        icon: Eye,
        title: "实时文件监控",
        text: "新增或变更的技能文件会被即时检测。SQLite 索引确保不会丢失任何数据。",
      },
    ],
    story: {
      title: "所有技能，统一管理。",
      description:
        "当你使用多个 AI 编程助手时，技能和提示词散落在不同目录中。SkillSync 将它们集中到一起——而不会破坏你现有的任何工作流。",
      timeline: [
        "技能分散在多个 Agent 目录下",
        "SkillSync 将它们移动到统一目录",
        "符号链接让每个 Agent 继续正常工作",
        "Git 同步备份所有技能，方便团队共享",
      ],
    },
    linkTypes: {
      title: "三种符号链接策略",
      description: "每种 Agent 支持不同的链接方式，匹配其读取技能文件的方式。",
      types: [
        { name: "目录链接", desc: "对整个目录创建符号链接——Agent 读取内部所有技能。" },
        { name: "单文件合并", desc: "将所有技能合并到 Agent 技能路径的一个文件中。" },
        { name: "覆盖模式", desc: "对单个技能文件分别创建符号链接，精细控制。" },
      ],
    },
    agents: {
      title: "支持 25 个工具",
      description: "SkillSync 开箱即用，支持你正在使用的 AI 编程工具。",
    },
    footer: {
      download: "下载 DMG",
      copyright: "\u00a9 2026 webkong. 保留所有权利。",
    },
  },
};

const AGENT_LOGOS = {
  "Claude Code": "claude-code",
  "Cursor": "cursor",
  "Codex": "codex",
  "Windsurf": "windsurf",
  "Copilot": "copilot",
  "OpenClaw": "openclaw",
  "Opencode": "opencode",
  "Gemini CLI": "gemini",
  "CodeBuddy": "codebuddy",
  "Kiro": "kiro",
  "Qoder": "qoder",
  "Hermes": "hermes",
  "Trae": "trae",
  "Zed": "zed",
  "Antigravity": "antigravity",
  "Kimi": "kimi",
  "Grok": "grok",
  "WorkBuddy": "workbuddy",
  "Roocode": "roocode",
  "Kilo Code": "kilocode",
  "KiloCLI": "kilocli",
  "Goose": "goose",
  "OhMyPi": "ohmypi",
  "Pi": "pi",
  "Craft": "craft",
};

function getInitialLanguage() {
  const params = new URLSearchParams(window.location.search);
  const queryLang = params.get("lang");
  if (queryLang === "zh" || queryLang === "en") return queryLang;
  const stored = window.localStorage.getItem(LANGUAGE_STORAGE_KEY);
  if (stored === "zh" || stored === "en") return stored;
  return navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en";
}

function App() {
  const [language, setLanguage] = useState(getInitialLanguage);
  const t = copy[language];

  useEffect(() => {
    document.documentElement.lang = t.htmlLang;
    document.title = t.pageTitle;
    let desc = document.querySelector('meta[name="description"]');
    if (!desc) { desc = document.createElement("meta"); desc.name = "description"; document.head.appendChild(desc); }
    desc.content = t.pageDescription;
    window.localStorage.setItem(LANGUAGE_STORAGE_KEY, language);
    const url = new URL(window.location.href);
    url.searchParams.set("lang", language);
    window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`);
  }, [language, t]);

  return (
    <main className="site-shell">
      <div className="ambient ambient-one" />
      <div className="ambient ambient-two" />
      <Navigation t={t} onToggleLanguage={() => setLanguage(l => l === "en" ? "zh" : "en")} />
      <Hero t={t} />
      <FeatureBand t={t} />
      <ProductStory t={t} />
      <LinkTypesSection t={t} />
      <ScreenshotRow />
      <AgentsSection t={t} />
      <Footer t={t} />
    </main>
  );
}

function Navigation({ t, onToggleLanguage }) {
  return (
    <header className="nav-wrap">
      <nav className="nav">
        <a className="brand" href="/" aria-label={t.brandHome}>
          <img src="/skillsync-logo.png" alt="" />
          <span>SkillSync</span>
        </a>
        <div className="nav-links">
          <a href="/#features">{t.nav.features}</a>
          <a href="/#agents">{t.nav.providers}</a>
          <a href={GITHUB_REPO_URL} target="_blank" rel="noreferrer">{t.nav.github}</a>
        </div>
        <div className="nav-actions">
          <button className="language-toggle" type="button" onClick={onToggleLanguage} aria-label={t.nav.languageLabel}>
            {t.nav.language}
          </button>
          <a className="nav-cta" href={DMG_DOWNLOAD_URL}>{t.nav.download}</a>
        </div>
      </nav>
    </header>
  );
}

function Hero({ t }) {
  return (
    <section className="hero" id="top">
      <div className="hero-copy">
        <h1>{t.hero.title}</h1>
        <p>{t.hero.description}</p>
        <div className="hero-actions" id="download">
          <a className="primary-button" href={DMG_DOWNLOAD_URL}>
            <Apple size={19} />
            {t.hero.primary}
          </a>
          <a className="secondary-button" href="#features">
            {t.hero.secondary}
            <ArrowDown size={17} />
          </a>
        </div>
        <div className="hero-proof" aria-label="Product highlights">
          {t.hero.proof.map(item => (
            <span key={item}><Check size={16} />{item}</span>
          ))}
        </div>
      </div>
      <div className="hero-visual" aria-label={t.hero.previewLabel}>
        <DashboardPreview />
      </div>
    </section>
  );
}

function DashboardPreview() {
  const agents = [
    { name: "Claude Code", icon: "claude-code" },
    { name: "Cursor", icon: "cursor" },
    { name: "Copilot", icon: "copilot" },
    { name: "Windsurf", icon: "windsurf" },
    { name: "Codex", icon: "codex" },
  ];
  return (
    <div className="panel-stage">
      <div className="panel-glow" />
      <div className="clip-panel">
        <div className="panel-header">
          <div className="panel-logo">S</div>
          <span>SkillSync</span>
          <div className="panel-spacer" />
          <RefreshCw size={13} style={{ opacity: 0.5 }} />
        </div>
        <div className="metric-grid">
          <div className="metric-card" style={{ "--tint": "#0891B2" }}>
            <div className="metric-label">Skills</div>
            <div className="metric-value">24</div>
            <div className="metric-sub">organized</div>
          </div>
          <div className="metric-card" style={{ "--tint": "#22D3EE" }}>
            <div className="metric-label">Agents</div>
            <div className="metric-value">5</div>
            <div className="metric-sub">linked</div>
          </div>
          <div className="metric-card" style={{ "--tint": "#06B6D4" }}>
            <div className="metric-label">Source</div>
            <div className="metric-value">OK</div>
            <div className="metric-sub">~/.agent/skills</div>
          </div>
          <div className="metric-card" style={{ "--tint": "#67E8F9" }}>
            <div className="metric-label">Git</div>
            <div className="metric-value">Synced</div>
            <div className="metric-sub">main</div>
          </div>
        </div>
        <div className="agent-strip">
          {agents.map(a => (
            <div className="agent-chip" key={a.name}>
              <img src={`/logos/${a.icon}.svg`} alt="" width={16} height={16}
                onError={e => { e.currentTarget.style.display = "none"; }} />
              {a.name}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function FeatureBand({ t }) {
  return (
    <section className="feature-band" id="features">
      {t.features.map(({ icon: Icon, title, text }) => (
        <article className="feature-card" key={title}>
          <div className="feature-icon"><Icon size={24} /></div>
          <h2>{title}</h2>
          <p>{text}</p>
        </article>
      ))}
    </section>
  );
}

function ProductStory({ t }) {
  return (
    <section className="story-section">
      <div>
        <h2>{t.story.title}</h2>
        <p>{t.story.description}</p>
      </div>
      <div className="workflow-card">
        {t.story.timeline.map((item, index) => (
          <div className="workflow-step" key={item}>
            <span>{index + 1}</span>
            <p>{item}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

function LinkTypesSection({ t }) {
  return (
    <section className="link-types-section">
      <div className="link-types-copy">
        <Layers size={34} />
        <h2>{t.linkTypes.title}</h2>
        <p>{t.linkTypes.description}</p>
      </div>
      <div className="link-types-grid">
        {t.linkTypes.types.map(({ name, desc }) => (
          <div className="link-type-card" key={name}>
            <h3>{name}</h3>
            <p>{desc}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

function ScreenshotRow() {
  return (
    <section className="screenshots-row">
      {["s1.png", "s2.png", "s3.png"].map(f => (
        <img height="100%" key={f} src={`/screenshot/${f}`} alt="SkillSync screenshot" className="screenshot-img"
          onError={e => { e.currentTarget.style.display = "none"; }} />
      ))}
    </section>
  );
}

function AgentsSection({ t }) {
  return (
    <section className="agents-section" id="agents">
      <div className="agents-copy">
        <Zap size={34} />
        <h2>{t.agents.title}</h2>
        <p>{t.agents.description}</p>
      </div>
      <div className="agents-grid">
        {AGENT_LIST.map(name => {
          const logoKey = AGENT_LOGOS[name];
          return (
            <div className="agent-chip" key={name}>
              {logoKey && (
                <img
                  src={`/logos/${logoKey}.svg`}
                  alt=""
                  width={16} height={16}
                  style={{ display: "inline-block", verticalAlign: "middle", marginRight: 5 }}
                  onError={e => { e.currentTarget.style.display = "none"; }}
                />
              )}
              {name}
            </div>
          );
        })}
      </div>
    </section>
  );
}

function Footer({ t }) {
  return (
    <footer className="footer">
      <div className="footer-main">
        <div className="brand footer-brand">
          <img src="/skillsync-logo.png" alt="" />
          <span>SkillSync</span>
        </div>
        <div className="footer-links">
          <a href={GITHUB_REPO_URL} target="_blank" rel="noreferrer">
            <Github size={16} /> GitHub
          </a>
          <a href={DMG_DOWNLOAD_URL}>
            <ExternalLink size={16} /> {t.footer.download}
          </a>
        </div>
      </div>
      <p className="footer-copyright">{t.footer.copyright}</p>
    </footer>
  );
}

createRoot(document.getElementById("root")).render(
  <React.StrictMode><App /></React.StrictMode>
);

export default App;
