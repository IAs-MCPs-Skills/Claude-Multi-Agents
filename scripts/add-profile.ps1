#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Multi-Agents -- Adicionar ou recriar perfil
.DESCRIPTION
    Cria um novo perfil Claude Code. Se o perfil ja existir, recria
    os arquivos sem apagar credenciais (.credentials.json).
    Para usar o perfil: $env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-<nome>"; claude
.PARAMETER Profile
    Nome do perfil. Se omitido, sera solicitado interativamente.
.PARAMETER PrimaryName
    Nome do perfil primario ao inicializar pela primeira vez. Default: "primary".
.PARAMETER Force
    Sobrescreve settings.json e CLAUDE.md mesmo se ja existirem.
.PARAMETER NoBash
    Nao atualiza ~/.bashrc mesmo se Git Bash estiver instalado.
.EXAMPLE
    .\scripts\add-profile.ps1
.EXAMPLE
    .\scripts\add-profile.ps1 -Profile papi
#>
param(
    [string]$Profile     = '',
    [string]$PrimaryName = 'primary',
    [switch]$NoBash,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = if ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
} else { '' }

function Write-Step { param($m) Write-Host "  o $m" -ForegroundColor Cyan   }
function Write-Ok   { param($m) Write-Host "  + $m" -ForegroundColor Green  }
function Write-Warn { param($m) Write-Host "  ! $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  x $m" -ForegroundColor Red    }

function Sanitize-Name {
    param([string]$name)
    ($name.Trim().ToLower() -replace '[^a-z0-9\-]', '')
}

Write-Host ""
Write-Host "  =====================================================" -ForegroundColor DarkCyan
Write-Host "   Claude Multi-Agents -- Adicionar Perfil             " -ForegroundColor DarkCyan
Write-Host "   https://github.com/Gustavo-b017/claude-multi-agents" -ForegroundColor DarkGray
Write-Host "  =====================================================" -ForegroundColor DarkCyan
Write-Host ""

# --- Pre-requisitos -----------------------------------------------------------

Write-Step "Verificando pre-requisitos..."

try {
    $v = & claude --version 2>&1
    Write-Ok "Claude Code encontrado: $v"
} catch {
    Write-Err "Claude Code nao encontrado. Instale em: https://claude.ai/download"
    exit 1
}

$PrimaryDir = "$env:USERPROFILE\.claude"
if (-not (Test-Path $PrimaryDir)) {
    Write-Err "Diretorio primario nao encontrado: $PrimaryDir"
    Write-Warn "Execute 'claude' uma vez para criar o perfil padrao."
    exit 1
}
Write-Ok "Perfil primario encontrado: $PrimaryDir"

# --- Resolve templates --------------------------------------------------------

$NeedsDownload = [string]::IsNullOrEmpty($ScriptDir) -or
                 -not (Test-Path (Join-Path $ScriptDir 'templates\settings.json'))

if ($NeedsDownload) {
    Write-Step "Baixando templates do GitHub..."
    $TempDir = Join-Path $env:TEMP "cma-add-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path "$TempDir\scripts"   -Force | Out-Null
    New-Item -ItemType Directory -Path "$TempDir\templates" -Force | Out-Null

    $BaseUrl = 'https://raw.githubusercontent.com/Gustavo-b017/claude-multi-agents/main'
    try {
        Invoke-WebRequest "$BaseUrl/scripts/switch-profile.ps1" -OutFile "$TempDir\scripts\switch-profile.ps1" -UseBasicParsing
        Invoke-WebRequest "$BaseUrl/templates/settings.json"    -OutFile "$TempDir\templates\settings.json"    -UseBasicParsing
        Invoke-WebRequest "$BaseUrl/templates/CLAUDE.md"        -OutFile "$TempDir\templates\CLAUDE.md"        -UseBasicParsing
        $ScriptDir = $TempDir
        Write-Ok "Templates baixados para: $TempDir"
    } catch {
        Write-Err "Falha ao baixar templates: $_"
        exit 1
    }
}

$TemplatesDir = Join-Path $ScriptDir 'templates'

# --- Carregar ou inicializar profiles.json ------------------------------------

Write-Host ""
$profilesConfig = "$PrimaryDir\profiles.json"
$ProfileMap     = [ordered]@{}

