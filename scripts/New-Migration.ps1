#Requires -Version 7.0
<#
.SYNOPSIS
  Creates a DbUp migration file from the kit template. Prints only the created path.
.EXAMPLE
  pwsh scripts/New-Migration.ps1 -Schema invoicing -Name add_credit_notes
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory)] [string] $Schema,
    [Parameter(Mandatory)] [string] $Name,
    [string] $RepoRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
$profilePath = Join-Path $RepoRoot '.ai/architecture/profile.yml'
$profileLines = Get-Content $profilePath

if ($Name -cnotmatch '^[a-z0-9]+(_[a-z0-9]+)*$') { throw "-Name must be snake_case (e.g. add_credit_notes)." }

# Map db_schema -> module from the profile
$module = $null; $current = $null; $schemas = @()
foreach ($line in $profileLines) {
    if ($line -match '^\s*-\s*name:\s*(\S+)') { $current = $Matches[1] }
    if ($line -match '^\s*db_schema:\s*(\S+)') {
        $schemas += $Matches[1]
        if ($Matches[1] -eq $Schema) { $module = $current }
    }
}
if (-not $module) { throw "Schema '$Schema' is not a db_schema in profile.yml. Known: $($schemas -join ', ')" }

$pathLine = $profileLines | Where-Object { $_ -match '^\s*migrations_path:\s*(\S+)' } | Select-Object -First 1
$migrationsPath = if ($pathLine -match '^\s*migrations_path:\s*(\S+)') { $Matches[1] } else { 'db/migrations' }
$folder = Join-Path $RepoRoot $migrationsPath
New-Item -ItemType Directory -Force -Path $folder | Out-Null

$file = Join-Path $folder "$(Get-Date -Format 'yyyyMMddHHmmss')_${Schema}_$Name.sql"
if (Test-Path $file) { throw "Exists: $file" }
$content = (Get-Content (Join-Path $RepoRoot '.ai/templates/dotnet/migration.sql.tmpl') -Raw).
    Replace('__NAME__', $Name).Replace('__SCHEMA__', $Schema).Replace('__MODULE__', $module)
Set-Content -Path $file -Value $content -NoNewline -Encoding utf8
[IO.Path]::GetRelativePath($RepoRoot, $file).Replace('\', '/')
