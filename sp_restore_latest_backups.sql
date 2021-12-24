
-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2021.03.12>
-- Description:			<Restore Backups>
-- =============================================

/*


This script	restores the latest backups from backup files accessible to the server. As the server is not the original producer of these backups,
	there will be no records of these backups in msdb. The records can be imported from the original server anyways but there would be
	some complications. This script probes recursively inside the provided directory, extracts all the full or read-write backup files,
	reads the database name and backup finish dates from these files and restores the latest backup of every found database. If the
	database already exists, a tail of log backup can be taken optionally first. If the name of the database cannot be obtained from the
	backup file, the script names the target database as 'CorruptBackup+<a random number>'. Such backup will most likely fail to restore.

System requirements:
SQL Server Compatibility: This script is designed to comply with SQL Server 2016 and later. Earlier versions are compatible if some
of the features are removed. The versions 2016 and 2017 are most likely supported. I have tested this on 2019

Attention: 		
	1. Please make sure SQL service has required permission to the paths you specify. Otherwise the script will fail. If the output paths do not
	exist, the script automatically creates them.
	2. If you restore the database to a new name and it already exists, some errors might occur. This script does
	not handle such a case.
	3. As leaving xp_cmdshell enabled has security risks, especially for the backup jobs which are meant to be scheduled
	to be triggered at special times, and compressing or decompressing files is time-consuming, this script does not wait for
	the compression or extraction process to complete and then disable xp_cmdshell. It launches a parallel script implicitly
	to disable xp_cmdshell immidiately after it starts. In other words, xp_cmdshell only remains enabled for a very short
	time. It was less than 0.3 second on my computer.
	4. If the database is to be restored on its own, this script automatically kills all sessions connected to the database except
	the current session, before restoring the database. The database will be returned to MULTI_USER at the end.
	5. Warning!! Appending backups to each other is not recommended and this script is not designed to handle such case.
	6. If the database is to be restored on its own, the script first tries to kill any conncetions to the database
	using 'ALTER DATABASE' statement. If it is in restoring state or any other state which will not allow ALTER DATABASE
	statement, SQL Server raises an error which is normal and is not an obstacle.

*/

USE master
GO

--============== First SP ================================================================================

-- This SP is called by the main SP
create or alter procedure sp_BackupDetails
	@Backup_Path nvarchar(1000) = N'E:\Backup\test_read-only\NW_FG-Archive_Full_0244.bak'
As
BEGIN
	set nocount on
	drop table if exists #tmp
	drop table if exists tempdb.._46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
	CREATE TABLE #tmp (
		BackupName nvarchar(128),
		BackupDescription nvarchar(255),
		BackupType tinyint,
		ExpirationDate datetime,
		Compressed tinyint,
		Position smallint,
		DeviceType tinyint,
		UserName nvarchar(128),
		ServerName nvarchar(128),
		DatabaseName nvarchar(128),
		DatabaseVersion int,
		DatabaseCreationDate datetime,
		BackupSize bigint,
		FirstLSN decimal(25),
		LastLSN decimal(25),
		CheckpointLSN decimal(25),
		DatabaseBackupLSN decimal(25),
		BackupStartDate datetime,
		BackupFinishDate datetime,
		SortOrder smallint,
		CodePage smallint,
		UnicodeLocaleId int,
		UnicodeComparisonStyle int,
		CompatibilityLevel tinyint,
		SoftwareVendorId int,
		SoftwareVersionMajor int,
		SoftwareVersionMinor int,
		SoftwareVersionBuild int,
		MachineName nvarchar(128),
		Flags int,
		BindingID uniqueidentifier,
		RecoveryForkID uniqueidentifier,
		Collation nvarchar(128),
		FamilyGUID uniqueidentifier,
		HasBulkLoggedData bit,
		IsSnapshot bit,
		IsReadOnly bit,
		IsSingleUser bit,
		HasBackupChecksums bit,
		IsDamaged bit,
		BeginsLogChain bit,
		HasIncompleteMetaData bit,
		IsForceOffline bit,
		IsCopyOnly bit,
		FirstRecoveryForkID uniqueidentifier,
		ForkPointLSN decimal(25),
		RecoveryModel nvarchar(60),
		DifferentialBaseLSN decimal(25),
		DifferentialBaseGUID uniqueidentifier,
		BackupTypeDescription nvarchar(128),
		BackupSetGUID uniqueidentifier,
		CompressedBackupSize bigint,
    
		)

		IF cast(cast(SERVERPROPERTY('ProductVersion') as char(4)) as float) > 11 -- Equal to or greater than SQL 2012 
  		BEGIN
  			ALTER TABLE #tmp ADD Containment tinyint NULL
  		END
  		IF cast(cast(SERVERPROPERTY('ProductVersion') as char(2)) as float) > 12 -- Equal to or greater than 2014
  		BEGIN
  			ALTER TABLE #tmp ADD KeyAlgorithm nvarchar(32),
								EncryptorThumbprint varbinary(20),
								EncryptorType nvarchar(32)
  		END

		-- N'E:\Backup\test_read-only\NW_readwrite_0316.bak' -- N'E:\Backup\test_read-only\NW_dif.dif' -- N'E:\Backup\test_read-only\NW_Full_backup_0240.bak' -- 
  		Declare @sql nvarchar(max) = 'RESTORE HEADERONLY FROM DISK = @Backup_Path'
  		INSERT INTO #tmp
  		EXEC master.sys.sp_executesql @sql , N'@Backup_Path nvarchar(150)', @Backup_Path


		select DatabaseName, LastLSN, BackupFinishDate, BackupTypeDescription into tempdb.._46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9 from #tmp
		

