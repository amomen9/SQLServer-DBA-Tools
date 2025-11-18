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
	-- keep empties: no WHERE
);
GO

-- Example Usage:
-- DECLARE @MyScript nvarchar(max) = N'SELECT * FROM sys.databases;'+CHAR(13)+CHAR(10)+N'SELECT * FROM sys.objects;';
-- SELECT * FROM dbo.fn_SplitStringByLine(@MyScript);

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
		@RestoreUpTo_TIMESTAMP				DATETIME2(3) = NULL,
		@backup_path_replace_string			NVARCHAR(4000) = NULL,
		@Recover_Database_On_Error			BIT = 0,
		@Preparatory_Script_Before_Restore	NVARCHAR(MAX) = NULL,
		@Complementary_Script_After_Restore	NVARCHAR(MAX) = NULL,
		@Execute							BIT	= 0,
		@Verbose							BIT = 1,
		@SQLCMD_Connect_Conn_String			NVARCHAR(MAX) = NULL
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
	DECLARE @MoveClauses NVARCHAR(MAX);
    DECLARE @create_directories NVARCHAR(MAX);
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @Script NVARCHAR(MAX) = N'';         -- plain script (already used)
	DECLARE @SQLCMD_Script NVARCHAR(MAX) = N'';  -- mirrors dt.Script result set
	DECLARE @tmpLine NVARCHAR(MAX);
	DECLARE @ord INT;

	------------------------------------------------------------
	-- Parameter validation
	------------------------------------------------------------

	IF DB_ID(@DatabaseName) IS NULL AND @Verbose = 1
		PRINT 'Note: Target DB does not currently exist (restore will create it).';
	
	IF @StopAt = '' SET @StopAt = NULL
	IF @RestoreUpTo_TIMESTAMP = '' OR @RestoreUpTo_TIMESTAMP IS NULL SET @RestoreUpTo_TIMESTAMP = GETDATE()+1
	IF ISNULL(@RestoreDBName,'') = '' SET @RestoreDBName = @DatabaseName

	------------------------------------------------------------
	-- Header
	------------------------------------------------------------
	PRINT '----------- ' + 'Database: ' + @DatabaseName + ' --> ' + @RestoreDBName + ' ---------------------------------';

	-- Also start header in @Script
	SET @Script += '----------- Database: ' + @DatabaseName + ' --> ' + @RestoreDBName + ' ---------------------------------' + CHAR(10);

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
		'----------------------------------------Restore statements begin------------------------------' + CHAR(10) +
		'BEGIN TRY' + CHAR(10);

	DECLARE @TRY_CATCH_TAIL NVARCHAR(MAX) =
		'END TRY' + CHAR(10) +
		'BEGIN CATCH' + CHAR(10) +
		'	SET @msg = ERROR_MESSAGE()' + CHAR(10) +
		'	RAISERROR(@msg,16,1)' + CHAR(10) +
		IIF(@Recover_Database_On_Error = 1,
		'	SET @msg = ''Restore failed at step ''+CONVERT(VARCHAR(5),@StepNo)+''.''+IIF(@StepNo>1,'' Database will be recovered.'','''')' + CHAR(10),		
		'	SET @msg = ''Restore failed at step ''+CONVERT(VARCHAR(5),@StepNo)+''. Restore finished for the database.''' + CHAR(10)) +
		'	RAISERROR(@msg,16,1) ' + CHAR(10) +
		IIF(@Recover_Database_On_Error = 1,
		'IF @StepNo > 1' + CHAR(10) +
		'		RESTORE DATABASE ' + QUOTENAME(@RestoreDBName) + ' WITH RECOVERY' + CHAR(10),
		'') +
		'	RETURN' + CHAR(10) +
		'END CATCH' + CHAR(10) +
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

	-- 3) TRY header + restore commands
	DECLARE @HeaderBlock NVARCHAR(MAX) =
			'DECLARE @StepNo INT' + CHAR(10) +
			'DECLARE @msg NVARCHAR(2000)' + CHAR(10) +
			@TRY_CATCH_HEAD;  -- includes restore-header + BEGIN TRY

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
		SET @SQLCMD_Script += CHAR(9)+'-- Step ' + CAST(@Step AS varchar(10)) + CHAR(10);
		SET @SQLCMD_Script += CHAR(9)+'SET @StepNo = '+CAST(@Step AS varchar(10)) + CHAR(10);

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
				SET @SQLCMD_Script += CHAR(9) + ISNULL(@tmpLine,'') + CHAR(10);
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
	
	IF @backup_path_replace_string IS NOT NULL
	BEGIN
		SELECT @Script = REPLACE(@Script, '@backup_path_replace_string', '''' + REPLACE(@backup_path_replace_string, '''', '''''') + '''')
			, @SQLCMD_Script = REPLACE(@SQLCMD_Script, '@backup_path_replace_string', '''' + REPLACE(@backup_path_replace_string, '''', '''''') + '''');
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
	SELECT LineText Script FROM dbo.fn_SplitStringByLine(@SQLCMD_Script);

END
GO

EXEC dbo.usp_build_one_db_restore_script @DatabaseName = 'Archive99',	-- sysname
                                         @RestoreDBName = '@DatabaseName',	-- Use to restore DatabaseName_2
										 @Restore_DataPath = '',				-- Uses original database path if not specified
										 @Restore_LogPath = '',					-- Uses original database path if not specified
										 @StopAt = '',				-- datetime
                                         @WithReplace = 1,				-- bit
										 @IncludeLogs = 1,
										 @IncludeDiffs = 1,
										 --@RestoreUpTo_TIMESTAMP = '2025-11-02 18:59:10.553',
										 @Recovery = 1,
										 @Recover_Database_On_Error = 1,
										 @backup_path_replace_string = 'REPLACE(Devices,''R:\'',''\\fdbdrbkpdsk\DBDR\FAlgoDB\Tape'')',
											--'REPLACE(Devices,''R:'',''\\''+CONVERT(NVARCHAR(256),SERVERPROPERTY(''MachineName'')))',
										 @Preparatory_Script_Before_Restore = '',
										 @Complementary_Script_After_Restore = 'ALTER AVAILABILITY GROUP FAlgoDBAVG ADD DATABASE [@RestoreDBName]',
										 @Verbose = 0,
										 @SQLCMD_Connect_Conn_String = ''
--\\fdbdrbkpdsk\DBDR\FAlgoDB\TapeBackups\FAlgoDBCLU0$FAlgoDBAVG						 
GO

