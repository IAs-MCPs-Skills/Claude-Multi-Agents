#Requires -Version 5.1
<#
.SYNOPSIS
    Adds or updates a single Claude Code profile.
.DESCRIPTION
    Reads ~/.claude/profiles.json, creates (or overwrites) one profile,
    then regenerates the PowerShell functions and slash command.
    All other profiles remain untouched.
.PARAMETER Name
    Profile name to create or update. Must be lowercase alphanumeric/dash.
.PARAMETER Force
    Overwrite existing settings.json and CLAUDE.md for the profile.
.PARAMETER NoVSCode
    Skip VS Code settings.json update.
.PARAMETER NoBash
    Skip ~/.bashrc update.
.EXAMPLE
    .\add-profile.ps1 -Name cliente-abc
.EXAMPLE
    .\add-profile.ps1 -Name trabalho -Force
#>
param(
    [string] $Name    = '',
    [switch] $Force,
    [switch] $NoVSCode,
    [switch] $NoBash
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = if ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else { $PWD.Path }

# --- Helpers ------------------------------------------------------------------

function Write-Step { param($m) Write-Host "  o $m" -ForegroundColor Cyan   }
function Write-Ok   { param($m) Write-Host "  + $m" -ForegroundColor Green  }
function Write-Warn { param($m) Write-Host "  ! $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  x $m" -ForegroundColor Red    }

function Sanitize-Name {
    param([string]$n)
    ($n.Trim().ToLower() -replace '[^a-z0-9\-]', '')
}

# --- Banner -------------------------------------------------------------------

Write-Host ""
Write-Host "  =====================================================" -ForegroundColor DarkCyan
Write-Host "   Claude Multi-Agents -- Adicionar / Atualizar Perfil " -ForegroundColor DarkCyan
Write-Host "  =====================================================" -ForegroundColor DarkCyan
Write-Host ""

# --- Prerequisites ------------------------------------------------------------

$PrimaryDir = "$env:USERPROFILE\.claude"

if (-not (Test-Path $PrimaryDir)) {
    Write-Err "Diretorio primario nao encontrado: $PrimaryDir"
    Write-Warn "Execute 'claude' uma vez para criar o perfil padrao."
    exit 1
}

$ProfilesConfig = "$PrimaryDir\profiles.json"

if (-not (Test-Path $ProfilesConfig)) {
    Write-Err "profiles.json nao encontrado em ~/.claude/"
    Write-Warn "Execute .\install.ps1 primeiro para configurar o ambiente base."
    exit 1
}

# --- Load profiles.json -------------------------------------------------------

try {
    $raw = Get-Content $ProfilesConfig -Raw -Encoding UTF8
    $ProfileMap = $raw | ConvertFrom-Json
} catch {
    Write-Err "Falha ao ler profiles.json: $_"
    exit 1
}

# Converter PSCustomObject para hashtable ordenada preservando entradas existentes
$ordered = [ordered]@{}
foreach ($p in $ProfileMap.PSObject.Properties) {
    $ordered[$p.Name] = $p.Value
}
$ProfileMap = $ordered

# Detectar perfil primario (diretorio = ~/.claude)
$PrimaryName = ($ProfileMap.GetEnumerator() |
    Where-Object { $_.Value -eq $PrimaryDir } |
    Select-Object -First 1).Key

if (-not $PrimaryName) {
    Write-Warn "Perfil primario nao detectado em profiles.json. Assumindo primeiro perfil."
    $PrimaryName = @($ProfileMap.Keys)[0]
}

# --- Coletar nome do perfil ---------------------------------------------------

if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-Host "  Perfis existentes:" -ForegroundColor White
    foreach ($k in $ProfileMap.Keys) {
        $marker = if ($k -eq $PrimaryName) { ' (primario)' } else { '' }
        Write-Host "    $k$marker  ->  $($ProfileMap[$k])" -ForegroundColor DarkGray
    }
    Write-Host ""
    $raw = Read-Host "  Nome do perfil a criar ou atualizar"
    $Name = Sanitize-Name $raw
}

if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-Err "Nome invalido."
    exit 1
}

if ($Name -eq $PrimaryName) {
    Write-Err "Nao e possivel modificar o perfil primario ('$PrimaryName') com este script."
    Write-Warn "Edite diretamente: $PrimaryDir"
    exit 1
}

