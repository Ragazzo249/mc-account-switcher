# Minecraft 統合版 アカウント切り替え - 初回セットアップ
# 作者: Ragazzo249
#
# ダウンロード直後に一度だけ実行する。
# インターネットから取得したファイルに付くブロック属性を外し、
# デスクトップにショートカットを作って、そのまま起動できるようにする。
#
# 通常は setup.cmd をダブルクリックして呼び出す。

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "  Minecraft 統合版 アカウント切り替え - セットアップ" -ForegroundColor Cyan
Write-Host "  ------------------------------------------------"
Write-Host ""

# 1. ブロック属性の解除
# ZIP から展開したファイルには「別のコンピューターから取得した」印が付き、
# 実行時に警告が出るため外しておく
$blocked = 0
foreach ($f in Get-ChildItem "$PSScriptRoot\*" -Include *.ps1, *.cmd -File) {
    try {
        if (Get-Item -LiteralPath $f.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue) {
            Unblock-File -LiteralPath $f.FullName
            $blocked++
        }
    } catch {
        # ストリームが無ければ何もしない
    }
}
if ($blocked -gt 0) {
    Write-Host "  [1/3] ファイルのブロックを解除しました（$blocked 件）" -ForegroundColor Green
} else {
    Write-Host "  [1/3] ブロックされたファイルはありませんでした" -ForegroundColor Green
}

# 2. Minecraft 統合版の確認
$installed = Get-AppxPackage -Name 'Microsoft.MinecraftUWP' -ErrorAction SilentlyContinue
if ($installed) {
    Write-Host "  [2/3] Minecraft 統合版を確認しました（$($installed.Version)）" -ForegroundColor Green
} else {
    Write-Host "  [2/3] Minecraft 統合版が見つかりません" -ForegroundColor Yellow
    Write-Host "        このツールは Minecraft for Windows（統合版）専用です。" -ForegroundColor DarkGray
    Write-Host "        Java 版のみをお使いの場合は動作しません。" -ForegroundColor DarkGray
}

# 3. ショートカット作成
Write-Host ""
$answer = Read-Host "  デスクトップにショートカットを作りますか？ [Y/n]"
if ($answer -notmatch '^[nN]') {
    try {
        & "$PSScriptRoot\create-shortcut.ps1"
        Write-Host "  [3/3] ショートカットを作成しました" -ForegroundColor Green
    } catch {
        Write-Host "  [3/3] ショートカットの作成に失敗しました: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [3/3] ショートカットは作成しませんでした" -ForegroundColor DarkGray
    Write-Host "        mc-switcher.cmd をダブルクリックすれば起動できます。" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  セットアップが完了しました。" -ForegroundColor Cyan
Write-Host ""

$answer = Read-Host "  今すぐ起動しますか？ [Y/n]"
if ($answer -notmatch '^[nN]') {
    Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden', '-File', "$PSScriptRoot\mc-switcher.ps1"
} else {
    Write-Host ""
    Read-Host "  Enter キーで閉じます" | Out-Null
}
