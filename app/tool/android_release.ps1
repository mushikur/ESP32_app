#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string]$ExpectedSignerSha256,
    [string]$JavaHome = 'C:\Program Files\Android\Android Studio\jbr',
    [string]$AndroidSdk = (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
    [string]$BundletoolJar
)

$ErrorActionPreference = 'Stop'
$app = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$expectedPackage = 'com.samir.esp_iot'

function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$(Split-Path -Leaf $Executable) exited with code $LASTEXITCODE."
    }
}

function Assert-ArtifactIdentity {
    param(
        [string]$Artifact,
        [string]$Package,
        [string]$VersionName,
        [string]$VersionCode
    )
    if ($Package -cne $expectedPackage -or
        $VersionName -cne $expectedVersionName -or
        $VersionCode -cne $expectedVersionCode) {
        throw "$Artifact reports $Package $VersionName ($VersionCode). Expected $expectedPackage $expectedVersionName ($expectedVersionCode)."
    }
}

$version = (Select-String -LiteralPath (Join-Path $app 'pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)$').Matches
if ($version.Count -ne 1) { throw 'Expected a single Android version and build number in pubspec.yaml.' }
$expectedVersionName = $version[0].Groups[1].Value
$expectedVersionCode = $version[0].Groups[2].Value

$tools = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
if (!$tools) { throw 'Android SDK Build Tools are required to verify release artifacts.' }

$java = Join-Path $JavaHome 'bin\java.exe'
if ($BundletoolJar) {
    $bundletoolArgs = @('-jar', (Resolve-Path -LiteralPath $BundletoolJar).Path)
} else {
    # The thin bundletool JAR and its dependencies for this project's AGP are
    # already in Gradle's local cache. A standalone JAR works on other setups.
    $gradleHome = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { Join-Path $env:USERPROFILE '.gradle' }
    $cache = Join-Path $gradleHome 'caches\modules-2\files-2.1'
    $groups = @(
        'com.android.tools.build', 'com.google.protobuf', 'com.google.guava',
        'com.google.code.gson', 'com.google.dagger', 'javax.inject',
        'jakarta.inject', 'com.google.auto.value', 'com.google.errorprone',
        'com.google.j2objc', 'org.checkerframework', 'org.bitbucket.b_c', 'org.slf4j'
    )
    $dependencyJars = @(
        'bundletool-1.18.3.jar', 'protobuf-java-3.25.5.jar',
        'protobuf-java-util-3.25.5.jar', 'guava-33.3.1-jre.jar',
        'failureaccess-1.0.2.jar', 'gson-2.13.2.jar', 'dagger-2.59.jar',
        'javax.inject-1.jar', 'jakarta.inject-api-2.0.1.jar',
        'aapt2-proto-9.1.0-14792394.jar', 'apksig-9.1.0.jar', 'apkzlib-9.1.0.jar',
        'auto-value-annotations-1.6.3.jar', 'error_prone_annotations-2.41.0.jar',
        'checker-qual-3.43.0.jar', 'j2objc-annotations-3.0.0.jar'
    )
    $classpathJars = @(foreach ($group in $groups) {
        Get-ChildItem -LiteralPath (Join-Path $cache $group) -Filter '*.jar' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in $dependencyJars -or $_.Name -match '^(jose4j|slf4j-api)-' } |
            Select-Object -ExpandProperty FullName
    })
    if (!($classpathJars -match 'bundletool-1\.18\.3\.jar$')) {
        throw 'No cached bundletool was found. Pass -BundletoolJar with a standalone bundletool release JAR.'
    }
    $bundletoolArgs = @('-cp', ($classpathJars -join ';'), 'com.android.tools.build.bundletool.BundleToolMain')
}

$previousJavaHome = $env:JAVA_HOME
$env:JAVA_HOME = $JavaHome
Push-Location -LiteralPath $app
try {
    Invoke-Checked 'flutter' @('--no-version-check', '--suppress-analytics', 'build', 'apk', '--release', '--no-pub')
    Invoke-Checked 'flutter' @('--no-version-check', '--suppress-analytics', 'build', 'appbundle', '--release', '--no-pub')

    $apk = (Resolve-Path -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk').Path
    $bundle = (Resolve-Path -LiteralPath 'build\app\outputs\bundle\release\app-release.aab').Path

    $badging = Invoke-Checked (Join-Path $tools.FullName 'aapt2.exe') @('dump', 'badging', $apk)
    $apkIdentity = [regex]::Match(
        ($badging -join "`n"),
        "(?m)^package: name='(?<package>[^']+)' versionCode='(?<code>\d+)' versionName='(?<version>[^']+)'"
    )
    if (!$apkIdentity.Success) { throw 'Could not read the APK package and version.' }
    Assert-ArtifactIdentity 'APK' $apkIdentity.Groups['package'].Value $apkIdentity.Groups['version'].Value $apkIdentity.Groups['code'].Value

    $manifestOutput = Invoke-Checked $java ($bundletoolArgs + @('dump', 'manifest', "--bundle=$bundle", '--module=base'))
    $manifest = ([xml]($manifestOutput -join "`n")).DocumentElement
    $android = 'http://schemas.android.com/apk/res/android'
    Assert-ArtifactIdentity 'AAB' ($manifest.GetAttribute('package')) ($manifest.GetAttribute('versionName', $android)) ($manifest.GetAttribute('versionCode', $android))

    $apkCertificate = Invoke-Checked (Join-Path $tools.FullName 'apksigner.bat') @('verify', '--print-certs', $apk)
    if (!($apkCertificate -match "Signer #1 certificate SHA-256 digest: $ExpectedSignerSha256$")) {
        throw 'The APK signer does not match the established release certificate.'
    }
    Invoke-Checked (Join-Path $tools.FullName 'zipalign.exe') @('-c', '-P', '16', '4', $apk)
    $verification = Invoke-Checked (Join-Path $JavaHome 'bin\jarsigner.exe') @('-verify', $bundle)
    if (!($verification -match '^jar verified\.$')) {
        throw 'App Bundle signature verification failed.'
    }
    $bundleCertificate = Invoke-Checked (Join-Path $JavaHome 'bin\keytool.exe') @('-printcert', '-jarfile', $bundle)
    if (!(($bundleCertificate -replace ':', '') -match "SHA256\s+$ExpectedSignerSha256$")) {
        throw 'The App Bundle signer does not match the established release certificate.'
    }

    $name = "ESP-IoT-$expectedVersionName-$expectedVersionCode"
    $output = New-Item -ItemType Directory -Path 'build\distribution' -Force
    $artifacts = @(
        (Join-Path $output.FullName "$name.apk")
        (Join-Path $output.FullName "$name.aab")
    )
    Copy-Item -LiteralPath $apk -Destination $artifacts[0]
    Copy-Item -LiteralPath $bundle -Destination $artifacts[1]
    Get-FileHash -LiteralPath $artifacts -Algorithm SHA256
} finally {
    Pop-Location
    $env:JAVA_HOME = $previousJavaHome
}
