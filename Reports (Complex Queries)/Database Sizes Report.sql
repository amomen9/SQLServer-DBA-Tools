-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2025-09-20"
-- Description:         "Database Sizes Report"
-- License:             "Please refer to the license file"
-- =============================================



USE master;
GO

DROP TABLE IF EXISTS #sd;
GO

/* Temp table to collect file info from every DB */
SELECT 
    ISNULL(CONNECTIONPROPERTY('local_net_address'), 'localhost') AS [Server IP],
    DB_NAME() AS DBName,
    file_id,
    type_desc,
    name AS [Logical Name],
    LEFT(physical_name, CHARINDEX(':', physical_name)) AS [Drive],
    size / 128.0 / 1024 AS Size_GB,
    ISNULL(FILEPROPERTY(name, 'spaceused'), 0) / 128.0 / 1024 AS UsedSpace_GB,
    CONVERT(DECIMAL(26,12), 0) AS [UsedSpace%],
    growth / 128.0 AS growth_MB,
    is_percent_growth,
    max_size / 128.0 / 1024 AS max_size_GB,
    is_read_only AS [File ReadOnly?],
    CONVERT(NVARCHAR(260), NULL) AS [physical_name],
    CONVERT(NVARCHAR(30), NULL) AS [database state],
    CONVERT(NVARCHAR(30), NULL) AS [user_access_desc],
    CONVERT(NVARCHAR(30), NULL) AS log_reuse_wait_desc
INTO #sd
FROM master.sys.database_files
WHERE 1 = 2;

SET NOCOUNT ON;

/* Collect rows for all online, non-snapshot DBs */
DECLARE @SQL nvarchar(max) = N'';

SELECT @SQL += '
USE ' + QUOTENAME(name) + ';
IF DB_ID(''' + name + ''') IS NOT NULL
BEGIN
    INSERT INTO #sd
    SELECT 
        ISNULL(CONNECTIONPROPERTY(''local_net_address''), ''localhost'') AS [Server IP],
        ''' + name + ''' AS DBName,
        file_id,
        mf.type_desc,
        mf.name,
        LEFT(physical_name, CHARINDEX('':'', physical_name)) AS [Drive],
        size / 128.0 / 1024 AS Size_GB,
        ISNULL(FILEPROPERTY(mf.name, ''spaceused''), 0) / 128.0 / 1024 AS UsedSpace_GB,
        ISNULL(FILEPROPERTY(mf.name, ''spaceused''), 0) * 100.0 / NULLIF(size, 0) AS [UsedSpace%],
        growth / 128.0 AS growth_MB,
        is_percent_growth,
        max_size / 128.0 / 1024 AS max_size_GB,
        mf.is_read_only AS [File ReadOnly?],
        mf.physical_name,
        db.state_desc,
        db.user_access_desc,
        db.log_reuse_wait_desc
    FROM sys.database_files mf
    JOIN sys.databases db ON db.database_id = DB_ID(''' + name + ''');
END;
'
FROM sys.databases
WHERE source_database_id IS NULL
  AND state_desc = 'ONLINE';

EXEC sys.sp_executesql @SQL;

