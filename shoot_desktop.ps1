param(
  [string]$ProcessName = "noahs_ark_desktop",
  [string]$Out = "C:\Users\other8080\Videos\project\hk\shots\desktop_login.png",
  [int]$WaitSeconds = 0
)
if ($WaitSeconds -gt 0) { Start-Sleep -Seconds $WaitSeconds }
$src = @'
using System;
using System.Runtime.InteropServices;
public class WinCap {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
'@
Add-Type -TypeDefinition $src -ReferencedAssemblies System.Drawing
Add-Type -AssemblyName System.Drawing
$p = Get-Process $ProcessName -ErrorAction SilentlyContinue
if (-not $p -or $p.MainWindowHandle -eq 0) { Write-Output "app window not found"; exit 1 }
[WinCap]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 500
$r = New-Object WinCap+RECT
[WinCap]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$bmp.Save($Out)
Write-Output "captured ${w}x${h} -> $Out"