# --- Verificar se e update ou criacao -----------------------------------------

$IsUpdate = $ProfileMap.ContainsKey($Name)

if ($IsUpdate) {
    Write-Step "Perfil '$Name' ja existe. Modo: ATUALIZAR"
    $ProfileDir = $ProfileMap[$Name] -replace '^~', $env:USERPROFILE
} else {
    Write-Step "Perfil '$Name' nao existe. Modo: CRIAR"
    $ProfileDir = "$env:USERPROFILE\.claude-$Name"
    $ProfileMap[$Name] = $ProfileDir
}

Write-Host "  Diretorio: $ProfileDir" -ForegroundColor DarkGray
Write-Host ""

# --- Diretorio do perfil ------------------------------------------------------

Write-Step "Diretorio do perfil..."

if (-not (Test-Path $ProfileDir)) {
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
    Write-Ok "Criado: $ProfileDir"
} else {
    Write-Ok "Ja existe: $ProfileDir"
}

# --- Resolver templates -------------------------------------------------------

$TemplatesDir = Join-Path $ScriptDir 'templates'
$NeedsDownload = -not (Test-Path (Join-Path $TemplatesDir 'settings.json'))

if ($NeedsDownload) {
    Write-Step "Baixando templates do GitHub..."
    $TempDir = Join-Path $env:TEMP "cma-add-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path "$TempDir\templates" -Force | Out-Null

    $BaseUrl = 'https://raw.githubusercontent.com/Gustavo-b017/claude-multi-agents/main'
    try {
        Invoke-WebRequest "$BaseUrl/templates/settings.json" -OutFile "$TempDir\templates\settings.json" -UseBasicParsing
        Invoke-WebRequest "$BaseUrl/templates/CLAUDE.md"     -OutFile "$TempDir\templates\CLAUDE.md"     -UseBasicParsing
        $TemplatesDir = "$TempDir\templates"
        Write-Ok "Templates baixados."
    } catch {
        Write-Warn "Falha ao baixar templates: $_"
        Write-Warn "Usando defaults minimos."
        $TemplatesDir = $null
    }
}

# --- settings.json ------------------------------------------------------------

Write-Step "settings.json..."

$settingsTarget = "$ProfileDir\settings.json"

if (-not (Test-Path $settingsTarget) -or $Force) {
    $src = if ($TemplatesDir) { Join-Path $TemplatesDir 'settings.json' } else { $null }
    if ($src -and (Test-Path $src)) {
        Copy-Item $src $settingsTarget -Force
    } else {
        '{}' | Set-Content -Path $settingsTarget -Encoding UTF8
    }
    $verb = if ($IsUpdate -and (Test-Path $settingsTarget)) { 'Sobrescrito' } else { 'Criado' }
    Write-Ok "$verb: settings.json"
} else {
    Write-Warn "settings.json ja existe -- use -Force para sobrescrever"
}

# --- CLAUDE.md ----------------------------------------------------------------

Write-Step "CLAUDE.md..."

$claudeMdTarget = "$ProfileDir\CLAUDE.md"

if (-not (Test-Path $claudeMdTarget) -or $Force) {
    $src = if ($TemplatesDir) { Join-Path $TemplatesDir 'CLAUDE.md' } else { $null }
    $content = if ($src -and (Test-Path $src)) {
        (Get-Content $src -Raw -Encoding UTF8) -replace '<name>', $Name
    } else {
        "# Perfil: $Name`n`nDescreva aqui o contexto e foco deste perfil.`n"
    }
    $content | Set-Content -Path $claudeMdTarget -Encoding UTF8
    $verb = if ($IsUpdate -and (Test-Path $claudeMdTarget)) { 'Sobrescrito' } else { 'Criado' }
    Write-Ok "$verb: CLAUDE.md"
} else {
    Write-Warn "CLAUDE.md ja existe -- use -Force para sobrescrever"
}

# --- Junctions: skills, agents, commands --------------------------------------

Write-Step "Junction points..."

