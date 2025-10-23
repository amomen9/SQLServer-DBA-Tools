-- ==============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2022.05.12>
-- Latest Update Date:	<2022.08.19>
-- Description:			<Move Databases' Datafiles>
-- ==============================================



-- Author: a-momen | Contact: amomen@gmail.com
-- Purpose: Print long strings; move or raw copy database data/log files with optional rename and AG handling

CREATE OR ALTER PROC usp_PrintLong
    @String NVARCHAR(MAX),
    @Max_Chunk_Size SMALLINT = 4000
AS
BEGIN
    SET @Max_Chunk_Size = ISNULL(@Max_Chunk_Size,4000);
    IF @Max_Chunk_Size > 4000 OR @Max_Chunk_Size < 50
    BEGIN
        RAISERROR('Invalid @Max_Chunk_Size.',16,1);
        RETURN 1;
    END;
    DECLARE @NewLineLocation INT,@TempStr NVARCHAR(4000),@Length INT,@carriage BIT;
    WHILE @String <> ''
    BEGIN
        IF LEN(@String) <= 4000
        BEGIN
            PRINT @String;
            BREAK;
        END
        ELSE
        BEGIN
            SET @TempStr = SUBSTRING(@String,1,4000);
            SELECT @NewLineLocation = CHARINDEX(CHAR(10),REVERSE(@TempStr));
            DECLARE @MinSeparator INT = CHARINDEX(CHAR(32),REVERSE(@TempStr));
            IF @MinSeparator > CHARINDEX(CHAR(9),REVERSE(@TempStr)) AND CHARINDEX(CHAR(9),REVERSE(@TempStr)) <> 0
                SET @MinSeparator = CHARINDEX(CHAR(9),REVERSE(@TempStr));
            SET @NewLineLocation = IIF(@NewLineLocation=0,@MinSeparator,@NewLineLocation);
            IF CHARINDEX(CHAR(13),REVERSE(@TempStr)) - @NewLineLocation = 1
                SET @carriage = 1;
            ELSE
                SET @carriage = 0;
            SET @TempStr = LEFT(@TempStr,(4000-@NewLineLocation)-CONVERT(INT,@carriage));
            PRINT @TempStr;
            SET @Length = LEN(@String)-LEN(@TempStr)-CONVERT(INT,@carriage)-1;
            SET @String = RIGHT(@String,@Length);
        END
    END
END;
GO

