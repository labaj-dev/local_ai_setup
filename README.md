# Local AI Coding Setup (Podman + Ollama + SearXNG + Cline + Open Web UI)

Fully local, free, open-source AI coding assistant with private web search.
No Docker Desktop, no cloud API keys, no accounts required.

**Stack:**
- **Brew (Mac OS only)** - package manager used for mac os
- **Podman** — container runtime (no Docker Desktop license needed)
- **SearXNG** — self-hosted, private metasearch engine (no account, no tracking)
- **Ollama** — runs the local LLM
- **Cline** — VS Code extension, AI coding agent
- **Open Web UI** — web interface for interacting with Ollama

---

## 1. Install Prerequisites

### Mac OS installation
#### Brew and Python 3
Verify that you have brew installed by following the instructions on https://brew.sh. Once it's installed, update it and install Python.

```bash
brew update
brew install python
```

#### Podman
```bash
brew install podman podman-compose
podman machine init --cpus 4 --memory 4096 --disk-size 60
podman machine start
```

Verify the machine is running and that it has at least 4 CPUs and 4096 MB of RAM:
```bash
podman ps                 # Shows if the machine is running
podman machine inspect    # Shows the CPU and memory settings
```
Should return an empty table with no errors.

> If you get `machine "podman-machine-default" already exists`, just run
> `podman machine start` — it's already created, nothing more to do.

### Fedora 44+ installation

#### Install Python
```bash
sudo dnf install python3 python3-pip python3-devel
```

#### Install Podman
```bash
sudo dnf install podman podman-compose
```
---

## 2. Clone This Repo and Start SearXNG

Everything needed — `docker-compose.yml`, the SearXNG config with JSON output
already enabled, and a one-command startup script — is in this repo. No files
to hand-copy.

```bash
git clone git@github.com:labaj-dev/local_ai_setup.git
cd local_ai_setup
```

(Optional but recommended) generate a secret key and store it in macOS
Keychain instead of running with an empty one — see
[Security Setup](#security-setup-optional-but-recommended) below, then come
back here.

Start everything:
```bash
./start.sh
```
On macOS this starts the Podman machine if it isn't running. On every OS it
then brings up SearXNG via `podman-compose`.

Test:
```bash
curl "http://localhost:8080/search?q=test&format=json"
```
Should return JSON, not a 403 error.

**Security note:** the `127.0.0.1:8080:8080` binding in `docker-compose.yml`
restricts SearXNG to your machine only — verify with
`lsof -nP -iTCP:8080 -sTCP:LISTEN`, which should show `127.0.0.1:8080`, not
`*:8080`.

---

## 3. Install Ollama and Pull a Model

```bash
brew install ollama
ollama --version   # confirm 0.30+ for MLX acceleration on Apple Silicon
```

Pull a coding model with reliable tool-calling support:
```bash
ollama pull qwen3-coder:30b
```

> **Model note:** Gemma 4 has a known, ecosystem-wide bug where it emits
> malformed tool calls in agent/tool-use scenarios (across Ollama, llama.cpp,
> vLLM). Qwen3-Coder and Qwen2.5-Coder do not have this issue — stick to the
> Qwen-Coder family for anything involving tool calling / agent mode.

If 30B is too slow/heavy for your machine, `qwen2.5-coder:14b` is a solid,
lighter fallback with reliable tool calling.

---

## 4. Install Cline (VS Code Extension)

1. In VS Code: Extensions (`Cmd+Shift+X` or `Ctrl+Shift+X`) → search **Cline** → Install
2. Click the Cline icon in the sidebar
3. Skip any sign-up/account prompt — click the settings gear icon directly
   instead of the primary "Sign in" button
4. Select **Bring my own API key**
5. Set **API Provider** to `Ollama`
6. Check **Use custom base URL** and set the URL to `http://localhost:11434`
7. Select `qwen3-coder:30b` from the model dropdown
8. Test with: *"list the files in this project and explain what it does"*

> **Known bug:** Cline + Ollama + Qwen-Coder can occasionally loop on tool
> calls due to a JSON/XML format mismatch. Fix: create a `.clinerules` file
> in your project root containing:
> ```
> Always format tool calls using Cline's native XML tool-call syntax, never JSON.
> ```

---

## 5. (Optional) Give Cline Web Search via SearXNG

Cline supports MCP servers. In Cline's settings → MCP Servers, add:

```json
{
  "mcpServers": {
    "searxng": {
      "command": "npx",
      "args": ["-y", "searxng-mcp-ts@latest"],
      "env": {
        "SEARXNG_URL": "http://localhost:8080"
      }
    }
  }
}
```

SearXNG (from step 2) must be running for this to work.

---

## 6. (Optional) Open Web UI

Open Web UI is a browser chat interface for your Ollama models. `./start.sh`
starts it alongside SearXNG (the first start pulls a large image and can take
a few minutes).

1. Open `http://localhost:8081` and create the local admin account.
2. Pick a model from the dropdown. It talks to the Ollama instance already
   running on your machine (`http://localhost:11434`).

Your chats and uploads live in `./open-webui/`, which is git-ignored.

On Linux, `./start.sh` also applies `docker-compose.linux.yml`, which lets the
container reach Ollama on the host's loopback without exposing Ollama to your
network. On macOS the Podman VM handles this on its own.

---

## Daily Use

After a reboot, from this repo's folder:
```bash
./start.sh
```
Then just open VS Code and use Cline normally — Ollama runs as a background
service once installed and doesn't need manual starting.

To shut down the services at any time:
```bash
./stop.sh
```

---
## Security Setup (Optional but Recommended)

For enhanced security, you can use the included scripts to manage your SearXNG secret key in macOS Keychain:

1. Run the setup script to generate and store a secure key:
   ```bash
   ./searxng-keychain-setup.sh
   ```

2. To manage your key later, use:
   ```bash
   # Show current key
   ./searxng-keychain-usage.sh show
   
   # Generate new key
   ./searxng-keychain-usage.sh reset
   
   # Remove key from Keychain (optional)
   ./searxng-keychain-usage.sh remove
   ```

3. The scripts will automatically load the key into your environment when you run them.

---

## Troubleshooting Quick Reference

| Symptom | Likely cause |
|---|---|
| SearXNG returns 403 on `format=json` | `searxng/settings.yml` got overwritten/reset — confirm it still lists `json` under `search.formats` |
| Cline/Ollama returns blank responses in Agent mode | Model has a tool-calling bug — switch to Qwen-Coder family |
| Tool calls loop forever | JSON/XML mismatch — add the `.clinerules` fix in step 4 |
| Everything feels slow | Check `ollama --version` is 0.30+; free up RAM (close Podman if unused); try a smaller model |
| `pip install` fails with "externally-managed-environment" | Not relevant to this stack — we use Homebrew/Ollama directly, no Python venvs needed |
