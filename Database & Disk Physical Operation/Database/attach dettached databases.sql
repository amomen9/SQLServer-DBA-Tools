-- =============================================
-- Author:              a-momen
-- Contact & Report:    amomen@gmail.com
-- Update date:         2023-01-15
-- Script:              Automated attachment of detached databases
-- Purpose:             Enumerate *.mdf files in a root folder, extract metadata with DBCC CHECKPRIMARYFILE,
--                      then build and execute sys.sp_attach_db for each set of files. Provides robust
--                      error handling with optional PRINT vs RAISERROR output mode.
-- =============================================


CREATE OR ALTER PROCEDURE usp_attach_detached_databases 
    ----------- Parameter -------------------------------------------------------
    -- Define your search path for mdf files here. If not specified, the instance default data path will be used
    @Search_Path  NVARCHAR(256) = ''
    -----------------------------------------------------------------------------
AS
BEGIN

    SET NOCOUNT ON;

    -- Drop leftover temp tables from prior runs
    DROP TABLE IF EXISTS #DataFilePaths;
    DROP TABLE IF EXISTS #DBDetails;

    -- Working variables
    DECLARE @path              NVARCHAR(255);
    DECLARE @SQL               NVARCHAR(MAX);
    DECLARE @PRINT_or_RAISERROR INT = 2;            -- 1 = PRINT errors, 2 = RAISERROR (default)
    DECLARE @ErrMsg            NVARCHAR(500);
    DECLARE @ErrLine           NVARCHAR(10);
    DECLARE @ErrNo             NVARCHAR(6);
    DECLARE @ErrState          NVARCHAR(3);
    DECLARE @ErrSeverity       NVARCHAR(2);
    DECLARE @UDErrMsg          NVARCHAR(MAX);

    -- Temp table to hold file list returned by DBCC CHECKPRIMARYFILE (option 3)
    CREATE TABLE #DataFilePaths
    (
        id       INT NOT NULL IDENTITY PRIMARY KEY,
        [status] INT,
        [fileid] SMALLINT,
        [name]   NCHAR(128),
        [filename] NCHAR(260)
    );

    -- Temp table to hold database properties returned by DBCC CHECKPRIMARYFILE (option 2)
    CREATE TABLE #DBDetails
    (
        id INT NOT NULL IDENTITY PRIMARY KEY,
        [property]   NVARCHAR(128),
        [value_sqlv] SQL_VARIANT,
        [value]      AS CONVERT(SYSNAME, value_sqlv)
    );

    IF (ISNULL(@Search_Path,'')='') SET @Search_Path = CONVERT(NVARCHAR(256),SERVERPROPERTY('InstanceDefaultDataPath'))
    -- Cursor enumerates *.mdf files under specified root path. Define arbitrary root path per
    -- your needs
    DECLARE Attacher CURSOR FAST_FORWARD FOR
        SELECT full_filesystem_path
        FROM  
        sys.dm_os_enumerate_filesystem(@Search_Path, N'*.mdf') fs
        LEFT JOIN sys.master_files mf
        ON mf.physical_name = fs.full_filesystem_path
        WHERE mf.database_id IS NULL AND fs.file_or_directory_name NOT IN ('model_msdbdata.mdf','model_replicatedmaster.mdf','mssqlsystemresource.mdf')

    OPEN Attacher;

    FETCH NEXT FROM Attacher INTO @path;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Clean temp tables for this iteration
        TRUNCATE TABLE #DataFilePaths;
        TRUNCATE TABLE #DBDetails;

        BEGIN TRY
            -- Retrieve file metadata (option 3)
            SET @SQL = N'DBCC CHECKPRIMARYFILE (N''' + @path + N''', 3) WITH NO_INFOMSGS;';
            INSERT #DataFilePaths
            EXEC (@SQL);

            -- Retrieve database name & other properties (option 2)
            SET @SQL = N'DBCC CHECKPRIMARYFILE (N''' + @path + N''', 2) WITH NO_INFOMSGS;';
            INSERT #DBDetails
            EXEC (@SQL);

            BEGIN TRY
                -- Build parameter list for sys.sp_attach_db (filename arguments)
                SELECT @SQL =
                    STRING_AGG(REPLICATE(CHAR(9), 7) + N'@filename' + CONVERT(NVARCHAR(10), id) +
                               N' = N''' + TRIM(filename) + N'''', N',' + CHAR(10))
                FROM #DataFilePaths;

                -- Prepend EXEC line with @dbname
                SET @SQL =
                      CHAR(9) + N'EXEC sys.sp_attach_db ' +
                      N'@dbname = N''' + (SELECT value FROM #DBDetails WHERE property = N'Database name') + N''',' + CHAR(10) +
                      @SQL;

                PRINT @SQL;        -- Echo generated command
                EXEC (@SQL);       -- Execute attach
            END TRY
            BEGIN CATCH
                -- Handle inner attach errors
                SET @ErrMsg     = ERROR_MESSAGE();
                SET @ErrLine    = CONVERT(NVARCHAR(10), ERROR_LINE());
                SET @ErrNo      = CONVERT(NVARCHAR(6), ERROR_NUMBER());
                SET @ErrState   = CONVERT(NVARCHAR(3), ERROR_STATE());
                SET @ErrSeverity= CONVERT(NVARCHAR(2), ERROR_SEVERITY());

                SET @UDErrMsg =
                    N'Attach operation failed for file: ' + @path + CHAR(10) +
                    N'System error:' + CHAR(10) +
                    N'Msg ' + @ErrNo + N', Level ' + @ErrSeverity + N', State ' + @ErrState +
                    N', Line ' + @ErrLine + CHAR(10) + @ErrMsg;

                IF @PRINT_or_RAISERROR = 1
                BEGIN
                    PRINT @UDErrMsg;
                    PRINT CHAR(13) + REPLICATE('-', 108);
                END
                ELSE
                BEGIN
                    PRINT CHAR(13) + REPLICATE('-', 108);
                    RAISERROR (@UDErrMsg, 16, 1);
                END
            END CATCH
        END TRY
        BEGIN CATCH
            -- Handle metadata extraction errors
            SET @ErrMsg      = ERROR_MESSAGE();
            SET @ErrLine     = CONVERT(NVARCHAR(10), ERROR_LINE());
            SET @ErrNo       = CONVERT(NVARCHAR(6), ERROR_NUMBER());
            SET @ErrState    = CONVERT(NVARCHAR(3), ERROR_STATE());
            SET @ErrSeverity = CONVERT(NVARCHAR(2), ERROR_SEVERITY());

            SET @UDErrMsg =
                N'Pre-attach metadata collection failed for file: ' + @path + CHAR(10) +
                N'System error:' + CHAR(10) +
                N'Msg ' + @ErrNo + N', Level ' + @ErrSeverity + N', State ' + @ErrState +
                N', Line ' + @ErrLine + CHAR(10) + @ErrMsg;

            IF @PRINT_or_RAISERROR = 1
            BEGIN
                PRINT @UDErrMsg;
                PRINT CHAR(13) + REPLICATE('-', 108);
            END
            ELSE
            BEGIN
                PRINT CHAR(13) + REPLICATE('-', 108);
                RAISERROR (@UDErrMsg, 16, 1);
            END
        END CATCH;

        -- Advance cursor
        FETCH NEXT FROM Attacher INTO @path;
    END;

    CLOSE Attacher;
    DEALLOCATE Attacher;
END
GO

EXEC dbo.usp_attach_detached_databases @Search_Path = N'' -- nvarchar(256)
