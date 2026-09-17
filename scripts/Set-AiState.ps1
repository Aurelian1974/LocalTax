#Requires -Version 7.0
<#
.SYNOPSIS
  Single writer for .ai/state/current.md. Agents change state with one short command instead of editing the file.
.EXAMPLE
  pwsh scripts/Set-AiState.ps1 -Init -Task "Add credit notes to Invoicing" -Tool copilot
  pwsh scripts/Set-AiState.ps1 phase=plan gate="G1 waiting" plan=.ai/plans/20260917-credit-notes.md
  pwsh scripts/Set-AiState.ps1 -Decision "Credit notes reuse the invoice numbering series" -Log "plan written"
  pwsh scripts/Set-AiState.ps1 -Handoff -Tool claude-code next="implementer: plan step 3"
  pwsh scripts/Set-AiState.ps1 -Show
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch] $Init,
    [string] $Task,
    [ValidateSet('copilot', 'claude-code')] [string] $Tool,
    [string] $Decision,
    [string] $Note,
    [string] $Log,
    [switch] $Handoff,
    [switch] $Show,
    [Parameter(ValueFromRemainingArguments)] [string[]] $Fields,
    [string] $RepoRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
$state = Join-Path $RepoRoot '.ai/state/current.md'
$template = Join-Path $RepoRoot '.ai/templates/state.md'
function Git-Sha { (git -C $RepoRoot rev-parse --short HEAD 2>$null) ?? 'none' }

if ($Init) {
    if (-not $Task) { throw '-Init requires -Task.' }
    if (Test-Path $state) {
        $archive = Join-Path $RepoRoot ".ai/state/archive/$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
        New-Item -ItemType Directory -Force -Path (Split-Path $archive) | Out-Null
        Move-Item $state $archive
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $state) | Out-Null
    $sha = Git-Sha
    $lines = (Get-Content $template) | ForEach-Object {
        switch -Regex ($_) {
            '^task:'  { "task: $Task" }
            '^base:'  { "base: $sha" }
            '^sha:'   { "sha: $sha" }
            '^tool:'  { "tool: $(if ($Tool) { $Tool } else { 'unknown' })" }
            '^phase:' { 'phase: classify' }
            '^gate:'  { 'gate: none' }
            '^class:' { 'class: unclassified' }
            '^modules:' { 'modules: none' }
            '^plan:'  { 'plan: none' }
            '^steps:' { 'steps: none' }
            '^next:'  { 'next: classify task' }
            '^- <'    { }                                  # drop placeholder list items
            default   { $_ }
        }
    }
    Set-Content $state $lines -Encoding utf8
}
if (-not (Test-Path $state)) { throw "No state file. Run with -Init -Task '<task>' first." }
if ($Show) { Get-Content $state; return }

$lines = [System.Collections.Generic.List[string]](Get-Content $state)
function Set-Field([string] $key, [string] $value) {
    $i = $lines.FindIndex({ param($l) $l -match "^$([regex]::Escape($key)):" })
    if ($i -lt 0) { throw "Unknown state field '$key'. Allowed: task class modules plan adrs base sha tool phase gate steps review_cycles next" }
    $lines[$i] = "${key}: $value"
}
function Add-Item([string] $section, [string] $text) {
    $i = $lines.IndexOf("## $section")
    if ($i -lt 0) { throw "Section '## $section' missing." }
    $j = $i + 1
    while ($j -lt $lines.Count -and $lines[$j] -notmatch '^## ') { $j++ }
    while ($j - 1 -gt $i -and [string]::IsNullOrWhiteSpace($lines[$j - 1])) { $j-- }
    $lines.Insert($j, "- $text")
}

foreach ($f in $Fields) {
    $m = [regex]::Match($f, '^(?<k>[a-z_]+)=(?<v>.*)$')
    if (-not $m.Success) { throw "Expected key=value, got '$f'." }
    Set-Field $m.Groups['k'].Value $m.Groups['v'].Value
}
if ($Tool -and -not $Init) { Set-Field 'tool' $Tool }
if ($Handoff) { Set-Field 'sha' (Git-Sha) }
if ($Decision) { Add-Item 'decisions' $Decision }
if ($Note) { Add-Item 'notes' $Note }
$toolName = ($lines | Where-Object { $_ -match '^tool:' } | Select-Object -First 1) -replace '^tool:\s*', ''
$phase = ($lines | Where-Object { $_ -match '^phase:' } | Select-Object -First 1) -replace '^phase:\s*', ''
if ($Init) { $Log = if ($Log) { $Log } else { 'state created' } }
if ($Handoff -and -not $Log) { $Log = 'handoff' }
if ($Log) { Add-Item 'log' "$(Get-Date -Format 'yyyy-MM-dd HH:mm') $toolName $phase $Log" }

Set-Content $state $lines -Encoding utf8
"STATE $phase | next: $(($lines | Where-Object { $_ -match '^next:' } | Select-Object -First 1) -replace '^next:\s*', '')"
