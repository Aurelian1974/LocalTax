#Requires -Version 7.0
<#
.SYNOPSIS
  Generates a vertical slice from templates so agents never spend output tokens on boilerplate.
  Prints only created file paths. Never overwrites.
.EXAMPLE
  pwsh scripts/New-Slice.ps1 -RootNamespace Valyan.Erp -Module Invoicing -Feature Invoices -UseCase CancelInvoice -Kind command -Recipe clean-sliced
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RootNamespace,
    [Parameter(Mandatory)] [string] $Module,
    [string] $Feature,
    [Parameter(Mandatory)] [string] $UseCase,
    [Parameter(Mandatory)] [ValidateSet('command', 'query', 'consumer')] [string] $Kind,
    [Parameter(Mandatory)] [ValidateSet('clean-sliced', 'sliced-domain', 'pure-slices', 'hexagonal-integration')] [string] $Recipe,
    [ValidateSet('dapper', 'ef')] [string] $ReadAccess = 'dapper',
    [ValidateSet('slice', 'host')] [string] $EndpointPlacement = 'slice',
    [string] $Event,
    [string] $Route,
    [string] $Policy,
    [string] $SrcRoot = 'src/Modules',
    [string] $RepoRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'

function ConvertTo-Kebab([string] $s) { ($s -creplace '(?<!^)([A-Z])', '-$1').ToLowerInvariant() }

if ($Recipe -ne 'hexagonal-integration' -and -not $Feature) { throw "-Feature is required for recipe $Recipe." }
if ($Kind -eq 'consumer' -and -not $Event) { throw "-Event is required for Kind consumer." }
if ($Kind -eq 'consumer' -and $Recipe -eq 'pure-slices') { $shape = 'multi' } else { $shape = if ($Recipe -eq 'pure-slices') { 'single' } else { 'multi' } }

$project = "$RootNamespace.Modules.$Module"
switch ($Recipe) {
    'clean-sliced'          { $dir = "$SrcRoot/$Module/$project.Application/Features/$Feature/$UseCase"; $ns = "$project.Application.Features.$Feature.$UseCase"; $dbctx = "I${Module}DbContext" }
    'sliced-domain'         { $dir = "$SrcRoot/$Module/$project/Features/$Feature/$UseCase";              $ns = "$project.Features.$Feature.$UseCase";             $dbctx = "${Module}DbContext" }
    'hexagonal-integration' { $dir = "$SrcRoot/$Module/$project/Features/$UseCase";                       $ns = "$project.Features.$UseCase";                      $dbctx = "${Module}DbContext" }
    'pure-slices'           {
        if ($shape -eq 'single') { $dir = "$SrcRoot/$Module/$project/Features/$Feature"; $ns = "$project.Features.$Feature" }
        else { $dir = "$SrcRoot/$Module/$project/Features/$Feature/$UseCase"; $ns = "$project.Features.$Feature.$UseCase" }
        $dbctx = "${Module}DbContext"
    }
}

$tokens = [ordered]@{
    '__NS__'      = $ns
    '__ROOT__'    = $RootNamespace
    '__MODULE__'  = $Module
    '__FEATURE__' = $Feature
    '__USECASE__' = $UseCase
    '__ROUTE__'   = if ($Route) { $Route.TrimStart('/') } else { ((@($Feature, $UseCase) | Where-Object { $_ }) | ForEach-Object { ConvertTo-Kebab $_ }) -join '/' }
    '__POLICY__'  = if ($Policy) { $Policy } else { "$Module.$(if ($Kind -eq 'query') { 'Read' } else { 'Write' })" }
    '__DBCTX__'   = $dbctx
    '__EVENT__'   = $Event
}

$templateRoot = Join-Path $RepoRoot '.claude/skills/feature-scaffold/assets/templates'
$templates = if ($shape -eq 'single') {
    @(Get-Item (Join-Path $templateRoot "single/$Kind.cs.tmpl"))
} else {
    Get-ChildItem (Join-Path $templateRoot "multi/$Kind") -Filter '*.tmpl' | Where-Object {
        -not ($_.Name -like '*Handler.dapper.cs.tmpl' -and $ReadAccess -ne 'dapper') -and
        -not ($_.Name -like '*Handler.ef.cs.tmpl' -and $ReadAccess -ne 'ef') -and
        -not ($_.Name -like '*Endpoint.cs.tmpl' -and $EndpointPlacement -eq 'host')
    }
}

$targetDir = Join-Path $RepoRoot $dir
$planned = foreach ($t in $templates) {
    $name = if ($shape -eq 'single') { "$UseCase.cs" } else { $t.Name -replace '\.tmpl$', '' -replace '\.(dapper|ef)\.cs$', '.cs' -replace '__USECASE__', $UseCase }
    [pscustomobject]@{ Template = $t.FullName; Path = Join-Path $targetDir $name }
}
$existing = $planned | Where-Object { Test-Path $_.Path }
if ($existing) { throw "Refusing to overwrite: $(($existing.Path | ForEach-Object { [IO.Path]::GetRelativePath($RepoRoot, $_) }) -join ', ')" }

New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
foreach ($p in $planned) {
    $content = Get-Content $p.Template -Raw
    foreach ($k in $tokens.Keys) { $content = $content.Replace($k, [string]$tokens[$k]) }
    Set-Content -Path $p.Path -Value $content -NoNewline -Encoding utf8
    [IO.Path]::GetRelativePath($RepoRoot, $p.Path).Replace('\', '/')
}
if ($EndpointPlacement -eq 'host' -and $Kind -ne 'consumer') { "NOTE endpoint not generated (endpoint_placement: host) — map $UseCase in the host per HOST rule." }
