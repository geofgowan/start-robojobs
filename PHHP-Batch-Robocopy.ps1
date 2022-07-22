Function start-RoboJobs {
<#
Geof Gowan, geofg@phhp.ufl.edu
July 18, 2022
Use at your own risk. Do not be stupid. Robocopy is great, but can ruin your day. Check your work. Etc.

NOTE: PHHP pre-loads ACLS on destination folders so we *do not* copy ACLS by default. 
IF that's not what you do, adjust the robocopy flag defaults (lines 24 and 36) as appropriate.

#>
Param(
[Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$source,
[Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$destination,
[Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$logfolder,
[Parameter(Mandatory=$false)]
    [int]$maxjobs=4,
[Parameter(Mandatory=$false)]
    [string]$roboflags='/COPY:DATO /DCOPY:T /MIR /E /R:1 /W:1 /SL',	
[Parameter(Mandatory=$false)]
    [switch]$rerun,
[Parameter(Mandatory=$false)]
    [switch]$quiet
)

BEGIN {
# Direct path to Robocopy. This is usually in the system path, but just playing it safe. 
$RC = "$env:SystemRoot\System32\robocopy.exe"

# These are added to the Robocopy flags to reduce log output when the RERUN switch is used.
$rerunflags = ' /NP /NS /NC /NFL /NDL'

$starttime = get-date

# Make the various paths PS Objects rather than strings. 
$SourceDir = Get-Item $source
$DestinationDir = Get-Item $destination
$Logdir = Get-Item $logfolder

# This script will limit concurrent jobs based on MAXJOBS, which will be restricted to no more than 8.
# The Robocopy MultiThread value will be set based on maxjobs to *not* exceed a combined 128. 

if ($maxjobs -ge 9) {$maxjobs = 8} elseif ($maxjobs -lt 1){$maxjobs = 1}
$mt = [math]::floor(128 /$maxjobs)

# First Robocopy run should log everything. Use the -rerun for further jobs so less is logged and the log file sizes are reasonable.
# AGAIN NOTE: PHHP pre-loads ACLS on destination folders so we *do not copy ACLS by default. IF that's not what you do, adjust as appropriate. 
if (-not $rerun) {
    $roboflags = $roboflags + ' /MT:' + $mt
} else {
    $roboflags = $roboflags + $rerunflags + ' /MT:' + $mt
}

} #BEGIN

PROCESS {
$SubDirs = get-childitem $SourceDir.fullname -Directory -Force

#Get individual files at the top of the source folder first
$logname = $($SourceDir).name.replace(' ','_') + '-Top-level-files' # This makes robocopy happier with lognames.
$log = $LogDir.fullname + "\" + $(get-date -f yyyyMMddHHmm) + '-' + $logname + '.log' 
# Backticks escape the quote so directory paths with spaces are handled properly by Robocopy. Ugly, but does the job. 
$RCCmd = $RC + " `"" + $SourceDir.fullname.trim('\') + "`"" + " `"" + $DestinationDir.fullname.trim('\') + "`"" + ' /Lev:1 ' + $roboflags +' /LOG+:' + "`"" + $log + "`""
if (-not $quiet) {
    Invoke-Expression $RCCmd
} else {
    Invoke-Expression $RCCmd | Out-Null
}
$Feedback = ($SourceDir).fullname + " Top level files completed " + $(get-date) + ". Time: " + $(new-timespan (Get-Item $log).CreationTime (Get-Date)).ToString("h\h\:mm\m\:ss\s")
if (-not $quiet) {
    Write-Host $Feedback -ForegroundColor Cyan
}



#Now go through all the folders. This is where the real work happens.  
$SubdirCount = @($SubDirs).count
foreach ($dir in $SubDirs) {

    $jobs = Get-Job -State "Running"

    while ($jobs.count -ge $maxjobs) {
        Start-Sleep -Milliseconds 500
        $jobs = Get-Job -State "Running"
    }

    if (-not $quiet) {
        Get-job -State "Completed" | Receive-job
    }
    Remove-job -State "Completed"

# Start-Job creates a completely independent PS background session. As such, you have to pass parameters *and*
# tell the process what to do with them. Note the param list in the scriptblock and arg list in start-job.

    $ScriptBlock = {
  
        param($dir,$DestinationDir,$LogDir,$roboflags,$RC,$quiet)
        $newdir = $DestinationDir.fullname + "\" + $dir.name
		$logname = $dir.name.replace(' ','_') # This makes robocopy happier with lognames.
        $log = $LogDir.fullname + "\" + $(get-date -f yyyyMMddHHmm) + '-' + $logname + '.log'
		# Backticks escape the quote so directory paths with spaces are handled properly by Robocopy. Ugly, but does the job. 
        $RCCmd = $RC + " `"" + $dir.fullname + "`" `"" + $newdir + "`" " + $roboflags +' /LOG+:' + "`"" + $log + "`""
        Invoke-Expression $RCCmd
        $Feedback = $($dir).fullname + " completed " + $(get-date) + ". Time: " + $(new-timespan (Get-Item $log).CreationTime (Get-Date)).ToString("h\h\:mm\m\:ss\s")
        if (-not $quiet) {
            Write-Host $Feedback -ForegroundColor Cyan
        }
    }
    if (-not $quiet) {
        Start-Job $ScriptBlock -ArgumentList $dir,$DestinationDir,$LogDir,$roboflags,$RC,$quiet -Name $("RJ" + "$SubdirCount")
    }else {
        Start-Job $ScriptBlock -ArgumentList $dir,$DestinationDir,$LogDir,$roboflags,$RC,$quiet -Name $("RJ" + "$SubdirCount") | Out-Null
    }
    $SubdirCount--
}
} #PROCESS

END {
# Now that there are no more jobs to process. Wait for all of them to complete. 

$jobcount = @(Get-Job).count

While ($jobcount -gt 0) { 
    Start-Sleep -Milliseconds 500
    $jobcount = @(Get-Job).count 
	if (-not $quiet) {
		Get-job -State "Completed" | Receive-job
	}
	Remove-Job -State "Completed"
}

$endtime = get-date

$ElapsedTime = $(new-timespan -start $starttime -end $endtime).ToString("dd\d\:hh\h\:mm\m\:ss\s")
if (-not $quiet) {
    # Spit out how long it took in a somewhat readable format.
    Write-Host "-" -ForegroundColor Cyan
    Write-Host "Total Elapsed Time: " -ForegroundColor Cyan -NoNewline
    Write-Host $ElapsedTime -ForegroundColor Magenta
    Write-Host "-" -ForegroundColor Cyan
    Write-Host "Start checking the logs with: " -ForegroundColor Cyan
    $logcheck = "Get-ChildItem " + "`"" + $logfolder + "`"" + '-File -Filter *.log | ForEach-Object {Get-Content $_.fullname |?{$_ -cmatch "ERROR|`t`t"}}'
    Write-Host $logcheck -ForegroundColor Yellow
}

} #END

<#
.SYNOPSIS
This is a wrapper for the Windows ROBOCOPY tool. It will scan a given directory and job out 
multiple robocopy processes to copy your source content more efficiently.

.DESCRIPTION
This will use robocopy to move files into the source directory you provide. It will then job out 
separate robocopy processes for each of the top-level SUBfolders of the source directory. This is 
more efficient than just increasing the multi-threading on a single robocopy process.

NOTE: PHHP pre-loads ACLS on destination folders so we *do not* copy ACLS by default. 
IF that's not what you do, adjust the robocopy flags on lines 24 and 36 as appropriate.

If you want to quickly check for errors in the log output, use this:
	Get-ChildItem "LOG FOLDER" | Foreach-Object {Get-Content $_.FullName |?{$_ -match "ERROR"}}
If you're using the -rerun flag and just want to see which logs have entries, use this:
	Get-ChildItem "LOG FOLDER" | Foreach-Object {Get-Content $_.Fullname|?{$_ -match "`t`t"}}
These can be combined like so: 
	Get-ChildItem "LOG FOLDER" | Foreach-Object {Get-Content $_.Fullname|?{$_ -match "ERROR|`t`t"}}

.PARAMETER  source
This is a STRING path to your Robocopy SOURCE folder. If you have spaces, put it in quotes. 

.PARAMETER destination
This is a STRING path to your Robocopy DESTINATION folder. If you have spaces, put it in quotes

.PARAMETER logfolder
This is a STRING path to your Robocopy LOG location folder. If you have spaces, put it in quotes. 

.PARAMETER maxjobs
This is a NUMBER between 1 and 8. It will set how many concurrent jobs to run. 

.PARAMETER roboflags
This is a base default for Robocopy flags: /COPY:DATO /DCOPY:T /MIR /E /R:1 /W:1 /SL
You can set these to other than default by adding crafting them inside quotes with this flag.
The calcuated MT value and log location will be added based on the MAXJOBS and LOGFOLDER parameters. 
Don't add them here.

.PARAMETER rerun
This SWITCH changes the ROBOCOPY FLAGS to be less verbose by adding '/NP /NS /NC /NFL /NDL ' to the 
robocopy flags, default or customized. 
}

.PARAMETER quiet
This SWITCH will reduce the console output chatter

.EXAMPLE
Start-Robojobs -source "Source Folder" -destination "Destination Folder" -logfolder "Log Folder" 
	Will run with normal output to the console and verbose logging
.EXAMPLE
Start-Robojobs -source "Source Folder" -destination "Destination Folder" -logfolder "Log Folder" -rerun
	Will run with normal console output and reduced output in the logs.
.EXAMPLE
Start-Robojobs -source "Source Folder" -destination "Destination Folder" -logfolder "Log Folder" -rerun -quiet
	Will run with reduced console output and reduced logging.
.LINK
Robocopy quick reference: https://ss64.com/nt/robocopy.html
Robocopy reference: https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
Original inspiration: https://community.spiceworks.com/topic/1691932-fastest-way-to-copy-millions-of-little-files-fastcopy

.NOTES

The logic in this function is based off of a SpiceWorks community post. See the "original inspiration" link.
 
Here's what that script had to say:

This script runs robocopy jobs in parallel by increasing the number of outstanding i/o's to the copy process. Even though you can
change the number of threads using the "/mt:#" parameter, your backups will run faster by adding two or more jobs to your
original set. 

To do this, you need to subdivide the work into directories. That is, each job will recurse the directory until completed.
The ideal case is to have 100's of directories as the root of the backup. Simply change $src to get
the list of folders to backup and the list is used to feed $ScriptBlock.
 
For maximum SMB throughput, do not exceed 8 concurrent Robocopy jobs with 20 threads. Any more will degrade
the performance by causing disk thrashing looking up directory entries. Lower the number of threads to 8 if one
or more of your volumes are encrypted.

Parameters:
$src Change this to a directory which has lots of subdirectories that can be processed in parallel 
$dest Change this to where you want to backup your files to
$max_jobs Change this to the number of parallel jobs to run ( <= 8 )
$log Change this to the directory where you want to store the output of each robocopy job.
#>

} 