if (Test-Path $profilesConfig) {
    Write-Step "Carregando perfis existentes..."
    try {
        $existingJson = Get-Content $profilesConfig -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $existingJson.PSObject.Properties) {
            $ProfileMap[$prop.Name] = $prop.Value
        }
        foreach ($entry in $ProfileMap.GetEnumerator()) {
            if ($entry.Value -eq $PrimaryDir) { $PrimaryName = $entry.Key; break }
        }
        Write-Ok "Perfis existentes: $($ProfileMap.Keys -join ', ')"
    } catch {
        Write-Err "Falha ao ler profiles.json: $_"
        exit 1
    }
} else {
    Write-Step "Inicializando profiles.json com perfil primario..."
    $ProfileMap[$PrimaryName] = $PrimaryDir
    Write-Ok "Perfil primario: $PrimaryName -> $PrimaryDir"
}

# --- Nome do perfil -----------------------------------------------------------

Write-Host ""

if ([string]::IsNullOrWhiteSpace($Profile)) {
    $raw     = Read-Host "  Nome do perfil (ex: trabalho, cliente, freelance)"
    $Profile = Sanitize-Name $raw
} else {
    $Profile = Sanitize-Name $Profile
}

if ([string]::IsNullOrEmpty($Profile)) {
    Write-Err "Nome de perfil invalido."
    exit 1
}

$NewDir    = "$env:USERPROFILE\.claude-$Profile"
$IsRecreate = $ProfileMap.Contains($Profile)

if ($IsRecreate) {
    Write-Warn "Perfil '$Profile' ja existe -- recriando arquivos..."
} else {
    $ProfileMap[$Profile] = $NewDir
    $ProfileMap | ConvertTo-Json -Depth 3 | Set-Content -Path $profilesConfig -Encoding UTF8
    Write-Ok "profiles.json atualizado: perfil '$Profile' adicionado"
}

# --- Diretorios compartilhados ------------------------------------------------

Write-Host ""
Write-Step "Preparando diretorios compartilhados..."

foreach ($d in @('skills', 'agents', 'commands', 'bin')) {
    $path = "$PrimaryDir\$d"
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Ok "Criado: ~/.claude/$d"
    }
}

# --- Criar/recriar perfil -----------------------------------------------------

Write-Host ""
Write-Step "Configurando perfil: $Profile"

if (-not (Test-Path $NewDir)) {
    New-Item -ItemType Directory -Path $NewDir -Force | Out-Null
    Write-Ok "  Diretorio criado: $NewDir"
} else {
    Write-Ok "  Diretorio existente: $NewDir"
}

$settingsTarget = "$NewDir\settings.json"
if (-not (Test-Path $settingsTarget) -or $Force -or $IsRecreate) {
    $src = Join-Path $TemplatesDir 'settings.json'
    if (Test-Path $src) { Copy-Item $src $settingsTarget -Force } else { '{}' | Set-Content -Path $settingsTarget -Encoding UTF8 }
    Write-Ok "  settings.json atualizado"
}

$claudeMdTarget = "$NewDir\CLAUDE.md"
if (-not (Test-Path $claudeMdTarget) -or $Force -or $IsRecreate) {
    $src     = Join-Path $TemplatesDir 'CLAUDE.md'
    $content = if (Test-Path $src) {
        (Get-Content $src -Raw -Encoding UTF8) -replace '<name>', $Profile
    } else {
        "# Perfil: $Profile`n`nDescreva aqui o contexto e foco deste perfil.`n"
    }
    $content | Set-Content -Path $claudeMdTarget -Encoding UTF8
    Write-Ok "  CLAUDE.md atualizado"
}

foreach ($link in @('skills', 'agents', 'commands')) {
    $linkPath   = "$NewDir\$link"
    $targetPath = "$PrimaryDir\$link"
    if (Test-Path $linkPath) {
        Write-Ok "  Junction '$link' ok"
    } else {
        $result = cmd /c "mklink /J `"$linkPath`" `"$targetPath`"" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "  Junction: $link -> ~/.claude/$link"
        } else {
            Write-Warn "  Falha ao criar junction '$link': $result"
        }
    }
}

# --- switch-profile.ps1 + slash command ---------------------------------------

$switchSrc = Join-Path $ScriptDir 'scripts\switch-profile.ps1'
$switchDst = "$PrimaryDir\bin\switch-profile.ps1"

if (Test-Path $switchSrc) {
    Copy-Item $switchSrc $switchDst -Force
}

$cmdFile = "$PrimaryDir\commands\profile-$Profile.md"
$content = @"
Switch the active Claude Code profile to '$Profile'.

