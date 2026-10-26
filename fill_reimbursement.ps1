param(
    [int]$Start = 0,
    [int]$Count = 999,
    [switch]$SkipUpload,
    [switch]$NoAdd
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataPath = Join-Path $scriptDir "data.json"
$invoiceDir = "C:\Users\29704\Downloads\10月发票"
$logPath = Join-Path $scriptDir ("run_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Bot {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, IntPtr e);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
}
'@
[Bot]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms

$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]
$CT = [System.Windows.Automation.ControlType]
$root = $AE::RootElement
$screenW = [Bot]::GetSystemMetrics(0)
$screenH = [Bot]::GetSystemMetrics(1)
$formLeft = 800
$formRight = 2800

function Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
    Write-Host $line
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}

function Sleep-Ms([int]$ms) { Start-Sleep -Milliseconds $ms }

$script:formRoot = $null
function Get-FormRoot {
    if ($script:formRoot -ne $null) {
        try { [void]$script:formRoot.Current.Name; return $script:formRoot } catch { $script:formRoot = $null }
    }
    $cond = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "添加明细")),
        (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Button))
    )
    $el = $root.FindFirst($TS::Descendants, $cond)
    if ($el -eq $null) { return $root }
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $p = $el
    while ($p -ne $null) {
        if ($p.Current.ControlType -eq $CT::Window) { $script:formRoot = $p; return $p }
        $p = $walker.GetParent($p)
    }
    return $root
}

function Get-Elements([string]$name, $controlType) {
    $conds = New-Object System.Collections.ArrayList
    if ($name -ne $null) { [void]$conds.Add((New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, $name))) }
    if ($controlType -ne $null) { [void]$conds.Add((New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $controlType))) }
    if ($conds.Count -eq 0) { return @() }
    if ($conds.Count -eq 1) { $cond = $conds[0] } else { $cond = New-Object System.Windows.Automation.AndCondition($conds.ToArray()) }
    $searchRoot = Get-FormRoot
    $found = $searchRoot.FindAll($TS::Descendants, $cond)
    $list = @()
    foreach ($e in $found) { $list += $e }
    return $list
}

function Get-Rect($el) { return $el.Current.BoundingRectangle }

function Get-LastElement([string]$name, $controlType) {
    $els = Get-Elements $name $controlType
    $best = $null; $bestY = -1
    foreach ($e in $els) {
        $r = Get-Rect $e
        if ($r.IsEmpty) { continue }
        if ($r.X -lt $formLeft -or $r.X -gt $formRight) { continue }
        if ($r.Y -gt $bestY) { $bestY = $r.Y; $best = $e }
    }
    return $best
}

function Invoke-El($el) {
    $pat = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pat)) {
        $pat.Invoke()
        return $true
    }
    return $false
}

function Activate-El($el) {
    $pat = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pat)) {
        $pat.Invoke()
    } else {
        Click-El $el
    }
}

function Click-Point([int]$x, [int]$y) {
    [Bot]::SetCursorPos($x, $y) | Out-Null
    Sleep-Ms 80
    [Bot]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
    [Bot]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
}

function Click-El($el) {
    $r = Get-Rect $el
    Click-Point ([int]($r.X + $r.Width / 2)) ([int]($r.Y + $r.Height / 2))
}

function Paste-Text([string]$text) {
    Set-Clipboard -Value $text
    Start-Sleep -Milliseconds 80
    [System.Windows.Forms.SendKeys]::SendWait("^v")
    Start-Sleep -Milliseconds 120
}

function Scroll-Form([int]$notches) {
    $x = 1500; $y = 1200
    [Bot]::SetCursorPos($x, $y) | Out-Null
    Sleep-Ms 60
    [Bot]::mouse_event(0x0800, 0, 0, (-$notches * 120), [IntPtr]::Zero)
    Sleep-Ms 450
}

function Is-Visible($el) {
    if ($el -eq $null) { return $false }
    $r = Get-Rect $el
    if ($r.IsEmpty) { return $false }
    return ($r.Top -ge 40 -and $r.Bottom -le ($screenH - 80) -and $r.Left -ge 0 -and $r.Right -le $screenW)
}

