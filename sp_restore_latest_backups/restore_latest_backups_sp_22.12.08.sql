USE master
GO

-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2021.03.12>
-- Latest Update Date:	<23.02.02>
-- Description:			<Restore Backups>
-- License:				<Please refer to the license file> 
-- =============================================

/*


This script	restores latest backups from the backups' repository filtered by the given criteria. As the server is most likely
	not the original producer of these backups,
	there will be no records of these backups in msdb. The records can be imported from the original server anyways but there would be
	some complications. This script probes recursively inside the provided directory, extracts all the full or read-write backup files,
	 and restores the latest backup of every chosen database. If the
	database already exists, a tail of log backup can be taken optionally first. If the name of the database cannot be obtained from the
	backup file, the script names the target database as 'UnreadableBackupFile+<a random string>'. Such backups will most likely fail to restore.

SQL Server version requirement:
This script is designed to comply with SQL Server 2019 and later. The versions 2016 and 2017 are also most likely supported.
Earlier versions are compatible if some of the features are removed. I have tested this on 2019

Attention: 		
	1. Please make sure SQL service has required permissions to the paths you specify. Otherwise the script will fail. If the output paths do not
	exist, the script automatically creates them.
	2. If the database is to be restored on its own, this script automatically kills all sessions connected to the database except
	the current session, before restoring the database. The database will be returned to MULTI_USER state at the end.
	3. Appending backup files to each other is not recommended and this script is not designed to handle such case.
	4. This scripts keeps the list of backup files in the SQLAdministrationDB database, for full backup files,	for both history and caching
	purposes, but for log backup files only for caching purposes. 
	5. Note in this script that if your resource directory is on the local server, you should not specify one directory path as local and an another
	one as UNC, otherwise errors might occur for "live restore operation"

TODO: 
	  
	  -. Elapsed time										done
	  -. Restore a live backup								done
	  -. Work on included 1 instead of 0					done
	  -. Delete Temp Tail of Log Backups					done
	  -. Become platform independent						Suspended (Is backward compatibility more important or platform independency for SQL Server?)
	  -. Merge include and exclude queries					rejected
	  -. Restore Order
	  -. smart progress percentage
	  -. restore datafiles to multiple places
	  -. Add differential Support
	  -. attach detached datafiles
	  -. make SQLAdministrationDB optional


*/



--============================================================================================
-- To me, "second" precision amount is perfectly enough, but if you want to include millisecond 
-- you may manage them here too. But please beware of DATEDIFF overflow error

CREATE OR ALTER FUNCTION ufn_ElapsedTime(@StartTime DATETIME)
RETURNS VARCHAR(33)
WITH 
	SCHEMABINDING,
	RETURNS NULL ON NULL INPUT
AS
BEGIN
	DECLARE @ExecutionTime_INT BIGINT,
			@ExecutionTime_VARCHAR VARCHAR(20),
			@Millisecond VARCHAR(3),
			@Second VARCHAR(2),
			@Minute VARCHAR(2),
			@Hour VARCHAR(2),
			@Day VARCHAR(4)

	SET @ExecutionTime_INT = DATEDIFF(SECOND,@StartTime,SYSDATETIME())
	--SET @Millisecond = RIGHT(@ExecutionTime_INT,3)
	--SET @Millisecond = REPLICATE('0',3-LEN(@Millisecond)) + @Millisecond
	--SET @ExecutionTime_INT /= 10000 
	SET @Second = @ExecutionTime_INT % 60
	SET @Second = REPLICATE('0',2-LEN(@Second)) + @Second
	SET @ExecutionTime_INT/=60
	SET @Minute = @ExecutionTime_INT % 60
	SET @Minute = REPLICATE('0',2-LEN(@Minute)) + @Minute
	SET @ExecutionTime_INT/=60
	SET @Hour = @ExecutionTime_INT % 24
	SET @Hour = REPLICATE('0',2-LEN(@Hour)) + @Hour
	SET @ExecutionTime_INT/=24
	IF LEN(@ExecutionTime_INT)=1 SET @Day = '0'+CONVERT(VARCHAR(1),@ExecutionTime_INT)	
	-- 20 characters + 
	RETURN @Day+':'+@Hour+':'+@Minute+':'+@Second+ISNULL('.'+@Millisecond,'')+' (dddd:hh:mm:ss)'
END
GO

--============================================================================================

CREATE OR ALTER PROC usp_PrintLong
	@String NVARCHAR(MAX),
	@Max_Chunk_Size SMALLINT = 4000
AS
BEGIN
	SET NOCOUNT ON
	SET @Max_Chunk_Size = ISNULL(@Max_Chunk_Size,4000)
	IF @Max_Chunk_Size > 4000 OR @Max_Chunk_Size<50 BEGIN RAISERROR('Wrong @Max_Chunk_Size cannot be bigger than 4000. A value less than 50 for this parameter is also not supported.',16,1) RETURN 1 END
	DECLARE @NewLineLocation INT,
			@TempStr NVARCHAR(4000),
			@Length INT,
			@carriage BIT,
			@SeparatorNewLineFlag BIT,
			@Temp_Max_Chunk_Size INT

	CREATE TABLE #MinSeparator
	(
		id INT IDENTITY PRIMARY KEY NOT NULL,
		Separator VARCHAR(2),
		SeparatorReversePosition INT
	)

	WHILE @String <> ''
	BEGIN
		IF LEN(@String)<=@Max_Chunk_Size
		BEGIN 
			PRINT @String
			BREAK
		END 
		ELSE
        BEGIN
			SET @Temp_Max_Chunk_Size = @Max_Chunk_Size
			StartWithChunk:
			SET @TempStr = SUBSTRING(@String,1,@Temp_Max_Chunk_Size)
			SELECT @NewLineLocation = CHARINDEX(CHAR(10),REVERSE(@TempStr))
			DECLARE @MinSeparator INT

			TRUNCATE TABLE #MinSeparator
			INSERT #MinSeparator
			(
			    Separator,
			    SeparatorReversePosition
			)
			VALUES ('.', CHARINDEX('.',REVERSE(@TempStr))), (')', CHARINDEX(')',REVERSE(@TempStr))), ('(', CHARINDEX('(',REVERSE(@TempStr))), (',', CHARINDEX(',',REVERSE(@TempStr))), ('-', CHARINDEX('-',REVERSE(@TempStr))), ('*', CHARINDEX('*',REVERSE(@TempStr))), ('/', CHARINDEX('/',REVERSE(@TempStr))), ('+', CHARINDEX('+',REVERSE(@TempStr))), (CHAR(32), CHARINDEX(CHAR(32),REVERSE(@TempStr))), (CHAR(9), CHARINDEX(CHAR(9),REVERSE(@TempStr)))
			SELECT @MinSeparator = MIN(SeparatorReversePosition) FROM #MinSeparator WHERE SeparatorReversePosition<>0

			IF @NewLineLocation=0 AND @MinSeparator IS NOT NULL
			BEGIN
				SET @SeparatorNewLineFlag = 0				
				SET @NewLineLocation = @MinSeparator
			END
			ELSE
				IF @NewLineLocation<>0	SET @SeparatorNewLineFlag = 1
			
			IF @NewLineLocation = 0 OR @NewLineLocation=@Max_Chunk_Size BEGIN SET @Temp_Max_Chunk_Size+=50 GOTO StartWithChunk END

			IF CHARINDEX(CHAR(13),REVERSE(@TempStr)) - @NewLineLocation = 1
				SET @carriage = 1
			ELSE
				SET @carriage = 0

			SET @TempStr = LEFT(@TempStr,(@Temp_Max_Chunk_Size-@NewLineLocation)-CONVERT(INT,@carriage))

			PRINT @TempStr
		
			SET @Length = LEN(@String)-LEN(@TempStr)-CONVERT(INT,@carriage)-1+CONVERT(INT,~@SeparatorNewLineFlag)
			SET @String = RIGHT(@String,@Length)
			
		END 
	END
END
GO

--============================================================================================

CREATE OR ALTER FUNCTION ufn_CheckNameValidation
(
	@String NVARCHAR(1000),
	@BenchmarkString NVARCHAR(1000),
	@delim nvarchar(5)
	,@DateString NVARCHAR(50)
)
RETURNS BIT
WITH 
inline=ON,
SCHEMABINDING,
RETURNS NULL ON NULL INPUT
AS
BEGIN
	DECLARE @OccuranceCountEquality BIT = IIF((LEN(@String)-LEN(REPLACE(@String,@delim,'')))=(LEN(@BenchmarkString)-LEN(REPLACE(@BenchmarkString,@delim,''))),1,0)
			,@DatePartialValidity BIT = IIF(PATINDEX('%[A-Za-z]%', @DateString)<>0,0,1)
	RETURN IIF(	@OccuranceCountEquality = 1 
				AND @DatePartialValidity = 1
				, 1, 0
			  )
END
GO

--============================================================================================
-- Note: the "ordinal column" is not available for SQL Server 2019 and earlier versions, but for SQL Server
-- 2022 and later, faster and more efficient definition of this function using new functionality of "STRING_SPLIT"
-- can be deployed.

CREATE OR ALTER FUNCTION ufn_StringTokenizer(@String NVARCHAR(max), @delim nvarchar(5), @Ind smallint)
RETURNS NVARCHAR(2000)
WITH 
inline=ON,
SCHEMABINDING,
RETURNS NULL ON NULL INPUT
AS
BEGIN
	RETURN 	(SELECT value
			from
			(
				SELECT row,dto.value
				FROM
				(
					SELECT ROW_NUMBER() OVER (PARTITION BY row ORDER BY row) row2,
					value,row 
					FROM 
					(
						SELECT TRIM(value) value,row 
						FROM 
						STRING_SPLIT(@String,@delim), ( SELECT 1 ROW
														UNION ALL 
														SELECT 2
														UNION ALL
														SELECT 3
														UNION ALL
														SELECT 4
														UNION ALL
														SELECT 5
														UNION ALL
														SELECT 6
													  ) dtrow
					) dt
				) dto
				WHERE dto.row = row2
			) dt
			WHERE ROW = @Ind)
END
GO

--====================================================================================
-- Checks if the file with the given path exists
CREATE OR alter FUNCTION dbo.ufn_FileExistsForAnotherDatabase(@Restore_DBName sysname, @path varchar(512))
RETURNS BIT
WITH RETURNS NULL ON NULL INPUT
AS
BEGIN
	IF	(SELECT file_exists+file_is_a_directory FROM sys.dm_os_file_exists(@path)) = 1 AND 
		(SELECT DB_NAME(database_id) FROM sys.master_files WHERE physical_name = @path) <> @Restore_DBName
		RETURN 1
	ELSE
		RETURN 0		
	RETURN 0
END;
GO

--============== First SP ================================================================================

-- This SP is called by the main SP
create or alter procedure usp_BackupDetails 
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

		IF cast(cast(SERVERPROPERTY('ProductVersion') as char(4)) as float) > 11 -- Equal to or greater than SQL 2014 
  		BEGIN
  			ALTER TABLE #tmp ADD Containment tinyint NULL
  		END
  		IF cast(cast(SERVERPROPERTY('ProductVersion') as char(2)) as float) > 12 -- Equal to or greater than 2016
  		BEGIN
  			ALTER TABLE #tmp ADD KeyAlgorithm nvarchar(32),
								EncryptorThumbprint varbinary(20),
								EncryptorType nvarchar(32)
  		END
		
		IF cast(cast(SERVERPROPERTY('ProductVersion') as char(2)) as float) > 15 -- Equal to or greater than 2022
  		BEGIN
			ALTER TABLE #tmp ADD [LastValidRestoreTime] datetime,
								 [TimeZone] smallint,
								 [CompressionAlgorithm] nvarchar(32)
		END

		-- N'E:\Backup\test_read-only\NW_readwrite_0316.bak' -- N'E:\Backup\test_read-only\NW_dif.dif' -- N'E:\Backup\test_read-only\NW_Full_backup_0240.bak' -- 
  		Declare @sql nvarchar(max) = 'RESTORE HEADERONLY FROM DISK = @Backup_Path'
  		INSERT INTO #tmp
  		EXEC master.sys.sp_executesql @sql , N'@Backup_Path nvarchar(150)', @Backup_Path

		INSERT #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
		select DatabaseName, LastLSN, BackupStartDate, BackupFinishDate, BackupTypeDescription, ServerName from #tmp

END
GO

--======= Second SP =====================================================================================================

--- This SP is called by the main SP:
create or alter proc usp_complete_restore
	@Drop_SQLSBuffers_Before_Restore BIT = 0,
	@Drop_Database_if_Exists BIT = 0,
	@DiskBackupFilesID INT,
	@USE_SQLAdministrationDB_Database BIT = 0,					-- Create or Update SQLAdministrationDB and DiskBackupFiles and RestoreHistory tables inside SQLAdministrationDB database for faster access to backup file records
																-- and their details. This is useful when your backup repository is very large, containing too many files. Using this feature does not speed up file scouring operations at the first run,
																-- but next times the runtime will be decreased remarkably because it evades RESTORE HEADERONLY for previously processed files.
	@Restore_DBName sysname,
	@Restore_Suffix sysname = '',
	@Restore_Prefix sysname = '',
	@Ignore_Existant BIT = 0,									
	@Backup_Location nvarchar(1000),
	@Destination_Database_DataFiles_Location nvarchar(300) = '',			
	@Destination_Database_LogFile_Location nvarchar(300) = '',
	@Destination_Database_Datafile_suffix NVARCHAR(128) = '',
	@Take_tail_of_log_backup_of_existing_database bit = 1,
	@Keep_Database_in_Restoring_State bit = 0,					-- If equals to 1, the database will be kept in restoring state until the whole process of restoring
	@DataFileSeparatorChar nvarchar(2) = '_',					-- This parameter specifies the punctuation mark used in data files names. For example "_"
	@Restore_Log_Backups BIT = 0,
	@Force_Recovery_If_No_Log_Backups_Found BIT = 0,
	@StopAt DATETIME = '9999-12-31T23:59:59',
	@STATS TINYINT = 50,
	@Generate_Statements_Only bit = 0,
	-- post-restore operations
	@Delete_Backup_File BIT = 0,
	@Change_Target_RecoveryModel_To NVARCHAR(20) = 'InheritFromSource',		-- Possible options: FULL|BULK-LOGGED|SIMPLE|InheritFromSource
	@Set_Target_Database_ReadOnly BIT = 0,

	@ShrinkDatabase_policy SMALLINT = -2,						-- Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave %x of free space after shrinking 
	@ShrinkLogFile_policy SMALLINT = -2,						-- Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave x MBs of free space after shrinking 
	@RebuildLogFile_policy VARCHAR(64) = '',					-- Possible options: NULL or Empty string: Do not rebuild | 'x:y:z' (For example, 4MB:64MB:1024MB) rebuild to SIZE = x, FILEGROWTH = y, MAXSIZE = z. If @RebuildLogFile_policy is specified, @ShrinkLogFile_policy will be ignored.
	@GrantAllPermissions_policy SMALLINT = -2,					-- Possible options: -2: Do not alter permissions | 1: Make every current DB user, a member of db_owner group | 2: Turn on guest account and make guest a member of db_owner group
	@OperationStartTime DATETIME = '',
	@Script_to_Execute_After_Restore NVARCHAR(MAX)
	