/* Aggregation + total summary row */
;WITH DataAgg AS (
    SELECT 
        d.database_id,
        d.create_date,
        s.DBName,
        s.Drive,
        SUM(s.Size_GB) AS Size_GB,
        SUM(s.UsedSpace_GB) AS UsedSpace_GB,
        SUM(s.UsedSpace_GB) * 100.0 / NULLIF(SUM(s.Size_GB),0) AS [UsedSpace%],
        s.[database state],
        s.log_reuse_wait_desc
    FROM #sd s
    JOIN sys.databases d ON s.DBName = d.name COLLATE DATABASE_DEFAULT
    WHERE s.type_desc = 'ROWS'
    GROUP BY d.database_id, d.create_date, s.DBName, s.Drive, s.[database state], s.log_reuse_wait_desc
),
LogAgg AS (
    SELECT 
        d.database_id,
        d.create_date,
        s.DBName,
        s.Drive,
        SUM(s.Size_GB) AS Size_GB,
        SUM(s.UsedSpace_GB) AS UsedSpace_GB,
        SUM(s.UsedSpace_GB) * 100.0 / NULLIF(SUM(s.Size_GB),0) AS [UsedSpace%],
        s.[database state],
        s.log_reuse_wait_desc
    FROM #sd s
    JOIN sys.databases d ON s.DBName = d.name COLLATE DATABASE_DEFAULT
    WHERE s.type_desc = 'LOG'
    GROUP BY d.database_id, d.create_date, s.DBName, s.Drive, s.[database state], s.log_reuse_wait_desc
),
CoreData AS (
    SELECT 
        dt1.create_date,
        dt1.DBName,
        dt1.Size_GB + dt2.Size_GB AS Overall_db_Size_GB,
        dt1.UsedSpace_GB + dt2.UsedSpace_GB AS Overall_db_UsedSpace_GB,
        dt1.Size_GB AS Data_Size_GB_numeric,
        dt1.UsedSpace_GB AS Data_UsedSpace_GB,
        dt1.Size_GB - dt1.UsedSpace_GB AS Data_FreeSpace_GB,
        dt1.[UsedSpace%] AS [Data_UsedSpace%],
        STRING_AGG(dt1.Drive, ', ') AS [Data Spanned over Drives],
        dt2.Size_GB AS Log_Size_GB_numeric,
        dt2.UsedSpace_GB AS Log_UsedSpace_GB,
        dt2.Size_GB - dt2.UsedSpace_GB AS Log_FreeSpace_GB,
        STRING_AGG(dt2.Drive, ', ') AS [Log Spanned over Drives],
        dt2.[UsedSpace%] AS [Log_UsedSpace%],
        dt1.log_reuse_wait_desc,
        dt1.[database state]
    FROM DataAgg dt1
    JOIN LogAgg dt2 ON dt2.DBName = dt1.DBName
    WHERE dt1.database_id > 4
    GROUP BY dt1.create_date,
             dt1.DBName,
             dt1.Size_GB,
             dt2.Size_GB,
             dt1.UsedSpace_GB,
             dt2.UsedSpace_GB,
             dt1.[UsedSpace%],
             dt2.[UsedSpace%],
             dt1.[database state],
             dt1.log_reuse_wait_desc
),
DataDriveCaps AS (
    SELECT LEFT(mf.physical_name, CHARINDEX(':', mf.physical_name)) AS Drive,
           MAX(vs.total_bytes)/(1024.0*1024*1024) AS DriveSizeGB
    FROM sys.master_files mf
    CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
    WHERE mf.type = 0 AND mf.database_id > 4
    GROUP BY LEFT(mf.physical_name, CHARINDEX(':', mf.physical_name))
),
LogDriveCaps AS (
    SELECT LEFT(mf.physical_name, CHARINDEX(':', mf.physical_name)) AS Drive,
           MAX(vs.total_bytes)/(1024.0*1024*1024) AS DriveSizeGB
    FROM sys.master_files mf
    CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
    WHERE mf.type = 1 AND mf.database_id > 4
    GROUP BY LEFT(mf.physical_name, CHARINDEX(':', mf.physical_name))
),
Totals AS (
    SELECT 
        SUM(Data_Size_GB_numeric) AS TotalDataSizeGB,
        SUM(Log_Size_GB_numeric)  AS TotalLogSizeGB,
        (SELECT SUM(DriveSizeGB) FROM DataDriveCaps) AS TotalDataDrivesCapGB,
        (SELECT SUM(DriveSizeGB) FROM LogDriveCaps)  AS TotalLogDrivesCapGB
    FROM CoreData
),
Combined AS (
    /* Detail rows */
    SELECT 
        0 AS RowSortFlag,
        create_date,
        DBName,
        Overall_db_Size_GB,
        Overall_db_UsedSpace_GB,
        CONVERT(NVARCHAR(100), CONVERT(DECIMAL(18,2), Data_Size_GB_numeric)) AS Data_Size_GB,
        Data_UsedSpace_GB,
        Data_FreeSpace_GB,
        [Data_UsedSpace%],
        [Data Spanned over Drives],
        CONVERT(NVARCHAR(100), CONVERT(DECIMAL(18,2), Log_Size_GB_numeric)) AS Log_Size_GB,
        Log_UsedSpace_GB,
        Log_FreeSpace_GB,
        [Log Spanned over Drives],
        [Log_UsedSpace%],
        log_reuse_wait_desc,
        [database state]
    FROM CoreData

    UNION ALL

    /* Summary row */
    SELECT
        1 AS RowSortFlag,
        NULL,
        NULL,
        NULL,
        NULL,
        CONVERT(NVARCHAR(100),
            CONVERT(VARCHAR(32), CONVERT(DECIMAL(18,2), t.TotalDataSizeGB)) + '/' +
            CONVERT(VARCHAR(32), CONVERT(DECIMAL(18,2), NULLIF(t.TotalDataDrivesCapGB,0)))
        ) AS Data_Size_GB,
        NULL,
        NULL,
        NULL,
        NULL,
        CONVERT(NVARCHAR(100),
            CONVERT(VARCHAR(32), CONVERT(DECIMAL(18,2), t.TotalLogSizeGB)) + '/' +
            CONVERT(VARCHAR(32), CONVERT(DECIMAL(18,2), NULLIF(t.TotalLogDrivesCapGB,0)))
        ) AS Log_Size_GB,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL
    FROM Totals t
)
SELECT 
    create_date,
    DBName,
    Overall_db_Size_GB,
    Overall_db_UsedSpace_GB,
    Data_Size_GB,
    Data_UsedSpace_GB,
    Data_FreeSpace_GB,
    [Data_UsedSpace%],
    [Data Spanned over Drives],
    Log_Size_GB,
    Log_UsedSpace_GB,
    Log_FreeSpace_GB,
    [Log Spanned over Drives],
    [Log_UsedSpace%],
    log_reuse_wait_desc,
    [database state]
FROM Combined
ORDER BY RowSortFlag, Data_FreeSpace_GB DESC;

DROP TABLE IF EXISTS #sd;