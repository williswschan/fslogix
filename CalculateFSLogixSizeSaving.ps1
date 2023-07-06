<#
.SYNOPSIS
This script is to evaluate the size saving by converting user local profile to FSLogix profile container

.DESCRIPTION
N/A

.NOTES
  Version:          1.0
  Author:           Manuel Winkel <www.deyda.net>
  Rewrite Author:   Willis Chan
  Rewrite Date:    2023-07-06
  Purpose/Change:
  NOTE: This only works between like profile versions. eg. You can’t migrate your 2008R2 profiles to Server 2016 and expect it to work.
        This requires using frx.exe, which means that FSLogix needs to be installed on the server that contains the profiles. The script will create the folders in the USERNAME_SID format, and set all proper permissions.
        Use this script. Edit it. Run it (as administrator) from the Citrix server. It will pop up this screen to select what profiles to migrate.
#>

#########################################################################################
# Setup Parameter first here newprofilepath
# Requires -RunAsAdministrator
# Requires FSLogix Agent (frx.exe)
#########################################################################################

$VHDPath = [System.Environment]::GetEnvironmentVariable('TEMP')
$UserProfiles = gci c:\users | ? { $_.psiscontainer -eq $true } | select -Expand fullname | sort | out-gridview -OutputMode Multiple -title "Please Select Profile(s) To Evaluate"

Write-Host
foreach ($UserProfile in $UserProfiles) {
	
  $SAM = ($UserProfile | split-path -leaf)
  Try { $SID = (New-Object System.Security.Principal.NTAccount($SAM)).translate([System.Security.Principal.SecurityIdentifier]).Value}
  Catch {
    Write-Host $Error[0] -ForegroundColor Red
    Write-Host
    Break
  }
  $FSLogixProfileFolder = join-path $VHDPath ($SAM + "_" + $SID)

  # if $FSLogixProfileFolder doesn't exist - create it with permissions
  Write-Host "Creating & granting permissions to new created fslogic folder & virtual disk..." -ForegroundColor Green
  if (!(test-path $FSLogixProfileFolder)) { New-Item -Path $FSLogixProfileFolder -ItemType directory | Out-Null }
  & icacls $FSLogixProfileFolder /setowner "$env:userdomain\$SAM" /T /C
  Write-Host
  & icacls $FSLogixProfileFolder /grant $env:userdomain\$SAM`:`(OI`)`(CI`)F /T
  Write-Host

  Write-Host "Calculating user profile size on disk..." -ForegroundColor Green
  $LocalProfileSize = gci $UserProfile -Force -Recurse | ? { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum
  Write-Host

  # sets vhd to \\nfolderpath\profile_username.vhdx (you can make vhd or vhdx here)
  $VHD = Join-Path $FSLogixProfileFolder ("Profile_" + $SAM + ".vhdx")
  Write-Host "Copying profile to virtual disk..." -ForegroundColor Green
  $Message = & "$PSScriptRoot\frx.exe" copy-profile -filename $VHD -sid $SID -dynamic 1
    If ($Message -match "Success" ) {
    Write-Host $Message
  } else {
    Write-Host $Message -ForegroundColor Red
    Write-Host
    Break
  }
  Write-Host
  
  #Write-Host "Shrinking virtual disk..." -ForegroundColor Green
  #& "$(Split-Path $MyInvocation.MyCommand.Path)\Invoke-FslShrinkDisk.ps1" -Path $VHD
  #Write-Host

  Write-Host "Calculating fslogix virtual disk size..." -ForegroundColor Green
  $FSLogixDiskSize = (gi $VHD).Length
  Write-Host

  $LocalProfileSizeRoundUp = "{0:N2} MB" -f ($LocalProfileSize.Sum / 1MB)
  $FSLogixDiskSizeRoundUp = "{0:N2} MB" -f ($FSLogixDiskSize / 1MB)
  Write-Host "$($SAM) Profile Size`t $($LocalProfileSizeRoundUp)"
  Write-Host "$($SAM) VHDX Size`t`t $($FSLogixDiskSizeRoundUp)"
  $SavingRatio = ($LocalProfileSize.Sum - $FSLogixDiskSize) / $LocalProfileSize.Sum * 100
  $SavingRoundUp = "{0:N2}%" -f ($SavingRatio)
  Write-Host "Size Saving Percentage`t`t $($SavingRoundUp)"
  Write-Host

  Write-Host "Removing virtual disk..." -ForegroundColor Green
  & cmd.exe /c rmdir /s /q $FSLogixProfileFolder
  Write-Host
  
}
