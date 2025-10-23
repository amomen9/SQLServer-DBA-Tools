# 🗄️ Automated Attachment of Detached Databases (`sys.sp_attach_db` Utility)

---

## 1. Overview 📘
This markdown documents a single `T-SQL` automation script that:
- Scans a root directory for detached `*.mdf` data files.
- Extracts metadata using `DBCC CHECKPRIMARYFILE`.
- Dynamically builds and executes `sys.sp_attach_db` statements.
- Implements structured error handling (choice of `PRINT` or `RAISERROR`).
- Attaches each discovered database without altering original functionality.

The explanation header from the script is preserved below.

---

## 2. Script Header (Original Explanation) 📝
```
-- Script:              Automated attachment of detached databases
-- Purpose:             Enumerate *.mdf files in a root folder, extract metadata with DBCC CHECKPRIMARYFILE,
--                      then build and execute sys.sp_attach_db for each set of files. Provides robust
--                      error handling with optional PRINT vs RAISERROR output mode.
```

---

## 3. Execution Flow 🔄

### 3.1 Setup
1. Enable `SET NOCOUNT ON`.
2. Drop any leftover temp tables.

### 3.2 Metadata Structures
1. Create `#DataFilePaths` for file-level records.
2. Create `#DBDetails` for database properties (includes database name).

### 3.3 Enumeration
1. Cursor (`Attacher`) lists all `*.mdf` files via `sys.dm_os_enumerate_filesystem`.

### 3.4 Per-File Processing
1. Clear temp tables.
2. Run `DBCC CHECKPRIMARYFILE` option `3` (file list).
3. Run `DBCC CHECKPRIMARYFILE` option `2` (properties).
4. Construct dynamic `EXEC sys.sp_attach_db` statement with parameters.
5. Print and execute the attachment command.

### 3.5 Error Handling
1. Inner TRY/CATCH: attachment-specific failures.
2. Outer TRY/CATCH: metadata extraction failures.
3. Output mode controlled by `@PRINT_or_RAISERROR` (1 vs 2).

### 3.6 Cleanup
1. Advance cursor.
2. Close and deallocate after loop.

---

## 4. Key Components 🧩

| Component | Purpose |
|-----------|---------|
| `sys.dm_os_enumerate_filesystem` | Lists files matching pattern (`*.mdf`). |
| `DBCC CHECKPRIMARYFILE` | Extracts file list & database name from primary file. |
| `STRING_AGG` | Builds parameter list for dynamic attach statement. |
| `sys.sp_attach_db` | Attaches the collected file set as a database. |
| `TRY...CATCH` | Captures and formats errors. |

---

## 5. Variables & Controls ⚙️

| Variable | Description |
|----------|-------------|
| `@path` | Current `.mdf` file full path. |
| `@PRINT_or_RAISERROR` | Error reporting mode (`1 = PRINT`, `2 = RAISERROR`). |
| `@SQL` | Dynamic command buffer. |
| `@UDErrMsg` | Formatted unified error message. |

---

## 6. Error Strategy ⚠️
- Each failure generates a detailed message (number, severity, state, line).
- Attachment continues to next file even after an error.
- No functional changes applied—behavior preserved.

---

## 7. Usage Recommendations ✅
1. Run under an account with rights to the target data file path.
2. Ensure log (`.ldf`) files are co-located or attachable implicitly.
3. Run inside a controlled maintenance window.
4. Consider capturing output to a logging table (future enhancement).

---

## 8. Glossary 🔍

| Term | Meaning |
|------|--------|
| `Detached Database` | Database removed from instance; files remain. |
| `Primary File` | Main data file (`.mdf`) containing metadata header. |
| `Dynamic SQL` | Constructed at runtime for variable file lists. |
| `sp_attach_db` | Legacy attach proc (works; modern recommendation is `CREATE DATABASE ... FOR ATTACH`). |

---

## 9. Full Script Source 💻

<details>
<summary>(click to expand) The 145 script:</summary>

```sql
-- =============================================
-- Author:              a-momen
-- Contact & Report:    amomen@gmail.com
-- Update date:         2023-01-15
-- Script:              Automated attachment of detached databases
-- Purpose:             Enumerate *.mdf files in a root folder, extract metadata with DBCC CHECKPRIMARYFILE,
--                      then build and execute sys.sp_attach_db for each set of files. Provides robust
--                      error handling with optional PRINT vs RAISERROR output mode.
-- =============================================

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

-- Cursor enumerates *.mdf files under specified root path
DECLARE Attacher CURSOR FAST_FORWARD FOR
    SELECT full_filesystem_path
    FROM sys.dm_os_enumerate_filesystem(N'M:\SQLData', N'*.mdf');

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
```

</details>

---

## 10. Verification Checklist ✅

| Check | Expected |
|-------|----------|
| File enumeration path valid | Returns rows |
| DBCC metadata extracted | Populates temp tables |
| Dynamic SQL built | Printed prior to execution |
| Attach success | No errors raised |
| Error path | Formatted messages output |

---

## 11. Future Enhancements 🚀
- Replace `sys.sp_attach_db` with `CREATE DATABASE ... FOR ATTACH`.
- Add logging table for audit trail.
- Support `.ndf` file grouping validation.
- Add retry logic on transient I/O errors.

---

**End of Document** ✨