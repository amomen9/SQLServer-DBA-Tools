# 🗃️ Automated Cleanup: Drop Databases Offline Beyond a Threshold

---

## 1. Overview 📘
This document explains a `T-SQL` stored procedure that inspects SQL Server error logs to identify databases which have remained in the `OFFLINE` state longer than a configurable number of days (`@interval_days`). It can either:
- Preview (report only) the candidate databases, or
- Bring them `ONLINE` (attempt), set them to `SINGLE_USER`, and drop them.

The logic depends on parsing error log messages of the pattern:
`Setting database option OFFLINE to ON for database '<DatabaseName>'`.

---

## 2. Embedded Script Header 📝
```
-- Automated drop of databases offline longer than given interval
```

---

## 3. What the Procedure Does 🔍
1. Determines the SQL Server error log directory and base name.
2. Enumerates error log files using `xp_dirtree`.
3. Reads each log with `sp_readerrorlog`, filtering for OFFLINE transition messages.
4. Extracts the most recent OFFLINE timestamp per database.
5. Lists databases with:
   - Days elapsed since OFFLINE event.
   - Whether they still exist and are currently `OFFLINE`.
6. Filters those exceeding `@interval_days`.
7. For each candidate (when not in preview mode):
   - Attempts to set `ONLINE`.
   - Forces `SINGLE_USER WITH ROLLBACK IMMEDIATE`.
   - Drops the database.
8. Prints counts before and after.

---

## 4. Parameters ⚙️

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `@interval_days` | INT | 60 | Minimum days OFFLINE before action. |
| `@Only_Show_Databases_Do_Not_Drop` | BIT | 0 | `1` = preview only (no drop); `0` = perform drop. |

---

## 5. Processing Steps 🧪

### 5.1 Initialization
- Counts user databases (excludes system DBs by `database_id > 4`).
- Resolves error log path via `SERVERPROPERTY('ErrorLogFileName')`.

### 5.2 Log Enumeration
- Uses `xp_dirtree` to list log files and counts those matching the base pattern.

### 5.3 Log Parsing Loop
- Iterates backward through logs.
- Inserts matching OFFLINE events into `#ErrLog_Entries`.

### 5.4 Offline Derivation
- Builds `#OfflineDatabases` with latest OFFLINE time per database.

### 5.5 Reporting
- Outputs offline duration and existence/state check.

### 5.6 Action Phase
- Cursor iterates stale OFFLINE databases.
- Tries to bring ONLINE (best effort).
- Switches to `SINGLE_USER`.
- Drops database (unless preview flag set).

### 5.7 Finalization
- Recounts remaining databases.
- Prints summary.

---

## 6. Safety & Considerations ⚠️

| Aspect | Note |
|--------|------|
| Log Dependency | Missing/rotated logs may omit older OFFLINE events. |
| Permissions | Requires `xp_dirtree`, `sp_readerrorlog`, and `ALTER/DROP DATABASE`. |
| Edge Cases | Failed ONLINE attempts still proceed to DROP attempt. |
| Preview Mode | Use `@Only_Show_Databases_Do_Not_Drop = 1` first. |

---

## 7. Example Usage ▶️
Preview only:
```
EXEC dbo.drop_databases_that_have_been_offline_for_more_than_a_specific_amount_of_time
     @interval_days = 90,
     @Only_Show_Databases_Do_Not_Drop = 1;
```

Execute cleanup:
```
EXEC dbo.drop_databases_that_have_been_offline_for_more_than_a_specific_amount_of_time
     @interval_days = 90,
     @Only_Show_Databases_Do_Not_Drop = 0;
```

---

## 8. Full Stored Procedure Source 💻

<details>
<summary>(click to expand) The complete 137-line script:</summary>

