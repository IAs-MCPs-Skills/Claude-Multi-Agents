# Claude Multi-Agents — Multi-Profile Manager

Manage multiple Claude Code accounts on a single Windows machine, without re-authenticating on every switch.

---

## Why this exists

Claude Code has no native multi-account support. Every account needs its own config directory. This project automates the entire setup with a single installer — no manual file editing, no hardcoded paths.

**What you get after running `claude-profiles.ps1 install`:**

- Per-profile isolation: each account has its own credentials and MCP servers
- Skills, agents, commands, and `CLAUDE.md` (context) are **shared across all profiles** — update once, everywhere updates
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

The single entry point is **`claude-profiles.ps1`**. There is no separate `install.ps1`.

```powershell
git clone https://github.com/Gustavo-b017/claude-multi-agents
cd claude-multi-agents
.\claude-profiles.ps1 install
```

If PowerShell blocks the script, run once:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

The installer asks interactively:
1. A name for your primary profile (your existing `~/.claude`, default `primary`)
2. How many additional profiles (1–5)
3. A name for each (e.g. `work`, `freelance`, `client`)

It then creates the directories, junctions, terminal aliases, and `/profile-*` slash commands. No admin rights required. No system-wide changes.

---

## Commands

All commands run against `claude-profiles.ps1`. Run with no argument for the **interactive menu**; run with a subcommand for direct CLI use.

```powershell
.\claude-profiles.ps1                       # interactive menu (list / add / switch / rename / remove / groups / scan)
.\claude-profiles.ps1 install               # first-time setup
.\claude-profiles.ps1 scan                  # discover ~/.claude* dirs, register new ones, (re)generate all commands
.\claude-profiles.ps1 add    -Profile work  # create a new profile
.\claude-profiles.ps1 remove -Profile work  # delete a profile (asks for confirmation)
.\claude-profiles.ps1 switch -Profile work  # switch active profile (used by the /profile-* slash commands)
```

### `scan` — moving to a new machine

`scan` is the command for when the profile directories already exist on disk (e.g. you copied `~/.claude*` to another machine, or restored a backup) but the aliases and slash commands are missing. It:

1. Finds every `~/.claude` and `~/.claude-<name>` directory
2. Registers any that are missing from `profiles.json`
3. Regenerates **all** access commands for every profile: `/profile-<name>` slash commands, `claude-<name>` PowerShell/Bash aliases, and `~/bin` launchers

After a `scan`, open a new terminal and the `claude-<name>` aliases work again.

> **On a fresh machine:** run `.\claude-profiles.ps1 install` first (it writes `profiles.json` and the shared dirs). If you brought your `~/.claude*` folders with you, run `.\claude-profiles.ps1 scan` to re-detect them and rebuild the commands.

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

**MCPs (tools):** use `claude mcp add --scope user` com o perfil ativo

```powershell
# Ative o perfil primeiro
claude-<name>

# Adicione um servidor stdio (processo local)
claude mcp add my-tool --scope user -- node "C:\path\to\server.js"

# Adicione um servidor HTTP (remoto)
claude mcp add my-api --scope user --transport http https://api.example.com/mcp

# Com autenticacao Bearer
claude mcp add my-api --scope user --transport http https://api.example.com/mcp --header "Authorization: Bearer TOKEN"

# Verifique
claude mcp list
```

> **Por que nao editar `settings.json` diretamente?**
> Claude Code armazena MCPs no `.claude.json` (gerenciado pelo `claude mcp add`).
> A chave `mcpServers` em `settings.json` e ignorada silenciosamente.

**Context:** edit `~/.claude/CLAUDE.md` (or the same file via any `~/.claude-<name>/CLAUDE.md` hardlink — it's the same file, shared by every profile).

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
  .claude.json          ← MCPs (gerenciado por `claude mcp add`)
  settings.json         ← permissoes, effort level, etc.
  CLAUDE.md             ← shared context (source of the hardlink)
  skills/               ← shared across all profiles
  agents/               ← shared across all profiles
  commands/             ← shared (includes /profile-* slash commands)
  bin/
    claude-profiles.ps1 ← installed copy (called by /profile-* slash commands)
  profiles.json         ← profile name → directory map
  groups.json           ← optional: profiles that share history/memory
  profile-env.json      ← optional: per-profile env var overrides

~/.claude-work/         ← additional profile
  .credentials.json     ← separate auth token
  .claude.json          ← MCPs deste perfil (gerenciado por `claude mcp add`)
  settings.json         ← permissoes, effort level, etc.
  CLAUDE.md             → hardlink → ~/.claude/CLAUDE.md (same file)
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
