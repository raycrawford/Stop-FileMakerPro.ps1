<#
.SYNOPSIS
  Script to ensure the FileMaker Pro Server is not hung as a background process

.SYNTAX
  Stop-FileMakerPro.ps1

.DESCRIPTION
  FileMaker Pro was hanging as a background process and we were asked to kill 
  the process if it lives as a background process for more than 15 seconds.  This 
  is tested through the C# assembly below.  [userwindows]::hasWindowStyle($fmpro) 
  Returns $true if the process is running as an interactive app and $false if it 
  is a background process.

.INPUTS
  None

.OUTPUTS
  Log file is dumped to C:\Windows\Temp\Stop-FileMakerPro.log

.NOTES
  Version:          1.0
  Author:           Ray Crawford
  Creation Date:    11/15/2018

  Version 1.0 was tested on Windows 2012r2

.EXAMPLE
  ./Start-WPE.ps1
#>

# Create a Windows task (the first time, only)
$taskName = "stopFileMakerPro"
$taskExists = Get-ScheduledTask | Where-Object {$_.TaskName -like $taskName}
if ($taskExists) {
  # Do nothing
} else {
  # Create task
  $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
    -Argument '-NoProfile -WindowStyle Hidden -command "& {C:\Stop-FileMakerPro.ps1}"'
  $trigger = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 3) `
    -RepetitionDuration (New-TimeSpan -Days 9999)
  $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew
  $principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest

  Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName `
    -Principal $principal `
    -Description "Ensure FileMaker Pro isn't hung as a background process"
}

# The following returns $true if the process is running as an application
#  and $false if it is running in the background.

Add-Type @"
  using System;
  using System.Runtime.InteropServices;
  using System.Diagnostics;
  using System.ComponentModel;
  public class UserWindows {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
      [DllImport("user32.dll")]
      public static extern IntPtr GetWindowLong(IntPtr hWnd, int nIndex);
      public static bool hasWindowStyle(Process p) {
        IntPtr hnd = p.MainWindowHandle;
        UInt32 WS_DISABLED = 0x8000000;
        int GWL_STYLE = -16;
        bool visible = false;
        if (hnd != IntPtr.Zero)
          {
            System.IntPtr style = GetWindowLong(hnd, GWL_STYLE);
            visible = ((style.ToInt32() & WS_DISABLED) != WS_DISABLED);
          }
        return visible;
    }
  }
"@

$startTime = Get-Date
# See if there is a FileMaker process
$fmpro = Get-Process -Name "FileMaker Pro" -ErrorAction SilentlyContinue

if ($fmpro) {
  $done = $false
  while (! $done) {
    # Confirm we are still looking at the same process
    $newFmpro = Get-Process -Name "FileMaker Pro" -ErrorAction SilentlyContinue
    if ( ($newFmpro) -and ($newFmpro.Id -eq $fmpro.Id) -and ($newFmpro.Name -eq $fmpro.Name) ) {
      $foreground = [userwindows]::hasWindowStyle($fmpro)
    } else {
      $(Get-Date -Format o) + " The FileMaker Pro process changed since we started.  Exiting." | Out-File C:\Windows\Temp\Stop-FileMakerPro.log -Append
      exit
    }
    if ($foreground) {
      $(Get-Date -Format o) + " FMP is now running as a foreground process.  Exiting." | Out-File C:\Windows\Temp\Stop-FileMakerPro.log -Append
      $done = $true
    } else {
      $(Get-Date -Format o) + " FMP is running as a background process." | Out-File C:\Windows\Temp\Stop-FileMakerPro.log -Append
      $duration = New-TimeSpan -Start $startTime -End $(Get-Date)
      if (($duration.Seconds -gt 15) -and (! $foreground)) {
        $(Get-Date -Format o) + " FMP has been running for more than 15 seconds in background.  Killing " + $fmpro.Id | Out-File C:\Windows\Temp\Stop-FileMakerPro.log -Append
        $fmpro | Stop-Process -Force
        $done = $true
      } elseif ($duration.Seconds -lt 15) {
        $(Get-Date -Format o) + " FMP is a newly discovered background process.  Passing this rotation and sleeping." | Out-File C:\Windows\Temp\Stop-FileMakerPro.log -Append
        sleep 20
      } else {
        $done = $true
      }
    }
  }
}
