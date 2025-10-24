# 📦 SQL Server File Copy / Move Utility (ROBOCOPY Wrapper)

---

## 1. Header Explanation 📝

Purpose: Copy or move files/directories using ROBOCOPY via xp_cmdshell with basic validation and status output.


---

## 2. Overview 📘
This script defines a lightweight toolkit to batch copy or move files and directories on the SQL Server host (or reachable paths) using `ROBOCOPY`, driven from T-SQL:
1. User passes a table-valued parameter (`File_Table`) listing source paths and target destinations.
2. The stored procedure `sp_copy_files` validates sources and destinations.
3. It normalizes path formatting (trailing slashes, quoting).
4. It enables `xp_cmdshell` temporarily to run `ROBOCOPY`.
5. It performs copy or move operations (controlled by `@move`).
6. It reports per-item success or warnings and then disables `xp_cmdshell`.

---

## 3. Components 🧩

| Component | Type | Purpose |
|-----------|------|---------|
| `File_Table` | Table Type | Supplies a list of source paths and destination directories. |
| `sp_copy_files` | Stored Procedure | Executes ROBOCOPY operations with validation and messaging. |
| Demo Block | T-SQL Batch | Shows procedure invocation and optional cleanup. |

---

## 4. Procedure Parameters ⚙️

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `@File_Table` | `File_Table` (TVP) | (Required) | Source + destination rows. |
| `@move` | `BIT` | `0` | `1` = move (remove source); `0` = copy. |
| `@Replace_String_Replacement` | `SYSNAME` | `''` | Placeholder (not implemented). |
| `@Replace_Pattern` | `SYSNAME` | `''` | Placeholder (not implemented). |
| `@NO_INFOMSGS` | `BIT` | `0` | Suppress success messages if `1`. |

---

## 5. Processing Flow 🔄

1. Input rows staged into temp table.
2. Paths sanitized (quotes removed, trailing slashes normalized).
3. Destination paths enforced to end with `\`.
4. Advanced options + `xp_cmdshell` enabled.
5. Validate:
   - At least one non-empty destination.
   - At least one existing source (file or directory).
6. Cursor iterates each row:
   - Creates destination directory if needed.
   - Builds `ROBOCOPY` command (file vs directory mode).
   - Executes via `xp_cmdshell`, logs output to `#tmp`.
   - Scans output for the token `ERROR`.
   - Prints success or warning.
7. Disables `xp_cmdshell` and advanced options.
8. Demo shows execution and optional cleanup.

---

## 6. ROBOCOPY Options Used 🛠️

| Option | Meaning |
|--------|---------|
| `/J` | Unbuffered I/O (reduces memory usage). |
| `/COPY:DATSOU` | Copies all file attributes (Data, Attributes, Timestamps, Security, Owner, Audit). |
| `/MOV` / `/MOVE` | Move (remove source) when `@move = 1`. |
| `/MT:8` | Multithreaded (8 threads). |
| `/R:3 /W:1` | Retry 3 times, wait 1 second between attempts. |
| `/E` | Include subdirectories (for directory copy). |
| `/COMPRESS` | Enables NTFS compression during transfer (directory mode). |
| `/UNILOG+:ROBOout.log` | Append Unicode log file. |
| `/TEE /UNICODE` | Echo output to console, ensure Unicode logging. |

---

## 7. Messaging & Error Handling ⚠️

| Aspect | Behavior |
|--------|----------|
| Validation Failure | Raises error and exits early. |
| ROBOCOPY Error Token | Captured via output scan; prints warning. |
| Success Output | Printed unless `@NO_INFOMSGS = 1`. |
| Catch Block | Prints structured diagnostic block per failed iteration. |
| Cleanup | Ensures `xp_cmdshell` disabled post-run. |

---

## 8. Use Cases 💡

| Scenario | How |
|----------|-----|
| One-off server file migration | Populate TVP with sources → run `@move = 1`. |
| Prepare seed files for other host | Use copy mode (`@move = 0`). |
| Scheduled housekeeping | Wrap in SQL Agent job (ensure security review). |
| Bulk directory replication | Provide root folder as a “directory” row. |

---

## 9. Security Considerations 🔐

| Concern | Mitigation |
|---------|------------|
| `xp_cmdshell` exposure | Enabled only inside procedure scope; disabled afterward. |
| Unauthorized paths | Restrict execution to trusted principals. |
| Log file growth (`ROBOout.log`) | Periodically archive/truncate. |
| UNC path permissions | Ensure service account access. |

---

## 10. Performance Notes 🚀

| Factor | Impact |
|--------|--------|
| `/MT:8` threads | Parallelism improves throughput; adjust for IO constraints. |
| Large directory trees | Use staging or split into batches. |
| Network share latency | Consider testing RTT before large moves. |

---

## 11. Table Type Definition 📄

