#Requires -Version 5.1
# lib/common.ps1 — Funcoes compartilhadas do Claude Multi-Agents
# Uso: . (Join-Path $PSScriptRoot '..\lib\common.ps1')

# ------------------------------------------------------------------------------
# Output helpers
# ------------------------------------------------------------------------------

function Write-Step { param($m) Write-Host "  o $m" -ForegroundColor Cyan   }
function Write-Ok   { param($m) Write-Host "  + $m" -ForegroundColor Green  }
function Write-Warn { param($m) Write-Host "  ! $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  x $m" -ForegroundColor Red    }
function Ask-YesNo  { param($q) $r = Read-Host "  $q [s/N]"; return ($r -match '^[sSyY]') }

function Sanitize-Name {
    param([string]$n)
    ($n.Trim().ToLower() -replace '[^a-z0-9\-]', '')
}

# ------------------------------------------------------------------------------
# Profile JSON  (~/.claude/profiles.json)
# Formato: { "nome": "C:\Users\user\.claude-nome", "primary": "C:\Users\user\.claude" }
# ------------------------------------------------------------------------------

function Get-PrimaryDir { "$env:USERPROFILE\.claude" }

function Load-ProfilesJson {
    $path = "$(Get-PrimaryDir)\profiles.json"
    if (-not (Test-Path $path)) { return [ordered]@{} }
    try {
        $json = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $map  = [ordered]@{}
        foreach ($p in $json.PSObject.Properties) { $map[$p.Name] = $p.Value }
        return $map
    } catch {
        throw "Falha ao ler profiles.json: $_"
    }
}

function Save-ProfilesJson {
    param($map)
    $path = "$(Get-PrimaryDir)\profiles.json"
    $map | ConvertTo-Json -Depth 3 | Set-Content -Path $path -Encoding UTF8
}

function Get-PrimaryName {
    param($map)
    $pd = Get-PrimaryDir
    foreach ($e in $map.GetEnumerator()) {
        if ($e.Value -eq $pd) { return $e.Key }
    }
    return if ($map.Count -gt 0) { @($map.Keys)[0] } else { 'primary' }
}

# ------------------------------------------------------------------------------
# Profile setup
# ------------------------------------------------------------------------------

$GLOBAL_JUNCTIONS = @('skills', 'agents', 'commands', 'hooks', 'plugins')

