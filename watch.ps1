function Test-FileLock {
  param (
    [parameter(Mandatory=$true)][string]$Path
  )

  $oFile = New-Object System.IO.FileInfo $Path

  if ((Test-Path -Path $Path) -eq $false) {
    return $false
  }

  try {
    $oStream = $oFile.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

    if ($oStream) {
      $oStream.Close()
    }
    return $false
  } catch {
    # file is locked by a process.
    return $true
  }
}

function Join-ArrayPath
{
   param([parameter(Mandatory=$true)]
   [string[]]$PathElements) 
   if ($PathElements.Length -eq "0")
   {
     $CombinedPath = ""
   }
   else
   {
     $CombinedPath = $PathElements[0]
     for($i=1; $i -lt $PathElements.Length; $i++)
     {
       $CombinedPath = Join-Path $CombinedPath $PathElements[$i]
     }
  }
  return $CombinedPath
}


function RemuxToMp4{
  param(
    [parameter(Mandatory=$true)][string]$Path,
    [parameter(Mandatory=$true)][string]$OutputDirectory
  )

  Write-Host "Remux-To-MP4"

  $sourceFile = Get-Item $Path
  if($sourceFile.Extension -eq ".mp4"){
    Write-Host "File is already an MP4, returning..."
    return
  }
  $sourceDirectory = $sourceFile.DirectoryName
  $sourceFileWithoutExt = $sourceFile.BaseName
  $fullPathWithoutExt = join-path $sourceDirectory $sourceFileWithoutExt
  Write-Host ($fullPathWithoutExt)

  $outputFilePath = Join-ArrayPath $OutputDirectory, "$sourceFileWithoutExt.mp4"

  Write-Host ($outputFilePath)

  $ArgumentList = "-i {0} -c copy -map 0 -video_track_timescale 60 {1}" -f $sourceFile, $outputFilePath

  Write-Host -ForegroundColor Green -Object $ArgumentList

  # Pause the script until user hits enter
  # $null = Read-Host -Prompt 'Press enter to continue, after verifying command line arguments.';

  # Start ffmpeg

  Start-Process -FilePath "E:\Tools\FFMPEG\ffmpeg.exe" -ArgumentList $ArgumentList -Wait -NoNewWindow

}

$PathToMonitor = "$PSScriptRoot\..\Input\"
$OutputDirectory = "$PSScriptRoot\..\Output\"

$FileSystemWatcher = New-Object System.IO.FileSystemWatcher
$FileSystemWatcher.Path = $PathToMonitor
$FileSystemWatcher.IncludeSubdirectories = $true

#emit events
$FileSystemWatcher.EnableRaisingEvents = $true


#define the action that is executed when a change is detected
$Action = {
    $details = $event.SourceEventArgs
    $Name = $details.Name    
    $FullPath = $details.FullPath
    $OldFullPath = $details.OldFullPath
    $OldName = $details.OldName
    $ChangeType = $details.ChangeType
    $Timestamp = $event.TimeGenerated
    $text = "{0} was {1} at {2}" -f $FullPath, $ChangeType, $Timestamp
    Write-Host ""
    Write-Host $text -ForegroundColor Green

    switch($ChangeType){
        'Changed' {"CHANGE"}
        'Created' {"CREATED"
            Write-Host "Checking to see if file is locked"
            $locked = Test-FileLock -Path $FullPath
            Write-Host "$locked"
            while($locked){
              $locked = Test-FileLock -Path $FullPath
              Write-Host "$locked"
              Wait-Event -Timeout 5
            }
            RemuxToMp4 -Path $FullPath -OutputDirectory $OutputDirectory
        }
        'Deleted' {"DELETED"         
        # uncomment the below to mimick a time intensive handler
        <#
        Write-Host "Deletion Handler Start" -ForegroundColor Gray
        Start-Sleep -Seconds 4    
        Write-Host "Deletion Handler End" -ForegroundColor Gray
        #>
        }
        'Renamed' {
            #this executes only when a file was renamed
            $text = "File {0} was renamed to {1}" -f $OldName, $Name
        }
        default { Write-Host $_ -ForegroundColor Red -BackgroundColor White}
    }
}

# add event handlers
$handlers = . {
    Register-ObjectEvent -InputObject $FileSystemWatcher -EventName Changed -Action $Action -SourceIdentifier FSChange
    Register-ObjectEvent -InputObject $FileSystemWatcher -EventName Created -Action $Action -SourceIdentifier FSCreate
    Register-ObjectEvent -InputObject $FileSystemWatcher -EventName Deleted -Action $Action -SourceIdentifier FSDelete
    Register-ObjectEvent -InputObject $FileSystemWatcher -EventName Renamed -Action $Action -SourceIdentifier FSRename
}

Write-Host "Monitoring $PathToMontior"

try{
    do{
        Wait-Event -Timeout 1
        Write-Host "." -NoNewline
    } while($true)
}
finally{
    # this gets executed when the user presses ctrl+c
    # remove the event handlers
    Unregister-Event -SourceIdentifier FSChange
    Unregister-Event -SourceIdentifier FSCreate
    Unregister-Event -SourceIdentifier FSDelete
    Unregister-Event -SourceIdentifier FSRename

    # remove background jobs
    $handlers | Remove-Job
    # remove filesystem watcher
    $FileSystemWatcher.EnableRaisingEvents = $false
    $FileSystemWatcher.Dispose()
    "Event Handler Disabled."
}