$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$projectRoot = Split-Path $PSScriptRoot -Parent
$releaseDirectory = Join-Path $projectRoot 'release'
[IO.Directory]::CreateDirectory($releaseDirectory) | Out-Null
$archivePath = Join-Path $releaseDirectory 'Worldbound-Windows.zip'

# Explicit distribution allowlist: no repository, local profile, or credentials.
$rootNames = @(
    'Worldbound.exe', 'chrome_100_percent.pak', 'chrome_200_percent.pak',
    'd3dcompiler_47.dll', 'dxcompiler.dll', 'dxil.dll', 'ffmpeg.dll',
    'icudtl.dat', 'libEGL.dll', 'libGLESv2.dll', 'resources.pak',
    'snapshot_blob.bin', 'v8_context_snapshot.bin', 'vk_swiftshader.dll',
    'vk_swiftshader_icd.json', 'vulkan-1.dll', 'version',
    'LICENSE', 'LICENSES.chromium.html', 'START-HERE.txt', 'README.md'
)
$required = @('Worldbound.exe', 'resources.pak', 'icudtl.dat',
    'resources/app/main.cjs', 'resources/app/package.json', 'resources/app/connection.html')
foreach ($name in $required) {
    if (!(Test-Path -LiteralPath (Join-Path $projectRoot $name))) {
        throw "Required distribution file missing: $name"
    }
}
$files = @($rootNames | ForEach-Object {
    $candidate = Join-Path $projectRoot $_
    if (Test-Path -LiteralPath $candidate) { Get-Item -LiteralPath $candidate }
})
$files += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'locales') -File)
$files += @('main.cjs', 'connection.html', 'package.json') | ForEach-Object {
    Get-Item -LiteralPath (Join-Path $projectRoot "resources/app/$_")
}
$stream = [IO.File]::Open($archivePath, [IO.FileMode]::Create)
$archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $file.FullName, "Worldbound-Windows/$relative",
            [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $archive.Dispose()
    $stream.Dispose()
}
$check = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    if ($check.Entries.Count -ne $files.Count) { throw 'Archive entry count mismatch' }
    foreach ($entry in $check.Entries) {
        $relative = $entry.FullName.Substring('Worldbound-Windows/'.Length)
        $original = Join-Path $projectRoot $relative
        $entryStream = $entry.Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = [BitConverter]::ToString($sha.ComputeHash($entryStream)).Replace('-', '') }
        finally { $sha.Dispose(); $entryStream.Dispose() }
        if ($actual -ne (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash) {
            throw "Archive content mismatch: $relative"
        }
    }
} finally { $check.Dispose() }
Get-Item -LiteralPath $archivePath | Select-Object FullName, Length
Get-FileHash -LiteralPath $archivePath -Algorithm SHA256
