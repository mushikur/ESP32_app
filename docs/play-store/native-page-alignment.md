# Check Android 16 KiB page alignment

Run these checks on each signed release candidate. They read the APK and AAB without changing either file. Static alignment does not measure runtime behavior on a device booted with 16 KiB pages. [Android page-size compatibility guide](https://developer.android.com/guide/practices/page-sizes)

## Universal APK packaging

```powershell
$espSdk = 'C:\Users\USER\AppData\Local\Android\Sdk'
$espApk = (Resolve-Path 'app\build\distribution\ESP-IoT-1.0.1-2003.apk').Path
$espBundle = (Resolve-Path 'app\build\distribution\ESP-IoT-1.0.1-2003.aab').Path
Get-FileHash -LiteralPath $espApk, $espBundle -Algorithm SHA256
& "$espSdk\build-tools\36.0.0\zipalign.exe" -c -P 16 -v 4 $espApk
```

Expect a zero exit code and `Verification successful`.

## Bundle structure and packaging

With a standalone [bundletool release JAR](https://github.com/google/bundletool/releases) and Java:

```powershell
java -jar bundletool-all-1.18.3.jar validate "--bundle=$espBundle"
java -jar bundletool-all-1.18.3.jar dump config "--bundle=$espBundle"
java -jar bundletool-all-1.18.3.jar dump manifest "--bundle=$espBundle"
```

Expect `optimizations.uncompressNativeLibraries.enabled` to be true and `alignment` to be `PAGE_ALIGNMENT_16K`. Check the manifest's application ID, version, and SDK levels against the release. The bundled Gradle-cache JAR is a thin Java library and needs its runtime dependencies on the classpath. For the installed Android Studio and Gradle cache used by this project, run:

```powershell
$espJava = 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe'
$espCache = 'C:\Users\USER\.gradle\caches\modules-2\files-2.1'
$espGroups = @(
  'com.android.tools.build', 'com.google.protobuf', 'com.google.guava',
  'com.google.code.gson', 'com.google.dagger', 'javax.inject',
  'jakarta.inject', 'com.google.auto.value', 'com.google.errorprone',
  'com.google.j2objc', 'org.checkerframework', 'org.bitbucket.b_c', 'org.slf4j'
)
$espJars = @(
  'bundletool-1.18.3.jar', 'protobuf-java-3.25.5.jar',
  'protobuf-java-util-3.25.5.jar', 'guava-33.3.1-jre.jar',
  'failureaccess-1.0.2.jar', 'gson-2.13.2.jar', 'dagger-2.59.jar',
  'javax.inject-1.jar', 'jakarta.inject-api-2.0.1.jar',
  'aapt2-proto-9.1.0-14792394.jar', 'apksig-9.1.0.jar', 'apkzlib-9.1.0.jar',
  'auto-value-annotations-1.6.3.jar', 'error_prone_annotations-2.41.0.jar',
  'checker-qual-3.43.0.jar', 'j2objc-annotations-3.0.0.jar'
)
$espClassPath = @(foreach ($espGroup in $espGroups) {
  Get-ChildItem -LiteralPath (Join-Path $espCache $espGroup) -Filter '*.jar' -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in $espJars -or $_.Name -match '^(jose4j|slf4j-api)-' } |
    Select-Object -ExpandProperty FullName
}) -join ';'
& $espJava -cp $espClassPath com.android.tools.build.bundletool.BundleToolMain dump config "--bundle=$espBundle"
```

## Native library segments

With the Android NDK, inspect `LOAD` lines from `llvm-objdump -p` for each extracted `.so` under `lib/arm64-v8a` and `lib/x86_64` in the APK and `base/lib` in the AAB. Each load segment must be aligned to at least `2**14`. The following PowerShell check reads the ELF64 program headers directly from the archives. It checks the declared alignment and matching file and virtual offsets at 16 KiB boundaries.

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($espArchive in @($espApk, $espBundle)) {
  $espZip = [IO.Compression.ZipFile]::OpenRead($espArchive)
  try {
    foreach ($espAbi in @('arm64-v8a', 'x86_64')) {
      $espEntries = @($espZip.Entries | Where-Object {
        $_.FullName -match "^(?:base/)?lib/$espAbi/[^/]+\.so$"
      })
      if ($espEntries.Count -eq 0) { throw "Missing $espAbi libraries in $espArchive" }
      foreach ($espEntry in $espEntries) {
        $espBytes = [IO.MemoryStream]::new()
        $espSource = $espEntry.Open()
        try { $espSource.CopyTo($espBytes) } finally { $espSource.Dispose() }
        $espBytes.Position = 0
        $espReader = [IO.BinaryReader]::new($espBytes)
        try {
          if ($espReader.ReadUInt32() -ne 0x464c457f -or
              $espReader.ReadByte() -ne 2 -or $espReader.ReadByte() -ne 1) {
            throw "Expected a little-endian ELF64 file in $($espEntry.FullName)"
          }
          $espBytes.Position = 32
          $espProgramHeaderOffset = $espReader.ReadUInt64()
          $espBytes.Position = 54
          $espProgramHeaderSize = $espReader.ReadUInt16()
          $espProgramHeaderCount = $espReader.ReadUInt16()
          $espAlignments = @(for ($espIndex = 0; $espIndex -lt $espProgramHeaderCount; $espIndex++) {
            $espBytes.Position = [long]($espProgramHeaderOffset + $espProgramHeaderSize * $espIndex)
            if ($espReader.ReadUInt32() -ne 1) { continue }
            $null = $espReader.ReadUInt32()
            $espFileOffset = $espReader.ReadUInt64()
            $espVirtualAddress = $espReader.ReadUInt64()
            $espBytes.Position += 24
            $espAlignment = $espReader.ReadUInt64()
            if ($espAlignment -lt 16384 -or $espFileOffset % 16384 -ne $espVirtualAddress % 16384) {
              throw "Unaligned load segment in $espArchive / $($espEntry.FullName)"
            }
            $espAlignment
          })
          if (!$espAlignments.Count) { throw "Missing load segments in $($espEntry.FullName)" }
          [pscustomobject]@{
            Archive = Split-Path $espArchive -Leaf
            Library = $espEntry.FullName
            LoadSegments = $espAlignments.Count
            MinimumAlignment = ($espAlignments | Measure-Object -Minimum).Minimum
          }
        } finally {
          $espReader.Dispose()
        }
      }
    }
  } finally {
    $espZip.Dispose()
  }
}
```