function Ensure-SharedDirs {
    $pd = Get-PrimaryDir
    foreach ($d in ($GLOBAL_JUNCTIONS + @('bin'))) {
        $p = "$pd\$d"
        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
}

function Setup-ProfileFiles {
    param(
        [string]$Name,
        [string]$Dir,
        [string]$TemplatesDir,
        [switch]$Force
    )
    $pd = Get-PrimaryDir

    if (-not (Test-Path $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        Write-Ok "  Diretorio criado: $Dir"
    }

    $st = "$Dir\settings.json"
    if (-not (Test-Path $st) -or $Force) {
        $src = if ($TemplatesDir) { Join-Path $TemplatesDir 'settings.json' } else { $null }
        if ($src -and (Test-Path $src)) { Copy-Item $src $st -Force }
        else { '{}' | Set-Content -Path $st -Encoding UTF8 }
        Write-Ok "  settings.json criado"
    }

    $cm = "$Dir\CLAUDE.md"
    if (-not (Test-Path $cm) -or $Force) {
        $src = if ($TemplatesDir) { Join-Path $TemplatesDir 'CLAUDE.md' } else { $null }
        $content = if ($src -and (Test-Path $src)) {
            (Get-Content $src -Raw -Encoding UTF8) -replace '<name>', $Name
        } else {
            "# Perfil: $Name`n`nDescreva aqui o contexto e foco deste perfil.`n"
        }
        $content | Set-Content -Path $cm -Encoding UTF8
        Write-Ok "  CLAUDE.md criado"
    }

    Ensure-GlobalJunctions -Dir $Dir -Quiet
}

function Remove-Junctions {
    param([string]$Dir)
    foreach ($link in $GLOBAL_JUNCTIONS) {
        $lp = "$Dir\$link"
        if (Test-Path $lp) { cmd /c "rmdir `"$lp`"" 2>&1 | Out-Null }
    }
}

function Ensure-GlobalJunctions {
    param([string]$Dir, [switch]$Quiet)
    $pd = Get-PrimaryDir
    Ensure-SharedDirs
    foreach ($link in $GLOBAL_JUNCTIONS) {
        $lp = "$Dir\$link"
        $tp = "$pd\$link"

        if (-not (Test-Path $lp)) {
            cmd /c "mklink /J `"$lp`" `"$tp`"" 2>&1 | Out-Null
            if (-not $Quiet) { Write-Ok "  Junction criada: $link -> ~/.claude/$link" }
            continue
        }

        $item = Get-Item $lp -Force
        if ($item.LinkType -eq 'Junction') {
            # Junction exists but might point to wrong target — fix if stale
            if ($item.Target -ne $tp) {
                cmd /c "rmdir `"$lp`"" 2>&1 | Out-Null
                cmd /c "mklink /J `"$lp`" `"$tp`"" 2>&1 | Out-Null
                if (-not $Quiet) { Write-Ok "  ${link}: junction corrigida -> ~/.claude/$link" }
            }
            continue
        }

        # Diretorio real: mescla conteudo para global (global vence conflitos), converte em junction
        Get-ChildItem $lp -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $rel  = $_.FullName.Substring($lp.Length + 1)
            $dest = Join-Path $tp $rel
            if (-not (Test-Path $dest)) {
                $destDir = Split-Path $dest
                if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                Copy-Item $_.FullName $dest -Force
            }
        }
        Remove-Item $lp -Recurse -Force
        cmd /c "mklink /J `"$lp`" `"$tp`"" 2>&1 | Out-Null
        if (-not $Quiet) { Write-Ok "  ${link}: conteudo mesclado para global, convertido em junction" }
    }
}

# ------------------------------------------------------------------------------
# File hardlinks  (para grupos que compartilham arquivos de config)
# ------------------------------------------------------------------------------

function Apply-FileHardlinks {
    param($group, $map)
    if (-not $group.PSObject.Properties.Name -contains 'hardlinks') { return }
    if (-not $group.hardlinks -or $group.hardlinks.Count -eq 0) { return }

    $sourceDir = $map[$group.source]
    foreach ($member in $group.members) {
        if (-not $map.Contains($member)) { continue }
        $memberDir = $map[$member]
        foreach ($file in $group.hardlinks) {
            $src = "$sourceDir\$file"
            $dst = "$memberDir\$file"
            if (-not (Test-Path $src)) { Write-Warn "  Arquivo fonte nao existe: $src"; continue }
            if (Test-Path $dst) { Remove-Item $dst -Force }
            $r = cmd /c "mklink /H `"$dst`" `"$src`"" 2>&1
            if ($LASTEXITCODE -eq 0) { Write-Ok "  $member/$file hardlink -> $($group.source)/$file" }
            else                      { Write-Warn "  Falha hardlink $member/$file : $r" }
        }
    }
}

function Sync-McpServers {
    param($group, $map)
    $sourceDir = $map[$group.source]
    $srcClaude = "$sourceDir\.claude.json"
    if (-not (Test-Path $srcClaude)) { return }
    $srcJson = Get-Content $srcClaude -Raw | ConvertFrom-Json
    if (-not $srcJson.mcpServers) { return }

    foreach ($member in $group.members) {
        if (-not $map.Contains($member)) { continue }
        $dstClaude = "$($map[$member])\.claude.json"
        if (-not (Test-Path $dstClaude)) { continue }
        $dstJson = Get-Content $dstClaude -Raw | ConvertFrom-Json
        if (-not $dstJson.mcpServers) {
            $dstJson | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        $changed = $false
        foreach ($mcp in $srcJson.mcpServers.PSObject.Properties) {
            if (-not ($dstJson.mcpServers.PSObject.Properties.Name -contains $mcp.Name)) {
                $dstJson.mcpServers | Add-Member -NotePropertyName $mcp.Name -NotePropertyValue $mcp.Value -Force
                Write-Ok "  MCP '$($mcp.Name)' -> $member/.claude.json"
                $changed = $true
            }
        }
        if ($changed) { $dstJson | ConvertTo-Json -Depth 20 | Set-Content $dstClaude -Encoding UTF8 }
    }
}

# ------------------------------------------------------------------------------
# Groups  (~/.claude/groups.json)
# Formato: [{ name, source, members[], share[] }]
# share[] pode conter: 'projects', 'memory'
# ------------------------------------------------------------------------------

function Get-GroupsFile { "$(Get-PrimaryDir)\groups.json" }

function Load-Groups {
    $path = Get-GroupsFile
    if (-not (Test-Path $path)) { return @() }
    try {
        $raw = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $raw) { return @() }
        return @($raw)
    } catch { return @() }
}

function Save-Groups {
    param([array]$groups)
    $path = Get-GroupsFile
    if ($groups.Count -eq 0) {
        '[]' | Set-Content -Path $path -Encoding UTF8
    } else {
        $groups | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8
    }
}

function Apply-Group {
    param($group, $map)
    $sourceDir = $map[$group.source]
    foreach ($member in $group.members) {
        if (-not $map.Contains($member)) { Write-Warn "  Membro '$member' nao existe no profiles.json"; continue }
        $memberDir = $map[$member]
        foreach ($dir in $group.share) {
            $srcPath = "$sourceDir\$dir"
            $dstPath = "$memberDir\$dir"

            # Garante que o diretorio fonte existe
            if (-not (Test-Path $srcPath)) {
                New-Item -ItemType Directory -Path $srcPath -Force | Out-Null
            }

            if (Test-Path $dstPath) {
                $item = Get-Item $dstPath -Force
                if ($item.LinkType -eq 'Junction') {
                    # Ja e junction — remove e recria apontando para a fonte certa
                    cmd /c "rmdir `"$dstPath`"" 2>&1 | Out-Null
                } else {
                    # Diretorio real — mescla conteudo para a fonte (fonte vence conflitos)
                    Get-ChildItem $dstPath -Recurse -File -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        $rel  = $_.FullName.Substring($dstPath.Length + 1)
                        $dest = Join-Path $srcPath $rel
                        if (-not (Test-Path $dest)) {
                            $destDir = Split-Path $dest
                            if (-not (Test-Path $destDir)) {
                                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                            }
                            Copy-Item $_.FullName $dest -Force
                        }
                    }
                    Remove-Item $dstPath -Recurse -Force
                }
            }

            $r = cmd /c "mklink /J `"$dstPath`" `"$srcPath`"" 2>&1
            if ($LASTEXITCODE -eq 0) { Write-Ok "  $member/$dir -> $($group.source)/$dir" }
            else                      { Write-Warn "  Falha junction $member/$dir : $r" }
        }
    }
}

function Remove-Group {
    param($group, $map)
    $sourceDir = $map[$group.source]
    foreach ($member in $group.members) {
        if (-not $map.Contains($member)) { continue }
        $memberDir = $map[$member]
        foreach ($dir in $group.share) {
            $srcPath = "$sourceDir\$dir"
            $dstPath = "$memberDir\$dir"

            if (-not (Test-Path $dstPath)) { continue }
            $item = Get-Item $dstPath -Force
            if ($item.LinkType -ne 'Junction') { continue }

            cmd /c "rmdir `"$dstPath`"" 2>&1 | Out-Null
            New-Item -ItemType Directory -Path $dstPath -Force | Out-Null

            if (Test-Path $srcPath) {
                Copy-Item "$srcPath\*" $dstPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Ok "  $member/${dir}: junction removida, conteudo copiado da fonte"
        }
    }
}

# ------------------------------------------------------------------------------
# Slash command  (~/.claude/commands/profile-<name>.md)
# ------------------------------------------------------------------------------

function New-SlashCommand {
    param([string]$Name, [string]$ScriptPath)
    $f = "$(Get-PrimaryDir)\commands\profile-$Name.md"
    $c = @"
Switch the active Claude Code profile to '$Name'.

Run this PowerShell command immediately using the PowerShell tool:

``````powershell
powershell -ExecutionPolicy Bypass -File "$ScriptPath" switch -Profile "$Name" -NoLaunch
``````

After the command completes:
- VS Code panel: Ctrl+Shift+P -> Developer: Reload Window
- Terminal: abra um novo terminal e execute ``claude-$Name``
"@
    $c | Set-Content -Path $f -Encoding UTF8
}

# ------------------------------------------------------------------------------
# Shell integration
# ------------------------------------------------------------------------------

function Update-PowerShellProfile {
    param($map)
    $pd = Get-PrimaryDir
    $pn = Get-PrimaryName $map

    $psPath = if (-not [string]::IsNullOrWhiteSpace($PROFILE)) { $PROFILE }
              else { "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" }
    $psDir = Split-Path $psPath
    if (-not (Test-Path $psDir)) { New-Item -ItemType Directory -Path $psDir -Force | Out-Null }

    $ms = '# -- Claude Multi-Agents: inicio --'
    $me = '# -- Claude Multi-Agents: fim --'

    $ex = if (Test-Path $psPath) { Get-Content $psPath -Raw -Encoding UTF8 } else { '' }
    $ex = $ex -replace "(?s)$([regex]::Escape($ms)).*?$([regex]::Escape($me))\r?\n?", ''

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($ms); $lines.Add('')

    foreach ($e in $map.GetEnumerator()) {
        $n = $e.Key; $d = $e.Value
        $lines.Add("function claude-$n {")
        $lines.Add("    `$env:CLAUDE_CONFIG_DIR = `"$d`"")
        $lines.Add("    Write-Host `"[claude] Perfil: $n`" -ForegroundColor Cyan")
        $lines.Add("    claude @args")
        $lines.Add('}'); $lines.Add('')
    }

    $lines.Add('function claude-perfil {')
    $lines.Add("    `$d = `$env:CLAUDE_CONFIG_DIR")
    $lines.Add("    if (-not `$d -or `$d -eq `"$pd`") {")
    $lines.Add("        Write-Host `"Perfil ativo: $pn`" -ForegroundColor Cyan")
    $lines.Add('    } else {')
    $lines.Add("        `$n = (Split-Path `$d -Leaf) -replace '^\.claude-', ''")
    $lines.Add("        Write-Host `"Perfil ativo: `$n`" -ForegroundColor Cyan")
    $lines.Add('    }')
    $lines.Add('}'); $lines.Add(''); $lines.Add($me)

    $block = $lines -join "`n"
    $final = $ex.TrimEnd() + "`n`n" + $block + "`n"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $written = $false
    try {
        [System.IO.File]::WriteAllText($psPath, $final, $utf8NoBom)
        Write-Ok "PowerShell `$PROFILE atualizado"
        $written = $true
    } catch {
        # Fallback: write to a local non-OneDrive path and source it from $PROFILE
        $localPs = "$env:USERPROFILE\Documents\WindowsPowerShell\claude-multi-agents.ps1"
        $localDir = Split-Path $localPs
        if (-not (Test-Path $localDir)) { New-Item -ItemType Directory -Path $localDir -Force | Out-Null }
        try {
            [System.IO.File]::WriteAllText($localPs, $final, $utf8NoBom)
            Write-Ok "Funcoes salvas em: $localPs"
            Write-Warn "`$PROFILE esta em OneDrive sem permissao de escrita."
            Write-Warn "Adicione esta linha ao seu `$PROFILE manualmente:"
            Write-Host "    if (Test-Path '$localPs') { . '$localPs' }" -ForegroundColor Yellow
            $written = $true
        } catch {
            Write-Warn "Nao foi possivel atualizar `$PROFILE: $_"
        }
    }
}

function Update-BashRc {
    param($map)
    $brc = "$env:USERPROFILE\.bashrc"
    $pn  = Get-PrimaryName $map
    $ms  = '# -- Claude Multi-Agents: inicio --'
    $me  = '# -- Claude Multi-Agents: fim --'

    $ex = if (Test-Path $brc) { Get-Content $brc -Raw -Encoding UTF8 } else { '' }
    $ex = $ex -replace "(?s)$([regex]::Escape($ms)).*?$([regex]::Escape($me))\n?", ''

    $upfx = $env:USERPROFILE -replace '\\', '/'
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($ms); $lines.Add('')

    foreach ($e in $map.GetEnumerator()) {
        $n = $e.Key
        $d = ($e.Value -replace '\\', '/') -replace "^$([regex]::Escape($upfx))", '$HOME'
        $lines.Add("claude-$n() {")
        $lines.Add("    export CLAUDE_CONFIG_DIR=`"$d`"")
        $lines.Add("    echo `"[claude] Perfil: $n`"")
        $lines.Add('    claude "$@"')
        $lines.Add('}'); $lines.Add('')
    }

    $lines.Add('claude-perfil() {')
    $lines.Add('    if [ -z "$CLAUDE_CONFIG_DIR" ]; then')
    $lines.Add("        echo `"Perfil ativo: $pn`"")
    $lines.Add('    else')
    $lines.Add('        echo "Perfil ativo: $CLAUDE_CONFIG_DIR"')
    $lines.Add('    fi')
    $lines.Add('}'); $lines.Add(''); $lines.Add($me)

    $block = $lines -join "`n"
    $final = $ex.TrimEnd() + "`n`n" + $block + "`n"
    [System.IO.File]::WriteAllText($brc, $final, [System.Text.UTF8Encoding]::new($false))
    Write-Ok "~/.bashrc atualizado"
    Write-Warn "Execute: source ~/.bashrc"
}

function Update-BinLaunchers {
    param($map)
    $bin = "$env:USERPROFILE\bin"
    if (-not (Test-Path $bin)) { New-Item -ItemType Directory -Path $bin -Force | Out-Null }
    $upfx = $env:USERPROFILE -replace '\\', '/'

    foreach ($e in $map.GetEnumerator()) {
        $n = $e.Key; $d = $e.Value
        $ds = $d -replace '\\', '/'
        $db = $ds -replace "^$([regex]::Escape($upfx))", '$HOME'

        $cmd = "@echo off`r`nset `"CLAUDE_CONFIG_DIR=$d`"`r`necho [claude] Perfil: $n`r`nclaude %*`r`n"
        [System.IO.File]::WriteAllText("$bin\claude-$n.cmd", $cmd, [System.Text.UTF8Encoding]::new($false))

        $sh = "#!/usr/bin/env bash`nexport CLAUDE_CONFIG_DIR=`"$db`"`necho `"[claude] Perfil: $n`"`nclaude `"`$@`"`n"
        [System.IO.File]::WriteAllText("$bin\claude-$n", $sh, [System.Text.UTF8Encoding]::new($false))
    }
}

# ------------------------------------------------------------------------------
# Active profile switch (env var + VS Code settings.json)
# ------------------------------------------------------------------------------

function Set-ActiveProfile {
    param([string]$Name, [string]$Dir)
    $env:CLAUDE_CONFIG_DIR = $Dir

    $sp = "$env:APPDATA\Code\User\settings.json"
    if (-not (Test-Path $sp)) { return }

    try {
        $raw      = Get-Content $sp -Raw -Encoding UTF8
        $stripped = $raw `
            -replace '(?m)^\s*//[^\r\n]*', '' `
            -replace ',\s*([\r\n]+\s*[}\]])', '$1'
        $json = $stripped | ConvertFrom-Json

        if (-not ($json.PSObject.Properties.Name -contains 'terminal.integrated.env.windows')) {
            $json | Add-Member -NotePropertyName 'terminal.integrated.env.windows' `
                               -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        $tb = $json.'terminal.integrated.env.windows'
        if ($tb.PSObject.Properties.Name -contains 'CLAUDE_CONFIG_DIR') { $tb.CLAUDE_CONFIG_DIR = $Dir }
        else { $tb | Add-Member -NotePropertyName 'CLAUDE_CONFIG_DIR' -NotePropertyValue $Dir -Force }

        $ev = @()
        if ($json.PSObject.Properties.Name -contains 'claudeCode.environmentVariables') {
            $ex = $json.'claudeCode.environmentVariables'
            if ($ex) { $ev = @($ex | Where-Object { $_.name -ne 'CLAUDE_CONFIG_DIR' }) }
        }
        $ev += [PSCustomObject]@{ name = 'CLAUDE_CONFIG_DIR'; value = $Dir }
        $json | Add-Member -NotePropertyName 'claudeCode.environmentVariables' `
                           -NotePropertyValue $ev -Force

        $json | ConvertTo-Json -Depth 50 | Set-Content -Path $sp -Encoding UTF8
    } catch {
        Write-Warn "Nao foi possivel atualizar VS Code settings.json: $_"
    }
}

# ------------------------------------------------------------------------------
# Misc
# ------------------------------------------------------------------------------

function Has-Bash {
    ($null -ne (Get-Command bash -ErrorAction SilentlyContinue)) -or
    (Test-Path 'C:\Program Files\Git\bin\bash.exe')
}
