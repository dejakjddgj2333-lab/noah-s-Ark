param([int]$W = 1500, [int]$H = 930)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinMover$W$H {
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hwnd, int x, int y, int w, int h, bool repaint);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$t = "WinMover$W$H" -as [type]
$hwnd = [IntPtr]::Zero
$procs = Get-Process | Where-Object { $_.ProcessName -match 'noahs' -and $_.MainWindowHandle -ne 0 }
if ($procs) { $hwnd = $procs[0].MainWindowHandle }
if ($hwnd -eq [IntPtr]::Zero) { Write-Output "no window"; exit 1 }
$r = New-Object ("WinMover${W}${H}+RECT" -replace '\+','.')
$rect = $null
$t::GetWindowRect($hwnd, [ref]$rect) | Out-Null
$t::MoveWindow($hwnd, $rect.Left, $rect.Top, $W, $H, $true) | Out-Null
Write-Output "moved to $W x $H"
