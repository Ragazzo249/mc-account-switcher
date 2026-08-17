# Minecraft 統合版 アカウント切り替え - インストーラーのビルド
# 作者: Ragazzo249
#
# Inno Setup で .exe インストーラーを作り、dist\ へ出力する。
# Inno Setup が未導入なら winget での導入方法を案内する。
#
# tako:run: powershell -NoProfile -ExecutionPolicy Bypass -File "${file}"
# tako:cwd: ${fileDir}

$ErrorActionPreference = 'Stop'

# ISCC.exe（Inno Setup のコンパイラ）を探す
# winget は管理者権限がないとユーザー配下へ入れるため、そちらも見る
$candidates = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    "${env:ProgramFiles(x86)}\Inno Setup 5\ISCC.exe"
)
$iscc = $null
foreach ($c in $candidates) {
    if ($c -and (Test-Path -LiteralPath $c)) { $iscc = $c; break }
}
if (-not $iscc) {
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { $iscc = $cmd.Source }
}
if (-not $iscc) {
    Write-Host "Inno Setup が見つかりません。次のコマンドで導入できます:" -ForegroundColor Yellow
    Write-Host "  winget install --id JRSoftware.InnoSetup"
    exit 1
}

# アイコンが無ければ先に生成する
$icon = Join-Path $PSScriptRoot 'assets\app.ico'
if (-not (Test-Path -LiteralPath $icon)) {
    Write-Host "アイコンが無いので生成します..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'tools\make-icon.ps1')
}

$iss = Join-Path $PSScriptRoot 'installer\mc-account-switcher.iss'
if (-not (Test-Path -LiteralPath $iss)) {
    throw "インストーラー定義が見つかりません: $iss"
}

$distDir = Join-Path $PSScriptRoot 'dist'
if (-not (Test-Path -LiteralPath $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }

Write-Host "Inno Setup: $iscc" -ForegroundColor DarkGray
Write-Host "ビルドしています..." -ForegroundColor Cyan

$output = & $iscc $iss 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "ビルドに失敗しました (exit $exitCode)" -ForegroundColor Red
    $output | Select-Object -Last 30 | ForEach-Object { Write-Host "  $_" }
    exit $exitCode
}

# 出力ファイルを確認する
$exe = Get-ChildItem -LiteralPath $distDir -Filter 'mc-account-switcher-setup-*.exe' -File |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $exe) {
    Write-Host "ビルドは成功しましたが、出力が見つかりません" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "インストーラーを作成しました" -ForegroundColor Green
Write-Host "  $($exe.FullName)"
Write-Host "  $([Math]::Round($exe.Length / 1KB)) KB"