function Get-LastUploadButton {
    $els = Get-Elements "上传文件" $CT::Button
    $rects = @()
    foreach ($e in $els) {
        $r = Get-Rect $e
        if ($r.IsEmpty) { continue }
        if ($r.X -lt $formLeft -or $r.X -gt $formRight) { continue }
        $rects += ,@($e, [int]$r.Y)
    }
    if ($rects.Count -lt 2) { return $null }
    $sorted = $rects | Sort-Object { $_[1] }
    $ys = @()
    foreach ($p in $sorted) { if ($ys.Count -eq 0 -or $ys[-1] -ne $p[1]) { $ys += $p[1] } }
    if ($ys.Count -lt 2) { return $null }
    $targetY = $ys[$ys.Count - 2]
    foreach ($p in $sorted) { if ($p[1] -eq $targetY) { return $p[0] } }
    return $null
}

function Test-Uploaded([string]$fileName) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt 4000) {
        foreach ($e in (Get-Elements $fileName $CT::Text)) {
            $r = Get-Rect $e
            if (-not $r.IsEmpty) { return $true }
        }
        Sleep-Ms 300
    }
    return $false
}

function Count-Cards {
    $n = 0
    foreach ($e in (Get-Elements "内容" $CT::Text)) {
        $r = Get-Rect $e
        if ($r.IsEmpty) { continue }
        if ($r.X -ge $formLeft -and $r.X -le $formRight) { $n++ }
    }
    return $n
}

function Get-AmountEdit {
    $best = $null; $bestY = -1
    foreach ($e in (Get-Elements $null $CT::Edit)) {
        $r = Get-Rect $e
        if ($r.IsEmpty) { continue }
        if ($r.X -lt $formLeft -or $r.X -gt $formRight) { continue }
        if ($e.Current.Name -eq "请选择") { continue }
        if ($r.Y -gt $bestY) { $bestY = $r.Y; $best = $e }
    }
    return $best
}

function Get-AddButton {
    foreach ($e in (Get-Elements "添加明细" $CT::Button)) {
        $r = Get-Rect $e
        if (-not $r.IsEmpty -and $r.X -ge $formLeft -and $r.X -le $formRight) { return $e }
    }
    return $null
}

function Get-ContentLabel {
    return (Get-LastElement "内容" $CT::Text)
}

function Get-ContentPoint($label) {
    $r = Get-Rect $label
    return @([int]($r.X + 130), [int]($r.Y + 76))
}

function Get-CardState {
    return @{
        content = (Get-ContentLabel)
        date    = (Get-LastElement "请选择" $CT::Edit)
        amount  = (Get-AmountEdit)
        upload  = (Get-LastUploadButton)
        add     = (Get-AddButton)
    }
}

function All-Visible($s) {
    if ($s.content -eq $null) { return $false }
    $cr = Get-Rect $s.content
    if ($cr.IsEmpty -or $cr.Top -lt 40) { return $false }
    if (($cr.Bottom + 140) -gt ($screenH - 80)) { return $false }
    if ($s.date -ne $null -and -not (Is-Visible $s.date)) { return $false }
    if ($s.amount -eq $null -or -not (Is-Visible $s.amount)) { return $false }
    if ($s.upload -eq $null -or -not (Is-Visible $s.upload)) { return $false }
    return $true
}

function Ensure-Visible([string]$label) {
    $prevY = -99999
    $stall = 0
    for ($i = 0; $i -lt 60; $i++) {
        $s = Get-CardState
        if (All-Visible $s) { return $true }
        $y = -1
        if ($s.content -ne $null) { $y = [int](Get-Rect $s.content).Y }
        if ($y -eq $prevY) { $stall++ } else { $stall = 0; $prevY = $y }
        if ($stall -ge 3) {
            Log "  滚动 3 次位置没有变化, 停止"
            break
        }
        Log "  scroll (attempt $($i + 1)): 「$label」控件还没有全部可见"
        Scroll-Form 2
    }
    $s = Get-CardState
    foreach ($k in @("content", "date", "amount", "upload", "add")) {
        if ($s[$k] -ne $null) { $r = Get-Rect $s[$k]; Log ("  位置 {0}: {1},{2},{3},{4}" -f $k, [int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height) }
        else { Log "  位置 $($k): 没有找到" }
    }
    return $false
}

function Wait-Dialog([int]$timeoutMs = 5000) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $cond = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "打开")),
        (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Window))
    )
    while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
        $dlg = $root.FindFirst($TS::Descendants, $cond)
        if ($dlg -ne $null) { return $dlg }
        Sleep-Ms 200
    }
    return $null
}

function Find-OpenDialog {
    $cond = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "打开")),
        (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Window))
    )
    return $root.FindFirst($TS::Descendants, $cond)
}

