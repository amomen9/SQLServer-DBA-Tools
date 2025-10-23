# 🧹 Locate Orphaned SQL Server Database Files

---

## 1. Overview 📘  
This document describes a `T-SQL` utility that discovers potential orphaned SQL Server data (`.mdf`, `.ndf`) and log (`.ldf`) files on disk that are **not** registered in `sys.master_files`. It dynamically derives candidate root folders from currently attached databases plus the instance default data/log paths, enumerates the filesystem, filters out noise, and reports unreferenced files ordered by size.

---

## 2. Embedded Script Header 📝  
```
-- Script: Locate orphaned SQL Server database data/log files not referenced in sys.master_files
-- Scope: Scans known data/log directories plus default instance paths to list files absent from catalog
-- Output: full_filesystem_path, size in MB, and file_or_directory_name for orphan candidates (ordered by size)
```

---

## 3. What the Script Does 🔍  
1. Gathers distinct parent directories of all files in `sys.master_files`.  
2. Adds `InstanceDefaultDataPath` and `InstanceDefaultLogPath` (if not already included).  
3. Enumerates each folder recursively (one level) via `sys.dm_os_enumerate_filesystem`.  
4. Filters out obvious non–database artifacts and template model clones.  
5. Left joins enumerated paths against cataloged file paths to isolate those not attached.  
6. Returns a list of orphan candidates with size (MB), sorted descending.  
7. Executes the stored procedure, then optionally drops it (ad‑hoc usage pattern).

---

## 4. Key Objects & DMVs 🧩  

| Object / DMV | Purpose |
|--------------|---------|
| `sys.master_files` | Catalog of currently attached database files. |
| `SERVERPROPERTY('InstanceDefaultDataPath')` | Default data directory. |
| `SERVERPROPERTY('InstanceDefaultLogPath')` | Default log directory. |
| `sys.dm_os_enumerate_filesystem` | Enumerates filesystem contents (needs appropriate permissions). |

---

## 5. Result Set 📤  

| Column | Description |
|--------|-------------|
| `full_filesystem_path` | Full path to the candidate file. |
| `Size_MB` | File size (MB). |
| `file_or_directory_name` | Leaf file name. |

---

## 6. Usage Steps ✅  

### 6.1 Preview  
1. Open a query window in `master`.  
2. Run the script as-is.  
3. Review output for unexpected large orphaned files.

### 6.2 Remediation (Manual)  
1. Validate file truly unused (check backups, DR scripts).  
2. Move or delete file per retention policy.  
3. Consider automating archival.

---

## 7. Considerations ⚠️  

| Aspect | Note |
|--------|------|
| Permissions | Requires ability to execute `sys.dm_os_enumerate_filesystem`. |
| Coverage | Only scans inferred folders (does not brute-force entire drives). |
| False Positives | Files from snapshot, manual staging, or backup processes may appear. |
| Filenames | Pattern match excludes some known template derivatives; adjust as needed. |

---

## 8. Potential Enhancements 🚀  

| Enhancement | Description |
|-------------|-------------|
| Depth Control | Add deeper recursion support. |
| Extension Whitelist | Positive filter for `.mdf`, `.ndf`, `.ldf` only. |
| Logging Table | Persist results for historical drift tracking. |
| Size Threshold | Exclude files smaller than N MB. |

---

## 9. Full Script 💻  

<details>
<summary>(click to expand) The complete 102-line script:</summary>

