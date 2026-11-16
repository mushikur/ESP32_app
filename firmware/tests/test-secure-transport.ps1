#Requires -Version 7.5
param([string]$OpenSsl = 'openssl')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$folder = Join-Path $root "firmware/build/tls-$([guid]::NewGuid().ToString('N'))"
[void](New-Item -ItemType Directory -Path $folder -Force)
$cert = Join-Path $folder 'loopback.crt'
$key = Join-Path $folder 'loopback.key'
try {
    & $OpenSsl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -sha256 `
        -days 1 -subj '/CN=ESP IoT loopback test' -addext 'subjectAltName=IP:127.0.0.1' -keyout $key -out $cert
    if ($LASTEXITCODE -ne 0) { throw 'Could not generate the ephemeral loopback certificate.' }
    Push-Location (Join-Path $root 'app')
    try {
        & flutter --no-version-check --suppress-analytics test --no-pub `
            (Join-Path $PSScriptRoot 'secure_transport_test.dart') `
            "--dart-define=ESP_IOT_TEST_CERT=$cert" "--dart-define=ESP_IOT_TEST_KEY=$key"
        if ($LASTEXITCODE -ne 0) { throw 'The secure transport test failed.' }
    } finally {
        Pop-Location
    }
} finally {
    foreach ($file in @($cert, $key)) {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
    }
    Remove-Item -LiteralPath $folder
}
