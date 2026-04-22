# How it works

## The core mechanism: CLAUDE_CONFIG_DIR

Claude Code reads the environment variable `CLAUDE_CONFIG_DIR` to determine where to look for its configuration. If the variable is not set, it defaults to `~/.claude`.

```
CLAUDE_CONFIG_DIR not set     →  uses ~/.claude
CLAUDE_CONFIG_DIR=~/.claude-work  →  uses ~/.claude-work
```

Each directory is a fully independent profile:

| File | Purpose |
|---|---|
| `.credentials.json` | OAuth token — who is logged in |
| `.claude.json` | MCP servers active for this account (managed by `claude mcp add`) |
| `settings.json` | Permissions, effort level, and other Claude Code settings |
| `CLAUDE.md` | Global context instructions |
| `skills/` | Available skills |
| `agents/` | Custom agents |
| `commands/` | Slash commands |
| `projects/` | Conversation history per project |
| `memory/` | Persistent memory |

> **Importante:** MCPs vivem em `.claude.json`, nao em `settings.json`.
> Claude Code ignora silenciosamente a chave `mcpServers` no `settings.json`.
> Sempre use `claude mcp add --scope user` para adicionar MCPs a um perfil.

By pointing `CLAUDE_CONFIG_DIR` to a different directory, Claude Code boots with a completely different identity — different account, different MCPs, different context.

---

## Junction points: shared skills, agents, commands

Creating a separate directory per profile would mean duplicating skills, agents, and custom commands across every profile. To avoid this, this project creates Windows **junction points** (a type of directory symlink that requires no admin rights):

```
~/.claude-work/skills/    →  junction  →  ~/.claude/skills/
~/.claude-work/agents/    →  junction  →  ~/.claude/agents/
~/.claude-work/commands/  →  junction  →  ~/.claude/commands/
```

This means:
- Install a new skill in `~/.claude/skills/` once, and every profile sees it instantly
- Slash commands (including `/profile-*`) work from any active profile
- You never need to copy or sync anything

Junction points behave like real directories from the OS's perspective. Claude Code reads them without knowing they redirect.

---

## What switch-profile.ps1 does

When you run `claude-work` or `/profile-work`, the script:

1. **Reads `~/.claude/profiles.json`** to find the target directory
2. **Updates `$env:CLAUDE_CONFIG_DIR`** in the current process only
3. **Updates VS Code `settings.json`** in two places:
   - `terminal.integrated.env.windows.CLAUDE_CONFIG_DIR` — new integrated terminals pick up the value
   - `claudeCode.environmentVariables` — injected into the extension process; a `Reload Window` is enough to switch without restarting VS Code
4. **Launches `claude` automatically** (unless called with `-NoLaunch`, which slash commands use)

> **Why not `setx`?**
> `setx` writes `CLAUDE_CONFIG_DIR` to the Windows registry as a persistent user variable. This contaminates every terminal and VS Code window opened afterwards — even after you stop using that profile. Isolation is handled per-process (shell functions) and per-extension-reload (VS Code settings), never globally.

---

## VS Code panel: why Reload Window is sufficient

The Claude Code VS Code extension reads `claudeCode.environmentVariables` from `settings.json` when the extension host starts. `Developer: Reload Window` restarts the extension host — no need to close and reopen VS Code.

Sequence:
```
1. /profile-work  (or claude-work in terminal)
   → switch-profile.ps1 runs
   → settings.json updated with new CLAUDE_CONFIG_DIR

2. Ctrl+Shift+P → Developer: Reload Window
   → extension host restarts
   → Claude Code reads claudeCode.environmentVariables
   → panel now uses the work account
```

---

## profiles.json

The installer writes `~/.claude/profiles.json` mapping profile names to directories:

```json
{
  "primary": "C:\\Users\\YOU\\.claude",
  "work": "C:\\Users\\YOU\\.claude-work",
  "freelance": "C:\\Users\\YOU\\.claude-freelance"
}
```

`switch-profile.ps1` reads this file at runtime — no hardcoded paths.

---

## Security note

Each profile's `.credentials.json` contains an OAuth token for that Claude account. These files are never committed to git (see `.gitignore`). If you sync `~/.claude-*` directories with cloud storage, ensure `.credentials.json` is excluded.

---

## Adding a profile later

You don't need to re-run the full installer. You can add a profile manually:

```powershell
# 1. Create the directory
mkdir $env:USERPROFILE\.claude-newprofile

# 2. Copy templates
copy templates\settings.json $env:USERPROFILE\.claude-newprofile\
copy templates\CLAUDE.md $env:USERPROFILE\.claude-newprofile\

# 3. Create junction points
cmd /c "mklink /J `"$env:USERPROFILE\.claude-newprofile\skills`"   `"$env:USERPROFILE\.claude\skills`""
cmd /c "mklink /J `"$env:USERPROFILE\.claude-newprofile\agents`"   `"$env:USERPROFILE\.claude\agents`""
cmd /c "mklink /J `"$env:USERPROFILE\.claude-newprofile\commands`" `"$env:USERPROFILE\.claude\commands`""

# 4. Add to profiles.json
# Edit ~/.claude/profiles.json and add: "newprofile": "C:\\Users\\YOU\\.claude-newprofile"

# 5. Add PowerShell function to $PROFILE
# function claude-newprofile { $env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-newprofile"; claude @args }

# 6. Authenticate
claude-newprofile
# Inside Claude: /login

# 7. Add MCPs (with the profile active via CLAUDE_CONFIG_DIR)
$env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-newprofile"
claude mcp add my-tool --scope user -- node "C:\path\to\server.js"
claude mcp add my-api  --scope user --transport http https://api.example.com/mcp
claude mcp list   # verify
```

> MCPs sao gravados em `.claude.json` via `claude mcp add --scope user`.
> **Nao** edite `settings.json` para MCPs — Claude Code ignora essa chave la.
