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
.EXAMPLE
    .\scripts\add-profile.ps1
.EXAMPLE
    .\scripts\add-profile.ps1 -Profile papi
#>
param(
    [string]$Profile     = '',
    [string]$PrimaryName = 'primary',
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
Write-Host "    `$env:CLAUDE_CONFIG_DIR = `"$NewDir`"" -ForegroundColor DarkGray
Write-Host "    claude" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Dentro do Claude, faca o login: /login" -ForegroundColor DarkGray
Write-Host ""
