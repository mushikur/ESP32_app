#Requires -Version 7.5
param([string]$ArduinoCli = 'arduino-cli')

$ErrorActionPreference = 'Stop'
$firmware = Split-Path -Parent $PSScriptRoot
$root = Split-Path -Parent $firmware
$assets = Join-Path $root 'app/assets/learn'
$output = Join-Path $firmware 'build/learn'

$sketches = @(Get-ChildItem -LiteralPath (Join-Path $assets 'sketches') -Filter '*.ino' -File)
if ($sketches.Count -eq 0) { throw 'No learning sketches were found.' }
foreach ($sketch in $sketches) {
    $folder = Join-Path $output "sketches/$($sketch.BaseName)"
    $build = Join-Path $output "compiled/$($sketch.BaseName)"
    [void](New-Item -ItemType Directory -Path $folder -Force)
    Copy-Item -LiteralPath $sketch.FullName -Destination (Join-Path $folder $sketch.Name)
    & $ArduinoCli compile --fqbn 'esp32:esp32:esp32' --build-path $build $folder
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed for $($sketch.Name)." }
    "PASS $($sketch.Name)"
}
