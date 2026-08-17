# Minecraft 統合版 アカウント切り替え - 配布パッケージ作成
# 作者: Ragazzo249
#
# 個人情報（登録済みアカウント・設定・調査結果）を含めずに、
# 配布用の ZIP を dist\ へ出力する。
#
# tako:run: powershell -NoProfile -ExecutionPolicy Bypass -File "${file}"
# tako:cwd: ${fileDir}

param(
    # 出力する ZIP のファイル名。既定は日付入り
    [string]$Name
)

$ErrorActionPreference = 'Stop'

# 配布に含めるファイル。profiles / settings.json / snapshots は個人情報なので含めない
$include = @(
    'mc-switcher.ps1'
    'mc-switcher.cmd'
    'mc-profile.ps1'
    'lib.ps1'
    'create-shortcut.ps1'
    'setup.ps1'
    'setup.cmd'
    'snapshot.ps1'
    'compare.ps1'
    'README.md'
    'LICENSE'
)

$distDir = Join-Path $PSScriptRoot 'dist'
$stageDir = Join-Path $distDir '_stage'

if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

$copied = @()
$missing = @()
foreach ($f in $include) {
    $src = Join-Path $PSScriptRoot $f
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination $stageDir
        $copied += $f
    } else {
        $missing += $f
    }
}

if (-not $Name) {
    $Name = "mc-account-switcher-$((Get-Date).ToString('yyyyMMdd')).zip"
}
if ($Name -notlike '*.zip') { $Name = "$Name.zip" }

$zipPath = Join-Path $distDir $Name
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath
Remove-Item -LiteralPath $stageDir -Recurse -Force

# 個人情報が混入していないか、出来上がった ZIP の中身を確認する
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
$entries = @($zip.Entries | ForEach-Object { $_.FullName })
$zip.Dispose()

$leaked = @($entries | Where-Object { $_ -like 'profiles*' -or $_ -like 'settings.json' -or $_ -like 'snapshots*' })

Write-Host ""
Write-Host "パッケージを作成しました" -ForegroundColor Green
Write-Host "  $zipPath"
Write-Host "  収録 $($entries.Count) ファイル: $($entries -join ', ')" -ForegroundColor DarkGray

if ($missing.Count -gt 0) {
    Write-Host "  同梱できなかったファイル: $($missing -join ', ')" -ForegroundColor Yellow
}
if ($leaked.Count -gt 0) {
    Write-Host "  警告: 個人情報を含むファイルが混入しています: $($leaked -join ', ')" -ForegroundColor Red
} else {
    Write-Host "  個人情報（profiles / settings.json / snapshots）は含まれていません" -ForegroundColor Green
}
