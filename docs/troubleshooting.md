# Troubleshooting

## Claude is still showing the old account after switching

**Cause:** The extension process hasn't reloaded.

**Fix:** In VS Code, press `Ctrl+Shift+P` → type `Developer: Reload Window` → Enter.

This restarts the extension host and forces Claude Code to re-read `claudeCode.environmentVariables` from `settings.json`.

---

## `/profile-work` slash command not found

**Cause:** The commands directory is empty or the slash commands weren't installed.

**Fix:**
```powershell
# Verify the commands directory
ls $env:USERPROFILE\.claude\commands\

# If profile-*.md files are missing, re-run the installer
.\install.ps1
```

---

## Terminal shows a different profile than the VS Code panel

**Cause:** They read `CLAUDE_CONFIG_DIR` from different sources.

| Surface | Source |
|---|---|
| New integrated terminal | `terminal.integrated.env.windows` in VS Code `settings.json` |
| VS Code panel | `claudeCode.environmentVariables` in VS Code `settings.json` |
| External terminal (PowerShell, Git Bash) | The PowerShell function or shell alias |

Run `switch-profile.ps1` (or the terminal function) to update all three at once, then do `Reload Window` for the panel.

---

## "Execution of scripts is disabled on this system"

**Fix:**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

This only affects the current user, not the whole machine. No admin rights needed.

---

## Junction points failed: "Access denied" or "Cannot create a file when that file already exists"

**Cause 1 — Directory already exists at the junction path:**
```powershell
# Check what's there
ls $env:USERPROFILE\.claude-work\skills

# If it's a real directory (not a junction), remove it first
Remove-Item -Recurse "$env:USERPROFILE\.claude-work\skills"

# Then re-create the junction
cmd /c "mklink /J `"$env:USERPROFILE\.claude-work\skills`" `"$env:USERPROFILE\.claude\skills`""
```

**Cause 2 — Running from a OneDrive-synced directory:**
Some OneDrive configurations block junction point creation. Clone the repo outside of OneDrive and run from there.

---

## PowerShell function not found after install

**Cause:** The current terminal session doesn't know about the new functions yet.

**Fix:** Reload the profile in the current session:
```powershell
. $PROFILE
```

Or close and reopen PowerShell.

---

## The PowerShell profile is on OneDrive

This is normal on many Windows machines. The installer uses `$PROFILE` directly, which automatically resolves to the correct path (OneDrive or not). No action needed.

If you see encoding issues in the profile file, check that it's UTF-8:
```powershell
Get-Content $PROFILE -Encoding UTF8 | Select-String 'Claude'
```

---

## settings.json is corrupt / can't be parsed after a switch

**Cause:** The switch script strips JSONC comments before parsing, but may fail on complex or malformed comment patterns.

**Fix:** Validate and repair the file:
```powershell
# Open in VS Code (it shows JSON errors)
code "$env:APPDATA\Code\User\settings.json"

# Or check with PowerShell
Get-Content "$env:APPDATA\Code\User\settings.json" -Raw | ConvertFrom-Json
```

If the file is corrupt, VS Code keeps a backup at `settings.json.bak` in the same folder on some versions.

---

## profiles.json not found

**Cause:** The installer was not run, or the file was deleted.

**Fix:** Re-run the installer. It will recreate `~/.claude/profiles.json` based on your answers.

```powershell
.\install.ps1
```

---

## Authentication expired or Claude asks for /login

OAuth tokens from Claude Code are long-lived but can expire after a password change, a security event, or manual revocation.

**Fix:**
```powershell
claude-work       # or whichever profile needs re-auth
# Inside Claude:
/login
```

The new `.credentials.json` will be written to the profile's directory. Other profiles are not affected.

---

## Still stuck?

Open an issue at: [github.com/Gustavo-b017/claude-multi-agents/issues](https://github.com/Gustavo-b017/claude-multi-agents/issues)

Include:
- Output of `claude --version`
- Output of `Get-Content $env:USERPROFILE\.claude\profiles.json`
- The exact error message