END
GO

--======= Second SP =====================================================================================================

--- This SP is called by the main SP:
create or alter proc sp_complete_restore 
	@Drop_Database_if_Exists BIT = 0,
	@Restore_DBName sysname,
	@Restore_Suffix sysname = '',
	@Backup_Location nvarchar(1000),
	@Destination_Database_DataFiles_Location nvarchar(300) = '',			
	@Destination_Database_LogFile_Location nvarchar(300) = '',
	@Take_tail_of_log_backup bit = 1,
	@Keep_Database_in_Restoring_State bit = 0,					-- If equals to 1, the database will be kept in restoring state until the whole process of restoring
	@DataFileSeparatorChar nvarchar(2) = '_',					-- This parameter specifies the punctuation mark used in data files names. For example "_"
	@Change_Target_RecoveryModel_To NVARCHAR(20) = 'same',		-- Possible options: FULL|BULK-LOGGED|SIMPLE|SAME
	@Set_Target_Database_ReadOnly BIT = 0,
	@STATS TINYINT = 50,
	@Delete_Backup_File BIT = 0							
	
AS
BEGIN
  set nocount on
  SET @STATS = ISNULL(@STATS,0)
  SET @Restore_Suffix = ISNULL(@Restore_Suffix,'')
  SET @Restore_DBName += @Restore_Suffix
  IF (@Change_Target_RecoveryModel_To IS NULL) OR (@Change_Target_RecoveryModel_To = '')
	SET @Change_Target_RecoveryModel_To = 'same'
  
  DECLARE @Back_DateandTime nvarchar(20) = (select replace(convert(date, GetDate()),'-','.') + '_' + substring(replace(convert(nvarchar(10),convert(time, GetDate())), ':', ''),1,4) )
  Declare @DB_Restore_Script nvarchar(max) = ''
  declare @DropDatabaseStatement nvarchar(max) = ''
  
  IF (@Change_Target_RecoveryModel_To NOT IN ('FULL','BULK-LOGGED','SIMPLE','SAME'))
  BEGIN
	RAISERROR('Target recovery model specified is not a recognized SQL Server recovery model.',16,1)
	RETURN 1
  END
  
  ----------------------------------------------- Restoring Database:
    		  		
  			print('-----------------------------------------------------------------------------------------------------------')
			print('')

			-------------------------------------------------------------------

  			IF( DB_ID(@Restore_DBName) is not null ) -- restore database on its own
  			BEGIN
  				
  				------------------------------ check if the database has SIMPLE or PseudoSIMPLE recovery model:
  				declare @temp1 nvarchar(max)  
  				declare @dbinfo table (ParentObject nvarchar(100), Object nvarchar(100), Field nvarchar(100), [VALUE] nvarchar(100))
				DECLARE @DBCCStatement NVARCHAR(200) = 'dbcc dbinfo ('+ QUOTENAME(@Restore_DBName) +') with tableresults, NO_INFOMSGS'
  				insert @dbinfo
  				EXEC (@DBCCStatement)
  			
  				declare @isPseudoSimple_or_Simple bit = 0
  				IF cast(cast(SERVERPROPERTY('ProductVersion') as char(4)) as float) <= 10.5 -- Equal to or earlier than SQL 2008 R2
  				BEGIN
  					if ((select top 1 [VALUE] from @dbinfo where [Object] = 'dbi_dbbackupLSN' order by ParentObject) = '0')
  						set @isPseudoSimple_or_Simple = 1
  				END ELSE																	-- Later than SQL 2008 R2
  					if ((select top 1 [VALUE] from @dbinfo where Field = 'dbi_dbbackupLSN' order by ParentObject) = '0:0:0 (0x00000000:00000000:0000)')
  						set @isPseudoSimple_or_Simple = 1
  
  				-----------------------------
  				IF (SELECT state FROM sys.databases WHERE name = @Restore_DBName) = 0	-- state 0 means database is online
				begin
						SET @DB_Restore_Script += 'use '+ QUOTENAME(@Restore_DBName) + ' ALTER database ' + QUOTENAME(@Restore_DBName) + ' set single_user with rollback immediate
						'						
						EXECUTE (@DB_Restore_Script)
						SET @DB_Restore_Script = ''
				END
  				if (@isPseudoSimple_or_Simple != 1 and @Take_tail_of_log_backup = 1) -- check if the database has not SIMPLE or PseudoSIMPLE recovery model
				BEGIN
					DECLARE @Tail_of_Log_Backup_Script NVARCHAR(max)
					Declare @TailofLOG_Backup_Name nvarchar(100) = 'TailofLOG_' + @Restore_DBName+'_Backup_'+@Back_DateandTime+'.trn'
  					set @Tail_of_Log_Backup_Script = 'BACKUP LOG ' + QUOTENAME(@Restore_DBName) + ' TO DISK = ''' + @TailofLOG_Backup_Name + ''' WITH FORMAT,  NAME = ''' + @TailofLOG_Backup_Name + ''', NOREWIND, NOUNLOAD,  NORECOVERY 
  					'
					EXEC (@Tail_of_Log_Backup_Script)
					
				END  

				---- Dropping database if exists, before restoring, on user request ------
				IF (@Drop_Database_if_Exists = 1)
				BEGIN										
					SET @DropDatabaseStatement += 'DROP database ' + @Restore_DBName + CHAR(10)					
					GOTO restoreanew

				END
				--------------------------------------------------------------------------

  				set @DB_Restore_Script = 'RESTORE DATABASE ' + QUOTENAME(@Restore_DBName) + ' FROM  DISK = ''' + @Backup_Location + ''' WITH  FILE = 1, NOUNLOAD, replace' + IIF(@STATS = 0,'',(', STATS = ' + CONVERT(varchar(3),@STATS)))
  				if (@Keep_Database_in_Restoring_State = 1)  				
  					set @DB_Restore_Script += ',  NORECOVERY'
  				
  				
				
					
  
  			END ELSE
  			BEGIN														-- Restore database to a new name or restoring a non-existent database 
				RESTOREANEW:
  						
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
  	
  				Declare @sql nvarchar(max) = 'RESTORE FILELISTONLY FROM DISK = @Backup_Path'
  				INSERT INTO #Backup_Files_List
  				EXEC master.sys.sp_executesql @sql , N'@Backup_Path nvarchar(150)', @Backup_Location
				---------------------------------------------------------------------------------------------------								

  				set @DB_Restore_Script += @DropDatabaseStatement + N'RESTORE DATABASE ' + QUOTENAME(@Restore_DBName) + ' FROM  DISK = N''' + @Backup_Location + ''' WITH  FILE = 1  
  				'
				
--  				PRINT @Destination_Database_DataFiles_Location
				if (@Restore_Suffix <> '') -- (@Destination_Database_DataFiles_Location <> 'same')
				BEGIN
                
  					if OBJECT_ID('tempdb..#temp') is not null
  						drop table #temp
  					create Table #temp ([move] nvarchar(500))					
  			
  					if (ISNULL(@Destination_Database_Datafiles_Location,'') = '')
					begin
  						set @Destination_Database_Datafiles_Location = convert(nvarchar(1000),(select SERVERPROPERTY('InstanceDefaultDataPath')))
					end
					ELSE IF @Destination_Database_DataFiles_Location <> 'same'
  						exec xp_create_subdir @Destination_Database_DataFiles_Location
  
					if (ISNULL(@Destination_Database_Logfile_Location,'') = '')
					begin
  						set @Destination_Database_Logfile_Location = convert(nvarchar(1000),(select SERVERPROPERTY('InstanceDefaultLogPath')))
					end
					ELSE IF @Destination_Database_DataFiles_Location <> 'same'
  						exec xp_create_subdir @Destination_Database_LogFile_Location

					

------------------ Adding move statements:--------------------------	
  					if OBJECT_ID('tempdb..#temp2') is not null
  						drop table #temp2
  					select ', MOVE N''' + LogicalName + ''' TO N''' + 
					CASE when FileID = 2 then 
					IIF(
					@Destination_Database_DataFiles_Location <> 'same',@Destination_Database_LogFile_Location, LEFT(PhysicalName, (LEN(PhysicalName) - CHARINDEX('\',REVERSE(PhysicalName))))
					)
					ELSE 
					IIF(
					@Destination_Database_DataFiles_Location <> 'same',@Destination_Database_DataFiles_Location, LEFT(PhysicalName, (LEN(PhysicalName) - CHARINDEX('\',REVERSE(PhysicalName))))
					)
					END
					+ '\' + @Restore_DBName + right(PhysicalName, (CASE WHEN charindex(@DataFileSeparatorChar, RIGHT(PhysicalName,CHARINDEX('\', REVERSE(PhysicalName)))) <> 0 then charindex(@DataFileSeparatorChar,reverse(PhysicalName)) ELSE charindex('.',reverse(PhysicalName)) END)) + '''  '																		                                 
																				as [Single Move Statement]
  					into #temp2
  					from #Backup_Files_List
					
					
  					select @DB_Restore_Script += [Single Move Statement]
  					from #temp2
--------------------------------------------------------------------  
				end
				else
				BEGIN
		--			SELECT * from #Backup_Files_List
					DECLARE mkdir cursor for select PhysicalName from #Backup_Files_List
					open mkdir
						declare @DirPath nvarchar(1000)
						fetch next from mkdir into @DirPath
						while @@FETCH_STATUS = 0
						begin
							select @DirPath = left(@DirPath, (len(@DirPath)-charindex('\',REVERSE(@DirPath))))
							execute xp_create_subdir @DirPath										
							fetch next from mkdir into @DirPath
						end 
					CLOSE mkdir
					DEALLOCATE mkdir

				END
                if (@Keep_Database_in_Restoring_State = 1)  				
  					set @DB_Restore_Script += ',  NORECOVERY'
  					
  				

  				select @DB_Restore_Script += ',  NOUNLOAD' + IIF(@STATS = 0,'',(', STATS = ' + CONVERT(varchar(3),@STATS)))
  			
  			END	
  				print (@DB_Restore_Script)
  				EXEC (@DB_Restore_Script)
				----- Deleting backup file on successful restore on user's request
				IF (@@error = 0 AND @Delete_Backup_File = 1)
				BEGIN
					/*	This 'if' is applicable when you use xp_cmdshell to delete the files
					IF (SELECT value FROM sys.configurations WHERE name = 'xp_cmdshell') = 0
					begin
						RAISERROR('xp_cmdshell is required to be active by the user to delete the backup file.',16,1)
					end
					*/
					
					DECLARE @ErrorNo int
					EXEC xp_delete_files @Backup_Location
					
					IF(@@ERROR <> 0)
					BEGIN                    					
						DECLARE @ErrorMessage NVARCHAR(1000) = 'Deleting backup file '+ @Backup_Location +' failed due to the system above error message.'	
						PRINT @ErrorMessage
					END
					
                END

  				print(char(10)+'End '+ @Restore_DBName +' Database Restore') 
				print('')
				
  			      		
  			if (SELECT state FROM sys.databases WHERE name = @Restore_DBName) = 0
			BEGIN
				
				DECLARE @temp5 nvarchar(2000) = ''
				IF (@Change_Target_RecoveryModel_To <> 'same')
					SET @temp5 = 'ALTER DATABASE ' + QUOTENAME(@Restore_DBName) + ' SET RECOVERY ' + @Change_Target_RecoveryModel_To + CHAR(10)
				
  				set @temp5 += 'ALTER DATABASE ' + QUOTENAME(@Restore_DBName) + ' SET MULTI_USER' + CHAR(10)
				EXEC(@temp5)

				-- If use requests, turning sp's recovery model to simple and shrinking its log file
				IF (@Change_Target_RecoveryModel_To = 'SIMPLE')
					SET @temp5 = 'USE ' + QUOTENAME(@Restore_DBName) + CHAR(10) + 
					'declare @FileName sysname = (select name from sys.database_files where file_id=2)' + CHAR(10) +
					'declare @SQL nvarchar(200) = ''DBCC SHRINKFILE(''+''''''''+@FileName+''''''''+'',0) WITH NO_INFOMSGS''' + CHAR(10) +
					'exec (@SQL)' + CHAR(10)

				IF (@Set_Target_Database_ReadOnly = 1)
					SET @temp5 += 'alter database ' + @Restore_DBName + ' set READ_ONLY'
				
				--DECLARE @suppresser TABLE  (
				--	DbId smallint,
				--	FileId int,
				--	CurrentSize int,
				--	MinimumSize int,
				--	UsedPages int,
				--	EstimatedPages INT
				--)

				--INSERT @suppresser
				
  				EXEC (@temp5)
			END
END
GO


--============= Third SP: Main SP =================================================================================

-- Main SP:

CREATE OR ALTER PROC sp_restore_latest_backups

  @Drop_Database_if_Exists BIT = 0,
																-- Turning this feature on, potentially means relocating the data files
																-- of already existing databases

  @Destination_Database_Name_suffix nvarchar(128) = N'',
  																-- You can specify the destination database names' suffix here. If the destination database name is equal to the backup database name,
  																-- the database will be restored on its own. Leave empty to do so.
  @Destination_Database_DataFiles_Location nvarchar(300) = '',			
  																-- This script creates the folders if they do not exist automatically. Make sure SQL Service has permission to create such folders
  																-- This variable must be in the form of for example 'D:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\DATA'
  @Destination_Database_LogFile_Location nvarchar(300) = '',
  
  @Backup_root nvarchar(120) = N'e:\Backup',					-- Root location for backup files.

  @Exclude_DBName_Filter NVARCHAR(500) = N'',					-- Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
																-- N'Northwind,AdventureWorks, StackOverFlow'. The script excludes databases that contain any of such keywords
																-- in the name like AdventureWorks2019. Note that space at the begining and end of the names will be disregarded
  
  @Include_DBName_Filter NVARCHAR(500) = N'',					-- Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
																-- N'Northwind,AdventureWorks, StackOverFlow'. The script includes databases that contain any of such keywords
																-- in the name like AdventureWorks2019 and excludes others. Note that space at the begining and end of the names
																-- will be disregarded.

  @IncludeSubdirectories BIT = 1,								-- Choosing whether to include subdirectories or not while the script is searching for backup files.  
  
  @Keep_Database_in_Restoring_State bit = 0,					-- If equals to 1, the database will be kept in restoring state
  @Take_tail_of_log_backup bit = 1,
  --@Temp_Working_Directory nvarchar(100) = N'C:\Temp',			-- Make sure SQL Service has permission to create this folder
  @DataFileSeparatorChar nvarchar(2) = '_',						-- This parameter specifies the punctuation mark used in data files names. For example "_"
																-- in NW_1.mdf or "$" in NW$1.mdf
  @Change_Target_RecoveryModel_To NVARCHAR(20) = 'same',		-- Possible options: FULL|BULK-LOGGED|SIMPLE|SAME
  @Set_Target_Databases_ReadOnly BIT = 0,
  @Delete_Backup_File BIT = 0,
  @STATS TINYINT = 50,											-- Set this to specify stats parameter of restore statements											
																-- Turn this feature on to delete the backup files that are successfully restored.
  @Email_Failed_Restores_To NVARCHAR(128) = NULL

AS
BEGIN
  ---------------------------- Standardization of Customizable Variables:
  
  
  IF RIGHT(@Destination_Database_Datafiles_Location, 1) = '\' 
  	SET @Destination_Database_Datafiles_Location = 
  	left(@Destination_Database_Datafiles_Location,(len(@Destination_Database_Datafiles_Location)-1))
  
  IF RIGHT(@Backup_root, 1) = '\' 
  	SET @Backup_root = 
  	left(@Backup_root,(len(@Backup_root)-1))
  
  --IF RIGHT(@Temp_Working_Directory, 1) = '\' 
  --	SET @Temp_Working_Directory = 
  --	left(@Temp_Working_Directory,(len(@Temp_Working_Directory)-1))
  
  
  IF @Destination_Database_DataFiles_Location = ''
    SET @Destination_Database_DataFiles_Location = convert(nvarchar(300),SERVERPROPERTY('instancedefaultdatapath'))

  IF @Destination_Database_LogFile_Location = ''
    SET @Destination_Database_LogFile_Location = @Destination_Database_DataFiles_Location

  IF RIGHT(@Destination_Database_DataFiles_Location, 1) = '\' 
	SET @Destination_Database_DataFiles_Location = 
	left(@Destination_Database_DataFiles_Location,(len(@Destination_Database_DataFiles_Location)-1))

  IF RIGHT(@Destination_Database_LogFile_Location, 1) = '\' 
	SET @Destination_Database_LogFile_Location = 
	left(@Destination_Database_LogFile_Location,(len(@Destination_Database_LogFile_Location)-1))

  SET @Exclude_DBName_Filter = ISNULL(@Exclude_DBName_Filter,'')
  SET @Include_DBName_Filter = ISNULL(@Include_DBName_Filter,'')
  SET @Drop_Database_if_Exists = ISNULL(@Drop_Database_if_Exists,0)
  SET @IncludeSubdirectories = ISNULL(@IncludeSubdirectories,1)
  SET @Keep_Database_in_Restoring_State = ISNULL(@Keep_Database_in_Restoring_State,0)
  SET @Take_tail_of_log_backup = ISNULL(@Take_tail_of_log_backup,1)
  SET @Set_Target_Databases_ReadOnly = ISNULL(@Set_Target_Databases_ReadOnly,0)
  SET @Delete_Backup_File = ISNULL(@Delete_Backup_File,0)
  SET @Destination_Database_Name_suffix = ISNULL(@Destination_Database_Name_suffix,'')
  SET @Destination_Database_DataFiles_Location = ISNULL(@Destination_Database_DataFiles_Location,'')
  SET @Destination_Database_LogFile_Location = ISNULL(@Destination_Database_LogFile_Location,'')
  set @Backup_root = isNULL(@Backup_root,'')
  --SET @Temp_Working_Directory = ISNULL(@Temp_Working_Directory,'')
  SET @DataFileSeparatorChar = ISNULL(@DataFileSeparatorChar,'_')
  SET @Change_Target_RecoveryModel_To = ISNULL(@Change_Target_RecoveryModel_To,'same')
  SET @Email_Failed_Restores_To = ISNULL(@Email_Failed_Restores_To,'')
  SET @Backup_root = REPLACE(@Backup_root,'"','')
  SET @Destination_Database_DataFiles_Location = REPLACE(@Destination_Database_DataFiles_Location,'"','')
  SET @Destination_Database_LogFile_Location = REPLACE(@Destination_Database_LogFile_Location,'"','')
  
  --------------- Other Variables: !!!! Warning: Please do not modify these variables !!!!
    
  
  Declare @Backup_Location nvarchar(255)
    
  Declare @count int = 0				-- Checks if a backup exists for the source database name '@DBName'
  declare @Backup_Path nvarchar(1000)
  
  
  declare @DatabaseName nvarchar(128), @BackupFinishDate datetime, @BackupTypeDescription nvarchar(128)
  
  DROP TABLE IF EXISTS #t
  CREATE TABLE #t (dbname NVARCHAR(128), path NVARCHAR(255))

  ---- Begin Body:
  
  SET NOCOUNT ON
  EXECUTE sp_configure 'show advanced options', 1; RECONFIGURE; EXECUTE sp_configure 'xp_cmdshell', 1; RECONFIGURE;
  
  
  
  if (@Backup_root <> '')
  BEGIN  					
		
		drop table if exists #DirContents
		create table #DirContents ([file] nvarchar(255))
        DECLARE @cmdshellInput NVARCHAR(500) = CASE @IncludeSubdirectories WHEN 1 THEN 'dir /B '+ '/S' +' "' + @Backup_root + '\*.bak"' ELSE '@echo off & for %a in ('+@Backup_root+'\*.bak) do echo %~fa' END
	
        insert into #DirContents
  		EXEC master..xp_cmdshell @cmdshellInput	

		EXECUTE sp_configure 'xp_cmdshell', 0; RECONFIGURE; EXECUTE sp_configure 'show advanced options', 0; RECONFIGURE;

  		  if (CHARINDEX('\',(select TOP 1 [file] from #DirContents)) = 0 )		  
  		  BEGIN				
				declare @message nvarchar(150) = 'Fatal error: "'+ (select TOP 1 [file] from #DirContents) +'"'
    			raiserror(@message, 16, 1)
				set @message = 'The folder path you specified for backup root either does not exist or no backups exist within that folder or its subdirectories'
    			raiserror(@message, 16, 1)				
				return 1
    	  END
		delete from #DirContents where [file] is null
		alter table #DirContents add DatabaseName nvarchar(128), BackupFinishDate datetime, BackupTypeDescription nvarchar(128)

		
		declare BackupDetails cursor for select * from #DirContents
		open BackupDetails
			
			fetch next from BackupDetails into @Backup_Path, @DatabaseName , @BackupFinishDate, @BackupTypeDescription								
			while @@FETCH_STATUS = 0
			begin
			
---------------------------------------------------------------------------------------------------------				
				execute sp_BackupDetails @Backup_Path
---------------------------------------------------------------------------------------------------------
				update #DirContents set DatabaseName = (select top 1 DatabaseName from tempdb.._46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails
				update #DirContents set BackupFinishDate = (select top 1 BackupFinishDate from tempdb.._46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails
				update #DirContents set BackupTypeDescription = (select top 1 BackupTypeDescription from tempdb.._46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails
				IF (SELECT DatabaseName FROM [tempdb].[dbo].[_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9]) IS NULL
				BEGIN
--					SET @count+=1
					INSERT INTO #t
					(
					    dbname,
					    path
					)
					VALUES
					(   concat('CorruptBackup_', LEFT(CONVERT(NVARCHAR(50),NEWID()),12)), -- dbname - nvarchar(128)
					    @Backup_Path  -- path - nvarchar(255)
					)
				END
                
				DELETE from tempdb.._46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
				fetch next from BackupDetails into @Backup_Path, @DatabaseName , @BackupFinishDate, @BackupTypeDescription				
			end 
		CLOSE BackupDetails
		DEALLOCATE BackupDetails

		----- Applying @Exclude_DBName_Filter and @Include_DBName_Filter filters-----------------------------------------
		BEGIN try
			---- Filtering out @Exclude_DBName_Filter databases ---------------------------------------------------------
			IF @Exclude_DBName_Filter <> ''
			BEGIN
				DECLARE @DB_to_Exclude sysname
				
				DECLARE excluder CURSOR FOR SELECT * FROM STRING_SPLIT(@Exclude_DBName_Filter,',')
				OPEN excluder
					FETCH NEXT FROM excluder INTO @DB_to_Exclude
					WHILE @@FETCH_STATUS = 0
					BEGIN
						IF @DB_to_Exclude <> ''
							DELETE FROM #DirContents WHERE DatabaseName LIKE ('%'+TRIM(@DB_to_Exclude)+'%')
						FETCH NEXT FROM excluder INTO @DB_to_Exclude
                    END
				CLOSE excluder
				DEALLOCATE excluder
			END			
			------------------------------------------------------------------------------------------------------------
			---- Including @Include_DBName_Filter databases and excluding others ---------------------------------------
			IF @Include_DBName_Filter <> ''
			BEGIN
				
				ALTER TABLE #DirContents ADD flag BIT NOT NULL DEFAULT 0
				
				DECLARE @DB_to_Include sysname
				DECLARE includer CURSOR FOR SELECT * FROM STRING_SPLIT(@Include_DBName_Filter,',')
				OPEN includer
					FETCH NEXT FROM includer INTO @DB_to_Include
					WHILE @@FETCH_STATUS = 0
					BEGIN
						IF @DB_to_Include <> ''
							UPDATE #DirContents SET flag = 1 WHERE DatabaseName LIKE ('%'+TRIM(@DB_to_Include)+'%')
						FETCH NEXT FROM includer INTO @DB_to_Include
                    END
				CLOSE includer
				DEALLOCATE includer
				
				DELETE FROM #DirContents WHERE flag = 0
				
			END
			------------------------------------------------------------------------------------------------------------
		END TRY		
        BEGIN CATCH
			RAISERROR('Probably STRING_SPLIT function was not recognized by the tsql interpreter. For that your database compatibility level must be 130 or higher.',16,1)
			RETURN 1
        END CATCH
        ----- End applying @Exclude_DBName_Filter and @Include_DBName_Filter filters------------------------------------

		;WITH T
		AS
		(
		SELECT  ROW_NUMBER() OVER (PARTITION BY DatabaseName  ORDER BY BackupFinishDate DESC) AS Radif , DatabaseName as database_name, [file]
		FROM #DirContents
		WHERE [BackupTypeDescription] in ('Database','Partial') 
		)
		INSERT INTO #t
		SELECT T.database_name dbname, [file] [path]		
		FROM T 
		WHERE T.Radif = 1
		ORDER BY 1

						
  END
  else
  begin
	raiserror('A backup root must be specified',16,1)
	return 1
  end
  	
  	IF ((select count(*) from #DirContents)=0)
	begin
  		RAISERROR('Fatal error: No backups exist within the folder you specified for your backup root or its subdirectories with the given criteria.',16,1)
		return 1
	end
  
  
  
  		PRINT('')
		PRINT('DATABASES TO RESTORE:')
		PRINT('---------------------')		
		DECLARE @Databases NVARCHAR(500) = (SELECT STRING_AGG(dbname,CHAR(10)) FROM #t)
		PRINT @Databases
		PRINT('')
		declare RestoreResults cursor for select * from #t
		open RestoreResults
			-------------------------------------------------------------------------
			IF OBJECT_ID('tempdb..FaultyBackupskjfjko340fksmlkf_4io3o44of') IS null
				CREATE TABLE tempdb..FaultyBackupskjfjko340fksmlkf_4io3o44of 
				(
					ErrorID int IDENTITY NOT NULL,
					SourceDatabaseName sysname NOT NULL,
					DestinationDatabaseName sysname NOT NULL,
					BackupFilePath NVARCHAR(1000),
					RestoreStartTime DATETIME NOT NULL,
					ErrorProcedure sysname NOT NULL,
					ErrorNo INT,
					ErrorSeverity TINYINT,
					ErrorState TINYINT,
					ErrorLine INT,
					ErrorMessage VARCHAR(MAX)								
				)

			fetch next from RestoreResults into @DatabaseName, @Backup_Path			
			while @@FETCH_STATUS = 0
			begin
				
				DECLARE @SourceDatabaseName sysname = @DatabaseName
				--SET @DatabaseName += @Destination_Database_Name_suffix; 
-------------------------------------------------------------------------------------------------------------------------------					
					EXEC sp_complete_restore    @Drop_Database_if_Exists = @Drop_Database_if_Exists,
												@Restore_DBName = @DatabaseName,
												@Restore_Suffix = @Destination_Database_Name_suffix,
												@Backup_Location = @Backup_Path,
												@Destination_Database_DataFiles_Location = @Destination_Database_DataFiles_Location ,	-- If the database exists, this parameter assignment will be ignored
												@Destination_Database_LogFile_Location = @Destination_Database_LogFile_Location,		-- If the database exists, this parameter assignment will be ignored
												@Take_tail_of_log_backup = @Take_tail_of_log_backup,
												@Keep_Database_in_Restoring_State  = @Keep_Database_in_Restoring_State,				-- If equals to 1, the database will be kept in restoring state until the whole process of restoring
												@DataFileSeparatorChar  = '_',														-- This parameter specifies the punctuation mark used in data files names. For example "_"
												@Change_Target_RecoveryModel_To = @Change_Target_RecoveryModel_To,
												@Set_Target_Database_ReadOnly = @Set_Target_Databases_ReadOnly,
												@STATS = @STATS,
												@Delete_Backup_File = @Delete_Backup_File
-------------------------------------------------------------------------------------------------------------------------------				
				fetch next from RestoreResults into @DatabaseName, @Backup_Path
			end 
		CLOSE RestoreResults
		DEALLOCATE RestoreResults
		PRINT('-----------------------------------------------------------------------------------------------------------')
  				
	
--	select * from tempdb.._46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
	drop table tempdb.._46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
  
END

GO

--=============================================================================================================================

exec sp_restore_latest_backups 
	@Drop_Database_if_Exists = 0,
									-- (Optional) Turning this feature on is not recommended because 'replace' option of the restore command, transactionally drops the
									-- existing database first and then restores the backup. That means if restore fails, drop also will not commit, a procedure
									-- which cannot be implemented by the tsql programmer (alter database, drop database, restore database commands cannot be put into a user
									-- transaction). But if you want a clean restore (Currently I don't know what the difference between 'restore with replace' and 'drop and restore'
									-- is except for what I said which is an advantage of 'restore with replace'), set this parameter to 1, however it's risky and not
									-- recommended because if the restore operation fails, the drop operation cannot be reverted and you will lose the existing database. If you
									-- don't set this parameter to 1, the 'replace' option of the restore command will be used anyway. 
									-- Note: if you want to use this parameter only to relocate database files 'replace' command does this for you and you don't need to use this
									-- parameter. Generally, use this parameter as a last resort on a manual execution basis.

	@Destination_Database_Name_suffix = N'',
  									-- (Optional) You can specify the destination database names' suffix here. If the destination database name is equal to the backup database name,
  									-- the database will be restored on its own. Leave empty to do so.
	@Destination_Database_DataFiles_Location = 'same',			
  									-- (Optional) This script creates the folders if they do not exist automatically. Make sure SQL Service has permission to create such folders
  									-- This variable must be in the form of for example 'D:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\DATA'. If left empty,
									-- the datafiles will be restored to destination servers default directory. If given 'same', the script will try to put datafiles to
									-- exactly the same path as the original server. One of the situations that you can benefit from this, is if your destination server
									-- has an identical structure as your original server, for example it's a clone of it.
									-- if this parameter is set to 'same', the '@Destination_Database_LogFile_Location' parameter will be ignored.
									-- Setting this variable to 'same' also means forcing @Drop_Database_if_Exists to 1
									-- Possible options: 'SAME'|''. '' or NULL means target server's default
	@Destination_Database_LogFile_Location = 'D:\test\testLog',	
									-- (Optional) If @Destination_Database_DataFiles_Location parameter is set to same, the '@Destination_Database_LogFile_Location' parameter will be ignored.
	@Backup_root = N'e:\TestBackup',		
									-- (*Mandatory) Root location for backup files.
	@Exclude_DBName_Filter = N'',					
									-- (Optional) Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
									-- N'Northwind,AdventureWorks, StackOverFlow'. The script excludes databases that contain any of such keywords
									-- in the name like AdventureWorks2019. Note that space at the begining and end of the names will be disregarded
  
	@Include_DBName_Filter = N'',					
									-- (Optional) Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
									-- N'Northwind,AdventureWorks, StackOverFlow'. The script includes databases that contain any of such keywords
									-- in the name like AdventureWorks2019 and excludes others. Note that space at the begining and end of the names
									-- will be disregarded.

	@IncludeSubdirectories = 1,		-- (Optional) Choose whether to include subdirectories or not while the script is searching for backup files.
	@Keep_Database_in_Restoring_State = 0,						
									-- (Optional) If equals to 1, the database will be kept in restoring state
	@Take_tail_of_log_backup = 0,
																
	@DataFileSeparatorChar = '_',		
									-- (Optional) This parameter specifies the punctuation mark used in data files names. For example "_"
									-- in 'NW_sales_1.ndf' or "$" in 'NW_sales$1.ndf'.
	@Change_Target_RecoveryModel_To = 'same',
									-- (Optional) Set this variable for the target databases' recovery model. Possible options: FULL|BULK-LOGGED|SIMPLE|SAME
									-- If the chosen option is simple, the log file will also shrink
	@Set_Target_Databases_ReadOnly = 0,
									-- (Optional)
	@STATS = 50,
									-- (Optional)
	@Delete_Backup_File = 0
									-- (Optional) Turn this feature on to delete the backup files that are successfully restored.
							   