function Close-AnyDialog {
    for ($n = 0; $n -lt 5; $n++) {
        $dlg = Find-OpenDialog
        if ($dlg -eq $null) { return $true }
        Log "  关闭残留的文件对话框"
        $cancel = $dlg.FindFirst($TS::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "取消")))
        if ($cancel -ne $null) { Click-El $cancel } else { [System.Windows.Forms.SendKeys]::SendWait("{ESC}") }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt 3000) {
            if ((Find-OpenDialog) -eq $null) { break }
            Sleep-Ms 200
        }
    }
    return ((Find-OpenDialog) -eq $null)
}

function Wait-DialogClosed($dlg, [int]$timeoutMs = 15000) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $goneSince = -1
    while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
        if ((Find-OpenDialog) -eq $null) {
            if ($goneSince -lt 0) { $goneSince = $sw.ElapsedMilliseconds }
            if (($sw.ElapsedMilliseconds - $goneSince) -ge 750) { return $true }
        } else {
            $goneSince = -1
        }
        Sleep-Ms 250
    }
    return $false
}

function Upload-Invoice([string]$fullPath) {
    Close-AnyDialog | Out-Null
    $btn = Get-LastUploadButton
    if ($btn -eq $null) { throw "找不到「上传文件」按钮" }
    Click-El $btn
    $dlg = Wait-Dialog 6000
    if ($dlg -eq $null) { throw "文件打开对话框没有出现" }
    Sleep-Ms 400

    $fileName = [System.IO.Path]::GetFileName($fullPath)

    # 先在搜索框里搜索文件名
    $searchCond = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "搜索框")),
        (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Edit))
    )
    $search = $dlg.FindFirst($TS::Descendants, $searchCond)
    if ($search -eq $null) {
        $searchCond = New-Object System.Windows.Automation.PropertyCondition($AE::AutomationIdProperty, "SearchEditBox")
        $search = $dlg.FindFirst($TS::Descendants, $searchCond)
    }
    if ($search -eq $null) { throw "找不到搜索框" }
    Click-El $search
    Sleep-Ms 200
    [System.Windows.Forms.SendKeys]::SendWait("^a")
    Paste-Text $fileName
    Sleep-Ms 300
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Log "  搜索: $fileName"

    # 等搜索结果里出现该文件, 选中第一个
    $item = $null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt 6000) {
        $listCond = New-Object System.Windows.Automation.AndCondition(
            (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, $fileName)),
            (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::ListItem))
        )
        $item = $dlg.FindFirst($TS::Descendants, $listCond)
        if ($item -ne $null) { break }
        try { if ($dlg.Current.BoundingRectangle.IsEmpty) { return } } catch { return }
        Sleep-Ms 250
    }
    if ($item -eq $null) { throw "搜索结果里没有 $fileName" }
    $sel = $null
    if ($item.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sel)) {
        $sel.Select()
    } else {
        Click-El $item
    }
    Sleep-Ms 300

    # 确认文件已被选中(文件名框有值), 没有就再单击一次
    $nameCond = New-Object System.Windows.Automation.PropertyCondition($AE::AutomationIdProperty, "1148")
    $nameField = $dlg.FindFirst($TS::Descendants, $nameCond)
    $selected = ""
    if ($nameField -ne $null) {
        $vp = $null
        if ($nameField.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) { $selected = $vp.Current.Value }
    }
    if ($selected -ne $fileName) {
        Click-El $item
        Sleep-Ms 400
    }

    # 点击打开
    $openCond = New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "打开(O)")
    $open = $dlg.FindFirst($TS::Descendants, $openCond)
    if ($open -eq $null) { [System.Windows.Forms.SendKeys]::SendWait("{ENTER}") }
    else { Click-El $open }
    if (-not (Wait-DialogClosed $dlg 2500)) {
        Log "  打开没有生效, 再试一次"
        $dlg2 = Find-OpenDialog
        if ($dlg2 -eq $null) { return }
        Close-AnyDialog | Out-Null
        return
    }
    Sleep-Ms 900
}

$items = Get-Content $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$selected = @($items | Select-Object -Skip $Start -First $Count)
Log "开始: 共 $($items.Count) 条, 本次 $($selected.Count) 条 (start=$Start)"
Log "屏幕: ${screenW}x${screenH}"

