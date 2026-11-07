# Compute systemd-stub CHIDs for this machine and match them against a systemd hwids JSON.
# Mirrors systemd src/fundamental/chid.c + src/boot/chid.c: the stub populates only
# manufacturer/family/product/sku/baseboard/EDID-panel and matches in a fixed priority.
#
# Example (shows which device tree systemd-stub would pick for this Surface):
#   curl.exe -sLo denali.json https://raw.githubusercontent.com/systemd/systemd/main/src/boot/hwids/aa64/x1e80100-microsoft-denali.json
#   .\tools\sp11-chid.ps1 -HwidsJson .\denali.json -Panel LGD077B
# -Panel is the internal panel's EDID ID (Device Manager > Monitors, or HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY).
param([Parameter(Mandatory)] [string] $HwidsJson, [string] $Panel)

$bios = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS'
$f = @{
  manufacturer    = $bios.SystemManufacturer.Trim()
  family          = $bios.SystemFamily.Trim()
  product_name    = $bios.SystemProductName.Trim()
  product_sku     = $bios.SystemSKU.Trim()
  bb_manufacturer = $bios.BaseBoardManufacturer.Trim()
  bb_product      = $bios.BaseBoardProduct.Trim()
  panel           = $Panel
}
$table = [ordered]@{
  'x2' = 'manufacturer', 'product_sku', 'panel'
  'x1' = 'manufacturer', 'family', 'panel'
  'x0' = 'manufacturer', 'family', 'product_name', 'panel'
  '3'  = 'manufacturer', 'family', 'product_name', 'product_sku', 'bb_manufacturer', 'bb_product'
  '6'  = 'manufacturer', 'product_sku', 'bb_manufacturer', 'bb_product'
  '8'  = 'manufacturer', 'product_name', 'bb_manufacturer', 'bb_product'
  '10' = 'manufacturer', 'family', 'bb_manufacturer', 'bb_product'
  '4'  = 'manufacturer', 'family', 'product_name', 'product_sku'
  '5'  = 'manufacturer', 'family', 'product_name'
  '7'  = 'manufacturer', 'product_sku'
  '9'  = 'manufacturer', 'product_name'
  '11' = 'manufacturer', 'family'
}
$ns = [byte[]](0x70,0xff,0xd8,0x12,0x4c,0x7f,0x4c,0x7d,0,0,0,0,0,0,0,0)
$sha = [Security.Cryptography.SHA1]::Create()
$hw = Get-Content $HwidsJson -Raw | ConvertFrom-Json
$winner = $null
foreach ($kind in $table.Keys) {
  $names = $table[$kind]
  if ($names -contains 'panel' -and -not $Panel) { continue }
  $data = [Text.Encoding]::Unicode.GetBytes((($names | ForEach-Object { $f[$_] }) -join '&'))
  $h = $sha.ComputeHash([byte[]]($ns + $data))[0..15]
  $h[6] = ($h[6] -band 0x0f) -bor 0x50; $h[8] = ($h[8] -band 0x3f) -bor 0x80
  $hex = -join ($h | ForEach-Object { $_.ToString('x2') })
  $guid = '{0}-{1}-{2}-{3}-{4}' -f $hex.Substring(0,8), $hex.Substring(8,4), $hex.Substring(12,4), $hex.Substring(16,4), $hex.Substring(20,12)
  $hit = $hw.hwids -contains $guid
  if ($hit -and -not $winner) { $winner = $kind }
  '{0,4}: {1} {2}' -f $kind, $guid, $(if ($hit) { "MATCH -> $($hw.compatible)" } else { '' })
}
if ($winner) { "systemd-stub picks $($hw.compatible) via CHID $winner" } else { "No CHID matches $($hw.compatible)" }
