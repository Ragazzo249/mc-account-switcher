# Minecraft 統合版 アカウント切り替え - GUI
# 作者: Ragazzo249
#
# アカウントのカードをクリックするだけで切り替え、そのまま Minecraft を起動する。
# ゲーム内のサインアウト・再サインイン操作は不要。
# アカウントの登録も「アカウントを追加」ダイアログから行える。
#
# tako:run: powershell -NoProfile -ExecutionPolicy Bypass -File "${file}"
# tako:cwd: ${fileDir}

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# タイトルバーをダークにするための API。対応していない環境では無視される
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DwmHelper {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
}
"@

[System.Windows.Forms.Application]::EnableVisualStyles()

# --- 配色 ---
$colBg        = [System.Drawing.Color]::FromArgb(30, 30, 32)
$colPanel     = [System.Drawing.Color]::FromArgb(38, 38, 42)
$colCard      = [System.Drawing.Color]::FromArgb(44, 44, 48)
$colCardHover = [System.Drawing.Color]::FromArgb(58, 58, 64)
$colAccent    = [System.Drawing.Color]::FromArgb(60, 133, 39)   # Minecraft の緑
$colAccentLit = [System.Drawing.Color]::FromArgb(78, 160, 52)
$colText      = [System.Drawing.Color]::FromArgb(238, 238, 238)
$colSub       = [System.Drawing.Color]::FromArgb(155, 155, 162)
$colLine      = [System.Drawing.Color]::FromArgb(62, 62, 68)

$fontFamily   = 'Yu Gothic UI'
$fontTitle    = New-Object System.Drawing.Font($fontFamily, 12, [System.Drawing.FontStyle]::Bold)
$fontBody     = New-Object System.Drawing.Font($fontFamily, 10)
$fontSmall    = New-Object System.Drawing.Font($fontFamily, 8.5)
$fontBadge    = New-Object System.Drawing.Font($fontFamily, 8.5, [System.Drawing.FontStyle]::Bold)

# メールアドレスを画面に出すかどうか。「メールアドレスを削除」で false 側に倒れる
$script:HideEmail = [bool](Get-AppSettings).hideEmail

# --- 共通の部品 ---

# カードやダイアログに出すアカウントの説明文。
# メールアドレスを削除済みならゲーマータグだけを返す
function Format-AccountDetail {
    param([string]$Gamertag, [string]$UserName)
    if ($script:HideEmail -or [string]::IsNullOrWhiteSpace($UserName)) {
        return [string]$Gamertag
    }
    return "$Gamertag  /  $UserName"
}

function Show-Warn {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message, 'Minecraft アカウント切り替え',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
}

function Set-DarkTitleBar {
    param($Form)
    # 20 は Windows 10 2004 以降、19 はそれ以前のビルド向けの属性番号
    $on = 1
    foreach ($attr in @(20, 19)) {
        [void][DwmHelper]::DwmSetWindowAttribute($Form.Handle, $attr, [ref]$on, 4)
    }
}

