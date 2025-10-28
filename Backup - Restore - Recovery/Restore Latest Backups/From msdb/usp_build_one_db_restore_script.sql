
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

CREATE OR ALTER PROC usp_build_one_db_restore_script
		@DatabaseName sysname,				-- Target database
		@StopAt       datetime = NULL,		-- Point-in-time inside last DIFF/LOG
		@WithReplace  bit     = 0,			-- Include REPLACE on RESTORE DATABASE
		@IncludeLogs  BIT     = 1,			-- Include log backups	
		@IncludeDiffs BIT     = 1			-- Include differential backups
AS
BEGIN
	------------------------------------------------------------
	-- Header
	------------------------------------------------------------
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
	-- Parameters
	------------------------------------------------------------
	DECLARE 
		@Execute      bit     = 0,			-- 1 = execute restore chain
		@Debug        bit     = 0;			-- If executing, but only PRINT dynamic SQL

	IF DB_ID(@DatabaseName) IS NULL
		PRINT 'Note: Target DB does not currently exist (restore will create it).';

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
	GROUP BY b.backup_set_id, b.database_name, b.backup_start_date, b.backup_finish_date,
			 b.first_lsn, b.last_lsn, b.checkpoint_lsn, b.database_backup_lsn
	ORDER BY b.backup_finish_date DESC;

	IF NOT EXISTS (SELECT 1 FROM #Full)
	BEGIN
		RAISERROR('No FULL backup found for %s.',16,1,@DatabaseName);
		RETURN;
	END

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
	  AND b.backup_finish_date > f.backup_finish_date
	  AND @IncludeDiffs = 1
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
	  AND b.backup_finish_date > @BaseFinish
	  AND @IncludeLogs = 1
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
				N'RESTORE DATABASE [' + @DatabaseName + N'] FROM ' + dc.Disks + N' WITH ' +
				N'STATS = 5' + @ReplaceClause + 
				CASE WHEN rc.StepNumber = @LastStep THEN N', NORECOVERY;' ELSE N', NORECOVERY;' END
			WHEN 'DIFF' THEN
				N'RESTORE DATABASE [' + @DatabaseName + N'] FROM ' + dc.Disks + N' WITH ' +
				(CASE 
					WHEN rc.StepNumber = @LastStep AND @StopAt IS NOT NULL AND @HasLogs = 0
						THEN N'STOPAT = ''' + CONVERT(varchar(23), @StopAt, 121) + N''', '
					ELSE N''
				 END) +
				N'STATS = 5' +
				CASE WHEN rc.StepNumber = @LastStep AND @HasLogs = 0 THEN N', NORECOVERY;' ELSE N', NORECOVERY;' END
			WHEN 'LOG' THEN
				N'RESTORE LOG [' + @DatabaseName + N'] FROM ' + dc.Disks + N' WITH ' +
				(CASE 
					WHEN rc.StepNumber = @LastStep AND @StopAt IS NOT NULL
						THEN N'STOPAT = ''' + CONVERT(varchar(23), @StopAt, 121) + N''', '
					ELSE N''
				 END) +
				N'STATS = 5' +
				CASE WHEN rc.StepNumber = @LastStep THEN N', NORECOVERY;' ELSE N', NORECOVERY;' END
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

	PRINT '----------- ' + 'Database: ' + @DatabaseName + ' ----------------------------------------';
	PRINT '-- ```RESTORE CHAIN BUILDER```';
	PRINT '-- Full: ' + @FullInfo;
	IF @HasDiff = 1 PRINT '-- Diff: ' + @DiffInfo ELSE PRINT '-- Diff: (none)';
	PRINT '-- Log backups: ' + CAST(@LogCount AS varchar(12));
	PRINT '-- Log chain LSN continuity: ' + CASE WHEN @LogCount = 0 THEN 'N/A (no logs)'
											 WHEN @LogsChainValid = 1 THEN 'VALID' ELSE 'BROKEN' END;
	IF @LogsChainValid = 0
		PRINT 'WARNING: Log chain appears broken (gap detected).';
	IF @StopAt IS NOT NULL
		PRINT 'STOPAT requested: ' + CONVERT(varchar(23), @StopAt, 121);
	PRINT '------------------------------------------------------------------';

	------------------------------------------------------------
	-- PRINT commands
	------------------------------------------------------------

	DECLARE @i int = 1, @max int = (SELECT MAX(StepNumber) FROM #RestoreChain), @Cmd nvarchar(max);
	WHILE @i <= @max
	BEGIN
		SELECT @Cmd = RestoreCommand FROM #RestoreChain WHERE StepNumber = @i;
		PRINT '-- Step ' + CAST(@i AS varchar(10));
		PRINT @Cmd;
		SET @i += 1;
	END
	PRINT '--##############################################################--'+REPLICATE(CHAR(10),2);
END
GO

EXEC dbo.usp_build_one_db_restore_script @DatabaseName = 'TBS', -- sysname
                                         @StopAt = NULL,       -- datetime
                                         @WithReplace = 0      -- bit
GO


