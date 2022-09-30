# start-robojobs
Powershell function to efficiently parallelize robocopy

# SYNOPSIS

This is a wrapper for the Windows ROBOCOPY tool. It will scan a given directory and job out 
multiple robocopy processes to copy your source content more efficiently.

# DESCRIPTION

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

# PARAMETERS  

	-source

This is a STRING path to your Robocopy SOURCE folder. If you have spaces, put it in quotes. 

	-destination

This is a STRING path to your Robocopy DESTINATION folder. If you have spaces, put it in quotes

	-logfolder

This is a STRING path to your Robocopy LOG location folder. If you have spaces, put it in quotes. 

	-maxjobs

This is a NUMBER between 1 and 8. It will set how many concurrent jobs to run. 

	-roboflags

This is a base default for Robocopy flags: /COPY:DATO /DCOPY:T /MIR /E /R:1 /W:1 /SL
You can set these to other than default by adding crafting them inside quotes with this flag.
The calcuated MT value and log location will be added based on the MAXJOBS and LOGFOLDER parameters. 
Don't add them here.

	-rerun

This SWITCH changes the ROBOCOPY FLAGS to be less verbose by adding '/NP /NS /NC /NFL /NDL ' to the 
robocopy flags, default or customized. 

	-quiet

This SWITCH will reduce the console output chatter

# EXAMPLES

	Start-Robojobs -source "Source Folder" -destination "Destination Folder" -logfolder "Log Folder" 

Will run with normal output to the console and verbose logging

	Start-Robojobs -source "Source Folder" -destination "Destination Folder" -logfolder "Log Folder" -rerun

Will run with normal console output and reduced output in the logs.

	Start-Robojobs -source "Source Folder" -destination "Destination Folder" -logfolder "Log Folder" -rerun -quiet

Will run with reduced console output and reduced logging.

# EXTERNAL RESOURCES

Robocopy quick reference: https://ss64.com/nt/robocopy.html

Robocopy reference: https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy

Original inspiration: https://community.spiceworks.com/topic/1691932-fastest-way-to-copy-millions-of-little-files-fastcopy

# NOTES

The logic in this function is based off of a SpiceWorks community post. See the "original inspiration" link.
 
Here's what that script had to say:

"This script runs robocopy jobs in parallel by increasing the number of outstanding i/o's to the copy process. Even though you can
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

$log Change this to the directory where you want to store the output of each robocopy job."
