param([int]$X, [int]$Y)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class ClickHelper$X$Y {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);
}
"@
[void]("ClickHelper$X$Y" -as [type])::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 150
("ClickHelper$X$Y" -as [type])::mouse_event(0x0002, 0, 0, 0, 0)
Start-Sleep -Milliseconds 80
("ClickHelper$X$Y" -as [type])::mouse_event(0x0004, 0, 0, 0, 0)
Write-Output "clicked $X,$Y"