Run this PowerShell command immediately using the PowerShell tool — do not ask the user to run it manually:

``````powershell
powershell -ExecutionPolicy Bypass -File "$switchDst" -Profile "$Profile" -NoLaunch
``````

After the command completes:
- Report whether the switch succeeded or failed.
- If running inside **VS Code panel**: tell the user to press ``Ctrl+Shift+P`` -> ``Developer: Reload Window``.
- If running in a **terminal session**: tell the user to run ``claude-$Profile`` or set ```$env:CLAUDE_CONFIG_DIR`` manually.
"@
$content | Set-Content -Path $cmdFile -Encoding UTF8
Write-Ok "  Slash command criado: /profile-$Profile"

# --- PATH launchers -----------------------------------------------------------

Write-Host ""
Write-Step "Configurando launchers em ~/bin..."

$UserBin = Join-Path $env:USERPROFILE 'bin'
if (-not (Test-Path $UserBin)) {
    New-Item -ItemType Directory -Path $UserBin -Force | Out-Null
}

foreach ($name in $ProfileMap.Keys) {
    $dir = $ProfileMap[$name]
    $dirSlash = $dir -replace '\\', '/'
    $userProfileSlash = $env:USERPROFILE -replace '\\', '/'
    $dirBash = $dirSlash -replace "^$([regex]::Escape($userProfileSlash))", '$HOME'

    $cmdLauncher = @"
@echo off
set "CLAUDE_CONFIG_DIR=$dir"
echo [claude] Perfil: $name
claude %*
"@
    [System.IO.File]::WriteAllText((Join-Path $UserBin "claude-$name.cmd"), $cmdLauncher, [System.Text.UTF8Encoding]::new($false))

    $bashLauncher = @"
#!/usr/bin/env bash
export CLAUDE_CONFIG_DIR="$dirBash"
echo "[claude] Perfil: $name"
claude "`$@"
"@
    [System.IO.File]::WriteAllText((Join-Path $UserBin "claude-$name"), $bashLauncher, [System.Text.UTF8Encoding]::new($false))
}

$PathParts = $env:PATH -split ';'
if ($PathParts -contains $UserBin) {
    Write-Ok "  Launcher criado/atualizado: claude-$Profile"
} else {
    Write-Warn "  Launchers criados em $UserBin, mas esse diretorio nao esta no PATH atual"
}

# --- Terminal commands --------------------------------------------------------

Write-Host ""
Write-Step "Configurando funcoes no PowerShell..."

$PsProfilePath = if ([string]::IsNullOrWhiteSpace($PROFILE)) {
    Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
} else {
    $PROFILE
}
$PsProfileDir  = Split-Path $PsProfilePath
if ([string]::IsNullOrWhiteSpace($PsProfileDir)) {
    $PsProfilePath = Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    $PsProfileDir  = Split-Path $PsProfilePath
}

if (-not (Test-Path $PsProfileDir)) {
    New-Item -ItemType Directory -Path $PsProfileDir -Force | Out-Null
}

$MarkerStart = '# -- Claude Multi-Agents: inicio --'
$MarkerEnd   = '# -- Claude Multi-Agents: fim --'

$existing = if (Test-Path $PsProfilePath) {
    Get-Content $PsProfilePath -Raw -Encoding UTF8
} else { '' }

$existing = $existing -replace "(?s)$([regex]::Escape($MarkerStart)).*?$([regex]::Escape($MarkerEnd))\r?\n?", ''

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add($MarkerStart)
$lines.Add('')

