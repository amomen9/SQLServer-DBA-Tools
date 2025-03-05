# SQL Server Backup and Restore History Analyzer

<details>
<summary>(click to expand) The complete script file with added explanations:</summary>

```sql
-- Refactored and optimized script for querying SQL Server backup and restore history
-- Purpose: Retrieve and analyze backup and restore history, including database space usage.

-- Query to retrieve all backup sets
SELECT * 
FROM msdb.dbo.backupset;

-- Query to retrieve all backup media families
SELECT * 
FROM msdb.dbo.backupmediafamily;

-- Query to retrieve top 1000 backup sets with details
SELECT TOP 1000 
    b.database_name, 
    b.backup_start_date, 
    b.type, 
    b.* 
FROM msdb.dbo.backupset b 
WHERE b.is_copy_only = 0 
ORDER BY b.backup_set_id DESC;

-- Query to retrieve top 1000 log backups grouped by start time
SELECT TOP 1000 
    MIN(backup_set_id) AS backup_set_id, 
    FORMAT(backup_start_date, 'HH:mm', 'en-uk') AS backup_time, 
    type 
FROM msdb.dbo.backupset 
WHERE is_copy_only = 0 
    AND type = 'L' 
GROUP BY backup_start_date, type 
ORDER BY MIN(backup_set_id) DESC;

-- Query to retrieve top 1000 full backups grouped by start time and database
SELECT TOP 1000 
    MIN(backup_set_id) AS backup_set_id, 
    FORMAT(backup_start_date, 'yyyy-MM-dd HH:mm', 'en-uk') AS backup_time, 
    type, 
    database_name 
FROM msdb.dbo.backupset 
WHERE is_copy_only = 0 
    AND type = 'D' 
GROUP BY backup_start_date, type, database_name 
ORDER BY MIN(backup_set_id) DESC;

-- Query to retrieve top 1000 backup sets with file details
SELECT TOP 1000 
    b.database_name, 
    b.backup_start_date, 
    b.type, 
    b.* 
FROM msdb.dbo.backupset b 
JOIN msdb.dbo.backupfile f ON f.backup_set_id = b.backup_set_id 
WHERE b.is_copy_only = 0 
ORDER BY b.backup_set_id DESC;

-- Query to retrieve top 1000 backup sets with media family details
SELECT TOP 1000 
    b.database_name, 
    b.backup_start_date, 
    b.type, 
    f.physical_device_name, 
    b.backup_size / 1024.0 AS backup_size_MB 
FROM msdb.dbo.backupset b 
JOIN msdb.dbo.backupmediafamily f ON f.media_set_id = b.media_set_id 
WHERE b.is_copy_only = 0 
ORDER BY b.backup_set_id DESC;

-- Query to retrieve distinct databases with full backups
SELECT DISTINCT a.database_name 
FROM (
    SELECT TOP 10000 
        b.database_name, 
        b.backup_start_date, 
        b.type, 
        b.backup_size / 1024.0 AS backup_size_MB 
    FROM msdb.dbo.backupset b 
    WHERE b.is_copy_only = 0 
        AND type = 'D' 
    ORDER BY b.backup_set_id DESC
) a;

-- Query to retrieve top 10000 log backups
SELECT TOP 10000 
    b.database_name, 
    b.backup_start_date, 
    b.type, 
    b.backup_size / 1024.0 AS backup_size_MB 
FROM msdb.dbo.backupset b 
WHERE b.is_copy_only = 0 
    AND type = 'L' 
ORDER BY b.backup_set_id DESC;

-- Query to retrieve backup history with details
DECLARE @dbname SYSNAME, @days INT;
SET @dbname = 'TPCG_WaitStats'; -- Specify database name or NULL for all databases
SET @days = -30; -- Number of days to look back (default: 30 days)

SELECT 
    b.database_name,
    b.backup_start_date,
    b.backup_finish_date,
    CASE b.type
        WHEN 'D' THEN 'Database'
        WHEN 'F' THEN 'File or filegroup'
        WHEN 'G' THEN 'Differential file'
        WHEN 'I' THEN 'Differential database'
        WHEN 'L' THEN 'Log'
        WHEN 'P' THEN 'Partial'
        WHEN 'Q' THEN 'Differential partial'
        ELSE b.type
    END AS [Backup Type],
    b.backup_size / 1024.0 / 1024 / 1024 AS backup_size_GB,
    b.compressed_backup_size / 1024.0 / 1024 / 1024 AS compressed_backup_size_GB,
    f.physical_device_name,
    b.user_name
FROM msdb.dbo.backupset b
JOIN msdb.dbo.backupmediafamily f ON f.media_set_id = b.media_set_id
WHERE b.database_name = ISNULL(@dbname, b.database_name)
    AND b.backup_finish_date >= DATEADD(DAY, ISNULL(@days, -30), GETDATE())
ORDER BY b.backup_finish_date DESC;

-- Query to analyze database space usage
DROP TABLE IF EXISTS #UsedSpacePerDB;
CREATE TABLE #UsedSpacePerDB (
    id INT IDENTITY PRIMARY KEY,
    database_id INT NOT NULL,
    SUMUsedSpace FLOAT NOT NULL
);

INSERT INTO #UsedSpacePerDB (database_id, SUMUsedSpace)
EXEC sys.sp_MSforeachdb '
    USE [?];
    SELECT DB_ID(), SUM(FILEPROPERTY(name, ''SpaceUsed'')) / 128.0 AS [Used Space]
    FROM sys.database_files
    WHERE file_id <> 2;
';

SELECT 
    dt.[DB Name],
    dt.[Reserved Space MB],
    dt.[Used Space MB],
    dt.backup_size_MB,
    (dt.[Used Space MB] / dt.[Reserved Space MB]) * 100 AS [Used Space Percentage]
FROM (
    SELECT 
        DB_NAME(mf.database_id) AS [DB Name],
        SUM(size) / 128.0 AS [Reserved Space MB],
        MIN(US.SUMUsedSpace) AS [Used Space MB],
        (
            SELECT TOP 1
                backup_size / 1024.0 / 1024 AS backup_size_MB
            FROM msdb.dbo.backupset
            WHERE type = 'D' AND DB_ID(database_name) = mf.database_id
            ORDER BY backup_finish_date DESC
        ) AS backup_size_MB
    FROM sys.master_files mf
    JOIN #UsedSpacePerDB US ON US.database_id = mf.database_id
    WHERE file_id <> 2
    GROUP BY mf.database_id
) dt;
GO

-- Query to retrieve restore history
DECLARE @dbname SYSNAME, @days INT;
SET @dbname = NULL; -- Specify database name or NULL for all databases
SET @days = -30; -- Number of days to look back (default: 30 days)

SELECT
    rsh.destination_database_name AS [Database],
    rsh.user_name AS [Restored By],
    CASE rsh.restore_type
        WHEN 'D' THEN 'Database'
        WHEN 'F' THEN 'File'
        WHEN 'G' THEN 'Filegroup'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        WHEN 'V' THEN 'Verifyonly'
        WHEN 'R' THEN 'Revert'
        ELSE rsh.restore_type
    END AS [Restore Type],
    rsh.restore_date AS [Restore Started],
    bmf.physical_device_name AS [Restored From],
    rf.destination_phys_name AS [Restored To]
FROM msdb.dbo.restorehistory rsh
JOIN msdb.dbo.backupset bs ON rsh.backup_set_id = bs.backup_set_id
JOIN msdb.dbo.restorefile rf ON rsh.restore_history_id = rf.restore_history_id
JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE rsh.restore_date >= DATEADD(DAY, ISNULL(@days, -30), GETDATE())
    AND rsh.destination_database_name = ISNULL(@dbname, rsh.destination_database_name)
ORDER BY rsh.restore_history_id DESC;
```

