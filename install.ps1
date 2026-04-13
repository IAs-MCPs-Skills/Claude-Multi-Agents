#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Multi-Agents -- Multi-Profile Installer for Windows
.DESCRIPTION
    Sets up multiple Claude Code profiles on a single machine.
    Each profile gets its own credentials, settings.json (MCPs) and CLAUDE.md.
    Skills, agents and commands are shared via junction points.
.PARAMETER Profiles
    Optional: profile names to create (skips interactive prompts).
    Example: -Profiles work,freelance
.PARAMETER PrimaryName
    Optional: name to use for the primary profile (~/.claude).
    Default: "primary"
.PARAMETER NoVSCode
    Skip VS Code integration.
.PARAMETER NoBash
    Skip Git Bash integration.
.PARAMETER Force
    Overwrite existing settings.json and CLAUDE.md files.
.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -Profiles work,freelance -PrimaryName personal
#>
param(
    [string[]]$Profiles    = @(),
    [string]  $PrimaryName = '',
    [switch]  $NoVSCode,
    [switch]  $NoBash,
    [switch]  $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = if ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else { '' }

# --- Helpers -----------------------------------------------------------------

function Write-Step  { param($m) Write-Host "  o $m" -ForegroundColor Cyan    }
function Write-Ok    { param($m) Write-Host "  + $m" -ForegroundColor Green   }
function Write-Warn  { param($m) Write-Host "  ! $m" -ForegroundColor Yellow  }
function Write-Err   { param($m) Write-Host "  x $m" -ForegroundColor Red     }
function Ask-YesNo   { param($q) $r = Read-Host "  $q [s/N]"; return ($r -match '^[sSyY]') }

function Sanitize-Name {
    param([string]$name)
    ($name.Trim().ToLower() -replace '[^a-z0-9\-]', '')
}

# --- Banner -------------------------------------------------------------------

Write-Host ""
Write-Host "  =====================================================" -ForegroundColor DarkCyan
Write-Host "   Claude Multi-Agents -- Multi-Profile Installer       " -ForegroundColor DarkCyan
Write-Host "   https://github.com/Gustavo-b017/claude-multi-agents" -ForegroundColor DarkGray
Write-Host "  =====================================================" -ForegroundColor DarkCyan
Write-Host ""

# --- Prerequisites ------------------------------------------------------------

Write-Step "Verificando pre-requisitos..."

# Claude Code
try {
    $v = & claude --version 2>&1
    Write-Ok "Claude Code encontrado: $v"
} catch {
    Write-Err "Claude Code nao encontrado. Instale em: https://claude.ai/download"
    exit 1
}

# Primary profile directory
$PrimaryDir = "$env:USERPROFILE\.claude"
if (-not (Test-Path $PrimaryDir)) {
    Write-Err "Diretorio primario nao encontrado: $PrimaryDir"
    Write-Warn "Execute 'claude' uma vez para criar o perfil padrao, depois rode este instalador."
    exit 1
}
Write-Ok "Perfil primario encontrado: $PrimaryDir"

# --- Resolve script assets (local ou remoto via irm | iex) -------------------

$NeedsDownload = [string]::IsNullOrEmpty($ScriptDir) -or
                 -not (Test-Path (Join-Path $ScriptDir 'scripts\switch-profile.ps1'))

if ($NeedsDownload) {
    Write-Step "Modo remoto detectado -- baixando arquivos do GitHub..."
    $TempDir = Join-Path $env:TEMP "cma-install-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path "$TempDir\scripts"   -Force | Out-Null
    New-Item -ItemType Directory -Path "$TempDir\templates" -Force | Out-Null

    $BaseUrl = 'https://raw.githubusercontent.com/Gustavo-b017/claude-multi-agents/main'
    try {
        Invoke-WebRequest "$BaseUrl/scripts/switch-profile.ps1" -OutFile "$TempDir\scripts\switch-profile.ps1" -UseBasicParsing
        Invoke-WebRequest "$BaseUrl/templates/settings.json"    -OutFile "$TempDir\templates\settings.json"    -UseBasicParsing
        Invoke-WebRequest "$BaseUrl/templates/CLAUDE.md"        -OutFile "$TempDir\templates\CLAUDE.md"        -UseBasicParsing
        $ScriptDir = $TempDir
        Write-Ok "Arquivos baixados para: $TempDir"
    } catch {
        Write-Err "Falha ao baixar arquivos do GitHub: $_"
        Write-Warn "Clone e execute localmente: git clone https://github.com/Gustavo-b017/claude-multi-agents"
        exit 1
    }
}

# --- Collect profile info -----------------------------------------------------

Write-Host ""

# Primary profile name
if ([string]::IsNullOrWhiteSpace($PrimaryName)) {
    $raw = Read-Host "  Nome do perfil primario (~/.claude) [Enter para 'primary']"
    $PrimaryName = if ([string]::IsNullOrWhiteSpace($raw)) { 'primary' } else { Sanitize-Name $raw }
}

# Additional profiles
if ($Profiles.Count -eq 0) {
    Write-Host ""
    $count = 0
    do {
        $countStr = Read-Host "  Quantos perfis adicionais voce quer criar? (1-5)"
    } until ([int]::TryParse($countStr.Trim(), [ref]$count) -and $count -ge 1 -and $count -le 5)

    $Profiles = @()
    for ($i = 1; $i -le $count; $i++) {
        $raw = Read-Host "  Nome do perfil $i (ex: trabalho, freelance, cliente)"
        $Profiles += Sanitize-Name $raw
    }
}

# Validate no duplicates or conflict with primary
foreach ($p in $Profiles) {
    if ($p -eq $PrimaryName) {
        Write-Err "Nome '$p' ja esta em uso pelo perfil primario."
        exit 1
    }
}

# --- VS Code integration ------------------------------------------------------

$VSCodeSettingsPath = "$env:APPDATA\Code\User\settings.json"
$HasVSCode = Test-Path $VSCodeSettingsPath

if (-not $NoVSCode -and $HasVSCode) {
    $DoVSCode = Ask-YesNo "Integrar com VS Code? (atualiza settings.json ao trocar perfil)"
} elseif (-not $HasVSCode) {
    Write-Warn "VS Code nao detectado -- pulando integracao."
    $DoVSCode = $false
} else {
    $DoVSCode = $false
}

# --- Git Bash integration -----------------------------------------------------

$BashRc = "$env:USERPROFILE\.bashrc"
$HasGitBash = ($null -ne (Get-Command bash -ErrorAction SilentlyContinue)) -or
              (Test-Path "C:\Program Files\Git\bin\bash.exe")

if (-not $NoBash -and $HasGitBash) {
    $DoBash = Ask-YesNo "Adicionar funcoes ao ~/.bashrc (Git Bash)?"
} else {
    if (-not $HasGitBash) { Write-Warn "Git Bash nao detectado -- pulando .bashrc." }
    $DoBash = $false
}

# --- Ensure shared dirs exist -------------------------------------------------

Write-Host ""
Write-Step "Preparando diretorios compartilhados..."

$SharedDirs = @('skills', 'agents', 'commands', 'bin')
foreach ($d in $SharedDirs) {
    $path = "$PrimaryDir\$d"
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Ok "Criado: ~/.claude/$d"
    }
}

