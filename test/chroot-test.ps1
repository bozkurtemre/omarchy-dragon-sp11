<#
.SYNOPSIS
  Test the staged sp11-lcd payload inside the official ISO's target root image.

.DESCRIPTION
  Run after build-iso.ps1 (which downloads the ISO and stages the payload):
    powershell -ExecutionPolicy Bypass -File .\test\chroot-test.ps1
  Needs a privileged container for the loop and overlay mounts; the image itself is never modified.
#>
param(
  [string] $Version = '4.5.0',
  [string] $WorkDir = (Join-Path $env:USERPROFILE 'sp11-omarchy-build')
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
docker run --rm --privileged --env "OMARCHY_VERSION=$Version" `
  -v "$(Join-Path $WorkDir 'dl'):/in:ro" -v "$(Join-Path $WorkDir 'payload'):/payload:ro" `
  -v "$(Join-Path $repo 'build'):/build:ro" -v "$(Join-Path $repo 'test'):/test:ro" `
  -v sp11work:/work sp11-remaster bash /test/chroot-test.sh
if ($LASTEXITCODE -ne 0) { throw 'chroot test failed' }