function New-FlatButton {
    param(
        [string]$Text,
        [int]$X, [int]$Y, [int]$Width, [int]$Height = 32,
        [switch]$Primary
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($Width, $Height)
    $b.FlatStyle = 'Flat'
    $b.Font = $fontSmall
    $b.ForeColor = $colText
    $b.FlatAppearance.BorderSize = 0
    if ($Primary) {
        $b.BackColor = $colAccent
        $b.FlatAppearance.MouseOverBackColor = $colAccentLit
    } else {
        $b.BackColor = $colCard
        $b.FlatAppearance.MouseOverBackColor = $colCardHover
    }
    return $b
}

function New-TextLabel {
    param(
        [string]$Text,
        [int]$X, [int]$Y,
        $Font, $Color,
        [int]$Width = 0
    )
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Font = $Font
    $l.ForeColor = $Color
    if ($Width -gt 0) {
        $l.AutoSize = $false
        $l.Size = New-Object System.Drawing.Size($Width, 20)
    } else {
        $l.AutoSize = $true
    }
    return $l
}

function New-Separator {
    param([int]$X, [int]$Y, [int]$Width)
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($X, $Y)
    $p.Size = New-Object System.Drawing.Size($Width, 1)
    $p.BackColor = $colLine
    return $p
}

# --- アカウント登録ダイアログ ---
#
# 現在サインイン中のアカウントを登録する。
# 別のアカウントを追加したい場合は、ダイアログ内の手順に従って
# Minecraft でサインインし直し、「再確認」で読み直す。
function Show-RegisterDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'アカウントを追加'
    $dlg.ClientSize = New-Object System.Drawing.Size(460, 396)
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.StartPosition = 'CenterParent'
    $dlg.BackColor = $colBg
    $dlg.ForeColor = $colText
    $dlg.Font = $fontBody
    $dlg.Add_Shown({ Set-DarkTitleBar $dlg }.GetNewClosure())

    # 検出したアカウント
    $lblCaption = New-TextLabel '現在サインイン中のアカウント' 16 16 $fontSmall $colSub
    $lblTag     = New-TextLabel '' 16 36 $fontTitle $colText
    $lblMsa     = New-TextLabel '' 18 64 $fontSmall $colSub
    $lblDup     = New-TextLabel '' 18 86 $fontSmall $colAccentLit

    $btnRecheck = New-FlatButton '再確認' 344 36 100 30

    $sep1 = New-Separator 16 112 428

    # 登録名
    $lblNameCap = New-TextLabel '登録名' 16 124 $fontSmall $colSub
    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point(16, 146)
    $txtName.Size = New-Object System.Drawing.Size(428, 26)
    $txtName.BackColor = $colCard
    $txtName.ForeColor = $colText
    $txtName.BorderStyle = 'FixedSingle'
    $txtName.Font = $fontBody

    $lblNameHint = New-TextLabel '用途が分かる名前を付けます（例: 普段用、検証用）' 16 178 $fontSmall $colSub

    $sep2 = New-Separator 16 206 428

    # 別アカウントを追加する手順
    $lblGuideCap = New-TextLabel '別のアカウントを追加するには' 16 218 $fontSmall $colText
    $lblGuide = New-Object System.Windows.Forms.Label
    $lblGuide.Text = "1. 「Minecraft を起動」を押す`r`n" +
                     "2. ゲーム内で 設定 → アカウント → サインアウト`r`n" +
                     "3. 追加したいアカウントでサインインする`r`n" +
                     "4. Minecraft を終了し、「再確認」を押す"
    $lblGuide.Location = New-Object System.Drawing.Point(18, 240)
    $lblGuide.Size = New-Object System.Drawing.Size(300, 86)
    $lblGuide.Font = $fontSmall
    $lblGuide.ForeColor = $colSub

    $btnLaunch = New-FlatButton 'Minecraft を起動' 324 246 120 32

    # 決定ボタン
    $btnCancel = New-FlatButton 'キャンセル' 244 348 96
    $btnOk     = New-FlatButton '登録' 348 348 96 -Primary

    $dlg.Controls.AddRange(@(
        $lblCaption, $lblTag, $lblMsa, $lblDup, $btnRecheck, $sep1,
        $lblNameCap, $txtName, $lblNameHint, $sep2,
        $lblGuideCap, $lblGuide, $btnLaunch, $btnCancel, $btnOk
    ))

    # 検出したアカウントを保持する。登録時にこの値を使うのではなく
    # 保存直前にレジストリを読み直すため、ここでは表示と重複判定にだけ使う
    $state = @{ Account = $null; Saved = $false }

    $refresh = {
        try {
            $acct = Get-CurrentAccount
        } catch {
            Show-Warn $_.Exception.Message
            return
        }
        $state.Account = $acct

        $lblTag.Text = if ($acct.Gamertag) { $acct.Gamertag } else { '(不明)' }
        $lblMsa.Text = if ($script:HideEmail) {
            ''
        } elseif ($acct.UserName) {
            $acct.UserName
        } else {
            'サインイン情報を取得できません'
        }

        $existing = Get-ProfileByXuid -Xuid $acct.Xuid
        if ($existing) {
            $lblDup.Text = "このアカウントは既に「$($existing.name)」として登録されています"
            if ([string]::IsNullOrWhiteSpace($txtName.Text)) { $txtName.Text = $existing.name }
        } else {
            $lblDup.Text = ''
            if ([string]::IsNullOrWhiteSpace($txtName.Text) -and $acct.Gamertag) {
                $txtName.Text = $acct.Gamertag
            }
        }
    }

    $btnRecheck.Add_Click({
        if (Test-MinecraftRunning) {
            Show-Warn "Minecraft が起動中です。`n`nサインインの状態は Minecraft を終了したあとに確定します。終了してから「再確認」を押してください。"
            return
        }
        & $refresh
    }.GetNewClosure())

    $btnLaunch.Add_Click({
        Start-MinecraftBedrock
    })

    $btnOk.Add_Click({
        $name = $txtName.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($name)) {
            Show-Warn '登録名を入力してください。'
            return
        }

        if (Test-MinecraftRunning) {
            Show-Warn "Minecraft が起動中です。終了してから登録してください。"
            return
        }

        try {
            # 同名の登録があれば上書き確認
            if (Test-ProfileExists -Name $name) {
                $answer = [System.Windows.Forms.MessageBox]::Show(
                    "「$name」は既に登録されています。上書きしますか？",
                    '確認',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question)
                if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            }

            # 同じアカウントが別名で登録済みなら二重登録の確認
            $existing = Get-ProfileByXuid -Xuid $state.Account.Xuid
            if ($existing -and $existing.name -ne $name) {
                $answer = [System.Windows.Forms.MessageBox]::Show(
                    "このアカウントは既に「$($existing.name)」として登録されています。`n別名でもう一つ登録しますか？",
                    '確認',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question)
                if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            }

            Save-AccountProfile -Name $name | Out-Null
            # メールアドレスを削除済みなら、新しい登録にも残さない
            if ($script:HideEmail) { Clear-ProfileEmail -Name $name | Out-Null }
            $state.Saved = $true
            $dlg.Close()
        } catch {
            Show-Warn $_.Exception.Message
        }
    }.GetNewClosure())

    $btnCancel.Add_Click({ $dlg.Close() }.GetNewClosure())

    & $refresh
    $dlg.ShowDialog($form) | Out-Null
    $dlg.Dispose()
    return $state.Saved
}

