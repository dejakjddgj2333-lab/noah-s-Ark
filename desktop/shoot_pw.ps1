param(
  [string]$ProcessName = "noahs_ark_desktop",
  [string]$Out = "C:\Users\other8080\Videos\project\hk\shots\desktop_pw.png"
)
$src = @'
using System;
using System.Runtime.InteropServices;
public class WinPW {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
'@
Add-Type -TypeDefinition $src -ReferencedAssemblies System.Drawing
Add-Type -AssemblyName System.Drawing
$p = Get-Process $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p -or $p.MainWindowHandle -eq 0) { Write-Output "app window not found"; exit 1 }
$r = New-Object WinPW+RECT
[WinPW]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
# PW_RENDERFULLCONTENT=2: 捕获被遮挡窗口的完整内容
$ok = [WinPW]::PrintWindow($p.MainWindowHandle, $hdc, 2)
$g.ReleaseHdc($hdc)
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$bmp.Save($Out)
$g.Dispose(); $bmp.Dispose()
Write-Output "printwindow=$ok captured ${w}x${h} -> $Out"
