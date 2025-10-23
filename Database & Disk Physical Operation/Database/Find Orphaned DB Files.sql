-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2024-03-13"
-- Description:         "Find Orphaned DB Files Orphan"
-- License:             "Please refer to the license file"
-- =============================================



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