# --- メインフォーム ---
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Minecraft アカウント切り替え'
$form.Size = New-Object System.Drawing.Size(480, 520)
$form.MinimumSize = New-Object System.Drawing.Size(420, 360)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $colBg
$form.ForeColor = $colText
$form.Font = $fontBody
$form.Add_Shown({ Set-DarkTitleBar $form })

# ヘッダー（現在サインイン中のアカウント）
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 88
$header.BackColor = $colPanel

$lblHeaderCaption = New-TextLabel '現在サインイン中' 16 12 $fontSmall $colSub
$lblCurrentTag = New-TextLabel '' 16 32 $fontTitle $colText
$lblCurrentMsa = New-TextLabel '' 16 60 $fontSmall $colSub
$header.Controls.AddRange(@($lblHeaderCaption, $lblCurrentTag, $lblCurrentMsa))

# プロファイル一覧
$list = New-Object System.Windows.Forms.FlowLayoutPanel
$list.Dock = 'Fill'
$list.FlowDirection = 'TopDown'
$list.WrapContents = $false
$list.AutoScroll = $true
$list.BackColor = $colBg
$list.Padding = New-Object System.Windows.Forms.Padding(14, 14, 14, 8)

# フッター
$footer = New-Object System.Windows.Forms.Panel
$footer.Dock = 'Bottom'
$footer.Height = 84
$footer.BackColor = $colPanel

$chkLaunch = New-Object System.Windows.Forms.CheckBox
$chkLaunch.Text = '切り替え後に Minecraft を起動する'
$chkLaunch.Checked = $true
$chkLaunch.ForeColor = $colSub
$chkLaunch.Font = $fontSmall
$chkLaunch.Location = New-Object System.Drawing.Point(16, 12)
$chkLaunch.AutoSize = $true

$btnAdd = New-FlatButton '＋ アカウントを追加' 16 38 150 -Primary
$btnHideEmail = New-FlatButton 'メールアドレスを削除' 172 38 150
$btnRestore = New-FlatButton '直前の状態に戻す' 328 38 120

$footer.Controls.AddRange(@($chkLaunch, $btnAdd, $btnHideEmail, $btnRestore))

# Dock は後から追加したものが外側を取るため、Fill を先に追加する
$form.Controls.Add($list)
$form.Controls.Add($header)
$form.Controls.Add($footer)