$idx = $Start
foreach ($item in $selected) {
    $idx++
    Log "[$idx/$($items.Count)] $($item.name)  $($item.amount)  $($item.file)"
    $invoicePath = Join-Path $invoiceDir $item.file
    if (-not (Test-Path -LiteralPath $invoicePath)) { throw "发票文件不存在: $invoicePath" }

    if (-not (Ensure-Visible $item.name)) { throw "滚动后仍看不到完整的明细卡片" }
    Close-AnyDialog | Out-Null

    # 1. 内容
    $label = Get-ContentLabel
    if ($label -eq $null) { throw "找不到「内容」字段" }
    $pt = Get-ContentPoint $label
    Click-Point $pt[0] $pt[1]
    Sleep-Ms 150
    [System.Windows.Forms.SendKeys]::SendWait("^a")
    Paste-Text $item.name
    Log "  内容: $($item.name)"

    # 2. 日期 -> 今天
    $date = Get-LastElement "请选择" $CT::Edit
    if ($date -eq $null) {
        Log "  日期: 已经填写, 跳过"
    } else {
        Click-El $date
        Sleep-Ms 500
        $todayBtn = $null
        for ($i = 0; $i -lt 10; $i++) {
            $tc = New-Object System.Windows.Automation.AndCondition(
                (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "今天")),
                (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Button))
            )
            foreach ($e in $root.FindAll($TS::Descendants, $tc)) { $r = Get-Rect $e; if (-not $r.IsEmpty -and $r.Y -gt 0 -and $r.Y -lt $screenH) { $todayBtn = $e; break } }
            if ($todayBtn -ne $null) { break }
            Sleep-Ms 200
        }
        if ($todayBtn -eq $null) { throw "日期弹窗里找不到「今天」" }
        Invoke-El $todayBtn | Out-Null
        Sleep-Ms 400
        Log "  日期: 今天"
    }

    # 3. 金额
    $amountEdit = Get-AmountEdit
    if ($amountEdit -eq $null) { throw "找不到金额输入框" }
    Click-El $amountEdit
    Sleep-Ms 150
    [System.Windows.Forms.SendKeys]::SendWait("^a")
    Paste-Text $item.amount
    Log "  金额: $($item.amount)"

    # 4. 上传发票
    if (-not $SkipUpload) {
        Upload-Invoice $invoicePath
        if (-not (Test-Uploaded $item.file)) {
            Log "  上传未确认, 重试"
            Upload-Invoice $invoicePath
        }
        if (-not (Test-Uploaded $item.file)) { throw "发票上传失败: $($item.file)" }
        Log "  发票: $($item.file)"
    }

    # 5. 添加明细 (最后一条不加)
    $isLast = ($idx -eq $items.Count)
    if ((-not $isLast) -and (-not $NoAdd)) {
        Sleep-Ms 500
        $before = Count-Cards
        $added = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $addBtn = Get-AddButton
            if ($addBtn -eq $null) { throw "找不到「添加明细」按钮" }
            $inv = $null
            if ($addBtn.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$inv)) {
                Log "  invoke 添加明细"
                $inv.Invoke()
            } else {
                if (-not (Is-Visible $addBtn)) {
                    Log "  滚动到「添加明细」"
                    $prevY = -99999; $stall = 0
                    for ($i = 0; $i -lt 40; $i++) {
                        if (Is-Visible $addBtn) { break }
                        Scroll-Form 2
                        Sleep-Ms 250
                        $addBtn = Get-AddButton
                        if ($addBtn -eq $null) { break }
                        $y = [int](Get-Rect $addBtn).Y
                        if ($y -eq $prevY) { $stall++ } else { $stall = 0; $prevY = $y }
                        if ($stall -ge 3) { break }
                    }
                    if (-not (Is-Visible $addBtn)) { throw "滚动后仍看不到「添加明细」" }
                    Sleep-Ms 300
                }
                Click-El $addBtn
            }
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.ElapsedMilliseconds -lt 4000) {
                Sleep-Ms 250
                if ((Count-Cards) -gt $before) { $added = $true; break }
            }
            if ($added) { break }
            Log "  添加明细没有生效, 重试 $attempt"
            Sleep-Ms 300
        }
        $after = Count-Cards
        Log "  添加明细: 卡片数 $before -> $after"
        if (-not $added) { throw "点击「添加明细」后没有出现新卡片" }
        Scroll-Form 2
        Sleep-Ms 300
    }
}

Log "完成 $($selected.Count) 条"