</details>

## Purpose
This script is designed to query and analyze SQL Server backup and restore history, as well as database space usage. It provides insights into:
- Backup history (full, differential, log, etc.).
- Restore history (database, file, log, etc.).
- Database space usage (reserved and used space).

## Features
1. **Backup History**:
   - Retrieves backup details such as database name, backup type, start/finish date, size, and physical device name.
   - Supports filtering by database name and time range.

2. **Restore History**:
   - Retrieves restore details such as database name, restore type, restore date, and source/destination paths.
   - Supports filtering by database name and time range.

3. **Database Space Usage**:
   - Calculates reserved and used space for each database.
   - Compares used space with the latest full backup size.

## Usage
1. Set the `@dbname` variable to filter by a specific database (or `NULL` for all databases).
2. Set the `@days` variable to specify the number of days to look back (default: 30 days).
3. Execute the script to retrieve the desired information.

## Notes
- The script uses system tables (`msdb.dbo.backupset`, `msdb.dbo.restorehistory`, etc.) to gather data.
- Temporary tables are used for intermediate calculations (e.g., `#UsedSpacePerDB`).

## Example Output
- Backup history with details like backup type, size, and device name.
- Restore history with details like restore type, date, and paths.
- Database space usage with reserved space, used space, and percentage utilization.

## Dependencies
- SQL Server 2012 or later.
- Access to `msdb` system database.

---

**Signature**: This script is optimized for readability, performance, and maintainability while preserving the original functionality.