# --- カード生成 ---
function New-ProfileCard {
    param($Profile, [bool]$IsCurrent)

    $card = New-Object System.Windows.Forms.Panel
    $card.Size = New-Object System.Drawing.Size(418, 72)
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $card.BackColor = $colCard
    $card.Cursor = [System.Windows.Forms.Cursors]::Hand

    # 現在のアカウントは左端に緑のラインを引いて区別する
    $bar = New-Object System.Windows.Forms.Panel
    $bar.Size = New-Object System.Drawing.Size(4, 72)
    $bar.Location = New-Object System.Drawing.Point(0, 0)
    $bar.BackColor = if ($IsCurrent) { $colAccent } else { $colCard }

    $lblName = New-TextLabel $Profile.name 18 12 $fontTitle $colText
    $lblDetail = New-TextLabel (Format-AccountDetail $Profile.gamertag $Profile.userName) 20 42 $fontSmall $colSub
    $lblBadge = New-TextLabel $(if ($IsCurrent) { '使用中' } else { '' }) 350 16 $fontBadge $colAccent

    $card.Controls.AddRange(@($bar, $lblName, $lblDetail, $lblBadge))

    # マウス操作。子ラベルの上にカーソルがあっても「カード内」として扱う
    $enter = {
        $card.BackColor = $colCardHover
    }.GetNewClosure()

    $leave = {
        $pt = $card.PointToClient([System.Windows.Forms.Cursor]::Position)
        if (-not $card.ClientRectangle.Contains($pt)) {
            $card.BackColor = $colCard
        }
    }.GetNewClosure()

    $click = {
        Invoke-Switch -Name $Profile.name
    }.GetNewClosure()

    # 右クリックメニュー
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $itemRename = $menu.Items.Add('登録名を変更')
    $itemDelete = $menu.Items.Add('このプロファイルを削除')

    $itemRename.Add_Click({
        $newName = Show-RenameDialog -Profile $Profile
        if ($newName) { Update-View }
    }.GetNewClosure())

    $itemDelete.Add_Click({
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "プロファイル「$($Profile.name)」を削除しますか？`n（Minecraft のセーブデータは削除されません）",
            '確認',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            try {
                Remove-AccountProfile -Name $Profile.name
                Update-View
            } catch {
                Show-Warn $_.Exception.Message
            }
        }
    }.GetNewClosure())

    foreach ($c in @($card, $lblName, $lblDetail, $lblBadge, $bar)) {
        $c.Add_MouseEnter($enter)
        $c.Add_MouseLeave($leave)
        $c.Add_Click($click)
        $c.ContextMenuStrip = $menu
        if ($c -ne $card) { $c.Cursor = [System.Windows.Forms.Cursors]::Hand }
    }

    return $card
}

# --- 登録名の変更 ---
function Show-RenameDialog {
    param($Profile)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = '登録名を変更'
    $dlg.ClientSize = New-Object System.Drawing.Size(400, 150)
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.StartPosition = 'CenterParent'
    $dlg.BackColor = $colBg
    $dlg.ForeColor = $colText
    $dlg.Add_Shown({ Set-DarkTitleBar $dlg }.GetNewClosure())

    $lbl = New-TextLabel (Format-AccountDetail $Profile.gamertag $Profile.userName) 16 16 $fontSmall $colSub

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(16, 44)
    $txt.Size = New-Object System.Drawing.Size(368, 26)
    $txt.BackColor = $colCard
    $txt.ForeColor = $colText
    $txt.BorderStyle = 'FixedSingle'
    $txt.Font = $fontBody
    $txt.Text = $Profile.name

    $btnCancel = New-FlatButton 'キャンセル' 184 100 96
    $btnOk = New-FlatButton '変更' 288 100 96 -Primary

    $result = @{ Name = $null }

    $btnOk.Add_Click({
        $name = $txt.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($name)) {
            Show-Warn '登録名を入力してください。'
            return
        }
        if ($name -eq $Profile.name) { $dlg.Close(); return }

        try {
            if (Test-ProfileExists -Name $name) {
                Show-Warn "「$name」は既に使われています。別の名前にしてください。"
                return
            }
            # 中身の name も合わせて更新する必要があるため、保存し直して旧ファイルを消す
            $data = Get-AccountProfile -Name $Profile.name
            $data.name = $name
            $data | ConvertTo-Json -Depth 4 |
                Set-Content -LiteralPath (Join-Path $PSScriptRoot "profiles\$name.json") -Encoding utf8
            Remove-AccountProfile -Name $Profile.name
            $result.Name = $name
            $dlg.Close()
        } catch {
            Show-Warn $_.Exception.Message
        }
    }.GetNewClosure())

    $btnCancel.Add_Click({ $dlg.Close() }.GetNewClosure())

    $dlg.Controls.AddRange(@($lbl, $txt, $btnCancel, $btnOk))
    $dlg.ShowDialog($form) | Out-Null
    $dlg.Dispose()
    return $result.Name
}

