param(
    [string]$Amount,
    [string]$File
)
$ErrorActionPreference = "Stop"
$invoiceDir = "C:\Users\29704\Downloads\10月发票"

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Bot2 {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, IntPtr e);
}
'@
[Bot2]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms

$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]
$CT = [System.Windows.Automation.ControlType]
$root = $AE::RootElement
$screenH = [Bot2]::GetSystemMetrics(1)
$formLeft = 800
$formRight = 2800

function Sleep-Ms([int]$ms) { Start-Sleep -Milliseconds $ms }
function Get-Rect($el) { return $el.Current.BoundingRectangle }

function Get-FormRoot {
    $cond = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "添加明细")),
        (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Button))
    )
    $btn = $root.FindFirst($TS::Descendants, $cond)
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $p = $btn
    while ($p -ne $null) {
        if ($p.Current.ControlType -eq $CT::Window) { return $p }
        $p = $walker.GetParent($p)
    }
    return $root
}

function Find-AmountEdit([string]$value) {
    $form = Get-FormRoot
    $edits = $form.FindAll($TS::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Edit)))
    foreach ($e in $edits) {
        $r = Get-Rect $e
        if ($r.IsEmpty) { continue }
        if ($r.X -lt $formLeft -or $r.X -gt $formRight) { continue }
        $vp = $null
        if ($e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) {
            if ($vp.Current.Value -eq $value) { return $e }
        }
    }
    return $null
}

function Find-UploadForAmount($amountEdit) {
    $form = Get-FormRoot
    $ar = Get-Rect $amountEdit
    $btns = $form.FindAll($TS::Descendants, (New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "上传文件")),
        (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Button)))))
    $best = $null; $bestY = 999999
    foreach ($b in $btns) {
        $r = Get-Rect $b
        if ($r.IsEmpty) { continue }
        if ($r.X -lt $formLeft -or $r.X -gt $formRight) { continue }
        if ($r.Y -gt ($ar.Y + 40) -and $r.Y -lt $bestY) { $bestY = $r.Y; $best = $b }
    }
    return $best
}

function Click-Point([int]$x, [int]$y) {
    [Bot2]::SetCursorPos($x, $y) | Out-Null
    Sleep-Ms 80
    [Bot2]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
    [Bot2]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
}

function Click-El($el) {
    $r = Get-Rect $el
    Click-Point ([int]($r.X + $r.Width / 2)) ([int]($r.Y + $r.Height / 2))
}

function Paste-Text([string]$text) {
    Set-Clipboard -Value $text
    Sleep-Ms 80
    [System.Windows.Forms.SendKeys]::SendWait("^v")
    Sleep-Ms 120
}

function Find-OpenDialog {
    $cond = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "打开")),
        (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Window))
    )
    return $root.FindFirst($TS::Descendants, $cond)
}

function Wait-DialogGone([int]$ms) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $gone = -1
    while ($sw.ElapsedMilliseconds -lt $ms) {
        if ((Find-OpenDialog) -eq $null) {
            if ($gone -lt 0) { $gone = $sw.ElapsedMilliseconds }
            if (($sw.ElapsedMilliseconds - $gone) -ge 750) { return $true }
        } else { $gone = -1 }
        Sleep-Ms 250
    }
    return $false
}

function Test-Chip([string]$fileName) {
    $form = Get-FormRoot
    $els = $form.FindAll($TS::Descendants, (New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, $fileName)),
        (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Text)))))
    return ($els.Count -gt 0)
}

function Scroll-Form([int]$notches) {
    [Bot2]::SetCursorPos(1500, 1200) | Out-Null
    Sleep-Ms 60
    [Bot2]::mouse_event(0x0800, 0, 0, ($notches * 120), [IntPtr]::Zero)
    Sleep-Ms 400
}

$full = Join-Path $invoiceDir $File
if (-not (Test-Path -LiteralPath $full)) { throw "文件不存在: $full" }
$amountEdit = Find-AmountEdit $Amount
if ($amountEdit -eq $null) { throw "找不到金额为 $Amount 的明细卡片" }
for ($i = 0; $i -lt 60; $i++) {
    $ar = Get-Rect $amountEdit
    if (-not $ar.IsEmpty -and $ar.Y -ge 60 -and $ar.Y -le ($screenH - 400)) { break }
    if ($ar.Y -lt 60) { Scroll-Form 3 } else { Scroll-Form -3 }
    Sleep-Ms 200
}
$ar = Get-Rect $amountEdit
Write-Host "amount card y=$([int]$ar.Y)"
$btn = Find-UploadForAmount $amountEdit
if ($btn -eq $null) { throw "找不到该卡片的发票上传按钮" }
$r = Get-Rect $btn
for ($i = 0; $i -lt 10; $i++) {
    if ($r.Y -ge 40 -and ($r.Y + $r.Height) -le ($screenH - 40)) { break }
    if ($r.Y -lt 40) { Scroll-Form 2 } else { Scroll-Form -2 }
    Sleep-Ms 200
    $r = Get-Rect $btn
}
if ($r.Y -lt 0 -or $r.Y -gt $screenH) { throw "上传按钮不在屏幕内: $($r.Y)" }
$fileName = $File

Write-Host "amount=$Amount button=$([int]$r.X),$([int]$r.Y) file=$fileName"
Click-El $btn
Sleep-Ms 400
$dlg = Find-OpenDialog
if ($dlg -eq $null) { throw "文件对话框没有出现" }
Sleep-Ms 300

$searchCond = New-Object System.Windows.Automation.AndCondition(
    (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "搜索框")),
    (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Edit)))
$search = $dlg.FindFirst($TS::Descendants, $searchCond)
if ($search -eq $null) { throw "找不到搜索框" }
Click-El $search
Sleep-Ms 200
[System.Windows.Forms.SendKeys]::SendWait("^a")
Paste-Text $fileName
Sleep-Ms 300
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

$item = $null
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.ElapsedMilliseconds -lt 6000) {
    $ic = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, $fileName)),
        (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::ListItem)))
    $item = $dlg.FindFirst($TS::Descendants, $ic)
    if ($item -ne $null) { break }
    Sleep-Ms 250
}
if ($item -eq $null) { throw "搜索结果里没有 $fileName" }
$sel = $null
if ($item.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sel)) { $sel.Select() } else { Click-El $item }
Sleep-Ms 300
$open = $dlg.FindFirst($TS::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "打开(O)")))
if ($open -eq $null) { [System.Windows.Forms.SendKeys]::SendWait("{ENTER}") } else { Click-El $open }
if (-not (Wait-DialogGone 2500)) {
    $d2 = Find-OpenDialog
    if ($d2 -ne $null) {
        $o2 = $d2.FindFirst($TS::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "打开(O)")))
        if ($o2 -ne $null) { Click-El $o2 }
        if (-not (Wait-DialogGone 8000)) { throw "文件对话框没有关闭" }
    }
}
Sleep-Ms 1500
if (Test-Chip $fileName) { "REPAIRED $fileName" } else { throw "上传后没有看到文件 $fileName" }
