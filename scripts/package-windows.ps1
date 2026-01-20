$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root "dist\windows"

if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Path $dist | Out-Null
New-Item -ItemType Directory -Path (Join-Path $dist "bin") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $dist "extensions") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $dist "services") | Out-Null

Push-Location $root
cargo build --release -p idm-cli -p idm-daemon -p idm-native-host
Pop-Location

Copy-Item (Join-Path $root "target\release\idm-cli.exe") (Join-Path $dist "bin")
Copy-Item (Join-Path $root "target\release\idm-daemon.exe") (Join-Path $dist "bin")
Copy-Item (Join-Path $root "target\release\idm-native-host.exe") (Join-Path $dist "bin")

Copy-Item (Join-Path $root "extensions\chrome") (Join-Path $dist "extensions") -Recurse
Copy-Item (Join-Path $root "extensions\firefox") (Join-Path $dist "extensions") -Recurse
Copy-Item (Join-Path $root "extensions\native-host") (Join-Path $dist "extensions") -Recurse
Copy-Item (Join-Path $root "extensions\install_native_host.sh") (Join-Path $dist "extensions")

Copy-Item (Join-Path $root "README.md") $dist

$zip = Join-Path $root "dist\idm-open-windows.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $dist -DestinationPath $zip

Write-Host "Created $zip"
