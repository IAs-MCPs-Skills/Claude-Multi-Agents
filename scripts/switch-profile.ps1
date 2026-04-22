#Requires -Version 5.1
<#
.SYNOPSIS
    Switches the active Claude Code profile.
.DESCRIPTION
    Reads ~/.claude/profiles.json to find the target directory,
    then updates CLAUDE_CONFIG_DIR in the current process, Windows user env,
    and optionally VS Code settings.json.
.PARAMETER Profile
    Name of the profile to switch to (must exist in profiles.json).
.PARAMETER NoVSCode
    Skip updating VS Code settings.json.
.PARAMETER NoLaunch
    Skip auto-launching Claude after switching (used when called from inside Claude, e.g. via slash command).
.EXAMPLE
    switch-profile.ps1 -Profile work
.EXAMPLE
    switch-profile.ps1 -Profile work -NoLaunch
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Profile,

    [switch]$NoVSCode,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

# --- Load profile map --------------------------------------------------------

$profilesConfig = "$env:USERPROFILE\.claude\profiles.json"

if (-not (Test-Path $profilesConfig)) {
    Write-Host ""
    Write-Host "  [erro] profiles.json nao encontrado em ~/.claude/" -ForegroundColor Red
    Write-Host "  Execute o instalador novamente: .\install.ps1" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

try {
    $profileMap = Get-Content $profilesConfig -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Host "  [erro] Falha ao ler profiles.json: $_" -ForegroundColor Red
    exit 1
}

# --- Validate profile --------------------------------------------------------

$target = $profileMap.$Profile

if (-not $target) {
    $available = ($profileMap.PSObject.Properties.Name | Sort-Object) -join ', '
    Write-Host ""
    Write-Host "  [erro] Perfil '$Profile' nao encontrado." -ForegroundColor Red
    Write-Host "  Disponiveis: $available" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Expand ~ if present
$target = $target -replace '^~', $env:USERPROFILE

# --- Set env var (current process only) -------------------------------------
# setx is intentionally NOT used: a persistent user env var would contaminate
# all terminal sessions and VS Code windows opened after this switch, making it
# impossible to run the primary profile without explicitly resetting the var.
# Isolation is achieved via:
#   - terminal: shell functions (claude-<name>) set CLAUDE_CONFIG_DIR per process
#   - VS Code panel: claudeCode.environmentVariables in settings.json (updated below)

$env:CLAUDE_CONFIG_DIR = $target

# --- Update VS Code settings.json --------------------------------------------

if (-not $NoVSCode) {
    $settingsPath = "$env:APPDATA\Code\User\settings.json"

    if (Test-Path $settingsPath) {
        try {
            $raw = Get-Content $settingsPath -Raw -Encoding UTF8

            # Strip JSONC single-line comments so ConvertFrom-Json can parse
            $stripped = $raw `
                -replace '(?m)^\s*//[^\r\n]*', '' `
                -replace ',\s*([\r\n]+\s*[}\]])', '$1'

            $json = $stripped | ConvertFrom-Json

            # terminal.integrated.env.windows -- new integrated terminals inherit the profile
            if (-not ($json.PSObject.Properties.Name -contains 'terminal.integrated.env.windows')) {
                $json | Add-Member -NotePropertyName 'terminal.integrated.env.windows' `
                                   -NotePropertyValue ([PSCustomObject]@{}) -Force
            }
            $termBlock = $json.'terminal.integrated.env.windows'
            if ($termBlock.PSObject.Properties.Name -contains 'CLAUDE_CONFIG_DIR') {
                $termBlock.CLAUDE_CONFIG_DIR = $target
            } else {
                $termBlock | Add-Member -NotePropertyName 'CLAUDE_CONFIG_DIR' `
                                        -NotePropertyValue $target -Force
            }

            # claudeCode.environmentVariables -- injected into the extension process
            # After "Developer: Reload Window" the extension passes CLAUDE_CONFIG_DIR
            # to the Claude subprocess, switching accounts in the panel.
            $claudeEnvVars = @()
            if ($json.PSObject.Properties.Name -contains 'claudeCode.environmentVariables') {
                $existing = $json.'claudeCode.environmentVariables'
                if ($existing) {
                    $claudeEnvVars = @($existing | Where-Object { $_.name -ne 'CLAUDE_CONFIG_DIR' })
                }
            }
            $claudeEnvVars += [PSCustomObject]@{ name = 'CLAUDE_CONFIG_DIR'; value = $target }
            $json | Add-Member -NotePropertyName 'claudeCode.environmentVariables' `
                               -NotePropertyValue $claudeEnvVars -Force

            $json | ConvertTo-Json -Depth 50 | Set-Content -Path $settingsPath -Encoding UTF8

        } catch {
            Write-Host "  [aviso] Nao foi possivel atualizar o VS Code settings.json: $_" -ForegroundColor Yellow
            Write-Host "  Adicione manualmente: claudeCode.environmentVariables > CLAUDE_CONFIG_DIR = $target" -ForegroundColor DarkGray
        }
    }
}

# --- Output ------------------------------------------------------------------

Write-Host ""
Write-Host "  Perfil ativo: $Profile" -ForegroundColor Green
Write-Host "  CLAUDE_CONFIG_DIR = $target" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Terminal: novos terminais integrados ja usam este perfil." -ForegroundColor Cyan

if (-not $NoVSCode -and (Test-Path "$env:APPDATA\Code\User\settings.json")) {
    Write-Host "  Painel VS Code: Ctrl+Shift+P -> Developer: Reload Window" -ForegroundColor Yellow
    Write-Host "  (Reload Window e suficiente, nao precisa fechar o VS Code)" -ForegroundColor DarkGray
}

# --- Warn if no credentials --------------------------------------------------

$cred = Join-Path $target '.credentials.json'
$needsLogin = -not (Test-Path $cred)
if ($needsLogin) {
    Write-Host ""
    Write-Host "  [aviso] Perfil '$Profile' ainda nao tem credenciais." -ForegroundColor Magenta
    Write-Host "  Execute /login dentro do Claude para autenticar." -ForegroundColor Magenta
}

Write-Host ""

# --- Auto-launch Claude (unless called from inside Claude via slash command) --

if (-not $NoLaunch) {
    Write-Host "  Iniciando Claude com o perfil '$Profile'..." -ForegroundColor Cyan
    Write-Host ""
    & claude
}
