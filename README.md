![](https://img.shields.io/badge/-%23FFFFFF.svg?&style=flat-square&logo=Microsoft%20SQL%20Server&logoColor=red)<b>SQL Server</b>


# \#SQLServer DBA Tools



[![license badge]][license]


[license badge]:https://img.shields.io/badge/license-%20MIT%20-blue


[license]:https://github.com/amomen9/SQLServer-DBA-Tools/blob/main/LICENSE

<br/>


T-SQL Scripts

* LICENSE:
  MIT as noted. If you wish to contribute to this repository's codes or have any suggestions or want to report a flaw, please give me an email at [amomen@gmail.com](mailto:amomen@gmail.com) or report on GitHub. I'd be appreciative
* These scripts are for SQL Server's general purposes. For corresponding instructions for each script, please read them below.
* The scripts are not pretty much optimized where they don't need to be.
* Some scripts (I believe a few) might seem simple (they are put inside the "Educational" directory), but they carry useful tricky ideas
* If you like the codes, please spread the word and connect me on Linkedin at [https://www.linkedin.com/in/ali-momen](https://www.linkedin.com/in/ali-momen) and star this repository if you like.
* Please have a look at my website if you wish at [https://amdbablog.blogspot.com/](https://amdbablog.blogspot.com/)
* Most of the stored procedures start with "sp_" in the name instead of "usp_". That's how I have been more convenient. You can change the name of course.
* General note: T-SQL is not optimized when it comes to heavy workloads and may become partly the bottleneck of your tasks unless you natively compile and optimize it. This does not usually happen in OLTP systems though. You just may want to bear this in mind.
* Some codes may not have been well refactored, cleaned, and commented on yet. Though they will be some time in the future, and mostly I don't believe they are hard to understand right now, and the variables' namings are helpful.
* Some scripts contained within this repository are not mentioned in this readme file yet.

## Contained Scripts

[](https://github.com/amomen9/SQLServer-DBA-Tools#contained-scripts)

1. sp_restore_latest_backups

   Effortlessly probe for backup files within a folder recursively and restore the ones that you want to whatever point in time or to the latest log backup available, on an instance, either from scratch or to replace the existing one.The idea for this script comes from my SQL Server professor P.Aghasadeghi ([http://fad.ir/Teacher/Details/10](http://fad.ir/Teacher/Details/10)). This stored procedure restores the latest backups from backup files accessible to the server. As the server is not the original producer of these backups, there will be no records of these backups in MSDB. The records can be imported from the original server anyway but there would be some complications. This script probes recursively inside the provided directory, extracts all the full or read-write backup files, and optionally probes for log backups for point-in-time recovery or restoring to a later moment than the last full backup, reads the database name and backup dates from these files and restores the latest backup of every found database within the given criteria. If the database already exists, a tail of log backup can be taken first. A sample Standard Output of the execution is within the sp_restore_latest_backups directory.**Applications:**1. Automation of restoring the backups on the development or staging servers and carrying out the post-restore operations automatically like changing the recovery model, setting the database as read-only, shrinking database files, granting high permissions to every user of the database, rebuilding log file, etc.2. Granting execute access on this SP to senior developers on the development instances, so that they can renew or PITR their databases whenever they require without the need for DBAs' intervention or their direct access to the backup files/repository.3. Keep history and track of who restored what database, when, which backup, to what point in time, other restore details, etc.

 **Example:**

```tsql
EXEC sp_restore_latest_backups 

	@Destination_Database_Name_suffix = N'_test',
  										-- (Optional) You can specify the destination database names' suffix here. If the destination database name is equal to the backup database name,
  										-- the database will be restored on its own. 
	@Destination_Database_Name_prefix = N'',
  										-- (Optional) You can specify the destination database names' prefix here. If the destination database name is equal to the backup database name,
  										-- the database will be restored on its own. 
	@Destination_DatabaseName = N'',	-- This option only works if you have only one database to restore, otherwise it will be ignored. Prefix and suffix options will also be applied.
	@Ignore_Existant = 0,	
										-- (Optional) Ignore restoring databases that already exist on target. If set to 0, the existant will be replaced.
	@Destination_Database_DataFiles_Location = 'D:\Database Data',
										--'D:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\',	
  										-- (Optional) This script creates the folders if they do not exist automatically. Make sure SQL Service has permission to create such folders
  										-- This variable must be in the form of for example 'D:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\DATA'. If left empty,
										-- the datafiles will be restored to destination servers default directory. If given 'same', the script will try to put datafiles to
										-- exactly the same path as the original server. One of the situations that you can benefit from this, is if your destination server
										-- has an identical structure as your original server, for example it's a clone of it.
										-- if this parameter is set to 'same', the '@Destination_Database_LogFile_Location' parameter will be ignored.
										-- Possible options: 'SAME'|''|'Some Path'. '' or NULL means target server's default
	@Destination_Database_LogFile_Location = 'D:\Database Log',
										-- (Optional) If @Destination_Database_DataFiles_Location parameter is set to same, the '@Destination_Database_LogFile_Location' parameter will be ignored.
										-- Possible options: 'SAME'|''|'Some Path'. '' or NULL means target server's default

	@Backup_root_or_path = --'%userprofile%\desktop',
					N'D:\Database Backup\',			
					--N'"D:\Database Backup\NW_Full_backup_0240.bak"',
										-- (*Mandatory) Root location for backup files. You can also specify a single file.
										-- Possible options: ''|'Some Path'. '' or NULL means target server's default

	------ Begin file processing speed-up parameters: ---------------------------------------------------------------------------
	-- These parameters are not mandatory, anyhow you need to carefully read the instructions before you can use them.
	-- For less than 300 files in your repository, these parameters will be ignored.
	@BackupFileName_naming_convention = --'',
										N'[{"BackupType": "FUL","NamingConvention":"DBName_BackupType_ServerName_TIMESTAMP.ext","Separator":"_","Transform":"STUFF(STUFF(STUFF(STUFF(TIMESTAMP,5,0,''.''),8,0,''.''),11,0,'' ''),14,0,'':'')+'':00''"}, {"BackupType": "ALL","NamingConvention":"DBName_BackupType_TIMESTAMP.ext","Separator":"_","Transform":"STUFF(STUFF(STUFF(STUFF(TIMESTAMP,5,0,''.''),8,0,''.''),11,0,'' ''),14,0,'':'')+'':00''"}]',
										--N'DBName_BackupType_TIMESTAMP.ext',
										/*
										-- (Optional) Causes file scouring to speed up, if you have too many files in the directory, (for less than 400 files it's unnecessary)
										-- JSON format. You can define multiple conventions. Every JSON collection is a convention definition.
										-- Use the exact keywords for the following:
										--		1. BackupType: {"LOG" | "DIF" | "FUL" | "ALL"} for the backup type of the specific naming convention,
										--		2. NamingConvention: File name: "DBName" for database name, "TIMESTAMP" for backup start date, ".ext" for backup extension, "ServerName" for
										--			Server's Name etc. in the file's name. DBName and TIMESTAMP are mandatory. If you do not include .ext, the sp will assume that your backup
										--			files do not have extension.
										--		3. Separator: File name keywords' separator ("_" in the example) 
										--		4. Transform: Transform inline function to transform the timestamp part of your file names' string into standard datetime format. Use the keyword "TIMESTAMP" inside 
										--			this transform.(You do not need to include CONVERT or CAST functions) 
										-- This script compares the dates to find intended backups.
										-- Example: 
										--			'TLog:DBName_BackupType_ServerName_TIMESTAMP.ext:_:STUFF(STUFF(STUFF(STUFF(TIMESTAMP,5,0,''.''),8,0,''.''),11,0,'' ''),14,0,'':'')+'':00''; DBName_BackupType_TIMESTAMP.ext:_:STUFF(STUFF(STUFF(STUFF(TIMESTAMP,5,0,''.''),8,0,''.''),11,0,'' ''),14,0,'':'')+'':00'''
										-- Note: DBName and TIMESTAMP are mandatory if this option is used.
								
										*/
										-- Our company's naming convention: dbWarden_FULL_BI-DB_202206010018.bak

	@Skip_Files_That_Do_Not_Match_Naming_Convention = 1,
										-- After processing the file names, some files may remain that have not matched the defined naming convention(s) and consequently
										-- their database name, TIMESTAMP or other details have not been detected. These files can be scanned using reading of their headers
										-- , which is slower (default behavior), or skipped if this option is set to 1.
	------ End file processing speed-up parameters: -----------------------------------------------------------------------------

	@BackupFileName_RegexFilter = '',		
										-- (Optional) Use this filter to speed file scouring up, if you have too many files in the directory.

	@BackupFinishDate_StartDATETIME = '',
								
										-- (Optional)
	@BackupFinishDate_EndDATETIME = '',
								
										-- (Optional)
	@USE_SQLAdministrationDB_Database = 1,		
										-- (Optional, Highly Recommended to be set to 1) Create or Update DiskBackupFiles table inside SQLAdministrationDB database for faster access to backup file records and their details.

	@Exclude_system_databases = 1,		-- (Optional) set to 1 to avoid system databases' backups
	@Exclude_DBName_Filter = N'  %adventure%,  %DW%',			
										-- (Optional) Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
										-- N'Northwind,AdventureWorks, StackOverFlow'. The script excludes databases that contain any of such keywords
										-- in the name like AdventureWorks2019. Note that space at the begining and end of the names will be disregarded. You
										-- can also include wildcard characters "%" and "_" for each entry. The escape carachter for these wildcards is "\"
										-- The @Exclude_DBName_Filter outpowers @Include_DBName_Filter.
  
	@Include_DBName_Filter = N'',
										-- (Optional) Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
										-- N'Northwind,AdventureWorks, StackOverFlow'. The script includes databases that contain any of such keywords
										-- in the name like AdventureWorks2019 and excludes others. Note that space at the begining and end of the names
										-- will be disregarded. You can also include wildcard character "%" and "_" for each entry. The escape carachter for 
										-- these wildcards is "\".
							

	@IncludeSubdirectories = 1,			-- (Optional) Choose whether to include subdirectories or not while the script is searching for backup files.

	------------ Begin Log backup restore related parameters: -------------------------------------------------
	@Restore_Log_Backups = 1,			-- (Optional)
	@LogBackup_root_or_path = N'',
										-- (Optional) If left undefined, the script will assume that the log backups root is the same as the full
										-- backups' root
	@StopAt = '2022.08.17 20:35:18',
										-- (Optional)
	------------ End Log backup restore related parameters: ---------------------------------------------------

	@Keep_Database_in_Restoring_State = 0,				
										-- (Optional) If equals to 1, the database will be kept in restoring state
	@Take_tail_of_log_backup_of_existing_database = 0,
										-- (Optional, important)				
	@DataFileSeparatorChar = '_',
										-- (Optional) This parameter specifies the punctuation mark used in data files names. For example "_"
										-- in 'NW_sales_1.ndf' or "$" in 'NW_sales$1.ndf'.
	@Change_Target_RecoveryModel_To = 'same',
										-- (Optional) Set this variable for the target databases' recovery model. Possible options: FULL|BULK-LOGGED|SIMPLE|SAME
								
	@Set_Target_Databases_ReadOnly = 0,
										-- (Optional)
	@STATS = 50,
										-- (Optional) Report restore percentage stats in SQL Server restore process.
	@Generate_Statements_Only = 0,
										-- (Optional) use this to generate restore statements without executing them.
	@Delete_Backup_File = 0,
										-- (Optional) Turn this feature on to delete the backup files that are successfully restored. (This does not apply to transaction log backup files)
	@Activate_Destination_Database_Containment = 1,
										-- (Optional, but error will be raised for backups of partially contained databases if 'contained database authentication' has not been activated,
										-- you try to restore backups of partially contained databases and this option has not been turned to 1 on the target server)
	@Stop_On_Error = 0,					-- (Optional) Stop restoring databases should a retore fails
	@ShrinkDatabase_policy = 0,			-- (Optional) Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave %x of free space after shrinking 
	@ShrinkLogFile_policy = -2,			-- (Optional) Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave x MBs of free space after shrinking.
										-- Using @ShrinkDatabase_policy and @ShrinkLogFile_policy may be redundant for log file if the same option for both is specified.
	@RebuildLogFile_policy = '2MB:64MB:1024MB',
										-- (Optional) Possible options: NULL or Empty string: Do not rebuild | 'x:y:z' (For example, 4MB:64MB:1024MB) rebuild to SIZE = x, FILEGROWTH = y, MAXSIZE = z. If @RebuildLogFile_policy is specified, @ShrinkLogFile_policy will be ignored.
										-- Note: There is no risk of 'Transactional inconsistency', in this stored procedure specifically, despite the warning message that Microsoft may generate and you do not need to run CHECKDB for this in particular. Also, the extra log files have been deleted.

	@GrantAllPermissions_policy = -2	-- (Optional) Possible options: -2: Do not alter permissions | 1: Make every current DB user, a member of db_owner group | 2: Turn on guest account and make guest a member of db_owner group

```

---

2. sp_MoveDatabases_Datafiles

   Effortlessly and robustly with minimum down time, move your databases' database files to another folder and then automatically bring them back online using this stored procedure. It supports databases with FILESTREAM/IN-MEMORY filegroups as well. You can also change the location of your tempdb database database files, after which a SQL Server service restart is required to put the change into effect. You can also specify multiple databases. If you want to move tempdb database files, you must not include any other database.Upcoming: Most of the times move command is used to rename files/directories. I want to add this feature to this sp.
   
   
   **Example:**

```tsql
EXEC dbo.sp_MoveDatabases_Datafiles 
		@DatabasesToBeMoved = '',				-- enter database's name, including wildcard character %. Leaving this empty or null means all databases except some certain databases. This script can only work for tempdb in system databases. 
		@New_Datafile_Directory = '',				-- nvarchar(300), if left empty, data files will not be moved
		@New_Logfile_Directory = 'E:\Database Log'		-- nvarchar(300), if left empty, log files will not be moved
```

---

3. sp_JobsInfo:

	This script reports some information about jobs and their schedules. A sample output of this script is as follows. It is not optimized though because no optimization would be crucial. Part of the script (first function and the body of second function has been taken from the following URL written by  **Alan Jefferson**:
	
	[https://www.sqlservercentral.com/articles/how-to-decipher-sysschedules](https://www.sqlservercentral.com/articles/how-to-decipher-sysschedules)

	It helps DBAs plan their jobs' time table to smartly set their schedules to carry out necessary practices. For example, overlapping jobs should generally be avoided. Every job is executed with the permissions of its owner. So it's a security best practice to set the owner of the jobs, the logins which have minimum required permissions, and sysadmin members should generally be avoided. The last column lists the server role memberships of the owner of the job.

[![Sample script output](https://github.com/amomen9/SQLServer-DBA-Tools/raw/main/img/Screenshot_5.png)](https://github.com/amomen9/SQLServer-DBA-Tools/blob/main/img/Screenshot_5.png)

---

4. transfer indexes to other Filegroups/Partition Schemes

   This SP takes database names on the instance, generates the index transfer statements, and moves the specified index IDs to another filegroup/partition scheme. Email report of the result can also be implemented. Please note that index creation statements do not exist within "sys.all_sql_modules" or "sys.sql_modules" system catalogue views.
   
   **Example:**

```tsql
	EXEC dbo.usp_move_indexes_to_another_filegroup_per_every_database

		@DatabaseName,
		@starting_index_id,
		@ending_index_id,
		@target_filegroup_or_partition_scheme_name,	-- Possible values: {partition_scheme_name ( column_name ) | filegroup_name | default}. 
		@SORT_IN_TEMPDB = 0,
		@STATISTICS_NORECOMPUTE = 1,
		@STATISTICS_INCREMENTAL = 0,			-- It's not recommended to turn this feature on because you may face the following error:
										/*
											Msg 9108, Level 16, State 9, Line 139
											This type of statistics is not supported to be incremental.
										*/
		@ONLINE = 1,
		@MAXDOP = 4,
		@DATA_COMPRESSION = 'NONE',			-- Possible values: {DEFAULT|NONE|ROW|PAGE}
		@DATA_COMPRESSION_PARTITIONS = NULL,		-- Possible values: leave it empty for the whole partitions or for example 1,3,10,11 or 1-8
		@FILESTREAM = NULL,				-- Possible values: {filestream_filegroup_name | partition_scheme_name | NULL}
		@Retry_With_Less_Options = 1,
								-- If some of the transfer statements raise error on first try and this parameter is enabled, the
								-- script retries only those statements by turning off the following switches. What remains will
								-- be reported via email:
								-- 1. @STATISTICS_INCREMENTAL
								-- 2. @ONLINE

		@Email_Recipients,
		@copy_recipients,
		@blind_copy_recipients,
		@Create_or_Update_IndexTransferResults_Table = 0
								-- Creates or updates IndexTransferResults table within the SQLAdministrationDB database

```

---

5. Upcoming: Create automated dynamically generated formatted and decorated Excel (xlsx) file without SSIS:

   This script creates an Excel file and formats it. It can be automated to run on special occasions, for instance to send with an email report as attachment. The name of the file, the dates inside of it, its formatting and everything about it can be dynamic. A sample screen clipping of the result is the following:![Sample script output](img/Screenshot_5.png)

**Example:**

```tsql
Sample Code:
```

---

6. Execute external tsql

   The new version has become revolutionary and includes many new features! It has been tested in real environment to meet many needs. This script executes external tsql file(s) using sqlcmd and xp_cmdshell. It can run all the tsql files contained within a folder and its subdirectories. Because the scripts are to be executed by SQLCMD, you can also use SQLCMD commands like the one noted or ":connect" in your scripts as well. Sample sp execution statement is as follows:
   
   **Example:**

```tsql
EXECUTE sqladministrationdb..sp_execute_external_tsql 
		  @Change_Directory_To_CD = ''
		 ,@InputFiles = ''--N'D:\CandoMigration\test\3).sql'	-- Semicolon delimited list of script files to execute.
		 ,@InputFolder = '"C:\Users\Administrator\Desktop\test"'
		 ,@PreCommand = 'exec sp_configure ''show advanced options'',1; reconfigure; exec sp_configure ''cost threshold for parallelism'',25; reconfigure; exec sp_configure ''show advanced options'',0; reconfigure;'--'select 1987'
		 --,@PostCommand = 'exec sp_configure ''show advanced options'',0; reconfigure;'--'select ''jook'''
		 ,@FileName_REGEX_Filter_PowerShell = '*.sql'
		 ,@Include_Subdirectories = 1
		 ,@Server = NULL					-- Server name/IP + instance name. Include port if applicable
		 ,@AuthenticationType = NULL 				-- any value which does not include the word 'sql' means Windows Authentication
		 ,@UserName = NULL
		 ,@Password = NULL
		 --,@DefaultDatabase = 'SQLAdministrationDB'
		 ,@DefaultDatabase = 'SQLAdministrationDB'		-- Enter the name of the database unquoted, even if it has special characters or space. Leaving empty means "master"
		 ,@Keep_xp_cmdshell_Enabled = 1
		 ,@isDAC = 0	-- run files with Dedicated Admin Connection
		 ,@Debug_Mode = 2	--  none = 0 | simple = 1 | show = 2 | verbose = 3
		 ,@DoNot_Dispaly_Full_Path = 1
		 ,@skip_cmdshell_configuration = 0
		 ,@Stop_On_Error = 0
		 ,@Show_List_of_Executed_Scripts = 0
		 ,@Stop_After_Executing_Script = ''--'3).sql'		-- stops executing scripts after the first occurance of the given script
		 ,@After_Successful_Execution_Policy = 4		-- 0 | 1 | 2 | 3	0 (Default): Do nothing, 1: delete after successful execution, 
				-- 2: Move to @MoveTo_Folder_Name folder beside @InputFolder after successful execution replacing existings.
				-- 3: Move to @MoveTo_Folder_Name folder beside @InputFolder after successful execution and rename (add "_2") the files to avoid file replacements
				-- 4: Copy to @MoveTo_Folder_Name folder beside @InputFolder after successful execution and rename (add "_2") the files to avoid file replacements, but don't delete source files
				-- in options 2&3 the folders with the same name will be merged. These options work for @InputFolder only, not @InputFiles.
		 ,@MoveTo_Folder_Name = 'old'		
				-- If you set @After_Successful_Execution_Policy to 2 or more, the copy or movement command will be t this folder preserving the original directory tree structure, and if you
				-- leave this empty, the files will be logically moved/copied to one level up in the directory tree.
```

---

7. Enable CDC on a cluster's primary replica, enable CDC on a secondary replica
   (Within "BI\Enable CDC for clusters" directory)
   
   Enabling CDC on an AlwaysOn cluster which involves failovering is tricky. The two scripts contained within the BI directory, do just that effortlessly. You need to execute "Enable CDC for clusters.sql", within which you have to specify the path for "create CDC Jobs On Secondary.sql" script.---

8. dbWarden scripts: (contained within dbWarden directory)

   dbWarden is a free SQL Server Monitoring package written mostly in T-SQL. Here is a useful link in introduction to dbWarden:

	[https://www.sqlservercentral.com/articles/dbwarden-a-free-sql-server-monitoring-package-3](https://www.sqlservercentral.com/articles/dbwarden-a-free-sql-server-monitoring-package-3)

	sourceforge link:

	[https://sourceforge.net/projects/dbwarden/](https://sourceforge.net/projects/dbwarden/)

The scripts that currently are contained include "CPU intensive tasks for an instance (dbWarden).sql" and "Per Day-Average KPI stat for the last No of days.sql".---

9. Backup Website (Within T-SQL_Backup&Restore repo directory):

   This script performs a full backup of the database and home folder files of the intended website. It can be turned into a scheduled job to run at specific schedules. The DB backup file name will be in 'DBName_Date_Time + .bak' format. The home folder backup has a similar name. A checkdb will also be performed prior to the database backup.---

10. Restore Website (Within T-SQL_Backup&Restore repo directory):

    Before using this script, please read the comments at the beginning of Backup_Website.sql script thoroughly. This script restores the backups performed by the Backup_Website.sql script. You can also specify the destination database. If you don't specify the destination database, the database will be restored on its own. This script probes inside the backup folder and extracts and restores the latest backup. If the database is to be restored on its own, a tail of log backup will be taken first, if the database does not have SIMPLE or Pseudosimple recovery model. For the files restore, it overwrites all the files in the destination. By default, the last backup set will be restored, by probing into the backups directory and ignoring the history records of SQL Server msdb database. But you can specify the backup location manually. The names are case-insensitive. As the restore of Website files is normally time-consuming, the database will be kept in restoring state until the whole script is completed. For security reasons, the script enables the extended stored procedure xp_cmdshell and disables it again immediately once the procedure is finished executing.---

11. Cardinality Factor calculator sp for a table

    This stored procedure takes the name of a database and its table and calculates cardinality factor by calculating count(distinct column)/count(*) for every column. This may help the tuning specialists choose the better candidate column for indexing.
	
	**Example:**

```tsql
    DECLARE @temp TABLE(Column_Name SYSNAME, [Crowdedness (IN %)] FLOAT)
    INSERT INTO @temp
    EXECUTE master..CardinalityCalc 'Northwind','saasdsad.orders'

    select * from @temp
    order by 2 desc
```

---

12. Drop login dependencies

    This stored procedure disables a login and revokes any dependecies (that prevent the login from being dropped) on the server for that login. Generally, dropping a login in SQL Server is not recommended but there is an option to drop the login at the end of the process. It may also leave orphaned database users. If the login is windows authentication, you do not have to specify the domain or computer name unless there are several identical login names under different domain and computer names. The complete windows authentication login name must be in the format: DomainName\LoginName (LoginName@DomainName format is not supported). For transferring the dependencies, security best practices are observed, that means the ownership of databases and user defined server roles will be transfered to holder of 0x01 SID (login name 'sa' by default) and the ownership of jobs will be transferred to a new login with no specific access.
	
	**Example:**

```tsql
    DECLARE @SID VARBINARY(85)
    EXEC sp_drop_login_dependencies @LoginName = 'test'
					,@DropLogin = 1
					,@DroppedLoginSID = @SID OUTPUT
```

---

13. sp_restore_latest_backups_on_other_server (using psexec)

    The idea of this script comes from my SQL Server professor P.Aghasadeghi ([http://fad.ir/Teacher/Details/10](http://fad.ir/Teacher/Details/10)). This stored procedure restores the latest backups of a server on another server. Can come in handy sometimes. Please note that this SP benefits from Mark Russinovich's PsTools (psexec executable) briefly introduced on Microsoft's website at [https://docs.microsoft.com/en-us/sysinternals/downloads/pstools](https://docs.microsoft.com/en-us/sysinternals/downloads/pstools) and is mandatory for this script. After downloading PsTools, please place psexec from its archive to the source server's path. You can add it to a folder which is already in path like %systemroot%\system32\. There is no requirement for psexec on the destination server except for availability of the ports tcp\135 and tcp\445 which are open by default in Windows Firewall.
	
	**Example:**

```tsql
  exec sp_restore_latest_backups_on_other_server
	@Source = '192.168.241.3',					-- IPv4, IPv6, or hostname
	@Destination = '192.168.241.100',				-- IPv4, IPv6, or hostname
	@DestinationUser = 'Ali-PC\Ali',				-- Leave user and pass empty if on a domain, and source's SQL Server service account 
									-- must be an administrator on the target machine, Otherwise specify a username
									-- and password of an administrator of the target machine. Provide the username
									-- in full [Domain or Computer name\username] format. The destination user must
									-- also be a windows login and authorized to restore backups on the target SQL Server
	@DestinationPass = 'P@$$W0rd'
```

---

14. correct checksum of a corrupt_page: (Within Educational directory)

	If you have a corrupt page within your database and have identified it through some means, for example "DBCC CHECKDB('DBNAME')", you can make the page readable/writable again, by ordinary SQL statements, by correcting the checksum at a low level. This script is an example of it on the "Northwind" database. This script is included inside "Educational" subdirectory of the repository. You can get the "Northwind" sample database from the following link on Microsoft's website:

	[https://docs.microsoft.com/en-us/dotnet/framework/data/adonet/sql/linq/downloading-sample-databases](https://docs.microsoft.com/en-us/dotnet/framework/data/adonet/sql/linq/downloading-sample-databases)

---

15. create DimDate table (Within BI directory)

    This SP takes the start and end dates and creates DimDate table within the database that this SP is being created in. The DimDate table can have several cultures altogether besides Gregorian Calendar. The sample culture here is Persian. It has its own non-clustered index including all the necessary columns with the main index key of DateKey_Persian to be referenced by the foreign keys of other tables.
	
	**Example:**

```tsql
EXEC dbo.Create_DimDate @StartDate_Gregorian = '19900101', -- varchar(8)
                        @EndDate_Gregorian = '20401231',    -- varchar(8)
			@Drop_Last_DimDate_If_Exists = 1
```

---

16. Typical SQL Server setup configuration file with installation batch file. (Within educational directory)

    If you wish to install SQL Server instances on many servers, you should consider using a configuration file. A configuration file makes it easier and faster for you to install instances and maintain harmonical policies among your instances (You can also generate your own configuration file at the end of SQL Server's ordinary step by step main visual installation setup and use it numerously afterwards). The Microsoft's documentation regarding this possibility exists on the link below:

	[https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt?view=sql-server-ver16](https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt?view=sql-server-ver16)

	These batch, sql, and ini files help you do loads of sequential installation and preparation actions with one batch file execution. You just need to remember to alter these files according to your specifications and needs.* You may want to refer to the readme.txt file in the "SQL Server Unattended (Silent) Installation" itself too.

* Also, you need to either provide the following missing files or remove their reference from the batch files:
  * dbWarden_DB1_truncated_22.05.31.bak: backup file of dbWarden database
  * MsSqlCmdLnUtils.msi: MSI installation file for SQLCMD from Microsoft
  * SQLADDB_22.06.06.bak: backup file of SQLAdministrationDB database
  * SSMS Setup
  * dbWarden-Jobs.sql
* Please note that SQL port-firewall.bat includes changing the default port number for the default instance. If you do not intend to do that, simply remove the commands.
* You must run the "Install SQL Server.cmd" batch file with administrative priviledges.
* Some of the actions that this batch file carries out are the following:
  * Mounts SQL Server Installation .iso image file
  * Installs the SQL Server instance according to the configuration file
  * Installs SSMS silently
  * Installs SQL Server Cumulative Update silently
  * Installs SQLCMD silently
  * Does port/firewall configurations
  * Changes "sa" login name
  * Restores some preliminary databases from their backup files
  * Restarts the system on user's confirmation

**Example:**

```batchfile
rem "for the batch file's arguments refer to the readme file."
"\\Server\c$\Users\a.momen\Directory\Install SQL Server.cmd" H $@PA$$W0RD 2 #####-#####-#####-#####-##### 4 
```

<details class="details-reset details-overlay details-overlay-dark ">
<summary class="float-right" role="button"><div class="Link--secondary pt-1 pl-2"><svg aria-label="Edit repository metadata" role="img" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-gear float-right"><path d="M8 0a8.2 8.2 0 0 1 .701.031C9.444.095 9.99.645 10.16 1.29l.288 1.107c.018.066.079.158.212.224.231.114.454.243.668.386.123.082.233.09.299.071l1.103-.303c.644-.176 1.392.021 1.82.63.27.385.506.792.704 1.218.315.675.111 1.422-.364 1.891l-.814.806c-.049.048-.098.147-.088.294.016.257.016.515 0 .772-.01.147.038.246.088.294l.814.806c.475.469.679 1.216.364 1.891a7.977 7.977 0 0 1-.704 1.217c-.428.61-1.176.807-1.82.63l-1.102-.302c-.067-.019-.177-.011-.3.071a5.909 5.909 0 0 1-.668.386c-.133.066-.194.158-.211.224l-.29 1.106c-.168.646-.715 1.196-1.458 1.26a8.006 8.006 0 0 1-1.402 0c-.743-.064-1.289-.614-1.458-1.26l-.289-1.106c-.018-.066-.079-.158-.212-.224a5.738 5.738 0 0 1-.668-.386c-.123-.082-.233-.09-.299-.071l-1.103.303c-.644.176-1.392-.021-1.82-.63a8.12 8.12 0 0 1-.704-1.218c-.315-.675-.111-1.422.363-1.891l.815-.806c.05-.048.098-.147.088-.294a6.214 6.214 0 0 1 0-.772c.01-.147-.038-.246-.088-.294l-.815-.806C.635 6.045.431 5.298.746 4.623a7.92 7.92 0 0 1 .704-1.217c.428-.61 1.176-.807 1.82-.63l1.102.302c.067.019.177.011.3-.071.214-.143.437-.272.668-.386.133-.066.194-.158.211-.224l.29-1.106C6.009.645 6.556.095 7.299.03 7.53.01 7.764 0 8 0Zm-.571 1.525c-.036.003-.108.036-.137.146l-.289 1.105c-.147.561-.549.967-.998 1.189-.173.086-.34.183-.5.29-.417.278-.97.423-1.529.27l-1.103-.303c-.109-.03-.175.016-.195.045-.22.312-.412.644-.573.99-.014.031-.021.11.059.19l.815.806c.411.406.562.957.53 1.456a4.709 4.709 0 0 0 0 .582c.032.499-.119 1.05-.53 1.456l-.815.806c-.081.08-.073.159-.059.19.162.346.353.677.573.989.02.03.085.076.195.046l1.102-.303c.56-.153 1.113-.008 1.53.27.161.107.328.204.501.29.447.222.85.629.997 1.189l.289 1.105c.029.109.101.143.137.146a6.6 6.6 0 0 0 1.142 0c.036-.003.108-.036.137-.146l.289-1.105c.147-.561.549-.967.998-1.189.173-.086.34-.183.5-.29.417-.278.97-.423 1.529-.27l1.103.303c.109.029.175-.016.195-.045.22-.313.411-.644.573-.99.014-.031.021-.11-.059-.19l-.815-.806c-.411-.406-.562-.957-.53-1.456a4.709 4.709 0 0 0 0-.582c-.032-.499.119-1.05.53-1.456l.815-.806c.081-.08.073-.159.059-.19a6.464 6.464 0 0 0-.573-.989c-.02-.03-.085-.076-.195-.046l-1.102.303c-.56.153-1.113.008-1.53-.27a4.44 4.44 0 0 0-.501-.29c-.447-.222-.85-.629-.997-1.189l-.289-1.105c-.029-.11-.101-.143-.137-.146a6.6 6.6 0 0 0-1.142 0ZM11 8a3 3 0 1 1-6 0 3 3 0 0 1 6 0ZM9.5 8a1.5 1.5 0 1 0-3.001.001A1.5 1.5 0 0 0 9.5 8Z"></path></svg></div></summary>

</details>
