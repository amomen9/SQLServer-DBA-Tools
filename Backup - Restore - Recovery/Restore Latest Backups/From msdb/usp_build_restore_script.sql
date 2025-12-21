-- =============================================
-- Author:				<a.momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			
-- Latest Update Date:	
-- Description:			Iterates over all user databases and calls usp_build_one_db_restore_script
--                      for each, building restore scripts in bulk.
-- License:				<Please refer to the license file> 
-- =============================================

SET NOCOUNT ON;

USE msdb;
GO

CREATE OR ALTER PROC dbo.usp_build_restore_script
(
        -- Original parameters
        @DB_Name_Pattern                    NVARCHAR(MAX)   = N'',     -- comma-delimited patterns/tokens; see below
        @StopAt                             DATETIME        = NULL,    -- Point-in-time inside last DIFF/LOG
        @WithReplace                        BIT             = 0,       -- Include REPLACE on RESTORE DATABASE
        
        -- Additional parameters (defaults match usp_build_one_db_restore_script)
        @RestoreDBName                      SYSNAME         = NULL,    -- Destination database name (NULL = same as source)
        @create_datafile_dirs               BIT             = 1,       -- Create original parent directories of the database files in target
        @Restore_DataPath                   NVARCHAR(1000)  = NULL,    -- Custom restore path for data files
        @Restore_LogPath                    NVARCHAR(1000)  = NULL,    -- Custom restore path for log files
        @IncludeLogs                        BIT             = 1,       -- Include log backups
        @IncludeDiffs                       BIT             = 1,       -- Include differential backups
        @Recovery                           BIT             = 0,       -- Specify whether to eventually recover the database or not
        @RestoreUpTo_TIMESTAMP              DATETIME2(3)    = NULL,    -- Backup files started after this TIMESTAMP will be excluded
        @new_backups_parent_dir             NVARCHAR(4000)  = NULL,    -- T-SQL formula to be executed on the backup files full path
                                                                       -- Example: REPLACE(Devices,'R:\','\\'+CONVERT(NVARCHAR(256),SERVERPROPERTY(''MachineName'')))
		@check_backup_file_existance		BIT = 0,				   -- Check if the backup file exists on disk at @new_backups_parent_dir or
																	   -- the original file backup path if @new_backups_parent_dir is empty or null
        @Recover_Database_On_Error          BIT             = 0,       -- If 1, recover the database on error; if 0, leave in restoring state
        @Preparatory_Script_Before_Restore  NVARCHAR(MAX)   = NULL,    -- Script to execute before restore script
        @Complementary_Script_After_Restore NVARCHAR(MAX)   = NULL,    -- Script to execute after restore script
        @Execute                            BIT             = 0,       -- 1 = execute the produced script
        @Verbose                            BIT             = 1,       -- If executing and @Verbose = 1 the produced script will also be printed
        @SQLCMD_Connect_Conn_String         NVARCHAR(MAX)   = NULL
)  -- <-- required (fixes "Incorrect syntax near the keyword 'AS'")
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartUTC datetime2(3) = SYSDATETIME();
    DECLARE @Iteration_Count INT = 0
    DECLARE @Count INT = 0
    DECLARE @Drop_BIT BIT = 0

    IF @DB_Name_Pattern IS NULL SET @DB_Name_Pattern = '';

    /* -----------------------------------------------------------------------
       @DB_Name_Pattern syntax (comma-delimited; whitespace ignored around tokens)
         - SYSTEM_DATABASES    : include system DBs (master, model, msdb, tempdb*)
         - -SYSTEM_DATABASES   : exclude system DBs
         - USER_DATABASES      : include user DBs
         - -USER_DATABASES     : exclude user DBs
         - <pattern>           : include DB names matching pattern (LIKE syntax, supports %)
         - -<pattern>          : exclude DB names matching pattern
         - Multiple tokens allowed, separated by comma.
         - Exclusion has priority over inclusion (if a DB matches both => excluded).
         - If @DB_Name_Pattern is empty => all databases (still excluding tempdb*).
         - If only exclusions are provided (no includes) => start from all, then exclude.
         * tempdb is always excluded because it cannot be restored from backups.
       ----------------------------------------------------------------------- */

    DECLARE @Pattern NVARCHAR(MAX) = LTRIM(RTRIM(@DB_Name_Pattern));
    DECLARE @IncSystem BIT = 0, @ExcSystem BIT = 0, @IncUser BIT = 0, @ExcUser BIT = 0, @HasInclusions BIT = 0;

    IF OBJECT_ID('tempdb..#PatternTokens') IS NOT NULL DROP TABLE #PatternTokens;
    CREATE TABLE #PatternTokens
    (
        Token      NVARCHAR(4000) NOT NULL,
        IsExclude  BIT            NOT NULL,
        Raw        NVARCHAR(4000) NOT NULL,
        RawUpper   NVARCHAR(4000) NOT NULL
    );

    IF OBJECT_ID('tempdb..#IncludeNamePatterns') IS NOT NULL DROP TABLE #IncludeNamePatterns;
    CREATE TABLE #IncludeNamePatterns (Pattern NVARCHAR(4000) NOT NULL);

    IF OBJECT_ID('tempdb..#ExcludeNamePatterns') IS NOT NULL DROP TABLE #ExcludeNamePatterns;
    CREATE TABLE #ExcludeNamePatterns (Pattern NVARCHAR(4000) NOT NULL);

    IF (@Pattern <> N'')
    BEGIN
        ;WITH s AS
        (
            SELECT LTRIM(RTRIM([value])) AS v
            FROM STRING_SPLIT(@Pattern, N',')
        )
        INSERT #PatternTokens (Token, IsExclude, Raw, RawUpper)
        SELECT
            v,
            CASE WHEN LEFT(v,1) = N'-' THEN 1 ELSE 0 END,
            LTRIM(RTRIM(CASE WHEN LEFT(v,1) = N'-' THEN SUBSTRING(v,2,4000) ELSE v END)),
            UPPER(LTRIM(RTRIM(CASE WHEN LEFT(v,1) = N'-' THEN SUBSTRING(v,2,4000) ELSE v END)))
        FROM s
        WHERE v IS NOT NULL AND v <> N'';

        SELECT
            @IncSystem = CASE WHEN EXISTS (SELECT 1 FROM #PatternTokens WHERE RawUpper = N'SYSTEM_DATABASES' AND IsExclude = 0) THEN 1 ELSE 0 END,
            @ExcSystem = CASE WHEN EXISTS (SELECT 1 FROM #PatternTokens WHERE RawUpper = N'SYSTEM_DATABASES' AND IsExclude = 1) THEN 1 ELSE 0 END,
            @IncUser   = CASE WHEN EXISTS (SELECT 1 FROM #PatternTokens WHERE RawUpper = N'USER_DATABASES'   AND IsExclude = 0) THEN 1 ELSE 0 END,
            @ExcUser   = CASE WHEN EXISTS (SELECT 1 FROM #PatternTokens WHERE RawUpper = N'USER_DATABASES'   AND IsExclude = 1) THEN 1 ELSE 0 END;

        INSERT #IncludeNamePatterns (Pattern)
        SELECT Raw
        FROM #PatternTokens
        WHERE RawUpper NOT IN (N'SYSTEM_DATABASES', N'USER_DATABASES')
          AND IsExclude = 0
          AND Raw <> N'';

        INSERT #ExcludeNamePatterns (Pattern)
        SELECT Raw
        FROM #PatternTokens
        WHERE RawUpper NOT IN (N'SYSTEM_DATABASES', N'USER_DATABASES')
          AND IsExclude = 1
          AND Raw <> N'';

        SET @HasInclusions =
            CASE WHEN (@IncSystem = 1 OR @IncUser = 1 OR EXISTS (SELECT 1 FROM #IncludeNamePatterns)) THEN 1 ELSE 0 END;
    END

    IF OBJECT_ID('tempdb..#DBsToProcess') IS NOT NULL DROP TABLE #DBsToProcess;
    CREATE TABLE #DBsToProcess
    (
        DatabaseName SYSNAME NOT NULL PRIMARY KEY
    );

    INSERT #DBsToProcess (DatabaseName)
    SELECT d.name
    FROM sys.databases AS d
    WHERE
        d.state = 0
        AND d.source_database_id IS NULL
        AND d.name <> N'tempdb'                 -- always exclude (not restorable)
        AND d.name NOT LIKE N'ReportServerTempDB' -- keep existing optional exclusion
        AND
        (
            @Pattern = N''

            OR
            (
                -- Inclusion phase:
                (
                    @HasInclusions = 0
                    OR
                    (
                        (@IncSystem = 1 AND d.database_id <= 4)      -- system DBs (except tempdb above)
                        OR (@IncUser = 1 AND d.database_id > 4)      -- user DBs
                        OR EXISTS (SELECT 1 FROM #IncludeNamePatterns p WHERE d.name LIKE p.Pattern)
                    )
                )
                -- Exclusion phase (wins over inclusion):
                AND NOT
                (
                    (@ExcSystem = 1 AND d.database_id <= 4)
                    OR (@ExcUser   = 1 AND d.database_id > 4)
                    OR EXISTS (SELECT 1 FROM #ExcludeNamePatterns p WHERE d.name LIKE p.Pattern)
                )
            )
        );

    SELECT @Iteration_Count = COUNT(*) FROM #DBsToProcess;

    /* Required: this temp table is referenced later (COUNT/INSERT). */
    IF OBJECT_ID('tempdb..#Total_Execution_Report_per_DB') IS NOT NULL DROP TABLE #Total_Execution_Report_per_DB;
    CREATE TABLE #Total_Execution_Report_per_DB
    (
        RowId           int IDENTITY(1,1) PRIMARY KEY,
        DatabaseName    sysname,
        Status          varchar(20),
        ErrorMessage    nvarchar(4000) NULL,
        ExecutionStart  datetime2(3),
        ExecutionEnd    datetime2(3)
    );

    DECLARE @DatabaseName sysname;

    DECLARE dbs CURSOR LOCAL FAST_FORWARD FOR
        SELECT DatabaseName
        FROM #DBsToProcess
        ORDER BY DatabaseName;

    OPEN dbs;
    FETCH NEXT FROM dbs INTO @DatabaseName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @ExecStart datetime2(3) = SYSDATETIME();

        IF @Iteration_Count <= (SELECT COUNT(*) FROM #Total_Execution_Report_per_DB) + 1
            SET @Drop_BIT = 1
        BEGIN TRY

            EXEC dbo.usp_build_one_db_restore_script
                    @DatabaseName                       = @DatabaseName,
                    @RestoreDBName                      = @RestoreDBName,
                    @create_datafile_dirs               = @create_datafile_dirs,
                    @Restore_DataPath                   = @Restore_DataPath,
                    @Restore_LogPath                    = @Restore_LogPath,
                    @StopAt                             = @StopAt,
                    @WithReplace                        = @WithReplace,
                    @IncludeLogs                        = @IncludeLogs,
                    @IncludeDiffs                       = @IncludeDiffs,
                    @Recovery                           = @Recovery,
                    @RestoreUpTo_TIMESTAMP              = @RestoreUpTo_TIMESTAMP,
                    @new_backups_parent_dir             = @new_backups_parent_dir,
                    @check_backup_file_existance        = @check_backup_file_existance,
                    @Recover_Database_On_Error          = @Recover_Database_On_Error,
                    @Preparatory_Script_Before_Restore  = @Preparatory_Script_Before_Restore,
                    @Complementary_Script_After_Restore = @Complementary_Script_After_Restore,
                    @Execute                            = @Execute,
                    @Verbose                            = @Verbose,
                    @SQLCMD_Connect_Conn_String         = @SQLCMD_Connect_Conn_String,
                    @Drop_Disk_Table                    = @Drop_BIT


            INSERT INTO #Total_Execution_Report_per_DB(DatabaseName, Status, ErrorMessage, ExecutionStart, ExecutionEnd)
            VALUES (@DatabaseName, 'SUCCESS', NULL, @ExecStart, SYSDATETIME());

        END TRY
        BEGIN CATCH
            INSERT INTO #Total_Execution_Report_per_DB(DatabaseName, Status, ErrorMessage, ExecutionStart, ExecutionEnd)
            VALUES (@DatabaseName, 'FAILED', ERROR_MESSAGE(), @ExecStart, SYSDATETIME());

            -- Optionally continue; to abort on first failure, uncomment:
            -- CLOSE dbs; DEALLOCATE dbs;
            -- THROW;
        END CATCH;

        FETCH NEXT FROM dbs INTO @DatabaseName;
    END

    CLOSE dbs;
    DEALLOCATE dbs;

    -- Display Output (guarded)
    IF OBJECT_ID('tempdb..##Total_Output') IS NOT NULL
    BEGIN
        SELECT * FROM ##Total_Output;
        DROP TABLE ##Total_Output;
    END

    -- Display results summary
    SELECT * FROM #Total_Execution_Report_per_DB ORDER BY RowId;

END;
GO

-- Sample execution (values from usp_build_one_db_restore_script sample)
EXEC dbo.usp_build_restore_script
    @DB_Name_Pattern                    = '',
    @StopAt                             = NULL,
    @WithReplace                        = 1,
    @RestoreDBName                      = '',
    @create_datafile_dirs               = 1,
    @Restore_DataPath                   = '',
    @Restore_LogPath                    = '',
    @IncludeLogs                        = 1,
    @IncludeDiffs                       = 1,
    @Recovery                           = 1,
    @RestoreUpTo_TIMESTAMP              = NULL, -- '2025-11-02 18:59:10.553',
    @new_backups_parent_dir         	= '', --'\\fdbdrbkpdsk\DBDR\',
	@check_backup_file_existance        = 0,
    @Recover_Database_On_Error          = 1,
    @Preparatory_Script_Before_Restore  = '',
    @Complementary_Script_After_Restore = '--ALTER AVAILABILITY GROUP FAlgoDBAVG ADD DATABASE @RestoreDBName',
    @Execute                            = 0,
    @Verbose                            = 0,
    @SQLCMD_Connect_Conn_String         = '';
GO