# --- Build profile map --------------------------------------------------------

$ProfileMap = [ordered]@{}
$ProfileMap[$PrimaryName] = $PrimaryDir
foreach ($p in $Profiles) {
    $ProfileMap[$p] = "$env:USERPROFILE\.claude-$p"
}

# Save to profiles.json (read by switch-profile.ps1)
$ProfileMap | ConvertTo-Json -Depth 3 | Set-Content -Path "$PrimaryDir\profiles.json" -Encoding UTF8
Write-Ok "Mapa de perfis salvo em ~/.claude/profiles.json"

# --- Create additional profiles -----------------------------------------------

$TemplatesDir = Join-Path $ScriptDir 'templates'

foreach ($name in $Profiles) {
    $dir = $ProfileMap[$name]

    Write-Host ""
    Write-Step "Configurando perfil: $name"

    # Directory
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Ok "  Diretorio criado: $dir"
    } else {
        Write-Warn "  Diretorio ja existe -- mantendo conteudo existente"
    }

    # settings.json
    $settingsTarget = "$dir\settings.json"
    if (-not (Test-Path $settingsTarget) -or $Force) {
        $src = Join-Path $TemplatesDir 'settings.json'
        if (Test-Path $src) {
            Copy-Item $src $settingsTarget -Force
        } else {
            '{}' | Set-Content -Path $settingsTarget -Encoding UTF8
        }
        Write-Ok "  settings.json criado"
    } else {
        Write-Warn "  settings.json ja existe -- use -Force para sobrescrever"
    }

    # CLAUDE.md
    $claudeMdTarget = "$dir\CLAUDE.md"
    if (-not (Test-Path $claudeMdTarget) -or $Force) {
        $src = Join-Path $TemplatesDir 'CLAUDE.md'
        $content = if (Test-Path $src) {
            (Get-Content $src -Raw -Encoding UTF8) -replace '<name>', $name
        } else {
            "# Perfil: $name`n`nDescreva aqui o contexto e foco deste perfil.`n"
        }
        $content | Set-Content -Path $claudeMdTarget -Encoding UTF8
        Write-Ok "  CLAUDE.md criado"
    } else {
        Write-Warn "  CLAUDE.md ja existe -- use -Force para sobrescrever"
    }

    # Junction points: skills, agents, commands -> ~/.claude/
    foreach ($link in @('skills', 'agents', 'commands')) {
        $linkPath   = "$dir\$link"
        $targetPath = "$PrimaryDir\$link"

        if (Test-Path $linkPath) {
            Write-Warn "  Junction '$link' ja existe -- pulando"
        } else {
            $result = cmd /c "mklink /J `"$linkPath`" `"$targetPath`"" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "  Junction: $link -> ~/.claude/$link"
            } else {
                Write-Warn "  Falha ao criar junction '$link': $result"
            }
        }
    }
}

