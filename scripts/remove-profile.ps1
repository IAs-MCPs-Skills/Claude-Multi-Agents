#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Multi-Agents -- Remover perfil
.DESCRIPTION
    Remove um perfil: apaga o diretorio e remove do profiles.json.
    O perfil primario (~/.claude) nunca pode ser removido.
.PARAMETER Profile
    Nome do perfil a remover. Se omitido, lista os disponiveis e pergunta.
.EXAMPLE
    .\scripts\remove-profile.ps1
.EXAMPLE
    .\scripts\remove-profile.ps1 -Profile pipi
#>
param([string]$Profile = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step { param($m) Write-Host "  o $m" -ForegroundColor Cyan   }
function Write-Ok   { param($m) Write-Host "  + $m" -ForegroundColor Green  }
function Write-Warn { param($m) Write-Host "  ! $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  x $m" -ForegroundColor Red    }
function Ask-YesNo  { param($q) $r = Read-Host "  $q [s/N]"; return ($r -match '^[sSyY]') }

Write-Host ""
Write-Host "  =====================================================" -ForegroundColor DarkCyan
Write-Host "   Claude Multi-Agents -- Remover Perfil               " -ForegroundColor DarkCyan
Write-Host "   https://github.com/Gustavo-b017/claude-multi-agents" -ForegroundColor DarkGray
Write-Host "  =====================================================" -ForegroundColor DarkCyan
Write-Host ""

# --- Carregar profiles.json ---------------------------------------------------

$PrimaryDir     = "$env:USERPROFILE\.claude"
$profilesConfig = "$PrimaryDir\profiles.json"

if (-not (Test-Path $profilesConfig)) {
    Write-Err "profiles.json nao encontrado em ~/.claude/"
    exit 1
}

try {
    $existingJson = Get-Content $profilesConfig -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Err "Falha ao ler profiles.json: $_"
    exit 1
}

$ProfileMap  = [ordered]@{}
$PrimaryName = 'primary'
foreach ($prop in $existingJson.PSObject.Properties) {
    $ProfileMap[$prop.Name] = $prop.Value
    if ($prop.Value -eq $PrimaryDir) { $PrimaryName = $prop.Name }
}

$removable = @($ProfileMap.Keys | Where-Object { $_ -ne $PrimaryName })

if ($removable.Count -eq 0) {
    Write-Warn "Nenhum perfil adicional para remover."
    exit 0
}

# --- Escolher perfil ----------------------------------------------------------

Write-Host "  Perfis disponiveis:" -ForegroundColor White
foreach ($name in $removable) {
    Write-Host "    - $name  ($($ProfileMap[$name]))" -ForegroundColor DarkGray
}
Write-Host ""

if ([string]::IsNullOrWhiteSpace($Profile)) {
    $Profile = (Read-Host "  Nome do perfil a remover").Trim().ToLower()
}

if (-not $ProfileMap.Contains($Profile)) {
    Write-Err "Perfil '$Profile' nao encontrado. Disponiveis: $($removable -join ', ')"
    exit 1
}

if ($Profile -eq $PrimaryName) {
    Write-Err "O perfil primario nao pode ser removido."
    exit 1
}

$TargetDir = $ProfileMap[$Profile]

# --- Confirmacao --------------------------------------------------------------

Write-Host ""
Write-Warn "Vai apagar permanentemente: $TargetDir"
Write-Host ""

if (-not (Ask-YesNo "Confirma remocao do perfil '$Profile'?")) {
    Write-Warn "Cancelado."
    exit 0
}

# --- Remover ------------------------------------------------------------------

Write-Host ""
Write-Step "Removendo perfil '$Profile'..."

if (Test-Path $TargetDir) {
    foreach ($link in @('skills', 'agents', 'commands')) {
        $linkPath = "$TargetDir\$link"
        if (Test-Path $linkPath) { cmd /c "rmdir `"$linkPath`"" 2>&1 | Out-Null }
    }
    Remove-Item -Path $TargetDir -Recurse -Force
    Write-Ok "Diretorio removido: $TargetDir"
} else {
    Write-Warn "Diretorio nao encontrado (ja removido?)"
}

$ProfileMap.Remove($Profile)
$ProfileMap | ConvertTo-Json -Depth 3 | Set-Content -Path $profilesConfig -Encoding UTF8
Write-Ok "Perfil '$Profile' removido do profiles.json"

$cmdFile = "$PrimaryDir\commands\profile-$Profile.md"
if (Test-Path $cmdFile) {
    Remove-Item $cmdFile -Force
    Write-Ok "Slash command /profile-$Profile removido"
}

# --- Resumo -------------------------------------------------------------------

Write-Host ""
Write-Host "  =====================================================" -ForegroundColor Green
Write-Host "   Perfil '$Profile' removido com sucesso!             " -ForegroundColor Green
Write-Host "  =====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Perfis restantes: $($ProfileMap.Keys -join ', ')" -ForegroundColor DarkGray
Write-Host ""