```sql
-- Table type for supplying source and destination paths
IF NOT EXISTS (SELECT 1 FROM sys.types WHERE name = 'File_Table')
    CREATE TYPE File_Table AS TABLE
    (
        [file or directory] NVARCHAR(2000) NOT NULL,
        [Destination]       NVARCHAR(2000) NOT NULL
    );
GO
```

---

## 12. Stored Procedure Source ⚙️

<details>
<summary>(click to expand) The complete 176-line script:</summary>

```sql
-- Stored procedure: copy or move files/directories provided in a File_Table TVP.
CREATE OR ALTER PROC dbo.sp_copy_files
    @File_Table                File_Table READONLY,
    @move                      BIT              = 0,    -- 1 = move; 0 = copy
    @Replace_String_Replacement SYSNAME         = '',   -- (placeholder, currently unused)
    @Replace_Pattern           SYSNAME          = '',   -- (placeholder, currently unused)
    @NO_INFOMSGS               BIT              = 0     -- 1 = suppress success info messages
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PhysicalName        NVARCHAR(2000),
            @Destination         NVARCHAR(2000),
            @CMDSHELL_Command1   VARCHAR(1000),
            @CMDSHELL_Command2   VARCHAR(1000),
            @FileName            NVARCHAR(255),
            @New_Datafile_Dir    NVARCHAR(300),
            @Physical_Directory  NVARCHAR(500),
            @NewPath             NVARCHAR(500),
            @Error_Line          INT,
            @message             NVARCHAR(300),
            @isfile              BIT;

    -- Stage input into a work table and normalize path formatting.
    SELECT * INTO #File_Table FROM @File_Table;

    UPDATE #File_Table
    SET [file or directory] = TRIM(REPLACE([file or directory], '"', ''));

    UPDATE #File_Table
    SET Destination = TRIM(REPLACE(Destination, '"', ''));

    -- Remove trailing backslashes from source path (except drive root).
    WHILE @@ROWCOUNT <> 0
        UPDATE #File_Table
        SET [file or directory] = LEFT([file or directory], LEN([file or directory]) - 1)
        WHERE RIGHT([file or directory], 1) = '\' AND LEN([file or directory]) > 3;

    -- Ensure destination ends with backslash.
    UPDATE #File_Table
    SET Destination += '\'
    WHERE RIGHT(Destination, 1) <> '\' AND Destination <> '';

    -- Enable required advanced options and xp_cmdshell.
    EXEC sys.sp_configure 'show advanced options', 1; RECONFIGURE;
    EXEC sys.sp_configure 'cmdshell', 1; RECONFIGURE;

    CREATE TABLE #tmp (id INT IDENTITY PRIMARY KEY, [output] NVARCHAR(500));

    -- Validate destinations.
    IF NOT EXISTS (SELECT 1 FROM #File_Table WHERE ISNULL(Destination, '') <> '')
    BEGIN
        RAISERROR('All the destinations you have specified are invalid', 16, 1);
        RETURN 1;
    END;

    -- Validate source existence.
    IF NOT EXISTS (
        SELECT 1
        FROM #File_Table
        CROSS APPLY sys.dm_os_file_exists([file or directory])
        WHERE (file_exists + file_is_a_directory) = 1
    )
    BEGIN
        RAISERROR('None of the files you want to copy exist.', 16, 1);
        RETURN 1;
    END;

    -- Cursor over each source item.
    DECLARE Copier CURSOR FAST_FORWARD FOR
        SELECT
            [file or directory],
            RIGHT([file or directory], CHARINDEX('\', REVERSE([file or directory])) - 1) AS FileName,
            LEFT([file or directory], LEN([file or directory]) - CHARINDEX('\', REVERSE([file or directory])) + 1) AS physical_directory,
            Destination
        FROM #File_Table;

    OPEN Copier;
    FETCH NEXT FROM Copier INTO @PhysicalName, @FileName, @Physical_Directory, @Destination;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            IF @Destination <> '' EXEC sys.xp_create_subdir @Destination;

            TRUNCATE TABLE #tmp;
            SET @NewPath = @Destination + @FileName;

            IF (SELECT file_exists FROM sys.dm_os_file_exists(@PhysicalName)) = 1
            BEGIN
                SET @CMDSHELL_Command1 =
                    'ROBOCOPY "' + @Physical_Directory + '" "' + @Destination + '" "' + @FileName +
                    '" /J /COPY:DATSOU ' + IIF(@move = 1, '/MOV', '') +
                    ' /MT:8 /R:3 /W:1 /UNILOG+:ROBOout.log /TEE /UNICODE';
                SET @isfile = 1;
                INSERT #tmp EXEC master.sys.xp_cmdshell @CMDSHELL_Command1;
            END
            ELSE IF (SELECT file_is_a_directory FROM sys.dm_os_file_exists(@PhysicalName)) = 1
            BEGIN
                SET @CMDSHELL_Command1 =
                    'ROBOCOPY ' + IIF(@move = 1, '/MOVE', '') + ' /E /COMPRESS "' + @PhysicalName + '" "' + @NewPath + '"';
                SET @isfile = 0;
                INSERT #tmp EXEC master.sys.xp_cmdshell @CMDSHELL_Command1;
            END
            ELSE
            BEGIN
                RAISERROR('The source file/directory you specified does not exist.', 16, 1);
            END;

            SELECT @Error_Line = id FROM #tmp WHERE [output] LIKE '%ERROR%';
            SELECT @message = (
                SELECT STRING_AGG([output], CHAR(10))
                FROM #tmp
                WHERE id BETWEEN @Error_Line AND (@Error_Line + 1)
            );

            IF @Error_Line IS NOT NULL
            BEGIN
                DECLARE @Warning_Message NVARCHAR(300) =
                    'Warning: Copy process failed:' + CHAR(10) + ISNULL(@message, '');
                PRINT @Warning_Message;
            END
            ELSE
            BEGIN
                IF (SELECT file_exists + file_is_a_directory FROM sys.dm_os_file_exists(@NewPath)) = 1
                BEGIN
                    IF @NO_INFOMSGS = 0
                    BEGIN
                        SET @message =
                            'Success: ' + IIF(@isfile = 1, 'File', 'Folder') + ' "' + @FileName + '" ' +
                            IIF(@move = 1, 'moved', 'copied') + ' from "' + @Physical_Directory + '" to "' + @Destination + '".';
                        RAISERROR(@message, 0, 1) WITH NOWAIT;
                    END
                END
            END
        END TRY
        BEGIN CATCH
            DECLARE @PRINT_or_RAISERROR INT = 1;  -- 1=PRINT, 2=RAISERROR
            DECLARE @ErrMsg NVARCHAR(500) = ERROR_MESSAGE();
            DECLARE @ErrLine NVARCHAR(10) = CONVERT(NVARCHAR(10), ERROR_LINE());
            DECLARE @ErrNo NVARCHAR(6) = CONVERT(NVARCHAR(6), ERROR_NUMBER());
            DECLARE @ErrState NVARCHAR(3) = CONVERT(NVARCHAR(3), ERROR_STATE());
            DECLARE @ErrSeverity NVARCHAR(2) = CONVERT(NVARCHAR(2), ERROR_SEVERITY());
            DECLARE @UDErrMsg NVARCHAR(MAX) =
                'Operation warning: iteration skipped.' + CHAR(10) +
                'Msg ' + @ErrNo + ', Level ' + @ErrSeverity + ', State ' + @ErrState +
                ', Line ' + @ErrLine + CHAR(10) + @ErrMsg;

            IF @PRINT_or_RAISERROR = 1
            BEGIN
                PRINT @UDErrMsg;
                PRINT '';
                PRINT '--------------------------------------------------------------------------------';
                PRINT '';
            END
            ELSE
            BEGIN
                PRINT '';
                PRINT '--------------------------------------------------------------------------------';
                PRINT '';
                RAISERROR(@UDErrMsg, 16, 1);
            END
        END CATCH;

        FETCH NEXT FROM Copier INTO @PhysicalName, @FileName, @Physical_Directory, @Destination;
    END;

    CLOSE Copier;
    DEALLOCATE Copier;

    PRINT '';

    -- Disable xp_cmdshell and advanced options reset.
    EXEC sys.sp_configure 'cmdshell', 0; RECONFIGURE;
    EXEC sys.sp_configure 'show advanced options', 0; RECONFIGURE;
END;
GO
```

