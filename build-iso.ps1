<#
.SYNOPSIS
  Build an Omarchy aarch64 edge ISO for the Surface Pro 11 LCD (Snapdragon X Plus X1P64100).

.DESCRIPTION
  Run on Windows on the Surface Pro 11 itself, with Docker Desktop running:
    powershell -ExecutionPolicy Bypass -File .\build-iso.ps1
    powershell -ExecutionPolicy Bypass -File .\build-iso.ps1 -Iso C:\path\omarchy-2026.11.20-aarch64-edge.iso
    powershell -ExecutionPolicy Bypass -File .\build-iso.ps1 -LcdOnlyUki

  1. Base ISO: Omarchy's official edge nightly named in latest.json, downloaded once and checked
     against the size and SHA256 that latest.json and the .sha256 file give, or the ISO given with
     -Iso (for example one built with build/edge/build-edge-iso.sh). Edge ISOs carry no release
     signature: the checksum proves an intact download, not who built it.
  2. Stages sp11-lcd/: setup.sh and README.md from payload/, plus windows/: every driver package in
     the Windows driver store whose INF names Surface, Qualcomm or Dolby as its provider,
     device-facts.json and a SHA256SUMS manifest. These are Microsoft, Qualcomm and Dolby files
     for this device only: they go onto the ISO, never into the git repository.
  3. Remasters the ISO in a Linux container (build/remaster.sh): adds /sp11-lcd and keeps the
     volume UUID, dates and boot records. -LcdOnlyUki also rebuilds the live UKI with the LCD
     device tree as its only tree, for a Surface whose firmware hides the panel EDID from
     systemd-stub (README, "If the live session has no picture").
  4. Writes <iso>.sha256 and <iso>.provenance.txt next to the result.

  Large files live in -WorkDir (default %USERPROFILE%\sp11-omarchy-build), outside OneDrive.
#>
param(
  [string] $Iso,
  [switch] $LcdOnlyUki,
  [string] $WorkDir = (Join-Path $env:USERPROFILE 'sp11-omarchy-build'),
  [string] $LatestUrl = 'https://nightly.omarchy.org/edge-aarch64/latest.json',
  [int] $MinFreeGB = 8
)
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$dl = Join-Path $WorkDir 'dl'
$payloadRoot = Join-Path $WorkDir 'payload'
$stage = Join-Path $payloadRoot 'sp11-lcd'
$out = Join-Path $WorkDir 'out'
$store = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'
$utf8 = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force $dl, $out | Out-Null

# Text the Linux side reads: UTF-8 without a BOM, LF line endings.
function Write-LinuxText([string] $path, [string[]] $lines) {
  [IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), $utf8)
}

function Get-Sha256([string] $path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }

# The provider an INF names in [Version], with a %token% resolved from [Strings].
function Get-InfProvider([string] $path) {
  $text = Get-Content -LiteralPath $path -Raw
  $sections = @{}
  foreach ($s in [regex]::Split($text, '(?m)^[ \t]*\[')) {
    if ($s -match '^([^\]\r\n]+)\]') {
      $name = $matches[1].Trim().ToLowerInvariant()
      if (-not $sections.ContainsKey($name)) { $sections[$name] = $s }
    }
  }
  if ($sections['version'] -notmatch '(?im)^[ \t]*Provider[ \t]*=[ \t]*([^;\r\n]+)') { return '' }
  $value = $matches[1].Trim().Trim('"')
  if ($value -match '^%([^%]+)%$') {
    $token = [regex]::Escape($matches[1])
    foreach ($name in @('strings') + @($sections.Keys | Where-Object { $_ -like 'strings.*' } | Sort-Object)) {
      if ($sections[$name] -match "(?im)^[ \t]*$token[ \t]*=[ \t]*`"?([^`";\r\n]+)") { return $matches[1].Trim() }
    }
  }
  $value
}

function Assert-FreeSpace([string] $path, [int64] $needed, [string] $what) {
  $drive = Get-PSDrive -Name ((Resolve-Path $path).Path.Substring(0, 1))
  $left = $drive.Free - $needed
  if ($left -lt ([int64]$MinFreeGB * 1GB)) {
    throw ('{0} needs {1:N1} GB on {2}:, which would leave {3:N1} GB free (minimum {4} GB). Free some space first.' -f
      $what, ($needed / 1GB), $drive.Name, ($left / 1GB), $MinFreeGB)
  }
}

# --- 1. Base ISO ------------------------------------------------------------------------------
$source = [ordered]@{}
if ($Iso) {
  $isoPath = (Resolve-Path -LiteralPath $Iso).Path
  Write-Host "==> Base ISO (local): $isoPath"
  $source['base'] = "local file $isoPath"
  $sidecar = "$isoPath.sha256"
  $isoSha = Get-Sha256 $isoPath
  if (Test-Path -LiteralPath $sidecar) {
    $want = ((Get-Content -LiteralPath $sidecar -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
    if ($want -ne $isoSha) { throw "$isoPath has SHA256 $isoSha, but $sidecar says $want" }
    Write-Host "    SHA256 matches $(Split-Path -Leaf $sidecar)"
  }
  $provenance = Join-Path (Split-Path -Parent $isoPath) 'PROVENANCE.txt'
  if (Test-Path -LiteralPath $provenance) { $source['base provenance'] = $provenance }
} else {
  Write-Host "==> Base ISO: Omarchy edge nightly ($LatestUrl)"
  $latest = (& curl.exe -fsSL --retry 3 $LatestUrl | Out-String) | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0 -or -not $latest) { throw "cannot read $LatestUrl" }
  if ($latest.url -notmatch '^https://nightly\.omarchy\.org/[^?#]+\.iso$' -or $latest.sha256 -notmatch '^[0-9a-f]{64}$' -or
      [int64]$latest.size -le 0) {
    throw "unexpected latest.json: url=$($latest.url) sha256=$($latest.sha256) size=$($latest.size)"
  }
  $name = Split-Path -Leaf $latest.url
  $isoPath = Join-Path $dl $name
  $sidecarSha = (((& curl.exe -fsSL --retry 3 "$($latest.url).sha256") | Out-String).Trim() -split '\s+')[0].ToLowerInvariant()
  if ($sidecarSha -ne $latest.sha256) { throw "$name.sha256 says $sidecarSha, latest.json says $($latest.sha256)" }
  foreach ($key in 'version', 'url', 'sha256', 'size', 'built_at', 'iso_commit', 'omarchy_version', 'omarchy_commit', 'kernel') {
    $source["latest.json $key"] = $latest.$key
  }
  $have = if (Test-Path -LiteralPath $isoPath) { (Get-Item -LiteralPath $isoPath).Length } else { 0 }
  if ($have -ne [int64]$latest.size) {
    Assert-FreeSpace $dl ([int64]$latest.size - $have) "Downloading $name"
    Write-Host "    downloading $name ($([math]::Round([int64]$latest.size / 1GB, 2)) GB)"
    & curl.exe -fL --retry 5 -C - -o $isoPath $latest.url   # resumes a partial download
    if ($LASTEXITCODE -ne 0) { throw "download of $($latest.url) failed" }
  }
  if ((Get-Item -LiteralPath $isoPath).Length -ne [int64]$latest.size) { throw "$isoPath does not have the size latest.json gives ($($latest.size))" }
  $isoSha = Get-Sha256 $isoPath
  if ($isoSha -ne $latest.sha256) {
    Remove-Item -LiteralPath $isoPath
    throw "$name has SHA256 $isoSha, latest.json says $($latest.sha256); deleted it, run again to download it anew"
  }
  Write-Host "    size and SHA256 match latest.json (no release signature exists for edge ISOs)"
}
$isoSize = (Get-Item -LiteralPath $isoPath).Length
$source['base sha256'] = $isoSha
$source['base size'] = $isoSize
$isoName = Split-Path -Leaf $isoPath
$outName = ($isoName -replace '\.iso$', '') + $(if ($LcdOnlyUki) { '-sp11-lcd-fallback.iso' } else { '-sp11-lcd.iso' })
$outPath = Join-Path $out $outName

# --- 2. sp11-lcd/: the setup script and this machine's Windows driver archive -----------------
Write-Host "==> Selecting this machine's Surface, Qualcomm and Dolby driver packages"
$packages = foreach ($dir in Get-ChildItem -LiteralPath $store -Directory) {
  $inf = Join-Path $dir.FullName ($dir.Name -replace '_(arm64|amd64|x86)_[0-9a-f]{16}$', '')
  if (-not (Test-Path -LiteralPath $inf)) { continue }
  $provider = Get-InfProvider $inf
  if ($provider -notmatch '^(Microsoft )?Surface|^Qualcomm|^Dolby') { continue }
  $files = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File)
  $driverVer = ''
  if ((Get-Content -LiteralPath $inf -Raw) -match '(?im)^[ \t]*DriverVer[ \t]*=[ \t]*([^;\r\n]+)') { $driverVer = $matches[1].Trim() }
  [pscustomobject]@{ Dir = $dir; Provider = $provider; DriverVer = $driverVer; Files = $files.Count
    Bytes = [int64](($files | Measure-Object Length -Sum).Sum) }
}
$archiveBytes = [int64](($packages | Measure-Object Bytes -Sum).Sum)
$archiveFiles = [int](($packages | Measure-Object Files -Sum).Sum)
'    {0} packages, {1} files, {2:N1} MB' -f @($packages).Count, $archiveFiles, ($archiveBytes / 1MB) | Write-Host
foreach ($required in 'surfacepro_snscfgcrd8380.inf_*', 'dax3_ext_qc.inf_*') {
  if (-not ($packages | Where-Object { $_.Dir.Name -like $required })) { throw "no $required package in $store" }
}

if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path -LiteralPath $outPath) { Remove-Item -LiteralPath $outPath -Force }
Assert-FreeSpace $WorkDir ($archiveBytes + $isoSize + $archiveBytes + 512MB) 'Staging the archive and writing the ISO'

Write-Host "==> Staging sp11-lcd"
$windows = Join-Path $stage 'windows'
$repoDir = Join-Path $windows 'FileRepository'
New-Item -ItemType Directory -Force $repoDir | Out-Null
Copy-Item -Path (Join-Path $repo 'payload\sp11-lcd\*') -Destination $stage -Recurse
foreach ($p in $packages) {
  Copy-Item -LiteralPath $p.Dir.FullName -Destination (Join-Path $repoDir $p.Dir.Name) -Recurse
}
$staged = @(Get-ChildItem -LiteralPath $repoDir -Recurse -File)
if ($staged.Count -ne $archiveFiles) { throw "copied $($staged.Count) files from the driver store, expected $archiveFiles" }

Write-Host "==> Recording device facts (no secrets: no recovery key, product key, serial number or account data)"
$bios = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS'
$cpu = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0'
$os = Get-CimInstance Win32_OperatingSystem
$smbios = Get-CimInstance Win32_BIOS
$present = @(Get-PnpDevice -PresentOnly)

# The internal panel: the monitor Windows reports on an internal connection (0x80000000). Its
# EDID ID as systemd computes it: the PNP vendor and the product code as four lowercase hex digits.
$panel = [ordered]@{}
try {
  $internal = Get-CimInstance -Namespace root\wmi WmiMonitorConnectionParams |
    Where-Object { [uint64]$_.VideoOutputTechnology -eq 2147483648 } | Select-Object -First 1
  $monitor = Get-CimInstance -Namespace root\wmi WmiMonitorID | Where-Object InstanceName -eq $internal.InstanceName
  $vendor = -join ($monitor.ManufacturerName | Where-Object { $_ } | ForEach-Object { [char]$_ })
  $product = -join ($monitor.ProductCodeID | Where-Object { $_ } | ForEach-Object { [char]$_ })
  $instance = $internal.InstanceName -replace '_0$', ''
  $edid = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Enum\$instance\Device Parameters" -Name EDID).EDID
  $m = ([int]$edid[8] -shl 8) -bor [int]$edid[9]
  $edidVendor = -join ([char](64 + (($m -shr 10) -band 31)), [char](64 + (($m -shr 5) -band 31)), [char](64 + ($m -band 31)))
  $edidProduct = [int]$edid[10] -bor ([int]$edid[11] -shl 8)
  $edidId = '{0}{1:x4}' -f $edidVendor, $edidProduct
  if ($edidId.ToUpperInvariant() -ne "$vendor$product".ToUpperInvariant()) { throw "EDID says $edidId, WmiMonitorID says $vendor$product" }
  $panel = [ordered]@{ edid_panel_id = $edidId; pnp_id = "$vendor$product"; connection = 'internal (0x80000000)'; instance = $instance }
} catch {
  $panel = [ordered]@{ error = "not readable: $($_.Exception.Message)" }
}

$wifiDev = $present | Where-Object { $_.Class -eq 'Net' -and $_.InstanceId -like 'PCI\VEN_17CB*' } | Select-Object -First 1
# The card's own address: Windows' extra Wi-Fi Direct adapters on the same device have locally
# administered ones.
$wifiNic = Get-NetAdapter -Physical | Where-Object { $_.PnPDeviceID -eq $wifiDev.InstanceId -and $_.PermanentAddress -and
  (([Convert]::ToInt32($_.PermanentAddress.Substring(0, 2), 16) -band 2) -eq 0) } | Select-Object -First 1
$btRadio = $present | Where-Object { $_.Class -eq 'Bluetooth' -and $_.InstanceId -like 'QCA_SHB\*' } | Select-Object -First 1
$btAddr = $null
if ($btRadio) {
  # DEVPKEY_Bluetooth_RadioAddress
  $btAddr = (Get-PnpDeviceProperty -InstanceId $btRadio.InstanceId -KeyName '{A92F26CA-EDA7-4B1D-9DB2-27B68AA5A2EB} 1' -ErrorAction SilentlyContinue).Data
}
function Format-Mac([uint64] $value) { (0..5 | ForEach-Object { '{0:X2}' -f (($value -shr (8 * (5 - $_))) -band 0xFF) }) -join ':' }
$wifiPermanent = if ($wifiNic) { [Convert]::ToUInt64($wifiNic.PermanentAddress, 16) } else { $null }
$addresses = [ordered]@{
  wifi_permanent = if ($null -ne $wifiPermanent) { Format-Mac $wifiPermanent } else { $null }
  wifi_current = if ($wifiNic) { $wifiNic.MacAddress -replace '-', ':' } else { $null }
  bluetooth_radio = if ($btAddr) { Format-Mac ([uint64]$btAddr) } else { $null }
  mac_address_emulation_address = 'not read: the UEFI variable needs administrator rights on Windows'
}
# microsoft-surface-snapdragon-addresses: Wi-Fi = MacAddressEmulationAddress - 2, Bluetooth = - 1.
if ($null -ne $wifiPermanent -and $btAddr -and ([uint64]$btAddr - $wifiPermanent) -eq 1) {
  $addresses['mac_address_emulation_address_derived'] = Format-Mac ($wifiPermanent + 2)
  $addresses['derivation'] = 'Wi-Fi + 2 = Bluetooth + 1, the layout microsoft-surface-snapdragon-addresses reads from the variable'
}

$audio = $present | Where-Object { $_.InstanceId -like 'AUCD\*' } | Select-Object -First 1
$audioId = if ($audio) { ($audio.InstanceId -split '\\')[1] } else { $null }
$tuning = $null
if ($audioId -match 'DEV_([0-9A-F]{4})&SUBSYS_(\w+)&REV_(\w+)') {
  $xmlName = 'AUCD_DEV_{0}_SUBSYS_{1}_REV_{2}_ADCM_SUBSYS_{1}.xml' -f $matches[1], $matches[2], $matches[3]
  $tuning = Get-ChildItem -LiteralPath $repoDir -Recurse -File -Filter $xmlName | Select-Object -First 1
}

$facts = [ordered]@{
  generated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  generator = 'omarchy-dragon-sp11 build-iso.ps1'
  windows = [ordered]@{ caption = $os.Caption; version = $os.Version; build = $os.BuildNumber }
  smbios = [ordered]@{
    manufacturer = $bios.SystemManufacturer; family = $bios.SystemFamily; product_name = $bios.SystemProductName
    product_sku = $bios.SystemSKU; system_version = $bios.SystemVersion; baseboard_manufacturer = $bios.BaseBoardManufacturer
    baseboard_product = $bios.BaseBoardProduct; bios_vendor = $bios.BIOSVendor; bios_version = $bios.BIOSVersion
    bios_release_date = $bios.BIOSReleaseDate; smbios_version = '{0}.{1}' -f $smbios.SMBIOSMajorVersion, $smbios.SMBIOSMinorVersion
  }
  firmware = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object DeviceClass -eq 'FIRMWARE' | Sort-Object DeviceName |
    ForEach-Object { [ordered]@{ name = $_.DeviceName; version = $_.DriverVersion; hardware_id = $_.HardWareID } })
  soc = [ordered]@{ name = $cpu.ProcessorNameString.Trim(); identifier = $cpu.Identifier; vendor = $cpu.VendorIdentifier }
  panel = $panel
  wifi = [ordered]@{ device = if ($wifiDev) { $wifiDev.FriendlyName } else { $null }; instance_id = if ($wifiDev) { $wifiDev.InstanceId } else { $null } }
  bluetooth = [ordered]@{ device = if ($btRadio) { $btRadio.FriendlyName } else { $null }; instance_id = if ($btRadio) { $btRadio.InstanceId } else { $null } }
  addresses = $addresses
  audio = [ordered]@{ instance_id = if ($audio) { $audio.InstanceId } else { $null }
    dolby_tuning_xml = if ($tuning) { 'FileRepository/' + $tuning.FullName.Substring($repoDir.Length + 1).Replace('\', '/') } else { $null } }
  integrated_devices = @($present | Where-Object { $_.InstanceId -match '^(ACPI|PCI|AUCD|QCA_SHB|UEFI)\\' -or $_.InstanceId -like 'HID\VEN_MSHW*' } |
    Sort-Object InstanceId | ForEach-Object { [ordered]@{ class = $_.Class; name = $_.FriendlyName; instance_id = $_.InstanceId } })
  archive = [ordered]@{
    selection = 'driver store packages whose INF provider is Surface, Qualcomm or Dolby'
    source = $store; packages = @($packages).Count; files = $archiveFiles; bytes = $archiveBytes
    list = @($packages | Sort-Object { $_.Dir.Name } | ForEach-Object {
      [ordered]@{ name = $_.Dir.Name; provider = $_.Provider; driver_ver = $_.DriverVer; files = $_.Files; bytes = $_.Bytes } })
  }
}
Write-LinuxText (Join-Path $windows 'device-facts.json') ((ConvertTo-Json $facts -Depth 6) -split "`r?`n")
'    panel {0}, Wi-Fi {1}, Bluetooth {2}, audio {3}' -f $panel['edid_panel_id'], $addresses['wifi_permanent'], $addresses['bluetooth_radio'], $audioId | Write-Host

Write-Host "==> Writing windows/SHA256SUMS"
$sums = foreach ($file in Get-ChildItem -LiteralPath $windows -Recurse -File | Sort-Object FullName) {
  '{0}  {1}' -f (Get-Sha256 $file.FullName), $file.FullName.Substring($windows.Length + 1).Replace('\', '/')
}
Write-LinuxText (Join-Path $windows 'SHA256SUMS') $sums
'    {0} files' -f @($sums).Count | Write-Host

# --- 3. Remaster -----------------------------------------------------------------------------
Write-Host "==> Building the toolbox image"
docker build -q -t sp11-remaster (Join-Path $repo 'build') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'docker build failed (is Docker Desktop running?)' }
docker volume create sp11work | Out-Null

$prov = "$outPath.provenance.txt"
$commit = (& git -C $repo rev-parse HEAD 2>$null)
if ($commit) { if (& git -C $repo status --porcelain 2>$null) { $commit += ' (uncommitted changes)' } } else { $commit = 'unknown' }
$header = @(
  "$outName",
  "built      $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')) by omarchy-dragon-sp11 build-iso.ps1, commit $commit",
  "live UKI   $(if ($LcdOnlyUki) { 'rebuilt with only the LCD device tree (-LcdOnlyUki)' } else { "Omarchy's own, unchanged" })",
  "archive    windows/: $(@($packages).Count) driver packages, $archiveFiles files, $archiveBytes bytes",
  "signature  none: Omarchy publishes no signature for edge ISOs, and this remaster is unsigned too"
)
$header += $source.Keys | ForEach-Object { '{0,-24} {1}' -f $_, $source[$_] }
Write-LinuxText $prov $header

Write-Host "==> Remastering $isoName"
$isoDir = Split-Path -Parent $isoPath
docker run --rm --env "BASE_ISO=$isoName" --env "OUT_ISO=$outName" --env "LCD_ONLY_UKI=$([int][bool]$LcdOnlyUki)" `
  -v "${isoDir}:/in:ro" -v "${payloadRoot}:/payload:ro" -v "$(Join-Path $repo 'build'):/build:ro" `
  -v "${out}:/out" -v sp11work:/work sp11-remaster bash /build/remaster.sh
if ($LASTEXITCODE -ne 0) { throw 'remaster failed' }
Write-Host "`nISO:        $outPath`nProvenance: $prov"
