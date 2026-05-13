#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Multi-Agents — Gerenciador de Perfis
.DESCRIPTION
    Sem argumentos: menu interativo para criar, trocar, renomear e remover perfis.
    Com 'install': setup inicial completo (primeira vez).
    Com 'switch -Profile <nome>': troca silenciosa usada pelos slash commands do Claude.
.EXAMPLE
    .\claude-profiles.ps1
    .\claude-profiles.ps1 install
    .\claude-profiles.ps1 switch -Profile trabalho -NoLaunch
#>
param(
    [string]$Command  = '',
    [string]$Profile  = '',
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptPath   = $MyInvocation.MyCommand.Path
$ScriptDir    = Split-Path -Parent $ScriptPath
$TemplatesDir = Join-Path $ScriptDir 'templates'
$LibPath      = Join-Path $ScriptDir 'lib\common.ps1'

# Carrega funcoes compartilhadas (local ou GitHub)
if (Test-Path $LibPath) {
    . $LibPath
} else {
    Write-Host ''
    Write-Host '  Baixando lib/common.ps1 do GitHub...' -ForegroundColor Cyan
    $tmp = Join-Path $env:TEMP 'cma-common.ps1'
    try {
        Invoke-WebRequest 'https://raw.githubusercontent.com/Gustavo-b017/claude-multi-agents/main/lib/common.ps1' `
            -OutFile $tmp -UseBasicParsing
        . $tmp
        $TemplatesDir = $null  # templates tambem nao existem localmente
    } catch {
        Write-Host '  Erro: lib/common.ps1 nao encontrado e download falhou.' -ForegroundColor Red
        Write-Host '  Clone o repositorio: git clone https://github.com/Gustavo-b017/claude-multi-agents' -ForegroundColor Yellow
        exit 1
    }
}

# Caminho onde o script fica instalado (chamado pelos slash commands)
$InstalledScript = "$(Get-PrimaryDir)\bin\claude-profiles.ps1"

# ==============================================================================
# UI
# ==============================================================================

function Show-Banner {
    Write-Host ''
    Write-Host '  +--------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '  |   Claude Multi-Agents -- Gerenciador de Perfis   |' -ForegroundColor DarkCyan
    Write-Host '  |   github.com/Gustavo-b017/claude-multi-agents    |' -ForegroundColor DarkGray
    Write-Host '  +--------------------------------------------------+' -ForegroundColor DarkCyan
}

function Show-Menu {
    param($map)
    $pn = Get-PrimaryName $map
    $cc = $env:CLAUDE_CONFIG_DIR
    $an = if ($cc) {
        $f = $map.GetEnumerator() | Where-Object { $_.Value -eq $cc } | Select-Object -First 1
        if ($f) { $f.Key } else { $pn }
    } else { $pn }
    $others = ($map.Keys | Where-Object { $_ -ne $an }) -join ' | '

    Write-Host ''
    Write-Host '  +--------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '  |   Claude Multi-Agents -- Gerenciador de Perfis   |' -ForegroundColor DarkCyan
    Write-Host '  +--------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host "  Perfil ativo: $an" -ForegroundColor Green -NoNewline
    if ($others) { Write-Host "   |  outros: $others" -ForegroundColor DarkGray }
    else         { Write-Host '' }
    Write-Host ''
    Write-Host '  [1] Listar perfis' -ForegroundColor White
    Write-Host '  [2] Criar perfil' -ForegroundColor White
    Write-Host '  [3] Trocar perfil ativo' -ForegroundColor White
    Write-Host '  [4] Renomear perfil' -ForegroundColor White
    Write-Host '  [5] Remover perfil' -ForegroundColor White
    Write-Host '  [6] Gerenciar grupos (compartilhar entre contas)' -ForegroundColor White
    Write-Host '  [0] Sair' -ForegroundColor DarkGray
    Write-Host ''
}

# ==============================================================================
# Helpers de selecao
# ==============================================================================

function Pick-Profile {
    param($map, [switch]$ExcludePrimary)
    $pn   = Get-PrimaryName $map
    $list = if ($ExcludePrimary) {
        @($map.Keys | Where-Object { $_ -ne $pn })
    } else {
        @($map.Keys)
    }
    if ($list.Count -eq 0) { return $null }

    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-Host "    [$($i+1)] $($list[$i])" -ForegroundColor DarkGray
    }
    Write-Host ''
    $sel = (Read-Host '  Numero').Trim()
    $idx = 0
    if (-not ([int]::TryParse($sel, [ref]$idx)) -or $idx -lt 1 -or $idx -gt $list.Count) {
        Write-Err 'Opcao invalida.'
        return $null
    }
    return $list[$idx - 1]
}

function Sync-Script {
    if ($ScriptPath -and $ScriptPath -ne $InstalledScript -and (Test-Path $ScriptPath)) {
        Copy-Item $ScriptPath $InstalledScript -Force
    }
}

# ==============================================================================
# Operacoes do menu
# ==============================================================================

function Do-List {
    param($map)
    $pn = Get-PrimaryName $map
    $cc = $env:CLAUDE_CONFIG_DIR
    Write-Host '  Perfis registrados:' -ForegroundColor White
    Write-Host ''
    foreach ($e in $map.GetEnumerator()) {
        $isPrimary = $e.Key -eq $pn
        $isActive  = $e.Value -eq $cc -or ($isPrimary -and -not $cc)
        $tags = @()
        if ($isPrimary) { $tags += 'primario' }
        if ($isActive)  { $tags += 'ATIVO' }
        $tagStr = if ($tags) { "  [$($tags -join ', ')]" } else { '' }
        $color  = if ($isActive) { 'Green' } else { 'DarkGray' }
        Write-Host "    claude-$($e.Key)$tagStr" -ForegroundColor $color
        Write-Host "      $($e.Value)" -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Do-Add {
    param($map)
    Write-Host ''
    $raw  = Read-Host '  Nome do novo perfil (ex: trabalho, freelance, cliente)'
    $name = Sanitize-Name $raw
    if ([string]::IsNullOrEmpty($name)) { Write-Err 'Nome invalido.'; return $map }
    if ($map.Contains($name))           { Write-Warn "Perfil '$name' ja existe."; return $map }

    $dir        = "$env:USERPROFILE\.claude-$name"
    $map[$name] = $dir

    Write-Host ''
    Write-Step "Criando perfil '$name'..."
    Ensure-SharedDirs
    Setup-ProfileFiles -Name $name -Dir $dir -TemplatesDir $TemplatesDir
    Save-ProfilesJson $map
    Sync-Script
    New-SlashCommand -Name $name -ScriptPath $InstalledScript
    Update-PowerShellProfile $map
    if (Has-Bash) { Update-BashRc $map }
    Update-BinLaunchers $map

    Write-Host ''
    Write-Host "  + Perfil '$name' criado!" -ForegroundColor Green
    Write-Host '    1. Abra um novo PowerShell' -ForegroundColor DarkGray
    Write-Host "    2. Execute: claude-$name" -ForegroundColor DarkGray
    if (-not (Test-Path "$dir\.credentials.json")) {
        Write-Host '    3. Dentro do Claude: /login' -ForegroundColor Magenta
    }
    Write-Host ''
    return Load-ProfilesJson
}

function Do-Switch {
    param($map)
    $pn = Get-PrimaryName $map
    if (($map.Keys | Where-Object { $_ -ne $pn }).Count -eq 0) {
        Write-Warn 'Nenhum perfil adicional para trocar.'
        return
    }

    Write-Host ''
    Write-Host '  Para qual perfil trocar?' -ForegroundColor White
    $name = Pick-Profile $map -ExcludePrimary
    if (-not $name) { return }

    $dir = $map[$name]
    Set-ActiveProfile -Name $name -Dir $dir

    Write-Host ''
    Write-Ok "Perfil '$name' ativo nesta sessao."
    Write-Host "    Novo terminal: abra um novo PowerShell e use claude-$name" -ForegroundColor DarkGray
    if (Test-Path "$env:APPDATA\Code\User\settings.json") {
        Write-Host '    VS Code: Ctrl+Shift+P -> Developer: Reload Window' -ForegroundColor Yellow
    }
    if (-not (Test-Path "$dir\.credentials.json")) {
        Write-Host '    Sem credenciais ainda. Dentro do Claude: /login' -ForegroundColor Magenta
    }
    Write-Host ''
}

function Do-Rename {
    param($map)
    $pn = Get-PrimaryName $map
    if (($map.Keys | Where-Object { $_ -ne $pn }).Count -eq 0) {
        Write-Warn 'Nenhum perfil para renomear.'
        return $map
    }

    Write-Host ''
    Write-Host '  Qual perfil renomear?' -ForegroundColor White
    $oldName = Pick-Profile $map -ExcludePrimary
    if (-not $oldName) { return $map }

    $oldDir      = $map[$oldName]
    $expectedDir = "$env:USERPROFILE\.claude-$oldName"

    Write-Host ''
    if ($oldDir -ne $expectedDir) {
        Write-Warn "Diretorio atual : $oldDir"
        Write-Warn "Esperado       : $expectedDir"
        Write-Host ''
    }

    $raw     = Read-Host "  Novo nome para '$oldName' (Enter = manter '$oldName')"
    $newName = if ([string]::IsNullOrWhiteSpace($raw)) { $oldName } else { Sanitize-Name $raw }

    if ([string]::IsNullOrEmpty($newName)) { Write-Err 'Nome invalido.'; return $map }

    $newDir = "$env:USERPROFILE\.claude-$newName"

    if ($newName -eq $oldName -and $oldDir -eq $newDir) {
        Write-Warn 'Nenhuma alteracao necessaria.'
        return $map
    }

    if ($newName -ne $oldName -and $map.Contains($newName)) {
        Write-Err "Perfil '$newName' ja existe."
        return $map
    }

    Write-Host ''
    Write-Step "Atualizando perfil '$oldName'..."
    if ($oldDir -ne $newDir) { Write-Step "  $oldDir -> $newDir" }

    # Rename dir on disk only when the path actually changes
    if ($oldDir -ne $newDir) {
        Remove-Junctions -Dir $oldDir
        if (Test-Path $oldDir) {
            Rename-Item -Path $oldDir -NewName ".claude-$newName"
        }
    }

    # Guarantee all 4 global junctions exist (creates missing, converts real dirs to junctions)
    Ensure-GlobalJunctions -Dir $newDir

    # Rebuild map preserving order
    $newMap = [ordered]@{}
    foreach ($e in $map.GetEnumerator()) {
        if ($e.Key -eq $oldName) { $newMap[$newName] = $newDir }
        else                     { $newMap[$e.Key]   = $e.Value }
    }
    Save-ProfilesJson $newMap

    # Remove old launchers / slash command only when name changed
    if ($newName -ne $oldName) {
        $oldCmd = "$(Get-PrimaryDir)\commands\profile-$oldName.md"
        if (Test-Path $oldCmd) { Remove-Item $oldCmd -Force }

        $bin = "$env:USERPROFILE\bin"
        foreach ($ext in @('.cmd', '')) {
            $f = "$bin\claude-$oldName$ext"
            if (Test-Path $f) { Remove-Item $f -Force }
        }
    }

    New-SlashCommand -Name $newName -ScriptPath $InstalledScript
    Update-PowerShellProfile $newMap
    if (Has-Bash) { Update-BashRc $newMap }
    Update-BinLaunchers $newMap

    # Update groups.json references
    $groups = Load-Groups
    if ($groups.Count -gt 0 -and $newName -ne $oldName) {
        $changed = $false
        foreach ($g in $groups) {
            if ($g.source -eq $oldName) { $g.source = $newName; $changed = $true }
            $g.members = @($g.members | ForEach-Object {
                if ($_ -eq $oldName) { $changed = $true; $newName } else { $_ }
            })
        }
        if ($changed) { Save-Groups $groups }
    }

    Write-Host ''
    Write-Ok "Perfil atualizado: '$oldName' -> '$newName'"
    if ($oldDir -ne $newDir) { Write-Ok "Diretorio: $(Split-Path $oldDir -Leaf) -> $(Split-Path $newDir -Leaf)" }
    Write-Warn "Abra um novo terminal e use: claude-$newName"
    Write-Host ''
    return Load-ProfilesJson
}

function Do-Remove {
    param($map)
    $pn = Get-PrimaryName $map
    if (($map.Keys | Where-Object { $_ -ne $pn }).Count -eq 0) {
        Write-Warn 'Nenhum perfil adicional para remover.'
        return $map
    }

    Write-Host ''
    Write-Host '  Qual perfil remover?' -ForegroundColor White
    $name = Pick-Profile $map -ExcludePrimary
    if (-not $name) { return $map }

    $dir = $map[$name]
    Write-Host ''
    Write-Warn "Vai apagar permanentemente: $dir"
    Write-Host ''
    if (-not (Ask-YesNo "Confirma remocao do perfil '$name'?")) {
        Write-Warn 'Cancelado.'
        return $map
    }

    if (Test-Path $dir) {
        Remove-Junctions -Dir $dir
        Remove-Item -Path $dir -Recurse -Force
    }

    $map.Remove($name)
    Save-ProfilesJson $map

    $cmdFile = "$(Get-PrimaryDir)\commands\profile-$name.md"
    if (Test-Path $cmdFile) { Remove-Item $cmdFile -Force }

    $bin = "$env:USERPROFILE\bin"
    foreach ($ext in @('.cmd', '')) {
        $f = "$bin\claude-$name$ext"
        if (Test-Path $f) { Remove-Item $f -Force }
    }

    Update-PowerShellProfile $map
    if (Has-Bash) { Update-BashRc $map }

    Write-Host ''
    Write-Ok "Perfil '$name' removido."
    Write-Host "  Perfis restantes: $($map.Keys -join ', ')" -ForegroundColor DarkGray
    Write-Host ''
    return Load-ProfilesJson
}

# ==============================================================================
# Gerenciamento de grupos
# ==============================================================================

# Opcoes de compartilhamento disponiveis nos grupos
$SHARE_OPTIONS = @(
    [PSCustomObject]@{ key = 'projects'; desc = 'Historico e memoria de projetos' }
    [PSCustomObject]@{ key = 'memory';   desc = 'Memoria global do assistente' }
    [PSCustomObject]@{ key = 'sessions'; desc = 'Sessoes de conversa' }
    [PSCustomObject]@{ key = 'tasks';    desc = 'Tarefas (TodoWrite)' }
    [PSCustomObject]@{ key = 'plans';    desc = 'Planos de implementacao' }
    [PSCustomObject]@{ key = 'todos';    desc = 'Lista de todos' }
    [PSCustomObject]@{ key = 'backups';  desc = 'Backups de configuracao' }
)

function Show-Groups {
    param([array]$groups, $map)
    Write-Host ''
    Write-Host '  Compartilhamento global (todos os perfis):' -ForegroundColor Cyan
    Write-Host '    skills/  agents/  commands/  hooks/  -> ~/.claude/' -ForegroundColor DarkGray
    Write-Host ''
    if ($groups.Count -eq 0) {
        Write-Host '  Nenhum grupo configurado.' -ForegroundColor DarkGray
    } else {
        Write-Host '  Grupos:' -ForegroundColor White
        foreach ($g in $groups) {
            $members = $g.members -join ', '
            $share   = $g.share   -join ', '
            Write-Host "    [$($g.name)]  fonte: $($g.source)  membros: $members" -ForegroundColor White
            Write-Host "      compartilha: $share" -ForegroundColor DarkGray
        }
    }
    Write-Host ''
}

function Do-ManageGroups {
    param($map)
    $groups = Load-Groups

    do {
        Show-Groups $groups $map
        Write-Host '  [1] Criar grupo' -ForegroundColor White
        Write-Host '  [2] Remover grupo' -ForegroundColor White
        Write-Host '  [0] Voltar' -ForegroundColor DarkGray
        Write-Host ''
        $opt = (Read-Host '  Escolha').Trim()
        Write-Host ''

        switch ($opt) {
            '1' { $groups = Do-CreateGroup $map $groups }
            '2' { $groups = Do-DeleteGroup $map $groups }
            '0' { }
            default { Write-Warn 'Opcao invalida.' }
        }
    } while ($opt -ne '0')
}

function Do-CreateGroup {
    param($map, [array]$groups)

    Write-Host '  Criar grupo de compartilhamento' -ForegroundColor White
    Write-Host '  Use para contas do mesmo usuario que devem ter o mesmo historico.' -ForegroundColor DarkGray
    Write-Host ''

    # Nome do grupo
    $name = (Read-Host '  Nome do grupo (ex: pessoal, trabalho)').Trim()
    if ([string]::IsNullOrEmpty($name)) { Write-Err 'Nome invalido.'; return $groups }
    if ($groups | Where-Object { $_.name -eq $name }) { Write-Warn "Grupo '$name' ja existe."; return $groups }

    # Perfil fonte
    Write-Host ''
    Write-Host '  Perfil FONTE (conteudo existente sera preservado):' -ForegroundColor White
    $source = Pick-Profile $map
    if (-not $source) { return $groups }

    # Membros
    $available = @($map.Keys | Where-Object { $_ -ne $source })
    if ($available.Count -eq 0) { Write-Warn 'Nenhum outro perfil disponivel.'; return $groups }

    Write-Host ''
    Write-Host '  Membros do grupo (numeros separados por virgula):' -ForegroundColor White
    Write-Host '  (conteudo existente sera mesclado para a fonte, fonte vence conflitos)' -ForegroundColor DarkGray
    for ($i = 0; $i -lt $available.Count; $i++) {
        Write-Host "    [$($i+1)] $($available[$i])" -ForegroundColor DarkGray
    }
    Write-Host ''
    $sel     = (Read-Host '  Numeros (ex: 1,2)').Trim()
    $members = @()
    foreach ($s in ($sel -split ',')) {
        $idx = 0
        if ([int]::TryParse($s.Trim(), [ref]$idx) -and $idx -ge 1 -and $idx -le $available.Count) {
            $members += $available[$idx - 1]
        }
    }
    if ($members.Count -eq 0) { Write-Err 'Nenhum membro valido.'; return $groups }

    # O que compartilhar
    Write-Host ''
    Write-Host '  O que compartilhar? (numeros separados por virgula, Enter = tudo)' -ForegroundColor White
    for ($i = 0; $i -lt $SHARE_OPTIONS.Count; $i++) {
        Write-Host "    [$($i+1)] $($SHARE_OPTIONS[$i].key)  —  $($SHARE_OPTIONS[$i].desc)" -ForegroundColor DarkGray
    }
    Write-Host ''
    $sel2 = (Read-Host '  Numeros').Trim()
    $share = @()
    if ([string]::IsNullOrEmpty($sel2)) {
        $share = @($SHARE_OPTIONS | ForEach-Object { $_.key })
    } else {
        foreach ($s in ($sel2 -split ',')) {
            $idx = 0
            if ([int]::TryParse($s.Trim(), [ref]$idx) -and $idx -ge 1 -and $idx -le $SHARE_OPTIONS.Count) {
                $share += $SHARE_OPTIONS[$idx - 1].key
            }
        }
    }
    if ($share.Count -eq 0) { Write-Err 'Nenhuma opcao valida.'; return $groups }

    # Confirmacao
    Write-Host ''
    Write-Warn "Fonte    : $source"
    Write-Warn "Membros  : $($members -join ', ')"
    Write-Warn "Compartilha: $($share -join ', ')"
    Write-Host ''
    if (-not (Ask-YesNo 'Confirma criacao do grupo?')) { Write-Warn 'Cancelado.'; return $groups }

    $group = [PSCustomObject]@{
        name    = $name
        source  = $source
        members = $members
        share   = $share
    }

    Write-Host ''
    Write-Step "Aplicando grupo '$name'..."
    Apply-Group -group $group -map $map

    $newGroups = @($groups) + @($group)
    Save-Groups $newGroups
    Write-Ok "Grupo '$name' criado!"
    return $newGroups
}

function Do-DeleteGroup {
    param($map, [array]$groups)
    if ($groups.Count -eq 0) { Write-Warn 'Nenhum grupo para remover.'; return $groups }

    for ($i = 0; $i -lt $groups.Count; $i++) {
        $g = $groups[$i]
        Write-Host "    [$($i+1)] $($g.name)  (fonte: $($g.source) | membros: $($g.members -join ', '))" -ForegroundColor DarkGray
    }
    Write-Host ''
    $sel = (Read-Host '  Numero do grupo a remover').Trim()
    $idx = 0
    if (-not ([int]::TryParse($sel, [ref]$idx)) -or $idx -lt 1 -or $idx -gt $groups.Count) {
        Write-Err 'Opcao invalida.'; return $groups
    }
    $g = $groups[$idx - 1]

    Write-Host ''
    Write-Warn "Remove o grupo '$($g.name)' e desfaz as junctions."
    Write-Warn "Conteudo sera copiado da fonte para cada membro."
    Write-Host ''
    if (-not (Ask-YesNo "Confirma remocao do grupo '$($g.name)'?")) { Write-Warn 'Cancelado.'; return $groups }

    Write-Host ''
    Write-Step "Removendo grupo '$($g.name)'..."
    Remove-Group -group $g -map $map

    $newGroups = @($groups | Where-Object { $_.name -ne $g.name })
    Save-Groups $newGroups
    Write-Ok "Grupo '$($g.name)' removido."
    return $newGroups
}

# ==============================================================================
# install — setup inicial completo
# ==============================================================================

function Do-Install {
    Show-Banner
    Write-Host ''
    Write-Step 'Verificando pre-requisitos...'

    try {
        $v = & claude --version 2>&1
        Write-Ok "Claude Code: $v"
    } catch {
        Write-Err 'Claude Code nao encontrado. Instale em https://claude.ai/download'
        exit 1
    }

    $pd = Get-PrimaryDir
    if (-not (Test-Path $pd)) {
        Write-Err "~/.claude nao encontrado. Execute 'claude' uma vez antes de instalar."
        exit 1
    }
    Write-Ok "Perfil primario: $pd"

    Write-Host ''
    $raw = Read-Host "  Nome do perfil primario (~/.claude) [Enter = 'primary']"
    $pn  = if ([string]::IsNullOrWhiteSpace($raw)) { 'primary' } else { Sanitize-Name $raw }

    $count = 0
    do { $cs = Read-Host '  Quantos perfis adicionais? (1-5)' }
    until ([int]::TryParse($cs.Trim(), [ref]$count) -and $count -ge 1 -and $count -le 5)

    $extra = @()
    for ($i = 1; $i -le $count; $i++) {
        $raw = Read-Host "  Nome do perfil $i (ex: trabalho, freelance)"
        $extra += Sanitize-Name $raw
    }

    $map = [ordered]@{}
    $map[$pn] = $pd
    foreach ($p in $extra) { $map[$p] = "$env:USERPROFILE\.claude-$p" }

    Write-Host ''
    Ensure-SharedDirs
    Save-ProfilesJson $map

    foreach ($p in $extra) {
        Write-Step "Configurando perfil: $p"
        Setup-ProfileFiles -Name $p -Dir $map[$p] -TemplatesDir $TemplatesDir
        Write-Host ''
    }

    Copy-Item $ScriptPath $InstalledScript -Force
    Write-Ok 'Script instalado em ~/.claude/bin/'

    foreach ($name in $map.Keys) {
        New-SlashCommand -Name $name -ScriptPath $InstalledScript
    }

    Update-PowerShellProfile $map
    if (Has-Bash) { Update-BashRc $map }
    Update-BinLaunchers $map

    $pol = Get-ExecutionPolicy
    if ($pol -notin @('Bypass', 'Unrestricted', 'RemoteSigned')) {
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Write-Ok 'ExecutionPolicy: RemoteSigned'
        } catch {
            Write-Warn 'Altere manualmente: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'
        }
    }

    Write-Host ''
    Write-Host '  +--------------------------------------------------+' -ForegroundColor Green
    Write-Host '  |   Instalacao concluida!                          |' -ForegroundColor Green
    Write-Host '  +--------------------------------------------------+' -ForegroundColor Green
    Write-Host ''
    Write-Host '  Proximos passos:' -ForegroundColor White
    Write-Host '  1. Feche e reabra o PowerShell (ou: . $PROFILE)' -ForegroundColor DarkGray
    foreach ($p in $extra) {
        Write-Host "  2. Use o perfil: claude-$p" -ForegroundColor DarkGray
        Write-Host '     Dentro do Claude: /login' -ForegroundColor DarkGray
    }
    Write-Host '  3. Para gerenciar perfis depois: .\claude-profiles.ps1' -ForegroundColor DarkGray
    Write-Host ''
}

# ==============================================================================
# switch — troca silenciosa (chamado pelos slash commands)
# ==============================================================================

function Do-SwitchDirect {
    param([string]$ProfileName)
    $map = Load-ProfilesJson
    if (-not $map.Contains($ProfileName)) {
        Write-Err "Perfil '$ProfileName' nao encontrado. Disponiveis: $($map.Keys -join ', ')"
        exit 1
    }
    $dir = $map[$ProfileName] -replace '^~', $env:USERPROFILE

    Set-ActiveProfile -Name $ProfileName -Dir $dir

    Write-Host ''
    Write-Ok "Perfil '$ProfileName' ativo."
    Write-Host "  CLAUDE_CONFIG_DIR = $dir" -ForegroundColor DarkGray

    if (Test-Path "$env:APPDATA\Code\User\settings.json") {
        Write-Host '  VS Code: Ctrl+Shift+P -> Developer: Reload Window' -ForegroundColor Yellow
    }
    if (-not (Test-Path "$dir\.credentials.json")) {
        Write-Host ''
        Write-Warn "Perfil '$ProfileName' sem credenciais. Dentro do Claude: /login"
    }
    Write-Host ''

    if (-not $NoLaunch) {
        Write-Host "  Iniciando Claude com o perfil '$ProfileName'..." -ForegroundColor Cyan
        Write-Host ''
        & claude
    }
}

# ==============================================================================
# Entry point
# ==============================================================================

switch ($Command.ToLower()) {

    'install' {
        Do-Install
    }

    'switch' {
        if ([string]::IsNullOrWhiteSpace($Profile)) {
            Write-Err 'Use: .\claude-profiles.ps1 switch -Profile <nome>'
            exit 1
        }
        Do-SwitchDirect -ProfileName $Profile
    }

    default {
        $pd = Get-PrimaryDir
        if (-not (Test-Path $pd) -or -not (Test-Path "$pd\profiles.json")) {
            Show-Banner
            Write-Host ''
            Write-Warn 'Claude Multi-Agents ainda nao foi instalado.'
            Write-Warn 'Execute: .\claude-profiles.ps1 install'
            Write-Host ''
            exit 0
        }

        Show-Banner
        $map = Load-ProfilesJson

        do {
            Show-Menu $map
            $opt = (Read-Host '  Escolha').Trim()
            Write-Host ''

            switch ($opt) {
                '1' { Do-List   $map }
                '2' { $map = Do-Add    $map }
                '3' { Do-Switch $map }
                '4' { $map = Do-Rename $map }
                '5' { $map = Do-Remove $map }
                '6' { Do-ManageGroups $map }
                '0' { Write-Host '  Ate logo!' -ForegroundColor DarkGray }
                default { Write-Warn 'Opcao invalida. Escolha entre 0 e 5.' }
            }
        } while ($opt -ne '0')

        Write-Host ''
    }
}
