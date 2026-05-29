#!/usr/bin/env node

const readline = require("readline");
const http = require("http");
const fs = require("fs");
const path = require("path");

// ---------------------------------------------------------------------------
// Env loader
// ---------------------------------------------------------------------------
function loadEnv() {
  const envPath = path.join(__dirname, ".env");
  if (!fs.existsSync(envPath)) return {};
  const vars = {};
  for (const line of fs.readFileSync(envPath, "utf-8").split("\n")) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const i = t.indexOf("=");
    if (i === -1) continue;
    vars[t.slice(0, i).trim()] = t.slice(i + 1).trim();
  }
  return vars;
}

const env = loadEnv();
const PORT = env.PORT || process.env.PORT || 3000;
const API_KEY = env.CODEBLOX_API_KEY || process.env.CODEBLOX_API_KEY || "codeblox-default-key";
const BASE = `http://localhost:${PORT}`;

// ---------------------------------------------------------------------------
// Subcommand routing
// ---------------------------------------------------------------------------
const sub = process.argv[2];
if (sub === "server") { require("./server.js"); }
else if (sub === "dev") { require("./server.js"); setTimeout(() => startREPL(), 500); }
else { startREPL(); }

function startREPL() {

// ---------------------------------------------------------------------------
// ANSI helpers
// ---------------------------------------------------------------------------
const R = "\x1b[0m";
const DIM = "\x1b[90m";

const themes = {
  black: { fg: "\x1b[97m", dim: "\x1b[90m", hi: "\x1b[1;97m", box: "\x1b[90m", sel: "\x1b[1;97m" },
  white: { fg: "\x1b[30m", dim: "\x1b[37m", hi: "\x1b[1;30m", box: "\x1b[37m", sel: "\x1b[1;30m" },
};
let theme = env.DEFAULT_THEME || "black";
let connected = false;
let serverInfo = {};

const T = () => themes[theme] || themes.black;
const c = (s) => `${T().fg}${s}${R}`;
const hi = (s) => `${T().hi}${s}${R}`;
const dim = (s) => `${T().dim}${s}${R}`;
const box = (s) => `${T().box}${s}${R}`;
const sel = (s) => `${T().sel}${s}${R}`;

function w(s) { return s.replace(/\x1b\[[0-9;]*m/g, "").length; }
function pad(s, n) { return s + " ".repeat(Math.max(0, n - w(s))); }

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------
const COLS = process.stdout.columns || 80;
const IW = Math.min(COLS - 4, 76);

function top()  { return box("╭" + "─".repeat(IW) + "╮"); }
function mid()  { return box("├" + "─".repeat(IW) + "┤"); }
function bot()  { return box("╰" + "─".repeat(IW) + "╯"); }

function line(text, align) {
  const t = w(text);
  const space = IW - 2 - t;
  if (align === "center") {
    const l = Math.floor(space / 2);
    return box("│") + " ".repeat(l) + text + " ".repeat(space - l) + box(" │");
  }
  return box("│ ") + text + " ".repeat(Math.max(0, IW - 2 - t)) + box("│");
}

function drawBox(title, contentLines) {
  const out = [top(), line(hi(title), "center"), mid()];
  for (const l of contentLines) out.push(line(" " + l));
  out.push(bot());
  return out;
}

function printBox(title, contentLines) {
  for (const l of drawBox(title, contentLines)) console.log(l);
}

// ---------------------------------------------------------------------------
// Interactive select (arrow keys)
// ---------------------------------------------------------------------------
function selectPrompt(title, items) {
  // items: [{ label, value, active? }]
  return new Promise((resolve) => {
    let cursor = Math.max(0, items.findIndex(i => i.active));
    if (cursor < 0) cursor = 0;
    const totalLines = items.length + 4; // top + title + mid + items + bot

    function render() {
      // move cursor up to redraw area
      if (render.drawn) {
        process.stdout.write(`\x1b[${totalLines}A`);
      }

      const lines = [top(), line(hi(title), "center"), mid()];
      for (let i = 0; i < items.length; i++) {
        const it = items[i];
        const isCursor = i === cursor;
        const marker = isCursor ? sel(" > ") : dim("   ");
        const label = isCursor ? sel(it.label) : c(it.label);
        lines.push(line(marker + label));
      }
      lines.push(bot());

      for (const l of lines) console.log(l);
      render.drawn = true;
    }

    render();

    // Raw mode for keypress capture
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.setEncoding("utf8");

    function onKey(key) {
      if (key === "\x1b[A") { // up
        cursor = (cursor - 1 + items.length) % items.length;
        render();
      } else if (key === "\x1b[B") { // down
        cursor = (cursor + 1) % items.length;
        render();
      } else if (key === "\r" || key === "\n") { // enter
        cleanup();
        resolve(items[cursor].value);
      } else if (key === "\x1b" || key === "\x03") { // esc or ctrl+c
        cleanup();
        resolve(null);
      }
    }

    function cleanup() {
      process.stdin.removeListener("data", onKey);
      process.stdin.setRawMode(false);
      process.stdin.pause();
    }

    process.stdin.on("data", onKey);
  });
}

// ---------------------------------------------------------------------------
// Interactive text input (with prompt)
// ---------------------------------------------------------------------------
function textPrompt(label) {
  return new Promise((resolve) => {
    process.stdout.write(dim("  " + label + ": "));
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.setEncoding("utf8");

    let buf = "";

    function onKey(key) {
      if (key === "\r" || key === "\n") {
        cleanup();
        process.stdout.write("\n");
        resolve(buf);
      } else if (key === "\x7f" || key === "\b") { // backspace
        if (buf.length > 0) {
          buf = buf.slice(0, -1);
          process.stdout.write("\b \b");
        }
      } else if (key === "\x1b" || key === "\x03") { // esc/ctrl+c
        cleanup();
        process.stdout.write("\n");
        resolve(null);
      } else if (key >= " ") {
        buf += key;
        process.stdout.write(key);
      }
    }

    function cleanup() {
      process.stdin.removeListener("data", onKey);
      process.stdin.setRawMode(false);
      process.stdin.pause();
    }

    process.stdin.on("data", onKey);
  });
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------
function api(method, ep, body) {
  return new Promise((resolve, reject) => {
    const url = new URL(ep, BASE);
    const data = body ? JSON.stringify(body) : null;
    const opts = {
      hostname: url.hostname, port: url.port, path: url.pathname, method,
      headers: { "Content-Type": "application/json", "X-API-Key": API_KEY },
    };
    if (data) opts.headers["Content-Length"] = Buffer.byteLength(data);
    const req = http.request(opts, (res) => {
      let buf = "";
      res.on("data", (c) => (buf += c));
      res.on("end", () => {
        try { resolve(JSON.parse(buf)); } catch { resolve({ raw: buf }); }
      });
    });
    req.on("error", reject);
    if (data) req.write(data);
    req.end();
  });
}

// ---------------------------------------------------------------------------
// Status bar
// ---------------------------------------------------------------------------
function statusBar() {
  const p = serverInfo.activeProvider || "---";
  const m = serverInfo.activeModel || "---";
  const s = connected ? hi("ON") : dim("OFF");
  const bar = ` ${dim("status")} ${s}  ${dim("provider")} ${c(p)}  ${dim("model")} ${c(m)}  ${dim("theme")} ${c(theme)} `;
  const pad = IW - w(bar);
  console.log(box("├" + "─".repeat(IW) + "┤"));
  console.log(box("│") + bar + " ".repeat(Math.max(0, pad)) + box("│"));
  console.log(box("╰" + "─".repeat(IW) + "╯"));
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------
async function cmdConnect() {
  try {
    const s = await api("GET", "/api/status");
    connected = true;
    serverInfo = s;
    if (s.theme && themes[s.theme] && s.theme !== theme) theme = s.theme;
    printBox("CODEBLOX", [
      hi("Connected"),
      "",
      dim("Port") + "     " + c(PORT),
      dim("Uptime") + "   " + c(Math.floor(s.uptime) + "s"),
      dim("Plugin") + "   " + (s.pluginConnected ? hi("Active") : dim("Waiting...")),
      dim("Provider") + " " + hi(s.activeProvider),
      dim("Model") + "    " + c(s.activeModel),
      dim("Theme") + "    " + c(s.theme),
      dim("Queue") + "    " + c(String(s.queueLength)) + " pending",
    ]);
    return s;
  } catch (e) {
    connected = false;
    printBox("CODEBLOX", [
      dim("Disconnected"),
      "",
      dim("Error") + "    " + c(e.message),
      "",
      dim("Start the server: npm start"),
    ]);
    return null;
  }
}

async function cmdHelp() {
  const cmds = [
    ["/connect",  "Connect to server"],
    ["/provider", "Select / add / edit providers"],
    ["/model",    "View or switch model"],
    ["/theme",    "Switch theme (black|white)"],
    ["/chat",     "Show conversation history"],
    ["/logs",     "Show server logs"],
    ["/clear",    "Clear screen"],
    ["/quit",     "Exit"],
    ["[text]",    "Send script to Studio"],
  ];
  const w1 = 14;
  printBox("COMMANDS", cmds.map(([cmd, desc]) => pad(hi(cmd), w1) + dim(desc)));
}

async function cmdProvider(args) {
  const sub = args[0];

  // No args: interactive arrow-key provider select
  if (!sub) {
    try {
      const data = await api("POST", "/api/provider", { action: "list" });
      const items = data.providers.map(p => ({
        label: p.name + (p.hasKey ? "" : " (no key)"),
        value: p.name,
        active: p.active,
      }));

      const chosen = await selectPrompt("PROVIDERS", items);

      if (chosen) {
        const r = await api("POST", "/api/provider", { action: "select", name: chosen });
        if (r.success) {
          serverInfo.activeProvider = chosen;
          console.log(dim("  Selected: ") + hi(chosen));
        } else {
          console.log(dim("  Error: ") + c(r.error));
        }
      } else {
        console.log(dim("  Cancelled"));
      }
    } catch (e) {
      console.log(dim("  Error: ") + c(e.message));
    }
    return;
  }

  if (sub === "select") {
    // Also interactive if no name given
    if (args[1]) {
      try {
        const r = await api("POST", "/api/provider", { action: "select", name: args[1] });
        if (r.success) { serverInfo.activeProvider = args[1]; console.log(dim("  Selected: ") + hi(args[1])); }
        else console.log(dim("  Error: ") + c(r.error));
      } catch (e) { console.log(dim("  Error: ") + c(e.message)); }
      return;
    }
    // Redirect to interactive
    return cmdProvider([]);
  }

  if (sub === "add") {
    const name = args[1] || await textPrompt("Provider name");
    if (!name) { console.log(dim("  Cancelled")); return; }
    const key = args[2] || await textPrompt("API key (optional)") || "";
    try {
      const r = await api("POST", "/api/provider", { action: "add", name, apiKey: key });
      if (r.success) console.log(dim("  Added: ") + hi(name));
      else console.log(dim("  Error: ") + c(r.error));
    } catch (e) { console.log(dim("  Error: ") + c(e.message)); }
    return;
  }

  if (sub === "edit") {
    // If no name, show interactive list to pick which to edit
    if (!args[1]) {
      try {
        const data = await api("POST", "/api/provider", { action: "list" });
        const items = data.providers.map(p => ({
          label: p.name + (p.hasKey ? dim(" [has key]") : dim(" [no key]")),
          value: p.name,
          active: false,
        }));
        const chosen = await selectPrompt("EDIT PROVIDER", items);
        if (!chosen) { console.log(dim("  Cancelled")); return; }
        const key = await textPrompt("New API key");
        if (!key) { console.log(dim("  Cancelled")); return; }
        const r = await api("POST", "/api/provider", { action: "edit", name: chosen, apiKey: key });
        if (r.success) console.log(dim("  Updated: ") + hi(chosen));
        else console.log(dim("  Error: ") + c(r.error));
      } catch (e) { console.log(dim("  Error: ") + c(e.message)); }
      return;
    }
    const name = args[1];
    const key = args[2] || await textPrompt("New API key");
    if (!key) { console.log(dim("  Cancelled")); return; }
    try {
      const r = await api("POST", "/api/provider", { action: "edit", name, apiKey: key });
      if (r.success) console.log(dim("  Updated: ") + hi(name));
      else console.log(dim("  Error: ") + c(r.error));
    } catch (e) { console.log(dim("  Error: ") + c(e.message)); }
    return;
  }

  console.log(dim("  Unknown: ") + c(sub) + dim(" — use: select, add, edit"));
}

async function cmdModel(args) {
  // If no arg, fetch models list from server and show interactive select
  if (!args[0]) {
    try {
      const r = await api("POST", "/api/model", {});
      const models = (r.availableModels || [r.activeModel]).map(m => ({
        label: m,
        value: m,
        active: m === r.activeModel,
      }));

      if (models.length <= 1) {
        printBox("MODEL", [
          dim("Current: ") + hi(r.activeModel),
          "",
          dim("  /model [name] — switch model"),
        ]);
        return;
      }

      const chosen = await selectPrompt("MODEL", models);
      if (chosen) {
        const r2 = await api("POST", "/api/model", { model: chosen });
        serverInfo.activeModel = chosen;
        console.log(dim("  Model → ") + hi(r2.activeModel));
      } else {
        console.log(dim("  Cancelled"));
      }
    } catch (e) { console.log(dim("  Error: ") + c(e.message)); }
    return;
  }

  try {
    const r = await api("POST", "/api/model", { model: args[0] });
    serverInfo.activeModel = args[0];
    console.log(dim("  Model → ") + hi(r.activeModel));
  } catch (e) { console.log(dim("  Error: ") + c(e.message)); }
}

async function cmdTheme(args) {
  const t = args[0];
  if (!t) {
    const items = [
      { label: "black", value: "black", active: theme === "black" },
      { label: "white", value: "white", active: theme === "white" },
    ];
    const chosen = await selectPrompt("THEME", items);
    if (chosen) {
      try { await api("POST", "/api/theme", { theme: chosen }); } catch {}
      theme = chosen;
      console.log(dim("  Theme → ") + hi(chosen));
    } else {
      console.log(dim("  Cancelled"));
    }
    return;
  }
  if (t !== "black" && t !== "white") {
    console.log(dim("  Use: black or white"));
    return;
  }
  try { await api("POST", "/api/theme", { theme: t }); } catch {}
  theme = t;
  console.log(dim("  Theme → ") + hi(t));
}

async function cmdChat() {
  try {
    const r = await api("GET", "/api/chat");
    if (!r.history || !r.history.length) { console.log(dim("  No chat history.")); return; }
    const lines = r.history.slice(-20).map((e) => {
      const time = new Date(e.timestamp).toLocaleTimeString();
      const role = e.role === "user" ? hi("you") : e.role === "assistant" ? hi("ai") : dim("sys");
      return dim(time) + "  " + role + "  " + c(e.content.slice(0, IW - 20));
    });
    printBox("CHAT", lines);
  } catch (e) { console.log(dim("  Error: ") + c(e.message)); }
}

async function cmdLogs() {
  try {
    const r = await api("GET", "/api/logs");
    if (!r.logs || !r.logs.length) { console.log(dim("  No logs.")); return; }
    const lines = r.logs.slice(-20).map((e) => {
      const time = new Date(e.timestamp).toLocaleTimeString();
      const tag = e.type === "error" ? hi("ERR") : e.type === "success" ? hi(" OK") : dim("INF");
      return dim(time) + "  " + tag + "  " + c(e.message.slice(0, IW - 22));
    });
    printBox("LOGS", lines);
  } catch (e) { console.log(dim("  Error: ") + c(e.message)); }
}

function cmdClear() { process.stdout.write("\x1b[2J\x1b[H"); }

async function submitScript(code) {
  try {
    const r = await api("POST", "/api/submit", { code });
    if (r.queued) console.log(dim("  → ") + c(r.action.id));
    else console.log(dim("  Error: ") + c(r.error || "unknown"));
  } catch (e) {
    console.log(dim("  Connection error: ") + c(e.message));
  }
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------
async function handle(input) {
  const t = input.trim();
  if (!t) return;

  if (t.startsWith("/")) {
    const parts = t.slice(1).split(/\s+/);
    const cmd = parts[0].toLowerCase();
    const args = parts.slice(1);

    switch (cmd) {
      case "help": case "h": case "?": return cmdHelp();
      case "connect": case "c": return cmdConnect();
      case "chat": return cmdChat();
      case "logs": case "log": return cmdLogs();
      case "provider": case "p": return cmdProvider(args);
      case "model": case "m": return cmdModel(args);
      case "theme": return cmdTheme(args);
      case "clear": case "cls": return cmdClear();
      case "quit": case "exit": case "q":
        console.log(dim("\n  bye\n"));
        process.exit(0);
      default:
        console.log(dim("  unknown: ") + c("/" + cmd) + dim("  /help for commands"));
    }
    return;
  }

  await submitScript(t);
}

// ---------------------------------------------------------------------------
// REPL
// ---------------------------------------------------------------------------
let rl;

function startCLI() {
  rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: dim("  > "),
  });

  process.stdout.write("\x1b[2J\x1b[H");
  printBox(">_ CODEBLOX", [
    dim("Roblox Studio Bridge  v1.0.0"),
    "",
    dim("Type /help for commands"),
    dim("Type /connect to start"),
  ]);

  cmdConnect().then(() => {
    statusBar();
    rl.prompt();
  });

  rl.on("line", async (line) => {
    await handle(line);
    rl.prompt();
  });

  rl.on("close", () => {
    console.log(dim("\n  bye\n"));
    process.exit(0);
  });
}

startCLI();

} // end startREPL
