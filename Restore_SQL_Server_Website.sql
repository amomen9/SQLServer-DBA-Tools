
-- =============================================
-- Author:		<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:		<2021.03.12>
-- Description:		<Restore Website Backup>
-- =============================================

/*

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

System requirements:
SQL Server Compatibility: This script is designed to comply with SQL Server 2008 R2 and later. Earlier versions are not tested.
This script utilizes 7zip, so install 7-zip first, which is an open source and multiplatform compression software.
Sample 7zip commands
	for compression:
	7z a -tzip -mx9 -mmt4 -y -bd -ssw -stl  -p1234 "D:\Website Backup\21.03.10_0500\DBNAME_File Backup_21.03.10_0500.zip" "C:\inetpub\wwwroot\*"
	for extraction:
	7z x -aoa -spe -p1234 -o"C:\inetpub\wwwroot" "D:\Website Backup\21.03.10_0500\DBNAME_File Backup_21.03.10_0500.zip"
For information regarding 7zip commands and switches please refer to 7zip's manual.

Attention: 	
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

For the backup operation, please use Backup_Website.sql script.


*/

use master
go

--------------- Customizable Variables:
Declare @Source_Backup_Database_Name nvarchar(128) = N'sadasdasd'	-- Use the name of the website's db you wish to restore
Declare @Destination_Database_Name nvarchar(128) = N'jfdksfkj'
																-- You can specify the destination database name here. If the destination database name is equal to the source database name,
																-- the database will be restored on its own
Declare @Destination_Database_Datafiles_Location nvarchar(200) = 'D:\New Data'			
																-- This script creates the folders if they do not exist automatically.
																-- This variable must be in the form of for example 'D:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\DATA'
Declare @Destination_Website_Files_Location nvarchar(200) = ''	-- This script creates the folders if they do not exist automatically.
																-- This variable must be in the form of for example 'C:\xampp\htdocs'
Declare @Backup_Directory nvarchar(150) = ''					-- Null or empty string for this variable implies restore of the last available backup
																-- Otherwise it must be in form of for example D:\Website Backup\DBNAME_21.03.10_0500																
Declare @Files_Restore bit = 1									-- Restores the files if and only if it is set to 1
Declare @Database_Restore bit = 1								-- Restores the database if and only if it is set to 1
Declare @Backup_root nvarchar(120) = N'D:\Website Backup'		-- Root location for backup files. Ignore this variable if you have set @Backup_Location
Declare @Website_root nvarchar(120) = N'C:\inetpub\wwwroot'		-- Default for Microsoft IIS home folder
Declare @7zip_install_location nvarchar(500) = N'C:\Program Files\7-zip\'
																-- 7-zip install location
Declare @Archive_File_Password nvarchar(15) = N'1234'			-- Use only characters and numbers. If you enter the password wrong, this script will raise error
Declare @Keep_Database_in_Restoring_State bit = 1				-- If equals to 1, the database will be kept in restoring state until the whole process of restoring
																-- Website files is completed.
Declare @Temp_Working_Directory nvarchar(100) = N'C:\Temp'		-- Make sure SQL Service has permission to create this folder



--------------- Other Variables: !!!! Warning: Please do not modify these variables !!!!
Declare @Back_DateandTime nvarchar(20) = replace(convert(date, GetDate()),'-','.') + '_' + substring(replace(convert(nvarchar(10),convert(time, GetDate())), ':', ''),1,4) 
Declare @TailofLOG_Back_Name nvarchar(100) = 'TailofLOG_' + @Source_Backup_Database_Name+'_Backup_'+@Back_DateandTime+'.trn'
Declare @DB_Restore_Script nvarchar(max) = ''
Declare @TailofLOG_Back_Script nvarchar(500)
Declare @CommandtoExecute nvarchar(1000)
Declare @DirTree Table (subdirectory nvarchar(255), depth INT, [file] INT)
Declare @Backup_Location nvarchar(255)
Declare @DB_Backup_Name nvarchar(70)
Declare @Database_State bit = 0						-- Defines if the database is in restoring mode or not. 0 means ONLINE
Declare @Backup_Availability bit = 0				-- Checks if a backup exists for the source database name '@Source_Backup_Database_Name'
Declare @test bit = NULL

