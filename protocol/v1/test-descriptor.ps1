#Requires -Version 7.5

$ErrorActionPreference = 'Stop'
$schemaPath = Join-Path $PSScriptRoot 'device.schema.json'
$fixturePath = Join-Path $PSScriptRoot 'examples/bench-controller.json'
$fixture = Get-Content -Raw -LiteralPath $fixturePath

if (-not (Test-Json -Json $fixture -SchemaFile $schemaPath)) {
    throw 'The bench descriptor fixture must be accepted.'
}
Write-Output 'PASS valid bench descriptor'

$invalidCases = @(
    @{ Name = 'wrong protocol'; Change = { param($d) $d.protocol = 'eso-iot' } }
    @{ Name = 'unsupported version'; Change = { param($d) $d.version = 2 } }
    @{ Name = 'invalid device ID'; Change = { param($d) $d.deviceId = '192.168.1.2' } }
    @{ Name = 'credential in descriptor'; Change = { param($d) $d.token = 'placeholder' } }
    @{ Name = 'unexpected command path'; Change = { param($d) $d.capabilities[0].path = '/led/on' } }
    @{ Name = 'zero range step'; Change = { param($d) $d.capabilities[2].step = 0 } }
    @{ Name = 'unsupported capability kind'; Change = { param($d) $d.capabilities[7].type = 'typo' } }
    @{ Name = 'duplicate motion direction'; Change = { param($d) $d.capabilities[6].directions = @('forward', 'forward') } }
    @{ Name = 'excessive motion duration'; Change = { param($d) $d.capabilities[6].maxDurationMs = 5000 } }
)

foreach ($case in $invalidCases) {
    $descriptor = ConvertFrom-Json -InputObject $fixture -AsHashtable
    & $case.Change $descriptor
    $invalidJson = ConvertTo-Json -InputObject $descriptor -Depth 10
    if (Test-Json -Json $invalidJson -SchemaFile $schemaPath -ErrorAction SilentlyContinue) {
        throw "Unexpected acceptance of $($case.Name)."
    }
    Write-Output "PASS rejected $($case.Name)"
}
