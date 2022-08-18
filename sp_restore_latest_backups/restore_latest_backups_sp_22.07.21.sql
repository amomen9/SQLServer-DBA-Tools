
-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2021.03.12>
-- Latest Update Date:	<22.04.22>
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

TODO: 
	  
	  
	  1. Log support
	  2. Increase permissions after restore
	  3. attach detached datafiles

*/

USE master
GO

/* If you want to your retention policy be in table variable format you may use this. I have used JSON datatype
--============== Retention Policy Type ===================================================================

--DROP TYPE IF EXISTS Retention_Policy
IF not EXISTS (SELECT 1 FROM sys.types WHERE name = 'Retention_Policy')
	CREATE TYPE Retention_Policy AS TABLE   
		( [From (n) Days Ago] INT NOT NULL  
		, [To (n) Days Ago] INT NULL  
		, [Backup Retention Interval Every (n) Days] INT NOT NULL 
		);  
ELSE
	PRINT 'Warning! The Retention_Policy type already exists, it may be different than what this stored procedure needs.'
GO
*/
--BEGIN TRY
--	DECLARE @sql NVARCHAR(500)
--	SET @sql =
--	'
CREATE OR alter FUNCTION dbo.fn_FileExists(@path varchar(512))
RETURNS BIT
AS
BEGIN
		DECLARE @result INT
		EXEC master.dbo.xp_fileexist @path, @result OUTPUT
		RETURN cast(@result as bit)
END;
--	'
--	EXEC (@sql)
--END TRY
--BEGIN CATCH
--END CATCH
GO

--============== First SP ================================================================================

-- This SP is called by the main SP
create or alter procedure sp_BackupDetails 
	@Backup_Path nvarchar(1000) = N'E:\Backup\test_read-only\NW_FG-Archive_Full_0244.bak'
As
BEGIN
	set nocount on
	drop table if exists #tmp
	--drop table if exists #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
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

		INSERT #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
		select DatabaseName, LastLSN, BackupFinishDate, BackupTypeDescription from #tmp
		

END
GO

--======= Second SP =====================================================================================================

--- This SP is called by the main SP:
create or alter proc sp_complete_restore
	@Drop_Database_if_Exists BIT = 0,
	@Restore_DBName sysname,
	@Restore_Suffix sysname = '',
	@Restore_Prefix sysname = '',
	@Ignore_Existant BIT = 0,									
	@Backup_Location nvarchar(1000),
	@Destination_Database_DataFiles_Location nvarchar(300) = '',			
	@Destination_Database_LogFile_Location nvarchar(300) = '',
	@Destination_Database_Datafile_suffix NVARCHAR(128) = '',
	@Take_tail_of_log_backup bit = 1,
	@Keep_Database_in_Restoring_State bit = 0,					-- If equals to 1, the database will be kept in restoring state until the whole process of restoring
	@DataFileSeparatorChar nvarchar(2) = '_',					-- This parameter specifies the punctuation mark used in data files names. For example "_"
	@STATS TINYINT = 50,
	@Generate_Statements_Only bit = 0,
	-- post-restore operations
	@Delete_Backup_File BIT = 0,
	@Change_Target_RecoveryModel_To NVARCHAR(20) = 'same',		-- Possible options: FULL|BULK-LOGGED|SIMPLE|SAME
	@Set_Target_Database_ReadOnly BIT = 0,
	@ShrinkDatabase_policy SMALLINT = -2,						-- Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave %x of free space after shrinking 
	@ShrinkLogFile_policy SMALLINT = -2,						-- Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave x MBs of free space after shrinking 
	@RebuildLogFile_policy VARCHAR(64) = '',					-- Possible options: NULL or Empty string: Do not rebuild | 'x:y:z' (For example, 4MB:64MB:1024MB) rebuild to SIZE = x, FILEGROWTH = y, MAXSIZE = z. If @RebuildLogFile_policy is specified, @ShrinkLogFile_policy will be ignored.
	@GrantAllPermissions_policy SMALLINT = -2					-- Possible options: -2: Do not alter permissions | 1: Make every current DB user, a member of db_owner group | 2: Turn on guest account and make guest a member of db_owner group

	
