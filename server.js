/**
 * CodeBlox API Server
 *
 * A robust REST API engine that bridges the CLI and Roblox Studio Plugin.
 * Manages state for providers, models, themes, chat history, and script queues.
 *
 * All endpoints validate the X-API-Key header against the configured secret.
 */

require("dotenv").config();

const express = require("express");
const cors = require("cors");

const app = express();
const PORT = process.env.PORT || 3000;
const API_KEY = process.env.CODEBLOX_API_KEY || "codeblox-default-key";

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------
app.use(cors());
app.use(express.json({ limit: "10mb" }));

/**
 * Authentication middleware.
 * Every request must include an X-API-Key header matching the server secret.
 */
function authenticate(req, res, next) {
  const key = req.headers["x-api-key"];
  if (!key || key !== API_KEY) {
    return res.status(401).json({
      error: "Unauthorized",
      message: "Missing or invalid X-API-Key header.",
    });
  }
  next();
}

app.use(authenticate);

// ---------------------------------------------------------------------------
// In-Memory State
// ---------------------------------------------------------------------------

/** Provider registry: { [name]: { apiKey: string, active: boolean } } */
const providers = {
  "google-ai": { apiKey: "", active: true },
  "xiaomi-mimo": { apiKey: "", active: false },
  openclaude: { apiKey: "", active: false },
};