foreach ($link in @('skills', 'agents', 'commands')) {
    $linkPath   = "$ProfileDir\$link"
    $targetPath = "$PrimaryDir\$link"

    # Garantir que o diretorio compartilhado existe
    if (-not (Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    }

    if (Test-Path $linkPath) {
        # Verificar se ja e uma junction para o local correto
        $item = Get-Item $linkPath -Force
        $isJunction = $item.LinkType -eq 'Junction'
        if ($isJunction) {
            Write-Ok "  Junction '$link' ja existe -- OK"
        } else {
            Write-Warn "  '$link' existe mas nao e junction -- pulando"
        }
    } else {
        $result = cmd /c "mklink /J `"$linkPath`" `"$targetPath`"" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "  Junction criada: $link -> ~/.claude/$link"
        } else {
            Write-Warn "  Falha ao criar junction '$link': $result"
        }
    }
}

# --- Salvar profiles.json atualizado ------------------------------------------

Write-Step "Atualizando profiles.json..."

$ProfileMap | ConvertTo-Json -Depth 3 | Set-Content -Path "$PrimaryDir\profiles.json" -Encoding UTF8
Write-Ok "profiles.json atualizado ($($ProfileMap.Count) perfis)"

# --- Slash command ------------------------------------------------------------

Write-Step "Slash command /profile-$Name..."

$CommandsDir   = "$PrimaryDir\commands"
$switchScript  = "$PrimaryDir\bin\switch-profile.ps1"

if (-not (Test-Path $CommandsDir)) {
    New-Item -ItemType Directory -Path $CommandsDir -Force | Out-Null
}

$cmdFile = "$CommandsDir\profile-$Name.md"
$cmdContent = @"
Switch the active Claude Code profile to '$Name'.

Run this PowerShell command immediately using the PowerShell tool — do not ask the user to run it manually:

``````powershell
powershell -ExecutionPolicy Bypass -File "$switchScript" -Profile "$Name" -NoLaunch
``````

After the command completes:
- Report whether the switch succeeded or failed.
- If running inside **VS Code panel**: tell the user to press ``Ctrl+Shift+P`` -> ``Developer: Reload Window`` to activate the new profile in the panel.
- If running in a **terminal session**: tell the user to close this Claude session and run ``claude-$Name`` in a new terminal to start Claude with the new profile.
"@

$cmdContent | Set-Content -Path $cmdFile -Encoding UTF8
Write-Ok "/profile-$Name criado em ~/.claude/commands/"

# --- PowerShell $PROFILE (regenerar bloco completo) ---------------------------

Write-Step "Atualizando PowerShell `$PROFILE..."

# Resolve profile path manually — $PROFILE is empty in non-interactive shells (e.g. Claude Code)
$hasPS7 = $null -ne (Get-Command pwsh -ErrorAction SilentlyContinue)
$PsProfilePath = if ($hasPS7) {
    "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
} else {
    "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
}
$PsProfileDir = Split-Path $PsProfilePath

if (-not (Test-Path $PsProfileDir)) {
    New-Item -ItemType Directory -Path $PsProfileDir -Force | Out-Null
}

$MarkerStart = '# -- Claude Multi-Agents: inicio --'
$MarkerEnd   = '# -- Claude Multi-Agents: fim --'

$existing = if (Test-Path $PsProfilePath) {
    Get-Content $PsProfilePath -Raw -Encoding UTF8
} else { '' }

# Remover bloco anterior (idempotente)
$existing = $existing -replace "(?s)$([regex]::Escape($MarkerStart)).*?$([regex]::Escape($MarkerEnd))\r?\n?", ''

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add($MarkerStart)
$lines.Add('')

