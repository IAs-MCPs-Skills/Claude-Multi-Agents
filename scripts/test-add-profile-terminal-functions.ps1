#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\add-profile.ps1'
$content = Get-Content -Path $scriptPath -Raw -Encoding UTF8

$requiredSnippets = @(
    'Configurando funcoes no PowerShell',
    'function claude-$name {',
    '$env:CLAUDE_CONFIG_DIR',
    'Configurando funcoes no ~/.bashrc',
    'claude-$name() {',
    'export CLAUDE_CONFIG_DIR=',
    'source ~/.bashrc',
    'Configurando launchers em ~/bin',
    'claude-$name.cmd'
)

foreach ($snippet in $requiredSnippets) {
    if ($content -notlike "*$snippet*") {
        throw "Missing expected add-profile terminal function snippet: $snippet"
    }
}

Write-Host 'add-profile terminal function checks passed'
