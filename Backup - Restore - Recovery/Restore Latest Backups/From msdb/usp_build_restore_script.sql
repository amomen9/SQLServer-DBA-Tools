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
        @DB_Name_Pattern                    NVARCHAR(MAX)   = N'',     -- Comma-delimited tokens/patterns; see detailed syntax below.
        @StopAt                             DATETIME        = NULL,    -- Point-in-time recovery (applies to last DIFF/LOG restore if used).
        @WithReplace                        BIT             = 0,       -- Include REPLACE option on RESTORE DATABASE.

        -- Additional parameters (defaults match usp_build_one_db_restore_script)
        @RestoreDBName                      SYSNAME         = NULL,    -- Destination database name (NULL = same as source per DB).
        @create_datafile_dirs               BIT             = 1,       -- If 1: emit (and optionally execute) xp_create_subdir statements.
        @Restore_DataPath                   NVARCHAR(1000)  = NULL,    -- Override restore folder for data files (NULL/empty = keep original).
        @Restore_LogPath                    NVARCHAR(1000)  = NULL,    -- Override restore folder for log files  (NULL/empty = keep original).
        @IncludeLogs                        BIT             = 1,       -- If 1: include log chain restores (if available).
        @IncludeDiffs                       BIT             = 1,       -- If 1: include latest DIFF tied to chosen FULL (if available).
        @Recovery                           BIT             = 0,       -- If 1: final step uses RECOVERY, else leaves DB in NORECOVERY.
        @RestoreUpTo_TIMESTAMP              DATETIME2(3)    = NULL,    -- Exclude backups with backup_start_date >= this (acts like "upper bound").
        @new_backups_parent_dir             NVARCHAR(4000)  = NULL,    -- If set: map backup files by base name under this directory.
                                                                       -- Example formula (in caller): REPLACE(Devices,'R:\','\\'+CONVERT(...))
		@check_backup_file_existance		BIT = 0,				   -- If 1: validate backup files exist on disk (original or remapped path).
        @Recover_Database_On_Error          BIT             = 0,       -- If 1: TRY/CATCH in generated script will attempt RECOVERY on failures.
        @Preparatory_Script_Before_Restore  NVARCHAR(MAX)   = NULL,    -- Optional script emitted/executed before restore chain.
        @Complementary_Script_After_Restore NVARCHAR(MAX)   = NULL,    -- Optional script emitted/executed after restore chain.
        @Execute                            BIT             = 0,       -- If 1: execute emitted restore script (per DB).
        @Verbose                            BIT             = 1,       -- If 1 and @Execute=1: prints emitted script as well.
        @SQLCMD_Connect_Conn_String         NVARCHAR(MAX)   = NULL,    -- If set: emitted script includes :connect for sqlcmd mode.
        @Separate_Results_Per_Database      BIT             = 0        -- If 1: each DB returns its own result set; else bulk-aggregated output.
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Notes:
    --  * This procedure iterates databases based on @DB_Name_Pattern and calls dbo.usp_build_one_db_restore_script per DB.
    --  * tempdb is always excluded (cannot be restored from backup history like user DBs).
    --  * Failures are captured per database in #Total_Execution_Report_per_DB; iteration continues by default.

    DECLARE @StartUTC datetime2(3) = SYSDATETIME();
    DECLARE @Iteration_Count INT = 0
    DECLARE @Count INT = 0
    DECLARE @Last_Procedure_Iteration BIT = 0
    DECLARE @First_Procedure_Iteration BIT = 1

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

    /* Execution summary:
       - SUCCESS/FAILED is recorded per DB.
       - ErrorMessage captures ERROR_MESSAGE() from the CATCH block (per-DB failure).
       - This is only an execution/iteration report; restore-chain details are emitted by the child procedure. */
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

        IF @Count <> 0 SET @First_Procedure_Iteration = 0
        SET @Count+=1
        IF @Iteration_Count <= @Count
            SET @Last_Procedure_Iteration = 1
        --SELECT @Iteration_Count, @Count, @Last_Procedure_Iteration
        BEGIN TRY
            -- Child procedure is responsible for building the restore chain and returning/aggregating the generated script.
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
                    @First_Parent_Procedure_Iteration   = @First_Procedure_Iteration,
                    @Last_Parent_Procedure_Iteration    = @Last_Procedure_Iteration,
                    @ResultSet_is_for_single_Database   = @Separate_Results_Per_Database;

            INSERT INTO #Total_Execution_Report_per_DB(DatabaseName, Status, ErrorMessage, ExecutionStart, ExecutionEnd)
            VALUES (@DatabaseName, 'SUCCESS', NULL, @ExecStart, SYSDATETIME());
        END TRY
        BEGIN CATCH
            -- Continue-on-error behavior:
            --  - This procedure records failure and proceeds to next database.
            --  - To stop on first failure, switch to THROW (see commented lines).
            INSERT INTO #Total_Execution_Report_per_DB(DatabaseName, Status, ErrorMessage, ExecutionStart, ExecutionEnd)
            VALUES (@DatabaseName, 'FAILED', ERROR_MESSAGE(), @ExecStart, SYSDATETIME());

            -- CLOSE dbs; DEALLOCATE dbs;
            -- THROW;
        END CATCH;

        FETCH NEXT FROM dbs INTO @DatabaseName;
    END

    CLOSE dbs;
    DEALLOCATE dbs;

    -------------------------------------------------------------------------
    -- Emit aggregated output once at the very end (bulk mode only)
    -------------------------------------------------------------------------
    IF @Separate_Results_Per_Database = 0
       AND OBJECT_ID('tempdb..##Total_Output') IS NOT NULL
    BEGIN
        DECLARE @OutLine NVARCHAR(MAX);

        DECLARE out_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT CAST([Output] AS NVARCHAR(MAX))
            FROM ##Total_Output
            ORDER BY Output_Id;

        OPEN out_cur;
        FETCH NEXT FROM out_cur INTO @OutLine;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- PRINT truncates; RAISERROR(0) preserves longer text and can NOWAIT.
            RAISERROR(N'%s', 0, 1, @OutLine) WITH NOWAIT;
            FETCH NEXT FROM out_cur INTO @OutLine;
        END

        CLOSE out_cur;
        DEALLOCATE out_cur;

        DROP TABLE ##Total_Output;
    END

    -- Display results summary
    SELECT * FROM #Total_Execution_Report_per_DB ORDER BY RowId;

END;
GO

/* ------------------------------------------------------------------------------------
   SAMPLE EXECUTION
   - This is an example call for interactive testing.
   - In automation/CI/CD, keep sample calls commented out to avoid accidental execution.
------------------------------------------------------------------------------------ */
-- Sample execution (values from usp_build_one_db_restore_script sample)
EXEC dbo.usp_build_restore_script
    @DB_Name_Pattern                    = '-SYSTEM_DATABASES',--'-dbWarden_temp,-MofidV3,-NewDB,-Uni',
    @StopAt                             = NULL,
    @WithReplace                        = 1,
    @RestoreDBName                      = '@DatabaseName',
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
    @SQLCMD_Connect_Conn_String         = '',
    @Separate_Results_Per_Database      = 0;
GO