```sql
-- filepath: c:\Users\Ali\git\MyGitHubRepos\SQLServer-DBA-Tools\Database & Disk Physical Operation\Database\Drop Databases been offline more than a specific amount of time.sql
-- Automated drop of databases offline longer than given interval
USE master;
GO

CREATE OR ALTER PROC dbo.drop_databases_that_have_been_offline_for_more_than_a_specific_amount_of_time
    @interval_days INT = 60,                -- Threshold in days
    @Only_Show_Databases_Do_Not_Drop BIT = 0 -- Preview mode flag (1 = show only)
AS
BEGIN
    SET NOCOUNT ON;

    -- Basic counts and error log path discovery
    DECLARE @NoofDatabases VARCHAR(10) = CONVERT(VARCHAR(10),(SELECT COUNT(*) FROM sys.databases WHERE database_id > 4)),
            @CountofErrorFiles INT,
            @ErrLogPath NVARCHAR(500),
            @ErrLogBaseName NVARCHAR(64);

    SELECT
        @ErrLogPath     = LEFT(ErrBaseName,(LEN(ErrBaseName)-CHARINDEX('\',REVERSE(ErrBaseName)))) + '\',
        @ErrLogBaseName = RIGHT(ErrBaseName,CHARINDEX('\',REVERSE(ErrBaseName))-1)
    FROM (SELECT CONVERT(NVARCHAR(500),SERVERPROPERTY('ErrorLogFileName')) AS ErrBaseName) AS s;

    -- Enumerate error log files
    IF OBJECT_ID('tempdb..#ErrorLog_Files') IS NOT NULL DROP TABLE #ErrorLog_Files;
    CREATE TABLE #ErrorLog_Files (Path NVARCHAR(500), depth INT, [file] INT);

    INSERT #ErrorLog_Files (Path, depth, [file])
    EXEC sys.xp_dirtree @ErrLogPath, 1, 1;

    SELECT @CountofErrorFiles = COUNT(*)
    FROM #ErrorLog_Files
    WHERE Path LIKE (@ErrLogBaseName + '%') AND [file] = 1;

    -- Collect offline -> online transitions from error logs
    IF OBJECT_ID('tempdb..#ErrLog_Entries') IS NOT NULL DROP TABLE #ErrLog_Entries;
    CREATE TABLE #ErrLog_Entries (LogDate DATETIME, ProcessInfo NVARCHAR(12), [Text] NVARCHAR(3999));

    SET @CountofErrorFiles -= 1;

    WHILE @CountofErrorFiles >= 0
    BEGIN
        INSERT #ErrLog_Entries (LogDate, ProcessInfo, [Text])
        EXEC sys.sp_readerrorlog @p1 = @CountofErrorFiles, @p2 = 1,
                                 @p3 = N'Setting database option OFFLINE to ON for database ';

        SET @CountofErrorFiles -= 1;
    END;

    -- Derive list of offline databases (latest event per DB)
    IF OBJECT_ID('tempdb..#OfflineDatabases') IS NOT NULL DROP TABLE #OfflineDatabases;
    SELECT LogDate,
           LEFT(DBName, LEN(DBName) - 2) AS DBName
    INTO #OfflineDatabases
    FROM (
        SELECT ROW_NUMBER() OVER (PARTITION BY [Text] ORDER BY LogDate DESC) AS rn,
               LogDate,
               SUBSTRING([Text], CHARINDEX('''',[Text]) + 1, LEN([Text])) AS DBName
        FROM #ErrLog_Entries
    ) AS d
    WHERE rn = 1;

    PRINT 'No. of databases before operation: ' + @NoofDatabases;

    -- Report offline durations and existence
    SELECT DBName,
           DATEDIFF(DAY, LogDate, GETDATE()) AS [How Long Offline?],
           IIF(EXISTS (SELECT 1 FROM sys.databases WHERE name = DBName AND state_desc = 'OFFLINE'), 1, 0) AS [Does still exist?]
    FROM #OfflineDatabases
    ORDER BY [How Long Offline?] DESC;

    -- Cursor over stale offline databases
    DECLARE @DatabaseName SYSNAME,
            @SQL NVARCHAR(MAX),
            @ErrMsg NVARCHAR(MAX),
            @CompanyDBName SYSNAME,
            @usedb NVARCHAR(MAX) = '';

    DECLARE db_cursor CURSOR FAST_FORWARD FOR
        SELECT DBName
        FROM #OfflineDatabases
        WHERE LogDate < DATEADD(DAY, -@interval_days, GETDATE())
          AND (SELECT state_desc FROM sys.databases WHERE name = DBName) = 'OFFLINE';

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @DatabaseName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @CompanyDBName = @DatabaseName;

        BEGIN TRY
            -- Attempt to bring database online
            SET @SQL = @usedb + CHAR(10) +
                       'PRINT(''' + QUOTENAME(@CompanyDBName) + '''); ' +
                       'ALTER DATABASE ' + QUOTENAME(@CompanyDBName) + ' SET ONLINE;';
            IF @Only_Show_Databases_Do_Not_Drop = 0 EXEC (@SQL);

            -- Force single-user for drop
            SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@CompanyDBName) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
            IF @Only_Show_Databases_Do_Not_Drop = 0 EXEC (@SQL);
        END TRY
        BEGIN CATCH
            SET @ErrMsg = ERROR_MESSAGE();
            PRINT 'Warning: Could not bring ' + QUOTENAME(@CompanyDBName) +
                  ' online; will attempt drop. Manual file cleanup may be required.';
        END CATCH;

        BEGIN TRY
            -- Drop database
            SET @SQL = @usedb + CHAR(10) +
                       'DROP DATABASE ' + QUOTENAME(@CompanyDBName) + ';';
            IF @Only_Show_Databases_Do_Not_Drop = 0 EXEC (@SQL);
            PRINT 'Database ' + QUOTENAME(@CompanyDBName) + ' was dropped.';
        END TRY
        BEGIN CATCH
            SET @ErrMsg = ERROR_MESSAGE();
            RAISERROR(@ErrMsg, 16, 1);
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @DatabaseName;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    -- Final count
    SET @NoofDatabases = CONVERT(VARCHAR(10),(SELECT COUNT(*) FROM sys.databases WHERE database_id > 4));
    PRINT 'No. of databases now (after operation): ' + @NoofDatabases;
END;
GO

-- Example execution (preview mode)
EXEC dbo.drop_databases_that_have_been_offline_for_more_than_a_specific_amount_of_time
     @interval_days = 60,
     @Only_Show_Databases_Do_Not_Drop = 1;
GO
```

</details>

---

## 9. Quick Checklist ✅

| Task | Status |
|------|--------|
| Preview run completed | ☐ |
| Threshold validated | ☐ |
| Permissions confirmed | ☐ |
| Error logs retained | ☐ |
| Post-drop file cleanup reviewed | ☐ |

---

**END** ✨