AS
BEGIN
	set nocount ON
	
	DECLARE @OriginalDBName sysname = @Restore_DBName
	DECLARE @ErrMsg NVARCHAR(256)
	DECLARE @DatabaseReplaceFlag BIT = 0
	IF  @GrantAllPermissions_policy NOT IN (-2,1,2,3) RAISERROR('Invalid option for @GrantAllPermissions_policy was specified.',16,1)
	SET @GrantAllPermissions_policy = ISNULL(@GrantAllPermissions_policy,-2)
	SET @ShrinkDatabase_policy = ISNULL(@ShrinkDatabase_policy,-2)
	SET @ShrinkLogFile_policy = ISNULL(@ShrinkLogFile_policy,-2)
	SET @STATS = ISNULL(@STATS,0)
	SET @Restore_Suffix = ISNULL(@Restore_Suffix,'')
	SET @Restore_Prefix = ISNULL(@Restore_Prefix,'')
	SET @Restore_DBName = @Restore_Prefix + @Restore_DBName + @Restore_Suffix
	IF (@Change_Target_RecoveryModel_To IS NULL) OR (@Change_Target_RecoveryModel_To = '') SET @Change_Target_RecoveryModel_To = 'InheritFromSource'
	SET @Destination_Database_Datafiles_Location = ISNULL(@Destination_Database_Datafiles_Location,'')
	SET @Destination_Database_LogFile_Location = ISNULL(@Destination_Database_Logfile_Location,'')
	SET @RebuildLogFile_policy = ISNULL(@RebuildLogFile_policy,'')
	SET @StopAt = ISNULL(@StopAt,'9999-12-31 23:59:59')
	SET @Script_to_Execute_After_Restore = ISNULL(@Script_to_Execute_After_Restore,'')


	DECLARE @Back_DateandTime nvarchar(20) = (select replace(convert(date, GetDate()),'-','.') + '_' + substring(replace(convert(nvarchar(10),convert(time, GetDate())), ':', ''),1,4) )
	Declare @DB_Restore_Script nvarchar(4000) = ''
	DECLARE @Log_Restore_Script nvarchar(max) = ''
	declare @DropDatabaseStatement nvarchar(4000) = ''
	DECLARE @Degree_of_Parallelism int
	DECLARE @identity INT
	declare @message nvarchar(300)
	DECLARE @ErrNo INT 

	DECLARE @BackupFinishDate DATETIME,
			@LastLogBackupID INT,
			@LastLogBackupLocation nvarchar(2000),
			@LastLogBackupFinishDate DATETIME,
			@LastLogBackupStartDate DATETIME,
			@LastLogBackupLastLSN DECIMAL(25,0),
			@BackupLastLSN DECIMAL(25,0),
			@No_of_Log_Backups INT = 0

	IF ISNULL(@OriginalDBName,'') = ''
	BEGIN
	RAISERROR('@OriginalDBName must be specified.',16,1)
	RETURN 1
	END
	
	IF @Change_Target_RecoveryModel_To NOT IN ('FULL','BULK-LOGGED','SIMPLE','InheritFromSource','SameAsDestination')
	BEGIN
	RAISERROR('Target recovery model specified is not a recognized SQL Server recovery model.',16,1)
	RETURN 1
	END

	IF @Destination_Database_Datafiles_Location = ''
	BEGIN
	  	set @Destination_Database_Datafiles_Location = convert(nvarchar(1000),(select SERVERPROPERTY('InstanceDefaultDataPath')))
	END
	IF @Destination_Database_LogFile_Location = ''
	BEGIN
	  	set @Destination_Database_Logfile_Location = convert(nvarchar(1000),(select SERVERPROPERTY('InstanceDefaultLogPath')))
	END

	IF @Restore_Log_Backups = 1 
	BEGIN
		--SELECT @BackupFinishDate = BackupFinishDate FROM SQLAdministrationDB..DiskBackupFiles WHERE DiskBackupFilesID = @DiskBackupFilesID
		--IF @BackupFinishDate IS NULL
		--BEGIN
		EXEC dbo.usp_BackupDetails @Backup_Path = @Backup_Location -- nvarchar(1000)
		SELECT TOP 1 @BackupFinishDate = BackupFinishDate FROM #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
		SELECT TOP 1 @BackupLastLSN = LastLSN FROM #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
		TRUNCATE TABLE #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
		--END		
			
		IF @StopAt < @BackupFinishDate
		BEGIN
			SELECT TOP 1 
				@DiskBackupFilesID = dt.DiskBackupFilesID,
				@Backup_Location = dt.[file]		
			FROM
            (
				SELECT TOP 2 DiskBackupFilesID, [file], BackupStartDate
				FROM
				SQLAdministrationDB..DiskBackupFiles
				WHERE DatabaseName = @OriginalDBName AND IsIncluded = 1
				ORDER BY BackupStartDate desc
			) dt
			ORDER BY dt.BackupStartDate

			EXEC dbo.usp_BackupDetails @Backup_Path = @Backup_Location -- nvarchar(1000)
			SELECT TOP 1 @BackupFinishDate = BackupFinishDate FROM #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
			SELECT TOP 1 @BackupLastLSN = LastLSN FROM #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
			TRUNCATE TABLE #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9

        END
    END

  ----------------------------------------------- Restoring Database:
		BEGIN try
    		  		
  			print('--=========================================================================================================')

			-------------------------------------------------------------------

  			IF DB_ID(@Restore_DBName) is not null  -- restore database on its own
  			BEGIN
				SET @DatabaseReplaceFlag = 1
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
  				IF (SELECT state FROM sys.databases WHERE name = @Restore_DBName) in (0,4,5)	-- states: 0 online, 4 suspect, 5 emergency
				begin
					SET @DB_Restore_Script += 'use '+ QUOTENAME(@Restore_DBName) + ' ALTER database ' + QUOTENAME(@Restore_DBName) + ' set single_user with rollback immediate'+CHAR(10)
						
					IF (@Generate_Statements_Only = 0 AND @Ignore_Existant = 0)					
						EXECUTE (@DB_Restore_Script)
					SET @DB_Restore_Script = ''
					IF @Take_tail_of_log_backup_of_existing_database = 1
  						if @isPseudoSimple_or_Simple != 1	 -- check if the database has not SIMPLE or PseudoSIMPLE recovery model
						BEGIN
							DECLARE @Tail_of_Log_Backup_Script NVARCHAR(max)
							Declare @TailofLOG_Backup_Name nvarchar(100) = 'TailofLOG_' + @Restore_DBName+'_Backup_'+@Back_DateandTime+'.trn'
  							set @Tail_of_Log_Backup_Script = 'BACKUP LOG ' + QUOTENAME(@Restore_DBName) + ' TO DISK = ''' + @TailofLOG_Backup_Name + ''' WITH FORMAT,  NAME = ''' + @TailofLOG_Backup_Name + ''', NOREWIND, NOUNLOAD,  NORECOVERY 
  							'
							IF (@Generate_Statements_Only = 0)
								EXEC (@Tail_of_Log_Backup_Script)					
					
						END
					ELSE
						RAISERROR('@Take_tail_of_log_backup_of_existing_database is set to 1, but your existing database is either simple or in pseudo-simple mode, and a transcation log backup cannot be taken.',16,1)
				END
				---- Dropping database if exists, before restoring, on user request ------
				IF (@Drop_Database_if_Exists = 1)
				BEGIN										
					SET @DropDatabaseStatement += 'DROP database ' + @Restore_DBName + CHAR(10)					
					GOTO restoreanew

				END
				--------------------------------------------------------------------------
  												
  
  			END 
			ELSE
			BEGIN            
				PRINT ('--'+@Restore_DBName+' (New Database)')				
			END	


			PRINT ''
  			BEGIN				-- Restore database to a new name or restoring a non-existent database 
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
				BEGIN try
  					INSERT INTO #Backup_Files_List
  					EXEC master.sys.sp_executesql @sql , N'@Backup_Path nvarchar(150)', @Backup_Location
				END TRY
				BEGIN CATCH
					RAISERROR('Your file is probably corrupt, encrypted without the corresponding certificate on your server, not recognizable by this version of SQL Server, or not a database backup file. Restore will not continue.',16,1)
				END CATCH
				---------------------------------------------------------------------------------------------------								

  				set @DB_Restore_Script += @DropDatabaseStatement + N'RESTORE DATABASE ' + QUOTENAME(@Restore_DBName) + ' FROM  DISK = N''' + @Backup_Location + ''' WITH  FILE = 1'
				

				BEGIN                
  					
					IF (@Generate_Statements_Only = 0 AND CHARINDEX(':',@Destination_Database_DataFiles_Location) <> 0)
					begin
  						EXEC xp_create_subdir @Destination_Database_DataFiles_Location
  						EXEC xp_create_subdir @Destination_Database_LogFile_Location
					end
					

------------------ Adding move statements:---------------------------	
-- [File Exists] here cannot be turned into a computed column, because then you have to create the fuction inside tempdb, and when you want
-- to reexecute this script instantly the temp table most likely is not disposed of yet, it takes some time for this table to be disposed of
-- (A SQL Server bug in my opinion), that's why the function
-- cannot be recreated due to the dependancy of temp table on the function, therefore an error will be raised which is not the problem of this
-- script and is SQL Server's itself. That's why computed column cannot be used. Suppressing the error also appeared to be not a correct decision

					CREATE TABLE #TempTargetDBFiles 
					(						
						FileID BIGINT NOT NULL,
						head NVARCHAR(500) NOT NULL,
						tail NVARCHAR(1000) NOT NULL,
						type CHAR(1),
						[File Exists] bit
					)
					
					INSERT #TempTargetDBFiles (FileID ,head , tail, type, [File Exists])					
						SELECT dt.FileID, head, dt.tail, dt.Type, dbo.ufn_FileExistsForAnotherDatabase(@Restore_DBName,tail) from
						(
  						
  							select FileID, ',MOVE N''' + LogicalName + ''' TO N''' head, 
							CASE when Type = 'L' then 
							IIF
							(
								@Destination_Database_LogFile_Location <> 'InheritFromSource',@Destination_Database_LogFile_Location, LEFT(PhysicalName, (LEN(PhysicalName) - CHARINDEX('\',REVERSE(PhysicalName))))
							)
							ELSE 
							IIF
							(
								@Destination_Database_DataFiles_Location <> 'InheritFromSource',@Destination_Database_DataFiles_Location, LEFT(PhysicalName, (LEN(PhysicalName) - CHARINDEX('\',REVERSE(PhysicalName))))
							)
							END
							+ '\' + 
							iif(CHARINDEX(@OriginalDBName,RIGHT(PhysicalName,CHARINDEX('\', REVERSE(PhysicalName))))<>0
									,REPLACE(RIGHT(PhysicalName,(CHARINDEX('\', REVERSE(PhysicalName))-1)),@OriginalDBName,@Restore_DBName)
									,@Restore_DBName+'_'+RIGHT(PhysicalName,(CHARINDEX('\', REVERSE(PhysicalName))-1)))
							-- Put SeparatorChar* or .extension after @Restore_DBName:

							AS tail,
							Type
  							from #Backup_Files_List

						) dt



					WHILE EXISTS (SELECT 1 FROM #TempTargetDBFiles WHERE [File Exists] = 1) 
					BEGIN

						UPDATE a 
							SET tail = LEFT(tail,LEN(tail)-4)+'_2'+RIGHT(tail,4),
								a.[File Exists] = dbo.ufn_FileExistsForAnotherDatabase(@Restore_DBName, LEFT(tail,LEN(tail)-4)+'_2'+RIGHT(tail,4))
						FROM 
						(
							SELECT TOP 1 tail, [File Exists]
							FROM #TempTargetDBFiles
							WHERE [File Exists] = 1							
						) a
						
					end	

					
  					select @DB_Restore_Script += CHAR(10)+REPLICATE(CHAR(9),5)+head+tail+''''
  					from #TempTargetDBFiles

--------------------------------------------------------------------  
				end

----------------Creating necessary directories for 'InheritFromSource' option ----------------------------------------------------
					IF (@Generate_Statements_Only = 0 )
					BEGIN
						declare @DirPath nvarchar(1000)
						IF @Destination_Database_DataFiles_Location = 'InheritFromSource'
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
						IF @Destination_Database_LogFile_Location = 'InheritFromSource'
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
--------------------End creating necessary directories for 'InheritFromSource' option----------------------------------------------------------------------------

  				
				SELECT @DB_Restore_Script += ', NOUNLOAD, REPLACE' + IIF(@STATS = 0,'',(', STATS = ' + CONVERT(varchar(3),@STATS))) 

                if @Keep_Database_in_Restoring_State = 1 OR @Restore_Log_Backups = 1
  					set @DB_Restore_Script += ', NORECOVERY'
  					
  																											  
  			
  			END	
  				PRINT '-------- DB restore statement --------'+CHAR(10)+CHAR(10)+@DB_Restore_Script+CHAR(10)

				
				--------- Checking free disk space availability for database restore: ----------------------------------
				SET @message = ''
				SELECT @message +=	(
										SELECT STRING_AGG(dt.Error,CHAR(10))
										FROM
										(
											SELECT
											'--'+CONVERT(VARCHAR,CONVERT(BIGINT,SUM(bf.Size)/1024/1024))+' MB free disk space is required on ''' + fd.fixed_drive_path + ''', while ' + CONVERT(VARCHAR,MIN(fd.free_space_in_bytes)/1024/1024) + ' MB exists.' Error					
											FROM #TempTargetDBFiles tf JOIN #Backup_Files_List bf
											ON bf.FileID = tf.FileID
											JOIN
											(
												SELECT 
													fd0.fixed_drive_path,
													fd0.free_space_in_bytes+ISNULL(dt2.Size,0) free_space_in_bytes
												FROM
												sys.dm_os_enumerate_fixed_drives fd0
												LEFT JOIN 
												(	
													SELECT
														LEFT(physical_name,CHARINDEX(':',physical_name)+1) [DriveLetter],
														SUM(CONVERT(BIGINT,size)*8192) Size
													FROM
													sys.master_files
													WHERE DB_NAME(database_id) = @Restore_DBName
													GROUP BY LEFT(physical_name,CHARINDEX(':',physical_name)+1)
												) dt2
												ON fd0.fixed_drive_path = dt2.DriveLetter
											) fd
											ON tf.tail LIKE (fd.fixed_drive_path+'%')
											GROUP BY fd.fixed_drive_path
											HAVING SUM(bf.Size) > MIN(fd.free_space_in_bytes)
										) dt									
									)
				IF @message <> ''
				BEGIN
					IF @Generate_Statements_Only = 1
					BEGIN
						SET @message= '--Warning!!!'+CHAR(10)+@message+CHAR(10)+'--The restore statement was generated, but there is not available free disk space to restore the database for the paths you selected.'
						PRINT @message
					END
					ELSE
					BEGIN
						SET @message= @message
						RAISERROR(@message,15,1)
					END
                END
			

				------------- Begin generating Log Backups restore statements: ---------------------------------------------------
				IF @Restore_Log_Backups = 1
				BEGIN
					
					SELECT
						--'Joghd',
						 [DiskLogBackupFilesID]
						,[file]
						,[DatabaseName]
						,ISNULL([BackupStartDate],'') [BackupStartDate]
						,[BackupFinishDate]
						,CONVERT(DECIMAL(25,0),NULL) LastLSN
						,[BackupTypeDescription]
						,[ServerName]
						,[FileExtension]
						--,[IsAddedDuringTheLastDiskScan]
						,[IsIncluded]
						,dt.LeadBackupStartDate
					INTO #TempLog
					FROM
					(
						SELECT	TOP 100000000
							 [DiskLogBackupFilesID]
							,[file]
							,[DatabaseName]
							,COALESCE([BackupStartDate],[BackupFinishDate],'') [BackupStartDate]
							,[BackupFinishDate]
							,[BackupTypeDescription]
							,[ServerName]
							,[FileExtension]
							--,[IsAddedDuringTheLastDiskScan]
							,[IsIncluded]
							, COALESCE(LEAD([BackupStartDate]) OVER (ORDER BY [BackupStartDate]), '9999-12-31 23:59:59.000') [LeadBackupStartDate]
						FROM SQLAdministrationDB..DiskLogBackupFiles
						WHERE	DatabaseName = @OriginalDBName AND							
								IsIncluded = 1
						ORDER BY BackupStartDate
					) dt
					WHERE [LeadBackupStartDate] >= CONVERT(DATETIME,LEFT(CONVERT(VARCHAR(50),@BackupFinishDate,121),17)+'00')


					ALTER TABLE #TempLog ADD CONSTRAINT PK_TempLog PRIMARY KEY(BackupStartDate) WITH (FILLFACTOR=80)
					
					
					-- Analyzing and ascertaining the first log backup to restore:
					DECLARE @file NVARCHAR(255)
					DECLARE FinishDateFinder CURSOR LOCAL FOR
						SELECT 
							TOP 2 [file]
						FROM
                        #TempLog
						ORDER BY BackupStartDate
					OPEN FinishDateFinder
						FETCH NEXT FROM FinishDateFinder INTO @file
						WHILE @@FETCH_STATUS = 0
						BEGIN
							--IF @BackupFinishDateForCursor IS NULL
							--BEGIN
							EXEC dbo.usp_BackupDetails @Backup_Path = @file -- nvarchar(1000)
							UPDATE #TempLog 
								SET BackupFinishDate	= (SELECT TOP 1 BackupFinishDate	FROM #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9),
									LastLSN				= (SELECT TOP 1 LastLSN				FROM #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9)
							WHERE CURRENT OF FinishDateFinder
							TRUNCATE TABLE #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
							--END

							FETCH NEXT FROM FinishDateFinder INTO @file
						END
					CLOSE FinishDateFinder
					DEALLOCATE FinishDateFinder
					

					DELETE a FROM
					(
						SELECT TOP 2 * FROM #TempLog 
					) a
					WHERE a.LastLSN < @BackupLastLSN					

					-- Analyzing and ascertaining the last log backup to restore:
					SELECT TOP 1 
							@LastLogBackupID			= DiskLogBackupFilesID,
							@LastLogBackupFinishDate	= BackupFinishDate,
							@LastLogBackupStartDate		= BackupStartDate,
							@LastLogBackupLocation		= [file]
					FROM #TempLog					
					ORDER BY BackupStartDate DESC
                 
					IF @LastLogBackupLocation IS NOT NULL
					BEGIN					
                    
						
						IF @LastLogBackupFinishDate IS NULL
						BEGIN
							EXEC dbo.usp_BackupDetails @Backup_Path = @LastLogBackupLocation -- nvarchar(1000)
							SELECT TOP 1 @LastLogBackupFinishDate = BackupFinishDate FROM #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
							TRUNCATE TABLE #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
						END


						WHILE @LastLogBackupFinishDate < @StopAt
						BEGIN
							DECLARE @NextLogBackup_ID INT,
									@NextLogBackup_BackupStartDate DATETIME,
									@NextLogBackup_BackupFinishDate DATETIME,
									@NextLogBackup_Location NVARCHAR(2000)
						
							SELECT TOP 1
									@NextLogBackup_ID = DiskLogBackupFilesID,
									@NextLogBackup_BackupStartDate = BackupStartDate,
									@NextLogBackup_BackupFinishDate = BackupFinishDate,
									@NextLogBackup_Location = [file]
							FROM SQLAdministrationDB..DiskLogBackupFiles 
							WHERE 
								DatabaseName = @OriginalDBName AND 
								BackupStartDate > @LastLogBackupStartDate
							ORDER BY BackupStartDate

							IF @NextLogBackup_ID = @LastLogBackupID OR @NextLogBackup_ID IS NULL
								BREAK
						
							INSERT #TempLog 
							(
								[file],
								DatabaseName,
								BackupStartDate,
								BackupFinishDate,
								BackupTypeDescription,
								ServerName,
								FileExtension,
								--IsAddedDuringTheLastDiskScan,
								IsIncluded
							)
							SELECT	@NextLogBackup_Location,
									@OriginalDBName,
									@NextLogBackup_BackupStartDate,
									@NextLogBackup_BackupFinishDate,
									'LOG',
									NULL,
									NULL,
									--NULL,
									1
							
							IF @NextLogBackup_BackupFinishDate IS NULL
							BEGIN
								EXEC dbo.usp_BackupDetails @Backup_Path = @NextLogBackup_Location -- nvarchar(1000)
								SELECT TOP 1 @NextLogBackup_BackupFinishDate = BackupFinishDate FROM #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
								TRUNCATE TABLE #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
							END
							SET @LastLogBackupID			= @NextLogBackup_ID							
							SET @LastLogBackupLocation		= @NextLogBackup_Location
							SET @LastLogBackupStartDate		= @NextLogBackup_BackupStartDate
							SET @LastLogBackupFinishDate	= @NextLogBackup_BackupFinishDate
							
						
						END
					

						SELECT 
							@Log_Restore_Script = STRING_AGG(CONVERT(NVARCHAR(max),'RESTORE LOG '+QUOTENAME(@Restore_DBName)+' FROM DISK=N'''+[file]+''''),' WITH NORECOVERY'+CHAR(10)),
							@No_of_Log_Backups	= COUNT([file])
						FROM
						#TempLog
						


						--**				
						--IF OBJECT_ID('SQLAdministrationDB..temp') IS NULL
						--	CREATE TABLE SQLAdministrationDB..temp (str NVARCHAR(max))
						--TRUNCATE TABLE SQLAdministrationDB..temp
						--INSERT SQLAdministrationDB..temp
						--SELECT @Log_Restore_Script
						--**
						
						IF @Log_Restore_Script <> ''
						BEGIN

							PRINT CHAR(10)+'----- Log restore statement'+IIF(@No_of_Log_Backups>1,'s','')+'('+CONVERT(VARCHAR(3),@No_of_Log_Backups)+' backup'+IIF(@No_of_Log_Backups>1,'s','')+'): -----'+ CHAR(10)

							IF @StopAt<@LastLogBackupFinishDate
								SET @Log_Restore_Script+=CONVERT(NVARCHAR(MAX),' WITH STOPAT=N'''+CONVERT(VARCHAR(23),@StopAt,126)+''''+IIF(@Keep_Database_in_Restoring_State = 1,', NORECOVERY',''))
							ELSE
							BEGIN                    
								IF @Keep_Database_in_Restoring_State = 1
									SET @Log_Restore_Script+=' WITH NORECOVERY'
								--SET @StopAt = NULL
							END
												
							EXEC dbo.usp_PrintLong @Log_Restore_Script
							PRINT ''
						END
						

						--------- Getting the FILELIST detail of the last log backup: ----------------------------
						SET @sql = 'RESTORE FILELISTONLY FROM DISK = @Backup_Path'
						BEGIN TRY
							TRUNCATE TABLE #Backup_Files_List
  							INSERT INTO #Backup_Files_List
  							EXEC master.sys.sp_executesql @sql , N'@Backup_Path nvarchar(150)', @LastLogBackupLocation
						END TRY
						BEGIN CATCH
							RAISERROR('Your Log Backup file is probably corrupt, encrypted without the corresponding certificate on your server, not recognizable by this version of SQL Server, or not a database backup file. Restore will not continue.',16,1)
						END CATCH

						--------- Checking free disk space availability for the last log restore: ----------------------------------
						SET @message = ''
						SELECT @message +=	(
												SELECT STRING_AGG(dt.Error,CHAR(10))
												FROM
												(
													SELECT
													'--'+CONVERT(VARCHAR,CONVERT(BIGINT,SUM(bf.Size)/1024/1024))+' MB free disk space is required on ''' + fd.fixed_drive_path + ''', while ' + CONVERT(VARCHAR,MIN(fd.free_space_in_bytes)/1024/1024) + ' MB exists.' Error					
													FROM #TempTargetDBFiles tf JOIN #Backup_Files_List bf
													ON bf.FileID = tf.FileID
													JOIN
													(
														SELECT 
															fd0.fixed_drive_path,
															fd0.free_space_in_bytes+ISNULL(dt2.Size,0) free_space_in_bytes
														FROM
														sys.dm_os_enumerate_fixed_drives fd0
														LEFT JOIN 
														(	
															SELECT
																LEFT(physical_name,CHARINDEX(':',physical_name)+1) [DriveLetter],
																SUM(CONVERT(BIGINT,size)*8192) Size
															FROM
															sys.master_files
															WHERE DB_NAME(database_id) = @Restore_DBName
															GROUP BY LEFT(physical_name,CHARINDEX(':',physical_name)+1)
														) dt2
														ON fd0.fixed_drive_path = dt2.DriveLetter
													) fd
													ON tf.tail LIKE (fd.fixed_drive_path+'%')
													GROUP BY fd.fixed_drive_path
													HAVING SUM(bf.Size) > MIN(fd.free_space_in_bytes)
												) dt
											)
						IF @message <> ''
						BEGIN
							IF @Generate_Statements_Only = 1
							BEGIN
								SET @message= '--Warning!!!'+CHAR(10)+@message+CHAR(10)+'--The log restore statement(s) was generated, but there is not available free disk space to restore the database for the paths you selected.'
								PRINT @message
							END
							ELSE
							BEGIN
								SET @message= @message+CHAR(10)+'However, you can restore the database without some of the log backups, as it currently fits on your disk. To do so, set @Restore_Log_Backups to 0 and rerun the script.'
								RAISERROR(@message,15,1)
							END
						END


					END
					ELSE
                    BEGIN
						SET @message = CHAR(10)+'--Warning!!! @Restore_Log_Backups option was set to 1 but no log backups where found for the database "'+@OriginalDBName+'" with the given criteria.'+IIF(@Force_Recovery_If_No_Log_Backups_Found=1,' The database will be recoverd because @Force_Recovery_If_No_Log_Backups_Found was set to 1.',' ###The database will remain in restoring state###')+CHAR(10)
						PRINT @message
					END

                END				
				------------- End generating Log Backups restore statements ------------------------------------------------------
				
				IF (@Generate_Statements_Only = 0)
				BEGIN
					IF (@USE_SQLAdministrationDB_Database = 1)
					BEGIN 
						SET @temp1 =
						'
							INSERT SQLAdministrationDB..RestoreHistory
							(
								DiskBackupFilesID,
								LastRestoredLogBackupID,
								RestoreStartDate,
								RestoreFinishDate,
								DestinationDatabaseName,
								UserName,
								Replace,
								Recovery,
								StopAt,
								TargetRecoveryModel, 
								TargetUpdateability, 
								isBackupFileDeleteRequested, 
								ShrinkDatabase_policy,
								ShrinkLogFile_policy,
								RebuildLogFile_policy,
								GrantAllPermissions_policy
							)
							VALUES
							(   
								@DiskBackupFilesID,
								@LastRestoredLogBackupID,
								GETDATE(), -- RestoreStartDate - datetime
								NULL, -- RestoreFinishDate - datetime
								@Restore_DBName, -- DestinationDatabaseName - sysname
								ORIGINAL_LOGIN(), -- UserName - sysname
								@DatabaseReplaceFlag, -- Replace - bit
								~@Keep_Database_in_Restoring_State, -- Recovery - bit
								IIF(@StopAt<>''9999-12-31 23:59:59'',@StopAt,NULL),  -- StopAt - datetime2(7),
								@Change_Target_RecoveryModel_To,
								IIF(@Set_Target_Database_ReadOnly = 0, ''Read-Write'', ''Read-Only''),
								@Delete_Backup_File,
								@ShrinkDatabase_policy,
								@ShrinkLogFile_policy,
								@RebuildLogFile_policy,
								@GrantAllPermissions_policy
							)
							
							SELECT @identity = scope_identity()
						'		
						EXEC sys.sp_executesql 
												@temp1,
												N'
													@DiskBackupFilesID INT,
													@Restore_DBName sysname,
													@Keep_Database_in_Restoring_State BIT,
													@DatabaseReplaceFlag BIT,
													@StopAt datetime,
													@Change_Target_RecoveryModel_To VARCHAR(17),
													@Set_Target_Database_ReadOnly VARCHAR(10),
													@Delete_Backup_File bit,
													@ShrinkDatabase_policy SMALLINT,
													@ShrinkLogFile_policy SMALLINT,
													@RebuildLogFile_policy VARCHAR(24),
													@GrantAllPermissions_policy SMALLINT,
													@LastRestoredLogBackupID int,
													@identity int out
												',
												@DiskBackupFilesID,
												@Restore_DBName,
												@Keep_Database_in_Restoring_State,
												@DatabaseReplaceFlag,
												@StopAt,
												@Change_Target_RecoveryModel_To,
												@Set_Target_Database_ReadOnly,
												@Delete_Backup_File,
												@ShrinkDatabase_policy,
												@ShrinkLogFile_policy,
												@RebuildLogFile_policy,
												@GrantAllPermissions_policy,
												@LastLogBackupID,
												@identity OUT
					END
					SET @DB_Restore_Script+= CHAR(10) + 'select @Degree_of_Parallelism = dop from sys.dm_exec_requests where session_id = @@spid'
                    
					RAISERROR('** Begining database restore... **',0,1) WITH NOWAIT
					PRINT ''
					IF @Drop_SQLSBuffers_Before_Restore = 1
					BEGIN
						SET @temp1 = 'CHECKPOINT'+CHAR(10)+'EXEC sys.sp_flush_log'+CHAR(10)+'DBCC DROPCLEANBUFFERS() WITH no_infomsgs'
						EXEC(@temp1)
					END 
					-- Execute the prepared restore script:
  					EXEC sys.sp_executesql @DB_Restore_Script, N'@Degree_of_Parallelism int out', @Degree_of_Parallelism OUT
					
					IF @Force_Recovery_If_No_Log_Backups_Found = 1 AND @No_of_Log_Backups = 0 AND @Restore_Log_Backups = 1
					BEGIN
						SET @temp1 = 'RESTORE DATABASE '+QUOTENAME(@Restore_DBName)+' WITH RECOVERY'
						EXEC(@temp1)
					END

					
					IF (SELECT state FROM sys.databases WHERE name = @Restore_DBName) = 0
					BEGIN
						SET @temp1 ='ALTER DATABASE '+QUOTENAME(@Restore_DBName)+' SET SINGLE_USER WITH ROLLBACK IMMEDIATE'
						EXECUTE(@temp1)
					END


					SET @message = 'Elapsed time: ' + dbo.ufn_ElapsedTime(@OperationStartTime)
					RAISERROR(@message,0,1) WITH NOWAIT

					-- Setting newly restored database to single user mode to avoid interfering of other users until all the processes are finished.
					SET @temp1 = 
								'USE ' + QUOTENAME(@Restore_DBName) + '
								 ALTER DATABASE ' + QUOTENAME(@Restore_DBName) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE'
					IF (SELECT state FROM sys.databases WHERE name = @Restore_DBName) = 0
						EXEC (@temp1)

					PRINT('')

					IF @Restore_Log_Backups = 1 AND @No_of_Log_Backups > 0
					BEGIN
						PRINT 'Beginning Log backups restore...'+CHAR(10)
						DECLARE @count SMALLINT = 1

						DECLARE LogRestore CURSOR LOCAL FOR
							SELECT 
								CONVERT(NVARCHAR(MAX),'RESTORE LOG '+QUOTENAME(@Restore_DBName)+' FROM DISK=N'''+[file]+'''')							
							FROM
							#TempLog
							ORDER BY BackupStartDate
						OPEN LogRestore
							FETCH NEXT FROM LogRestore INTO @Log_Restore_Script
							WHILE @@FETCH_STATUS = 0
							BEGIN
								
								PRINT '-------- '+CONVERT(VARCHAR(3),@count)+'/'+CONVERT(VARCHAR(3),@No_of_Log_Backups)+' --------'

								IF @count < @No_of_Log_Backups
									SET @Log_Restore_Script += ' WITH NORECOVERY'
								ELSE
								BEGIN
									IF @StopAt<@LastLogBackupFinishDate
										SET @Log_Restore_Script+=CONVERT(NVARCHAR(MAX),' WITH STOPAT=N'''+CONVERT(VARCHAR(23),@StopAt,126)+''''+IIF(@Keep_Database_in_Restoring_State = 1,', NORECOVERY',''))
									ELSE
									BEGIN                    
										IF @Keep_Database_in_Restoring_State = 1
											SET @Log_Restore_Script+=' WITH NORECOVERY'
										SET @StopAt = NULL
									END
								END 

								PRINT @Log_Restore_Script

								BEGIN TRY
									EXEC (@Log_Restore_Script)
									SET @count+=1
								END TRY
								BEGIN CATCH

									SET @message = 'Restoring the last log bk failed. Probably the log bks'' chain is lost or the file is unreadable. You should notify your DB Admins immediately. The DB is in restoring state.'+' Total '+CONVERT(VARCHAR(3),(@count-1))+' log bks successfully restored.'
									RAISERROR(@message,16,1)
									

								END CATCH

								FETCH NEXT FROM LogRestore INTO @Log_Restore_Script
							END
						CLOSE LogRestore
						DEALLOCATE LogRestore
						SET @message = 'Elapsed time: ' + dbo.ufn_ElapsedTime(@OperationStartTime)
						RAISERROR(@message,0,1) WITH NOWAIT

					END
					ELSE IF @Restore_Log_Backups = 1
						BEGIN
							SET @StopAt = NULL
							PRINT '--No Log backups exist to restore.'
						END


					IF @USE_SQLAdministrationDB_Database = 1
					BEGIN
						SET @temp1 =
						'
							UPDATE SQLAdministrationDB..RestoreHistory 
							SET	RestoreFinishDate = GETDATE(),
							[Duration (DD:HH:MM:SS)] = (
															SELECT
																REPLICATE(''0'',2-LEN(DAYS))+DAYS+'':''+
																REPLICATE(''0'',2-LEN(HOURS))+HOURS+'':''+
																REPLICATE(''0'',2-LEN(MINUTES))+MINUTES+'':''+
																REPLICATE(''0'',2-LEN(SECONDS))+SECONDS+''.''+
																REPLICATE(''0'',3-LEN(MILLISECONDS))+MILLISECONDS [Duration DD:HH:MM:SS]
															FROM
															(
																SELECT
																	CONVERT(VARCHAR(2),HOURS / 24) [DAYS],
																	CONVERT(VARCHAR(2),HOURS % 24) [HOURS],
																	CONVERT(VARCHAR(2),MINUTES) [MINUTES],
																	CONVERT(VARCHAR(2),SECONDS) [SECONDS],
																	CONVERT(VARCHAR(3),MILLISECONDS) [MILLISECONDS]
																FROM
																(
																	SELECT 
																		MINUTES / 60 [HOURS],
																		[MINUTES] % 60 [MINUTES],
																		[SECONDS],
																		MILLISECONDS
																	FROM 
																	(
																		SELECT		
																			SECONDS / 60 [MINUTES],
																			SECONDS % 60 [SECONDS],
																			MILLISECONDS
																		FROM
																		(
																			SELECT
																			diff/1000 [SECONDS],
																			diff % 1000 [MILLISECONDS]
																			from
																			(
																				select 	datediff(MILLISECOND, RestoreStartDate,	GETDATE()) [diff]
																			) dt
																		) dt
																	) dt
																) dt
															) dt
														),
								dop = @Degree_of_Parallelism,
								StopAt = @StopAt
							WHERE RestoreHistoryID = @identity
						'
						EXEC sys.sp_executesql @temp1, N'@identity int, @Degree_of_Parallelism int, @StopAt datetime', @identity, @Degree_of_Parallelism, @StopAt
                    END
					PRINT(CHAR(10)+'** End '+ @Restore_DBName +' Database Restore **')
					



				END
				ELSE
					PRINT CHAR(10)+'--Nothing was restored as @Generate_Statements_Only was set to 1'
					
				----- Deleting backup file on successful restore and user's request
				IF (@@error = 0 AND @Delete_Backup_File = 1)
				BEGIN
					
					DECLARE @ErrorNo INT
					EXEC xp_delete_files @Backup_Location
					
					IF(@@ERROR <> 0)
					BEGIN                    					
						DECLARE @ErrorMessage NVARCHAR(1000) = 'Deleting backup file '+ @Backup_Location +' failed due to the system above error message.'	
						PRINT @ErrorMessage
					END
					
                END

				
  				--=== Postrestore operations:      		
  				IF @Generate_Statements_Only = 0 AND (SELECT state FROM sys.databases WHERE name = @Restore_DBName) = 0 
				BEGIN
					RAISERROR ('** Begining postrestore operations: **',0,1) WITH NOWAIT
					DECLARE @temp5 VARCHAR(4000) = ''
					IF (@Change_Target_RecoveryModel_To <> 'InheritFromSource')
						SET @temp5 = 'ALTER DATABASE ' + QUOTENAME(@Restore_DBName) + ' SET RECOVERY ' + @Change_Target_RecoveryModel_To + CHAR(10)
				
					SET @Script_to_Execute_After_Restore = 'USE '+QUOTENAME(@Restore_DBName)+CHAR(10)+@Script_to_Execute_After_Restore
					EXEC(@Script_to_Execute_After_Restore)

					-- Begining shrink/log rebuild operations, if user requests:
					SET @temp5 = 'declare @SQL nvarchar(500)'+CHAR(10)
					IF @RebuildLogFile_policy <>''
					BEGIN
						BEGIN TRY
							SET @temp1 =
							'
								IF EXISTS (SELECT 1 FROM '+QUOTENAME(@Restore_DBName)+'.sys.filegroups WHERE type = ''FX'')
									RAISERROR(''Rebuilding log is not supported for databases containing files belonging to MEMORY_OPTIMIZED_DATA filegroup (SQL Server Error Message 41836). The argument @RebuildLogFile_policy for database '+QUOTENAME(@Restore_DBName)+' was ignored.'',16,1)
							'
							EXEC(@temp1)
							DECLARE @SIZE VARCHAR(20),
									@MAXSIZE VARCHAR(20),
									@FILEGROWTH VARCHAR(20),
									@NewLog_path NVARCHAR(1000)
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
							SELECT TOP 1 @DirPath = tail FROM #TempTargetDBFiles WHERE type = 'L'
							SET @DirPath = left(@DirPath, (len(@DirPath)-charindex('\',REVERSE(@DirPath))))
							PRINT ''
							SET @NewLog_path = @DirPath + '\' + @Restore_DBName + '_$$$newLog.ldf'
							SET @temp1 =
							'
								alter database ' + QUOTENAME(@Restore_DBName) + ' set emergency


								ALTER DATABASE ' + QUOTENAME(@Restore_DBName) + '
								   REBUILD LOG ON (Name = ''' + @Restore_DBName + '_$$$newLog'' , FILENAME=''' + @NewLog_path + ''', SIZE = '+@SIZE+', MAXSIZE = '+@MAXSIZE+', FILEGROWTH = '+@FILEGROWTH+')

								alter database ' + QUOTENAME(@Restore_DBName) + ' set ONLINE

								alter database ' + QUOTENAME(@Restore_DBName) + ' set multi_user
							'					
							EXEC (@temp1)

							-- Now deleting the privious log files iteratively:
							DECLARE @Log_Path NVARCHAR(512)
							DECLARE delete_log CURSOR FOR
								SELECT tail FROM #TempTargetDBFiles WHERE type = 'L'
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
								print ''Log file was successfully rebuilt to new ''+'''+@SIZE+'''+'' size, the new log file name is "''+''' + @NewLog_path + '''+''":''+char(10)+''Note: There is no risk of ''''Transactional inconsistency'''', in this stored procedure specifically, despite the warning message that Microsoft has generated above and you do not need to run CHECKDB for this in particular. Also, the extra log files have been deleted.''
							'
							EXEC(@temp1)
						END TRY
						BEGIN CATCH
							PRINT CHAR(10) + 'Warning!! ' + ERROR_MESSAGE()
							SET @ShrinkLogFile_policy = -1
							GOTO SHRINKLOGPOINT
						END CATCH
					END
					ELSE		-- Shrink Log File if the user has not chosen to rebuild it.
						IF (@ShrinkLogFile_policy >= -1)
						BEGIN
							SHRINKLOGPOINT:
							SET @temp5  =	'declare @SQL nvarchar(500)'+CHAR(10)
							SET @temp5 +=	'PRINT CHAR(10)+''--===Begining the Logfile shrink op:''' + CHAR(10) +
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
						SET @temp5  =	'declare @SQL nvarchar(500)'+CHAR(10)
						SET @temp5 +=	'PRINT CHAR(10)+''--===Begining the DB shrink op:''' + CHAR(10) +
										'USE ' + QUOTENAME(@Restore_DBName) + CHAR(10) + 					
										'SET @SQL = ''DBCC SHRINKDATABASE(''+'''+QUOTENAME(@Restore_DBName)+'''+'''+
										IIF(@ShrinkDatabase_policy=-1,'',' ,'+CONVERT(VARCHAR(10),@ShrinkDatabase_policy))+
										') WITH NO_INFOMSGS''' + CHAR(10) +
										'exec (@SQL)' + CHAR(10)
						EXEC(@temp5)
					END
					IF (@Set_Target_Database_ReadOnly = 1)
						SET @temp5 = 'alter database ' + @Restore_DBName + ' set READ_ONLY'
					
					
				
  					EXEC (@temp5)

					-----========= Begin grant permissions:
					IF @GrantAllPermissions_policy = 1	-- Add every current user to db_owner group
					BEGIN
					
						SET @temp5 = 'PRINT ''--===Begining the Grant all permissions(value 1) op:''' + CHAR(10) +
						'
							use '+quotename(@Restore_DBName)+'
							DECLARE @sql NVARCHAR(max)	
							DECLARE @USERNAME sysname 
							DECLARE InnerDB CURSOR FOR
								SELECT name FROM sys.database_principals 
								WHERE	principal_id BETWEEN 6 AND 16380 AND
										--(CHARINDEX(''.'',name)<>0) AND 
										type IN (''s'',''u'')
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
						'
						EXEC(@temp5)
					END

					IF @GrantAllPermissions_policy = 2	-- Remove every db user, turn on guest account and make it a member of db_owner role
					BEGIN
					
						SET @temp5 = 'PRINT ''--===Begining the Grant all permissions(value 2) op:''' + CHAR(10) +
						'
							use '+quotename(@Restore_DBName)+'
							GRANT CONNECT TO [GUEST]
							ALTER ROLE [db_owner] ADD MEMBER [GUEST]
							DECLARE @sql NVARCHAR(max)	
							DECLARE @USERNAME sysname 
							DECLARE InnerDB CURSOR FOR
								SELECT name FROM sys.database_principals
								WHERE	principal_id BETWEEN 6 AND 16380 AND 
										--(CHARINDEX(''.'',name)<>0) AND 
										type IN (''s'',''u'')
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
						'
						EXEC(@temp5)
					END

					IF @GrantAllPermissions_policy = 3
					BEGIN
						SET @temp5 = 'PRINT ''--===Begining the Grant all permissions(value 3) op:''' + CHAR(10) +
						'
							use '+quotename(@Restore_DBName)+'
							GRANT CONNECT TO [GUEST]
							ALTER ROLE [db_owner] ADD MEMBER [GUEST]
							DECLARE @sql NVARCHAR(max)	
							DECLARE @USERNAME sysname 
							DECLARE InnerDB CURSOR FOR
								SELECT name FROM sys.database_principals
								WHERE	principal_id BETWEEN 6 AND 16380 AND
										--(CHARINDEX(''.'',name)<>0) AND 
										type IN (''s'',''u'')
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
						'
						EXEC(@temp5)
					END
					-----========= End grant permissions
					

					SET @temp5 = 'ALTER DATABASE ' + QUOTENAME(@Restore_DBName) + ' SET MULTI_USER' + CHAR(10) +
								  'PRINT CHAR(10)+''|The database is ready for use.|'''
					EXEC(@temp5)

				END
				RETURN 0
			END TRY
			BEGIN CATCH
				PRINT ''
				DECLARE @Severity INT = ERROR_SEVERITY()
				DECLARE @State INT = ERROR_STATE()

				IF (SELECT state FROM sys.databases WHERE name = @Restore_DBName) IN (0,5)
				BEGIN
					SET @temp1 = 'ALTER DATABASE '+QUOTENAME(@Restore_DBName)+' SET ONLINE'
					EXEC (@temp1)
					SET @temp1 = 'ALTER DATABASE '+QUOTENAME(@Restore_DBName)+' SET MULTI_USER'
					EXEC (@temp1)								  
                END
				SET @ErrNo = ERROR_NUMBER()
				set @message = 'Fatal error: '+IIF(@ErrNo=50000,'','System Message:'+CHAR(10)+ 'Msg '+CONVERT(VARCHAR(50),@ErrNo)+', Level '+CONVERT(VARCHAR(50),@Severity)+', State '+CONVERT(VARCHAR(50),@State)+', Line '+CONVERT(VARCHAR(50),ERROR_LINE()))+CHAR(10)+
								+ERROR_MESSAGE()	
				raiserror(@message, @Severity, @State)
				
				
				PRINT 'Ali Momen: This is not my fault Ostad! :D'
				PRINT ''
				RETURN 1
			END CATCH
			
END
GO

----============= Third SP: File Operations =========================================================================

--CREATE OR ALTER PROC FileOperations
	
--AS
--BEGIN
	
--END
--GO

--============= Third SP: Main SP =================================================================================

-- Main (Third) SP:

CREATE OR ALTER PROC usp_restore_latest_backups 

	@Drop_SQLSBuffers_Before_Restore BIT = 0,
	@Ignore_Existant BIT = 0,										
																-- ignore restoring databases that already exist on target
	@Destination_Database_Name_suffix nvarchar(128) = N'',
																	-- You can specify the destination database names' suffix here. If the destination database name is equal to the backup database name,
																	-- the database will be restored on its own.
	@Destination_Database_Name_prefix NVARCHAR(128) = N'',
	@Destination_DatabaseName sysname = N'',						-- This option only works if you have only one database to restore, and prefix and suffix options will also be applied.
	@Destination_Database_DataFiles_Location nvarchar(300) = '',			
																	-- This script creates the folders if they do not exist automatically. Make sure SQL Service has permission to create such folders
																	-- This variable must be in the form of for example 'D:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\DATA'
	@Destination_Database_LogFile_Location nvarchar(300) = '',

	@Backup_root_or_path nvarchar(300),			-- Root location for backup files.
	
	
	@BackupFileName_naming_convention NVARCHAR(4000) = '',
	@Skip_Files_Not_Matching_Naming_Convention BIT = 0,
	@BackupFileName_RegexFilter NVARCHAR(128) = '',				-- Use this filter to speed file scouring up, if you have too many files in the directory.
	
	@BackupFinishDate_StartDATETIME DATETIME = '1900.01.01 00:00:00',
	@BackupFinishDate_EndDATETIME DATETIME = '9999.12.31 23:59:59',
	@USE_SQLAdministrationDB_Database BIT = 0,					-- Create or Update SQLAdministrationDB and DiskBackupFiles and RestoreHistory tables inside SQLAdministrationDB database for faster access to backup file records
																-- and their details. This is useful when your backup repository is very large, containing too many files. Using this feature does not speed up file scouring operations at the first run,
																-- but next times the runtime will be decreased remarkably because it evades RESTORE HEADERONLY for previously processed files.
	@Exclude_system_databases BIT = 1,

	@Exclude_DBName_Filter NVARCHAR(1000) = N'master',				-- Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
																-- N'Northwind,AdventureWorks, StackOverFlow'. The script excludes databases that contain any of such keywords
																-- in the name like AdventureWorks2019. Note that space at the begining and end of the names will be disregarded
	
	@Include_DBName_Filter NVARCHAR(1000) = N'',					-- Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
																-- N'Northwind,AdventureWorks, StackOverFlow'. The script includes databases that contain any of such keywords
																-- in the name like AdventureWorks2019 and excludes others. Note that space at the begining and end of the names
																-- will be disregarded.

	@IncludeSubdirectories BIT = 1,								-- Choosing whether to include subdirectories or not while the script is searching for backup files.	
	
	
	@Restore_Log_Backups BIT = 0,
	@Force_Recovery_If_No_Log_Backups_Found bit = 0,
	@LogBackup_root_or_path NVARCHAR(300) = '',
	@LogBackupFileName_RegexFilter NVARCHAR(128) = '',
	@StopAt DATETIME = '9999-12-31 23:59:59',						-- For point in time recovery, set the exact point in time, to which you want to redo your database logs.
	@Live_Restore_LogBackup_Temporary_Location NVARCHAR(300) = '',


	
	@Keep_Database_in_Restoring_State bit = 0,					-- If equals to 1, the database will be kept in restoring state
	@Take_tail_of_log_backup_of_existing_database bit = 1,
	@DataFileSeparatorChar nvarchar(2) = '_',						-- This parameter specifies the punctuation mark used in data files names. For example "_"
																-- in NW_1.mdf or "$" in NW$1.mdf

	@STATS TINYINT = 50,											-- Set this to specify stats parameter of restore statements											
	@Change_Target_RecoveryModel_To NVARCHAR(17) = 'InheritFromSource',		-- Possible options: FULL|BULK-LOGGED|SIMPLE|InheritFromSource
	@Set_Target_Databases_ReadOnly BIT = 0,
	@Delete_Backup_File BIT = 0,
																-- Turn this feature on to delete the backup files that are successfully restored.
	@Generate_Statements_Only bit = 1,
	@Email_Failed_Restores_To NVARCHAR(128) = NULL,
	@Activate_Destination_Database_Containment BIT = 1,
	@Set_Destination_FILESTREAM_Feature_To TINYINT = 2,
	@Stop_On_Error INT = 0,
	@ShrinkDatabase_policy SMALLINT = -2,							-- Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave %x of free space after shrinking 
	@ShrinkLogFile_policy SMALLINT = -2,							-- Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave x MBs of free space after shrinking 
	@RebuildLogFile_policy VARCHAR(24) = '',						-- Possible options: NULL or Empty string: Do not rebuild | 'x:y:z' (For example, 4MB:64MB:1024MB) rebuild to SIZE = x, FILEGROWTH = y, MAXSIZE = z. If @RebuildLogFile_policy is specified, @ShrinkLogFile_policy will be ignored.
	@GrantAllPermissions_policy SMALLINT = -2,						-- Possible options: -2: Do not alter permissions | 1: Make every current DB user, a member of db_owner group | 2: Turn on guest account and make guest a member of db_owner group
	@Script_to_Execute_After_Restore NVARCHAR(MAX) = ''
--WITH ENCRYPTION--, EXEC AS 'dbo'
AS
BEGIN
	SET NOCOUNT ON
	
	DECLARE @OperationStartTime DATETIME = SYSDATETIME()

	---------------------------- Standardization of Customizable Variables:
		
	IF @Generate_Statements_Only = 1 SET @Delete_Backup_File = 0

	IF RIGHT(TRIM(@Destination_Database_Datafiles_Location), 1) = '\' 
		SET @Destination_Database_Datafiles_Location = 
		left(TRIM(@Destination_Database_Datafiles_Location),(len(@Destination_Database_Datafiles_Location)-1))
	
	IF RIGHT(TRIM(@Backup_root_or_path), 1) = '\' 
		SET @Backup_root_or_path = 
		left(TRIM(@Backup_root_or_path),(len(@Backup_root_or_path)-1))
	
	IF RIGHT(TRIM(@LogBackup_root_or_path), 1) = '\' 
		SET @LogBackup_root_or_path = 
		left(TRIM(@LogBackup_root_or_path),(len(@LogBackup_root_or_path)-1))
	
	--IF RIGHT(@Temp_Working_Directory, 1) = '\' 
	--	SET @Temp_Working_Directory = 
	--	left(@Temp_Working_Directory,(len(@Temp_Working_Directory)-1))
	
	SET @Destination_Database_DataFiles_Location = ISNULL(@Destination_Database_DataFiles_Location,'')	
	IF @Destination_Database_DataFiles_Location = ''
		SET @Destination_Database_DataFiles_Location = convert(nvarchar(300),SERVERPROPERTY('InstanceDefaultDataPath'))
	
	SET @Destination_Database_LogFile_Location = ISNULL(@Destination_Database_LogFile_Location,'')
	IF @Destination_Database_LogFile_Location = ''
		SET @Destination_Database_LogFile_Location = convert(nvarchar(300),SERVERPROPERTY('InstanceDefaultLogPath'))	
			
	SET @Backup_root_or_path = isNULL(@Backup_root_or_path,'')
	IF @Backup_root_or_path = ''
		EXEC master.dbo.xp_instance_regread 
						N'HKEY_LOCAL_MACHINE', 
						N'Software\Microsoft\MSSQLServer\MSSQLServer',N'BackupDirectory', 
						@Backup_root_or_path OUTPUT,	
						'no_output'	
		

	
	IF RIGHT(@Destination_Database_DataFiles_Location, 1) = '\' SET @Destination_Database_DataFiles_Location = left(@Destination_Database_DataFiles_Location,(len(@Destination_Database_DataFiles_Location)-1))
	IF RIGHT(@Destination_Database_LogFile_Location, 1) = '\'	SET @Destination_Database_LogFile_Location = left(@Destination_Database_LogFile_Location,(len(@Destination_Database_LogFile_Location)-1))
	IF RIGHT(@Live_Restore_LogBackup_Temporary_Location, 1) = '\'	SET @Live_Restore_LogBackup_Temporary_Location = left(@Live_Restore_LogBackup_Temporary_Location,(len(@Live_Restore_LogBackup_Temporary_Location)-1))	
	
	SET @Force_Recovery_If_No_Log_Backups_Found = ISNULL(@Force_Recovery_If_No_Log_Backups_Found,0)
	SET @Drop_SQLSBuffers_Before_Restore = ISNULL(@Drop_SQLSBuffers_Before_Restore,0)
	SET @Exclude_DBName_Filter = ISNULL(@Exclude_DBName_Filter,'')
	SET @Live_Restore_LogBackup_Temporary_Location = ISNULL(@Live_Restore_LogBackup_Temporary_Location,'')
	SET @Exclude_system_databases = ISNULL(@Exclude_system_databases,0)
	SET @Include_DBName_Filter = ISNULL(@Include_DBName_Filter,'')		
	SET @IncludeSubdirectories = ISNULL(@IncludeSubdirectories,1)
	SET @Keep_Database_in_Restoring_State = ISNULL(@Keep_Database_in_Restoring_State,0)
	SET @Take_tail_of_log_backup_of_existing_database = ISNULL(@Take_tail_of_log_backup_of_existing_database,1)
	SET @Set_Target_Databases_ReadOnly = ISNULL(@Set_Target_Databases_ReadOnly,0)
	SET @Delete_Backup_File = ISNULL(@Delete_Backup_File,0)
	SET @Destination_Database_Name_suffix = ISNULL(@Destination_Database_Name_suffix,'')
	SET @StopAt = iif(@StopAt is null or @StopAt = '' or @Restore_Log_Backups = 0,'9999.12.31 23:59:59',@StopAt)
	SET @BackupFinishDate_EndDATETIME = iif(@BackupFinishDate_EndDATETIME is null or @BackupFinishDate_EndDATETIME = '', '9999.12.31 23:59:59', @BackupFinishDate_EndDATETIME)
	SET @Script_to_Execute_After_Restore = ISNULL(@Script_to_Execute_After_Restore,'')
	IF	@StopAt < @BackupFinishDate_StartDATETIME RAISERROR('@StopAt cannot be less than @BackupFinishDate_StartDATETIME. Check your inputs.',16,1)
	IF	@Skip_Files_Not_Matching_Naming_Convention = 1 AND @BackupFileName_naming_convention = '' RAISERROR('Both @Skip_Files_Not_Matching_Naming_Convention is set to 1 and @BackupFileName_naming_convention is not defined.',16,1)


	IF	@Restore_Log_Backups = 1 SET @BackupFinishDate_EndDATETIME = @StopAt
	
	IF	@BackupFinishDate_EndDATETIME<@BackupFinishDate_StartDATETIME RAISERROR ('@BackupFinishDate_EndDATETIME cannot be less than @BackupFinishDate_StartDATETIME.',16,1)
	

	SET @Skip_Files_Not_Matching_Naming_Convention = ISNULL(@Skip_Files_Not_Matching_Naming_Convention,0)
	SET @LogBackup_root_or_path = ISNULL(@LogBackup_root_or_path,'')
	IF	@LogBackup_root_or_path = '' SET @LogBackup_root_or_path = @Backup_root_or_path

	set @LogBackupFileName_RegexFilter = isnull(@LogBackupFileName_RegexFilter,'')
	IF	@Restore_Log_Backups=1 AND @LogBackup_root_or_path='' RAISERROR ('@Restore_Log_Backups is set to 1 but @LogBackup_root_or_path was not specified.',16,1)

	SET @BackupFileName_naming_convention = ISNULL(@BackupFileName_naming_convention,'')

	IF	@BackupFileName_naming_convention <> '' AND (CHARINDEX('DBName',@BackupFileName_naming_convention)=0 OR CHARINDEX('TIMESTAMP',@BackupFileName_naming_convention)=0)
	begin
	RAISERROR('@BackupFileName_naming_convention is used, but either DBName or TIMESTAMP is not specified.',16,1)
	RETURN 1
	end
	--SET @Temp_Working_Directory = ISNULL(@Temp_Working_Directory,'')
	SET @DataFileSeparatorChar = ISNULL(@DataFileSeparatorChar,'_')
	SET @Change_Target_RecoveryModel_To = ISNULL(@Change_Target_RecoveryModel_To,'InheritFromSource')
	SET @Email_Failed_Restores_To = ISNULL(@Email_Failed_Restores_To,'')
	SET @Backup_root_or_path = REPLACE(@Backup_root_or_path,'"','')
	SET @Destination_Database_DataFiles_Location = REPLACE(@Destination_Database_DataFiles_Location,'"','')
	SET @Destination_Database_LogFile_Location = REPLACE(@Destination_Database_LogFile_Location,'"','')
	SET @Stop_On_Error = ISNULL(@Stop_On_Error,0)
	--SET @Destination_Database_Datafile_suffix = ISNULL(@Destination_Database_Datafile_suffix,'')
	SET @Force_Recovery_If_No_Log_Backups_Found = ISNULL(@Force_Recovery_If_No_Log_Backups_Found,0)
	SET @RebuildLogFile_policy = ISNULL(@RebuildLogFile_policy,'')
	SET @BackupFileName_RegexFilter = ISNULL(@BackupFileName_RegexFilter,'')
	
	SET @BackupFinishDate_StartDATETIME = ISNULL(@BackupFinishDate_StartDATETIME,'1900.01.01 00:00:00')
	--SET @BackupFinishDate_EndDATETIME = ISNULL(@BackupFinishDate_EndDATETIME,'9999.12.31 23:59:59')
	SET @USE_SQLAdministrationDB_Database = ISNULL(@USE_SQLAdministrationDB_Database,0)				
	SET @Destination_DatabaseName = ISNULL(@Destination_DatabaseName,'')

	--------------- Other Variables: !!!! Warning: Please do not modify these variables !!!!
	
	Declare @Backup_Location nvarchar(255)
	DECLARE @DiskBackupFilesID INT
	Declare @count int = 0				-- Checks if a backup exists for the source database name '@DBName'
	declare @message nvarchar(1000) = 'Target Server: '+@@SERVERNAME+CHAR(10)+'-----------------------------------------------------------------------------------------------------------'+CHAR(10)
	DECLARE @ErrLevel TINYINT
	DECLARE @ErrState TINYINT	
	declare @Backup_Path nvarchar(1000), @DatabaseName nvarchar(128)
	DECLARE @SQL NVARCHAR(max)
	DECLARE @Count_FileHeaders_to_read INT
	DECLARE @LoopCount INT
	DECLARE @Chunk_Size INT = 50					-- 50 files estimatedly take long enough to read, for the user to be prompted of the progress

	RAISERROR(@message,0,1) WITH NOWAIT

	IF @Exclude_system_databases = 1
	BEGIN
	IF @Exclude_DBName_Filter <> ''
		SET @Exclude_DBName_Filter+=','
	SET @Exclude_DBName_Filter+='master,msdb,model'
	end	

	IF @Activate_Destination_Database_Containment = 1 AND (SELECT value_in_use FROM sys.configurations WHERE configuration_id = 16393) = 0
		EXEC sp_configure 'contained database authentication', 1; RECONFIGURE WITH OVERRIDE;

	IF @Set_Destination_FILESTREAM_Feature_To > 0 AND (SELECT value_in_use FROM sys.configurations WHERE configuration_id = 1580) <> @Set_Destination_FILESTREAM_Feature_To
		BEGIN TRY
			EXEC sys.sp_configure N'filestream access level', @Set_Destination_FILESTREAM_Feature_To; RECONFIGURE WITH OVERRIDE;
        END TRY
		BEGIN CATCH
			PRINT 'FILESTREAM feature cannot be enabled. Reason:'
			PRINT (ERROR_MESSAGE())
		END CATCH

  
  
	CREATE TABLE #t (FT_ID INT, dbname NVARCHAR(128), ServerName sysname NULL, path NVARCHAR(255))

	---- Begin Body:
  
  
  
  
	IF (@Backup_root_or_path <> '')
	BEGIN  					
		
		IF @USE_SQLAdministrationDB_Database = 1
		BEGIN

			---------- creating SQLAdministrationDB database:

			IF DB_ID('SQLAdministrationDB') is null
				create database SQLAdministrationDB

			---------- creating necessary tables inside SQLAdministrationDB:
			---------- creating DiskBackupFiles table:

			SET @sql =
			'
				use SQLAdministrationDB

				IF OBJECT_ID(''DiskBackupFiles'') IS NULL
					CREATE TABLE DiskBackupFiles 
					( 
						DiskBackupFilesID int identity not null,
						[file] nvarchar(255) NOT NULL,
						[DatabaseName] nvarchar(128),
						[BackupStartDate] datetime,
						[BackupFinishDate] datetime,
						[BackupTypeDescription] nvarchar(128),
						ServerName NVARCHAR(128),
						FileExtension VARCHAR(5),
						/*IsAddedDuringTheLastDiskScan BIT NOT NULL DEFAULT 0,*/
						IsIncluded BIT NOT NULL DEFAULT 1,
						IsDeleted BIT NOT NULL DEFAULT 0,
						CONSTRAINT [PK_DiskBackupFiles_FILE] PRIMARY KEY ([FILE],[IsIncluded]) WITH FILLFACTOR = 70
					)
				ELSE
					UPDATE DiskBackupFiles
					SET IsIncluded = 0
					WHERE IsIncluded = 1 --AND IsDeleted = 0
			'
			EXEC (@sql)

			----------- creating DiskBackupFiles indexes:
			
			SET @SQL =
			'
				use SQLAdministrationDB
				/*
				--IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(''DiskBackupFiles'') AND name = ''IX_DiskBackupFiles_IsAddedDuringTheLastDiskScan_Filtered'')
				--	CREATE INDEX IX_DiskBackupFiles_IsAddedDuringTheLastDiskScan_Filtered		ON SQLAdministrationDB..DiskBackupFiles (IsAddedDuringTheLastDiskScan)
				--	INCLUDE([file], [DatabaseName], [BackupStartDate], [BackupFinishDate], [BackupTypeDescription])
				--	WHERE IsDeleted = 0
				--	WITH(FILLFACTOR = 70)
				*/
				IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(''DiskBackupFiles'') AND name = ''IX_DiskBackupFiles_DatabaseName_Filtered'')
					CREATE INDEX IX_DiskBackupFiles_DatabaseName_Filtered						ON SQLAdministrationDB..DiskBackupFiles (IsIncluded,DatabaseName,BackupFinishDate,BackupStartDate) 
					INCLUDE([file],ServerName,DiskBackupFilesID,BackupTypeDescription)
					WHERE DatabaseName IS NOT NULL
					WITH(FILLFACTOR = 70)

				IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(''DiskBackupFiles'') AND name = ''IX_DiskBackupFiles_DiskBackupFilesID'')
					CREATE INDEX IX_DiskBackupFiles_DiskBackupFilesID							ON SQLAdministrationDB..DiskBackupFiles (DiskBackupFilesID) 
					INCLUDE(BackupFinishDate,[file])
					WITH(FILLFACTOR = 70)

				IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(''DiskBackupFiles'') AND name = ''IX_DiskBackupFiles_IsDeleted_Filtered'')
					CREATE INDEX IX_DiskBackupFiles_IsDeleted_Filtered							ON SQLAdministrationDB..DiskBackupFiles (IsDeleted)
					INCLUDE([file], [DatabaseName], [BackupStartDate], [BackupFinishDate], [BackupTypeDescription])
					/*WHERE IsAddedDuringTheLastDiskScan = 0*/
					WITH(FILLFACTOR = 70)

			'
			EXEC(@SQL)

			----------- creating DiskLogBackupFiles table:

			SET @sql =
			'
				use SQLAdministrationDB

				IF OBJECT_ID(''DiskLogBackupFiles'') IS NULL
					CREATE TABLE DiskLogBackupFiles 
					( 
						DiskLogBackupFilesID int identity not null,
						[file] nvarchar(255) NOT NULL,
						[DatabaseName] nvarchar(128),
						[BackupStartDate] datetime,
						[BackupFinishDate] datetime,
						[BackupTypeDescription] nvarchar(128),
						ServerName NVARCHAR(128),
						FileExtension VARCHAR(5),
						/*IsAddedDuringTheLastDiskScan BIT,*/
						IsIncluded BIT NOT NULL DEFAULT 1,
						/*IsDeleted BIT NOT NULL DEFAULT 0,*/
						CONSTRAINT [PK_DiskLogBackupFiles_FILE] PRIMARY KEY ([FILE],[IsIncluded]) WITH FILLFACTOR = 70
					)
				ELSE
					UPDATE DiskLogBackupFiles
					SET IsIncluded = 0
					WHERE IsIncluded = 1
					--WHERE IsDeleted = 0
			'
			IF @Restore_Log_Backups = 1 OR OBJECT_ID('SQLAdministrationDB..DiskLogBackupFiles') IS NULL
				EXEC (@sql)
			
			----------- creating DiskLogBackupFiles table indexes:
			
			SET @SQL =
			'
				use SQLAdministrationDB
				/*
				--IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(''DiskLogBackupFiles'') AND name = ''IX_DiskLogBackupFiles_IsAddedDuringTheLastDiskScan'')
				--	CREATE INDEX IX_DiskLogBackupFiles_IsAddedDuringTheLastDiskScan					ON SQLAdministrationDB..DiskLogBackupFiles (IsAddedDuringTheLastDiskScan)
				--	INCLUDE([file], [DatabaseName], [BackupStartDate], [BackupFinishDate], [BackupTypeDescription])
				--	WITH(FILLFACTOR = 70)
				*/
				IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(''DiskLogBackupFiles'') AND name = ''IX_DiskLogBackupFiles_DatabaseName_Filtered'')
					CREATE INDEX IX_DiskLogBackupFiles_DatabaseName_Filtered						ON SQLAdministrationDB..DiskLogBackupFiles (DatabaseName,BackupStartDate,BackupFinishDate) 
					INCLUDE([file],IsIncluded,DiskLogBackupFilesID,BackupTypeDescription,FileExtension,ServerName)
					WHERE DatabaseName IS NOT NULL
					WITH(FILLFACTOR = 70)
				/*
				--IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(''DiskLogBackupFiles'') AND name = ''IX_DiskLogBackupFiles_DatabaseName_isIncluded'')
				--	CREATE INDEX IX_DiskLogBackupFiles_DatabaseName_isIncluded						ON SQLAdministrationDB..DiskLogBackupFiles (DatabaseName,isIncluded,BackupStartDate,BackupFinishDate) 
				--	INCLUDE([file])
				--	WITH(FILLFACTOR = 70)
				*/
				IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(''DiskLogBackupFiles'') AND name = ''IX_DiskLogBackupFiles_DiskLogBackupFilesID_DatabaseName'')
					CREATE INDEX IX_DiskLogBackupFiles_DiskLogBackupFilesID_DatabaseName			ON SQLAdministrationDB..DiskLogBackupFiles (DiskLogBackupFilesID,DatabaseName) 					
					WITH(FILLFACTOR = 70)

			'
			EXEC(@SQL)

			----------- creating RestoreHistory table:

			SET @sql =
			'
				use SQLAdministrationDB

				IF OBJECT_ID(''RestoreHistory'') IS NULL
					CREATE TABLE RestoreHistory 
					( 
						RestoreHistoryID int identity not null,
						DiskBackupFilesID INT NOT NULL,
						LastRestoredLogBackupID INT NULL,
						RestoreStartDate DATETIME,
						RestoreFinishDate DATETIME,
						[Duration (DD:HH:MM:SS)] varchar(15),
						dop int,
						DestinationDatabaseName sysname,
						UserName sysname,
						Replace BIT,
						Recovery BIT,
						StopAt DATETIME2,
						TargetRecoveryModel VARCHAR(17) NOT NULL DEFAULT ''No Data'',
						TargetUpdateability VARCHAR(10) NOT NULL DEFAULT ''No Data'',
						isBackupFileDeleteRequested bit NOT NULL DEFAULT 0,
						ShrinkDatabase_policy SMALLINT NOT NULL DEFAULT -2,
						ShrinkLogFile_policy SMALLINT NOT NULL DEFAULT -2,
						RebuildLogFile_policy VARCHAR(24) NOT NULL DEFAULT '''',
						GrantAllPermissions_policy SMALLINT NOT NULL DEFAULT -2,

						CONSTRAINT [PK_RestoreHistory_RestoreHistoryID] PRIMARY KEY (RestoreHistoryID)
					)
				
			'
			EXEC (@sql)

		END



		--drop table if exists #DirContents
		create table #DirContents 
		(
			DiskBackupFilesID INT IDENTITY NOT NULL,
			[file] nvarchar(255),
			DatabaseName nvarchar(128),
			BackupStartDate datetime,
			BackupFinishDate datetime,
			BackupTypeDescription nvarchar(128),
			ServerName NVARCHAR(128),
			FileExtension VARCHAR(5),
			--IsAddedDuringTheLastDiskScan AS (CONVERT(BIT,1)),
			IsIncluded BIT NOT NULL DEFAULT 0,
			IsDeleted AS (CONVERT(BIT,0))
		)
		
		------------ Begin file operations: (Backups) ----------------------------------------------------------------

		BEGIN try
			IF (SELECT file_exists+file_is_a_directory FROM sys.dm_os_file_exists(@Backup_root_or_path)) = 0
			BEGIN
			 
				set @message = 'Fatal filesystem error:'+CHAR(10)+'The file or folder "'+@Backup_root_or_path+'", you specified for @Backup_root_or_path does not exist, or you do not have permission.'
    			raiserror(@message, 16, 1)				
				RETURN 1
			END

			IF (SELECT file_is_a_directory FROM sys.dm_os_file_exists(@Backup_root_or_path)) = 1
			BEGIN
				/****** Deprecated cmdshell but faster approach:
				DECLARE @cmdshellInput NVARCHAR(500) = 
				CASE @IncludeSubdirectories 
					WHEN 1 THEN --'powershell "GET-ChildItem -Recurse -File \"' + @Backup_root_or_path + '\*.bak\" | %{ $_.FullName }"'	
								'dir /B /S /A-D "' + @Backup_root_or_path + '\*.bak"' 
					ELSE		--'powershell "GET-ChildItem -File \"' + @Backup_root_or_path + '\*.bak\" | %{ $_.FullName }"'					
								'@echo off & for %a in ('+@Backup_root_or_path+'\*.bak) do echo %~fa' 
					END
				PRINT @cmdshellInput


				EXECUTE sp_configure 'show advanced options', 1; RECONFIGURE; EXECUTE sp_configure 'xp_cmdshell', 1; RECONFIGURE;

				insert into #DirContents ([file])
  				EXEC master..xp_cmdshell @cmdshellInput								
				*/
				--EXECUTE sp_configure 'xp_cmdshell', 0; RECONFIGURE; EXECUTE sp_configure 'show advanced options', 0; RECONFIGURE;
				insert into #DirContents ([file])
				SELECT full_filesystem_path FROM sys.dm_os_enumerate_filesystem(@Backup_root_or_path,'*.bak')

				IF @BackupFileName_RegexFilter <> ''
					DELETE FROM #DirContents WHERE PATINDEX(@BackupFileName_RegexFilter,[file]) = 0

				PRINT ''
				raiserror('Warning! The files/folders that the SQL Server service account does not have permission to, will be excluded.',0,1) with nowait

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
				ALTER TABLE #DirContents ADD CONSTRAINT PK_DirContents_FILE PRIMARY KEY ([file],[IsIncluded])
				CREATE INDEX IX_DirContents_DatabaseName ON #DirContents (DatabaseName,BackupFinishDate,BackupStartDate) INCLUDE(ServerName,[file],IsIncluded,DiskBackupFilesID,BackupTypeDescription)
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
				UPDATE a
				SET IsDeleted = 1,
					IsIncluded = 0
				FROM
				(
					SELECT * FROM SQLAdministrationDB..DiskBackupFiles dbf
					WHERE dbf.[file] NOT IN (SELECT [file] FROM #DirContents)
				
				) a
			
				/*UPDATE SQLAdministrationDB..DiskBackupFiles SET IsAddedDuringTheLastDiskScan = 0 WHERE IsAddedDuringTheLastDiskScan = 1*/
			
				INSERT SQLAdministrationDB..DiskBackupFiles
				SELECT 
				    dc.[file],
					dc.DatabaseName,
					dc.BackupStartDate,
					dc.BackupFinishDate,
					dc.BackupTypeDescription,
					dc.ServerName,
					dc.FileExtension,
					/*dc.IsAddedDuringTheLastDiskScan,*/
					dc.IsIncluded,
					dc.IsDeleted
				FROM #DirContents dc LEFT JOIN SQLAdministrationDB..DiskBackupFiles dbf
				ON dbf.[file] = dc.[file]
				WHERE dbf.[file] IS NULL
			'
			EXEC(@SQL)

        END

		CREATE TABLE #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
		(
			DatabaseName nvarchar(128),
			LastLSN decimal(25,0),
			BackupStartDate datetime,
			BackupFinishDate datetime,
			BackupTypeDescription nvarchar(128),
			ServerName NVARCHAR(128)
		)

		SET @SQL = 
		'
			SELECT @Count_FileHeaders_to_read = count(*) from ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + '
			WHERE DatabaseName IS NULL
		'
		EXEC sys.sp_executesql @SQL, N'@Count_FileHeaders_to_read int out', @Count_FileHeaders_to_read OUT


		CREATE TABLE #BackupNamePartIndexes (id INT IDENTITY PRIMARY KEY NOT NULL, BackupNamePartIndex TINYINT)
		IF @BackupFileName_naming_convention <> '' AND @Count_FileHeaders_to_read > (2*@Chunk_Size)
		BEGIN
			DECLARE @Convention NVARCHAR(128),
					@Separator	NVARCHAR(5),
					@Transform	NVARCHAR(2000),					
					@HasExt		BIT


			DECLARE FileScannerbyConvention CURSOR FOR
				select NamingConvention, Separator, Transform from openjson(@BackupFileName_naming_convention) with (BackupType nchar(3),NamingConvention nvarchar(128),Separator nvarchar(5), Transform nvarchar(2000))
				WHERE BackupType IN ('FUL','ALL')
			OPEN FileScannerbyConvention
				FETCH NEXT FROM FileScannerbyConvention INTO @Convention, @Separator, @Transform
				WHILE @@FETCH_STATUS = 0
				BEGIN									

					INSERT #BackupNamePartIndexes
					(			    
						BackupNamePartIndex
					)		
					SELECT
						IIF(dt.BeforeToken = '',NULL,(LEN(dt.BeforeToken)-LEN(REPLACE(dt.BeforeToken,@Separator,''))+1))
					FROM
					(
						SELECT LEFT(@Convention,CHARINDEX(dt.value,@Convention)) BeforeToken
						FROM
						(
							SELECT 'DBName' value
							UNION ALL
							SELECT 'BackupType'
							UNION ALL
							SELECT 'ServerName'
							UNION ALL
							SELECT 'TIMESTAMP'							
						) dt
					) dt

					SET @HasExt = IIF(CHARINDEX('.ext',@Convention)<> 0, 1, 0)

					SET @SQL =
					'
						DECLARE @DBIndex				TINYINT	= (SELECT BackupNamePartIndex FROM #BackupNamePartIndexes WHERE id = 1),
								@BackupTypeIndex		TINYINT = (SELECT BackupNamePartIndex FROM #BackupNamePartIndexes WHERE id = 2),
								@ServerNameIndex		TINYINT = (SELECT BackupNamePartIndex FROM #BackupNamePartIndexes WHERE id = 3),
								@BackupStartDateIndex	TINYINT = (SELECT BackupNamePartIndex FROM #BackupNamePartIndexes WHERE id = 4)
						
				
						UPDATE b
						SET
							b.DatabaseName			= b.DBName,
							b.BackupTypeDescription	= b.BTDescription,
							b.ServerName			= b.SerName,
							b.BackupStartDate		= b.BFDate
							'+IIF(@HasExt = 1,',b.FileExtension	= b.Ext','') +'
						FROM
						(
							SELECT						
									a.DatabaseName,
									a.BackupTypeDescription,
									a.BackupStartDate,
									a.ServerName,
									a.FileExtension,
									a.FileName,
									dbo.ufn_StringTokenizer(a.FileName,@BackupFileName_naming_convention_separator,@DBIndex) DBName,
									dbo.ufn_StringTokenizer(a.FileName,@BackupFileName_naming_convention_separator,@BackupTypeIndex) BTDescription,
									dbo.ufn_StringTokenizer(a.FileName,@BackupFileName_naming_convention_separator,@ServerNameIndex) SerName,
									'+REPLACE(@Transform,'TIMESTAMP','dbo.ufn_StringTokenizer(a.FileName,@BackupFileName_naming_convention_separator,@BackupStartDateIndex)')+' BFDate					
									'+IIF(@HasExt = 1,',a.Ext','') +'
							
							FROM
							(SELECT DatabaseName, BackupTypeDescription, BackupStartDate, ServerName, FileExtension, '+IIF(@HasExt = 1, 'LEFT(RIGHT([file],CHARINDEX(''\'',REVERSE([file]))-1),LEN(RIGHT([file],CHARINDEX(''\'',REVERSE([file]))-1))-CHARINDEX(''.'',REVERSE(RIGHT([file],CHARINDEX(''\'',REVERSE([file]))-1))))','RIGHT([file],CHARINDEX(''\'',REVERSE([file]))-1)') + ' FileName ' + IIF(@HasExt = 1,',RIGHT([file],CHARINDEX(''.'',REVERSE([file]))-1) Ext','') + '  FROM ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + '
							 WHERE DatabaseName IS NULL) a
						 ) b
						 WHERE dbo.ufn_CheckNameValidation(b.FileName'+IIF(@HasExt = 1,'+''.''+b.Ext ','')+','''+@Convention+''', '''+@Separator+''', b.BFDate) = 1
				
						/*
						--select
						--		a.FileName,
						--		dbo.ufn_StringTokenizer(a.FileName,@BackupFileName_naming_convention_separator,@DBIndex),
						--		dbo.ufn_StringTokenizer(a.FileName,@BackupFileName_naming_convention_separator,@BackupTypeIndex),
						--		dbo.ufn_StringTokenizer(a.FileName,@BackupFileName_naming_convention_separator,@ServerNameIndex),
						--		'+REPLACE(@Transform,'TIMESTAMP','dbo.ufn_StringTokenizer(a.FileName,@BackupFileName_naming_convention_separator,@BackupStartDateIndex)')+'
						--		'+IIF(@HasExt = 1,', a.Ext','') +'
						--FROM
						--(SELECT DatabaseName, BackupTypeDescription, BackupStartDate, ServerName, FileExtension, '+IIF(@HasExt = 1, 'LEFT(RIGHT([file],CHARINDEX(''\'',REVERSE([file]))-1),LEN(RIGHT([file],CHARINDEX(''\'',REVERSE([file]))-1))-CHARINDEX(''.'',REVERSE(RIGHT([file],CHARINDEX(''\'',REVERSE([file]))-1))))','RIGHT([file],CHARINDEX(''\'',REVERSE([file]))-1)') + ' FileName ' + IIF(@HasExt = 1,',RIGHT([file],CHARINDEX(''.'',REVERSE([file]))-1) Ext','') + '  FROM ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + '
						-- WHERE IsAddedDuringTheLastDiskScan = 1) a
						-- WHERE dbo.ufn_CheckNameValidation(a.FileName'+IIF(@HasExt = 1,'+''.''+a.Ext ','')+','''+@Convention+''', '''+@Separator+''') = 1
						*/					
					'			
					
					BEGIN TRY
						EXEC sys.sp_executesql @SQL, N'@BackupFileName_naming_convention_separator NVARCHAR(5)', @Separator
					END TRY
					BEGIN CATCH
						PRINT ERROR_MESSAGE()
						RAISERROR('Warning!!! Something is wrong with some of your backup file names, the name convention you have introduced to this stored procedure, its separator, or the formula you have given for DATETIME transform.',0,1) WITH NOWAIT
					END CATCH
					TRUNCATE TABLE #BackupNamePartIndexes

					FETCH NEXT FROM FileScannerbyConvention INTO @Convention, @Separator, @Transform
				END
			CLOSE FileScannerbyConvention
			DEALLOCATE FileScannerbyConvention

        END

		SET @SQL = 
		'
			SELECT @Count_FileHeaders_to_read = count(*) from ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + '
			WHERE DatabaseName IS NULL
		'
		EXEC sys.sp_executesql @SQL, N'@Count_FileHeaders_to_read int out', @Count_FileHeaders_to_read OUT

		IF @Skip_Files_Not_Matching_Naming_Convention = 0 AND @Count_FileHeaders_to_read > 0
		BEGIN 
			

			SET @message = CHAR(10)+'Reading headers of database backup files for '+CONVERT(VARCHAR(10),@Count_FileHeaders_to_read)+' files (lower speed but more accurate mode):'+CHAR(10)+'0 percent of files processed.'
            RAISERROR(@message,0,1) WITH NOWAIT

			
			SET @LoopCount = CEILING(@Count_FileHeaders_to_read*1.0/@Chunk_Size)	
			SET @count = @LoopCount
			DECLARE @Percentage INT

			WHILE @LoopCount > 0
			BEGIN 
				
				SET @SQL =
				'
					declare @Backup_Path nvarchar(1000), @DatabaseName nvarchar(128), @BackupFinishDate datetime, @BackupTypeDescription nvarchar(128), @ServerName nvarchar(128)

					declare BackupDetails cursor FOR
						SELECT'+
						' TOP '+CONVERT(VARCHAR(10),@Chunk_Size)+
						' [file], DatabaseName , BackupFinishDate, BackupTypeDescription
						from ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + '
						WHERE DatabaseName IS NULL
					open BackupDetails
			
						fetch next from BackupDetails into @Backup_Path, @DatabaseName , @BackupFinishDate, @BackupTypeDescription								
						while @@FETCH_STATUS = 0
						begin
			
					/*---------------------------------------------------------------------------------------------------------*/

							execute usp_BackupDetails @Backup_Path

					/*---------------------------------------------------------------------------------------------------------*/
							update ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + ' set DatabaseName = ISNULL((select top 1 DatabaseName from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9),concat(''UnreadableBackupFile_'', LEFT(CONVERT(NVARCHAR(50),NEWID()),12))) WHERE CURRENT OF BackupDetails
							update ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + ' set BackupStartDate = (select top 1 BackupStartDate from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails							
							update ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + ' set BackupFinishDate = (select top 1 BackupFinishDate from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails
							update ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + ' set BackupTypeDescription = (select top 1 BackupTypeDescription from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails
							update ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + ' set ServerName = (select top 1 ServerName from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails
										
                
							TRUNCATE TABLE #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
							FETCH NEXT FROM BackupDetails INTO @Backup_Path, @DatabaseName , @BackupFinishDate, @BackupTypeDescription				
						END 
					CLOSE BackupDetails
					DEALLOCATE BackupDetails
				'
				EXEC(@sql)
				
				SET @Percentage = (@Count-@LoopCount+1)*@Chunk_Size*100/@Count_FileHeaders_to_read
				SET @message = CONVERT(VARCHAR(3),IIF(@Percentage<=100, @Percentage,100))+' percent of files processed.'
				RAISERROR(@message,0,1) WITH NOWAIT

				SET @LoopCount-=1
			END

			SET @message = 'Reading of headers completed.'+CHAR(10)+'-----------------------------------------------------------------------------------------------------------'+CHAR(10)
			RAISERROR(@message,0,1) WITH NOWAIT

		END

		----- Applying Filters: @Exclude_DBName_Filter, and @Include_DBName_Filter filters-----------------------------------------
		BEGIN TRY

			---- Including @Include_DBName_Filter databases and excluding others ---------------------------------------
			IF @Include_DBName_Filter <> ''
			BEGIN
				SET @SQL =
				'
					UPDATE FT
					SET FT.IsIncluded = 1
					FROM
					(SELECT * FROM ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + ' WHERE IsIncluded = 0) FT				
					JOIN (SELECT TRIM(value) value FROM STRING_SPLIT('''+@Include_DBName_Filter+''','','')) ss
					ON FT.DatabaseName LIKE ss.value { ESCAPE ''\'' }
					
					OPTION (RECOMPILE)
				'
				EXEC(@SQL)
			END

			------------------------------------------------------------------------------------------------------------
			---- Filtering out @Exclude_DBName_Filter databases --------------------------------------------------------
			IF @Exclude_DBName_Filter <> ''
			BEGIN
				SET @SQL =
				'
					UPDATE FT
					SET FT.IsIncluded = 0
					FROM 
					(SELECT * FROM ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + ' WHERE IsIncluded = 1) FT				
					JOIN (SELECT TRIM(value) value FROM STRING_SPLIT('''+@Exclude_DBName_Filter+''','','')) ss
					ON FT.DatabaseName LIKE ss.value { ESCAPE ''\'' }
					OPTION (RECOMPILE)
				'
				EXEC(@sql)
			END

			-- Applying time filter:
			SET @SQL =
			'
				IF @BackupFinishDate_StartDATETIME <> ''1900.01.01 00:00:00''
					UPDATE ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + ' 
					SET IsIncluded = 0
					WHERE IsIncluded = 1 AND IsDeleted = 0 AND COALESCE(BackupFinishDate, BackupStartDate) < @BackupFinishDate_StartDATETIME

				IF @BackupFinishDate_EndDATETIME <> ''9999.12.31 23:59:59''
					UPDATE ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + ' 
					SET IsIncluded = 0
					WHERE IsIncluded = 1 AND IsDeleted = 0 AND COALESCE(BackupFinishDate, BackupStartDate) > @BackupFinishDate_EndDATETIME

			'

			
			EXEC sp_executesql @SQL, N'@BackupFinishDate_StartDATETIME DATETIME, @BackupFinishDate_EndDATETIME DATETIME', @BackupFinishDate_StartDATETIME, @BackupFinishDate_EndDATETIME

			------------------------------------------------------------------------------------------------------------
		END TRY		
        BEGIN CATCH
			SET @message = ERROR_MESSAGE()
			PRINT @message
			RAISERROR('Probably STRING_SPLIT function was not recognized by the tsql interpreter. For that your database compatibility level must be 130 or higher.',16,1)
			RETURN 1
        END CATCH
        ----- End applying filters--------------------------------------------------------------------------------------
		-- Finding latest records within criteria:		
		SET @SQL =
		'
			;WITH T
			AS
			(
				SELECT  
					ROW_NUMBER() OVER (PARTITION BY DatabaseName ORDER BY BackupStartDate DESC) AS [Row] ,
					DiskBackupFilesID,
					DatabaseName AS database_name,
					[file],
					ServerName
				FROM (SELECT DatabaseName, ServerName, BackupFinishDate, BackupStartDate, DiskBackupFilesID, [file], BackupTypeDescription FROM ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskBackupFiles', '#DirContents') + ' WHERE IsIncluded = 1 AND IsDeleted = 0 AND DatabaseName IS NOT NULL) FT
				WHERE [BackupTypeDescription] IN (''Database'',''Partial'', ''FULL'') OR [BackupTypeDescription] IS NULL
			)
			INSERT INTO #t
			SELECT 
				DiskBackupFilesID,
				T.database_name dbname,
				ServerName,
				[file] [path]		
			FROM T 
			WHERE T.[Row] = 1
			ORDER BY 1
		'
		EXEC (@SQL)
		
		------------ End file operations (Backups) -------------------------------------------------------------------
		DECLARE @Number_of_Databases_to_Restore VARCHAR(4) = CONVERT(VARCHAR(4),(select count(*) from #t))
  		IF @Number_of_Databases_to_Restore=0
		BEGIN
			SET @message = 'Fatal error: No backups exist within the folder you specified for your backup root or its subdirectories with the given criteria, or you do not have permission.'+CHAR(10)+'Hint: check also your naming convention if you are using it.'
  			RAISERROR(@message,16,1)
			RETURN 1
		END
		----- Show elapsed time:
		SET @message = 'Elapsed time: ' + dbo.ufn_ElapsedTime(@OperationStartTime)
		RAISERROR(@message,0,1) WITH NOWAIT
	
		DECLARE @Databases NVARCHAR(4000)
		PRINT(CHAR(10))
		--RAISERROR('***Begining Operation:',0,1) WITH NOWAIT
		PRINT('DATABASES TO RESTORE: ('+@Number_of_Databases_to_Restore+' Database' + IIF(@Number_of_Databases_to_Restore>1,'s','') + ')')
		PRINT('---------------------')		
		IF @Destination_DatabaseName<>'' AND @Number_of_Databases_to_Restore = 1
		begin
			
			UPDATE #t SET dbname = @Destination_DatabaseName
			SELECT @Databases =				(
												dbname + REPLICATE(CHAR(9),2) + '-->' + REPLICATE(CHAR(9),2) +
												@Destination_DatabaseName + IIF(EXISTS (SELECT 1 FROM sys.databases WHERE name=@Destination_DatabaseName),' (Replace)',' (New)') 												
											) 
										FROM #t
										
		END
		ELSE
		BEGIN
			DECLARE @Len INT =(SELECT MAX(LEN(dbname)) FROM #t)
			SELECT @Databases = STRING_AGG	(
												CONVERT	(NVARCHAR(MAX),
															dbname + REPLICATE(CHAR(9),CEILING((@Len-LEN(dbname))/4.0)+1) + '-->' + REPLICATE(CHAR(9),2) +
															@Destination_Database_Name_prefix +
															dbname +
															@Destination_Database_Name_suffix + IIF(DB_ID(@Destination_Database_Name_prefix+dbname+@Destination_Database_Name_suffix) IS NULL,' (New)',' (Replace)') 																													
														)
												,CHAR(10)
											) 
										FROM #t
		END
	
		EXEC dbo.usp_PrintLong @Databases
		PRINT('')
		PRINT('')




		------------ Begin file operations: (Log Backups) ------------------------------------------------------------
		IF @Restore_Log_Backups = 1
		BEGIN        
			BEGIN TRY
				create table #DirContentsLog 
				(
					DiskLogBackupFilesID INT IDENTITY NOT NULL,
					[file] nvarchar(255),
					DatabaseName nvarchar(128),
					BackupStartDate datetime,
					BackupFinishDate datetime,
					BackupTypeDescription nvarchar(128),
					ServerName NVARCHAR(128),
					FileExtension VARCHAR(5),
					--IsAddedDuringTheLastDiskScan AS (CONVERT(BIT,1)),
					IsIncluded BIT NOT NULL DEFAULT 1
					--,IsDeleted AS (CONVERT(BIT,0))
				)

				DECLARE @ExitCode TABLE (ExitCode INT)

				IF (SELECT file_exists+file_is_a_directory FROM sys.dm_os_file_exists(@LogBackup_root_or_path)) = 0
				BEGIN
			 
					set @message = 'Fatal filesystem error:'+CHAR(10)+'The file or folder "'+@LogBackup_root_or_path+'", you specified for @LogBackup_root_or_path does not exist, or you do not have permission.'
					INSERT @ExitCode SELECT 1
    				raiserror(@message, 16, 1)				
				END

				------------ Taking log backup for live restore operation: ---------------------------------------------------
				IF @Live_Restore_LogBackup_Temporary_Location <> ''
				BEGIN
					IF (SELECT file_is_a_directory FROM sys.dm_os_file_exists(@Live_Restore_LogBackup_Temporary_Location)) = 0
					BEGIN
						
						
						INSERT @ExitCode SELECT 1
						RAISERROR('The directory specified for @Live_Restore_LogBackup_Temporary_Location is either invalid or inaccessible.',16,1)
					END
					PRINT CHAR(10)+'--------------------------- for live restore operation ----------------------------------------------------'
					DECLARE @FT_ID INT, @dbname NVARCHAR(128), @ServerName sysname, @path NVARCHAR(255), @rpc BIT, @TimeStampStart DATETIME, @TimeStampEnd DATETIME, @LinkedServerName sysname, @remote_transaction_promotion BIT
					DECLARE ServerNameFinder CURSOR FOR
						SELECT FT_ID,dbname,ServerName,[path] FROM #t
					OPEN ServerNameFinder
						FETCH NEXT FROM ServerNameFinder INTO @FT_ID, @dbname, @ServerName,@path
						WHILE @@FETCH_STATUS = 0
						BEGIN
							IF @ServerName IS NULL
							BEGIN                    
								EXEC dbo.usp_BackupDetails @Backup_Path = @path
								UPDATE #t SET ServerName = (select top 1 ServerName from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF ServerNameFinder
								SET @ServerName = (select top 1 ServerName from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9)
								TRUNCATE TABLE #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
							END
							SET @path = @Live_Restore_LogBackup_Temporary_Location+'\'+@dbname+'_'+FORMAT(GETDATE(),'yyyyMMdd_HHmmss')+'_temp_log_backup.trn'
							SET @message = 'The linked-server '+@ServerName+' is not defined, and the @Live_Restore_LogBackup_Temporary_Location option was specified. Define it with the appropriate mappings and try again.'+CHAR(10)+'Note that the linked-server''s name must be something like SERVERNAME\INSTANCE,PORT and not IP address.'
					
							SELECT @LinkedServerName = name, @rpc = is_rpc_out_enabled, @remote_transaction_promotion = is_remote_proc_transaction_promotion_enabled FROM sys.servers WHERE name LIKE @ServerName+'%' AND SUBSTRING(name,LEN(@ServerName)+1,1) IN (',','')
							SET @SQL = 'EXEC(''IF (SELECT recovery_model_desc FROM sys.databases WHERE name = '''''+@dbname+''''') <> ''''SIMPLE'''' BEGIN BACKUP LOG '+QUOTENAME(@dbname)+' TO DISK=N'''''+@path+''''' WITH COPY_ONLY, COMPRESSION, INIT, STATS=40; SELECT @@ERROR END; ELSE BEGIN SELECT -20; /*PRINT ''''Warning!!! The recovery model of the database is simple, thus '''''''''+@dbname+''''''''' database cannot be restored to its latest state using a log backup.''''*/ END '') AT '+QUOTENAME(@LinkedServerName)
							IF @LinkedServerName IS NULL
							BEGIN
								INSERT @ExitCode SELECT 1
								RAISERROR(@message,16,1)
							END

							SET @message = 'Your linked-server exists, but RPC is not enabled for it, which is required.'
							IF @rpc = 0
							BEGIN
								INSERT @ExitCode SELECT 1
								RAISERROR(@message,16,1)
							END
							
							SET @message = 'Your linked-server exists, but ''Remote Proc Transaction Promotion'' option is enabled for it, which needs to be turned off.'
							IF @remote_transaction_promotion = 1
							BEGIN
								INSERT @ExitCode SELECT 1
								RAISERROR(@message,16,1)
							END

							SET @message = 'Taking tail of the log backup for the database '''+@dbname+''' for live restore operation(COPY_ONLY,RECOVERY).'
							
							--IF @Generate_Statements_Only = 0
							RAISERROR(@message,0,1) WITH NOWAIT
							SET @TimeStampStart = GETDATE()
							
							--IF @Generate_Statements_Only = 0
							INSERT @ExitCode							
							EXEC(@SQL)
							SET @TimeStampEnd = GETDATE()

							--IF @Generate_Statements_Only = 0
							IF (SELECT ExitCode FROM @ExitCode) = 0
							BEGIN
								SET @message = 'Log backup taken remotely successfully.'+CHAR(10)+'------------------'
								RAISERROR(@message,0,1) WITH NOWAIT
								DELETE FROM @ExitCode
							END							
							ELSE
							BEGIN								
								SET @message = 'Error! The recovery model of the database is simple on the source server, thus '''+@dbname+''' database cannot be restored to its latest state using a log backup. The entire operation will abort.'
								raiserror(@message,16,1)
							END
							
							IF @Live_Restore_LogBackup_Temporary_Location NOT LIKE @LogBackup_root_or_path+'%'
								INSERT #DirContentsLog								
								(
									[file],
									DatabaseName,
									BackupStartDate,
									BackupFinishDate,
									BackupTypeDescription,
									ServerName,
									FileExtension,
									IsIncluded
								)
								VALUES
								(   @path,    -- file - nvarchar(255)
									@dbname,   -- DatabaseName - nvarchar(128)
									@TimeStampStart,   -- BackupStartDate - datetime
									@TimeStampEnd,   -- BackupFinishDate - datetime
									'LOG',   -- BackupTypeDescription - nvarchar(128)
									@ServerName,   -- ServerName - nvarchar(128)
									'TRN',   -- FileExtension - varchar(5)
									1 -- IsIncluded - bit
								)
							FETCH NEXT FROM ServerNameFinder INTO @FT_ID, @dbname, @ServerName,@path
						END
					CLOSE ServerNameFinder
					DEALLOCATE ServerNameFinder

					SELECT * INTO #TempTailLogFiles FROM #DirContentsLog	
					
					PRINT '--------------------------- end for live restore operation ------------------------------------------------'+CHAR(10)
				END
			END TRY
			BEGIN CATCH

				SET @message = ERROR_MESSAGE()
				SET @ErrLevel = ERROR_SEVERITY()
				SET @ErrState = ERROR_STATE()
				RAISERROR(@message,@ErrLevel,@ErrState)
				IF NOT EXISTS (SELECT 1 FROM @ExitCode) 
					RETURN 1
				RETURN (SELECT ExitCode FROM @ExitCode)

			END CATCH

				------------ End Taking log backup for live restore operation: ---------------------------------------------------


				IF (SELECT file_is_a_directory FROM sys.dm_os_file_exists(@LogBackup_root_or_path)) = 1
				BEGIN
					/********* Deprecated but faster cmdshell approach 
					SET @cmdshellInput = 
					CASE @IncludeSubdirectories 
						WHEN 1 THEN --'powershell "GET-ChildItem -Recurse -File \"' + @LogBackup_root_or_path + '\*.bak\" | %{ $_.FullName }"'	
									'dir /B /S /A-D "' + @LogBackup_root_or_path + '\*.trn"' 
						ELSE		--'powershell "GET-ChildItem -File \"' + @LogBackup_root_or_path + '\*.bak\" | %{ $_.FullName }"'					
									'@echo off & for %a in ('+@LogBackup_root_or_path+'\*.trn) do echo %~fa' 
						END
					PRINT @cmdshellInput
					

					--EXECUTE sp_configure 'show advanced options', 1; RECONFIGURE; EXECUTE sp_configure 'xp_cmdshell', 1; RECONFIGURE;


					insert into #DirContentsLog ([file])
  					EXEC master..xp_cmdshell @cmdshellInput
										

					EXECUTE sp_configure 'xp_cmdshell', 0; RECONFIGURE; EXECUTE sp_configure 'show advanced options', 0; RECONFIGURE;
					*/
					INSERT into #DirContentsLog ([file])
					SELECT full_filesystem_path FROM sys.dm_os_enumerate_filesystem(@Backup_root_or_path,'*.trn')


					IF @LogBackupFileName_RegexFilter <> ''
						DELETE FROM #DirContentsLog WHERE PATINDEX(@BackupFileName_RegexFilter,RIGHT([file],CHARINDEX('\',REVERSE([file]))-1)) = 0

  					if (CHARINDEX('\',(select TOP 1 [file] from #DirContentsLog)) = 0 )		  
  					BEGIN				
							set @message = 'Fatal error: "'+ (select TOP 1 [file] from #DirContentsLog) +'"'
    						raiserror(@message, 16, 1)
							set @message = 'No backups exist within that folder or its subdirectories, or you do not have permission.'
    						raiserror(@message, 16, 1)				
							RETURN 1
    				END
					DELETE FROM #DirContentsLog WHERE [file] IS NULL OR [file] = ''
					SET @SQL = 'ALTER TABLE #DirContentsLog ALTER COLUMN [file] nvarchar(255) NOT NULL'
					EXEC (@sql)
					ALTER TABLE #DirContentsLog ADD CONSTRAINT PK_DirContentsLog_FILE PRIMARY KEY ([file],[IsIncluded])
					CREATE INDEX IX_DirContentsLog_DatabaseName ON #DirContentsLog (DatabaseName,BackupStartDate,BackupFinishDate) INCLUDE([file],IsIncluded,DiskLogBackupFilesID,BackupTypeDescription)
				END
				
			-- This script does not keep history for DiskLogBackupFiles table.

			IF @USE_SQLAdministrationDB_Database = 1
			BEGIN
				SET @SQL =
				'
					DELETE a 
					FROM
					(
						SELECT * FROM SQLAdministrationDB..DiskLogBackupFiles dbf
						WHERE dbf.[file] NOT IN (SELECT [file] FROM #DirContentsLog)
				
					) a
			
					/*UPDATE SQLAdministrationDB..DiskLogBackupFiles SET IsAddedDuringTheLastDiskScan = 0 WHERE IsAddedDuringTheLastDiskScan = 1*/
			
					INSERT SQLAdministrationDB..DiskLogBackupFiles
					SELECT 
						dc.[file],
						dc.DatabaseName,
						dc.BackupStartDate,
						dc.BackupFinishDate,
						dc.BackupTypeDescription,
						dc.ServerName,
						dc.FileExtension,
						/*dc.IsAddedDuringTheLastDiskScan,*/
						dc.IsIncluded
						/*,dc.IsDeleted*/
					FROM #DirContentsLog dc LEFT JOIN SQLAdministrationDB..DiskLogBackupFiles dbf
					ON dbf.[file] = dc.[file]
					WHERE dbf.[file] IS NULL
				'
				EXEC(@SQL)

			END


			SET @SQL = 
			'
				SELECT @Count_FileHeaders_to_read = count(*) from ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskLogBackupFiles', '#DirContentsLog') + '
				WHERE DatabaseName IS NULL
			'
			EXEC sys.sp_executesql @SQL, N'@Count_FileHeaders_to_read int out', @Count_FileHeaders_to_read OUT
			
			IF @BackupFileName_naming_convention <> '' AND @Count_FileHeaders_to_read > (2*@Chunk_Size)
			BEGIN
				
				DECLARE FileScannerByConvention CURSOR FOR
					select NamingConvention, Separator, Transform from openjson(@BackupFileName_naming_convention) with (BackupType nchar(4),NamingConvention nvarchar(128),Separator nvarchar(5), Transform nvarchar(2000))
					WHERE BackupType IN ('LOG','ALL')
				OPEN FileScannerbyConvention
					FETCH NEXT FROM FileScannerbyConvention INTO @Convention, @Separator, @Transform
					WHILE @@FETCH_STATUS = 0
					BEGIN


						INSERT #BackupNamePartIndexes
						(			    
							BackupNamePartIndex
						)		
						SELECT
							IIF(dt.BeforeToken = '',NULL,(LEN(dt.BeforeToken)-LEN(REPLACE(dt.BeforeToken,@Separator,''))+1))
						FROM
						(
							SELECT LEFT(@Convention,CHARINDEX(dt.value,@Convention)) BeforeToken
							FROM
							(
								SELECT 'DBName' value
								UNION ALL
								SELECT 'BackupType'
								UNION ALL
								SELECT 'ServerName'
								UNION ALL
								SELECT 'TIMESTAMP'							
							) dt
						) dt

						SET @HasExt = IIF(CHARINDEX('.ext',@Convention)<> 0, 1, 0)
						SET @SQL =
						'
							DECLARE @DBIndex				TINYINT	= (SELECT BackupNamePartIndex FROM #BackupNamePartIndexes WHERE id = 1),
									@BackupTypeIndex		TINYINT = (SELECT BackupNamePartIndex FROM #BackupNamePartIndexes WHERE id = 2),
									@ServerNameIndex		TINYINT = (SELECT BackupNamePartIndex FROM #BackupNamePartIndexes WHERE id = 3),
									@BackupStartDateIndex	TINYINT = (SELECT BackupNamePartIndex FROM #BackupNamePartIndexes WHERE id = 4)
							
				
							UPDATE b
							SET
								b.DatabaseName			= b.DBName,
								b.BackupTypeDescription	= b.BTDescription,
								b.ServerName			= b.SerName,
								b.BackupStartDate		= b.BFDate
								'+IIF(@HasExt = 1,',b.FileExtension	= b.Ext','') +'
							FROM
							(
								SELECT						
										a.DatabaseName,
										a.BackupTypeDescription,
										a.BackupStartDate,
										a.ServerName,
										a.FileExtension,
										a.FileName,
										dbo.ufn_StringTokenizer(a.FileName,@BackupFileName_naming_convention_separator,@DBIndex) DBName,
										dbo.ufn_StringTokenizer(a.FileName,@BackupFileName_naming_convention_separator,@BackupTypeIndex) BTDescription,
										dbo.ufn_StringTokenizer(a.FileName,@BackupFileName_naming_convention_separator,@ServerNameIndex) SerName,
										'+REPLACE(@Transform,'TIMESTAMP','dbo.ufn_StringTokenizer(a.FileName,@BackupFileName_naming_convention_separator,@BackupStartDateIndex)')+' BFDate					
										'+IIF(@HasExt = 1,',a.Ext','') +'
							
								FROM
								(SELECT DatabaseName, BackupTypeDescription, BackupStartDate, ServerName, FileExtension, '+IIF(@HasExt = 1, 'LEFT(RIGHT([file],CHARINDEX(''\'',REVERSE([file]))-1),LEN(RIGHT([file],CHARINDEX(''\'',REVERSE([file]))-1))-CHARINDEX(''.'',REVERSE(RIGHT([file],CHARINDEX(''\'',REVERSE([file]))-1))))','RIGHT([file],CHARINDEX(''\'',REVERSE([file]))-1)') + ' FileName ' + IIF(@HasExt = 1,',RIGHT([file],CHARINDEX(''.'',REVERSE([file]))-1) Ext','') + '  FROM ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskLogBackupFiles', '#DirContentsLog') + '
								 WHERE DatabaseName IS NULL) a
							 ) b
							 WHERE dbo.ufn_CheckNameValidation(b.FileName'+IIF(@HasExt = 1,'+''.''+b.Ext ','')+','''+@Convention+''', '''+@Separator+''', b.BFDate) = 1
								
						'			
			
						BEGIN TRY
							EXEC sys.sp_executesql @SQL, N'@BackupFileName_naming_convention_separator NVARCHAR(5)', @Separator
						END TRY
						BEGIN CATCH
							SET @message = 'Something is wrong with some of your backup file names, the name convention you have introduced to this stored procedure, its separator,'+CHAR(10)+' or the formula you have given for DATETIME transform. The process of reading naming conventions will now skip to reading headers of the files.'
							RAISERROR(@message,16,1) WITH NOWAIT
						END CATCH
						TRUNCATE TABLE #BackupNamePartIndexes

						FETCH NEXT FROM FileScannerbyConvention INTO @Convention, @Separator, @Transform					
					END
				CLOSE FileScannerbyConvention
				DEALLOCATE FileScannerbyConvention
			END

			SET @SQL = 
			'
				SELECT @Count_FileHeaders_to_read = count(*) from ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskLogBackupFiles', '#DirContentsLog') + '
				WHERE DatabaseName IS NULL
			'
			EXEC sys.sp_executesql @SQL, N'@Count_FileHeaders_to_read int out', @Count_FileHeaders_to_read OUT

			IF @Skip_Files_Not_Matching_Naming_Convention = 0 AND @Count_FileHeaders_to_read > 0
			BEGIN 

				SET @message = 'Reading headers of Log backup files for '+CONVERT(VARCHAR(10),@Count_FileHeaders_to_read)+' files (lower speed but more accurate mode):'
				RAISERROR(@message,0,1) WITH NOWAIT

				
				SET @LoopCount = CEILING(@Count_FileHeaders_to_read*1.0/@Chunk_Size)	
				SET @count = @LoopCount
				
				WHILE @LoopCount > 0
				BEGIN 
				
					SET @SQL =
					'
						declare @Backup_Path nvarchar(1000), @DatabaseName nvarchar(128), @BackupFinishDate datetime, @BackupTypeDescription nvarchar(128), @ServerName nvarchar(128)

						declare BackupDetails cursor FOR
							SELECT'+
							' TOP '+CONVERT(VARCHAR(10),@Chunk_Size)+
							' [file], DatabaseName , BackupFinishDate, BackupTypeDescription
							from ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskLogBackupFiles', '#DirContentsLog') + '
							WHERE DatabaseName IS NULL
						open BackupDetails
			
							fetch next from BackupDetails into @Backup_Path, @DatabaseName , @BackupFinishDate, @BackupTypeDescription								
							while @@FETCH_STATUS = 0
							begin
			
						/*---------------------------------------------------------------------------------------------------------*/

								execute usp_BackupDetails @Backup_Path
								--print @Backup_Path
						/*---------------------------------------------------------------------------------------------------------*/
								update ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskLogBackupFiles', '#DirContentsLog') + ' set DatabaseName = ISNULL((select top 1 DatabaseName from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9),concat(''UnreadableBackupFile_'', LEFT(CONVERT(NVARCHAR(50),NEWID()),12))) WHERE CURRENT OF BackupDetails
								update ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskLogBackupFiles', '#DirContentsLog') + ' set BackupStartDate = (select top 1 BackupStartDate from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails								
								update ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskLogBackupFiles', '#DirContentsLog') + ' set BackupFinishDate = (select top 1 BackupFinishDate from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails
								update ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskLogBackupFiles', '#DirContentsLog') + ' set BackupTypeDescription = (select top 1 BackupTypeDescription from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails
								update ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskLogBackupFiles', '#DirContentsLog') + ' set ServerName = (select top 1 ServerName from #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9) WHERE CURRENT OF BackupDetails
										
                
								TRUNCATE TABLE #_46Y_xayCTv0Pidwh23eFBdt7TwavSK5r4j9
								FETCH NEXT FROM BackupDetails INTO @Backup_Path, @DatabaseName , @BackupFinishDate, @BackupTypeDescription				
							END 
						CLOSE BackupDetails
						DEALLOCATE BackupDetails
					'
					EXEC(@sql)
				
					SET @Percentage = (@Count-@LoopCount+1)*@Chunk_Size*100/@Count_FileHeaders_to_read
					SET @message = CONVERT(VARCHAR(3),IIF(@Percentage<=100, @Percentage,100))+' percent of files processed.'
					RAISERROR(@message,0,1) WITH NOWAIT

					SET @LoopCount-=1
				END

				SET @message = 'Reading of headers completed.'+CHAR(10)+'-----------------------------------------------------------------------------------------------------------'
				RAISERROR(@message,0,1) WITH NOWAIT

			END
	---------- Begin Purge Operation --------------------------------------------------------------------------


	---------- End Purge Operation ----------------------------------------------------------------------------

			----- Applying Fiters: @Exclude_DBName_Filter, and @Include_DBName_Filter filters-----------------------------------------
			BEGIN TRY

				---- Including @Include_DBName_Filter databases and excluding others ---------------------------------------
				IF @Include_DBName_Filter <> ''
				BEGIN
					SET @SQL =
					'
						UPDATE FT
						SET FT.IsIncluded = 1
						FROM
						(SELECT * FROM ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskLogBackupFiles', '#DirContentsLog') + ' WHERE IsIncluded = 0) FT				
						JOIN (SELECT TRIM(value) value FROM STRING_SPLIT('''+@Include_DBName_Filter+''','','')) ss
						ON FT.DatabaseName LIKE ss.value { ESCAPE ''\'' }
						
						OPTION (RECOMPILE)
					'
					EXEC(@SQL)
				END

				------------------------------------------------------------------------------------------------------------
				---- Filtering out @Exclude_DBName_Filter databases --------------------------------------------------------
				IF @Exclude_DBName_Filter <> ''
				BEGIN
					SET @SQL =
					'
						UPDATE FT
						SET FT.IsIncluded = 0
						FROM 
						(SELECT * FROM ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskLogBackupFiles', '#DirContentsLog') + ' WHERE IsIncluded = 1) FT				
						JOIN (SELECT TRIM(value) value FROM STRING_SPLIT('''+@Exclude_DBName_Filter+''','','')) ss
						ON FT.DatabaseName LIKE ss.value { ESCAPE ''\'' }
						OPTION (RECOMPILE)
					'
					EXEC(@sql)
				END
			
				-- Applying time filter:
				SET @SQL =
				'
					IF @BackupFinishDate_StartDATETIME <> ''1900.01.01 00:00:00''
						UPDATE ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskLogBackupFiles', '#DirContentsLog') + ' 
						SET IsIncluded = 0
						WHERE IsIncluded = 1 AND COALESCE(BackupFinishDate, BackupStartDate) < @BackupFinishDate_StartDATETIME

					IF @BackupFinishDate_EndDATETIME <> ''9999.12.31 23:59:59''
						UPDATE ' + IIF(@USE_SQLAdministrationDB_Database = 1, 'SQLAdministrationDB..DiskLogBackupFiles', '#DirContentsLog') + ' 
						SET IsIncluded = 0
						WHERE IsIncluded = 1 AND COALESCE(BackupFinishDate, BackupStartDate) > @BackupFinishDate_EndDATETIME
				'
			
				EXEC sp_executesql @SQL, N'@BackupFinishDate_StartDATETIME DATETIME, @BackupFinishDate_EndDATETIME DATETIME', @BackupFinishDate_StartDATETIME, @BackupFinishDate_EndDATETIME

				------------------------------------------------------------------------------------------------------------
			END TRY		
			BEGIN CATCH
				SET @message = ERROR_MESSAGE()
				PRINT @message
				RAISERROR('Probably STRING_SPLIT function was not recognized by the tsql interpreter. For that your database compatibility level must be 130 or higher.',16,1)
				RETURN 1
			END CATCH
			----- End applying filters--------------------------------------------------------------------------------------
			
		END
		ELSE
		BEGIN
			EXECUTE sp_configure 'xp_cmdshell', 0; RECONFIGURE; EXECUTE sp_configure 'show advanced options', 0; RECONFIGURE;			
		END
		------------ End file operations (Log Backups) -------------------------------------------------------------------

  END
  ELSE
  BEGIN
	RAISERROR('A backup root must be specified',16,1)
	RETURN 1
  END
	
	----- Show elapsed time:
	SET @message = 'Elapsed time: ' + dbo.ufn_ElapsedTime(@OperationStartTime)
	RAISERROR(@message,0,1) WITH NOWAIT
	
	PRINT('')
	DECLARE @RestoreSPResult int
	declare RestoreResults cursor FOR
		SELECT FT_ID,dbname,path from #t
	open RestoreResults
		-------------------------------------------------------------------------
		fetch next from RestoreResults into @DiskBackupFilesID, @DatabaseName, @Backup_Path			
		WHILE @@FETCH_STATUS = 0
		BEGIN
				
-------------------------------------------------------------------------------------------------------------------------------					
				EXEC @RestoreSPResult = usp_complete_restore
											@Drop_SQLSBuffers_Before_Restore = @Drop_SQLSBuffers_Before_Restore,
											@Drop_Database_if_Exists = 0,
											@DiskBackupFilesID = @DiskBackupFilesID,
											@Restore_DBName = @DatabaseName,
											@Restore_Suffix = @Destination_Database_Name_suffix,
											@Restore_Prefix = @Destination_Database_Name_prefix,
											@Ignore_Existant = @Ignore_Existant,
											@Backup_Location = @Backup_Path,
											@Destination_Database_DataFiles_Location = @Destination_Database_DataFiles_Location,	
											@Destination_Database_LogFile_Location = @Destination_Database_LogFile_Location,		
											@Take_tail_of_log_backup_of_existing_database = @Take_tail_of_log_backup_of_existing_database,
											@Keep_Database_in_Restoring_State  = @Keep_Database_in_Restoring_State,				-- If equals to 1, the database will be kept in restoring state until the whole process of restoring
											@DataFileSeparatorChar = '_',														-- This parameter specifies the punctuation mark used in data files names. For example "_"
											@Restore_Log_Backups = @Restore_Log_Backups,
											@Force_Recovery_If_No_Log_Backups_Found = @Force_Recovery_If_No_Log_Backups_Found,
											@StopAt = @StopAt,
											@Change_Target_RecoveryModel_To = @Change_Target_RecoveryModel_To,
											@Set_Target_Database_ReadOnly = @Set_Target_Databases_ReadOnly,
											@STATS = @STATS,
											@Generate_Statements_Only = @Generate_Statements_Only,
											@Delete_Backup_File = @Delete_Backup_File,
											@USE_SQLAdministrationDB_Database = @USE_SQLAdministrationDB_Database,
											@ShrinkLogFile_policy = @ShrinkLogFile_policy,
											@ShrinkDatabase_policy = @ShrinkDatabase_policy,
											@RebuildLogFile_policy = @RebuildLogFile_policy,
											@GrantAllPermissions_policy = @GrantAllPermissions_policy,
											@OperationStartTime = @OperationStartTime,
											@Script_to_Execute_After_Restore = @Script_to_Execute_After_Restore
			IF @Stop_On_Error = 1 AND @RestoreSPResult <> 0
			BEGIN
				PRINT 'The last restore operation failed. The process will not continue as @Stop_On_Error was set to 1.'
				BREAK
            END
	-------------------------------------------------------------------------------------------------------------------------------				
			FETCH NEXT FROM RestoreResults INTO @DiskBackupFilesID, @DatabaseName, @Backup_Path
		END 
	CLOSE RestoreResults
	DEALLOCATE RestoreResults
	PRINT('--=========================================================================================================')	
	
	
	--------------------- Clearing temporary tail of log backup files -------------------------------------------------------------
	IF @Generate_Statements_Only = 0 AND @Live_Restore_LogBackup_Temporary_Location<>''
	BEGIN
		DECLARE TailLogWiper CURSOR FOR
			SELECT [file] FROM #TempTailLogFiles
		OPEN TailLogWiper
			FETCH NEXT FROM TailLogWiper INTO @path
			WHILE @@FETCH_STATUS = 0
			BEGIN
				EXEC xp_delete_files @path
				FETCH NEXT FROM TailLogWiper INTO @path
			END	
		CLOSE TailLogWiper
		DEALLOCATE TailLogWiper
	END
	--------------------- End clearing temporary tail of log backup files ---------------------------------------------------------

END

GO

--=============================================================================================================================

--IF  @@SERVERNAME NOT LIKE '%test%'
--BEGIN
--	RAISERROR('Session has a wrong connection! Change the connection and re-run the script',16,1)
--	RETURN;
--END 


EXEC usp_restore_latest_backups 

	@Drop_SQLSBuffers_Before_Restore = 0,
	@Destination_Database_Name_suffix = N'_stage',
  										-- (Optional) You can specify the destination database names' suffix here. If the destination database name is equal to the backup database name,
  										-- the database will be restored on its own. 
	@Destination_Database_Name_prefix = N'',
  										-- (Optional) You can specify the destination database names' prefix here. If the destination database name is equal to the backup database name,
  										-- the database will be restored on its own. 
	@Destination_DatabaseName = N'',	-- This option only works if you have only one database to restore, otherwise it will be ignored. Prefix and suffix options will also be applied.
	@Ignore_Existant = 0,			
										-- (Optional) Ignore restoring databases that already exist on target. If set to 0, the existant will be replaced.
	@Destination_Database_DataFiles_Location = '',
										--'D:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\',			
  										-- (Optional) Possible options: 'InheritFromSource'|''|'Some Path'|'SameAsDestination'. '' or NULL means target server's default.										
										-- This script creates the folders if they do not exist automatically. Make sure SQL Service has permission to create such folders
  										-- This variable must be in the form of for example 'D:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\DATA'. If left empty,
										-- the datafiles will be restored to destination servers default directory. If given 'InheritFromSource', the script will try to put datafiles to
										-- exactly the same path as the original server. One of the situations that you can benefit from this, is if your destination server
										-- has an identical disk layout as your original server, for example it's a clone of it. 
										-- IF set to 'SameAsDestination' and the database already exists, the database will be replaced, but the database files will be placed were they
										-- were used to be on the target server.
										-- if this parameter is set to 'InheritFromSource', the '@Destination_Database_LogFile_Location' parameter will be ignored.
	@Destination_Database_LogFile_Location = '',	
										-- (Optional) If @Destination_Database_DataFiles_Location parameter is set to 'InheritFromSource', the '@Destination_Database_LogFile_Location' parameter will be ignored.
										-- Possible options: 'InheritFromSource'|''|'Some Path'. '' or NULL means target server's default

	@Backup_root_or_path = --'\\Cando-DB1\D$\backup',--'%userprofile%\desktop',
					N'\\KarboarD-DB1\g$\',
					--N'\\172.16.40.35\Backup\Backup\Database',
					--N'"D:\Database Backup\NW_Full_backup_0240.bak"',
										-- (*Mandatory) Root location for backup files. You can also sepcify a single file.
										-- Possible options: ''|'Some Path'|NULL. '' or NULL means target server's default

	------ Begin file processing speed-up parameters: ---------------------------------------------------------------------------
	-- These parameters are not mandatory, anyhow you need to carefully read the instructions before you can use them.
	-- For less than 300 files in your repository, these parameters will be ignored.
	@BackupFileName_naming_convention = --'',
										N'[{"BackupType": "FUL","NamingConvention":"DBName_BackupType_ServerName_TIMESTAMP.ext","Separator":"_","Transform":"STUFF(STUFF(STUFF(STUFF(TIMESTAMP,5,0,''.''),8,0,''.''),11,0,'' ''),14,0,'':'')+'':00''"}, {"BackupType": "ALL","NamingConvention":"DBName_BackupType_TIMESTAMP.ext","Separator":"_","Transform":"STUFF(STUFF(STUFF(STUFF(TIMESTAMP,5,0,''.''),8,0,''.''),11,0,'' ''),14,0,'':'')+'':00''"}]',
										--'DBName_BackupType_TIMESTAMP.ext',	
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
	
	@Skip_Files_Not_Matching_Naming_Convention = 0,
										-- After processing the file names, some files may remain that have not matched the defined naming convention(s) and consequently
										-- their database name, TIMESTAMP or other details have not been detected. These files can be scanned using reading of their headers
										-- , which is slower (default behavior), or skipped if this option is set to 1.
	------ End file processing speed-up parameters: -----------------------------------------------------------------------------
	
	@BackupFileName_RegexFilter = '',				
										-- (Optional) Use this filter to speed file scouring up, if you have too many files in the directory.
	
	@BackupFinishDate_StartDATETIME = '',
										--'2022.02.01 00:00:00',
										-- (Optional)
	@BackupFinishDate_EndDATETIME = '',
										--'2022.04.01 23:59:59',
										-- (Optional)
	@USE_SQLAdministrationDB_Database = 1,				
										-- (Optional, Highly Recommended to be set to 1) Create or Update DiskBackupFiles table inside SQLAdministrationDB database for faster access to backup file records and their details.
	
	@Exclude_system_databases = 1,		-- (Optional) set to 1 to avoid system databases' backups
	@Exclude_DBName_Filter = N'  %adventure%,  %NorthwindDW%',					
										-- (Optional) Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
										-- N'Northwind,AdventureWorks, StackOverFlow'. The script excludes databases that contain any of such keywords
										-- in the name like AdventureWorks2019. Note that space at the begining and end of the names will be disregarded. You
										-- can also include wildcard characters "%" and "_" for each entry. The escape character for these wildcards is "\"
										-- The @Exclude_DBName_Filter outpowers @Include_DBName_Filter.
  
	@Include_DBName_Filter = --'SQLAdministrationDB',
							--'dbWarden', 
							--N'nOrthwind',
							N'KarboardDB',
							--N'',
										-- (Optional) Enter a list of ',' delimited database names which can be split by TSQL STRING_SPLIT function. Example:
										-- N'Northwind,AdventureWorks, StackOverFlow'. The script includes databases that contain any of such keywords
										-- in the name like AdventureWorks2019 and excludes others. Note that space at the begining and end of the names
										-- will be disregarded. You can also include wildcard character "%" and "_" for each entry. The escape character for 
										-- these wildcards is "\".
									

	@IncludeSubdirectories = 1,			-- (Optional) Choose whether to include subdirectories or not while the script is searching for backup files.
	
	------------ Begin Log backup restore related parameters: -------------------------------------------------
	@Restore_Log_Backups = 1,			-- (Optional)
	@Force_Recovery_If_No_Log_Backups_Found = 1,
	@LogBackup_root_or_path = N'',
										-- (Optional) If left empty or undefined, the script will assume that the log backups root is the same as the full
										-- backups' root
	@StopAt = '',
				--'2022.10.02 11:10:18',--'2022.08.28 15:23:18',--'2022.08.12 09:25:25',
										-- (Optional)
	@Live_Restore_LogBackup_Temporary_Location = '',--N'\\172.16.40.35\TempBackups\',
										-- (Optional) In order to restore the database from production to the latest time before executing this script,
										-- this can be set for a temporary location of the log backup of production, triggered by this script. Note that
										-- all the previous log backups must also be available for the log chain. The specified path also needs to be
										-- a shared UNC path accessible to both servers. The linked server to the production must also exist to issue the
										-- log backup command, the RPC feature of the linked server must be enabled and the mapped login on production
										-- must have backup rights (for example: db_backupoperator). 
										-- IF left empty or null, this parameter will be ignored.
	------------ End Log backup restore related parameters: ---------------------------------------------------
	
	@Keep_Database_in_Restoring_State = 0,						
										-- (Optional) If equals to 1, the database will be kept in restoring state
	@Take_tail_of_log_backup_of_existing_database = 0,
										-- (Optional, important)						
	@DataFileSeparatorChar = '_',		
										-- (Optional) This parameter specifies the punctuation mark used in data files names. For example "_"
										-- in 'NW_sales_1.ndf' or "$" in 'NW_sales$1.ndf'.
	@Change_Target_RecoveryModel_To = 'simple',
										-- (Optional) Set this variable for the target databases' recovery model. Possible options: FULL|BULK-LOGGED|SIMPLE|InheritFromSource|SameAsDestination
										
	@Set_Target_Databases_ReadOnly = 0,
										-- (Optional)
	@STATS = 10,
										-- (Optional) Report restore percentage stats in SQL Server restore process. Only for database restore not log files restore.
	@Generate_Statements_Only = 0,
										-- (Optional) use this to generate restore statements without executing them.
	@Delete_Backup_File = 0,
										-- (Optional) Turn this feature on to delete the backup files that are successfully restored. (This does not apply to transaction log backup files)
	@Activate_Destination_Database_Containment = 1,
										-- (Optional, but error will be raised for backups of partially contained databases if 'contained database authentication' has not been activated,
										-- you try to restore backups of partially contained databases and this option has not been turned to 1 on the target server)
	@Stop_On_Error = 0,					-- (Optional) Stop restoring databases should a retore fail
	--@Retention_Policy_Enabled = 0,
	--									-- (Optional) Enable or disable removing (purging) the old backups according to the defined
	--									-- policy
	----,@Retention_Policy = @Retention_Policy
	--									-- (Optional) Setup a policy for retaining your past backups 
	@ShrinkDatabase_policy = -2,		-- (Optional) Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave %x of free space after shrinking 
	@ShrinkLogFile_policy = -2,			-- (Optional) Possible options: -2: Do not shrink | -1: shrink only | 0<=x : shrink reorganizing files and leave x MBs of free space after shrinking.
										-- Using @ShrinkDatabase_policy and @ShrinkLogFile_policy may be redundant for log file if the same option for both is specified.
	@RebuildLogFile_policy = '128MB:128MB:5GB',--'32MB:128MB:1024MB',	
										-- (Optional) Possible options: NULL or Empty string: Do not rebuild | 'x:y:z' (For example, 4MB:64MB:1024MB) rebuild to SIZE = x, FILEGROWTH = y, MAXSIZE = z. If @RebuildLogFile_policy is specified, @ShrinkLogFile_policy will be ignored.
										-- Note: There is no risk of 'Transactional inconsistency', in this stored procedure specifically, despite the warning message that Microsoft may generate and you do not need to run CHECKDB for this in particular. Also, the extra log files have been deleted.

	@GrantAllPermissions_policy = 3,	-- (Optional) Possible options: -2: Do not alter permissions | 1: Make every current DB user, a member of db_owner group | 2: Turn on guest account, remove every user from the database, and make guest a member of db_owner group:
										-- The "2" option is theorically correct, but there seems to be a SQL Server bug that I have seen cases that despite the fact that I dropped SQL Server users on that database, the users still authenticated with their previous user names and not
										-- 'guest' account. So I added the third option which is a combination of 1 & 2 | 3: make the existing users members of db_owner group and turn on guest account and make the guest account a db_owner
	@Script_to_Execute_After_Restore = ''	
										-- (Optional) This parameter will hold a dynamic query to be executed for each database before it becomes available to the end user. Before full execution of this dynamic query, the database will remain in
										-- SINGLE_USER mode.
GO


--SELECT * FROM SQLAdministrationDB.dbo.RestoreHistory ORDER BY RestoreHistoryID DESC
SELECT * FROM msdb..restorehistory ORDER BY restore_history_id DESC
SELECT * FROM SQLAdministrationDB..DiskBackupFiles WHERE [FILE] = '\\172.16.40.35\Backup\Backup\Database\Full\JvTalentPoolDB_FULL_202301190016.bak' 
UPDATE SQLAdministrationDB..DiskBackupFiles SET IsIncluded = 0 WHERE IsIncluded = 1
SELECT * FROM SQLAdministrationDB..DiskLogBackupFiles  WHERE IsIncluded = 1
--UPDATE SQLAdministrationDB..DiskLogBackupFiles SET IsIncluded = 0 WHERE IsIncluded = 1
SELECT * FROM SQLAdministrationDB..RestoreHistory


--ALTER TABLE SQLAdministrationDB..RestoreHistory ADD LastRestoredLogBackupID int
--SELECT DISTINCT DiskBackupFilesID from SQLAdministrationDB..RestoreHistory WHERE DiskBackupFilesID NOT IN (SELECT DiskBackupFilesID FROM SQLAdministrationDB..DiskBackupFiles)

-- Results after "SQLAdministrationDB Caching of Files" optimization for about 6000 backup files:
-- First Run: 00:20:51
-- Second Run: 00:00:13
-- Third Run: 00:00:03

-- restore database sqladministrationdb_test with recovery


DROP PROC dbo.usp_PrintLong
GO
DROP FUNCTION dbo.ufn_CheckNameValidation
GO
DROP FUNCTION dbo.ufn_StringTokenizer
GO
DROP FUNCTION dbo.ufn_FileExistsForAnotherDatabase
GO
DROP PROCEDURE usp_BackupDetails
GO
DROP PROCEDURE dbo.usp_complete_restore
GO
DROP PROCEDURE dbo.usp_restore_latest_backups
GO
DROP FUNCTION dbo.ufn_ElapsedTime
GO



