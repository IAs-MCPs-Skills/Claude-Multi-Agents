# Claude Multi-Agents — Multi-Profile Manager

Manage multiple Claude Code accounts on a single Windows machine, without re-authenticating on every switch.

---

## Why this exists

Claude Code has no native multi-account support. Every account needs its own config directory. This project automates the entire setup with a single installer — no manual file editing, no hardcoded paths.

**What you get after running `install.ps1`:**

- Per-profile isolation: each account has its own credentials, `settings.json` (MCPs), and `CLAUDE.md` (context)
- Skills, agents, and commands are **shared across all profiles** via junction points — update once, everywhere updates
- Terminal aliases: `claude-work`, `claude-personal` open Claude with the right account instantly
- Slash commands: `/profile-work` switches from inside Claude Code
- VS Code panel integration: one `Ctrl+Shift+P → Developer: Reload Window` is enough

---

## Requirements

- Windows 10 / 11
- [Claude Code](https://claude.ai/download) installed and authenticated (`claude --version` should work)
- PowerShell 5.1+ (built into Windows — no install needed)

---

## Install

**Option A — one command (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/Gustavo-b017/claude-multi-agents/main/install.ps1 | iex
```

**Option B — clone and run locally:**

```powershell
git clone https://github.com/Gustavo-b017/claude-multi-agents
cd claude-multi-agents
.\install.ps1
```

The installer will ask interactively:
1. How many additional profiles? (your existing `~/.claude` stays as profile 1)
2. A name for each profile (e.g. `work`, `freelance`, `client`)
3. VS Code integration? (auto-updates `settings.json` on every switch)
4. Git Bash integration? (adds aliases to `~/.bashrc`)

No admin rights required. No system-wide changes.

---

## Usage

```powershell
# PowerShell or Git Bash terminal
claude-work          # switch to "work" profile and open Claude
claude-personal      # switch to "personal" profile
claude-perfil        # show which profile is currently active
```

```
# Inside Claude Code (slash commands, any session)
/profile-work
/profile-personal
```

**VS Code panel:** after any profile switch, press `Ctrl+Shift+P` → `Developer: Reload Window`.

---

## Customizing a profile

**MCPs (tools):** edit `~/.claude-<name>/settings.json`

```json
{
    "mcpServers": {
        "my-tool": {
            "type": "stdio",
            "command": "node",
            "args": ["C:\\path\\to\\server.js"]
        }
    }
}
```

**Context:** edit `~/.claude-<name>/CLAUDE.md` — describe the account's role, active projects, conventions.

**Skills and agents:** add to `~/.claude/skills/` or `~/.claude/agents/` — junction points keep them shared automatically.

---

## First login on each new profile

After installing, authenticate each new profile once:

```powershell
claude-work
# Inside Claude:
/login
# Browser opens — log in with the work account
```

Repeat for every profile. Your primary `~/.claude` is already authenticated.

---

## Directory structure

```
~/.claude/              ← primary profile (already exists)
  .credentials.json     ← auth token
  settings.json         ← MCPs
  CLAUDE.md             ← global context
  skills/               ← shared across all profiles
  agents/               ← shared across all profiles
  commands/             ← shared (includes /profile-* slash commands)
  bin/
    switch-profile.ps1  ← installed by this project
  profiles.json         ← profile name → directory map

~/.claude-work/         ← additional profile
  .credentials.json     ← separate auth token
  settings.json         ← separate MCP config
  CLAUDE.md             ← separate context
  skills/  → junction → ~/.claude/skills/
  agents/  → junction → ~/.claude/agents/
  commands/ → junction → ~/.claude/commands/

~/.claude-freelance/    ← another profile (same structure)
```

---

## How it works

→ [docs/how-it-works.md](docs/how-it-works.md)

## Troubleshooting

→ [docs/troubleshooting.md](docs/troubleshooting.md)

---

## License

MIT — use freely, modify freely, no attribution required.
