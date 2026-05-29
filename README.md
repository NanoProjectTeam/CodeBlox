# CodeBlox

A bridge between Node.js CLI and Roblox Studio. Send scripts from your terminal directly into Roblox Studio via a local API server.

## Install

Requires Node.js 18+.

```
npm install -g git+https://github.com/NanoProjectTeam/CodeBlox.git
```

## Quick Start

**1. Start the server:**

```
codeblox server
```

**2. In a separate terminal, start the CLI:**

```
codeblox
```

**3. In Roblox Studio:**

- Install the `CodeBloxPlugin.lua` file into your Plugins folder
- Enable HTTP Requests in Studio Settings > Security
- The plugin will auto-connect when the server is running

**Or run both together:**

```
codeblox dev
```

## Configuration

Copy the example environment file and edit it:

```
cp .env.example .env
```

| Variable | Default | Description |
|---|---|---|
| `PORT` | `3000` | API server port |
| `CODEBLOX_API_KEY` | `codeblox-default-key` | Auth token for CLI/server/plugin |
| `DEFAULT_PROVIDER` | `google-ai` | Default AI provider |
| `DEFAULT_MODEL` | `gemini-pro` | Default AI model |
| `DEFAULT_THEME` | `black` | UI theme (`black` or `white`) |

## CLI Commands

| Command | Description |
|---|---|
| `/help` | Display all commands and connection info |
| `/connect` | Handshake with the server and show status |
| `/chat` | Show session history of prompts and scripts |
| `/logs` | Show server system logs |
| `/provider list` | List all registered AI providers |
| `/provider select [name]` | Switch active provider |
| `/provider add [name] [key]` | Register a new provider |
| `/provider edit [name] [key]` | Update a provider's API key |
| `/model [name]` | View or switch the active model |
| `/theme [black\|white]` | Toggle UI theme across CLI and plugin |
| `/clear` | Clear the terminal |
| `/quit` | Exit the CLI |

Any text typed without a `/` prefix is sent as a script payload to Roblox Studio for execution.

## API Endpoints

All endpoints require the `X-API-Key` header.

| Method | Endpoint | Description |
|---|---|---|
| GET | `/api/status` | Server state, theme, provider, model, uptime |
| GET | `/api/actions` | Fetch and dequeue pending scripts (plugin polls this) |
| POST | `/api/response` | Plugin reports execution results back |
| POST | `/api/submit` | Submit a script payload for execution |
| GET | `/api/chat` | Get full chat history |
| POST | `/api/chat` | Add entry to chat history |
| GET | `/api/logs` | Get system logs (optional `?since=` filter) |
| POST | `/api/provider` | Add, edit, or select providers |
| POST | `/api/model` | Change active model |
| POST | `/api/theme` | Change active theme |
| POST | `/api/clear` | Clear chat history, logs, and queue |

## Architecture

```
Terminal (CLI)  -->  Node.js API Server  -->  Roblox Studio (Plugin)
  cli.js              server.js               CodeBloxPlugin.lua
```

- **CLI** sends commands and script payloads to the server
- **Server** manages state, queues, providers, and routing
- **Plugin** polls the server every 0.5s, executes scripts, and reports results

## Roblox Plugin Features

- Premium monochromatic UI (black/white themes)
- Dynamic theme sync from server
- Status board showing active provider, model, and queue depth
- Live scrolling log feed with typed entries
- Metadata overlay with current provider/model
- Smooth TweenService button animations
- Safe `pcall` + `loadstring` execution with error capture

## Development

```
git clone https://github.com/NanoProjectTeam/CodeBlox.git
cd CodeBlox
npm install
npm run dev
```

## License

MIT
