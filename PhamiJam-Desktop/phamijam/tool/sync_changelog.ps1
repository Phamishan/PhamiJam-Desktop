# Copies the repo's top-level README.md over assets/CHANGELOG.md so the
# in-app changelog dialog reflects the latest Version History section.
# Run this after editing README.md, or let CI run it before each build.

$projectRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $projectRoot)
$readme = Join-Path $repoRoot 'README.md'
$changelog = Join-Path $projectRoot 'assets\CHANGELOG.md'

Copy-Item -Path $readme -Destination $changelog -Force
Write-Host "Synced $readme -> $changelog"
