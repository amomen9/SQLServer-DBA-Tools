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
        -- Original parameters
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
        @new_backups_parent_dir         NVARCHAR(4000)  = NULL,    -- T-SQL formula to be executed on the backup files full path
                                                                        -- Example: REPLACE(Devices,'R:\','\\'+CONVERT(NVARCHAR(256),SERVERPROPERTY(''MachineName'')))
        @Recover_Database_On_Error          BIT             = 0,       -- If 1, recover the database on error; if 0, leave in restoring state
        @Preparatory_Script_Before_Restore  NVARCHAR(MAX)   = NULL,    -- Script to execute before restore script
        @Complementary_Script_After_Restore NVARCHAR(MAX)   = NULL,    -- Script to execute after restore script
        @Execute                            BIT             = 0,       -- 1 = execute the produced script
        @Verbose                            BIT             = 1,       -- If executing and @Verbose = 1 the produced script will also be printed
        @SQLCMD_Connect_Conn_String         NVARCHAR(MAX)   = NULL     -- Connection string to be written in front of :connect (SQLCMD Mode)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartUTC datetime2(3) = SYSDATETIME();

    IF OBJECT_ID('tempdb..#Results') IS NOT NULL DROP TABLE #Results;
    CREATE TABLE #Results
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
        SELECT name
        FROM sys.databases
        WHERE database_id > 4                       -- exclude system DBs
          AND state = 0                             -- ONLINE
          AND source_database_id IS NULL            -- not a snapshot
          AND name NOT LIKE 'ReportServerTempDB'    -- (optional filters)
        ORDER BY name;

    OPEN dbs;
    FETCH NEXT FROM dbs INTO @DatabaseName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @ExecStart datetime2(3) = SYSDATETIME();
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
                    @new_backups_parent_dir         = @new_backups_parent_dir,
                    @Recover_Database_On_Error          = @Recover_Database_On_Error,
                    @Preparatory_Script_Before_Restore  = @Preparatory_Script_Before_Restore,
                    @Complementary_Script_After_Restore = @Complementary_Script_After_Restore,
                    @Execute                            = @Execute,
                    @Verbose                            = @Verbose,
                    @SQLCMD_Connect_Conn_String         = @SQLCMD_Connect_Conn_String;

            INSERT INTO #Results(DatabaseName, Status, ErrorMessage, ExecutionStart, ExecutionEnd)
            VALUES (@DatabaseName, 'SUCCESS', NULL, @ExecStart, SYSDATETIME());

        END TRY
        BEGIN CATCH
            INSERT INTO #Results(DatabaseName, Status, ErrorMessage, ExecutionStart, ExecutionEnd)
            VALUES (@DatabaseName, 'FAILED', ERROR_MESSAGE(), @ExecStart, SYSDATETIME());

            -- Optionally continue; to abort on first failure, uncomment:
            -- CLOSE dbs; DEALLOCATE dbs;
            -- THROW;
        END CATCH;

        FETCH NEXT FROM dbs INTO @DatabaseName;
    END

    CLOSE dbs;
    DEALLOCATE dbs;

    -- Display results summary
    SELECT * FROM #Results ORDER BY RowId;

END;
GO

-- Sample execution (values from usp_build_one_db_restore_script sample)
EXEC dbo.usp_build_restore_script 
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
    @new_backups_parent_dir         	= '\\fdbdrbkpdsk\DBDR\',
    @Recover_Database_On_Error          = 1,
    @Preparatory_Script_Before_Restore  = '',
    @Complementary_Script_After_Restore = '--ALTER AVAILABILITY GROUP FAlgoDBAVG ADD DATABASE @RestoreDBName',
    @Execute                            = 0,
    @Verbose                            = 0,
    @SQLCMD_Connect_Conn_String         = '';
GO
