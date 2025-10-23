# 🚚 Raw Copy / Movement of SQL Server Database Files Between Locations or Servers

---

## 1. Overview 📘
This document describes two `T-SQL` stored procedures plus an example workflow that:
- Copies or moves (`raw backup` mode vs relocation) SQL Server database data (`.mdf`/`.ndf`) and log (`.ldf`) files to new directories (local or UNC).
- Optionally renames files using a pattern + replacement.
- Handles `TempDB` (records relocation; requires restart) and excludes databases that are primary replicas in an Availability Group.
- Supports a non‑destructive “raw copy” mode (`@Take_a_Raw_Backup = 1`) that leaves catalog pointers unchanged so files can be attached on another server.
- Automates directory creation, enables `xp_cmdshell`, performs `ROBOCOPY`-based transfers, alters file metadata, and restores online status.

---

## 2. Components 🧩
1. Helper procedure `dbo.sp_PrintLong` (prints very long strings in 4000‑character chunks).
2. Main procedure `dbo.sp_MoveDatabases_Datafiles` (core movement / raw copy logic).
3. Example workflow:
   - Builds a target database name.
   - Removes it from an Availability Group.
   - Executes raw copy.
   - Re‑adds the database to the Availability Group.
   - Cleans up helper objects.

---

## 3. Parameters (Main Procedure) ⚙️

| Parameter | Type | Default | Purpose |
|-----------|------|---------|---------|
| `@DatabasesToBeMoved` | `SYSNAME` | '' (all user DBs) | Comma-separated list of database names (empty = all user DBs except system / AG primary). |
| `@New_Datafile_Directory` | `NVARCHAR(300)` | `D:\Database Data` | Destination for data files (blank = keep original folders). |
| `@New_Logfile_Directory` | `NVARCHAR(300)` | `E:\Database Log` | Destination for log files (blank = keep original folders). |
| `@Replace_String_Replacement` | `SYSNAME` | '' | Suffix/prefix appended when renaming (used with pattern). |
| `@Replace_Pattern` | `SYSNAME` | '' | Pattern inserted before/after original filename (basic rename strategy). |
| `@Take_a_Raw_Backup` | `BIT` | 0 | `0` = move + update catalog; `1` = copy only (leave catalog unchanged). |

---

## 4. High-Level Workflow 🔄

1. Normalize inputs; ensure destination paths formed with trailing `\`.
2. Create target folders (if provided).
3. Enable `xp_cmdshell` (temporarily) for `ROBOCOPY` usage.
4. Split database list (`STRING_SPLIT`).
5. Filter valid databases (exclude system, AG primary replicas, and invalid states).
6. For each database:
   1. Determine destination paths (inherit from source if blank).
   2. If movement needed: set single user, flush log, checkpoint, offline (except `TempDB`).
   3. For each data file:
      - Copy/move with `ROBOCOPY` (raw or move).
      - Optional rename.
      - Issue `ALTER DATABASE ... MODIFY FILE` (if not raw copy mode).
   4. For the log file: similar handling (file_id = 2).
   5. Bring database back online (unless `TempDB`).
7. Disable `xp_cmdshell`.
8. Example script: AG removal → copy → AG re-add.

---

## 5. Safety & Considerations ⚠️

| Topic | Note |
|-------|------|
| Availability Groups | Must remove database before relocating files (unless using raw copy to seed elsewhere). |
| Permissions | Requires `ALTER DATABASE`, `xp_cmdshell`, filesystem + share access, `ROBOCOPY` availability. |
| Raw Copy Mode | Leaves catalog unchanged; copied files become a detached “seed” for another server. |
| TempDB | File metadata updated; restart required for new physical locations to take effect. |
| Error Handling | TRY/CATCH blocks surface failures via `RAISERROR`. |
| File Renaming | Minimal pattern logic—adjust if more complex transformations required. |

---

## 6. Usage Examples ▶️

Preview raw copy for a specific database (no rename):
```
EXEC dbo.sp_MoveDatabases_Datafiles
    @DatabasesToBeMoved        = 'SalesDB',
    @New_Datafile_Directory    = '\\ServerA\D$\SQLData',
    @New_Logfile_Directory     = '\\ServerA\E$\SQLLog',
    @Take_a_Raw_Backup         = 1;
