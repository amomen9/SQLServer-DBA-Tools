# \#SQLServer
T-SQL Scripts


License: Please do whatever you wish with these files!!! :smile::laughing: Just please include the Author tag.
If you wish to contribute to the codes or have any suggestions or want to report a flaw,
please give me an email at amomen@gmail.com

#### Changes in version 1.0:
```
1. The scripts turned into stored procedures.
2. Added some features.
```

## Contained Scripts

#### 1. Backup Website:

This script performs a full backup of the database and home folder files of the intended website. It can be turned into a
scheduled job to run at specific schedules. The DB backup file name will be in 'DBName_Date_Time + .bak' format.
The home folder backup has a similar name. A checkdb will also be performed prior to the database backup. 

###### System requirements:
SQL Server Compatibility: This script is designed to comply with SQL Server 2008 R2 and later. Earlier versions are not tested.
This script utilizes 7zip version 19.0, so install 7-zip first, which is an open source and multiplatform compression software.
Sample 7zip commands
	for compression:
	7z a -tzip -mx9 -mmt4 -y -bd -ssw -stl  -p1234 "D:\Website Backup\DBNAME_21.03.10_0500\DBNAME_File Backup_21.03.10_0500.zip" "C:\inetpub\wwwroot\*"
	for extraction:
	7z x -aoa -spe -p1234 -o"C:\inetpub\wwwroot" "D:\Website Backup\DBNAME_21.03.10_0500\DBNAME_File Backup_21.03.10_0500.zip"
For information regarding 7zip commands and switches please refer to 7zip's manual.

This script also checks for the modification of Database's data files on SQL Server 2016 and later. If the modification is less than 60 pages,
no backup is performed. This number is experimental. To backup regardless, simply set threshold to 0. There will be
only one output file for database backup. For security reasons, the script enables the extended stored procedure xp_cmdshell
and disables it again immediately once the procedure is finished executing. Using website files' archive password is
recommended and this script does not offer an option not to set a password.															

###### Attention: 

	1. This script does not backup home folder on Non-Windows host operating systems, as xp_cmdshell is only
	available on windows by SQL Server 2019
	2. Please do not put anything else inside the backup directory manually or automatically, as it may interfere with
	restore script's functionality and completely wreck the operation.
	3. As leaving xp_cmdshell enabled may have security risks, especially for the backup jobs which are meant to be scheduled
	to be triggered at special times, and compressing or decompressing files is time-consuming, this script does not wait for
	the compression or extraction process to complete and then disable xp_cmdshell. It launches a parallel script implicitly
	to disable xp_cmdshell immidiately after it starts. In other words, xp_cmdshell only remains enabled for a very short
	time. It was less than 0.3 second on my computer.

For the restore operation, please use Restore_SQL_Server_Website_sp.sql script.

#### 2. Restore Website:

Before using this script, please read the comments at the beginning of Backup_Website.sql script thoroughly.
This script restores the backups performed by the Backup_Website.sql script. You can also specify the destination
database. If you don't specify the destination database, the database will be restored on its own. This script
probes inside the backup folder and extracts and restores the latest backup. If the database is to be restored
on its own, a tail of log backup will be taken first, if the database does not have SIMPLE or Pseudosimple
recovery model. For the files restore, it overwrites all the files in the destination. By default, the last 
backup set will be restored, by probing into the backups directory and ignoring the history records of SQL Server
msdb database. But you can specify the backup location manually. The names are case-insensitive. As the restore
of Website files is normally time-consuming, the database will be kept in restoring state until the whole script
is completed. For security reasons, the script enables the extended stored procedure xp_cmdshell
and disables it again immediately once the procedure is finished executing.

###### System requirements:
SQL Server Compatibility: This script is designed to comply with SQL Server 2008 R2 and later. Earlier versions are not tested.
This script utilizes 7zip, so install 7-zip first, which is an open source and multiplatform compression software.
Sample 7zip commands
	for compression:
	7z a -tzip -mx9 -mmt4 -y -bd -ssw -stl  -p1234 "D:\Website Backup\21.03.10_0500\DBNAME_File Backup_21.03.10_0500.zip" "C:\inetpub\wwwroot\*"
	for extraction:
	7z x -aoa -spe -p1234 -o"C:\inetpub\wwwroot" "D:\Website Backup\21.03.10_0500\DBNAME_File Backup_21.03.10_0500.zip"
For information regarding 7zip commands and switches please refer to 7zip's manual.

###### Attention: 	

	1. Please do not put anything else inside the backup directory or any of its subdirectories manually or automatically, 
	as it may interfere with this script's functionality and completely wreck the operation. The backup root '@Backup_root'
	must be exclusively dedicated to Backup_Website.sql and this script.
	2. This script is designed to restore one website at a time. If you have multiple websites on your server you
	must restore each separately.
	3. Please make sure SQL service has required permission to the paths you specify. Otherwise the script will fail. If the output paths do not
	exist, the script automatically creates them.
	4. This script does not restore home folder on Non-Windows host operating systems, as xp_cmdshell is only
	available on windows by SQL Server 2019
	5. This script does not support restoring from more than one backup file.
	6. If you restore the database to a new name and it already exists, some errors might occur. This script does
	not handle such a case.
	7. As leaving xp_cmdshell enabled has security risks, especially for the backup jobs which are meant to be scheduled
	to be triggered at special times, and compressing or decompressing files is time-consuming, this script does not wait for
	the compression or extraction process to complete and then disable xp_cmdshell. It launches a parallel script implicitly
	to disable xp_cmdshell immidiately after it starts. In other words, xp_cmdshell only remains enabled for a very short
	time. It was less than 0.3 second on my computer.
	8. If the database is to be restored on its own, this script automatically kills all sessions connected to the database except
	the current session, before restoring the database. The database will be returned to MULTI_USER at the end.

For the backup operation, please use Backup_SQL_Server_Website_sp.sql script.