foreach ($name in $ProfileMap.Keys) {
    $dir = $ProfileMap[$name]
    $lines.Add("function claude-$name {")
    $lines.Add("    `$env:CLAUDE_CONFIG_DIR = `"$dir`"")
    $lines.Add("    Write-Host `"[claude] Perfil: $name`" -ForegroundColor Cyan")
    $lines.Add("    claude @args")
    $lines.Add('}')
    $lines.Add('')
}

$lines.Add('function claude-perfil {')
$lines.Add("    `$d = `$env:CLAUDE_CONFIG_DIR")
$lines.Add("    if (-not `$d -or `$d -eq `"$PrimaryDir`") {")
$lines.Add("        Write-Host `"Perfil ativo: $PrimaryName ($PrimaryDir)`" -ForegroundColor Cyan")
$lines.Add('    } else {')
$lines.Add("        `$n = (Split-Path `$d -Leaf) -replace '\.claude-', ''")
$lines.Add("        Write-Host `"Perfil ativo: `$n (`$d)`" -ForegroundColor Cyan")
$lines.Add('    }')
$lines.Add('}')
$lines.Add('')
$lines.Add($MarkerEnd)

$newBlock = $lines -join "`n"
$final = $existing.TrimEnd() + "`n`n" + $newBlock + "`n"
try {
    $final | Set-Content -Path $PsProfilePath -Encoding UTF8 -ErrorAction Stop
    Write-Ok "  Funcao criada/atualizada: claude-$Profile"
    Write-Warn "  Execute: . `$PROFILE (ou abra um novo PowerShell)"
} catch {
    Write-Warn "  Nao foi possivel atualizar `$PROFILE ($PsProfilePath): $_"
    Write-Warn "  Use o launcher em ~/bin: claude-$Profile"
}

$BashRc = "$env:USERPROFILE\.bashrc"
$HasGitBash = ($null -ne (Get-Command bash -ErrorAction SilentlyContinue)) -or
              (Test-Path "C:\Program Files\Git\bin\bash.exe")

if (-not $NoBash -and $HasGitBash) {
    Write-Host ""
    Write-Step "Configurando funcoes no ~/.bashrc..."

    $MarkerBashStart = '# -- Claude Multi-Agents: inicio --'
    $MarkerBashEnd   = '# -- Claude Multi-Agents: fim --'

    $bashExisting = if (Test-Path $BashRc) {
        Get-Content $BashRc -Raw -Encoding UTF8
    } else { '' }

    $bashExisting = $bashExisting -replace "(?s)$([regex]::Escape($MarkerBashStart)).*?$([regex]::Escape($MarkerBashEnd))\n?", ''

    $bashLines = [System.Collections.Generic.List[string]]::new()
    $bashLines.Add($MarkerBashStart)
    $bashLines.Add('')

    $UserProfileSlash = $env:USERPROFILE -replace '\\', '/'
    foreach ($name in $ProfileMap.Keys) {
        $dir = ($ProfileMap[$name] -replace '\\', '/') -replace "^$([regex]::Escape($UserProfileSlash))", '$HOME'
        $bashLines.Add("claude-$name() {")
        $bashLines.Add("    export CLAUDE_CONFIG_DIR=`"$dir`"")
        $bashLines.Add("    echo `"[claude] Perfil: $name`"")
        $bashLines.Add('    claude "$@"')
        $bashLines.Add('}')
        $bashLines.Add('')
    }

    $bashLines.Add('claude-perfil() {')
    $bashLines.Add('    if [ -z "$CLAUDE_CONFIG_DIR" ]; then')
    $bashLines.Add("        echo `"Perfil ativo: $PrimaryName`"")
    $bashLines.Add('    else')
    $bashLines.Add('        echo "Perfil ativo: $CLAUDE_CONFIG_DIR"')
    $bashLines.Add('    fi')
    $bashLines.Add('}')
    $bashLines.Add('')
    $bashLines.Add($MarkerBashEnd)

    $newBash = $bashLines -join "`n"
    $finalBash = $bashExisting.TrimEnd() + "`n`n" + $newBash + "`n"
    [System.IO.File]::WriteAllText($BashRc, $finalBash, [System.Text.UTF8Encoding]::new($false))

    Write-Ok "  Funcao criada/atualizada no Bash: claude-$Profile"
    Write-Warn "  Execute: source ~/.bashrc (ou abra um novo Git Bash)"
} elseif ($NoBash) {
    Write-Warn "  ~/.bashrc nao atualizado por causa de -NoBash"
} else {
    Write-Warn "  Git Bash nao detectado -- ~/.bashrc nao atualizado"
}

# --- Resumo -------------------------------------------------------------------

Write-Host ""
Write-Host "  =====================================================" -ForegroundColor Green
if ($IsRecreate) {
    Write-Host "   Perfil '$Profile' recriado com sucesso!            " -ForegroundColor Green
} else {
    Write-Host "   Perfil '$Profile' criado com sucesso!              " -ForegroundColor Green
}
Write-Host "  =====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Para usar este perfil:" -ForegroundColor White
Write-Host "    claude-$Profile" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Se o terminal atual ainda nao reconhecer o comando:" -ForegroundColor White
Write-Host "    PowerShell: . `$PROFILE" -ForegroundColor DarkGray
Write-Host "    Git Bash:   source ~/.bashrc" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Dentro do Claude, faca o login: /login" -ForegroundColor DarkGray
Write-Host ""
