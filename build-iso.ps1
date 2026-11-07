<#
.SYNOPSIS
  Build the Omarchy aarch64 ISO for the Surface Pro 11 LCD (Snapdragon X Plus).

.DESCRIPTION
  Run on Windows on the Surface Pro 11 itself (Docker Desktop must be running):
    powershell -ExecutionPolicy Bypass -File .\build-iso.ps1

  1. Downloads the official Omarchy ISO, its .sha256 and .sig (once).
  2. Stages sp11-lcd/: the post-install scripts, plus this machine's signed
     DSP and GPU firmware copied from the Windows driver store. The firmware is
     Microsoft/Qualcomm's and is only for this device: it goes onto the ISO,
     never into the git repository.
  3. Remasters the ISO in an arm64 Linux container (build/remaster.sh), which
     verifies the official ISO's checksum and signature first.

  Large files live in -WorkDir (default %USERPROFILE%\sp11-omarchy-build), outside OneDrive.
#>
param(
  [string] $Version = '4.5.0',
  [string] $WorkDir = (Join-Path $env:USERPROFILE 'sp11-omarchy-build')
)
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$dl = Join-Path $WorkDir 'dl'
$payloadRoot = Join-Path $WorkDir 'payload'
$stage = Join-Path $payloadRoot 'sp11-lcd'
$out = Join-Path $WorkDir 'out'
New-Item -ItemType Directory -Force $dl, $out | Out-Null

Write-Host "==> Official Omarchy $Version aarch64 ISO"
$iso = "omarchy-$Version-aarch64.iso"
foreach ($file in "$iso.sha256", "$iso.sig", $iso) {
  $target = Join-Path $dl $file
  $url = "https://iso.omarchy.org/$file"
  if (Test-Path $target) {
    $remote = [int64](& curl.exe -sIL -o NUL -w '%header{content-length}' $url)
    if ((Get-Item $target).Length -eq $remote) { continue }
    & curl.exe -fL -C - --retry 5 -o $target $url   # resume a partial download
  } else {
    & curl.exe -fL --retry 5 -o $target $url
  }
  if ($LASTEXITCODE -ne 0) { throw "download of $file failed" }
}

Write-Host "==> Staging sp11-lcd (scripts + this machine's firmware)"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item (Join-Path $repo 'payload\sp11-lcd\*') $stage -Recurse
Copy-Item (Join-Path $repo 'build\uki-dtb.py') $stage

# The files the Surface Pro 11 device tree names (firmware-name), under their
# Windows names, with each driver package's INF so qcom-firmware-extract can
# rank versions the way Windows does.
$wanted = @{
  'surfacepro_ext_adsp8380.inf_*' = 'qcadsp8380.mbn', 'adsp_dtbs.elf'
  'qcnspmcdm_ext_cdsp8380.inf_*'  = 'qccdsp8380.mbn', 'cdsp_dtbs.elf'
  'qcdx8380.inf_*'                = @('qcdxkmsuc8380.mbn')
}
$store = 'C:\Windows\System32\DriverStore\FileRepository'
$found = @{}
foreach ($pattern in $wanted.Keys) {
  foreach ($package in Get-ChildItem $store -Directory -Filter $pattern) {
    $dest = Join-Path $stage "firmware\$($package.Name)"
    foreach ($name in @($wanted[$pattern]) + @((Get-ChildItem $package.FullName -Filter *.inf).Name)) {
      $source = Join-Path $package.FullName $name
      if (Test-Path $source) {
        New-Item -ItemType Directory -Force $dest | Out-Null
        Copy-Item $source $dest
        $found[$name] = $true
      }
    }
  }
}
$missing = $wanted.Values | ForEach-Object { $_ } | Where-Object { -not $found[$_] }
if ($missing) { throw "not in the Windows driver store: $($missing -join ', ')" }
Get-ChildItem (Join-Path $stage 'firmware') -Recurse -File |
  ForEach-Object { '  {0}  {1}' -f (Get-FileHash $_.FullName).Hash.Substring(0, 16).ToLower(), $_.FullName.Substring($stage.Length + 1) }

Write-Host "==> Building the toolbox image"
docker build -q -t sp11-remaster (Join-Path $repo 'build') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'docker build failed (is Docker Desktop running?)' }
docker volume create sp11work | Out-Null

Write-Host "==> Remastering"
docker run --rm --env "OMARCHY_VERSION=$Version" `
  -v "${dl}:/in:ro" -v "${payloadRoot}:/payload:ro" -v "$(Join-Path $repo 'build'):/build:ro" `
  -v "${out}:/out" -v sp11work:/work sp11-remaster bash /build/remaster.sh
if ($LASTEXITCODE -ne 0) { throw 'remaster failed' }
Write-Host "`nISO: $(Join-Path $out "omarchy-$Version-aarch64-sp11-lcd.iso")"