CREATE OR ALTER PROCEDURE sp_MoveDatabases_Datafiles
    @Perform_CheckDB_First BIT = 1,
    @DatabasesToBeMoved_or_Copied SYSNAME = '',
    @New_Datafile_Directory NVARCHAR(300) = 'D:\Database Data',
    @New_Logfile_Directory NVARCHAR(300) = 'E:\Database Log',
    @Remove_Database_From_AG_First BIT = 0,
    @Bring_Online_Add_Database_to_AG_Again_if_Removed BIT = 1,
    @Replace_String_Replacement SYSNAME = '',
    @Replace_Pattern SYSNAME = '',
    @Take_a_Raw_Backup BIT = 0,
    @Show_List_of_Databases_Affected BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @DBName SYSNAME,@SQL VARCHAR(MAX),@SQL2 NVARCHAR(4000),@Offline_Database NVARCHAR(1000),
            @New_Datafile_Directory_In_Loop NVARCHAR(300),@New_Logfile_Directory_In_Loop NVARCHAR(300),
            @message NVARCHAR(2000),@List_of_Databases_Affected NVARCHAR(MAX),
            @Count_of_Databases_Affected INT,@original_user_access TINYINT;

    -- Normalize inputs
    SET @DatabasesToBeMoved_or_Copied = TRIM(ISNULL(@DatabasesToBeMoved_or_Copied,''));
    SET @Replace_String_Replacement = TRIM(ISNULL(@Replace_String_Replacement,''));
    SET @Replace_Pattern = TRIM(ISNULL(@Replace_Pattern,''));
    SET @Take_a_Raw_Backup = ISNULL(@Take_a_Raw_Backup,0);
    SET @Remove_Database_From_AG_First = ISNULL(@Remove_Database_From_AG_First,0);
    SET @New_Datafile_Directory = TRIM(ISNULL(@New_Datafile_Directory,''));
    SET @New_Logfile_Directory = TRIM(ISNULL(@New_Logfile_Directory,''));
    IF @New_Datafile_Directory = '' AND @New_Logfile_Directory = '' AND @Replace_Pattern = '' AND @Replace_String_Replacement = ''
        RAISERROR('@New_Datafile_Directory and @New_Logfile_Directory are both undefined.',16,1);
    IF RIGHT(@New_Datafile_Directory,1) <> '\' AND @New_Datafile_Directory <> '' SET @New_Datafile_Directory += '\';
    IF RIGHT(@New_Logfile_Directory,1) <> '\' AND @New_Logfile_Directory <> '' SET @New_Logfile_Directory += '\';

    -- Ensure target folders
    IF @New_Datafile_Directory <> '' EXEC sys.xp_create_subdir @New_Datafile_Directory;
    IF @New_Logfile_Directory <> '' EXEC sys.xp_create_subdir @New_Logfile_Directory;

    -- Enable required advanced options
    EXEC sys.sp_configure @configname='show advanced options',@configvalue=1; RECONFIGURE;
    EXEC sys.sp_configure @configname='cmdshell',@configvalue=1; RECONFIGURE;

    -- Temp store for xp_cmdshell output
    CREATE TABLE #tmp (id INT IDENTITY PRIMARY KEY NOT NULL,[output] NVARCHAR(500));

    -- List of selected databases
    SELECT TRIM(value) dbname INTO #dbnames FROM STRING_SPLIT(@DatabasesToBeMoved_or_Copied,',');

    -- Validate candidates
    IF NOT EXISTS (
        SELECT 1
        FROM sys.databases d JOIN #dbnames dbnames
          ON d.name LIKE CASE WHEN @DatabasesToBeMoved_or_Copied = '' THEN '%' ELSE dbnames.dbname END
         AND database_id > CASE WHEN @DatabasesToBeMoved_or_Copied = '' THEN 4 ELSE 1 END
         AND state IN (0,1,2,3,5,6)
        WHERE sys.fn_hadr_is_primary_replica(name) IS NULL OR @Remove_Database_From_AG_First = 1
    )
    BEGIN
        IF @Remove_Database_From_AG_First = 0
            SET @message = 'No database matched criteria and was not in an Availability Group.';
        ELSE
            SET @message = 'No database matched criteria.';
        RAISERROR(@message,16,1);
        RETURN 1;
    END;

    -- Tracking table
    CREATE TABLE #List_of_Databases_Affected (id INT IDENTITY PRIMARY KEY NOT NULL,DBName SYSNAME NOT NULL);

    -- Cursor over databases
    DECLARE LoopThroughDatabases CURSOR FOR
        SELECT name
        FROM sys.databases d JOIN #dbnames dbnames
          ON d.name LIKE CASE WHEN @DatabasesToBeMoved_or_Copied = '' THEN '%' ELSE dbnames.dbname END
         AND database_id > CASE WHEN @DatabasesToBeMoved_or_Copied = '' THEN 4 ELSE 1 END
         AND state IN (0,2,3,5,6)
         AND source_database_id IS NULL
        WHERE sys.fn_hadr_is_primary_replica(name) IS NULL OR @Remove_Database_From_AG_First = 1;

    OPEN LoopThroughDatabases;
    FETCH NEXT FROM LoopThroughDatabases INTO @DBName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @DBPrint NVARCHAR(256) = 'Beginning ' + IIF(@Take_a_Raw_Backup=0,'movement','raw copy') + ' of Database: ' + @DBName;
        RAISERROR('-----------------------------------------------------------------------------------------------------------',0,1) WITH NOWAIT;
        RAISERROR(@DBPrint,0,1) WITH NOWAIT;
        PRINT '';

        -- Resolve target paths per DB
        IF @New_Datafile_Directory = ''
            SELECT @New_Datafile_Directory_In_Loop = LEFT(physical_name,(LEN(physical_name)-CHARINDEX('\',REVERSE(physical_name))+1))
            FROM sys.master_files WHERE database_id = DB_ID(@DBName) AND file_id = 1;
        ELSE
            SET @New_Datafile_Directory_In_Loop = @New_Datafile_Directory;

        IF @New_Logfile_Directory = ''
            SELECT @New_Logfile_Directory_In_Loop = LEFT(physical_name,(LEN(physical_name)-CHARINDEX('\',REVERSE(physical_name))+1))
            FROM sys.master_files WHERE database_id = DB_ID(@DBName) AND file_id = 2;
        ELSE
            SET @New_Logfile_Directory_In_Loop = @New_Logfile_Directory;

        BEGIN TRY
            -- Prepare offline if needed
            IF (SELECT state FROM sys.databases WHERE database_id = DB_ID(@DBName)) IN (0,5)
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM (
                        SELECT CASE type
                                 WHEN 1 THEN @New_Logfile_Directory_In_Loop + RIGHT(physical_name,CHARINDEX('\',REVERSE(physical_name))-1)
                                 ELSE @New_Datafile_Directory_In_Loop + RIGHT(physical_name,CHARINDEX('\',REVERSE(physical_name))-1)
                             END AS TargetPath
                        FROM sys.master_files
                        WHERE database_id = DB_ID(@DBName)
                        EXCEPT
                        SELECT physical_name FROM sys.master_files WHERE database_id = DB_ID(@DBName)
                    ) dt
                )
                BEGIN
                    FETCH NEXT FROM LoopThroughDatabases INTO @DBName;
                    SET @message = 'No datafile movement needed for ' + QUOTENAME(@DBName) + '.';
                    RAISERROR(@message,0,1) WITH NOWAIT;
                    CONTINUE;
                END;

                INSERT #List_of_Databases_Affected (DBName) VALUES (@DBName);

                IF @DBName <> 'TempDB'
                BEGIN
                    DECLARE @DB_AG_Name SYSNAME;
                    IF @Remove_Database_From_AG_First = 1 AND sys.fn_hadr_is_primary_replica(@DBName)=1
                    BEGIN
                        SET @SQL2 = 'SELECT @SQL = ag_name FROM sys.dm_hadr_cached_database_replica_states WHERE ag_db_name = ''' + @DBName + '''';
                        EXEC sys.sp_executesql @SQL2,N'@SQL NVARCHAR(MAX) OUT',@DB_AG_Name OUT;
                        SET @SQL = 'ALTER AVAILABILITY GROUP ' + QUOTENAME(@DB_AG_Name) + ' REMOVE DATABASE ' + QUOTENAME(@DBName);
                        EXEC (@SQL);
                    END;

                    DECLARE @ReadOnly_flag BIT;
                    SELECT @ReadOnly_flag = is_read_only FROM sys.databases WHERE name = @DBName;
                    IF @ReadOnly_flag = 1
                        RAISERROR('Database is read_only; active connections may block SINGLE_USER.',0,1) WITH NOWAIT;

                    SELECT @original_user_access = user_access FROM sys.databases WHERE name=@DBName;

                    SET @SQL = 'USE ' + QUOTENAME(@DBName) + '; ALTER DATABASE ' + QUOTENAME(@DBName) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
                    BEGIN TRY EXEC(@SQL); END TRY BEGIN CATCH PRINT 'Setting SINGLE_USER failed.'; END CATCH;

                    SET @SQL = 'USE ' + QUOTENAME(@DBName) + '; EXEC sys.sp_flush_log; CHECKPOINT; ALTER DATABASE ' +
                               QUOTENAME(@DBName) + ' SET ' +
                               CASE @original_user_access WHEN 0 THEN 'MULTI_USER' WHEN 1 THEN 'SINGLE_USER' WHEN 2 THEN 'RESTRICTED_USER' END +
                               '; USE master;';
                    EXEC (@SQL);

                    SET @SQL = IIF(@Perform_CheckDB_First=1,'DBCC CHECKDB(' + QUOTENAME(@DBName) + ') WITH NO_INFOMSGS;' + CHAR(10),'') +
                               'ALTER DATABASE ' + QUOTENAME(@DBName) + ' SET OFFLINE;';
                    EXEC (@SQL);
                END
            END

            -- Data files transfer
            SET @SQL = '
                DECLARE @PhysicalName NVARCHAR(260),@ErrMessage VARCHAR(700),@FileName NVARCHAR(255),@FileLogicalName NVARCHAR(255),
                        @NewPath NVARCHAR(500),@FileRelocate NVARCHAR(MAX),@CMDSHELL_Command1 VARCHAR(1000),@CMDSHELL_Command2 VARCHAR(1000),
                        @Error_Line INT,@Error_Message NVARCHAR(300),@Physical_Directory NVARCHAR(500);
                DECLARE MoveDatafiles CURSOR FOR
                    SELECT mf.name,mf.physical_name,
                           RIGHT(physical_name,CHARINDEX(''\'',REVERSE(physical_name))-1),
                           LEFT(physical_name,LEN(mf.physical_name)-CHARINDEX(''\'',REVERSE(physical_name))+1)
                    FROM sys.master_files mf JOIN sys.databases d ON d.database_id = mf.database_id
                    WHERE d.name=''' + @DBName + ''' AND file_id<>2;
                OPEN MoveDatafiles;
                FETCH NEXT FROM MoveDatafiles INTO @FileLogicalName,@PhysicalName,@FileName,@Physical_Directory;
                WHILE @@FETCH_STATUS = 0
                BEGIN
                    IF (@Physical_Directory = ''' + @New_Datafile_Directory_In_Loop + ''')
                    BEGIN
                        FETCH NEXT FROM MoveDatafiles INTO @FileLogicalName,@PhysicalName,@FileName,@Physical_Directory;
                        CONTINUE;
                    END
                    BEGIN TRY
                        SET @NewPath = ''' + @New_Datafile_Directory_In_Loop + ''' + @FileName;
            ';
            IF @DBName <> 'TempDB'
                SET @SQL += '
                        TRUNCATE TABLE #tmp;
                        IF (SELECT file_is_a_directory FROM sys.dm_os_file_exists(@PhysicalName)) <> 1
                        BEGIN
                            SET @CMDSHELL_Command1 = ''ROBOCOPY "'' + @Physical_Directory + ''" "''' + @New_Datafile_Directory_In_Loop + '''" "'' + @FileName + ''" /J /COPY:DATSOU ' + IIF(@Take_a_Raw_Backup=0,'/MOV ','') + '/MT:8 /R:3 /W:1 /UNILOG+:ROBOout.log /TEE /UNICODE'';
                            INSERT #tmp EXEC xp_cmdshell @CMDSHELL_Command1;
                            IF (''' + @Replace_Pattern + '''<>'''' OR ''' + @Replace_String_Replacement + '''<>'''')
                                SET @CMDSHELL_Command2 = ''CD "''' + @New_Datafile_Directory_In_Loop + '''" && REN '' + @FileName + '' '' + (''' + @Replace_Pattern + ''' + @FileName + ''' + @Replace_String_Replacement + ''')'';
                        END
                        ELSE
                        BEGIN
                            EXEC xp_create_subdir @NewPath;
                            SET @CMDSHELL_Command1 = ''ROBOCOPY ' + IIF(@Take_a_Raw_Backup=0,'/MOV ','') + '/E /COMPRESS "'' + @PhysicalName + ''" "'' + @NewPath + ''"'';
                            INSERT #tmp EXEC xp_cmdshell @CMDSHELL_Command1;
                        END
                        SELECT TOP 1 @Error_Line = id FROM #tmp WHERE [output] LIKE ''%ERROR%'';
                        SELECT @Error_Message = (SELECT STRING_AGG([output],CHAR(10)) FROM #tmp WHERE id BETWEEN @Error_Line AND (@Error_Line+1));
                        IF @Error_Line IS NOT NULL PRINT ''Warning: Datafile copy/move error:'' + ISNULL(@Error_Message,'''');
                ';
            SET @SQL += '
                        SET @FileRelocate = ''ALTER DATABASE ' + QUOTENAME(@DBName) +
                        ' MODIFY FILE (NAME='' + QUOTENAME(@FileLogicalName) + '', FILENAME='''''''' + @NewPath + '''''''')'';
            ';
            IF @DBName <> 'TempDB'
                SET @SQL += '
                        IF ' + CONVERT(CHAR(1),@Take_a_Raw_Backup) + '=0
                            IF (SELECT file_exists+file_is_a_directory FROM sys.dm_os_file_exists(@NewPath)) = 1
                                EXEC (@FileRelocate)
                            ELSE
                                RAISERROR(''File relocation skipped; physical move failed.'',16,1);
                ';
            ELSE
                SET @SQL += 'EXEC (@FileRelocate);';
            SET @SQL += '
                    END TRY
                    BEGIN CATCH
                        SET @ErrMessage = ''Failure processing datafile '' + @PhysicalName + ''. '' + ERROR_MESSAGE();
                        RAISERROR(@ErrMessage,16,1);
                        RETURN;
                    END CATCH
                    FETCH NEXT FROM MoveDatafiles INTO @FileLogicalName,@PhysicalName,@FileName,@Physical_Directory;
                END
                CLOSE MoveDatafiles;
                DEALLOCATE MoveDatafiles;
            ';
            IF @New_Datafile_Directory_In_Loop <> '' EXEC (@SQL);

            -- Log file transfer
            SET @SQL = '
                DECLARE @PhysicalName NVARCHAR(260),@ErrMessage VARCHAR(700),@FileName NVARCHAR(255),@FileLogicalName NVARCHAR(255),
                        @NewPath NVARCHAR(500),@FileRelocate NVARCHAR(MAX),@CMDSHELL_Command1 VARCHAR(1000),@CMDSHELL_Command2 VARCHAR(1000),
                        @Error_Line INT,@Error_Message NVARCHAR(300),@Physical_Directory NVARCHAR(500);
                DECLARE MoveLogfiles CURSOR FOR
                    SELECT mf.name,mf.physical_name,
                           RIGHT(physical_name,CHARINDEX(''\'',REVERSE(physical_name))-1),
                           LEFT(physical_name,LEN(mf.physical_name)-CHARINDEX(''\'',REVERSE(physical_name))+1)
                    FROM sys.master_files mf JOIN sys.databases d ON d.database_id = mf.database_id
                    WHERE d.name=''' + @DBName + ''' AND file_id=2;
                OPEN MoveLogfiles;
                FETCH NEXT FROM MoveLogfiles INTO @FileLogicalName,@PhysicalName,@FileName,@Physical_Directory;
                WHILE @@FETCH_STATUS = 0
                BEGIN
                    IF (@Physical_Directory = ''' + @New_Logfile_Directory_In_Loop + ''')
                    BEGIN
                        FETCH NEXT FROM MoveLogfiles INTO @FileLogicalName,@PhysicalName,@FileName,@Physical_Directory;
                        CONTINUE;
                    END
                    BEGIN TRY
                        SET @NewPath = ''' + @New_Logfile_Directory_In_Loop + ''' + @FileName;
            ';
            IF @DBName <> 'TempDB'
                SET @SQL += '
                        TRUNCATE TABLE #tmp;
                        SET @CMDSHELL_Command1 = ''ROBOCOPY "'' + @Physical_Directory + ''" "''' + @New_Logfile_Directory_In_Loop + '''" "'' + @FileName + ''" /J /COPY:DATSOU ' + IIF(@Take_a_Raw_Backup=0,'/MOV ','') + '/MT:8 /R:3 /W:1 /UNILOG+:ROBOout.log /TEE /UNICODE'';
                        INSERT #tmp EXEC xp_cmdshell @CMDSHELL_Command1;
                        SELECT @Error_Line = id FROM #tmp WHERE [output] LIKE ''%ERROR%'';
                        SELECT @Error_Message = (SELECT STRING_AGG([output],CHAR(10)) FROM #tmp WHERE id BETWEEN @Error_Line AND (@Error_Line+1));
                        IF @Error_Line IS NOT NULL PRINT ''Warning: Log copy/move error:'' + ISNULL(@Error_Message,'''');
                ';
            SET @SQL += '
                        SET @FileRelocate = ''ALTER DATABASE ' + QUOTENAME(@DBName) +
                        ' MODIFY FILE (NAME='' + QUOTENAME(@FileLogicalName) + '', FILENAME='''''''' + @NewPath + '''''''')'';
            ';
            IF @DBName <> 'TempDB'
                SET @SQL += '
                        IF ' + CONVERT(CHAR(1),@Take_a_Raw_Backup) + '=0
                            IF (SELECT file_exists FROM sys.dm_os_file_exists(@NewPath)) = 1
                                EXEC (@FileRelocate)
                            ELSE
                                RAISERROR(''Log relocation skipped; physical move failed.'',16,1);
                ';
            ELSE
                SET @SQL += 'EXEC (@FileRelocate);';
            SET @SQL += '
                    END TRY
                    BEGIN CATCH
                        SET @ErrMessage = ''Failure processing log file '' + @PhysicalName + ''. '' + ERROR_MESSAGE();
                        RAISERROR(@ErrMessage,16,1);
                        RETURN;
                    END CATCH
                    FETCH NEXT FROM MoveLogfiles INTO @FileLogicalName,@PhysicalName,@FileName,@Physical_Directory;
                END
                CLOSE MoveLogfiles;
                DEALLOCATE MoveLogfiles;
            ';
            IF @New_Logfile_Directory_In_Loop <> '' EXEC (@SQL);

            -- Bring online and optionally re-add to AG
            IF @DBName <> 'TempDB'
            BEGIN
                SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@DBName) + ' SET ONLINE;';
                IF @Bring_Online_Add_Database_to_AG_Again_if_Removed = 1
                BEGIN
                    EXEC (@SQL);
                    SET @SQL = 'ALTER AVAILABILITY GROUP ' + QUOTENAME(@DB_AG_Name) + ' ADD DATABASE ' + QUOTENAME(@DBName);
                    IF @DB_AG_Name IS NOT NULL EXEC(@SQL);
                END;
                PRINT '';
                SET @DBPrint = 'End ' + IIF(@Take_a_Raw_Backup=0,'movement','copy') +
                               IIF(@Bring_Online_Add_Database_to_AG_Again_if_Removed=1,', database ONLINE' +
                               IIF(@DB_AG_Name IS NOT NULL,' and re-added to AG.','.'),'.') +
                               IIF(@Take_a_Raw_Backup=0,'',' Files ready for attach.');
            END
            ELSE
            BEGIN
                PRINT '';
                SET @DBPrint = 'TempDB relocation recorded; restart instance to apply.';
            END;
            RAISERROR(@DBPrint,0,1) WITH NOWAIT;
        END TRY
        BEGIN CATCH
            DECLARE @PRINT_or_RAISERROR INT = 2;
            DECLARE @ErrMsg NVARCHAR(500)=ERROR_MESSAGE(),
                    @ErrLine NVARCHAR(500)=ERROR_LINE(),
                    @ErrNo NVARCHAR(6)=CONVERT(NVARCHAR(6),ERROR_NUMBER()),
                    @ErrState NVARCHAR(2)=CONVERT(NVARCHAR(2),ERROR_STATE()),
                    @ErrSeverity NVARCHAR(2)=CONVERT(NVARCHAR(2),ERROR_SEVERITY()),
                    @UDErrMsg NVARCHAR(MAX)='Operation error. Msg '+@ErrNo+', Level '+@ErrSeverity+', State '+@ErrState+', Line '+@ErrLine+CHAR(10)+@ErrMsg;
            IF @PRINT_or_RAISERROR = 1 PRINT @UDErrMsg ELSE RAISERROR(@UDErrMsg,16,1);
        END CATCH;

        FETCH NEXT FROM LoopThroughDatabases INTO @DBName;
    END;

    CLOSE LoopThroughDatabases;
    DEALLOCATE LoopThroughDatabases;

    SET @message = '-----------------------------------------------------------------------------------------------------------' + CHAR(10);
    RAISERROR(@message,0,1) WITH NOWAIT;

    SELECT TOP 1 @Count_of_Databases_Affected = id FROM #List_of_Databases_Affected ORDER BY id DESC;
    PRINT 'Number of Databases affected: ' + CONVERT(VARCHAR,@Count_of_Databases_Affected);
    IF @Show_List_of_Databases_Affected = 1
    BEGIN
        SELECT @List_of_Databases_Affected = STRING_AGG(CONVERT(NVARCHAR(MAX),CONVERT(VARCHAR,id)+'. '+DBName),CHAR(10))
        FROM #List_of_Databases_Affected;
        PRINT 'List of Databases affected:' + CHAR(10) + @List_of_Databases_Affected;
    END;

    PRINT '';

    -- Disable features re-enabled
    EXEC sys.sp_configure @configname='cmdshell',@configvalue=0; RECONFIGURE;
    EXEC sys.sp_configure @configname='show advanced options',@configvalue=0; RECONFIGURE;
END;
GO

-- Example execution for single database (raw copy mode)
EXEC dbo.sp_MoveDatabases_Datafiles
    @Perform_CheckDB_First = 1,
    @DatabasesToBeMoved_or_Copied = 'AtlasCoreDB',
    @New_Datafile_Directory = '\\DataOps-DB1\d$\Database Data',
    @New_Logfile_Directory = '\\DataOps-DB1\e$\Database Log',
    @Remove_Database_From_AG_First = 1,
    @Bring_Online_Add_Database_to_AG_Again_if_Removed = 1,
    @Replace_Pattern = '',
    @Replace_String_Replacement = '',
    @Take_a_Raw_Backup = 1,
    @Show_List_of_Databases_Affected = 1;
GO

-- Cleanup sample (drop helper procs)
DROP PROC dbo.usp_PrintLong;
GO
DROP PROC dbo.sp_MoveDatabases_Datafiles;
GO

-- Optional AG operations (examples with anonymized names)
-- ALTER AVAILABILITY GROUP [AG_DataOps] ADD DATABASE [Atlas-TestDB]
-- SELECT sys.fn_hadr_is_primary_replica('Atlas-TestDB')
-- ALTER DATABASE [Atlas-DB] SET MULTI_USER
-- SELECT * FROM sys.dm_exec_sessions WHERE database_id = DB_ID('AtlasFileDB')
-- KILL 62