```

Relocate and rename (movement):
```
EXEC dbo.sp_MoveDatabases_Datafiles
    @DatabasesToBeMoved        = 'SalesDB',
    @New_Datafile_Directory    = 'F:\SQLData_New',
    @New_Logfile_Directory     = 'G:\SQLLog_New',
    @Replace_Pattern           = '2025_',
    @Replace_String_Replacement= '_migrated',
    @Take_a_Raw_Backup         = 0;
```

---

## 7. Full Code Modules 💻

### 7.1 Helper Procedure: Print Long Strings

```sql
-- Helper proc: print very long strings in chunks
IF OBJECT_ID('dbo.sp_PrintLong','P') IS NOT NULL
    DROP PROC dbo.sp_PrintLong;
GO
CREATE OR ALTER PROC dbo.sp_PrintLong
    @String NVARCHAR(MAX)
AS
BEGIN
    DECLARE @Chunk NVARCHAR(4000);
    WHILE LEN(@String) > 0
    BEGIN
        SET @Chunk = LEFT(@String,4000);
        PRINT @Chunk;
        SET @String = SUBSTRING(@String,LEN(@Chunk)+1,8000000);
    END
END;
GO
```

### 7.2 Main Procedure: Move / Raw Copy Database Files

<details>
<summary>(click to expand) The complete 274-line script:</summary>

```sql
-- Main proc: move or copy database datafiles (and logfiles) to new directories
IF OBJECT_ID('dbo.sp_MoveDatabases_Datafiles','P') IS NOT NULL
    DROP PROC dbo.sp_MoveDatabases_Datafiles;
