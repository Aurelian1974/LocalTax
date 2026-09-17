#Requires -Version 7.0
<#
.SYNOPSIS
  Generates tool-specific AI customization files from the canonical sources in .ai/kit and validates skills.
  Sources (edit these):  .ai/kit/core*.md · .ai/kit/roles/*.json|*.md · .ai/kit/rules/*.md · .claude/skills/** (shared, not generated)
  Outputs (never edit):  .github/copilot-instructions.md · CLAUDE.md · .github/agents/*.agent.md · .claude/agents/claude-*.md
                         .claude/rules/*.md (single copy read by both: `paths` for Claude Code, `applyTo` for VS Code)
.PARAMETER Check
  Do not write. Exit 1 if any output is missing, stale, or orphaned, or validation fails. Use in CI / pre-commit.
#>
[CmdletBinding()]
param([switch] $Check, [string] $RepoRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$Marker = '<!-- GENERATED from .ai/kit by scripts/Build-AiKit.ps1 — edit the sources, not this file -->'
$Kit = Join-Path $RepoRoot '.ai/kit'
$SkillsRoot = Join-Path $RepoRoot '.claude/skills'
$errors = [System.Collections.Generic.List[string]]::new()

function Q([string] $s) { ConvertTo-Json $s }                       # JSON string literal = valid YAML scalar
function Read-Text([string] $p) { (Get-Content $p -Raw) -replace "`r`n", "`n" }
function List([object[]] $items) { '[' + (($items | ForEach-Object { "'$_'" }) -join ', ') + ']' }
function Split-FrontMatter([string] $text, [string] $file) {
    $m = [regex]::Match($text, '(?s)\A---\n(?<fm>.*?)\n---\n(?<body>.*)\z')
    if (-not $m.Success) { $errors.Add("${file}: missing frontmatter"); return $null }
    $meta = @{}
    foreach ($line in $m.Groups['fm'].Value -split "`n") {
        $kv = [regex]::Match($line, '^(?<k>[\w-]+):\s*(?<v>.*)$')
        if ($kv.Success) { $meta[$kv.Groups['k'].Value] = $kv.Groups['v'].Value.Trim().Trim('"') }
    }
    [pscustomobject]@{ Meta = $meta; Body = $m.Groups['body'].Value.TrimStart("`n") }
}

# ── Skills validation ─────────────────────────────────────────────────────────
$skillNames = @()
foreach ($dir in Get-ChildItem $SkillsRoot -Directory) {
    $file = Join-Path $dir.FullName 'SKILL.md'
    if (-not (Test-Path $file)) { $errors.Add("skill $($dir.Name): missing SKILL.md"); continue }
    $fm = Split-FrontMatter (Read-Text $file) "skill $($dir.Name)"
    if (-not $fm) { continue }
    $n = $fm.Meta['name']; $d = $fm.Meta['description']
    if ($n -ne $dir.Name) { $errors.Add("skill $($dir.Name): name '$n' must equal folder") }
    if ($n -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$' -or $n.Length -gt 64) { $errors.Add("skill $($dir.Name): name must be kebab-case ≤ 64") }
    if (-not $d) { $errors.Add("skill $($dir.Name): empty description") } elseif ($d.Length -gt 1024) { $errors.Add("skill $($dir.Name): description $($d.Length) > 1024") }
    $skillNames += $n
}

# ── Generation ───────────────────────────────────────────────────────────────
$out = [ordered]@{}
$core = Read-Text (Join-Path $Kit 'core.md')
$out['.github/copilot-instructions.md'] = "$Marker`n$core`n$(Read-Text (Join-Path $Kit 'core.copilot.md'))"
$out['CLAUDE.md']                       = "$Marker`n$core`n$(Read-Text (Join-Path $Kit 'core.claude.md'))"

$roles = Get-ChildItem (Join-Path $Kit 'roles') -Filter '*.json' | Sort-Object Name
$roleNames = $roles | ForEach-Object { $_.BaseName }
foreach ($r in $roles) {
    $name = $r.BaseName
    $meta = Get-Content $r.FullName -Raw | ConvertFrom-Json
    $bodyPath = Join-Path $r.DirectoryName "$name.md"
    if (-not (Test-Path $bodyPath)) { $errors.Add("role ${name}: missing $name.md"); continue }
    $body = Read-Text $bodyPath
    $skills = @($meta.skills | Where-Object { $_ })
    foreach ($s in $skills) { if ($s -notin $skillNames) { $errors.Add("role ${name}: unknown skill '$s'") } }

    if ($meta.copilot) {
        $c = $meta.copilot
        $fm = @('---', "name: $name", "description: $(Q $meta.description)")
        if ($c.argumentHint) { $fm += "argument-hint: $(Q $c.argumentHint)" }
        if ($c.tools) { $fm += "tools: $(List $c.tools)" }
        if ($c.agents) {
            foreach ($a in $c.agents) { if ($a -notin $roleNames) { $errors.Add("role ${name}: unknown subagent '$a'") } }
            $fm += "agents: $(List $c.agents)"
        }
        if ($c.PSObject.Properties['userInvocable'] -and -not $c.userInvocable) { $fm += 'user-invocable: false' }
        if ($c.model) { $fm += "model: $(List $c.model)" }
        if ($c.handoffs) {
            $fm += 'handoffs:'
            foreach ($h in $c.handoffs) {
                if ($h.agent -notin $roleNames) { $errors.Add("role ${name}: handoff to unknown agent '$($h.agent)'") }
                $fm += "  - label: $(Q $h.label)", "    agent: $($h.agent)", "    prompt: $(Q $h.prompt)", "    send: $("$($h.send)".ToLower())"
            }
        }
        $fm += '---', $Marker
        $load = if ($skills) { "Read first: " + (($skills | ForEach-Object { "``.claude/skills/$_/SKILL.md``" }) -join ', ') + "`n`n" } else { '' }
        $out[".github/agents/$name.agent.md"] = ($fm -join "`n") + "`n" + $load + $body
    }
    if ($meta.claude) {
        $k = $meta.claude
        $fm = @('---', "name: claude-$name", "description: $(Q $meta.description)")
        if ($k.tools) { $fm += "tools: $($k.tools)" }
        foreach ($p in 'model', 'effort', 'maxTurns', 'permissionMode') { if ($k.$p) { $fm += "${p}: $($k.$p)" } }
        if ($skills) { $fm += 'skills:'; $fm += $skills | ForEach-Object { "  - $_" } }
        $fm += '---', $Marker
        $out[".claude/agents/claude-$name.md"] = ($fm -join "`n") + "`n" + $body
    }
}

foreach ($rule in Get-ChildItem (Join-Path $Kit 'rules') -Filter '*.md' | Sort-Object Name) {
    $fm = Split-FrontMatter (Read-Text $rule.FullName) "rule $($rule.Name)"
    if (-not $fm) { continue }
    $globs = @($fm.Meta['globs'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $globs) { $errors.Add("rule $($rule.Name): globs required") }
    $ruleFm = (@('---', "name: $($fm.Meta['name'])", "description: $(Q $fm.Meta['description'])", "applyTo: $(Q ($globs -join ','))", 'paths:') +
               @($globs | ForEach-Object { "  - $(Q $_)" }) + @('---', $Marker)) -join "`n"
    $out[".claude/rules/$($rule.BaseName).md"] = "$ruleFm`n$($fm.Body)"
}

# ── Compare / write ──────────────────────────────────────────────────────────
$generatedDirs = '.github/agents', '.claude/agents', '.github/instructions', '.claude/rules'
$orphans = foreach ($d in $generatedDirs) {
    $full = Join-Path $RepoRoot $d
    if (Test-Path $full) {
        Get-ChildItem $full -File | Where-Object { (Get-Content $_.FullName -Raw) -match [regex]::Escape($Marker) } |
            ForEach-Object { [IO.Path]::GetRelativePath($RepoRoot, $_.FullName).Replace('\', '/') } | Where-Object { -not $out.Contains($_) }
    }
}
$stale = foreach ($path in $out.Keys) {
    $full = Join-Path $RepoRoot $path
    if (-not (Test-Path $full) -or ((Read-Text $full) -ne $out[$path])) { $path }
}

if ($Check) {
    $stale   | ForEach-Object { $errors.Add("stale or missing: $_") }
    $orphans | ForEach-Object { $errors.Add("orphaned generated file: $_") }
} else {
    foreach ($path in $stale) {
        $full = Join-Path $RepoRoot $path
        New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
        Set-Content -Path $full -Value $out[$path] -NoNewline -Encoding utf8
        "write  $path"
    }
    foreach ($path in $orphans) { Remove-Item (Join-Path $RepoRoot $path); "delete $path" }
}

if ($errors.Count) { $errors | ForEach-Object { "ERROR  $_" }; exit 1 }
"ok     $($out.Count) outputs, $($skillNames.Count) skills$(if ($Check) { ', in sync' })"
