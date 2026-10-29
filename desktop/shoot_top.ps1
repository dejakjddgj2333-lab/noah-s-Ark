param(
  [string]$ProcessName = "noahs_ark_desktop",
  [string]$Out = "C:\Users\other8080\Videos\project\hk\shots\desktop_login.png"
)
$src = @'
using System;
using System.Runtime.InteropServices;
public class WinCap2 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
'@
Add-Type -TypeDefinition $src -ReferencedAssemblies System.Drawing -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing
$p = Get-Process $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p -or $p.MainWindowHandle -eq 0) { Write-Output "app window not found"; exit 1 }
# HWND_TOP=0, SWP_NOMOVE|SWP_NOSIZE=0x3 — 提到 z 序顶部(非 topmost)
[WinCap2]::SetWindowPos($p.MainWindowHandle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0003) | Out-Null
Start-Sleep -Milliseconds 600
$r = New-Object WinCap2+RECT
[WinCap2]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$bmp.Save($Out)
Write-Output "captured ${w}x${h} -> $Out"