foreach ($entry in $ProfileMap.GetEnumerator()) {
    $pName = $entry.Key
    $pDir  = $entry.Value -replace '^~', $env:USERPROFILE
    $lines.Add("function claude-$pName {")
    $lines.Add("    `$env:CLAUDE_CONFIG_DIR = `"$pDir`"")
    $lines.Add("    Write-Host `"[claude] Perfil: $pName`" -ForegroundColor Cyan")
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
$final | Set-Content -Path $PsProfilePath -Encoding UTF8

Write-Ok "PowerShell `$PROFILE atualizado: $PsProfilePath"

# --- Bash ~/.bashrc (opcional) ------------------------------------------------

$BashRc    = "$env:USERPROFILE\.bashrc"
$HasBash   = ($null -ne (Get-Command bash -ErrorAction SilentlyContinue)) -or
             (Test-Path "C:\Program Files\Git\bin\bash.exe")

# Se o bloco Claude ja existe no .bashrc, atualiza automaticamente (sem prompt)
$BashAlreadyConfigured = (Test-Path $BashRc) -and
    ((Get-Content $BashRc -Raw -Encoding UTF8) -match [regex]::Escape('# -- Claude Multi-Agents: inicio --'))

$DoBash = $false
if (-not $NoBash -and $HasBash) {
    if ($BashAlreadyConfigured) {
        Write-Ok "Bloco Claude detectado em ~/.bashrc -- atualizando automaticamente."
        $DoBash = $true
    } else {
        $r = Read-Host "  Atualizar ~/.bashrc (Git Bash)? [s/N]"
        $DoBash = ($r -match '^[sSyY]')
    }
}

if ($DoBash) {
    $MarkerBashStart = '# -- Claude Multi-Agents: inicio --'
    $MarkerBashEnd   = '# -- Claude Multi-Agents: fim --'

    $bashExisting = if (Test-Path $BashRc) {
        Get-Content $BashRc -Raw -Encoding UTF8
    } else { '' }

    $bashExisting = $bashExisting -replace "(?s)$([regex]::Escape($MarkerBashStart)).*?$([regex]::Escape($MarkerBashEnd))\n?", ''

    $UserProfileSlash = $env:USERPROFILE -replace '\\', '/'
    $bashLines = [System.Collections.Generic.List[string]]::new()
    $bashLines.Add($MarkerBashStart)
    $bashLines.Add('')

    foreach ($entry in $ProfileMap.GetEnumerator()) {
        $pName = $entry.Key
        $pDir  = ($entry.Value -replace '\\', '/') -replace "^$([regex]::Escape($UserProfileSlash))", '$HOME'
        $bashLines.Add("claude-$pName() {")
        $bashLines.Add("    export CLAUDE_CONFIG_DIR=`"$pDir`"")
        $bashLines.Add("    echo `"[claude] Perfil: $pName`"")
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

    $newBash  = $bashLines -join "`n"
    $finalBash = $bashExisting.TrimEnd() + "`n`n" + $newBash + "`n"
    [System.IO.File]::WriteAllText($BashRc, $finalBash, [System.Text.UTF8Encoding]::new($false))

    Write-Ok "~/.bashrc atualizado."
    Write-Warn "Execute: source ~/.bashrc (ou abra novo terminal Git Bash)"
}

# --- Summary ------------------------------------------------------------------

Write-Host ""
Write-Host "  =====================================================" -ForegroundColor Green
$verb2 = if ($IsUpdate) { 'atualizado' } else { 'criado' }
Write-Host "   Perfil '$Name' $verb2 com sucesso!              " -ForegroundColor Green
Write-Host "  =====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Perfis registrados:" -ForegroundColor White
foreach ($entry in $ProfileMap.GetEnumerator()) {
    $marker = if ($entry.Key -eq $PrimaryName) { ' (primario)' } else { '' }
    Write-Host "    claude-$($entry.Key)$marker  ->  $($entry.Value)" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "  Proximos passos:" -ForegroundColor White
Write-Host "  1. Feche e reabra o PowerShell (ou: . `$PROFILE)" -ForegroundColor DarkGray
Write-Host "  2. Use o perfil: claude-$Name" -ForegroundColor DarkGray
if (-not (Test-Path "$ProfileDir\.credentials.json")) {
    Write-Host ""
    Write-Host "  [aviso] Perfil '$Name' ainda nao tem credenciais." -ForegroundColor Magenta
    Write-Host "  Dentro do Claude, execute: /login" -ForegroundColor Magenta
}
Write-Host ""
Write-Host "  Para MCPs:" -ForegroundColor White
Write-Host "    Ative o perfil: claude-$Name" -ForegroundColor DarkGray
Write-Host "    Adicione MCPs:  claude mcp add <nome> --scope user -- <cmd> [args]" -ForegroundColor DarkGray
Write-Host "    Verifique:      claude mcp list" -ForegroundColor DarkGray
Write-Host ""
