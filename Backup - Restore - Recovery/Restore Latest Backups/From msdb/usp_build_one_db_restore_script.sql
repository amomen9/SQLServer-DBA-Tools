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
    WHERE LTRIM(RTRIM(T.N.value('.', 'nvarchar(max)'))) <> ''
);
GO

-- Example Usage:
-- DECLARE @MyScript nvarchar(max) = N'SELECT * FROM sys.databases;'+CHAR(13)+CHAR(10)+N'SELECT * FROM sys.objects;';
-- SELECT * FROM dbo.fn_SplitStringByLine(@MyScript);

CREATE OR ALTER PROC usp_build_one_db_restore_script
		@DatabaseName			sysname,		-- Source database
		@RestoreDBName			sysname = NULL,		-- Destination database
		@create_datafile_dirs	BIT = 1,		-- Create original parent directories of the database files in target
		@Restore_DataPath		NVARCHAR(1000) = NULL,
		@Restore_LogPath		NVARCHAR(1000) = NULL,
		@StopAt		DATETIME		= NULL,		-- Point-in-time inside last DIFF/LOG
		@WithReplace			BIT	= 0,		-- Include REPLACE on RESTORE DATABASE
		@IncludeLogs			BIT	= 1,		-- Include log backups	
		@IncludeDiffs			BIT = 1,		-- Include differential backups
		@Recovery				BIT = 0,		-- Specify whether to eventually recover the database or not 
		@RestoreUpTo_TIMESTAMP 
					DATETIME2(3)	= NULL,		-- Backup files started after this TIMESTAMP will be excluded 
		@backup_path_replace_string				
					NVARCHAR(4000)	= NULL,		-- Write t-sql formula to be executed on the backup files full path stored in the
												-- parameter "Devices". 
												-- Example: REPLACE(Devices,'R:\','\\'+CONVERT(NVARCHAR(256),SERVERPROPERTY('MachineName')))

		@BeforeRestoreScript NVARCHAR(MAX) = NULL,
												-- Script to execute before restore script
		@AfterRestoreScript NVARCHAR(MAX) = NULL,
												-- Script to execute after restore script												
		@Execute				BIT	= 0,		-- 1 = execute the produced script
		@Verbose				BIT = 1,		-- If executing and @Verbose = 1 the produced script will also be printed.
		@SQLCMD_Connect_Clause NVARCHAR(MAX) = NULL	
												-- Connection string to be written in front of :connect if you want to
												-- execute the query on the target machine using SQLCMD Mode
AS
BEGIN
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
	DECLARE @MoveClauses NVARCHAR(MAX)
    DECLARE @create_directories NVARCHAR(MAX)
	DECLARE @SQL NVARCHAR(MAX)
	
	------------------------------------------------------------
	-- Parameter validation
	------------------------------------------------------------

	IF DB_ID(@DatabaseName) IS NULL AND @Verbose = 1
		PRINT 'Note: Target DB does not currently exist (restore will create it).';
	
	IF @StopAt = '' SET @StopAt = NULL
	IF @RestoreUpTo_TIMESTAMP = '' SET @RestoreUpTo_TIMESTAMP = NULL
	IF ISNULL(@RestoreDBName,'') = '' SET @RestoreDBName = @DatabaseName

	------------------------------------------------------------
	-- Header
	------------------------------------------------------------
	PRINT '----------- ' + 'Database: ' + @DatabaseName + ' --> ' + @RestoreDBName + ' ---------------------------------';

	------------------------------------------------------------
	-- FULL backup (latest non copy_only)
	------------------------------------------------------------
	IF OBJECT_ID('tempdb..#Full') IS NOT NULL DROP TABLE #Full;
	SELECT TOP (1)
		  b.backup_set_id
		, b.database_name
		, b.backup_start_date
		, b.backup_finish_date
		, b.first_lsn
		, b.last_lsn
		, b.checkpoint_lsn
		, b.database_backup_lsn
		, Devices = STRING_AGG(mf.physical_device_name, N',')
	INTO #Full
	FROM msdb.dbo.backupset b
	JOIN msdb.dbo.backupmediafamily mf ON b.media_set_id = mf.media_set_id
	WHERE b.database_name = @DatabaseName
	  AND b.[type] = 'D'
	  AND b.is_copy_only = 0
	  AND mf.mirror = 0
	  AND b.backup_start_date < COALESCE(@RestoreUpTo_TIMESTAMP, b.backup_start_date)
	GROUP BY b.backup_set_id, b.database_name, b.backup_start_date, b.backup_finish_date,
			 b.first_lsn, b.last_lsn, b.checkpoint_lsn, b.database_backup_lsn
	ORDER BY b.backup_finish_date DESC;

	IF NOT EXISTS (SELECT 1 FROM #Full)
	BEGIN
		RAISERROR('No FULL backup found for %s.',16,1,@DatabaseName);
		RETURN;
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
	SELECT TOP (1)
		  b.backup_set_id
		, b.backup_start_date
		, b.backup_finish_date
		, b.first_lsn
		, b.last_lsn
		, b.differential_base_lsn
		, Devices = STRING_AGG(mf.physical_device_name, N',')
	INTO #Diff
	FROM msdb.dbo.backupset b
	JOIN msdb.dbo.backupmediafamily mf ON b.media_set_id = mf.media_set_id
	CROSS JOIN #Full f
	WHERE b.database_name = @DatabaseName
	  AND b.[type] = 'I'
	  AND b.differential_base_lsn = f.checkpoint_lsn
	  AND mf.mirror = 0
	  AND b.backup_finish_date > f.backup_finish_date
	  AND @IncludeDiffs = 1
	  AND b.backup_start_date < COALESCE(@RestoreUpTo_TIMESTAMP, b.backup_start_date)
	GROUP BY b.backup_set_id, b.backup_start_date, b.backup_finish_date,
			 b.first_lsn, b.last_lsn, b.differential_base_lsn
	ORDER BY b.backup_finish_date DESC;

	------------------------------------------------------------
	-- LOG backups after base (Diff if exists else Full)
	------------------------------------------------------------
	DECLARE @BaseLastLSN numeric(25,0), @BaseFinish datetime;
	SELECT @BaseLastLSN = COALESCE((SELECT last_lsn FROM #Diff),(SELECT last_lsn FROM #Full));
	SELECT @BaseFinish  = COALESCE((SELECT backup_finish_date FROM #Diff),(SELECT backup_finish_date FROM #Full));

	IF OBJECT_ID('tempdb..#Logs') IS NOT NULL DROP TABLE #Logs;
	SELECT
		  b.backup_set_id
		, b.backup_start_date
		, b.backup_finish_date
		, b.first_lsn
		, b.last_lsn
		, b.database_backup_lsn
		, Devices = STRING_AGG(mf.physical_device_name, N',')
	INTO #Logs
	FROM msdb.dbo.backupset b
	JOIN msdb.dbo.backupmediafamily mf ON b.media_set_id = mf.media_set_id
	WHERE b.database_name = @DatabaseName
	  AND b.[type] = 'L'
	  AND mf.mirror = 0
	  AND b.backup_finish_date > @BaseFinish
	  AND @IncludeLogs = 1
	  AND b.backup_start_date < COALESCE(@RestoreUpTo_TIMESTAMP, b.backup_start_date)
	GROUP BY b.backup_set_id, b.backup_start_date, b.backup_finish_date,
			 b.first_lsn, b.last_lsn, b.database_backup_lsn
	ORDER BY b.first_lsn;

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
	-- Update restore chain backup paths using 
	-- @backup_path_replace_string
	------------------------------------------------------------
	IF ISNULL(@backup_path_replace_string,'') <> ''
	BEGIN
		SET @SQL =
		'
			UPDATE #RestoreChain SET Devices = ' + @backup_path_replace_string + '
		'
		EXEC(@SQL)
	END

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
	--SELECT @MoveClauses =
	--	STUFF((
	--		SELECT ',' + /*CHAR(10)*/ + ' MOVE N''' + mf.name + ''' TO N''' + mf.physical_name + ''''
	--		FROM sys.master_files AS mf
	--		WHERE mf.database_id = DB_ID(@DatabaseName)
	--		ORDER BY mf.type, mf.file_id
	--		FOR XML PATH(''), TYPE).value('.','nvarchar(max)')
	--	,1,2,'') + ',' + CHAR(10);
SELECT @MoveClauses =
    STUFF((
        SELECT CHAR(10) + CHAR(9) + 'MOVE N''' + mf.name + ''' TO N''' +
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
				N'STATS = 5' + @ReplaceClause + 
				CASE WHEN rc.StepNumber = @LastStep AND @Recovery = 1 THEN N', RECOVERY;' ELSE N', NORECOVERY;' END
			WHEN 'DIFF' THEN
				N'RESTORE DATABASE [' + @RestoreDBName + N'] FROM ' + dc.Disks + CHAR(10) + N' WITH ' +
				(CASE 
					WHEN rc.StepNumber = @LastStep AND @StopAt IS NOT NULL AND @HasLogs = 0
						THEN N'STOPAT = ''' + CONVERT(varchar(23), @StopAt, 121) + N''', '
					ELSE N''
				 END) + CHAR(10) +
				N'STATS = 5' +
				CASE WHEN rc.StepNumber = @LastStep AND @HasLogs = 0 AND @Recovery = 1 THEN N', RECOVERY;' ELSE N', NORECOVERY;' END
			WHEN 'LOG' THEN
				N'RESTORE LOG [' + @RestoreDBName + N'] FROM ' + dc.Disks + CHAR(10) + N' WITH ' +
				(CASE 
					WHEN rc.StepNumber = @LastStep AND @StopAt IS NOT NULL
						THEN N'STOPAT = ''' + CONVERT(varchar(23), @StopAt, 121) + N''', '
					ELSE N''
				 END) + CHAR(10) +
				N'STATS = 5' +
				CASE WHEN rc.StepNumber = @LastStep AND @Recovery = 1 THEN N', RECOVERY;' ELSE N', NORECOVERY;' END
		END
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
	END
	ELSE IF @LogCount > 0 AND @LogsChainValid = 0
		PRINT '-- Log chain LSN continuity: BROKEN!!!';

	IF @LogsChainValid = 0
	BEGIN
		PRINT 'WARNING: Log chain appears broken (gap detected).';
		PRINT '------------------------------------------------------------------';
	END

	IF @StopAt IS NOT NULL
		PRINT 'STOPAT requested: ' + CONVERT(varchar(23), @StopAt, 121);

	------------------------------------------------------------
	-- Giving the script in the STDOUT (PRINT)
	------------------------------------------------------------
	-- Print create directories commands
	IF @create_datafile_dirs = 1
	IF @create_directories IS NULL PRINT '--** Database does not exist on the instance, thus create directories statements were skipped.' + CHAR(10)
	ELSE 
	BEGIN
		PRINT @create_directories + CHAR(10)
		IF @Execute = 1 EXEC(@create_directories)
	END

	PRINT @BeforeRestoreScript
	DECLARE @i int = 1, @max int = (SELECT MAX(StepNumber) FROM #RestoreChain), @Cmd nvarchar(max);
	PRINT REPLICATE('-',40)+'Restore statements begin'+REPLICATE('-',30)
	WHILE @i <= @max
	BEGIN
		SELECT @Cmd = RestoreCommand FROM #RestoreChain WHERE StepNumber = @i;
		PRINT '-- Step ' + CAST(@i AS varchar(10));
		PRINT @Cmd;
		SET @i += 1;
	END
	PRINT REPLICATE('-',40)+'Restore statements end'+REPLICATE('-',32)
	PRINT @AfterRestoreScript
	PRINT '--##############################################################--'+REPLICATE(CHAR(10),2);

	------------------------------------------------------------
	-- Giving the script as a result set
	------------------------------------------------------------
	
	SELECT dt.Script FROM 
	(
		SELECT 0 OverallStep, ':connect '+@SQLCMD_Connect_Clause Script, 1 StepNumber, 1 SortOrder
		WHERE ISNULL(@SQLCMD_Connect_Clause,'') <> ''
		UNION ALL
		SELECT 0 OverallStep, '', 2 StepNumber, 2 SortOrder
		WHERE ISNULL(@SQLCMD_Connect_Clause,'') <> ''
		-----------------------------
		UNION ALL		
		SELECT 1 OverallStep, LineText, 1 StepNumber, ordinal SortOrder
		FROM dbo.fn_SplitStringByLine(@BeforeRestoreScript)
		-----------------------------
		UNION ALL
		SELECT 2 OverallStep, '', 1 StepNumber, 1 SortOrder
		UNION ALL
		SELECT 2 OverallStep, LineText, 2 StepNumber, ordinal SortOrder
		FROM dbo.fn_SplitStringByLine(@create_directories)
		UNION ALL
		SELECT 2 OverallStep, '', 3 StepNumber, 1 SortOrder
		-----------------------------
		UNION ALL
		SELECT 3 OverallStep, REPLICATE('-',40)+'Restore statements begin'+REPLICATE('-',30), 0, 0
		UNION ALL
		SELECT 3 OverallStep, Script, Commands.StepNumber, Commands.SortOrder
		FROM
		(
			SELECT
				'-- Step ' + CAST(StepNumber AS varchar(10)) AS Script,
				StepNumber,
				0 AS SortOrder
			FROM #RestoreChain
			UNION ALL
			SELECT
				fssl.LineText,
				StepNumber,
				fssl.ordinal AS SortOrder
			FROM #RestoreChain rc
			CROSS APPLY dbo.fn_SplitStringByLine(rc.RestoreCommand) fssl
		) AS Commands
		WHERE ISNULL(@SQLCMD_Connect_Clause,'') = '' OR 
			(ISNULL(@SQLCMD_Connect_Clause,'') <> '' AND TRIM(Commands.Script)<>'GO')
		UNION ALL
		SELECT 4 OverallStep, REPLICATE('-',40)+'Restore statements end'+REPLICATE('-',32), 0, 0
		UNION ALL
		-----------------------------------------------------------------
		SELECT 4, LineText, 1,	ordinal
		FROM dbo.fn_SplitStringByLine(@AfterRestoreScript)
		-----------------------------------------------------------------
		UNION ALL
		SELECT 5 OverallStep, v.Script, 1, 1
		FROM (VALUES ('GO'), (''), ('')) AS v(Script)
		WHERE ISNULL(@SQLCMD_Connect_Clause,'') <> ''
	) dt

	ORDER BY dt.OverallStep, StepNumber, SortOrder

END
GO



EXEC dbo.usp_build_one_db_restore_script @DatabaseName = 'AlgorithmicTrading',	-- sysname
                                         @RestoreDBName = '',
										 @Restore_DataPath = '',
										 @Restore_LogPath = '',
										 @StopAt = '',				-- datetime
                                         @WithReplace = 1,				-- bit
										 @IncludeLogs = 1,
										 @IncludeDiffs = 1,
										 @RestoreUpTo_TIMESTAMP = '2025-11-02 18:59:10.553',
										 @Recovery = 1,
										 @backup_path_replace_string = 'REPLACE(Devices,''R:\'',''\\fdbdrbkpdsk\DBDR\FAlgoDB\Tape'')',
											--'REPLACE(Devices,''R:'',''\\''+CONVERT(NVARCHAR(256),SERVERPROPERTY(''MachineName'')))',
										 @BeforeRestoreScript = '',
										 @AfterRestoreScript = '',
										 @Verbose = 0,
										 @SQLCMD_Connect_Clause = ''
--\\fdbdrbkpdsk\DBDR\FAlgoDB\TapeBackups\FAlgoDBCLU0$FAlgoDBAVG						 
GO