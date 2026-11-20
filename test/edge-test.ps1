<#
.SYNOPSIS
  Test an ISO built by build-iso.ps1 against the Omarchy edge ISO it was built from.

.DESCRIPTION
  Run after build-iso.ps1, with Docker Desktop running:
    powershell -ExecutionPolicy Bypass -File .\test\edge-test.ps1 -BaseIso <edge ISO> -Iso <result>
  -Iso defaults to the newest *-sp11-lcd*.iso in -WorkDir\out. The test (test/edge-test.sh) runs in a
  privileged Arch Linux ARM container for its loop and overlay mounts; neither ISO nor the target
  root image is modified. Scratch space, including the unpacked root image (about 7 GB), is in
  the sp11work Docker volume.
#>
param(
  [Parameter(Mandatory)] [string] $BaseIso,
  [string] $Iso,
  [string] $WorkDir = (Join-Path $env:USERPROFILE 'sp11-omarchy-build')
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $Iso) {
  $Iso = (Get-ChildItem (Join-Path $WorkDir 'out') -Filter '*-sp11-lcd*.iso' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
  if (-not $Iso) { throw "no *-sp11-lcd*.iso in $(Join-Path $WorkDir 'out'); run build-iso.ps1 first" }
}
$base = (Resolve-Path -LiteralPath $BaseIso).Path
$result = (Resolve-Path -LiteralPath $Iso).Path
docker build -q -t sp11-edge-verify (Join-Path $repo 'build\edge') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'docker build failed (is Docker Desktop running?)' }
docker run --rm --privileged `
  -v "$(Split-Path -Parent $base):/base:ro" -v "$(Split-Path -Parent $result):/result:ro" `
  -v "${repo}:/repo:ro" -v sp11work:/work sp11-edge-verify `
  bash /repo/test/edge-test.sh "/base/$(Split-Path -Leaf $base)" "/result/$(Split-Path -Leaf $result)"
if ($LASTEXITCODE -ne 0) { throw 'edge test failed' }