# --- Configure MCPs per profile (optional) ------------------------------------
#
# MCPs sao armazenados em .claude.json (nao em settings.json).
# O unico modo correto de adiciona-los e via `claude mcp add --scope user`.
# Ao definir CLAUDE_CONFIG_DIR antes do comando, ele grava no perfil certo.

Write-Host ""
Write-Step "Configuracao de MCPs por perfil (opcional)..."
Write-Host "  MCPs sao configurados via 'claude mcp add --scope user'." -ForegroundColor DarkGray
Write-Host "  O instalador pode configurar isso agora, ou voce pode fazer depois." -ForegroundColor DarkGray
Write-Host ""

foreach ($name in $Profiles) {
    $dir = $ProfileMap[$name]

    $doMcps = Ask-YesNo "Adicionar MCPs ao perfil '$name' agora?"
    if (-not $doMcps) {
        Write-Warn "  Pulando MCPs para '$name'. Para adicionar depois:"
        Write-Host "    1. Ative o perfil: claude-$name" -ForegroundColor DarkGray
        Write-Host "    2. Execute: claude mcp add <nome> --scope user [opcoes]" -ForegroundColor DarkGray
        Write-Host "    3. Verifique: claude mcp list" -ForegroundColor DarkGray
        continue
    }

    # Define CLAUDE_CONFIG_DIR para gravar no perfil correto
    $savedDir = $env:CLAUDE_CONFIG_DIR
    $env:CLAUDE_CONFIG_DIR = $dir

    while ($true) {
        Write-Host ""
        $mcpName = (Read-Host "  Nome do MCP (Enter para terminar)").Trim()
        if ([string]::IsNullOrWhiteSpace($mcpName)) { break }

        $typeChoice = ''
        while ($typeChoice -notin @('1', '2')) {
            $typeChoice = (Read-Host "  Tipo: [1] stdio (processo local)  [2] http (servidor remoto)").Trim()
        }

        if ($typeChoice -eq '2') {
            $mcpUrl  = (Read-Host "  URL do servidor").Trim()
            $hasAuth = Ask-YesNo "  Requer Bearer token?"
            if ($hasAuth) {
                $token  = (Read-Host "  Token").Trim()
                $result = & claude mcp add $mcpName --scope user --transport http $mcpUrl --header "Authorization: Bearer $token" 2>&1
            } else {
                $result = & claude mcp add $mcpName --scope user --transport http $mcpUrl 2>&1
            }
        } else {
            $mcpCmd  = (Read-Host "  Comando (ex: node, npx)").Trim()
            $rawArgs = (Read-Host "  Argumentos separados por virgula (ex: C:\path\server.js, arg2)").Trim()
            $mcpArgs = if ($rawArgs) {
                @($rawArgs -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
            } else { @() }

            if ($mcpArgs.Count -gt 0) {
                $result = & claude mcp add $mcpName --scope user -- $mcpCmd @mcpArgs 2>&1
            } else {
                $result = & claude mcp add $mcpName --scope user -- $mcpCmd 2>&1
            }
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Ok "  MCP '$mcpName' adicionado."
        } else {
            Write-Warn "  Falha ao adicionar '$mcpName': $result"
        }
    }

    $env:CLAUDE_CONFIG_DIR = $savedDir
    Write-Ok "  MCPs do perfil '$name' configurados. Verifique com: claude mcp list"
}

# --- Install switch-profile.ps1 -----------------------------------------------

Write-Host ""
Write-Step "Instalando switch-profile.ps1..."

$switchSrc = Join-Path $ScriptDir 'scripts\switch-profile.ps1'
$switchDst = "$PrimaryDir\bin\switch-profile.ps1"

if (Test-Path $switchSrc) {
    Copy-Item $switchSrc $switchDst -Force
    Write-Ok "switch-profile.ps1 instalado em ~/.claude/bin/"
} else {
    Write-Err "scripts\switch-profile.ps1 nao encontrado. Execute a partir da raiz do repositorio."
    exit 1
}

# --- Install slash commands ---------------------------------------------------

Write-Step "Instalando slash commands..."

$CommandsDir = "$PrimaryDir\commands"
foreach ($name in $ProfileMap.Keys) {
    $cmdFile = "$CommandsDir\profile-$name.md"
    $content = @"
Troca para o perfil '$name' do Claude Code.

Execute o comando abaixo e, no painel VS Code, pressione ``Ctrl+Shift+P`` -> ``Developer: Reload Window``:

``````powershell
powershell -ExecutionPolicy Bypass -File "$switchDst" -Profile "$name"
``````

Apos a execucao:
- **Terminal**: novos terminais integrados ja usam este perfil.
- **Painel VS Code**: ``Ctrl+Shift+P`` -> ``Developer: Reload Window`` (nao precisa fechar o VS Code).
"@
    $content | Set-Content -Path $cmdFile -Encoding UTF8
}

$cmds = ($ProfileMap.Keys | ForEach-Object { "/profile-$_" }) -join ', '
Write-Ok "Slash commands instalados: $cmds"

# --- Update PowerShell `$PROFILE ----------------------------------------------

Write-Host ""
Write-Step "Configurando funcoes no PowerShell..."

$PsProfilePath = $PROFILE
$PsProfileDir  = Split-Path $PsProfilePath

if (-not (Test-Path $PsProfileDir)) {
    New-Item -ItemType Directory -Path $PsProfileDir -Force | Out-Null
}

$MarkerStart = '# -- Claude Multi-Agents: inicio --'
$MarkerEnd   = '# -- Claude Multi-Agents: fim --'

$existing = if (Test-Path $PsProfilePath) {
    Get-Content $PsProfilePath -Raw -Encoding UTF8
} else { '' }

# Remove previous block (idempotent)
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
$final | Set-Content -Path $PsProfilePath -Encoding UTF8

Write-Ok "Funcoes adicionadas ao PowerShell `$PROFILE ($PsProfilePath)"

# --- Update .bashrc -----------------------------------------------------------

if ($DoBash) {
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

    foreach ($name in $ProfileMap.Keys) {
        $dir = ($ProfileMap[$name] -replace '\\', '/') -replace "^$([regex]::Escape($env:USERPROFILE -replace '\\', '/') )", '$HOME'
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
    $finalBash | Set-Content -Path $BashRc -Encoding UTF8

    Write-Ok "Funcoes adicionadas ao ~/.bashrc"
    Write-Warn "Execute: source ~/.bashrc (ou abra um novo terminal Git Bash)"
}

# --- ExecutionPolicy ----------------------------------------------------------

$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @('Restricted', 'Undefined', 'AllSigned')) {
    Write-Host ""
    Write-Step "Habilitando execucao de scripts PowerShell..."
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Ok "ExecutionPolicy definido como RemoteSigned (escopo: usuario atual)"
}

# --- Summary ------------------------------------------------------------------

Write-Host ""
Write-Host "  =====================================================" -ForegroundColor Green
Write-Host "   Instalacao concluida!                               " -ForegroundColor Green
Write-Host "  =====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Perfis configurados:" -ForegroundColor White
foreach ($name in $ProfileMap.Keys) {
    Write-Host "    claude-$name   ->   $($ProfileMap[$name])" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "  Proximos passos:" -ForegroundColor White
Write-Host "  1. Feche e reabra o PowerShell (ou: . `$PROFILE)" -ForegroundColor DarkGray
if ($DoBash) {
    Write-Host "  2. Em Git Bash: source ~/.bashrc" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "  Para cada perfil novo, faca o primeiro login:" -ForegroundColor White
foreach ($name in $Profiles) {
    Write-Host "    claude-$name   ->   dentro do Claude: /login" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "  Para adicionar/verificar MCPs de um perfil:" -ForegroundColor White
Write-Host "    claude mcp add <nome> --scope user -- <comando> [args]" -ForegroundColor DarkGray
Write-Host "    claude mcp add <nome> --scope user --transport http <url>" -ForegroundColor DarkGray
Write-Host "    claude mcp list" -ForegroundColor DarkGray
Write-Host "  (Ative o perfil antes: claude-<nome>)" -ForegroundColor DarkGray
Write-Host ""
if ($DoVSCode) {
    Write-Host "  Apos trocar perfil no VS Code:" -ForegroundColor White
    Write-Host "    Ctrl+Shift+P -> Developer: Reload Window" -ForegroundColor DarkGray
    Write-Host ""
}