# --- 切り替え処理 ---
function Invoke-Switch {
    param([string]$Name)

    try {
        $result = Switch-Account -Name $Name
    } catch {
        Show-Warn $_.Exception.Message
        return
    }

    if ($chkLaunch.Checked) {
        Start-MinecraftBedrock
        $form.Close()
        return
    }

    Update-View
    if ($result.Changed) {
        [System.Windows.Forms.MessageBox]::Show(
            "$($result.From) から $($result.To) に切り替えました。",
            '切り替え完了',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
}

# --- 表示更新 ---
function Update-View {
    try {
        $current = Get-CurrentAccount
    } catch {
        Show-Warn $_.Exception.Message
        return
    }

    $lblCurrentTag.Text = if ($current.Gamertag) { $current.Gamertag } else { '(不明)' }
    $lblCurrentMsa.Text = if ($script:HideEmail) {
        ''
    } elseif ($current.UserName) {
        $current.UserName
    } else {
        'サインイン情報を取得できません'
    }

    $list.Controls.Clear()
    $profiles = @(Get-AccountProfiles)

    if ($profiles.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.Label
        $empty.Text = "登録済みのアカウントがありません。`r`n`r`n" +
                      "下の「＋ アカウントを追加」から、現在サインイン中のアカウントを登録してください。`r`n" +
                      "別のアカウントは、そのダイアログの手順に従って追加できます。"
        $empty.ForeColor = $colSub
        $empty.Font = $fontSmall
        $empty.Size = New-Object System.Drawing.Size(410, 120)
        $list.Controls.Add($empty)
    } else {
        foreach ($p in $profiles) {
            $isCurrent = ([string]$p.xuid -eq [string]$current.Xuid)
            $list.Controls.Add((New-ProfileCard -Profile $p -IsCurrent $isCurrent))
        }
    }

    # 削除済みなら押せないようにして、状態が一目で分かるようにする
    if ($script:HideEmail) {
        $btnHideEmail.Text = 'メールアドレス削除済み'
        $btnHideEmail.Enabled = $false
        $btnHideEmail.BackColor = $colPanel
        $btnHideEmail.ForeColor = $colSub
    }

    # 起動時だけ、登録数に合わせて余白が出ないよう高さを詰める。
    # 以後はユーザーがリサイズした結果を尊重する
    if (-not $script:Sized) {
        $cardsHeight = [Math]::Min([Math]::Max($profiles.Count, 2) * 82 + 22, 460)
        $form.ClientSize = New-Object System.Drawing.Size(464, ($header.Height + $footer.Height + $cardsHeight))
        $script:Sized = $true
    }
}

# --- フッターのボタン ---
$btnAdd.Add_Click({
    if (Show-RegisterDialog) { Update-View }
})

$btnHideEmail.Add_Click({
    $msg = "登録済みアカウントからメールアドレスを削除します。`n`n" +
           "・一覧とヘッダーに表示されなくなります`n" +
           "・プロファイルの表示用データから削除されます`n" +
           "・以後、新しく登録するアカウントにも保存されません`n`n" +
           "アカウントの切り替えには影響しません。`n" +
           "ただし切り替え時にレジストリへ書き戻す内部データには" +
           "メールアドレスが残ります。そちらを消すと切り替えが正しく動作しなくなる" +
           "可能性があるためです。`n`n" +
           "削除したメールアドレスは元に戻せません（再登録すれば戻ります）。`n`n" +
           "実行しますか？"

    $answer = [System.Windows.Forms.MessageBox]::Show(
        $msg, 'メールアドレスを削除',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        $count = Clear-AllProfileEmails
        Set-AppSetting -Key 'hideEmail' -Value $true
        $script:HideEmail = $true
        Update-View
        [System.Windows.Forms.MessageBox]::Show(
            "メールアドレスを削除しました。（$count 件）", '完了',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } catch {
        Show-Warn $_.Exception.Message
    }
})

$btnRestore.Add_Click({
    try {
        $name = Restore-LatestBackup
        Update-View
        [System.Windows.Forms.MessageBox]::Show(
            "直前の状態に戻しました。`n($name)", '復元',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } catch {
        Show-Warn $_.Exception.Message
    }
})

# --- 起動 ---
Update-View
[System.Windows.Forms.Application]::Run($form)