GO
CREATE OR ALTER PROC dbo.sp_MoveDatabases_Datafiles
      @DatabasesToBeMoved           SYSNAME        = ''
    , @New_Datafile_Directory       NVARCHAR(300)  = 'D:\Database Data'
    , @New_Logfile_Directory        NVARCHAR(300)  = 'E:\Database Log'
    , @Replace_String_Replacement   SYSNAME        = ''
    , @Replace_Pattern              SYSNAME        = ''
    , @Take_a_Raw_Backup            BIT            = 0   -- 0 = move, 1 = raw copy only
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize inputs
    SET @DatabasesToBeMoved         = TRIM(ISNULL(@DatabasesToBeMoved,''));
    SET @Replace_String_Replacement = TRIM(ISNULL(@Replace_String_Replacement,''));
    SET @Replace_Pattern            = TRIM(ISNULL(@Replace_Pattern,''));
    SET @Take_a_Raw_Backup          = ISNULL(@Take_a_Raw_Backup,0);
    SET @New_Datafile_Directory     = TRIM(ISNULL(@New_Datafile_Directory,''));
    SET @New_Logfile_Directory      = TRIM(ISNULL(@New_Logfile_Directory,''));

    IF @New_Datafile_Directory = '' AND @New_Logfile_Directory = '' AND @Replace_Pattern = '' AND @Replace_String_Replacement = ''
        RAISERROR('@New_Datafile_Directory and @New_Logfile_Directory are both undefined.',16,1);

    IF @New_Datafile_Directory <> '' AND RIGHT(@New_Datafile_Directory,1) <> '\'
        SET @New_Datafile_Directory += '\';
    IF @New_Logfile_Directory <> '' AND RIGHT(@New_Logfile_Directory,1) <> '\'
        SET @New_Logfile_Directory += '\';

    -- Ensure destination folders exist
    IF @New_Datafile_Directory <> '' EXEC sys.xp_create_subdir @New_Datafile_Directory;
    IF @New_Logfile_Directory <> '' EXEC sys.xp_create_subdir @New_Logfile_Directory;

    -- Enable xp_cmdshell for copy/move operations
    EXEC sys.sp_configure 'show advanced options', 1; RECONFIGURE;
    EXEC sys.sp_configure 'cmdshell', 1; RECONFIGURE;

    -- Temp output logging table for xp_cmdshell
    IF OBJECT_ID('tempdb..#tmp') IS NOT NULL DROP TABLE #tmp;
    CREATE TABLE #tmp (id INT IDENTITY PRIMARY KEY, [output] NVARCHAR(500));

    -- Split database list
    IF OBJECT_ID('tempdb..#dbnames') IS NOT NULL DROP TABLE #dbnames;
    SELECT TRIM([value]) dbname INTO #dbnames FROM STRING_SPLIT(@DatabasesToBeMoved,',');

    DECLARE @message NVARCHAR(2000);

    -- Validate target databases (exclude AG primaries and unsupported states)
    IF NOT EXISTS (
        SELECT 1
        FROM sys.databases d
        JOIN #dbnames n ON d.name LIKE CASE WHEN @DatabasesToBeMoved = '' THEN '%' ELSE n.dbname END
        WHERE database_id > CASE WHEN @DatabasesToBeMoved = '' THEN 4 ELSE 1 END
          AND state IN (0,1,2,3,5,6)
          AND d.user_access = 0
          AND sys.fn_hadr_is_primary_replica(d.name) IS NULL
    )
    BEGIN
        SET @message = 'No Database was found with your given criteria that is not a member of an Availability Group.' + CHAR(10) +
                       'Note: To move/copy datafiles of databases which are members of an AG, you must first remove them from AG.';
        RAISERROR(@message,16,1);
    END

    -- Cursor over candidate databases
    DECLARE LoopThroughDatabases CURSOR FAST_FORWARD FOR
        SELECT d.name
        FROM sys.databases d
        JOIN #dbnames n ON d.name LIKE CASE WHEN @DatabasesToBeMoved = '' THEN '%' ELSE n.dbname END
        WHERE database_id > CASE WHEN @DatabasesToBeMoved = '' THEN 4 ELSE 1 END
          AND state IN (0,1,2,3,5,6)
          AND d.user_access = 0
          AND sys.fn_hadr_is_primary_replica(d.name) IS NULL;

    DECLARE @DBName SYSNAME;
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @New_Datafile_Directory_In_Loop NVARCHAR(300);
    DECLARE @New_Logfile_Directory_In_Loop NVARCHAR(300);
    DECLARE @ErrMsg NVARCHAR(500);
    DECLARE @DBPrint NVARCHAR(256);

    OPEN LoopThroughDatabases;
    FETCH NEXT FROM LoopThroughDatabases INTO @DBName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @DBPrint = 'Beginning ' + IIF(@Take_a_Raw_Backup=0,'movement','raw copy') + ' of Database: ' + @DBName;
        PRINT REPLICATE('-',107);
        PRINT @DBPrint;
        PRINT '';

        -- Resolve effective target directories (default to source if blank)
        IF @New_Datafile_Directory = ''
            SELECT @New_Datafile_Directory_In_Loop = LEFT(physical_name,LEN(physical_name)-CHARINDEX('\',REVERSE(physical_name))+1)
            FROM sys.master_files WHERE database_id = DB_ID(@DBName) AND file_id = 1;
        ELSE
            SET @New_Datafile_Directory_In_Loop = @New_Datafile_Directory;

        IF @New_Logfile_Directory = ''
            SELECT @New_Logfile_Directory_In_Loop = LEFT(physical_name,LEN(physical_name)-CHARINDEX('\',REVERSE(physical_name))+1)
            FROM sys.master_files WHERE database_id = DB_ID(@DBName) AND file_id = 2;
        ELSE
            SET @New_Logfile_Directory_In_Loop = @New_Logfile_Directory;

        BEGIN TRY
            -- If ONLINE/EMERGENCY evaluate necessity of movement
            IF (SELECT state FROM sys.databases WHERE database_id = DB_ID(@DBName)) IN (0,5)
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM (
                        SELECT CASE type
                                 WHEN 1 THEN @New_Logfile_Directory_In_Loop + RIGHT(physical_name, CHARINDEX('\',REVERSE(physical_name))-1)
                                 ELSE @New_Datafile_Directory_In_Loop + RIGHT(physical_name, CHARINDEX('\',REVERSE(physical_name))-1)
                               END AS TargetPath
                        FROM sys.master_files
                        WHERE database_id = DB_ID(@DBName)
                        EXCEPT
                        SELECT physical_name FROM sys.master_files WHERE database_id = DB_ID(@DBName)
                    ) t
                )
                BEGIN
                    PRINT 'No Datafile movement for the database ' + QUOTENAME(@DBName) + ' is required.';
                    FETCH NEXT FROM LoopThroughDatabases INTO @DBName;
                    CONTINUE;
                END

                -- Prepare database for file operations (except TempDB)
                IF @DBName <> 'TempDB'
                BEGIN
                    SET @SQL = '
                        USE ' + QUOTENAME(@DBName) + ';
                        ALTER DATABASE ' + QUOTENAME(@DBName) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                        EXEC sys.sp_flush_log;
                        CHECKPOINT;
                        ALTER DATABASE ' + QUOTENAME(@DBName) + ' SET MULTI_USER;
                        USE master;
                        ALTER DATABASE ' + QUOTENAME(@DBName) + ' SET OFFLINE;
                    ';
                    EXEC (@SQL);
                END
            END

            -- Datafiles move/copy block
            SET @SQL = '
                DECLARE @PhysicalName NVARCHAR(260),
                        @ErrMessage VARCHAR(700),
                        @FileName NVARCHAR(255),
                        @FileLogicalName NVARCHAR(255),
                        @NewPath NVARCHAR(500),
                        @FileRelocate NVARCHAR(MAX),
                        @CMDSHELL_Command1 VARCHAR(1000),
                        @CMDSHELL_Command2 VARCHAR(1000),
                        @Error_Line INT,
                        @Error_Message NVARCHAR(300),
                        @Physical_Directory NVARCHAR(500);

                DECLARE MoveDatafiles CURSOR FOR
                    SELECT mf.name,
                           mf.physical_name,
                           RIGHT(physical_name, CHARINDEX(''\'',REVERSE(physical_name))-1),
                           LEFT(physical_name, LEN(mf.physical_name)-CHARINDEX(''\'',REVERSE(physical_name))+1)
                    FROM sys.master_files mf
                    JOIN sys.databases d ON d.database_id = mf.database_id
                    WHERE d.name = ''' + @DBName + ''' AND file_id <> 2;

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
                            SET @CMDSHELL_Command1 = ''ROBOCOPY "'' + @Physical_Directory + ''" "''' + @New_Datafile_Directory_In_Loop + '''" "'' + @FileName + ''" /J /COPY:DATSOU ' + CASE WHEN @Take_a_Raw_Backup=0 THEN '/MOV ' ELSE '' END + '/MT:8 /R:3 /W:1 /UNILOG+:ROBOout.log /TEE /UNICODE'';
                            INSERT #tmp EXEC xp_cmdshell @CMDSHELL_Command1;
                            IF (''' + @Replace_Pattern + ''' <> '''' OR ''' + @Replace_String_Replacement + ''' <> '''')
                            BEGIN
                                SET @CMDSHELL_Command2 = ''CD "''' + @New_Datafile_Directory_In_Loop + '''" && REN '' + @FileName + '' '' + (''' + @Replace_Pattern + ''' + @FileName + ''' + @Replace_String_Replacement + ''')'';
                            END
                        END
                        ELSE
                        BEGIN
                            EXEC xp_create_subdir @NewPath;
                            SET @CMDSHELL_Command1 = ''ROBOCOPY ' + CASE WHEN @Take_a_Raw_Backup=0 THEN '/MOV ' ELSE '' END + '/E /COMPRESS "'' + @PhysicalName + ''" "'' + @NewPath + ''"'';
                            INSERT #tmp EXEC xp_cmdshell @CMDSHELL_Command1;
                        END
                        SELECT @Error_Line = id FROM #tmp WHERE [output] LIKE ''%ERROR%'';
                        SELECT @Error_Message = (SELECT STRING_AGG([output],CHAR(10)) FROM #tmp WHERE id BETWEEN @Error_Line AND (@Error_Line+1));
                        IF @Error_Line IS NOT NULL
                        BEGIN
                            PRINT ''Warning: Copy/Move failure:'' + CHAR(10) + ISNULL(@Error_Message,'''');
                        END
                ';

            SET @SQL += '
                        SET @FileRelocate = ''
                            ALTER DATABASE ' + QUOTENAME(@DBName) + '
                            MODIFY FILE (NAME = '' + QUOTENAME(@FileLogicalName) + '', FILENAME = '''''' + @NewPath + '''''')
                        '';
            ';

            IF @DBName <> 'TempDB'
                SET @SQL += '
                        IF ' + CONVERT(CHAR(1),@Take_a_Raw_Backup) + ' = 0
                            IF (SELECT file_exists + file_is_a_directory FROM sys.dm_os_file_exists(@NewPath)) = 1
                                EXEC (@FileRelocate)
                            ELSE
                                RAISERROR(''File movement failed; catalog relocation skipped.'',16,1);
                ';
            ELSE
                SET @SQL += 'EXEC (@FileRelocate);';

            SET @SQL += '
                    END TRY
                    BEGIN CATCH
                        SET @ErrMessage = ''Failure moving/copying datafile "''
                                          + @PhysicalName + ''". System Error:'' + CHAR(10) + ERROR_MESSAGE();
                        RAISERROR(@ErrMessage,16,1);
                        RETURN;
                    END CATCH
                    FETCH NEXT FROM MoveDatafiles INTO @FileLogicalName,@PhysicalName,@FileName,@Physical_Directory;
                END
                CLOSE MoveDatafiles;
                DEALLOCATE MoveDatafiles;
            ';

            IF @New_Datafile_Directory_In_Loop <> '' EXEC (@SQL);

            -- Logfiles move/copy block
            SET @SQL = '
                DECLARE @PhysicalName NVARCHAR(260),
                        @ErrMessage VARCHAR(700),
                        @FileName NVARCHAR(255),
                        @FileLogicalName NVARCHAR(255),
                        @NewPath NVARCHAR(500),
                        @FileRelocate NVARCHAR(MAX),
                        @CMDSHELL_Command1 VARCHAR(1000),
                        @CMDSHELL_Command2 VARCHAR(1000),
                        @Error_Line INT,
                        @Error_Message NVARCHAR(300),
                        @Physical_Directory NVARCHAR(500);

                DECLARE MoveLogfiles CURSOR FOR
                    SELECT mf.name,
                           mf.physical_name,
                           RIGHT(physical_name,CHARINDEX(''\'',REVERSE(physical_name))-1),
                           LEFT(physical_name,LEN(mf.physical_name)-CHARINDEX(''\'',REVERSE(physical_name))+1)
                    FROM sys.master_files mf
                    JOIN sys.databases d ON d.database_id = mf.database_id
                    WHERE d.name=''' + @DBName + ''' AND file_id = 2;

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
                        SET @CMDSHELL_Command1 = ''ROBOCOPY "'' + @Physical_Directory + ''" "''' + @New_Logfile_Directory_In_Loop + '''" "'' + @FileName + ''" /J /COPY:DATSOU ' + CASE WHEN @Take_a_Raw_Backup=0 THEN '/MOV ' ELSE '' END + '/MT:8 /R:3 /W:1 /UNILOG+:ROBOout.log /TEE /UNICODE'';
                        PRINT @CMDSHELL_Command1;
                        INSERT #tmp EXEC xp_cmdshell @CMDSHELL_Command1;
                        SELECT @Error_Line = id FROM #tmp WHERE [output] LIKE ''%ERROR%'';
                        SELECT @Error_Message = (SELECT STRING_AGG([output],CHAR(10)) FROM #tmp WHERE id BETWEEN @Error_Line AND (@Error_Line+1));
                        IF @Error_Line IS NOT NULL
                        BEGIN
                            PRINT ''Warning: Copy/Move failure:'' + CHAR(10) + ISNULL(@Error_Message,'''');
                        END
                ';

            SET @SQL += '
                        SET @FileRelocate = ''
                            ALTER DATABASE ' + QUOTENAME(@DBName) + '
                            MODIFY FILE (NAME = '' + QUOTENAME(@FileLogicalName) + '', FILENAME = '''''' + @NewPath + '''''')
                        '';
            ';

            IF @DBName <> 'TempDB'
                SET @SQL += '
                        IF ' + CONVERT(CHAR(1),@Take_a_Raw_Backup) + ' = 0
                            IF (SELECT file_exists FROM sys.dm_os_file_exists(@NewPath)) = 1
                                EXEC (@FileRelocate)
                            ELSE
                                RAISERROR(''File movement failed; catalog relocation skipped.'',16,1);
                ';
            ELSE
                SET @SQL += 'EXEC (@FileRelocate);';

            SET @SQL += '
                    END TRY
                    BEGIN CATCH
                        SET @ErrMessage = ''Failure moving/copying log file "''
                                          + @PhysicalName + ''". System Error:'' + CHAR(10) + ERROR_MESSAGE();
                        RAISERROR(@ErrMessage,16,1);
                        RETURN;
                    END CATCH
                    FETCH NEXT FROM MoveLogfiles INTO @FileLogicalName,@PhysicalName,@FileName,@Physical_Directory;
                END
                CLOSE MoveLogfiles;
                DEALLOCATE MoveLogfiles;
            ';
            IF @New_Logfile_Directory_In_Loop <> '' EXEC (@SQL);

            -- Bring database back online (non-TempDB)
            IF @DBName <> 'TempDB'
            BEGIN
                SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@DBName) + ' SET ONLINE;';
                EXEC (@SQL);
                PRINT '';
                SET @DBPrint = 'End database ' + IIF(@Take_a_Raw_Backup=0,'movement','files copy') +
                               '. If you see no errors, the database is ONLINE.' +
                               IIF(@Take_a_Raw_Backup=0,'',' You can now attach these files elsewhere.');
            END
            ELSE
            BEGIN
                PRINT '';
                SET @DBPrint = 'TempDB file relocation recorded. Restart instance to apply.';
            END
            PRINT @DBPrint;

        END TRY
        BEGIN CATCH
            DECLARE @PRINT_or_RAISERROR INT = 2;
            DECLARE @ErrLine NVARCHAR(10) = CONVERT(NVARCHAR(10),ERROR_LINE());
            DECLARE @ErrNo NVARCHAR(6) = CONVERT(NVARCHAR(6),ERROR_NUMBER());
            DECLARE @ErrState NVARCHAR(3) = CONVERT(NVARCHAR(3),ERROR_STATE());
            DECLARE @ErrSeverity NVARCHAR(2) = CONVERT(NVARCHAR(2),ERROR_SEVERITY());
            DECLARE @UDErrMsg NVARCHAR(MAX) =
                'Operation error (skipping database). System message:' + CHAR(10) +
                'Msg ' + @ErrNo + ', Level ' + @ErrSeverity + ', State ' + @ErrState +
                ', Line ' + @ErrLine + CHAR(10) + ERROR_MESSAGE();
            IF @PRINT_or_RAISERROR = 1
                PRINT @UDErrMsg;
            ELSE
                RAISERROR(@UDErrMsg,16,1);
        END CATCH

        FETCH NEXT FROM LoopThroughDatabases INTO @DBName;
    END
    CLOSE LoopThroughDatabases;
    DEALLOCATE LoopThroughDatabases;

    PRINT REPLICATE('-',107) + CHAR(10);

    -- Disable xp_cmdshell if enabled by this proc
    EXEC sys.sp_configure 'cmdshell', 0; RECONFIGURE;
    EXEC sys.sp_configure 'show advanced options', 0; RECONFIGURE;
END;
GO
```

</details>

### 7.3 Example Workflow (AG Removal → Raw Copy → AG Re-Add)

```sql
-- Example variables and AG removal/add cycle for a target database
DECLARE @SQL NVARCHAR(MAX);
DECLARE @DBName_Raw SYSNAME = 'analytics';
DECLARE @DBName SYSNAME = 'org-' + @DBName_Raw + 'DB';
PRINT @DBName;

-- Remove database from Availability Group
SET @SQL = '
ALTER AVAILABILITY GROUP [AG_DataOps]
REMOVE DATABASE ' + QUOTENAME(@DBName) + ';';
EXEC (@SQL);

-- Execute movement / raw copy (adjust network paths as needed)
EXEC dbo.sp_MoveDatabases_Datafiles
      @DatabasesToBeMoved        = @DBName
    , @New_Datafile_Directory    = '\\DataOps-DB1\D$\Database Data'
    , @New_Logfile_Directory     = '\\DataOps-DB1\E$\Database Log'
    , @Replace_Pattern           = ''
    , @Replace_String_Replacement= ''
    , @Take_a_Raw_Backup         = 1;

-- Re-add database to Availability Group
SET @SQL = '
USE master;
ALTER AVAILABILITY GROUP [AG_DataOps]
ADD DATABASE ' + QUOTENAME(@DBName) + ';';
EXEC (@SQL);
GO

-- Cleanup helper procs if desired
DROP PROC dbo.sp_PrintLong;
GO
DROP PROC dbo.sp_MoveDatabases_Datafiles;
GO
```

---

## 8. Checklist ✅

| Task | Status |
|------|--------|
| Tested in non‑production | ☐ |
| Verified free disk space | ☐ |
| Confirmed AG removal (if needed) | ☐ |
| Raw copy vs move decision made | ☐ |
| Post-move integrity checks run (DBCC CHECKDB) | ☐ |
| `xp_cmdshell` re-disabled | ☐ |

---

## 9. Enhancement Ideas 🚀

| Area | Idea |
|------|------|
| Logging | Persist operations + timings in an audit table. |
| Progress | Emit percentage or file size totals. |
| Rename Logic | Add pattern-based regex replacement. |
| Parallelism | Use PowerShell / external orchestrator for large fleets. |
| Validation | Pre-flight checklist (space, permissions, AG state). |

---

**END** ✨