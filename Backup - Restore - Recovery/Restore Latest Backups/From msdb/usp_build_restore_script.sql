
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


CREATE OR ALTER PROC dbo.usp_build_restore_script
        @StopAt       datetime = NULL,    -- Point-in-time inside last DIFF/LOG
        @WithReplace  bit       = 0       -- Include REPLACE on RESTORE DATABASE
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
                    @DatabaseName = @DatabaseName,
                    @StopAt       = @StopAt,
                    @WithReplace  = @WithReplace;


        END TRY
        BEGIN CATCH
            INSERT INTO #Results(DatabaseName, Status, ErrorMessage, ExecutionStart, ExecutionEnd)
            VALUES (@DatabaseName, 'FAILED',
                    ERROR_MESSAGE(), @ExecStart, SYSDATETIME());

            -- Optionally continue; to abort on first failure, uncomment:
            -- CLOSE dbs; DEALLOCATE dbs;
            -- THROW;
        END CATCH;

        FETCH NEXT FROM dbs INTO @DatabaseName;
    END

    CLOSE dbs;
    DEALLOCATE dbs;


END;
GO

EXEC dbo.usp_build_restore_script @StopAt = NULL,  -- datetime
                                  @WithReplace = 0 -- bit