```sql
-- Script: Locate orphaned SQL Server database data/log files not referenced in sys.master_files
-- Scope: Scans known data/log directories plus default instance paths to list files absent from catalog
-- Output: full_filesystem_path, size in MB, and file_or_directory_name for orphan candidates (ordered by size)
USE master;
GO

IF OBJECT_ID('dbo.usp_FindOrphanedDBFiles','P') IS NOT NULL
    DROP PROC dbo.usp_FindOrphanedDBFiles;
GO

CREATE OR ALTER PROC dbo.usp_FindOrphanedDBFiles
AS
BEGIN
    SET NOCOUNT ON;

    -- Collect distinct folder roots from existing database files and default instance paths
    IF OBJECT_ID('tempdb..#FolderRoots') IS NOT NULL DROP TABLE #FolderRoots;
    CREATE TABLE #FolderRoots (Folder NVARCHAR(500) PRIMARY KEY);

    INSERT INTO #FolderRoots(Folder)
    SELECT DISTINCT LEFT(mf.physical_name, LEN(mf.physical_name) - CHARINDEX('\', REVERSE(mf.physical_name)))
    FROM sys.master_files AS mf
    WHERE mf.physical_name LIKE '%\%';

    DECLARE @DefaultData NVARCHAR(500) = TRIM(CONVERT(NVARCHAR(500), SERVERPROPERTY('InstanceDefaultDataPath')));
    DECLARE @DefaultLog  NVARCHAR(500) = TRIM(CONVERT(NVARCHAR(500), SERVERPROPERTY('InstanceDefaultLogPath')));

    IF RIGHT(@DefaultData,1) = '\' SET @DefaultData = LEFT(@DefaultData, LEN(@DefaultData)-1);
    IF RIGHT(@DefaultLog ,1) = '\' SET @DefaultLog  = LEFT(@DefaultLog , LEN(@DefaultLog )-1);

    INSERT INTO #FolderRoots(Folder)
    SELECT v.Dir
    FROM (VALUES (@DefaultData),(@DefaultLog)) v(Dir)
    WHERE v.Dir IS NOT NULL AND v.Dir <> '' AND NOT EXISTS (SELECT 1 FROM #FolderRoots r WHERE r.Folder = v.Dir);

    -- Enumerate filesystem under each collected folder
    IF OBJECT_ID('tempdb..#Enumerated') IS NOT NULL DROP TABLE #Enumerated;
    CREATE TABLE #Enumerated
    (
        full_filesystem_path NVARCHAR(4000),
        file_or_directory_name NVARCHAR(512),
        size_in_bytes BIGINT
    );

    DECLARE @Folder NVARCHAR(500);

    DECLARE folders CURSOR FAST_FORWARD FOR SELECT Folder FROM #FolderRoots;
    OPEN folders;
    FETCH NEXT FROM folders INTO @Folder;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT #Enumerated (full_filesystem_path, file_or_directory_name, size_in_bytes)
        SELECT e.full_filesystem_path, e.file_or_directory_name, e.size_in_bytes
        FROM sys.dm_os_enumerate_filesystem(@Folder, N'*') AS e;

        FETCH NEXT FROM folders INTO @Folder;
    END
    CLOSE folders;
    DEALLOCATE folders;

    -- Filter out non‑database related extensions / known noise
    WITH Filtered AS
    (
        SELECT full_filesystem_path,
               file_or_directory_name,
               Size_MB = size_in_bytes / 1024.0 / 1024.0
        FROM #Enumerated
        WHERE full_filesystem_path NOT LIKE '%.hkckp'
          AND full_filesystem_path NOT LIKE '%.pdb'
          AND full_filesystem_path NOT LIKE '%.obj'
          AND full_filesystem_path NOT LIKE '%.c'
          AND full_filesystem_path NOT LIKE '%.dll'
          AND full_filesystem_path NOT LIKE '%.xml'
          AND full_filesystem_path NOT LIKE '%.out'
          AND full_filesystem_path NOT LIKE '%.cer'
          AND full_filesystem_path NOT LIKE '%.hdr'
          AND full_filesystem_path NOT LIKE '%model_msdbdata.mdf'
          AND full_filesystem_path NOT LIKE '%model_replicatedmaster.mdf'
          AND full_filesystem_path NOT LIKE '%model_msdblog.ldf'
          AND full_filesystem_path NOT LIKE '%model_replicatedmaster.ldf'
    )
    -- Left join to catalog to find orphans (no matching master_files entry)
    SELECT DISTINCT f.full_filesystem_path,
           f.Size_MB,
           f.file_or_directory_name
    FROM Filtered f
    LEFT JOIN sys.master_files mf
      JOIN sys.databases db ON db.database_id = mf.database_id
        ON f.full_filesystem_path = LEFT(mf.physical_name,2) +
           REPLACE(RIGHT(mf.physical_name, DATALENGTH(mf.physical_name)/2 - 2), '\\','\')
    WHERE mf.database_id IS NULL
    ORDER BY f.Size_MB DESC;
END;
GO

-- Execute procedure to list orphaned database files
EXEC dbo.usp_FindOrphanedDBFiles;
GO

-- Cleanup (drop procedure if only needed ad-hoc)
DROP PROC dbo.usp_FindOrphanedDBFiles;
GO
```

</details>

---

## 10. Quick Checklist ✅  

| Check | Status |
|-------|--------|
| Ran in non-production first | ☐ |
| Output reviewed for false positives | ☐ |
| Large files validated before deletion | ☐ |
| Script altered to persist SP (optional) | ☐ |
| Permissions adequate | ☐ |

---

**END** ✨