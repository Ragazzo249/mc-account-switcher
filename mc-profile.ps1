# Minecraft 統合版 アカウント切り替え - CLI
# 作者: Ragazzo249
#
# 通常は GUI (mc-switcher.ps1) を使う。こちらは自動化やトラブル時の確認用。
#
# tako:run[current]: powershell -NoProfile -ExecutionPolicy Bypass -File "${file}" current
# tako:run[list]: powershell -NoProfile -ExecutionPolicy Bypass -File "${file}" list
# tako:cwd: ${fileDir}

param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('save', 'list', 'current', 'switch', 'remove', 'restore')]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$Name,

    # switch 実行後に Minecraft を起動する
    [switch]$Launch,

    # エラー時にキー入力を待つ。ショートカットから実行したとき
    # メッセージを読む前にウィンドウが閉じるのを防ぐ
    [switch]$Pause
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib.ps1')

trap {
    Write-Host "エラー: $($_.Exception.Message)" -ForegroundColor Red
    if ($Pause) { Read-Host "Enter キーで閉じます" | Out-Null }
    exit 1
}

function Show-Account {
    param($Info)
    Write-Host "  ゲーマータグ : $($Info.Gamertag)"
    Write-Host "  MSA          : $($Info.UserName)"
    Write-Host "  XUID         : $($Info.Xuid)"
    Write-Host "  内部ID       : $(if ($Info.InternalId) { $Info.InternalId } else { '(不明)' })"
    if ($Info.DataPath) { Write-Host "  データ       : $($Info.DataPath)" }
}

switch ($Command) {

    'current' {
        Write-Host "現在サインイン中のアカウント" -ForegroundColor Cyan
        Show-Account (Get-CurrentAccount)
    }

    'save' {
        $profile = Save-AccountProfile -Name $Name
        Write-Host "プロファイル '$($profile.name)' を保存しました" -ForegroundColor Green
        Write-Host "  ゲーマータグ : $($profile.gamertag)"
        Write-Host "  MSA          : $($profile.userName)"
    }

    'list' {
        $profiles = @(Get-AccountProfiles)
        if ($profiles.Count -eq 0) {
            Write-Host "保存済みプロファイルはありません。" -ForegroundColor DarkGray
            Write-Host "サインイン中の状態を保存するには: .\mc-profile.ps1 save <名前>"
            break
        }

        $currentXuid = [string](Get-CurrentAccount).Xuid
        Write-Host "保存済みプロファイル" -ForegroundColor Cyan
        foreach ($p in $profiles) {
            $mark = if ([string]$p.xuid -eq $currentXuid) { '*' } else { ' ' }
            Write-Host ("  {0} {1,-14} {2,-18} {3}" -f $mark, $p.name, $p.gamertag, $p.userName)
        }
        Write-Host "  (* = 現在サインイン中)" -ForegroundColor DarkGray
    }

    'switch' {
        $result = Switch-Account -Name $Name
        if ($result.Changed) {
            Write-Host "切り替えました: $($result.From) -> $($result.To)" -ForegroundColor Green
            Write-Host "  切り替え前の状態: $($result.Backup)" -ForegroundColor DarkGray
        } else {
            Write-Host "既に '$Name' ($($result.To)) でサインイン中です。" -ForegroundColor Yellow
        }

        if ($Launch) {
            Write-Host "Minecraft を起動します..." -ForegroundColor Cyan
            Start-MinecraftBedrock
        }
    }

    'remove' {
        Remove-AccountProfile -Name $Name
        Write-Host "プロファイル '$Name' を削除しました。" -ForegroundColor Green
        Write-Host "（Minecraft のセーブデータは削除されていません）" -ForegroundColor DarkGray
    }

    'restore' {
        $name = Restore-LatestBackup
        Write-Host "バックアップから復元しました: $name" -ForegroundColor Green
    }
}
