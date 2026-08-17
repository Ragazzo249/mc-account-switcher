# Minecraft 統合版 アカウント切り替え - ショートカット作成
# 作者: Ragazzo249
#
# GUI をダブルクリックで開けるよう、デスクトップにショートカットを作る。
# アイコンには Minecraft 本体のものを使う。
#
# tako:run: powershell -NoProfile -ExecutionPolicy Bypass -File "${file}"
# tako:cwd: ${fileDir}

param(
    # 作成先。既定はデスクトップ
    [string]$OutDir = [Environment]::GetFolderPath('Desktop'),

    [string]$ShortcutName = 'Minecraft アカウント切り替え'
)

$ErrorActionPreference = 'Stop'

$guiScript = Join-Path $PSScriptRoot 'mc-switcher.ps1'
if (-not (Test-Path -LiteralPath $guiScript)) {
    throw "mc-switcher.ps1 が見つかりません: $guiScript"
}

# 専用アイコンを優先し、無ければ Minecraft 本体のアイコンで代用する
$iconCandidates = @(
    (Join-Path $PSScriptRoot 'assets\app.ico')
    (Join-Path $PSScriptRoot 'app.ico')
    'C:\XboxGames\Minecraft for Windows\Content\Minecraft.Windows.exe'
    "$env:ProgramFiles\WindowsApps\Microsoft.MinecraftUWP_8wekyb3d8bbwe\Minecraft.Windows.exe"
)
$icon = $null
foreach ($c in $iconCandidates) {
    if (Test-Path -LiteralPath $c) { $icon = $c; break }
}

$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$linkPath = Join-Path $OutDir "$ShortcutName.lnk"

$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($linkPath)
$link.TargetPath = $powershell
$link.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$guiScript`""
$link.WorkingDirectory = $PSScriptRoot
$link.Description = 'Minecraft 統合版のアカウントを切り替える'
$link.WindowStyle = 7   # 最小化で起動し、コンソールを見せない
if ($icon) { $link.IconLocation = "$icon,0" }
$link.Save()

Write-Host "ショートカットを作成しました" -ForegroundColor Green
Write-Host "  $linkPath"
if (-not $icon) {
    Write-Host "  ※ Minecraft のアイコンが見つからなかったため、既定のアイコンを使っています" -ForegroundColor DarkGray
}