</details>

---

## 13. Demo Execution & Cleanup ▶️

```sql
-- Demo execution block: prepare input table and invoke copy/move.
DECLARE @File_Table File_Table;
INSERT @File_Table ([file or directory], Destination)
VALUES
    (N'D:\1\d1\\\\\\', N'D:\2'),
    (N'D:\1\f1.docx',  N'D:\2');

EXEC dbo.sp_copy_files
     @File_Table                 = @File_Table,
     @move                       = 1,
     @Replace_String_Replacement = '',
     @Replace_Pattern            = '',
     @NO_INFOMSGS                = 0;
GO

-- Optional cleanup
DROP PROCEDURE dbo.sp_copy_files;
GO
```

---

## 14. Operational Checklist ✅

| Step | Done |
|------|------|
| Validate source paths | ☐ |
| Confirm destination permissions | ☐ |
| Decide copy vs move (`@move`) | ☐ |
| Review ROBOCOPY log (`ROBOout.log`) | ☐ |
| Disable `xp_cmdshell` verified | ☐ |

---

## 15. Enhancement Ideas 🚀

| Idea | Benefit |
|------|---------|
| Add retry logic parsing ROBOCOPY exit codes | Robust failure handling. |
| Implement rename placeholders | Dynamic filename transformations. |
| Add dry-run mode | Safety preview. |
| Aggregate summary table | Auditing & metrics. |
| Parameter for thread count (`/MT`) | Tunable performance. |

---

**End** ✨