/** Application state object – single source of truth */
const state = {
  theme: process.env.DEFAULT_THEME || "black",
  activeProvider: process.env.DEFAULT_PROVIDER || "google-ai",
  activeModel: process.env.DEFAULT_MODEL || "gemini-pro",
  chatHistory: [],
  scriptQueue: [],
  systemLogs: [],
  pluginConnected: false,
  lastPluginPoll: null,
  startedAt: new Date().toISOString(),
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Returns the currently active provider name */
function getActiveProvider() {
  return state.activeProvider;
}

/** Pushes a message into the chat history log */
function logChat(role, content) {
  state.chatHistory.push({
    role,
    content,
    timestamp: new Date().toISOString(),
  });
}

/** Pushes a system log entry (capped at 500) */
function logSystem(type, message) {
  state.systemLogs.push({
    type,
    message,
    timestamp: new Date().toISOString(),
  });
  if (state.systemLogs.length > 500) {
    state.systemLogs.splice(0, state.systemLogs.length - 500);
  }
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

/**
 * GET /api/status
 * Returns server metadata, connection state, active theme/provider/model.
 */
app.get("/api/status", (req, res) => {
  const providerNames = Object.keys(providers);
  const active = getActiveProvider();

  res.json({
    server: "CodeBlox API",
    version: "1.0.0",
    uptime: process.uptime(),
    startedAt: state.startedAt,
    pluginConnected: state.pluginConnected,
    lastPluginPoll: state.lastPluginPoll,
    theme: state.theme,
    activeProvider: active,
    activeModel: state.activeModel,
    providers: providerNames.map((name) => ({
      name,
      active: name === active,
      hasKey: !!providers[name].apiKey,
    })),
    queueLength: state.scriptQueue.length,
    chatEntries: state.chatHistory.length,
  });
});

/**
 * GET /api/actions
 * Polled by the Roblox Studio Plugin to retrieve queued code blocks.
 * Returns the full queue and clears it atomically.
 */
app.get("/api/actions", (req, res) => {
  if (!state.pluginConnected) {
    logSystem("info", "Plugin connected");
  }
  state.pluginConnected = true;
  state.lastPluginPoll = new Date().toISOString();

  const actions = state.scriptQueue.splice(0);

  res.json({
    actions,
    theme: state.theme,
    activeModel: state.activeModel,
    timestamp: new Date().toISOString(),
  });
});

/**
 * POST /api/response
 * Receives execution results, console output, or errors from Roblox Studio.
 * Body: { actionId: string, success: boolean, output?: string, error?: string }
 */
app.post("/api/response", (req, res) => {
  const { actionId, success, output, error } = req.body;

  if (!actionId) {
    return res.status(400).json({ error: "Missing actionId in request body." });
  }

  const entry = {
    actionId,
    success: !!success,
    output: output || "",
    error: error || "",
    timestamp: new Date().toISOString(),
  };

  // Log the result into chat history for the /chat command
  logChat("system", `[Studio] ${success ? "OK" : "ERROR"} – ${output || error || "no output"}`);
  logSystem(success ? "success" : "error", `Execution ${success ? "succeeded" : "failed"}: ${output || error || "no output"}`);

  res.json({ received: true, entry });
});

/**
 * POST /api/submit
 * Submits a script payload from the CLI into the queue for Roblox Studio.
 * Body: { code: string }
 */
app.post("/api/submit", (req, res) => {
  const { code } = req.body;

  if (!code || typeof code !== "string") {
    return res.status(400).json({ error: "Missing or invalid 'code' field." });
  }

  const action = {
    id: `act_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    code,
    submittedAt: new Date().toISOString(),
  };

  state.scriptQueue.push(action);
  logChat("user", code);
  logSystem("info", `Script queued: ${action.id}`);

  res.json({ queued: true, action });
});

/**
 * POST /api/chat
 * Stores a chat message (e.g. AI prompt/response) in the history.
 * Body: { role: "user"|"assistant"|"system", content: string }
 */
app.post("/api/chat", (req, res) => {
  const { role, content } = req.body;

  if (!content || typeof content !== "string") {
    return res.status(400).json({ error: "Missing or invalid 'content' field." });
  }

  logChat(role || "user", content);

  res.json({ logged: true });
});

/**
 * GET /api/chat
 * Returns the full chat history.
 */
app.get("/api/chat", (req, res) => {
  res.json({ history: state.chatHistory });
});

/**
 * GET /api/logs
 * Returns system log entries. Accepts optional `since` query param (ISO timestamp)
 * to retrieve only logs after a given point.
 */
app.get("/api/logs", (req, res) => {
  const { since } = req.query;
  if (since) {
    const filtered = state.systemLogs.filter((l) => l.timestamp > since);
    return res.json({ logs: filtered });
  }
  res.json({ logs: state.systemLogs });
});

/**
 * POST /api/provider
 * Updates provider configurations dynamically.
 * Body: { action: "add"|"edit"|"select"|"list", name?: string, apiKey?: string }
 */
app.post("/api/provider", (req, res) => {
  const { action, name, apiKey } = req.body;

  switch (action) {
    case "list": {
      const active = getActiveProvider();
      return res.json({
        providers: Object.entries(providers).map(([n, cfg]) => ({
          name: n,
          active: n === active,
          hasKey: !!cfg.apiKey,
        })),
      });
    }

    case "add": {
      if (!name) return res.status(400).json({ error: "Provider name is required." });
      if (providers[name]) return res.status(409).json({ error: `Provider '${name}' already exists. Use 'edit' to update.` });
      providers[name] = { apiKey: apiKey || "", active: false };
      logChat("system", `Provider '${name}' added.`);
      logSystem("info", `Provider added: ${name}`);
      return res.json({ success: true, message: `Provider '${name}' registered.` });
    }

    case "edit": {
      if (!name) return res.status(400).json({ error: "Provider name is required." });
      if (!providers[name]) return res.status(404).json({ error: `Provider '${name}' not found. Use 'add' to create.` });
      if (apiKey !== undefined) providers[name].apiKey = apiKey;
      logChat("system", `Provider '${name}' updated.`);
      logSystem("info", `Provider updated: ${name}`);
      return res.json({ success: true, message: `Provider '${name}' updated.` });
    }

    case "select": {
      if (!name) return res.status(400).json({ error: "Provider name is required." });
      if (!providers[name]) return res.status(404).json({ error: `Provider '${name}' not found.` });

      // Deactivate all, activate the selected one
      for (const key of Object.keys(providers)) {
        providers[key].active = key === name;
      }
      state.activeProvider = name;
      logChat("system", `Active provider switched to '${name}'.`);
      logSystem("info", `Provider switched to: ${name}`);
      return res.json({ success: true, message: `Active provider is now '${name}'.` });
    }

    default:
      return res.status(400).json({
        error: "Invalid action. Use 'add', 'edit', 'select', or 'list'.",
      });
  }
});

/**
 * POST /api/model
 * Switches or views the active AI model.
 * Body: { model?: string }
 */
app.post("/api/model", (req, res) => {
  const { model } = req.body;

  if (model) {
    state.activeModel = model;
    logChat("system", `Active model switched to '${model}'.`);
    logSystem("info", `Model changed to: ${model}`);
    return res.json({ success: true, activeModel: state.activeModel });
  }

  res.json({ activeModel: state.activeModel });
});

/**
 * POST /api/theme
 * Toggles the UI theme between black and white.
 * Body: { theme: "black" | "white" }
 */
app.post("/api/theme", (req, res) => {
  const { theme } = req.body;

  if (theme && (theme === "black" || theme === "white")) {
    state.theme = theme;
    logChat("system", `Theme switched to '${theme}'.`);
    logSystem("info", `Theme changed to: ${theme}`);
    return res.json({ success: true, theme: state.theme });
  }

  res.status(400).json({ error: "Invalid theme. Use 'black' or 'white'." });
});

/**
 * POST /api/clear
 * Clears the script queue and/or chat history.
 * Body: { target: "queue" | "chat" | "all" }
 */
app.post("/api/clear", (req, res) => {
  const { target } = req.body;

  switch (target) {
    case "queue":
      state.scriptQueue.length = 0;
      return res.json({ cleared: "queue" });
    case "chat":
      state.chatHistory.length = 0;
      return res.json({ cleared: "chat" });
    case "all":
      state.scriptQueue.length = 0;
      state.chatHistory.length = 0;
      return res.json({ cleared: "all" });
    default:
      return res.status(400).json({ error: "Invalid target. Use 'queue', 'chat', or 'all'." });
  }
});

// ---------------------------------------------------------------------------
// 404 Catch-All
// ---------------------------------------------------------------------------
app.use((req, res) => {
  res.status(404).json({ error: "Not Found", path: req.path });
});

// ---------------------------------------------------------------------------
// Error Handler
// ---------------------------------------------------------------------------
app.use((err, req, res, _next) => {
  console.error("[CodeBlox Server Error]", err.stack || err.message);
  res.status(500).json({ error: "Internal Server Error", message: err.message });
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
logSystem("info", `Server starting on port ${PORT}`);

app.listen(PORT, () => {
  logSystem("info", `Server listening on port ${PORT}`);
  console.log(`
  ╔══════════════════════════════════════════╗
  ║           CODEBLOX API SERVER            ║
  ╠══════════════════════════════════════════╣
  ║  Port    : ${String(PORT).padEnd(28)}║
  ║  Theme   : ${state.theme.padEnd(28)}║
  ║  Provider: ${state.activeProvider.padEnd(28)}║
  ║  Model   : ${state.activeModel.padEnd(28)}║
  ╚══════════════════════════════════════════╝
  `);
});
