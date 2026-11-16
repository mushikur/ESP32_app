#Requires -Version 7.5

param(
    [string]$Compiler = 'g++',
    [switch]$FlutterContract
)

$ErrorActionPreference = 'Stop'
$firmware = Split-Path -Parent $PSScriptRoot
$root = Split-Path -Parent $firmware
$source = Join-Path $firmware 'arduino/EspIoT/src'
$build = Join-Path $firmware 'build/host'
[void](New-Item -ItemType Directory -Path $build -Force)
$runner = Join-Path $build 'espiot-protocol-test.exe'

& $Compiler -std=c++14 -Wall -Wextra -Werror "-I$source" `
    (Join-Path $source 'espiot/Wire.cpp') `
    (Join-Path $source 'espiot/Protocol.cpp') `
    (Join-Path $source 'espiot/Pairing.cpp') `
    (Join-Path $PSScriptRoot 'protocol_test.cpp') -o $runner
if ($LASTEXITCODE -ne 0) { throw 'Firmware host compilation failed.' }

& $runner
if ($LASTEXITCODE -ne 0) { throw 'Firmware protocol checks failed.' }

$descriptor = 'descriptor' | & $runner --wire
if ($LASTEXITCODE -ne 0 -or !(Test-Json -Json $descriptor -SchemaFile (Join-Path $root 'protocol/v1/device.schema.json'))) {
    throw 'The SDK descriptor failed the shared v1 schema.'
}
'PASS generated descriptor matches the shared v1 schema'

if ($FlutterContract) {
    Push-Location (Join-Path $root 'app')
    try {
        & flutter --no-version-check --suppress-analytics test --no-pub `
            (Join-Path $PSScriptRoot 'firmware_contract_test.dart') "--dart-define=ESP_IOT_FIRMWARE_RUNNER=$runner"
        if ($LASTEXITCODE -ne 0) { throw 'The Android firmware contract test failed.' }
    } finally {
        Pop-Location
    }
}