-- Begin Body:

SET NOCOUNT ON


set @Backup_Directory = isNULL(@Backup_Directory,'')

if (@Backup_Directory = '')
BEGIN
	insert into @DirTree
	EXEC xp_dirtree @Backup_root ,1 ,1
	set @DB_Backup_Name = (select top 1 subdirectory from @DirTree where [file] = 0 and subdirectory like (@Source_Backup_Database_Name + '%') order by subdirectory desc)
	set @Backup_Directory = @Backup_root +'\'+ @DB_Backup_Name
		
	
	delete from @DirTree

END

	insert into @DirTree
	EXEC xp_dirtree @Backup_Directory, 1, 1
	select @DB_Backup_Name = subdirectory from @DirTree where subdirectory like '%.bak'
	set @Backup_Location = @Backup_Directory + '\' + @DB_Backup_Name
	IF ((@DB_Backup_Name is null))
		RAISERROR('Fatal error: no backup found for the source database.',16,1)
	ELSE
		set @Backup_Availability = 1


IF ((@Files_Restore = 0 and @Database_Restore = 0))
	RAISERROR('You have chosen not to restore anything!!!!',16,1)
ELSE
	IF(@Backup_Availability = 1)
	BEGIN

		----------------------------------------------- Restoring Database:

		IF( @Database_Restore = 1 )
		BEGIN
		
		
			IF( @Source_Backup_Database_Name = @Destination_Database_Name ) -- restore database on its own
			BEGIN
			
				------------------------------ check if the database has SIMPLE or PseudoSIMPLE recovery model:
				declare @temp1 nvarchar(max)  
				declare @dbinfo table (ParentObject nvarchar(100), Object nvarchar(100), Field nvarchar(100), [VALUE] nvarchar(100))
				insert @dbinfo
				EXEC ('dbcc dbinfo (['+ @Source_Backup_Database_Name +']) with tableresults')
			
				declare @isPseudoSimple_or_Simple bit = 0
				IF cast(cast(SERVERPROPERTY('ProductVersion') as char(4)) as float) <= 10.5 -- Equal to or earlier than SQL 2008 R2
				BEGIN
					if ((select top 1 [VALUE] from @dbinfo where [Object] = 'dbi_dbbackupLSN' order by ParentObject) = '0')
						set @isPseudoSimple_or_Simple = 1
				END ELSE																	-- Later than SQL 2008 R2
					if ((select top 1 [VALUE] from @dbinfo where Field = 'dbi_dbbackupLSN' order by ParentObject) = '0:0:0 (0x00000000:00000000:0000)')
						set @isPseudoSimple_or_Simple = 1

				-----------------------------
			
				set @DB_Restore_Script = @DB_Restore_Script + 'ALTER DATABASE [' + @Source_Backup_Database_Name + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
				'

				if (@isPseudoSimple_or_Simple != 1) -- check if the database has not SIMPLE or PseudoSIMPLE recovery model
					set @DB_Restore_Script = @DB_Restore_Script + 'BACKUP LOG ' + @Source_Backup_Database_Name + ' TO DISK = ''' + @Backup_root + '\' + @TailofLOG_Back_Name + ''' WITH NOFORMAT, NOINIT,  NAME = ''' + @TailofLOG_Back_Name + ''', NOSKIP, NOREWIND, NOUNLOAD,  NORECOVERY 
					'

				set @DB_Restore_Script = @DB_Restore_Script + 'RESTORE DATABASE ' + @Source_Backup_Database_Name + ' FROM  DISK = ''' + @Backup_Location + ''' WITH  FILE = 1,  NOUNLOAD'
				if (@Keep_Database_in_Restoring_State = 1)
				BEGIN
					set @DB_Restore_Script = @DB_Restore_Script + ',  NORECOVERY'
					set @Database_State = 1
				END

			END ELSE
			BEGIN														-- Restore database to a new name

						
				--------------------- Extract list of File Groups and Files
				if OBJECT_ID('tempdb..#Backup_Files_List') is not null
					drop table #Backup_Files_List

				CREATE TABLE #Backup_Files_List (     
					 LogicalName    nvarchar(128)
					,PhysicalName   nvarchar(260)
					,[Type] char(1)
					,FileGroupName  nvarchar(128) NULL
					,Size   numeric(20,0)
					,MaxSize    numeric(20,0)
					,FileID bigint
					,CreateLSN  numeric(25,0)
					,DropLSN    numeric(25,0) NULL
					,UniqueID   uniqueidentifier
					,ReadOnlyLSN    numeric(25,0) NULL
					,ReadWriteLSN   numeric(25,0) NULL
					,BackupSizeInBytes  bigint
					,SourceBlockSize    int
					,FileGroupID    int
					,LogGroupGUID   uniqueidentifier NULL
					,DifferentialBaseLSN    numeric(25,0) NULL
					,DifferentialBaseGUID   uniqueidentifier NULL
					,IsReadOnly bit
					,IsPresent  bit
				)
				IF cast(cast(SERVERPROPERTY('ProductVersion') as char(4)) as float) > 9 -- Equal to or greater than SQL 2005 
				BEGIN
					ALTER TABLE #Backup_Files_List ADD TDEThumbprint  varbinary(32) NULL
				END
				IF cast(cast(SERVERPROPERTY('ProductVersion') as char(2)) as float) > 12 -- Equal to or greater than 2014
				BEGIN
					ALTER TABLE #Backup_Files_List ADD SnapshotURL    nvarchar(360) NULL
				END
				Declare @Backup_Path nvarchar(150) = @Backup_Location
				Declare @sql nvarchar(max) = 'RESTORE FILELISTONLY FROM DISK = @Backup_Path'
				INSERT INTO #Backup_Files_List
				EXEC master.sys.sp_executesql @sql , N'@Backup_Path nvarchar(150)', @Backup_Path
				---------------------------------------------------------------------------------------------------

				set @DB_Restore_Script = @DB_Restore_Script + N'RESTORE DATABASE [' + @Destination_Database_Name + '] FROM  DISK = N''' + @Backup_Location + ''' WITH  FILE = 1,  
				'
			
				if OBJECT_ID('tempdb..#temp') is not null
					drop table #temp
				create Table #temp ([move] nvarchar(500))
			
				if (ISNULL(@Destination_Database_Datafiles_Location,'') = '')
					raiserror('You have not chosen a destination path ''@Destination_Database_Datafiles_Location'' for your new database data files.',16,1)
				else
					exec xp_create_subdir @Destination_Database_Datafiles_Location

				if OBJECT_ID('tempdb..#temp2') is not null
					drop table #temp2
				select 'MOVE N''' + LogicalName + ''' TO N''' + @Destination_Database_Datafiles_Location +RIGHT(PhysicalName,CHARINDEX('\', REVERSE(PhysicalName))) + ''',  ' as [Single Move Statement]
				into #temp2
				from #Backup_Files_List

				select @DB_Restore_Script = @DB_Restore_Script + [Single Move Statement]
				from #temp2

				select @DB_Restore_Script = @DB_Restore_Script + 'NOUNLOAD,  STATS = 20'
			
			END	
				print(@DB_Restore_Script)
				print(@Backup_Path)
				EXEC (@DB_Restore_Script)
				print('End Database Restore') 

		END


		----------------------------------------------- Restoring Files:

		/* 
			The if condition checks if the SQL Server host is windows, for on Linux xp_cmdshell is not available. To check the host's os
			you can use "select host_platform from sys.dm_os_host_info) = 'Windows'" statement but sys.dm_os_host_info is incompatible with
			SQL Server 2016 and earlier. To support these versions I used the global variable @@version instead.
		*/
		Declare @Linux_Position int
		SELECT @Linux_Position = CHARINDEX('Linux', @@VERSION)

		IF (@Linux_Position != 0 and @Files_Restore = 1)
			raiserror('You cannot restore website files on Linux host!', 16, 1)
		ELSE
			IF(@Files_Restore = 1)
			BEGIN
		
			EXECUTE xp_create_subdir @Temp_Working_Directory /* This directory keeps the log of disabling xp_cmdshell and
				'show advanced options' in the form of "MyOutput.txt".
			*/
		
			USE master

			-- To allow advanced options to be changed.  
			EXECUTE sp_configure 'show advanced options', 1;  
  
			-- To update the currently configured value for advanced options.  
			RECONFIGURE;  
  
			-- To enable the feature.  
			EXECUTE sp_configure 'xp_cmdshell', 1;  

			-- To update the currently configured value for this feature.  
			RECONFIGURE;  

		
			set @CommandtoExecute = 'sqlcmd -Q "/* To disable the feature.  */ EXECUTE sp_configure ''xp_cmdshell'', 0; /* To update the currently configured value for this feature.  */	RECONFIGURE; /* To deny advanced options to be changed.  */ EXECUTE sp_configure ''show advanced options'', 0; 	/* To update the currently configured value for advanced options.  */ RECONFIGURE; " -o C:\Temp\MyOutput.txt & "' + @7zip_install_location + N'7z" x -aoa -spe -p' + @Archive_File_Password + ' -o"' +	@Website_root + '" "' + LEFT(@Backup_Location ,(LEN(@Backup_Location)-4)) + '.zip" & whoami'
			set @CommandtoExecute = REPLACE(@CommandtoExecute,'Full Backup','File Backup')
		
			print ('Begin file restore')
			if OBJECT_ID('tempdb..#temp3') is not null
				drop table #temp3
			create table #temp3 ([output] nvarchar(500))
			insert #temp3
			EXECUTE master..xp_cmdshell @CommandtoExecute

		
			Declare @cmdshell_output nvarchar(max) = ''
			select @cmdshell_output = @cmdshell_output + ' ' + isNULL([output],'') + char(10)
			from #temp3
		
			print (@cmdshell_output)		-- Attention! 'print' truncates strings bigger than 4000 nvarchar characters
		
			if (CHARINDEX('Wrong password', @cmdshell_output) > 0)
			BEGIN
				raiserror('The archive password was not provided correctly and the website files were not restored.',16,1)
			END ELSE
			BEGIN
				if (CHARINDEX('No files to process', @cmdshell_output) > 0)
					raiserror('No files were restored to the website directory.',16,1)
				else
					if (CHARINDEX('Everything is Ok', @cmdshell_output) = 0)
					BEGIN
						declare @7zip_Error nvarchar(max) = 'Some error ocurred during archive extraction. More information on this error from 7-zip: ' + @cmdshell_output
						raiserror(@7zip_Error,16,1)
					END
			END

			/*	The following configurations are already set by xp_cmdshell and they must not be executed again:

				-- To disable the feature.  
				EXECUTE sp_configure 'xp_cmdshell', 0;  
	  
				-- To update the currently configured value for this feature.  
				RECONFIGURE;  
	  
				-- To deny advanced options to be changed.  
				EXECUTE sp_configure 'show advanced options', 0;  
	  
				-- To update the currently configured value for advanced options.  
				RECONFIGURE; 
			*/

		END
  
  
	END ELSE
		print ('Nothing restored!')


if @Database_State = 1
Begin
	restore database @Source_Backup_Database_Name with RECOVERY;
	declare @temp5 nvarchar(150) = 'ALTER DATABASE [' + @Source_Backup_Database_Name + '] SET MULTI_USER'
	EXEC (@temp5)
	if @@ERROR = 0
		set @Database_State = 0
END
GO

