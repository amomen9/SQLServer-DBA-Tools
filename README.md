# \#SQLServer
T-SQL Scripts


License: Please do whatever you wish with these files!!! :D Just please include the Author tag.
If you wish to contribute to the codes or have any suggestions or want to report a flaw,
please give me an email at amomen@gmail.com
These scripts are generally for SQL Server's general purposes. For full corresponding instructions for each script,
please refer to the README.md file included in its folder.

## Contained Scripts

#### 1. Backup Website (Within T-SQL_Backup&Restore folder):

```
This script performs a full backup of the database and home folder files of the intended website. It can be turned into a
scheduled job to run at specific schedules. The DB backup file name will be in 'DBName_Date_Time + .bak' format.
The home folder backup has a similar name. A checkdb will also be performed prior to the database backup. 
```

#### 2. Restore Website (Within T-SQL_Backup&Restore folder):

```
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
```
