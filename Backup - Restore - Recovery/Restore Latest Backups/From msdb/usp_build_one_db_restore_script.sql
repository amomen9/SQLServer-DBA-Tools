-- =============================================
-- Author:				<a.momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			
-- Latest Update Date:	
-- Description:			
-- License:				<Please refer to the license file> 
-- =============================================

SET NOCOUNT ON;

USE msdb;
GO


CREATE OR ALTER FUNCTION dbo.fn_SplitStringByLine
(
    @Query nvarchar(max)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        LTRIM(RTRIM(T.N.value('.', 'nvarchar(max)'))) AS LineText,
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS ordinal
    FROM (
        SELECT CAST('<r><x>' + REPLACE(REPLACE(@Query, CHAR(13), ''), CHAR(10), '</x><x>') + '</x></r>' AS xml)
    ) AS d(XmlData)
    CROSS APPLY d.XmlData.nodes('/r/x') AS T(N)
    -- WHERE LTRIM(RTRIM(T.N.value('.', 'nvarchar(max)'))) <> ''
	-- keep empties: Keep the "WHERE" clause commented out
);
GO

CREATE OR ALTER FUNCTION dbo.udf_BASE_NAME(@Path NVARCHAR(2000))
RETURNS NVARCHAR(2000)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @Result NVARCHAR(2000);
    DECLARE @CleanPath NVARCHAR(2000);
    
    -- Strip trailing backslashes and forward slashes
    SET @CleanPath = @Path;
    WHILE RIGHT(@CleanPath, 1) IN ('\', '/')
        SET @CleanPath = LEFT(@CleanPath, LEN(@CleanPath) - 1);
    
    -- Check if it's a URL (contains ://)
    IF @CleanPath LIKE '%://%'
    BEGIN
        SET @Result = @Path;  -- Return original URL
    END
    -- Windows path (contains backslash)
    ELSE IF @CleanPath LIKE '%\%'
    BEGIN
        SET @Result = RIGHT(@CleanPath, CHARINDEX('\', REVERSE(@CleanPath)) - 1);
    END
    -- Linux path (contains forward slash)
    ELSE IF @CleanPath LIKE '%/%'
    BEGIN
        SET @Result = RIGHT(@CleanPath, CHARINDEX('/', REVERSE(@CleanPath)) - 1);
    END
    -- No separators found
    ELSE
    BEGIN
        SET @Result = @CleanPath;
    END
    
    RETURN @Result;
END
GO

CREATE OR ALTER FUNCTION dbo.udf_PARENT_DIR(@Path NVARCHAR(2000))
RETURNS NVARCHAR(2000)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @Result NVARCHAR(2000);
    DECLARE @CleanPath NVARCHAR(2000);
    
    -- Strip trailing backslashes and forward slashes
    SET @CleanPath = @Path;
    WHILE RIGHT(@CleanPath, 1) IN ('\', '/')
        SET @CleanPath = LEFT(@CleanPath, LEN(@CleanPath) - 1);
    
    -- Check if it's a URL (contains ://) → return empty string
    IF @CleanPath LIKE '%://%'
    BEGIN
        SET @Result = '';
    END
    -- Windows path (contains backslash)
    ELSE IF @CleanPath LIKE '%\%'
    BEGIN
        SET @Result = LEFT(@CleanPath, LEN(@CleanPath) - CHARINDEX('\', REVERSE(@CleanPath)));
    END
    -- Linux path (contains forward slash)
    ELSE IF @CleanPath LIKE '%/%'
    BEGIN
        SET @Result = LEFT(@CleanPath, LEN(@CleanPath) - CHARINDEX('/', REVERSE(@CleanPath)));
    END
    -- No separators found → return empty string
    ELSE
    BEGIN
        SET @Result = '';
    END
    
    RETURN @Result;
END
GO
-- Example Usage:
-- DECLARE @MyScript nvarchar(max) = N'SELECT * FROM sys.databases;'+CHAR(13)+CHAR(10)+N'SELECT * FROM sys.objects;';
-- SELECT * FROM dbo.fn_SplitStringByLine(@MyScript);

CREATE OR ALTER FUNCTION dbo.user_dm_os_file_exists
(
    @parent_dir NVARCHAR(2000),
    @base_name  NVARCHAR(2000)
)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        NULL	AS full_filesystem_path,
        NULL	AS is_directory,
        NULL	AS file_or_directory_name,
		1		AS Existence_Check_Failed,
		CONVERT(VARCHAR(500),'File/Directory "'+ @base_name + '" is not a valid OS or UNC path.')
				AS Existence_Check_Status_Desc
    WHERE @parent_dir = '' OR @base_name = ''
    UNION ALL
    SELECT 
        fe.full_filesystem_path,
        fe.is_directory,
        fe.file_or_directory_name,
		0		AS Existence_Check_Failed,
		NULL	AS Existence_Check_Status_Desc
    FROM sys.dm_os_enumerate_filesystem(@parent_dir, @base_name) fe
    WHERE @parent_dir <> '' AND @base_name <> ''
);
GO


CREATE OR ALTER PROC usp_build_one_db_restore_script
		@DatabaseName						sysname,
		@RestoreDBName						sysname = NULL,
		@create_datafile_dirs				BIT = 1,
		@Restore_DataPath					NVARCHAR(1000) = NULL,	-- Uses original database path if not specified
		@Restore_LogPath					NVARCHAR(1000) = NULL,	-- Uses original database path if not specified
		@StopAt								DATETIME = NULL,
		@WithReplace						BIT	= 0,
		@IncludeLogs						BIT	= 1,
		@IncludeDiffs						BIT = 1,
		@Recovery							BIT = 0,
		@STATS								VARCHAR(3) = '25',
		@RestoreUpTo_TIMESTAMP				DATETIME2(3) = NULL,
		@new_backups_parent_dir				NVARCHAR(4000) = NULL,
		@check_backup_file_existance		BIT = 0,				-- Check if the backup file exists on disk at @new_backups_parent_dir or
																	-- the original file backup path if @new_backups_parent_dir is empty or null
		@Recover_Database_On_Error			BIT = 0,
		@Preparatory_Script_Before_Restore	NVARCHAR(MAX) = NULL,
		@Complementary_Script_After_Restore	NVARCHAR(MAX) = NULL,
		@Execute							BIT	= 0,
		@Verbose							BIT = 1,
		@SQLCMD_Connect_Conn_String			NVARCHAR(MAX) = NULL,
		@Last_Parent_Procedure_Iteration	BIT = 0,
		@First_Parent_Procedure_Iteration	BIT = 0,
		@ResultSet_is_for_single_Database	BIT = 1
AS
BEGIN
	SET NOCOUNT ON
	------------------------------------------------------------
	-- Author tag
	------------------------------------------------------------
	IF @Verbose = 1
		PRINT '
		-- =============================================
		-- Author:				<a.momen>
		-- Contact & Report:	<amomen@gmail.com>
		-- Create date:			
		-- Latest Update Date:	
		-- Description:			
		-- License:				<Please refer to the license file> 
		-- =============================================
	
		'
	------------------------------------------------------------
	-- Parameter definition
	------------------------------------------------------------
	DECLARE @MoveClauses NVARCHAR(MAX);
    DECLARE @create_directories NVARCHAR(MAX);
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Script NVARCHAR(MAX) = N'';         -- plain script (already used)
	DECLARE @SQLCMD_Script NVARCHAR(MAX) = N'';  -- mirrors dt.Script result set
	DECLARE @tmpLine NVARCHAR(MAX);
	DECLARE @ord INT;
	DECLARE @msg NVARCHAR(4000)
	DECLARE @Failure_Mark BIT = 0

	------------------------------------------------------------
	-- Parameter validation
	------------------------------------------------------------

	IF DB_ID(@DatabaseName) IS NULL AND @Verbose = 1
		PRINT 'Note: Target DB does not currently exist (restore will create it).';
	
	IF @StopAt = '' SET @StopAt = NULL
	IF @RestoreUpTo_TIMESTAMP = '' OR @RestoreUpTo_TIMESTAMP IS NULL SET @RestoreUpTo_TIMESTAMP = GETDATE()+1
	IF ISNULL(@RestoreDBName,'') = '' SET @RestoreDBName = @DatabaseName
	SET @check_backup_file_existance = ISNULL(@check_backup_file_existance,0)
	SET @new_backups_parent_dir = ISNULL(@new_backups_parent_dir, '')
	IF @STATS = '' SET @STATS = NULL

	------------------------------------------------------------
	-- Create Global Output Results Table
	------------------------------------------------------------

	IF OBJECT_ID('tempdb..##Total_Output') IS NULL
    CREATE TABLE ##Total_Output
    (
        Output_Id INT IDENTITY(1,1) PRIMARY KEY NOT NULL,
        Output NVARCHAR(MAX)
    );

	------------------------------------------------------------
	-- Header
	------------------------------------------------------------
	PRINT '----------- ' + 'Database: ' + @DatabaseName + ' --> ' + @RestoreDBName + ' ---------------------------------';

	-- Also start header in @Script
	SET @SQLCMD_Script += '--- Script creation time: ['+CONVERT(NVARCHAR(30),CONVERT(DATETIME2(0),GETDATE()),121)+'] ---' + REPLICATE(CHAR(10),2) +
		'----------- Database: ' + @DatabaseName + ' --> ' + @RestoreDBName + ' ---------------------------------';
	------------------------------------------------------------
	-- Get backup dump file list, if @new_backups_parent_dir is specified (The path different than the original server's backup destination, if specified)
	------------------------------------------------------------
	IF OBJECT_ID('tempdb..##usp_build_one_db_restore_script$Backup_Files') IS NULL
	BEGIN
		CREATE TABLE ##usp_build_one_db_restore_script$Backup_Files 
		(
			full_filesystem_path NVARCHAR(256),
			file_or_directory_name NVARCHAR(256) NOT NULL
		);
		ALTER TABLE ##usp_build_one_db_restore_script$Backup_Files ADD CONSTRAINT PK_Temp_Backup_Files PRIMARY KEY(file_or_directory_name);
	END
	IF OBJECT_ID('tempdb..##Backup_Path_List') IS NULL
		CREATE TABLE ##Backup_Path_List 
		(
			Database_Name sysname,
			Backup_Path NVARCHAR(256)
		);

	
	IF @new_backups_parent_dir <> ''
	BEGIN
		DECLARE @new_backups_parent_dir_status TINYINT = (SELECT file_exists+file_is_a_directory FROM sys.dm_os_file_exists(@new_backups_parent_dir))

		IF dbo.udf_PARENT_DIR(@new_backups_parent_dir) = '' OR dbo.udf_BASE_NAME(@new_backups_parent_dir) = ''
		BEGIN
			SET @msg = 'File/Directory "' + @new_backups_parent_dir + '" is not a valid OS or UNC path.'
			RAISERROR(@msg,16,1)
		END
		ELSE
			IF @new_backups_parent_dir_status IS NULL
			BEGIN
				SET @msg = 'Specified @new_backups_parent_dir='''+@new_backups_parent_dir+''' cannot be found or the Database Engine does not have necessary permissions.'
				RAISERROR(@msg,16,1)
			END
			ELSE IF NOT EXISTS (SELECT * FROM ##Backup_Path_List WHERE @new_backups_parent_dir LIKE Backup_Path+'%')			
				INSERT INTO ##usp_build_one_db_restore_script$Backup_Files (full_filesystem_path, file_or_directory_name)
					SELECT MIN(full_filesystem_path) full_filesystem_path, file_or_directory_name 
					FROM dbo.user_dm_os_file_exists(@new_backups_parent_dir,'*') 
					WHERE is_directory = 0
					GROUP BY file_or_directory_name

		INSERT ##Backup_Path_List
			SELECT @DatabaseName, @new_backups_parent_dir
	END
	
	------------------------------------------------------------
	-- FULL backup (latest non copy_only)
	------------------------------------------------------------
	IF OBJECT_ID('tempdb..#Full') IS NOT NULL DROP TABLE #Full;
		CREATE TABLE #Full ( [backup_set_id] int, [database_name] nvarchar(128), [backup_start_date] datetime, [backup_finish_date] datetime, [first_lsn] decimal(25,0), [last_lsn] decimal(25,0), [checkpoint_lsn] decimal(25,0), [database_backup_lsn] decimal(25,0), [Devices] nvarchar(4000) )
	SET @SQL =
	'
		SELECT TOP (1)
			  b.backup_set_id
			, b.database_name
			, b.backup_start_date
			, b.backup_finish_date
			, b.first_lsn
			, b.last_lsn
			, b.checkpoint_lsn
			, b.database_backup_lsn
			, Devices = STRING_AGG('+IIF(@new_backups_parent_dir='','b.physical_device_name','b.full_filesystem_path') + ', N'','')
		FROM
		(
			SELECT
				  b.backup_set_id
				, b.database_name
				, b.backup_start_date
				, b.backup_finish_date
				, b.first_lsn
				, b.last_lsn
				, b.checkpoint_lsn
				, b.database_backup_lsn
				, mf.physical_device_name
				'+IIF(@new_backups_parent_dir='','',', bf.full_filesystem_path') +REPLICATE(CHAR(9),4) + '		
				, dbo.udf_BASE_NAME(mf.physical_device_name) base_name
				, dbo.udf_PARENT_DIR(mf.physical_device_name) parent_dir		
			FROM msdb.dbo.backupset b
			JOIN msdb.dbo.backupmediafamily mf ON b.media_set_id = mf.media_set_id
			'+IIF(@new_backups_parent_dir='','','JOIN ##usp_build_one_db_restore_script$Backup_Files bf ON dbo.udf_BASE_NAME(mf.physical_device_name) = bf.file_or_directory_name')+
			'
			WHERE b.database_name = '''+@DatabaseName+'''
			  AND b.[type] = ''D''
			  AND b.is_copy_only = 0
			  AND mf.mirror = 0
			  AND mf.physical_device_name <> ''nul''
			  AND b.backup_start_date < COALESCE('+ISNULL(''''+CONVERT(VARCHAR(100),@RestoreUpTo_TIMESTAMP,121)+'''','NULL')+', b.backup_start_date)
		) b	
		'+IIF(@new_backups_parent_dir='','CROSS APPLY dbo.user_dm_os_file_exists(parent_dir,base_name) fe','')+
		-- dm_os_file_exists does not work for the line above, thus dm_os_enumerate_filesystem is used instead.
		'
		GROUP BY b.backup_set_id, b.database_name, b.backup_start_date, b.backup_finish_date,
					b.first_lsn, b.last_lsn, b.checkpoint_lsn, b.database_backup_lsn
		ORDER BY b.backup_finish_date DESC;
	'
	INSERT INTO #Full ([backup_set_id], [database_name], [backup_start_date], [backup_finish_date], [first_lsn], [last_lsn], [checkpoint_lsn], [database_backup_lsn], [Devices])
	EXEC(@SQL)

	IF NOT EXISTS (SELECT 1 FROM #Full)
		SET @Failure_Mark = 1
	
	IF @Failure_Mark = 1
	BEGIN
		IF @Last_Parent_Procedure_Iteration = 1 AND @ResultSet_is_for_single_Database = 0
		BEGIN
			SELECT * FROM ##Total_Output ORDER BY Output_Id
			DROP TABLE ##Total_Output
		END
		RAISERROR('No FULL backup found for %s.',16,1,@DatabaseName);
		RETURN 1;
	END

	------------------------------------------------------------
	-- Prepare create directories for each database file
	------------------------------------------------------------
	SELECT @create_directories = '------ Create datafiles directories' + CHAR(10) + STRING_AGG(d.create_dir, CHAR(13)+CHAR(10))
	FROM (
		SELECT DISTINCT 'EXEC sys.xp_create_subdir N''' +
							LEFT(mf.physical_name, LEN(mf.physical_name) - CHARINDEX('\', REVERSE(mf.physical_name))) + '''' AS create_dir
		FROM sys.master_files mf
		WHERE mf.database_id = DB_ID(@DatabaseName)
		  AND mf.physical_name LIKE '%\%'
	) d;

	------------------------------------------------------------
	-- DIFF (latest tied to that FULL)
	------------------------------------------------------------
	IF OBJECT_ID('tempdb..#Diff') IS NOT NULL DROP TABLE #Diff;
	CREATE TABLE #Diff ( [backup_set_id] int, [backup_start_date] datetime, [backup_finish_date] datetime, [first_lsn] decimal(25,0), [last_lsn] decimal(25,0), [differential_base_lsn] decimal(25,0), [Devices] nvarchar(4000) )
	SET @SQL =
	'
		SELECT TOP (1)
			  b.backup_set_id
			, b.backup_start_date
			, b.backup_finish_date
			, b.first_lsn
			, b.last_lsn
			, b.differential_base_lsn
			, Devices = STRING_AGG('+IIF(@new_backups_parent_dir='','b.physical_device_name','b.full_filesystem_path') + ', N'','')
		FROM
		(	
			SELECT
				  b.backup_set_id
				, b.backup_start_date
				, b.backup_finish_date
				, b.first_lsn
				, b.last_lsn
				, b.differential_base_lsn
				, mf.physical_device_name
				'+IIF(@new_backups_parent_dir='','',', bf.full_filesystem_path') +REPLICATE(CHAR(9),4) + '		
				, dbo.udf_BASE_NAME(mf.physical_device_name) base_name
				, dbo.udf_PARENT_DIR(mf.physical_device_name) parent_dir		
			FROM msdb.dbo.backupset b
			JOIN msdb.dbo.backupmediafamily mf ON b.media_set_id = mf.media_set_id
			CROSS JOIN #Full f
			'+IIF(@new_backups_parent_dir='','','JOIN ##usp_build_one_db_restore_script$Backup_Files bf ON dbo.udf_BASE_NAME(mf.physical_device_name) = bf.file_or_directory_name')+
			'
			WHERE b.database_name = '''+@DatabaseName+'''
			  AND b.[type] = ''I''
			  AND b.differential_base_lsn = f.checkpoint_lsn
			  AND mf.mirror = 0
			  AND mf.physical_device_name <> ''nul''
			  AND b.backup_finish_date > f.backup_finish_date
			  AND '+CONVERT(VARCHAR(1),@IncludeDiffs)+' = 1
			  AND b.backup_start_date < COALESCE('+ISNULL(''''+CONVERT(VARCHAR(100),@RestoreUpTo_TIMESTAMP,121)+'''','NULL')+', b.backup_start_date)
		) b
		'+IIF(@new_backups_parent_dir='','CROSS APPLY dbo.user_dm_os_file_exists(parent_dir,base_name) fe','')+
		-- dm_os_file_exists does not work for the line above, thus dm_os_enumerate_filesystem is used instead.
		'
		GROUP BY b.backup_set_id, b.backup_start_date, b.backup_finish_date,
				 b.first_lsn, b.last_lsn, b.differential_base_lsn
		ORDER BY b.backup_finish_date DESC;
	'
	INSERT INTO #Diff ([backup_set_id], [backup_start_date], [backup_finish_date], [first_lsn], [last_lsn], [differential_base_lsn], [Devices])
	EXEC(@SQL)
	------------------------------------------------------------
	-- LOG backups after base (Diff if exists else Full)
	------------------------------------------------------------
	DECLARE @BaseLastLSN numeric(25,0), @BaseFinish datetime;
	SELECT @BaseLastLSN = COALESCE((SELECT last_lsn FROM #Diff),(SELECT last_lsn FROM #Full));
	SELECT @BaseFinish  = COALESCE((SELECT backup_finish_date FROM #Diff),(SELECT backup_finish_date FROM #Full));

	IF OBJECT_ID('tempdb..#Logs') IS NOT NULL DROP TABLE #Logs;
	CREATE TABLE #Logs ( [backup_set_id] int, [backup_start_date] datetime, [backup_finish_date] datetime, [first_lsn] decimal(25,0), [last_lsn] decimal(25,0), [database_backup_lsn] decimal(25,0), [Devices] nvarchar(4000) )
	SET @SQL =
	'
		SELECT
			  b.backup_set_id
			, b.backup_start_date
			, b.backup_finish_date
			, b.first_lsn
			, b.last_lsn
			, b.database_backup_lsn
			, Devices = STRING_AGG('+IIF(@new_backups_parent_dir='','b.physical_device_name','b.full_filesystem_path') + ', N'','')
		FROM
		(
			SELECT
				  b.backup_set_id
				, b.backup_start_date
				, b.backup_finish_date
				, b.first_lsn
				, b.last_lsn
				, b.database_backup_lsn
				, mf.physical_device_name
				'+IIF(@new_backups_parent_dir='','',', bf.full_filesystem_path') +'	
				, dbo.udf_BASE_NAME(mf.physical_device_name) base_name
				, dbo.udf_PARENT_DIR(mf.physical_device_name) parent_dir		
			FROM msdb.dbo.backupset b
			JOIN msdb.dbo.backupmediafamily mf ON b.media_set_id = mf.media_set_id
			'+IIF(@new_backups_parent_dir='','','JOIN ##usp_build_one_db_restore_script$Backup_Files bf ON dbo.udf_BASE_NAME(mf.physical_device_name) = bf.file_or_directory_name')+
			'
			WHERE b.database_name = '''+@DatabaseName+'''
			  AND b.[type] = ''L''
			  AND mf.mirror = 0
			  AND mf.physical_device_name <> ''nul''
			  AND b.backup_finish_date > '''+CONVERT(VARCHAR(100),@BaseFinish,121)+'''
			  AND '+CONVERT(VARCHAR(1),@IncludeLogs)+' = 1
			  AND b.backup_start_date < COALESCE('+ISNULL(''''+CONVERT(VARCHAR(100),@RestoreUpTo_TIMESTAMP,121)+'''','NULL')+', b.backup_start_date)
		) b
		GROUP BY b.backup_set_id, b.backup_start_date, b.backup_finish_date,
				 b.first_lsn, b.last_lsn, b.database_backup_lsn
		ORDER BY b.first_lsn;
	'
	INSERT INTO #Logs ([backup_set_id], [backup_start_date], [backup_finish_date], [first_lsn], [last_lsn], [database_backup_lsn], [Devices])
	EXEC(@SQL)

	--------------- Drop the table ##usp_build_one_db_restore_script$Backup_Files if necessary ---------------
	IF @Last_Parent_Procedure_Iteration = 1
	BEGIN
		DROP TABLE ##usp_build_one_db_restore_script$Backup_Files
		DROP TABLE ##Backup_Path_List
	END
	------------------------------------------------------------
	-- Validate log chain (basic gaps)
	------------------------------------------------------------
	IF OBJECT_ID('tempdb..#LogsValid') IS NOT NULL DROP TABLE #LogsValid;
	SELECT  l.*
		  , PrevLastLSN = LAG(l.last_lsn) OVER (ORDER BY l.first_lsn)
		  , GapOK = CASE 
					  WHEN LAG(l.last_lsn) OVER (ORDER BY l.first_lsn) IS NULL 
						   THEN CASE WHEN l.first_lsn <= @BaseLastLSN + 1 AND l.last_lsn > @BaseLastLSN THEN 1 ELSE 0 END
					  ELSE CASE 
							 WHEN LAG(l.last_lsn) OVER (ORDER BY l.first_lsn) >= l.first_lsn - 1
								  AND LAG(l.last_lsn) OVER (ORDER BY l.first_lsn) <  l.last_lsn
								  THEN 1 ELSE 0 END
					END
	INTO #LogsValid
	FROM #Logs l
	ORDER BY l.first_lsn;

	DECLARE @LogsChainValid bit = 1;
	IF EXISTS (SELECT 1 FROM #LogsValid WHERE GapOK = 0)
		SET @LogsChainValid = 0;

	------------------------------------------------------------
	-- Build restore chain list
	------------------------------------------------------------
	IF OBJECT_ID('tempdb..#RestoreChain') IS NOT NULL DROP TABLE #RestoreChain;
	CREATE TABLE #RestoreChain
	(
		StepNumber     int IDENTITY(1,1) PRIMARY KEY,
		BackupType     varchar(10),
		BackupSetId    int,
		BackupStart    datetime,
		BackupFinish   datetime,
		FirstLSN       numeric(25,0),
		LastLSN        numeric(25,0),
		Devices        nvarchar(max),
		RestoreCommand nvarchar(max)
	);

	-- FULL
	INSERT INTO #RestoreChain
	(BackupType, BackupSetId, BackupStart, BackupFinish, FirstLSN, LastLSN, Devices, RestoreCommand)
	SELECT 'FULL', backup_set_id, backup_start_date, backup_finish_date, first_lsn, last_lsn, Devices, NULL
	FROM #Full;

	-- DIFF (optional)
	IF EXISTS (SELECT 1 FROM #Diff)
	BEGIN
		INSERT INTO #RestoreChain
		(BackupType, BackupSetId, BackupStart, BackupFinish, FirstLSN, LastLSN, Devices, RestoreCommand)
		SELECT 'DIFF', backup_set_id, backup_start_date, backup_finish_date, first_lsn, last_lsn, Devices, NULL
		FROM #Diff;
	END

	-- LOGs
	INSERT INTO #RestoreChain
	(BackupType, BackupSetId, BackupStart, BackupFinish, FirstLSN, LastLSN, Devices, RestoreCommand)
	SELECT 'LOG', backup_set_id, backup_start_date, backup_finish_date, first_lsn, last_lsn, Devices, NULL
	FROM #LogsValid
	ORDER BY first_lsn;

	------------------------------------------------------------
	-- Precompute DISK clauses (avoid aggregates in UPDATE)
	------------------------------------------------------------
	IF OBJECT_ID('tempdb..#DiskClauses') IS NOT NULL DROP TABLE #DiskClauses;
	SELECT rc.StepNumber,
		   Disks = STUFF((
			   SELECT ', DISK = N''' + LTRIM(RTRIM(value)) + ''''
			   FROM string_split(rc.Devices, ',')
			   ORDER BY value
			   FOR XML PATH(''), TYPE).value('.','nvarchar(max)'),1,2,'')
	INTO #DiskClauses
	FROM #RestoreChain rc;

	------------------------------------------------------------
	-- Precompute MOVE clauses (avoid aggregates in UPDATE)
	------------------------------------------------------------
	SELECT @MoveClauses =
		STUFF((
			SELECT CHAR(10) + REPLICATE(CHAR(9),4) + 'MOVE N''' + mf.name + ''' TO N''' +
				   CASE
					   WHEN mf.type_desc = 'LOG' AND ISNULL(@Restore_LogPath,'') <> '' THEN
						   @Restore_LogPath +
						   CASE WHEN RIGHT(@Restore_LogPath,1) IN ('\','/') THEN '' ELSE '\' END +
						   RIGHT(mf.physical_name, CHARINDEX('\', REVERSE(mf.physical_name)) - 1)
					   WHEN mf.type_desc <> 'LOG' AND ISNULL(@Restore_DataPath,'') <> '' THEN
						   @Restore_DataPath +
						   CASE WHEN RIGHT(@Restore_DataPath,1) IN ('\','/') THEN '' ELSE '\' END +
						   RIGHT(mf.physical_name, CHARINDEX('\', REVERSE(mf.physical_name)) - 1)
					   ELSE mf.physical_name
				   END + ''','
			FROM sys.master_files AS mf
			WHERE mf.database_id = DB_ID(@DatabaseName)
			ORDER BY mf.type, mf.file_id
			FOR XML PATH(''), TYPE).value('.','nvarchar(max)')
		,1,1,'');


	SET @MoveClauses = CHAR(10) + @MoveClauses


	-- Mark last step
	DECLARE @LastStep int = (SELECT MAX(StepNumber) FROM #RestoreChain);

	------------------------------------------------------------
	-- Generate RESTORE commands
	------------------------------------------------------------
	DECLARE 
		@HasDiff bit = CASE WHEN EXISTS (SELECT 1 FROM #RestoreChain WHERE BackupType='DIFF') THEN 1 ELSE 0 END,
		@HasLogs bit = CASE WHEN EXISTS (SELECT 1 FROM #RestoreChain WHERE BackupType='LOG') THEN 1 ELSE 0 END,
		@ReplaceClause nvarchar(20) = CASE WHEN @WithReplace = 1 THEN N', REPLACE' ELSE N'' END;

	UPDATE rc
	SET RestoreCommand =
		CASE rc.BackupType
			WHEN 'FULL' THEN
				N'RESTORE DATABASE [' + @RestoreDBName + N'] FROM ' + dc.Disks + CHAR(10) + N' WITH ' + @MoveClauses + CHAR(10) +
				ISNULL(N'STATS = '+@STATS,'') + @ReplaceClause + 
				CASE WHEN rc.StepNumber = @LastStep AND @Recovery = 1 THEN N', RECOVERY;' ELSE N', NORECOVERY;' END + REPLICATE(CHAR(10),2) +
				--- Calculating restore duration:
				'--- Calculating restore duration:' + CHAR(10) +
				'SET @Reused_seconds = RIGHT(''0''+CONVERT(VARCHAR(100),DATEDIFF_BIG(SECOND,@Reused_TimeStamp,GETDATE())%60),2); SET @Reused_minutes = RIGHT(''0''+CONVERT(VARCHAR(100),DATEDIFF_BIG(SECOND,@Reused_TimeStamp,GETDATE())/60),2); SET @Reused_hours = RIGHT(''00''+CONVERT(VARCHAR(100),DATEDIFF_BIG(SECOND,@Reused_TimeStamp,GETDATE())/3600),2); SET @msg = ''--- Restore finished (FULL Backup). Elapsed time: ['' + @Reused_hours+'':''+@Reused_minutes+'':''+@Reused_seconds+'']''; SET @Reused_TimeStamp = GETDATE(); RAISERROR(@msg,0,1) WITH NOWAIT' + CHAR(10) +
				'INSERT #BackupTimes (BackupType, StepNo, hours, minutes, seconds) SELECT		   ''FULL'',   1,   @Reused_hours, @Reused_minutes, @Reused_seconds' + CHAR(10)

			WHEN 'DIFF' THEN
				N'RESTORE DATABASE [' + @RestoreDBName + N'] FROM ' + dc.Disks + CHAR(10) + N' WITH ' +
				(CASE 
					WHEN rc.StepNumber = @LastStep AND @StopAt IS NOT NULL AND @HasLogs = 0
						THEN N'STOPAT = ''' + CONVERT(varchar(23), @StopAt, 121) + N''', '
					ELSE N''
				 END) + CHAR(10) +
				ISNULL(N'STATS = '+@STATS,'') +
				CASE WHEN rc.StepNumber = @LastStep AND @HasLogs = 0 AND @Recovery = 1 THEN N', RECOVERY;' ELSE N', NORECOVERY;' END + REPLICATE(CHAR(10),2) +
				--- Calculating restore duration:
				'--- Calculating restore duration:' + CHAR(10) +
				'SET @Reused_seconds = RIGHT(''0''+CONVERT(VARCHAR(100),DATEDIFF_BIG(SECOND,@Reused_TimeStamp,GETDATE())%60),2); SET @Reused_minutes = RIGHT(''0''+CONVERT(VARCHAR(100),DATEDIFF_BIG(SECOND,@Reused_TimeStamp,GETDATE())/60),2); SET @Reused_hours = RIGHT(''00''+CONVERT(VARCHAR(100),DATEDIFF_BIG(SECOND,@Reused_TimeStamp,GETDATE())/3600),2); SET @msg = ''--- Restore finished (DIFF Backup). Elapsed time: ['' + @Reused_hours+'':''+@Reused_minutes+'':''+@Reused_seconds+'']''; SET @Reused_TimeStamp = GETDATE(); RAISERROR(@msg,0,1) WITH NOWAIT' + CHAR(10) +
				'INSERT #BackupTimes (BackupType, StepNo, hours, minutes, seconds) SELECT		   ''DIFF'',   2,   @Reused_hours, @Reused_minutes, @Reused_seconds' + CHAR(10)
			
			WHEN 'LOG' THEN
				N'RESTORE LOG [' + @RestoreDBName + N'] FROM ' + dc.Disks + CHAR(10) + N' WITH ' +
				(CASE 
					WHEN rc.StepNumber = @LastStep AND @StopAt IS NOT NULL
						THEN N'STOPAT = ''' + CONVERT(varchar(23), @StopAt, 121) + N''', '
					ELSE N''
				 END) + CHAR(10) +
				ISNULL(N'STATS = '+@STATS,'') +
				CASE WHEN rc.StepNumber = @LastStep AND @Recovery = 1 THEN N', RECOVERY;' ELSE N', NORECOVERY;' END + REPLICATE(CHAR(10),2) +
				--- Calculating overall logs restore duration:
				'--- Calculating restore duration:' + CHAR(10) +
				'SET @Reused_seconds = RIGHT(''0''+CONVERT(VARCHAR(100),DATEDIFF_BIG(SECOND,@Reused_TimeStamp,GETDATE())%60),2); SET @Reused_minutes = RIGHT(''0''+CONVERT(VARCHAR(100),DATEDIFF_BIG(SECOND,@Reused_TimeStamp,GETDATE())/60),2); SET @Reused_hours = RIGHT(''00''+CONVERT(VARCHAR(100),DATEDIFF_BIG(SECOND,@Reused_TimeStamp,GETDATE())/3600),2); SET @msg = ''--- Restore finished (Log). Log No: #'+CONVERT(VARCHAR(4),rc.StepNumber-1-@HasDiff)+'. Logs Restoring Cumulative Elapsed: ['' + @Reused_hours+'':''+@Reused_minutes+'':''+@Reused_seconds+'']''; RAISERROR(@msg,0,1) WITH NOWAIT' + CHAR(10) +
				'INSERT #BackupTimes (BackupType, StepNo, hours, minutes, seconds) SELECT		   ''LOG'', ' + CONVERT(VARCHAR(4),rc.StepNumber) + ', @Reused_hours, @Reused_minutes, @Reused_seconds' + CHAR(10)
		END +
		CASE WHEN rc.StepNumber = @LastStep THEN CHAR(10) + N'--------------------------------------------------' ELSE N'' END
	FROM #RestoreChain rc
	JOIN #DiskClauses dc ON dc.StepNumber = rc.StepNumber;

	------------------------------------------------------------
	-- Info output
	------------------------------------------------------------
	DECLARE 
		@FullInfo nvarchar(200) = (SELECT 'FullFinish=' + CONVERT(varchar(19), backup_finish_date, 120) 
										  + ';' FROM #Full),
		@DiffInfo nvarchar(200) = (SELECT 'DiffFinish=' + CONVERT(varchar(19), backup_finish_date, 120) 
										  + ';' FROM #Diff),
		@LogCount int = (SELECT COUNT(*) FROM #RestoreChain WHERE BackupType='LOG');

	IF @Verbose = 1
	BEGIN
		PRINT '-- ```RESTORE CHAIN BUILDER```';
		PRINT '-- Full: ' + @FullInfo;
		IF @HasDiff = 1 PRINT '-- Diff: ' + @DiffInfo ELSE PRINT '-- Diff: (none)';
		PRINT '-- Log backups: ' + CAST(@LogCount AS varchar(12));
		PRINT '-- Log chain LSN continuity: ' + CASE WHEN @LogCount = 0 THEN 'N/A (no logs)'
												WHEN @LogsChainValid = 1 THEN 'VALID' ELSE 'BROKEN' END;

		-- Mirror the verbose info into @Script as well
		SET @Script += '-- ```RESTORE CHAIN BUILDER```' + CHAR(10)
					+  '-- Full: ' + @FullInfo + CHAR(10)
					+  '-- Diff: ' + CASE WHEN @HasDiff = 1 THEN @DiffInfo ELSE '(none);' END + CHAR(10)
					+  '-- Log backups: ' + CAST(@LogCount AS varchar(12)) + CHAR(10)
					+  '-- Log chain LSN continuity: '
					+  CASE WHEN @LogCount = 0 THEN 'N/A (no logs)'
							WHEN @LogsChainValid = 1 THEN 'VALID' ELSE 'BROKEN' END
					+  CHAR(10);
	END
	ELSE IF @LogCount > 0 AND @LogsChainValid = 0
		PRINT '-- Log chain LSN continuity: BROKEN!!!';

	IF @LogsChainValid = 0
	BEGIN
		PRINT 'WARNING: Log chain appears broken (gap detected).';
		PRINT '------------------------------------------------------------------';
		SET @Script += 'WARNING: Log chain appears broken (gap detected).' + CHAR(10)
					+  '------------------------------------------------------------------' + CHAR(10);
	END

	IF @StopAt IS NOT NULL
	BEGIN
		PRINT 'STOPAT requested: ' + CONVERT(varchar(23), @StopAt, 121);
		SET @Script += 'STOPAT requested: ' + CONVERT(varchar(23), @StopAt, 121) + CHAR(10);
	END


	------------------------------------------------------------
	-- Add TRY-CATCH statements to the restore statements
	--  (restore-header BEFORE BEGIN TRY, restore-footer AFTER END CATCH)
	------------------------------------------------------------
	DECLARE @TRY_CATCH_HEAD NVARCHAR(MAX) =
		'BEGIN TRY';
	
	-- 3) TRY header + restore commands
	DECLARE @HeaderBlock NVARCHAR(MAX) =
			'----------------------------------------Restore statements begin------------------------------' + CHAR(10) +
			IIF(@First_Parent_Procedure_Iteration = 1 OR @ResultSet_is_for_single_Database = 1,'DROP TABLE IF EXISTS #BackupTimes; ' +
			'CREATE TABLE #BackupTimes(BackupType varchar(4) NOT NULL, StepNo INT, hours VARCHAR(3), minutes VARCHAR(2), seconds VARCHAR(2));' + CHAR(10) +
			'DECLARE @StepNo INT, @msg NVARCHAR(2000), @Initial_TimeStamp DATETIME2(3) = GETDATE(), @Reused_TimeStamp DATETIME2(3) = GETDATE(), @Overall_seconds VARCHAR(2), @Overall_minutes VARCHAR(2), @Overall_hours VARCHAR(3), @Reused_seconds VARCHAR(2), @Reused_minutes VARCHAR(2), @Reused_hours VARCHAR(3);' + CHAR(10),'') +
			'SET @msg = ''Start restore procedure at: ''+CONVERT(VARCHAR(25),@Reused_TimeStamp,121); RAISERROR(@msg,0,1) WITH NOWAIT' + REPLICATE(CHAR(10),2) +
			@TRY_CATCH_HEAD;  -- includes restore-header + BEGIN TRY

	DECLARE @TRY_CATCH_TAIL NVARCHAR(MAX) =
		'END TRY' + CHAR(10) +
		'BEGIN CATCH' + CHAR(10) +
		REPLICATE(CHAR(9),4) + 'SET @msg = ERROR_MESSAGE(); RAISERROR(@msg,16,1); ' +
		IIF(@Recover_Database_On_Error = 1,
			REPLICATE(CHAR(9),4) + 'SET @msg = ''Restore failed at step ''+CONVERT(VARCHAR(5),@StepNo)+''.''+IIF(@StepNo>1,'' Database will be recovered.'','''')' + CHAR(10),		
			REPLICATE(CHAR(9),4) + 'SET @msg = ''Restore failed at step ''+CONVERT(VARCHAR(5),@StepNo)+''. Restore finished for the database.'' RAISERROR(@msg,16,1) ' + CHAR(10)
		) +
		IIF(@Recover_Database_On_Error = 1,
		REPLICATE(CHAR(9),4) + 'IF (@StepNo > 1)' + REPLICATE(CHAR(9),1) + 'RESTORE DATABASE ' + QUOTENAME(@RestoreDBName) + ' WITH RECOVERY' + CHAR(10),
		'') +
		'END CATCH' + REPLICATE(CHAR(10),2) +
		'SET @Overall_seconds = RIGHT(''0''+CONVERT(VARCHAR(100),DATEDIFF_BIG(SECOND,@Initial_TimeStamp,GETDATE())%60),2); SET @Overall_minutes = RIGHT(''0''+CONVERT(VARCHAR(100),DATEDIFF_BIG(SECOND,@Initial_TimeStamp,GETDATE())/60%60),2); SET @Overall_hours = RIGHT(''00''+CONVERT(VARCHAR(100),DATEDIFF_BIG(SECOND,@Initial_TimeStamp,GETDATE())/3600),2);' + 
		'SET @msg=''Restore Summary:''+CHAR(10)+''DB Name: ''+''['+@RestoreDBName+']'''+
					'+ISNULL(CHAR(10)+''FULL    Duration: ''+(SELECT ''['' + hours+'':''+minutes+'':''+seconds+'']'' FROM #BackupTimes WHERE BackupType=''FULL''),'''')'+
					'+ISNULL(CHAR(10)+''DIFF    Duration: ''+(SELECT ''['' + hours+'':''+minutes+'':''+seconds+'']'' FROM #BackupTimes WHERE BackupType=''DIFF''),'''')'+
					'+ISNULL(CHAR(10)+''LOG     Duration: ''+(SELECT TOP 1 ''['' + @Reused_hours+'':''+@Reused_minutes+'':''+@Reused_seconds+'']'' FROM #BackupTimes WHERE BackupType=''LOG''),'''')'+
					'+ISNULL(CHAR(10)+''Overall Duration: ''+(SELECT TOP 1 ''['' + @Overall_hours+'':''+@Overall_minutes+'':''+@Overall_seconds+'']''    FROM #BackupTimes),'''')' + 
		'SET @msg += CHAR(10) + ''Restored DB Size: '' + CONVERT(VARCHAR(20), CAST((SELECT SUM(CAST(size AS BIGINT)) * 8.0 / 1024 / 1024 FROM sys.master_files WHERE database_id = DB_ID(''' + @RestoreDBName + ''')) AS DECIMAL(18,2))) + '' GB'' ' + 
		'RAISERROR(@msg,0,1) WITH NOWAIT; TRUNCATE TABLE #BackupTimes;' + CHAR(10) +
		'----------------------------------------Restore statements end--------------------------------';

	------------------------------------------------------------
	-- Giving the script in the STDOUT (PRINT)
	------------------------------------------------------------
	-- xp_create_subdir section
	IF @create_datafile_dirs = 1
		IF @create_directories IS NULL 
		BEGIN
			PRINT '--** Database does not exist on the instance, thus create directories statements were skipped.';
			PRINT '';
			SET @Script += '--** Database does not exist on the instance, thus create directories statements were skipped.' + CHAR(10) + CHAR(10);
		END
		ELSE 
		BEGIN
			PRINT @create_directories;
			PRINT '';  -- one empty line after last xp_create_subdir
			SET @Script += @create_directories + CHAR(10) + CHAR(10);
			IF @Execute = 1 EXEC(@create_directories);
		END

	-- Preparatory script section (printed/plain)
	IF @Preparatory_Script_Before_Restore IS NOT NULL AND LEN(@Preparatory_Script_Before_Restore) > 0
	BEGIN
		PRINT '';  -- empty line
		PRINT '------------------------------------Preparatory Script Before Restore-------------------------';
		PRINT @Preparatory_Script_Before_Restore;
		PRINT '----------------------------------------------------------------------------------------------';
		PRINT '';  -- empty line

		SET @Script += CHAR(10) +
			'------------------------------------Preparatory Script Before Restore-------------------------' + CHAR(10) +
			@Preparatory_Script_Before_Restore + CHAR(10) +
			'----------------------------------------------------------------------------------------------' + CHAR(10) +
			CHAR(10);
	END

	-- restore body (plain script) – header now comes from TRY/CATCH, do NOT print the old line
	-- REMOVE these two lines:
	-- PRINT REPLICATE('-',40)+'Restore statements begin'+REPLICATE('-',30)
	-- SET @Script += REPLICATE('-',40) + 'Restore statements begin' + REPLICATE('-',30) + CHAR(10);
	-- keep only step lines and commands:
	DECLARE @i int = 1, @max int = (SELECT MAX(StepNumber) FROM #RestoreChain), @Cmd nvarchar(max);
	WHILE @i <= @max
	BEGIN
		SELECT @Cmd = RestoreCommand FROM #RestoreChain WHERE StepNumber = @i;
		PRINT '-- Step ' + CAST(@i AS varchar(10));
		PRINT @Cmd;
		SET @Script += '-- Step ' + CAST(@i AS varchar(10)) + CHAR(10) + ISNULL(@Cmd,N'') + CHAR(10);
		SET @i += 1;
	END
	-- footer also comes from TRY/CATCH now, so DROP the old print:
	-- PRINT REPLICATE('-',40)+'Restore statements end'+REPLICATE('-',32)
	-- SET @Script += REPLICATE('-',40) + 'Restore statements end' + REPLICATE('-',32) + CHAR(10);

	-- Complementary script section (printed/plain)
	IF @Complementary_Script_After_Restore IS NOT NULL AND LEN(@Complementary_Script_After_Restore) > 0
	BEGIN
		PRINT '';  -- empty line
		PRINT '-----------------------------------Complementary Script After Restore-----------------------';
		PRINT @Complementary_Script_After_Restore;
		PRINT '----------------------------------------------------------------------------------------------';
		PRINT '';  -- empty line

		SET @Script += CHAR(10) +
			'-----------------------------------Complementary Script After Restore-----------------------' + CHAR(10) +
			@Complementary_Script_After_Restore + CHAR(10) +
			'----------------------------------------------------------------------------------------------' + CHAR(10) +
			CHAR(10);
	END

	PRINT '--##############################################################--' + REPLICATE(CHAR(10),2);
	SET @Script += '--##############################################################--' + REPLICATE(CHAR(10),2);

	------------------------------------------------------------
	-- Build @SQLCMD_Script to mirror SELECT dt.Script
	------------------------------------------------------------
	-- 0) :connect and one empty line
	IF ISNULL(@SQLCMD_Connect_Conn_String,'') <> ''
	BEGIN
		SET @SQLCMD_Script += ':connect ' + @SQLCMD_Connect_Conn_String + CHAR(10);
		--SET @SQLCMD_Script += CHAR(10);  -- exactly one empty line
	END

	-- 1) Preparatory section in SQLCMD script
	IF @Preparatory_Script_Before_Restore IS NOT NULL AND @Preparatory_Script_Before_Restore <> N''
	BEGIN
		SET @SQLCMD_Script += CHAR(10) +
			'------------------------------------Preparatory Script Before Restore-------------------------' + CHAR(10);

		DECLARE curBefore CURSOR LOCAL FAST_FORWARD FOR
			SELECT LineText, ordinal
			FROM dbo.fn_SplitStringByLine(@Preparatory_Script_Before_Restore)
			ORDER BY ordinal;

		OPEN curBefore;
		FETCH NEXT FROM curBefore INTO @tmpLine, @ord;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @SQLCMD_Script += ISNULL(@tmpLine,'') + CHAR(10);
			FETCH NEXT FROM curBefore INTO @tmpLine, @ord;
		END
		CLOSE curBefore;
		DEALLOCATE curBefore;

		SET @SQLCMD_Script +=
			'----------------------------------------------------------------------------------------------' + CHAR(10) +
			CHAR(10);
	END

	-- 2) Blank line + xp_create_subdir + blank line
	SET @SQLCMD_Script += CHAR(10);

	IF @create_directories IS NOT NULL AND @create_directories <> N''
	BEGIN
		DECLARE curDirs CURSOR LOCAL FAST_FORWARD FOR
			SELECT LineText, ordinal
			FROM dbo.fn_SplitStringByLine(@create_directories)
			ORDER BY ordinal;

		OPEN curDirs;
		FETCH NEXT FROM curDirs INTO @tmpLine, @ord;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @SQLCMD_Script += ISNULL(@tmpLine,'') + CHAR(10);
			FETCH NEXT FROM curDirs INTO @tmpLine, @ord;
		END
		CLOSE curDirs;
		DEALLOCATE curDirs;

		SET @SQLCMD_Script += CHAR(10);  -- one empty line after last xp_create_subdir
	END


	DECLARE curHead CURSOR LOCAL FAST_FORWARD FOR
		SELECT LineText, ordinal
		FROM dbo.fn_SplitStringByLine(@HeaderBlock)
		ORDER BY ordinal;

	OPEN curHead;
	FETCH NEXT FROM curHead INTO @tmpLine, @ord;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @SQLCMD_Script += ISNULL(@tmpLine,'') + CHAR(10);
		FETCH NEXT FROM curHead INTO @tmpLine, @ord;
	END
	CLOSE curHead;
	DEALLOCATE curHead;

	-- per-step commands
	DECLARE @Step INT = 1, @MaxStep INT = (SELECT MAX(StepNumber) FROM #RestoreChain);
	WHILE @Step <= @MaxStep
	BEGIN
		SET @SQLCMD_Script += REPLICATE(CHAR(9),4)+'------------------- Step ' + CAST(@Step AS varchar(10)) + '/' + CONVERT(VARCHAR(4),@MaxStep) + ' -------------------' + CHAR(10);
		SET @SQLCMD_Script += REPLICATE(CHAR(9),4)+'SET @StepNo = '+CAST(@Step AS varchar(10)) + CHAR(10);

		DECLARE @RestoreCmd NVARCHAR(MAX);
		SELECT @RestoreCmd = RestoreCommand
		FROM #RestoreChain
		WHERE StepNumber = @Step;

		IF @RestoreCmd IS NOT NULL
		BEGIN
			DECLARE curCmd CURSOR LOCAL FAST_FORWARD FOR
				SELECT LineText, ordinal
				FROM dbo.fn_SplitStringByLine(@RestoreCmd)
				ORDER BY ordinal;

			OPEN curCmd;
			FETCH NEXT FROM curCmd INTO @tmpLine, @ord;
			WHILE @@FETCH_STATUS = 0
			BEGIN
				SET @SQLCMD_Script += REPLICATE(CHAR(9),4) + ISNULL(@tmpLine,'') + CHAR(10);
				FETCH NEXT FROM curCmd INTO @tmpLine, @ord;
			END
			CLOSE curCmd;
			DEALLOCATE curCmd;
		END

		SET @Step += 1;
	END

	-- 4) footer + TRY_CATCH_TAIL (includes END CATCH + restore-footer)
	DECLARE @FooterBlock NVARCHAR(MAX) = @TRY_CATCH_TAIL;

	DECLARE curFoot CURSOR LOCAL FAST_FORWARD FOR
		SELECT LineText, ordinal
		FROM dbo.fn_SplitStringByLine(@FooterBlock)
		ORDER BY ordinal;

	OPEN curFoot;
	FETCH NEXT FROM curFoot INTO @tmpLine, @ord;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @SQLCMD_Script += ISNULL(@tmpLine,'') + CHAR(10);
		FETCH NEXT FROM curFoot INTO @tmpLine, @ord;
	END
	CLOSE curFoot;
	DEALLOCATE curFoot;

	-- 5) Complementary section in SQLCMD script
	IF @Complementary_Script_After_Restore IS NOT NULL AND @Complementary_Script_After_Restore <> N''
	BEGIN
		SET @SQLCMD_Script += CHAR(10) +
			'-----------------------------------Complementary Script After Restore-----------------------' + CHAR(10);

		DECLARE curAfter CURSOR LOCAL FAST_FORWARD FOR
			SELECT LineText, ordinal
			FROM dbo.fn_SplitStringByLine(@Complementary_Script_After_Restore)
			ORDER BY ordinal;

		OPEN curAfter;
		FETCH NEXT FROM curAfter INTO @tmpLine, @ord;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @SQLCMD_Script += ISNULL(@tmpLine,'') + CHAR(10);
			FETCH NEXT FROM curAfter INTO @tmpLine, @ord;
		END
		CLOSE curAfter;
		DEALLOCATE curAfter;

		SET @SQLCMD_Script +=
			'----------------------------------------------------------------------------------------------' + CHAR(10) +
			CHAR(10);
	END

	-- 6) trailing GO / blanks
	IF ISNULL(@SQLCMD_Connect_Conn_String,'') <> ''
	BEGIN
		SET @SQLCMD_Script += 'GO' + CHAR(10) + CHAR(10) + CHAR(10);
	END



	------------------------------------------------------------
	-- Substituting variables inside variables that have been dynamically defined with other variables:
	------------------------------------------------------------

	-- Replace in order from longest to shortest variable names to avoid partial matches
	-- Only replace if the variable is not NULL
	
	IF @SQLCMD_Connect_Conn_String IS NOT NULL
	BEGIN
		SELECT @Script = REPLACE(@Script, '@SQLCMD_Connect_Conn_String', '''' + @SQLCMD_Connect_Conn_String + '''')
			, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@SQLCMD_Connect_Conn_String', '''' + @SQLCMD_Connect_Conn_String + '''');
	END
	
	IF @Complementary_Script_After_Restore IS NOT NULL
	BEGIN
		SELECT @Script = REPLACE(@Script, '@Complementary_Script_After_Restore', '''' + REPLACE(@Complementary_Script_After_Restore, '''', '''''') + '''')
			, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@Complementary_Script_After_Restore', '''' + REPLACE(@Complementary_Script_After_Restore, '''', '''''') + '''');
	END
	
	IF @Preparatory_Script_Before_Restore IS NOT NULL
	BEGIN
		SELECT @Script = REPLACE(@Script, '@Preparatory_Script_Before_Restore', '''' + REPLACE(@Preparatory_Script_Before_Restore, '''', '''''') + '''')
			, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@Preparatory_Script_Before_Restore', '''' + REPLACE(@Preparatory_Script_Before_Restore, '''', '''''') + '''');
	END
	
	IF @new_backups_parent_dir IS NOT NULL
	BEGIN
		SELECT @Script = REPLACE(@Script, '@new_backups_parent_dir', '''' + REPLACE(@new_backups_parent_dir, '''', '''''') + '''')
			, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@new_backups_parent_dir', '''' + REPLACE(@new_backups_parent_dir, '''', '''''') + '''');
	END
	
	IF @RestoreUpTo_TIMESTAMP IS NOT NULL
	BEGIN
		SELECT @Script = REPLACE(@Script, '@RestoreUpTo_TIMESTAMP', '''' + CONVERT(NVARCHAR(256), @RestoreUpTo_TIMESTAMP, 121) + '''')
			, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@RestoreUpTo_TIMESTAMP', '''' + CONVERT(NVARCHAR(256), @RestoreUpTo_TIMESTAMP, 121) + '''');
	END
	
	IF @StopAt IS NOT NULL
	BEGIN
		SELECT @Script = REPLACE(@Script, '@StopAt', '''' + CONVERT(NVARCHAR(256), @StopAt, 121) + '''')
			, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@StopAt', '''' + CONVERT(NVARCHAR(256), @StopAt, 121) + '''');
	END
	
	IF @Restore_LogPath IS NOT NULL
	BEGIN
		SELECT @Script = REPLACE(@Script, '@Restore_LogPath', '''' + @Restore_LogPath + '''')
			, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@Restore_LogPath', '''' + @Restore_LogPath + '''');
	END
	
	IF @Restore_DataPath IS NOT NULL
	BEGIN
		SELECT @Script = REPLACE(@Script, '@Restore_DataPath', '''' + @Restore_DataPath + '''')
			, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@Restore_DataPath', '''' + @Restore_DataPath + '''');
	END
	
	IF @RestoreDBName IS NOT NULL
	BEGIN
		SELECT @Script = REPLACE(@Script, '@RestoreDBName', @RestoreDBName)
			, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@RestoreDBName', @RestoreDBName);
	END
	
	-- @DatabaseName is never NULL, always replace
	SELECT @Script = REPLACE(@Script, '@DatabaseName', @DatabaseName)
		, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@DatabaseName', @DatabaseName);
	
	-- Bit parameters: cast to varchar (always replace, bits cannot be NULL)
	SELECT @Script = REPLACE(@Script, '@Recover_Database_On_Error', CAST(@Recover_Database_On_Error AS VARCHAR(1)))
		, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@Recover_Database_On_Error', CAST(@Recover_Database_On_Error AS VARCHAR(1)));
	
	SELECT @Script = REPLACE(@Script, '@create_datafile_dirs', CAST(@create_datafile_dirs AS VARCHAR(1)))
		, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@create_datafile_dirs', CAST(@create_datafile_dirs AS VARCHAR(1)));
	
	SELECT @Script = REPLACE(@Script, '@IncludeDiffs', CAST(@IncludeDiffs AS VARCHAR(1)))
		, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@IncludeDiffs', CAST(@IncludeDiffs AS VARCHAR(1)));
	
	SELECT @Script = REPLACE(@Script, '@IncludeLogs', CAST(@IncludeLogs AS VARCHAR(1)))
		, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@IncludeLogs', CAST(@IncludeLogs AS VARCHAR(1)));
	
	SELECT @Script = REPLACE(@Script, '@WithReplace', CAST(@WithReplace AS VARCHAR(1)))
		, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@WithReplace', CAST(@WithReplace AS VARCHAR(1)));
	
	SELECT @Script = REPLACE(@Script, '@Recovery', CAST(@Recovery AS VARCHAR(1)))
		, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@Recovery', CAST(@Recovery AS VARCHAR(1)));
	
	SELECT @Script = REPLACE(@Script, '@Verbose', CAST(@Verbose AS VARCHAR(1)))
		, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@Verbose', CAST(@Verbose AS VARCHAR(1)));
	
	SELECT @Script = REPLACE(@Script, '@Execute', CAST(@Execute AS VARCHAR(1)))
		, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@Execute', CAST(@Execute AS VARCHAR(1)));

	------------------------------------------------------------
	-- Expose both aggregated versions
	------------------------------------------------------------
	--SELECT @Script AS FullScript_Plain;
	IF @Failure_Mark = 0
	BEGIN
		IF @ResultSet_is_for_single_Database = 1
		BEGIN
			SELECT LineText Script FROM dbo.fn_SplitStringByLine(@SQLCMD_Script);
			DROP TABLE ##Total_Output
		END
		ELSE
			INSERT ##Total_Output (Output)
			SELECT LineText Script FROM dbo.fn_SplitStringByLine(@SQLCMD_Script);	
	END

END
GO

EXEC dbo.usp_build_one_db_restore_script @DatabaseName = 'archive99',		-- sysname
                                         @RestoreDBName = '@DatabaseName',	-- Use to restore DatabaseName_2
										 @Restore_DataPath = '',			-- Uses original database path if not specified
										 @Restore_LogPath = '',				-- Uses original database path if not specified
										 @StopAt = '',						-- datetime
                                         @WithReplace = 1,					-- bit
										 @IncludeLogs = 1,
										 @IncludeDiffs = 1,
										 --@RestoreUpTo_TIMESTAMP = '2025-11-02 18:59:10.553',
										 @Recovery = 1,
										 @Recover_Database_On_Error = 1,
										 @new_backups_parent_dir = '',--'D:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\',
											--'REPLACE(Devices,''R:'',''\\''+CONVERT(NVARCHAR(256),SERVERPROPERTY(''MachineName'')))',
										 @check_backup_file_existance = 1,
										 @Preparatory_Script_Before_Restore = '',
										 @Complementary_Script_After_Restore = '--ALTER AVAILABILITY GROUP FAlgoDBAVG ADD DATABASE [@RestoreDBName]',
										 @Verbose = 0,
										 @SQLCMD_Connect_Conn_String = ''
--\\fdbdrbkpdsk\DBDR\FAlgoDB\TapeBackups\FAlgoDBCLU0$FAlgoDBAVG						 
GO

--SELECT dbo.udf_BASE_NAME('\\fdbdrbkpdsk\DBDR\'),dbo.udf_PARENT_DIR('\\fdbdrbkpdsk\DBDR\')

--SELECT * FROM dbo.user_dm_os_file_exists('N\\fdbdrbkpdsk',N'DBDR')