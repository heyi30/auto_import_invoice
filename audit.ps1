Add-Type @'
using System; using System.Runtime.InteropServices;
public class AV { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
'@
[AV]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]
$CT = [System.Windows.Automation.ControlType]
$TF = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$root = $AE::RootElement
$a = $root.FindFirst($TS::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, "添加明细")))
$p = $a
while ($p -and $p.Current.ControlType -ne $CT::Window) { $p = $TF.GetParent($p) }
$all = $p.FindAll($TS::Descendants, [System.Windows.Automation.Condition]::TrueCondition)

$labels = @()
$edits = @()
$pdfs = @()
foreach ($e in $all) {
    try {
        $r = $e.Current.BoundingRectangle
        if ($r.IsEmpty) { continue }
        if ($r.X -lt 800 -or $r.X -gt 2800) { continue }
        $ct = $e.Current.ControlType
        if ($ct -eq $CT::Text -and $e.Current.Name -eq "内容") { $labels += ,@([int]$r.Y, $e) }
        elseif ($ct -eq $CT::Edit) {
            $vp = $null
            $v = ""
            if ($e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) { $v = $vp.Current.Value }
            $edits += ,@([int]$r.Y, $v)
        } elseif ($ct -eq $CT::Text -and $e.Current.Name -and $e.Current.Name.EndsWith(".pdf")) {
            $pdfs += ,@([int]$r.Y, $e.Current.Name)
        }
    } catch {}
}
$labels = $labels | Sort-Object { $_[0] }
$out = @()
for ($i = 0; $i -lt $labels.Count; $i++) {
    $y0 = $labels[$i][0]
    $y1 = 999999
    if ($i + 1 -lt $labels.Count) { $y1 = $labels[$i + 1][0] }
    $amount = ""
    foreach ($ed in $edits) { if ($ed[0] -gt $y0 -and $ed[0] -lt ($y0 + 500) -and $ed[1] -match '^\d+(\.\d+)?$') { $amount = $ed[1]; break } }
    $files = @()
    foreach ($pf in $pdfs) { if ($pf[0] -gt $y0 -and $pf[0] -lt $y1) { $files += $pf[1] } }
    $out += ("{0}`t{1}`t{2}" -f ($i + 1), $amount, ($files -join ","))
}
$out | Out-File -FilePath "C:\Users\29704\AppData\Local\Temp\invoice_work\audit.txt" -Encoding UTF8
"cards=$($labels.Count) pdfs=$($pdfs.Count)"