AS
BEGIN
  set nocount ON
  
  DECLARE @OriginalDBName sysname = @Restore_DBName
  DECLARE @ErrMsg NVARCHAR(256)
  IF @GrantAllPermissions_policy NOT IN (-2,1,2) RAISERROR('Invalid option for @GrantAllPermissions_policy was specified.',16,1)
  SET @GrantAllPermissions_policy = ISNULL(@GrantAllPermissions_policy,-2)
  SET @ShrinkDatabase_policy = ISNULL(@ShrinkDatabase_policy,-2)
  SET @ShrinkLogFile_policy = ISNULL(@ShrinkLogFile_policy,-2)
  SET @STATS = ISNULL(@STATS,0)
  SET @Restore_Suffix = ISNULL(@Restore_Suffix,'')
  SET @Restore_Prefix = ISNULL(@Restore_Prefix,'')
  SET @Restore_DBName = @Restore_Prefix + @Restore_DBName + @Restore_Suffix
  IF (@Change_Target_RecoveryModel_To IS NULL) OR (@Change_Target_RecoveryModel_To = '') SET @Change_Target_RecoveryModel_To = 'same'
  SET @Destination_Database_Datafiles_Location = ISNULL(@Destination_Database_Datafiles_Location,'')
  SET @Destination_Database_LogFile_Location = ISNULL(@Destination_Database_Logfile_Location,'')
  SET @RebuildLogFile_policy = ISNULL(@RebuildLogFile_policy,'')

  DECLARE @Back_DateandTime nvarchar(20) = (select replace(convert(date, GetDate()),'-','.') + '_' + substring(replace(convert(nvarchar(10),convert(time, GetDate())), ':', ''),1,4) )
  Declare @DB_Restore_Script nvarchar(max) = ''
  declare @DropDatabaseStatement nvarchar(max) = ''
  
  IF (ISNULL(@OriginalDBName,'')='') 
  BEGIN
	RAISERROR('@OriginalDBName must be specified.',16,1)
	RETURN 1
  END
  
  IF (@Change_Target_RecoveryModel_To NOT IN ('FULL','BULK-LOGGED','SIMPLE','SAME'))
  BEGIN
	RAISERROR('Target recovery model specified is not a recognized SQL Server recovery model.',16,1)
	RETURN 1
  END

  IF (@Destination_Database_Datafiles_Location = '')
  BEGIN
    	set @Destination_Database_Datafiles_Location = convert(nvarchar(1000),(select SERVERPROPERTY('InstanceDefaultDataPath')))
  END
  IF (@Destination_Database_LogFile_Location = '')
  BEGIN
    	set @Destination_Database_Logfile_Location = convert(nvarchar(1000),(select SERVERPROPERTY('InstanceDefaultLogPath')))
  END
  SELECT @Destination_Database_Logfile_Location, convert(nvarchar(1000),(select SERVERPROPERTY('InstanceDefaultLogPath')))
  ----------------------------------------------- Restoring Database:
		BEGIN try
    		  		
  			print('-----------------------------------------------------------------------------------------------------------')

			-------------------------------------------------------------------

  			IF( DB_ID(@Restore_DBName) is not null ) -- restore database on its own
  			BEGIN
  				IF (@Ignore_Existant = 1)
				BEGIN
					PRINT('Nothing was restored as @Ignore_Existant was set to 1 and the target database already exists.')
					PRINT ''
					RETURN 0
                END
				PRINT ('--'+@Restore_DBName+': (Replaces Existing Database)')

					

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
  				IF (SELECT state FROM sys.databases WHERE name = @Restore_DBName) in (0,4,5)	-- state 0 means database is online 4 suspect 5 emergency
				begin
					SET @DB_Restore_Script += 'use '+ QUOTENAME(@Restore_DBName) + ' ALTER database ' + QUOTENAME(@Restore_DBName) + ' set single_user with rollback immediate
						'
					IF (@Generate_Statements_Only = 0 AND @Ignore_Existant = 0)
						EXECUTE (@DB_Restore_Script)
					SET @DB_Restore_Script = ''
				
  					if (@isPseudoSimple_or_Simple != 1 and @Take_tail_of_log_backup = 1) -- check if the database has not SIMPLE or PseudoSIMPLE recovery model
					BEGIN
						DECLARE @Tail_of_Log_Backup_Script NVARCHAR(max)
						Declare @TailofLOG_Backup_Name nvarchar(100) = 'TailofLOG_' + @Restore_DBName+'_Backup_'+@Back_DateandTime+'.trn'
  						set @Tail_of_Log_Backup_Script = 'BACKUP LOG ' + QUOTENAME(@Restore_DBName) + ' TO DISK = ''' + @TailofLOG_Backup_Name + ''' WITH FORMAT,  NAME = ''' + @TailofLOG_Backup_Name + ''', NOREWIND, NOUNLOAD,  NORECOVERY 
  						'
						IF (@Generate_Statements_Only = 0)
							EXEC (@Tail_of_Log_Backup_Script)					
					
					END  
				END
				---- Dropping database if exists, before restoring, on user request ------
				IF (@Drop_Database_if_Exists = 1)
				BEGIN										
					SET @DropDatabaseStatement += 'DROP database ' + @Restore_DBName + CHAR(10)					
					GOTO restoreanew

				END
				--------------------------------------------------------------------------
/*
  				set @DB_Restore_Script = 'RESTORE DATABASE ' + QUOTENAME(@Restore_DBName) + ' FROM  DISK = ''' + @Backup_Location + ''' WITH  FILE = 1, NOUNLOAD, replace' + IIF(@STATS = 0,'',(', STATS = ' + CONVERT(varchar(3),@STATS)))
  				if (@Keep_Database_in_Restoring_State = 1)  				
  					set @DB_Restore_Script += ',  NORECOVERY'
*/  				
  				
				
					
  
  			END 
			ELSE
				PRINT ('--'+@Restore_DBName+' (New Database)')
			PRINT ''
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
					
--				IF (@Destination_Database_DataFiles_Location <> 'same')
				BEGIN                
  					
					IF (@Generate_Statements_Only = 0 AND CHARINDEX(':',@Destination_Database_DataFiles_Location) <> 0)
					begin
  						EXEC xp_create_subdir @Destination_Database_DataFiles_Location
  						EXEC xp_create_subdir @Destination_Database_LogFile_Location
					end
					

------------------ Adding move statements:---------------------------	
-- [File Exists] here cannot be turned into a computed column, because then you have to create the fuction inside tempdb, and when you want
-- to reexecute this script instantly the temp table most likely is not disposed yet, it takes some time for this table to be disposed
-- (A SQL Server bug in my opinion), that's why the function
-- cannot be recreated due to the dependancy of temp table on the function, therefore an error will be raised which is not the problem of this
-- script and is SQL Server's itself. That's why computed column cannot be used. Suppressing the error also appeared to be not a correct decision

					CREATE TABLE #temp2 
					(
						head NVARCHAR(500) NOT NULL,
						tail NVARCHAR(1000) NOT NULL,
						type CHAR(1),
						[File Exists] bit
					)
					
					INSERT #temp2 (head, tail, type, [File Exists])					
						SELECT head, dt.tail, dt.Type, dbo.fn_FileExists(tail) from
						(
  						
  							select ',MOVE N''' + LogicalName + ''' TO N''' head, 
							CASE when Type = 'L' then 
							IIF
							(
								@Destination_Database_LogFile_Location <> 'same',@Destination_Database_LogFile_Location, LEFT(PhysicalName, (LEN(PhysicalName) - CHARINDEX('\',REVERSE(PhysicalName))))
							)
							ELSE 
							IIF
							(
								@Destination_Database_DataFiles_Location <> 'same',@Destination_Database_DataFiles_Location, LEFT(PhysicalName, (LEN(PhysicalName) - CHARINDEX('\',REVERSE(PhysicalName))))
							)
							END
							+ '\' + 
							iif(CHARINDEX(@OriginalDBName,RIGHT(PhysicalName,CHARINDEX('\', REVERSE(PhysicalName))))<>0
									,REPLACE(RIGHT(PhysicalName,(CHARINDEX('\', REVERSE(PhysicalName))-1)),@OriginalDBName,@Restore_DBName)
									,@Restore_DBName+'_'+RIGHT(PhysicalName,(CHARINDEX('\', REVERSE(PhysicalName))-1))) 
							-- Put SeparatorChar* or .extension after @Restore_DBName:
							/*
							RIGHT(PhysicalName, (CASE WHEN charindex(@DataFileSeparatorChar, RIGHT(PhysicalName,CHARINDEX('\', REVERSE(PhysicalName)))) <> 0 then charindex(@DataFileSeparatorChar,reverse(PhysicalName)) ELSE charindex('.',reverse(PhysicalName)) END)) + '''' + '
							'
							*/
							AS tail,
							Type
  							from #Backup_Files_List

						) dt
						SELECT * FROM #temp2
						SELECT @Destination_Database_LogFile_Location
						DECLARE @ReplaceFlag BIT
                        DECLARE @ReplaceFlagComp NVARCHAR(500)
						DECLARE @ReplaceFlagParams NVARCHAR(100) = '@ReplaceFlag BIT out'
						DECLARE @ServerCollation NVARCHAR(200) = CONVERT(NVARCHAR(200),SERVERPROPERTY('Collation'))
						SET @ReplaceFlagComp =
						'
							--DECLARE @ReplaceFlag BIT
							if (select 1 from sys.databases where name = '''+@Restore_DBName+''') is not null
								select @ReplaceFlag = iif(count(*)<>0,0,1) from
								(
									select tail from #temp2 where [File Exists] = 1
									except
									select physical_name collate ' + @ServerCollation + ' from '+QUOTENAME(@Restore_DBName)+'.sys.database_files																		
								) dt
						'
						
						EXEC sys.sp_executesql @ReplaceFlagComp, @ReplaceFlagParams, @ReplaceFlag out

					--SELECT @Restore_DBName,@OriginalDBName
					WHILE @ReplaceFlag = 0 and
						(SELECT COUNT(*) FROM #temp2 WHERE [File Exists] = 1) <> 0 
					BEGIN
						--print 'while was run'
						UPDATE  #temp2 SET tail = LEFT(tail,LEN(tail)-4)+'_2'+RIGHT(tail,4) 
						UPDATE #temp2 SET [File Exists] = dbo.fn_FileExists(tail)
					end	

					
  					select @DB_Restore_Script += head+tail+'''
					'
  					from #temp2

--------------------------------------------------------------------  
				end
--				ELSE 
----------------Creating necessary directories for 'same' option ----------------------------------------------------
					IF (@Generate_Statements_Only = 0 )
					BEGIN
						declare @DirPath nvarchar(1000)
						IF @Destination_Database_DataFiles_Location = 'same'
						begin
							DECLARE mkdir cursor for 
								SELECT PhysicalName from #Backup_Files_List
							WHERE Type<>'L'
							open mkdir
								
								fetch next from mkdir into @DirPath
								while @@FETCH_STATUS = 0
								begin
									select @DirPath = left(@DirPath, (len(@DirPath)-charindex('\',REVERSE(@DirPath))))
									IF (SELECT file_is_a_directory FROM sys.dm_os_file_exists(LEFT(@DirPath,2))) = 1
										EXECUTE xp_create_subdir @DirPath										
									ELSE
									BEGIN
										SET @ErrMsg = 'Warning! The storage drive letter ('+LEFT(@DirPath,2)+') to which you wish to restore one of your database files does not exist. The restore will fail.'
										PRINT @ErrMsg
										PRINT ''
										BREAK
									end
									fetch next FROM mkdir into @DirPath
								end 
							CLOSE mkdir
							DEALLOCATE mkdir
						END
						IF @Destination_Database_LogFile_Location = 'same'
						BEGIN
							DECLARE mkdir cursor for 
								SELECT PhysicalName from #Backup_Files_List
							WHERE type = 'L'
							open mkdir
								
								fetch next from mkdir into @DirPath
								while @@FETCH_STATUS = 0
								begin
									select @DirPath = left(@DirPath, (len(@DirPath)-charindex('\',REVERSE(@DirPath))))
									IF (SELECT file_is_a_directory FROM sys.dm_os_file_exists(LEFT(@DirPath,2))) = 1
										EXECUTE xp_create_subdir @DirPath										
									ELSE
									BEGIN
										SET @ErrMsg = 'Warning! The storage drive letter ('+LEFT(@DirPath,2)+') to which you wish to restore one of your database files does not exist. The restore will fail.'
										PRINT @ErrMsg
										PRINT ''
										BREAK
									end
									fetch next FROM mkdir into @DirPath
								end 
							CLOSE mkdir
							DEALLOCATE mkdir
                        END
					END
--------------------End creating necessary directories for 'same' option----------------------------------------------------------------------------


                if (@Keep_Database_in_Restoring_State = 1)  				
  					set @DB_Restore_Script += ',NORECOVERY'
  					
  				

  				select @DB_Restore_Script += ',NOUNLOAD, REPLACE' + IIF(@STATS = 0,'',(', STATS = ' + CONVERT(varchar(3),@STATS)))

											  
  			
  			END	
  				print (@DB_Restore_Script)
				IF (@Generate_Statements_Only = 0)
				begin
  					EXEC (@DB_Restore_Script)
					SET @temp1 = 
								'USE ' + QUOTENAME(@Restore_DBName) + '
								 ALTER DATABASE ' + QUOTENAME(@Restore_DBName) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE'
					EXEC (@temp1)
					PRINT('')
					PRINT(char(10)+'End '+ @Restore_DBName +' Database Restore') 
				END
				ELSE
					PRINT '--Nothing was restored as @Generate_Statements_Only was set to 1'
					
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

				--PRINT('')
				--IF @Generate_Statements_Only = 0
  		--			PRINT(char(10)+'End '+ @Restore_DBName +' Database Restore') 
				--ELSE
				--	PRINT '--Nothing was restored as @Generate_Statements_Only was set to 1'
				
				
  			--*** Postprocessing operations:      		
  			if ((SELECT state FROM sys.databases WHERE name = @Restore_DBName) = 0 AND @Generate_Statements_Only = 0)
			BEGIN
				
				DECLARE @temp5 varchar(4000) = ''
				IF (@Change_Target_RecoveryModel_To <> 'same')
					SET @temp5 = 'ALTER DATABASE ' + QUOTENAME(@Restore_DBName) + ' SET RECOVERY ' + @Change_Target_RecoveryModel_To + CHAR(10)
				

				-- Begining shrink/log rebuild operations, if user requests:
				IF @RebuildLogFile_policy <>''
				BEGIN
					DECLARE @SIZE VARCHAR(20),
							@MAXSIZE VARCHAR(20),
							@FILEGROWTH VARCHAR(20)
					-- I liked to use cte instead of creating temp table to split @RebuildLogFile_policy
					;WITH cte AS
                    (
						SELECT row,dto.value
						FROM
						(
							SELECT ROW_NUMBER() OVER (PARTITION BY row ORDER BY row) row2,
							* 
							FROM 
							(
								SELECT * 
								FROM 
								STRING_SPLIT(@RebuildLogFile_policy,':'), (SELECT 1 row UNION ALL SELECT 2 UNION ALL SELECT 3) dtrow
							) dt
						) dto
						WHERE dto.row = row2
					)
					SELECT  @SIZE			= (SELECT value FROM cte WHERE row = 1),
							@MAXSIZE		= (SELECT value FROM cte WHERE row = 2),
							@FILEGROWTH		= (SELECT value FROM cte WHERE row = 3)
					SELECT TOP 1 @DirPath = tail FROM #temp2 WHERE type = 'L'
					SET @DirPath = left(@DirPath, (len(@DirPath)-charindex('\',REVERSE(@DirPath))))
					PRINT ''
					SET @temp1 =
					'
						alter database ' + QUOTENAME(@Restore_DBName) + ' set emergency


						ALTER DATABASE ' + QUOTENAME(@Restore_DBName) + '
						   REBUILD LOG ON (Name = ''' + @Restore_DBName + '_$$$newLog'' , FILENAME=''' + @DirPath + '\' + @Restore_DBName + '_$$$newLog.ldf'', SIZE = '+@SIZE+', MAXSIZE = '+@MAXSIZE+', FILEGROWTH = '+@FILEGROWTH+')

						alter database ' + QUOTENAME(@Restore_DBName) + ' set ONLINE

						alter database ' + QUOTENAME(@Restore_DBName) + ' set multi_user
					'					
					
					EXEC (@temp1)

					-- Now deleting the privious log files iteratively:
					DECLARE @Log_Path NVARCHAR(512)
					DECLARE delete_log CURSOR FOR
						SELECT tail FROM #temp2 WHERE type = 'L'
					OPEN delete_log
						FETCH NEXT FROM delete_log INTO @Log_Path
						WHILE @@FETCH_STATUS = 0
						BEGIN
							EXEC sys.xp_delete_files @Log_Path
							FETCH NEXT FROM delete_log INTO @Log_Path
						END
					CLOSE delete_log
					DEALLOCATE delete_log
					SET @temp1 = 
					'
						print ''Log file was successfully rebuilt to new ''+'''+@SIZE+'''+'' size:''+char(10)+''Note: There is no risk of ''''Transactional inconsistency'''', in this stored procedure specifically, despite the warning message that Microsoft has generated above and you do not need to run CHECKDB for this in particular. Also, the extra log files have been deleted.''
					'
					EXEC(@temp1)

                END
				ELSE		-- Shrink Log File if the user has not chosen to rebuild it.
					IF (@ShrinkLogFile_policy >= -1)
					BEGIN
						SET @temp5 = 'declare @SQL nvarchar(500)'+CHAR(10)
						SET @temp5 += 'PRINT ''--===Begining the Logfile shrink op:''' + CHAR(10) +
									'USE ' + QUOTENAME(@Restore_DBName) + CHAR(10) + 
									'declare @FileName sysname = (select top 1 name from sys.database_files where type=1 order by create_lsn desc)' + CHAR(10) +
									'SET @SQL = ''DBCC SHRINKFILE(''+''''''''+@FileName+''''''''+'','+
									IIF(@ShrinkLogFile_policy=-1,(CONVERT(VARCHAR(10),0)+', TRUNCATEONLY'),CONVERT(VARCHAR(10),@ShrinkLogFile_policy))+
									') WITH NO_INFOMSGS''' + CHAR(10) +
									'exec (@SQL)' + CHAR(10)
						EXEC(@temp5)
					END
				IF (@ShrinkDatabase_policy >= -1)
				BEGIN
					SET @temp5 = 'declare @SQL nvarchar(500)'+CHAR(10)
					SET @temp5 += 'PRINT ''--===Begining the DB shrink op:''' + CHAR(10) +
								'USE ' + QUOTENAME(@Restore_DBName) + CHAR(10) + 
					
								'SET @SQL = ''DBCC SHRINKDATABASE(''+'''+QUOTENAME(@Restore_DBName)+'''+'''+
								IIF(@ShrinkLogFile_policy=-1,'',' ,'+CONVERT(VARCHAR(10),@ShrinkLogFile_policy))+
								') WITH NO_INFOMSGS''' + CHAR(10) +
								'exec (@SQL)' + CHAR(10)
					EXEC(@temp5)
				END

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

				-----========= Begin grant permissions:
				IF @GrantAllPermissions_policy = 1
				BEGIN
					
					SET @temp5 = 'PRINT ''--===Begining the Grant all permissions(1) op:''' + CHAR(10) +
					'
						use '+quotename(@Restore_DBName)+'
						DECLARE @sql NVARCHAR(max)	
						DECLARE @USERNAME sysname 
						DECLARE InnerDB CURSOR FOR
							SELECT name FROM sys.database_principals WHERE principal_id BETWEEN 4 AND 16380 AND (CHARINDEX(''.'',name)<>0) AND type IN (''s'',''u'')
						OPEN InnerDB
							FETCH NEXT FROM InnerDB INTO @USERNAME
							WHILE @@FETCH_STATUS = 0
							BEGIN
									declare @ErrMsg nvarchar(max)
		
									BEGIN try
			
										set @sql =
										''
									
											ALTER ROLE [db_owner] ADD MEMBER ''+QUOTENAME(@USERNAME)+''
									
											--drop user ''+QUOTENAME(@USERNAME)+''
				
										''
										exec (@sql)

									END TRY
									BEGIN CATCH
										set @ErrMsg = db_name()+''::''+@USERNAME+''::''+ERROR_MESSAGE()
										raiserror(@ErrMsg,16,1)
									END CATCH
	

									FETCH NEXT FROM InnerDB INTO @USERNAME
								END
							CLOSE InnerDB
							DEALLOCATE InnerDB
							-- Just because one of my colleagues once asked me:
							IF exists (select 1 from sys.database_principals where name = ''db_developer'')
							BEGIN
								SET @sql = ''GRANT CONTROL TO db_developer''
								EXEC(@sql)
							END
					'
					EXEC(@temp5)
				END

				IF @GrantAllPermissions_policy = 2
				BEGIN
					
					SET @temp5 = 'PRINT ''--===Begining the Grant all permissions(2) op:''' + CHAR(10) +
					'
						use '+quotename(@Restore_DBName)+'
						GRANT CONNECT TO [GUEST]
						ALTER ROLE [db_owner] ADD MEMBER [GUEST]
						DECLARE @sql NVARCHAR(max)	
						DECLARE @USERNAME sysname 
						DECLARE InnerDB CURSOR FOR
							SELECT name FROM sys.database_principals WHERE principal_id BETWEEN 4 AND 16380 AND (CHARINDEX(''.'',name)<>0) AND type IN (''s'',''u'')
						OPEN InnerDB
							FETCH NEXT FROM InnerDB INTO @USERNAME
							WHILE @@FETCH_STATUS = 0
							BEGIN
									declare @ErrMsg nvarchar(max)
		
									BEGIN try
			
										set @sql =
										''
									
											--ALTER ROLE [db_owner] ADD MEMBER ''+QUOTENAME(@USERNAME)+''
									
											drop user ''+QUOTENAME(@USERNAME)+''
				
										''
										exec (@sql)

									END TRY
									BEGIN CATCH
										set @ErrMsg = db_name()+''::''+@USERNAME+''::''+ERROR_MESSAGE()
										raiserror(@ErrMsg,16,1)
									END CATCH
	

									FETCH NEXT FROM InnerDB INTO @USERNAME
								END
							CLOSE InnerDB
							DEALLOCATE InnerDB
							-- Just because one of my colleagues once asked me:
							IF exists (select 1 from sys.database_principals where name = ''db_developer'')
							BEGIN
								SET @sql = ''GRANT CONTROL TO db_developer''
								EXEC(@sql)
							END
					'
					EXEC(@temp5)
				END

				-----========= End grant permissions
				
				SET @temp5 += 'ALTER DATABASE ' + QUOTENAME(@Restore_DBName) + ' SET MULTI_USER' + CHAR(10) +
							  'PRINT ''|The database is ready for use.|'''
				EXEC(@temp5)

			END
				RETURN 0
			END TRY
			BEGIN CATCH
				PRINT ''
				DECLARE @Severity INT = ERROR_SEVERITY()
				DECLARE @State INT = ERROR_STATE()
				declare @message nvarchar(150) = 'Fatal error: System Message:'+CHAR(10)+ 'Msg '+CONVERT(VARCHAR(50),ERROR_NUMBER())+', Level '+CONVERT(VARCHAR(50),@Severity)+', State '+CONVERT(VARCHAR(50),@State)+', Line '+CONVERT(VARCHAR(50),ERROR_LINE())+'
				' +ERROR_MESSAGE()	
				raiserror(@message, @Severity, @State)	
				
				PRINT 'Ali Momen: This is not my fault Ostad! :D'
				PRINT ''
				RETURN 1
			END CATCH
			
END
GO


--============= Third SP: Main SP =================================================================================

-- Main (Third) SP:

CREATE OR ALTER PROC sp_restore_latest_backups 

  @Drop_Database_if_Exists BIT = 0,
																-- Turning this feature on, potentially means relocating the data files
																-- of already existing databases

  @Ignore_Existant BIT = 0,										
																-- ignore restoring databases that already exist on target
  @Destination_Database_Name_suffix nvarchar(128) = N'',
  																-- You can specify the destination database names' suffix here. If the destination database name is equal to the backup database name,
  																-- the database will be restored on its own.
  @Destination_Database_Name_prefix NVARCHAR(128) = N'',
  @Destination_Database_DataFiles_Location nvarchar(300) = '',			
  																-- This script creates the folders if they do not exist automatically. Make sure SQL Service has permission to create such folders
  																-- This variable must be in the form of for example 'D:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\DATA'
  @Destination_Database_LogFile_Location nvarchar(300) = '',

  @Backup_root_or_path nvarchar(120) = N'e:\Backup',			-- Root location for backup files.
  @BackupFileName_naming_convention NVARCHAR(128) = '',
  @BackupFileName_naming_convention_separator NVARCHAR(2) = '',

  @BackupFileName_RegexFilter NVARCHAR(128) = '',				-- Use this filter to speed file scouring up, if you have too many files in the directory.
  @BackupStartDate_StartDATETIME DATETIME = '1900.01.01',
  @BackupStartDate_EndDATETIME DATETIME = '9999.12.31',
  @USE_SQLAdministrationDB_Database BIT = 0,				-- Create or Update DiskBackupFiles table inside SQLAdministrationDB database for faster access to backup file records and their details.
  @Exclude_system_databases BIT = 1,

  @Exclude_DBName_Filter NVARCHAR(1000) = N'master',				-- Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
																-- N'Northwind,AdventureWorks, StackOverFlow'. The script excludes databases that contain any of such keywords
																-- in the name like AdventureWorks2019. Note that space at the begining and end of the names will be disregarded
  
  @Include_DBName_Filter NVARCHAR(1000) = N'',					-- Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
																-- N'Northwind,AdventureWorks, StackOverFlow'. The script includes databases that contain any of such keywords
																-- in the name like AdventureWorks2019 and excludes others. Note that space at the begining and end of the names
																-- will be disregarded.

  @IncludeSubdirectories BIT = 1,								-- Choosing whether to include subdirectories or not while the script is searching for backup files.  
  
  @Keep_Database_in_Restoring_State bit = 0,					-- If equals to 1, the database will be kept in restoring state
  @Take_tail_of_log_backup bit = 1,
  @DataFileSeparatorChar nvarchar(2) = '_',						-- This parameter specifies the punctuation mark used in data files names. For example "_"
																-- in NW_1.mdf or "$" in NW$1.mdf
  @Change_Target_RecoveryModel_To NVARCHAR(20) = 'same',		-- Possible options: FULL|BULK-LOGGED|SIMPLE|SAME
  @Set_Target_Databases_ReadOnly BIT = 0,
  @Delete_Backup_File BIT = 0,
  @STATS TINYINT = 50,											-- Set this to specify stats parameter of restore statements											
																-- Turn this feature on to delete the backup files that are successfully restored.
  @Generate_Statements_Only bit = 0,
  @Email_Failed_Restores_To NVARCHAR(128) = NULL,
  @Activate_Destination_Database_Containment BIT = 1,
  @Set_Destination_FILESTREAM_Feature_To TINYINT = 2,
  @Stop_On_Error INT = 0,
  @Retention_Policy_Enabled BIT = 0,
  @Retention_Policy NVARCHAR(max) = NULL,
  @ShrinkDatabase_policy SMALLINT = -2,							-- Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave %x of free space after shrinking 
  @ShrinkLogFile_policy SMALLINT = -2,							-- Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave x MBs of free space after shrinking 
  @RebuildLogFile_policy VARCHAR(64) = '',						-- Possible options: NULL or Empty string: Do not rebuild | 'x:y:z' (For example, 4MB:64MB:1024MB) rebuild to SIZE = x, FILEGROWTH = y, MAXSIZE = z. If @RebuildLogFile_policy is specified, @ShrinkLogFile_policy will be ignored.
  @GrantAllPermissions_policy SMALLINT = -2						-- Possible options: -2: Do not alter permissions | 1: Make every current DB user, a member of db_owner group | 2: Turn on guest account and make guest a member of db_owner group

AS
BEGIN
  ---------------------------- Standardization of Customizable Variables:
  
  
  IF @Generate_Statements_Only = 1
	SET @Delete_Backup_File = 0

  IF RIGHT(@Destination_Database_Datafiles_Location, 1) = '\' 
  	SET @Destination_Database_Datafiles_Location = 
  	left(@Destination_Database_Datafiles_Location,(len(@Destination_Database_Datafiles_Location)-1))
  
  IF RIGHT(@Backup_root_or_path, 1) = '\' 
  	SET @Backup_root_or_path = 
  	left(@Backup_root_or_path,(len(@Backup_root_or_path)-1))
  
  --IF RIGHT(@Temp_Working_Directory, 1) = '\' 
  --	SET @Temp_Working_Directory = 
  --	left(@Temp_Working_Directory,(len(@Temp_Working_Directory)-1))
  
  SET @Destination_Database_DataFiles_Location = ISNULL(@Destination_Database_DataFiles_Location,'')  
  IF @Destination_Database_DataFiles_Location = ''
    SET @Destination_Database_DataFiles_Location = convert(nvarchar(300),SERVERPROPERTY('InstanceDefaultDataPath'))
  
  SET @Destination_Database_LogFile_Location = ISNULL(@Destination_Database_LogFile_Location,'')
  IF @Destination_Database_LogFile_Location = ''
    SET @Destination_Database_LogFile_Location = convert(nvarchar(300),SERVERPROPERTY('InstanceDefaultLogPath'))

  
  IF RIGHT(@Destination_Database_DataFiles_Location, 1) = '\' 
	SET @Destination_Database_DataFiles_Location = left(@Destination_Database_DataFiles_Location,(len(@Destination_Database_DataFiles_Location)-1))

  IF RIGHT(@Destination_Database_LogFile_Location, 1) = '\' 
	SET @Destination_Database_LogFile_Location = left(@Destination_Database_LogFile_Location,(len(@Destination_Database_LogFile_Location)-1))

  SET @Exclude_DBName_Filter = ISNULL(@Exclude_DBName_Filter,'')
  SET @Exclude_system_databases = ISNULL(@Exclude_system_databases,0)
  SET @Include_DBName_Filter = ISNULL(@Include_DBName_Filter,'')
  SET @Drop_Database_if_Exists = ISNULL(@Drop_Database_if_Exists,0)
  SET @IncludeSubdirectories = ISNULL(@IncludeSubdirectories,1)
  SET @Keep_Database_in_Restoring_State = ISNULL(@Keep_Database_in_Restoring_State,0)
  SET @Take_tail_of_log_backup = ISNULL(@Take_tail_of_log_backup,1)
  SET @Set_Target_Databases_ReadOnly = ISNULL(@Set_Target_Databases_ReadOnly,0)
  SET @Delete_Backup_File = ISNULL(@Delete_Backup_File,0)
  SET @Destination_Database_Name_suffix = ISNULL(@Destination_Database_Name_suffix,'')
  
  set @Backup_root_or_path = isNULL(@Backup_root_or_path,'')
  SET @BackupFileName_naming_convention = ISNULL(@BackupFileName_naming_convention,'')
  SET @BackupFileName_naming_convention_separator = ISNULL(@BackupFileName_naming_convention_separator,'')
  --SET @Temp_Working_Directory = ISNULL(@Temp_Working_Directory,'')
  SET @DataFileSeparatorChar = ISNULL(@DataFileSeparatorChar,'_')
  SET @Change_Target_RecoveryModel_To = ISNULL(@Change_Target_RecoveryModel_To,'same')
  SET @Email_Failed_Restores_To = ISNULL(@Email_Failed_Restores_To,'')
  SET @Backup_root_or_path = REPLACE(@Backup_root_or_path,'"','')
  SET @Destination_Database_DataFiles_Location = REPLACE(@Destination_Database_DataFiles_Location,'"','')
  SET @Destination_Database_LogFile_Location = REPLACE(@Destination_Database_LogFile_Location,'"','')
  SET @Stop_On_Error = ISNULL(@Stop_On_Error,0)
  --SET @Destination_Database_Datafile_suffix = ISNULL(@Destination_Database_Datafile_suffix,'')
  SET @RebuildLogFile_policy = ISNULL(@RebuildLogFile_policy,'')
  SET @BackupFileName_RegexFilter = ISNULL(@BackupFileName_RegexFilter,'')
  
  SET @BackupStartDate_StartDATETIME = ISNULL(@BackupStartDate_StartDATETIME,'1900.01.01')
  SET @BackupStartDate_EndDATETIME = ISNULL(@BackupStartDate_EndDATETIME,'9999.12.31')
  SET @USE_SQLAdministrationDB_Database = ISNULL(@USE_SQLAdministrationDB_Database,0)				

  --------------- Other Variables: !!!! Warning: Please do not modify these variables !!!!
  
  DECLARE @SQL NVARCHAR(max)
  IF @Exclude_system_databases = 1
  BEGIN
	IF @Exclude_DBName_Filter <> ''
		SET @Exclude_DBName_Filter+=','
	SET @Exclude_DBName_Filter+='master,msdb,model'
  end  

  IF @Activate_Destination_Database_Containment = 1
		EXEC sp_configure 'contained database authentication', 1; RECONFIGURE WITH OVERRIDE;

	IF @Set_Destination_FILESTREAM_Feature_To > 0
		BEGIN TRY
			EXEC sys.sp_configure N'filestream access level', @Set_Destination_FILESTREAM_Feature_To; RECONFIGURE WITH OVERRIDE;
        END TRY
		BEGIN CATCH
			PRINT 'FILESTREAM feature cannot be enabled. Reason:'
			PRINT (ERROR_MESSAGE())
		END CATCH

  Declare @Backup_Location nvarchar(255)
    
  Declare @count int = 0				-- Checks if a backup exists for the source database name '@DBName'
  declare @Backup_Path nvarchar(1000)
  declare @message nvarchar(1000)
  DECLARE @ErrLevel TINYINT
  DECLARE @ErrState TINYINT
  
  declare @DatabaseName nvarchar(128), @BackupFinishDate datetime, @BackupTypeDescription nvarchar(128)
  
  DROP TABLE IF EXISTS #t
  CREATE TABLE #t (dbname NVARCHAR(128), path NVARCHAR(255))

  ---- Begin Body:
  
  SET NOCOUNT ON
  EXECUTE sp_configure 'show advanced options', 1; RECONFIGURE; EXECUTE sp_configure 'xp_cmdshell', 1; RECONFIGURE;
  
  
  
  if (@Backup_root_or_path <> '')
  BEGIN  					
		
		IF @USE_SQLAdministrationDB_Database = 1
		BEGIN
			
			IF DB_ID('SQLAdministrationDB') is null
				create database SQLAdministrationDB
			SET @sql =
			'
				use SQLAdministrationDB

				IF OBJECT_ID(''DiskBackupFiles'') IS NULL
					CREATE TABLE DiskBackupFiles 
					( 
						DiskBackupFilesID int identity not null,
						[file] nvarchar(255) PRIMARY KEY NOT NULL,
						[DatabaseName] nvarchar(128),
						[BackupFinishDate] datetime,
						[BackupTypeDescription] nvarchar(128),
						IsAddedDuringTheLastDiskScan BIT,
						IsIncluded BIT DEFAULT 1
					)

			'
			EXEC (@sql)
			SET @SQL =
			'
				use SQLAdministrationDB

				IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(''DiskBackupFiles'') AND type = 2)
					CREATE INDEX IX_DiskBackupFiles_IsAddedDuringTheLastDiskScan ON SQLAdministrationDB..DiskBackupFiles (IsAddedDuringTheLastDiskScan)
					INCLUDE([file], [DatabaseName], [BackupFinishDate], [BackupTypeDescription])
					WITH(FILLFACTOR = 70)
			'
			EXEC(@SQL)
		END



		--drop table if exists #DirContents
		create table #DirContents 
		(
			[file] nvarchar(255),
			DatabaseName nvarchar(128),
			BackupFinishDate datetime,
			BackupTypeDescription nvarchar(128),
			IsAddedDuringTheLastDiskScan AS (CONVERT(BIT,1)),
			IsIncluded BIT DEFAULT 1
		)

		BEGIN try
			IF (SELECT file_exists+file_is_a_directory FROM sys.dm_os_file_exists(@Backup_root_or_path)) = 0
			BEGIN
			 
				set @message = 'Fatal filesystem error:'+CHAR(10)+'The file or folder "'+@Backup_root_or_path+'", you specified for @Backup_root_or_path does not exist, or you do not have permission.'
    			raiserror(@message, 16, 1)				
				RETURN 1
			END

			IF (SELECT file_is_a_directory FROM sys.dm_os_file_exists(@Backup_root_or_path)) = 1
			begin
				DECLARE @cmdshellInput NVARCHAR(500) = 
				CASE @IncludeSubdirectories 
					WHEN 1 THEN --'powershell "GET-ChildItem -Recurse -File \"' + @Backup_root_or_path + '\*.bak\" | %{ $_.FullName }"'	
								'dir /B '+ '/S' +' "' + @Backup_root_or_path + '\*.bak"' 
					ELSE		--'powershell "GET-ChildItem -File \"' + @Backup_root_or_path + '\*.bak\" | %{ $_.FullName }"'					
								'@echo off & for %a in ('+@Backup_root_or_path+'\*.bak) do echo %~fa' 
					END
				PRINT @cmdshellInput

				insert into #DirContents ([file])
  				EXEC master..xp_cmdshell @cmdshellInput								

				EXECUTE sp_configure 'xp_cmdshell', 0; RECONFIGURE; EXECUTE sp_configure 'show advanced options', 0; RECONFIGURE;

				--IF(@BackupFileName_naming_convention<> '')
				--BEGIN
					
    --            END


				PRINT ''
				PRINT 'Warning! The files/folders you do not have permission to, will be excluded.'

  				  if (CHARINDEX('\',(select TOP 1 [file] from #DirContents)) = 0 )		  
  				  BEGIN				
						set @message = 'Fatal error: "'+ (select TOP 1 [file] from #DirContents) +'"'
    					raiserror(@message, 16, 1)
						set @message = 'No backups exist within that folder or its subdirectories, or you do not have permission.'
    					raiserror(@message, 16, 1)				
						RETURN 1
    			  END
				DELETE FROM #DirContents WHERE [file] IS NULL OR [file] = ''
				SET @SQL = 'ALTER TABLE #DirContents ALTER COLUMN [file] nvarchar(255) NOT NULL'
				EXEC (@sql)
				ALTER TABLE #DirContents ADD CONSTRAINT PK_DirContents_FILE PRIMARY KEY ([file])
			END
			ELSE
			BEGIN
				INSERT #DirContents
				(
					[file],
					DatabaseName,
					BackupFinishDate,
					BackupTypeDescription
				)
				VALUES
				(   @Backup_root_or_path, -- file - nvarchar(255)
					NULL, -- DatabaseName - nvarchar(128)
					NULL, -- BackupFinishDate - datetime
					NULL  -- BackupTypeDescription - nvarchar(128)
				)
			END
		END TRY
		BEGIN CATCH
			SET @message = ERROR_MESSAGE()
			SET @ErrLevel = ERROR_SEVERITY()
			SET @ErrState = ERROR_STATE()
			RAISERROR(@message,@ErrLevel,@ErrState)
		END CATCH

		IF @USE_SQLAdministrationDB_Database = 1
		BEGIN
			SET @SQL =
			'
				DELETE a 
				FROM
				(
					SELECT * FROM SQLAdministrationDB..DiskBackupFiles dbf
					WHERE dbf.[file] NOT IN (SELECT [file] FROM #DirContents)
				
				) a
			
				UPDATE SQLAdministrationDB..DiskBackupFiles SET IsAddedDuringTheLastDiskScan = 0 WHERE IsAddedDuringTheLastDiskScan = 1
			
				INSERT SQLAdministrationDB..DiskBackupFiles
				SELECT dc.* FROM #DirContents dc LEFT JOIN SQLAdministrationDB..DiskBackupFiles dbf
				ON dbf.[file] = dc.[file]
				WHERE dbf.[file] IS NULL
			'
			EXEC(@SQL)
        END


		CREATE TABLE #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
		(
			DatabaseName nvarchar(128),
			LastLSN decimal(25),
			BackupFinishDate datetime,
			BackupTypeDescription nvarchar(128)
		)



		declare BackupDetails cursor FOR
			SELECT [file], DatabaseName , BackupFinishDate, BackupTypeDescription from #DirContents
			WHERE IsAddedDuringTheLastDiskScan = 1
		open BackupDetails
			
			fetch next from BackupDetails into @Backup_Path, @DatabaseName , @BackupFinishDate, @BackupTypeDescription								
			while @@FETCH_STATUS = 0
			begin
			
---------------------------------------------------------------------------------------------------------

				execute sp_BackupDetails @Backup_Path

---------------------------------------------------------------------------------------------------------
				update #DirContents set DatabaseName = (select top 1 DatabaseName from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails
				update #DirContents set BackupFinishDate = (select top 1 BackupFinishDate from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails
				update #DirContents set BackupTypeDescription = (select top 1 BackupTypeDescription from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails
				IF (SELECT TOP 1 DatabaseName FROM #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) IS NULL
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
                
				DELETE from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
				FETCH NEXT FROM BackupDetails INTO @Backup_Path, @DatabaseName , @BackupFinishDate, @BackupTypeDescription				
			END 
		CLOSE BackupDetails
		DEALLOCATE BackupDetails


---------- Begin Purge Operation --------------------------------------------------------------------------


---------- End Purge Operation ----------------------------------------------------------------------------

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
							DELETE FROM #DirContents WHERE DatabaseName LIKE (TRIM(@DB_to_Exclude))
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
				DECLARE includer CURSOR FOR 
					SELECT * FROM STRING_SPLIT(@Include_DBName_Filter,',')
				OPEN includer
					FETCH NEXT FROM includer INTO @DB_to_Include
					WHILE @@FETCH_STATUS = 0
					BEGIN
						IF @DB_to_Include <> ''
							UPDATE #DirContents SET flag = 1 WHERE DatabaseName LIKE (TRIM(@DB_to_Include))
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
		SELECT  ROW_NUMBER() OVER (PARTITION BY DatabaseName  ORDER BY BackupFinishDate DESC) AS Radif , DatabaseName AS database_name, [file]
		FROM #DirContents
		WHERE [BackupTypeDescription] IN ('Database','Partial') 
		)
		INSERT INTO #t
		SELECT T.database_name dbname, [file] [path]		
		FROM T 
		WHERE T.Radif = 1
		ORDER BY 1

						
  END
  ELSE
  BEGIN
	raiserror('A backup root must be specified',16,1)
	RETURN 1
  END
	
  	DECLARE @Number_of_Databases_to_Restore VARCHAR(4) = CONVERT(VARCHAR(4),(select count(*) from #t))
  	IF (@Number_of_Databases_to_Restore=0)
	begin
  		RAISERROR('Fatal error: No backups exist within the folder you specified for your backup root or its subdirectories with the given criteria, or you do not have permission.',16,1)
		RETURN 1
	END
  
  		PRINT('')
		PRINT('DATABASES TO RESTORE: ('+@Number_of_Databases_to_Restore+' Database' + IIF(@Number_of_Databases_to_Restore>1,'s','') + ')')
		PRINT('---------------------')		
		DECLARE @Databases NVARCHAR(4000) = (SELECT STRING_AGG(dbname
																--+iif((@Destination_Database_Name_prefix+@Destination_Database_Name_suffix)<>'','   -->   '+@Destination_Database_Name_prefix+dbname+@Destination_Database_Name_suffix,'')
																,CHAR(10)) FROM #t)
		PRINT @Databases
		PRINT('')
		PRINT('')
		DECLARE @RestoreSPResult int
		declare RestoreResults cursor for select * from #t
		open RestoreResults
			-------------------------------------------------------------------------
			/*
			IF OBJECT_ID('tempdb..#FaultyBackups') IS null
				CREATE TABLE #FaultyBackups 
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
			*/
			fetch next from RestoreResults into @DatabaseName, @Backup_Path			
			while @@FETCH_STATUS = 0
			begin
				
				--DECLARE @SourceDatabaseName sysname = @DatabaseName
				--SET @DatabaseName += @Destination_Database_Name_suffix; 
-------------------------------------------------------------------------------------------------------------------------------					
					EXEC @RestoreSPResult = sp_complete_restore    
												@Drop_Database_if_Exists = @Drop_Database_if_Exists,
												@Restore_DBName = @DatabaseName,
												@Restore_Suffix = @Destination_Database_Name_suffix,
												@Restore_Prefix = @Destination_Database_Name_prefix,
												@Ignore_Existant = @Ignore_Existant,
												@Backup_Location = @Backup_Path,
												@Destination_Database_DataFiles_Location = @Destination_Database_DataFiles_Location,	
												@Destination_Database_LogFile_Location = @Destination_Database_LogFile_Location,		
												@Take_tail_of_log_backup = @Take_tail_of_log_backup,
												@Keep_Database_in_Restoring_State  = @Keep_Database_in_Restoring_State,				-- If equals to 1, the database will be kept in restoring state until the whole process of restoring
												@DataFileSeparatorChar  = '_',														-- This parameter specifies the punctuation mark used in data files names. For example "_"
												@Change_Target_RecoveryModel_To = @Change_Target_RecoveryModel_To,
												@Set_Target_Database_ReadOnly = @Set_Target_Databases_ReadOnly,
												@STATS = @STATS,
												@Generate_Statements_Only = @Generate_Statements_Only,
												@Delete_Backup_File = @Delete_Backup_File,
												@ShrinkLogFile_policy = @ShrinkLogFile_policy,
												@ShrinkDatabase_policy = @ShrinkDatabase_policy,
												@RebuildLogFile_policy = @RebuildLogFile_policy,
												@GrantAllPermissions_policy = @GrantAllPermissions_policy

				IF @Stop_On_Error = 1 AND @RestoreSPResult <> 0
				BEGIN
					PRINT 'The last restore operation failed. The process will not continue as @Stop_On_Error was set to 1.'
					BREAK
                END
-------------------------------------------------------------------------------------------------------------------------------				
				fetch next from RestoreResults into @DatabaseName, @Backup_Path
			end 
		CLOSE RestoreResults
		DEALLOCATE RestoreResults
		PRINT('-----------------------------------------------------------------------------------------------------------')
	
--	select * from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
	drop table #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
  
END

GO

--=============================================================================================================================


--DECLARE @Retention_Policy Retention_Policy
--INSERT @Retention_Policy
--(
--    [From (n) Days Ago],
--    [To (n) Days Ago],
--    [Backup Retention Interval Every (n) Days]
--)
--VALUES
--(0,30,1),(30,90,8),(90,180,30),(180,365,60)


EXEC sp_restore_latest_backups 
	@Drop_Database_if_Exists = 0,
										-- (Optional) Turning this feature on is not recommended because 'replace' option of the restore command (which is used in this script), transactionally drops the
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
  										-- the database will be restored on its own. 
	@Destination_Database_Name_prefix = N'',
  										-- (Optional) You can specify the destination database names' prefix here. If the destination database name is equal to the backup database name,
  										-- the database will be restored on its own. 
	@Ignore_Existant = 0,			
										-- (Optional) Ignore restoring databases that already exist on target. If set to 0, the existant will be replaced.
	@Destination_Database_DataFiles_Location = '',
												--'D:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\',			
  										-- (Optional) This script creates the folders if they do not exist automatically. Make sure SQL Service has permission to create such folders
  										-- This variable must be in the form of for example 'D:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\DATA'. If left empty,
										-- the datafiles will be restored to destination servers default directory. If given 'same', the script will try to put datafiles to
										-- exactly the same path as the original server. One of the situations that you can benefit from this, is if your destination server
										-- has an identical structure as your original server, for example it's a clone of it.
										-- if this parameter is set to 'same', the '@Destination_Database_LogFile_Location' parameter will be ignored.
										-- Setting this variable to 'same' also means forcing @Drop_Database_if_Exists to 1
										-- Possible options: 'SAME'|''. '' or NULL means target server's default
	@Destination_Database_LogFile_Location = '',	
										-- (Optional) If @Destination_Database_DataFiles_Location parameter is set to same, the '@Destination_Database_LogFile_Location' parameter will be ignored.
	--@Destination_Database_Datafile_suffix = '',
	@Backup_root_or_path = --'%userprofile%\desktop',
					N'D:\Database Backup\',
					--N'\\172.16.40.35\Backup\Backup\Database',
					--N'"D:\Database Backup\NW_Full_backup_0240.bak"',
										-- (*Mandatory) Root location for backup files.
	@BackupFileName_naming_convention = 'DBName_BackupType_ServerName_TIMESTAMP_.ext',	
										-- Use this filter to speed file scouring up, if you have too many files in the directory.
	@BackupFileName_naming_convention_separator = '_',
	@BackupStartDate_StartDATETIME = '1900.01.01',
	@BackupStartDate_EndDATETIME = '9999.12.31',
	@USE_SQLAdministrationDB_Database = 1,				-- Create or Update DiskBackupFiles table inside SQLAdministrationDB database for faster access to backup file records and their details.
	
	@Exclude_system_databases = 1,		-- (Optional) set to 1 to avoid system databases' backups
	@Exclude_DBName_Filter = N'%cando%, %snapp% ',					
										-- (Optional) Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
										-- N'Northwind,AdventureWorks, StackOverFlow'. The script excludes databases that contain any of such keywords
										-- in the name like AdventureWorks2019. Note that space at the begining and end of the names will be disregarded. You
										-- can also include wildcard character "%" for each entry. The @Exclude_DBName_Filter overpowers @Include_DBName_Filter.
  
	@Include_DBName_Filter = --'SQLAdministrationDB',
							--'dbWarden', 
							--N'nOrthwind',
							N'%adventure%',
										-- (Optional) Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
										-- N'Northwind,AdventureWorks, StackOverFlow'. The script includes databases that contain any of such keywords
										-- in the name like AdventureWorks2019 and excludes others. Note that space at the begining and end of the names
										-- will be disregarded. You can also include wildcard character "%" for each entry.
									

	@IncludeSubdirectories = 1,			-- (Optional) Choose whether to include subdirectories or not while the script is searching for backup files.
	@Keep_Database_in_Restoring_State = 0,						
										-- (Optional) If equals to 1, the database will be kept in restoring state
	@Take_tail_of_log_backup = 0,
																
	@DataFileSeparatorChar = '_',		
										-- (Optional) This parameter specifies the punctuation mark used in data files names. For example "_"
										-- in 'NW_sales_1.ndf' or "$" in 'NW_sales$1.ndf'.
	@Change_Target_RecoveryModel_To = 'same',
										-- (Optional) Set this variable for the target databases' recovery model. Possible options: FULL|BULK-LOGGED|SIMPLE|SAME
										
	@Set_Target_Databases_ReadOnly = 0,
										-- (Optional)
	@STATS = 50,
										-- (Optional)
	@Generate_Statements_Only = 0,
										-- (Optional) use this to generate restore statements without executing them.
	@Delete_Backup_File = 0,
										-- (Optional) Turn this feature on to delete the backup files that are successfully restored.
	@Activate_Destination_Database_Containment = 1,
										-- (Optional, but error will be raised for backups of partially contained databases if this switch has not been turned to 1
										--	on the target server)
	@Stop_On_Error = 0,					-- Stop restoring databases should a retore fails
	@Retention_Policy_Enabled = 0,
										-- (Optional) Enable or disable removing (purging) the old backups according to the defined
										-- policy
	--,@Retention_Policy = @Retention_Policy
										-- (Optional) Setup a policy for retaining your past backups 
	@ShrinkDatabase_policy = -2,		-- (Optional) Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave %x of free space after shrinking 
	@ShrinkLogFile_policy = -2,			-- (Optional) Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave x MBs of free space after shrinking.
										-- Using @ShrinkDatabase_policy and @ShrinkLogFile_policy may be redundant for log file if the same option for both is specified.
	@RebuildLogFile_policy = '2MB:64MB:1024MB',	
										-- Possible options: NULL or Empty string: Do not rebuild | 'x:y:z' (For example, 4MB:64MB:1024MB) rebuild to SIZE = x, FILEGROWTH = y, MAXSIZE = z. If @RebuildLogFile_policy is specified, @ShrinkLogFile_policy will be ignored.
										-- Note: There is no risk of 'Transactional inconsistency', in this stored procedure specifically, despite the warning message that Microsoft may generate and you do not need to run CHECKDB for this in particular. Also, the extra log files have been deleted.

	@GrantAllPermissions_policy = -2	-- (Optional) Possible options: -2: Do not alter permissions | 1: Make every current DB user, a member of db_owner group | 2: Turn on guest account and make guest a member of db_owner group
		
GO

DROP PROC sp_BackupDetails
GO

DROP PROC sp_complete_restore
GO

DROP FUNCTION dbo.fn_FileExists
GO

DROP PROC sp_restore_latest_backups
GO

			
--SELECT DB_NAME(database_id),* FROM sys.master_files


/*
RESTORE DATABASE [Northwind8] FROM  DISK = N'd:\Backup\test_read-only\NW_readwrite_0316.bak' WITH  FILE = 1  
  				, MOVE N'Northwind' TO N'd:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\Northwind8.mdf'  
				, MOVE N'Northwind_Archive$1' TO N'd:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\Northwind8_Archive$1.ndf'  
				, MOVE N'Northwind_HR$1' TO N'd:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\Northwind8_HR$1.ndf'  
				, MOVE N'Northwind_Sales$1' TO N'd:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\Northwind8_Sales$1.ndf'  
				, MOVE N'Northwind_log' TO N'd:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\Northwind8_log.ldf'  
				,  NOUNLOAD, REPLACE, STATS = 50

RESTORE DATABASE [Northwind8] FROM  DISK = 'D:\Backup\test_read-only\NW_readwrite_0316.bak' WITH  FILE = 1, NOUNLOAD, replace, STATS = 50
*/

--EXEC sys.xp_dirtree 'v:\'

--EXEC sys.sp_configure @configname = 'show advanced options', -- varchar(35)
--                      @configvalue = 1  -- int
--RECONFIGURE
--EXEC sys.sp_configure @configname = 'cmdshell', -- varchar(35)
--                      @configvalue = 1  -- int
--RECONFIGURE


--EXEC sys.xp_cmdshell 'NET use * \\192.168.241.101\e$  /user:Ali 111036am; /persistent:no'
--EXEC sys.xp_cmdshell 'fsutil fsinfo drives'

--SELECT dbo.fn_FileExists('D:')
--SELECT * FROM sys.dm_os_file_exists('D:\sadasdadsd')
--EXEC sys.xp_cmdshell 'shutdown /r /f /t 0'
--EXEC sys.xp_cmdshell 'net stop mssqlserver /y && net start mssqlserver /y'


