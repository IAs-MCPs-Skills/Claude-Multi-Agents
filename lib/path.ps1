#Requires -Version 5.1
# lib/path.ps1 — Garante que a pasta de launchers (~/bin) esteja no PATH do usuario
# Uso: . (Join-Path $PSScriptRoot '..\lib\path.ps1')
#
# Por que existe: os aliases claude-<perfil> funcionam via funcao no $PROFILE
# (PowerShell) e no ~/.bashrc (Git Bash), mas o cmd.exe nao le nenhum dos dois —
# ele so enxerga o PATH. Update-BinLaunchers (lib/common.ps1) grava os shims
# claude-<perfil>.cmd/bash em ~/bin; esta funcao garante que ~/bin esteja no
# PATH do usuario para que o cmd.exe encontre esses shims.

function Ensure-UserBinOnPath {
    # Adiciona $Dir ao PATH do usuario (HKCU) se ainda nao estiver la.
    # Nunca usa setx (trunca em 1024 chars) e nunca sobrescreve o PATH sem
    # preservar o valor atual. So mexe no PATH de User, nunca em Machine.
    param([string]$Dir)

    if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }

    $normalized = $Dir.Trim().Trim('"').TrimEnd('\', '/')

    $current = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($null -eq $current) { $current = '' }

    $entries = @($current -split ';' | Where-Object { $_ -ne '' })
    $alreadyInUserPath = $entries | Where-Object {
        $_.Trim().Trim('"').TrimEnd('\', '/') -ieq $normalized
    }

    if (-not $alreadyInUserPath) {
        $trimmed = $current.TrimEnd(';')
        $newPath = if ($trimmed -eq '') { $normalized } else { "$trimmed;$normalized" }
        [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
        Write-Ok "PATH do usuario atualizado: $normalized"
        Write-Warn 'Terminais ja abertos (cmd.exe, PowerShell, Git Bash) precisam ser reabertos para enxergar o PATH novo.'
    }

    # Atualiza tambem a sessao atual, para o alias funcionar sem reabrir terminal
    $sessionEntries = @($env:PATH -split ';' | Where-Object { $_ -ne '' })
    $alreadyInSession = $sessionEntries | Where-Object {
        $_.Trim().Trim('"').TrimEnd('\', '/') -ieq $normalized
    }
    if (-not $alreadyInSession) {
        $env:PATH = $env:PATH.TrimEnd(';') + ';' + $normalized
    }
}
