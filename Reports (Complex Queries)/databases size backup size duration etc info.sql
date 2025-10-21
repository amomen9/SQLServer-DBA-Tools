
DROP TABLE IF EXISTS #FULL
DROP TABLE IF EXISTS #DIFF
DROP TABLE IF EXISTS #LOG
DROP TABLE IF EXISTS #sizes
DROP TABLE IF EXISTS #backup
GO

        
USE master
GO
CREATE OR ALTER FUNCTION dbo.FormatDuration (@TotalTime DECIMAL(30,3))
RETURNS VARCHAR(MAX)
AS
BEGIN
    DECLARE 
        @TotalMilliseconds BIGINT = CAST(@TotalTime * 1000 AS BIGINT)
	DECLARE
        @Days BIGINT = @TotalMilliseconds / 86400000,
        @RemainingMs BIGINT = @TotalMilliseconds % 86400000
    DECLARE    
		@Hours INT = @RemainingMs / 3600000,
        @Minutes INT = (@RemainingMs % 3600000) / 60000,
        @Seconds INT = (@RemainingMs % 60000) / 1000,
        @Milliseconds INT = @RemainingMs % 1000;

    RETURN 
        CAST(@Days AS VARCHAR(MAX)) + ':' + 
        RIGHT('0' + CAST(@Hours AS VARCHAR(2)), 2) + ':' + 
        RIGHT('0' + CAST(@Minutes AS VARCHAR(2)), 2) + ':' + 
        RIGHT('0' + CAST(@Seconds AS VARCHAR(2)), 2) + '.' + 
        RIGHT('000' + CAST(@Milliseconds AS VARCHAR(3)), 3);
END;
GO
 

 
    DROP TABLE IF EXISTS #sd
    GO
    SELECT ISNULL(CONNECTIONPROPERTY('local_net_address'),'localhost') AS [Server IP],DB_NAME() DBName, file_id, type_desc, name [Logical Name] , LEFT(physical_name,CHARINDEX(':',physical_name)) [Drive], size/128.0/1024 Size_GB, (FILEPROPERTY(name,'spaceused')/128.0/1024) [UsedSpace_GB], CONVERT(DECIMAL(26,12),0) [UsedSpace%], growth growth_MB, is_percent_growth, max_size max_size_GB, is_read_only [File ReadOnly?], CONVERT(NVARCHAR(260),NULL) [physical_name], CONVERT(NVARCHAR(30),NULL) [database state], CONVERT(NVARCHAR(30),NULL) [user_access_desc], CONVERT(NVARCHAR(30),NULL) log_reuse_wait_desc INTO #sd FROM master.sys.database_files WHERE 1=2
    SET NOCOUNT ON
    DECLARE @DBName sysname,
@SQL NVARCHAR(MAX)
       DECLARE LoopThroughDBs CURSOR FOR
SELECT name FROM sys.databases WHERE source_database_id is NULL AND state_desc = 'ONLINE'
       OPEN LoopThroughDBs
FETCH NEXT FROM LoopThroughDBs INTO @DBName
WHILE(@@FETCH_STATUS=0)
BEGIN
SET @SQL = 'DECLARE @SQL nvarchar(max)='''' set @SQL=''USE ['+@DBName+'] '' ; set @SQL+=''IF db_id('''''+@DBName+''''')>=1 begin select ISNULL(CONNECTIONPROPERTY(''''local_net_address''''),''''localhost'''') as [Server IP], '''''+@DBName+''''' DBName, file_id, mf.type_desc, mf.name, left(physical_name,charindex('''':'''',physical_name)), size/128.0/1024, fileproperty(mf.name,''''spaceused'''')/128.0/1024,fileproperty(mf.name,''''spaceused'''')*100.0/size, growth/128.0, is_percent_growth, max_size/128.0/1024 max_size, mf.is_read_only, mf.physical_name, db.state_desc, user_access_desc, log_reuse_wait_desc from sys.database_files mf join sys.databases db on db.database_id=db_id('''''+@DBName+''''') end'' EXEC (@SQL)'	
INSERT #sd
EXEC (@SQL)
FETCH NEXT FROM LoopThroughDBs INTO @DBName
END
       CLOSE LoopThroughDBs
       DEALLOCATE LoopThroughDBs
   
       
 
 
 
 
---------------------- SELECT #2: Each Database (Aggregated over database files): -----------------------
SELECT *
into #sizes
FROM
(
       SELECT
--dt1.create_date,
dt1.DBName,
--dt1.Size_GB Data_Size_GB,
--dt2.Size_GB Log_Size_GB,
CONVERT(DEC(30,3),dt1.UsedSpace_GB) Data_UsedSpace_GB,
--dt1.Size_GB-dt1.UsedSpace_GB Data_FreeSpace_GB,
--STRING_AGG(dt1.Drive,', ') [Data Spanned over Drives],
--dt2.UsedSpace_GB Log_UsedSpace_GB,
--dt2.Size_GB-dt2.UsedSpace_GB Log_FreeSpace_GB,
--STRING_AGG(dt2.Drive,', ') [Log Spanned over Drives],
--dt1.[UsedSpace%] [Data_UsedSpace%],
--dt2.[UsedSpace%] [Log_UsedSpace%],
dt1.[database state]
--dt1.log_reuse_wait_desc
       FROM
       (
SELECT d.create_date,#sd.DBName, Drive, type_desc, SUM(Size_GB) Size_GB, SUM(UsedSpace_GB) UsedSpace_GB, SUM(UsedSpace_GB)*100.0/SUM(Size_GB) [UsedSpace%], [database state], #sd.log_reuse_wait_desc
FROM #sd JOIN sys.databases d
ON DBName=d.name COLLATE Persian_100_CI_AI
WHERE type_desc='ROWS' --AND Drive = 'd:'
       
GROUP BY d.create_date,#sd.DBName, Drive, type_desc, [database state], #sd.log_reuse_wait_desc
       ) dt1 JOIN
       (
SELECT d.create_date,#sd.DBName, Drive, type_desc, SUM(Size_GB) Size_GB, SUM(UsedSpace_GB) UsedSpace_GB, SUM(UsedSpace_GB)*100.0/SUM(Size_GB) [UsedSpace%], [database state], #sd.log_reuse_wait_desc
FROM #sd JOIN sys.databases d
ON DBName=d.name COLLATE Persian_100_CI_AI
WHERE type_desc='LOG' --AND--Drive = 'd:'
GROUP BY d.create_date,#sd.DBName, Drive, type_desc, [database state], #sd.log_reuse_wait_desc
       ) dt2 ON dt2.DBName = dt1.DBName
       --WHERE dt1.DBName LIKE 'Co-%DB'
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
) dto
where DBName not in ('tempdb')
--ORDER BY  ISNULL(Data_FreeSpace_GB,1000000000) DESC--+ISNULL(Log_UsedSpace_GB,0) desc--Size_GB DESC
 
 
 
 

 
SELECT name, dt.compressed_backup_size_GB, duration, [# files]
INTO #FULL
FROM sys.databases db
OUTER APPLY
(
    SELECT TOP 1
		 database_name
		, CONVERT(DEC(10,3),backup_size/1024.0/1024/1024) backup_size_GB
		, CONVERT(DEC(10,3),compressed_backup_size/1024.0/1024/1024) compressed_backup_size_GB
		, DATEDIFF_BIG(SECOND,backup_start_date,backup_finish_date) duration
		, last_family_number [# files]
    FROM msdb.dbo.backupset
    WHERE type = 'D' AND database_name = db.name
    ORDER BY backup_finish_date DESC
) dt
WHERE db.database_id<>2



SELECT name, dt.compressed_backup_size_GB, duration, [# files]
INTO #DIFF
FROM sys.databases db
OUTER APPLY
(
    SELECT TOP 1
		 database_name
		, CONVERT(DEC(10,3),backup_size/1024.0/1024/1024) backup_size_GB
		, CONVERT(DEC(10,3),compressed_backup_size/1024.0/1024/1024) compressed_backup_size_GB
		, DATEDIFF_BIG(SECOND,backup_start_date,backup_finish_date) duration
		, last_family_number [# files]
    FROM msdb.dbo.backupset
    WHERE type = 'I' AND database_name = db.name
    ORDER BY backup_finish_date DESC
) dt
WHERE db.database_id<>2
 


SELECT name, dt.compressed_backup_size_GB, duration, [# files]
INTO #Log
FROM sys.databases db
OUTER APPLY
(
    SELECT
		MAX(dti.DBName) DBName,
		CONVERT(DEC(10,3),SUM(backup_size_GB)) backup_size_GB,
		CONVERT(DEC(10,3),SUM(dti.compressed_backup_size_GB)) compressed_backup_size_GB,
		SUM(dti.duration) duration,
		AVG([# files]) [# files]
    FROM
    (
		SELECT
		 database_name DBName
		, backup_size/1024.0/1024/1024 backup_size_GB
		, compressed_backup_size/1024.0/1024/1024 compressed_backup_size_GB
		, DATEDIFF_BIG(MILLISECOND,backup_start_date,backup_finish_date)/1000.0 duration
		, last_family_number [# files]
		FROM msdb.dbo.backupset
		WHERE type = 'L' AND backup_finish_date > DATEADD(HOUR,-24,GETDATE()) AND database_name = db.name
    ) dti
) dt
WHERE db.database_id<>2
 
 
 
 
 
SELECT
	CASE WHEN GROUPING(name) = 1
		THEN 'Grand Total'
		ELSE name
	END AS name,
	SUM(full_backup_size_GB) AS full_backup_size_GB,
	SUM([# f_files]) [# f_files],
	--dbo.FormatDuration(SUM(full_restore_dur)) AS full_restore_dur_fmt,
	SUM(full_restore_dur) AS full_restore_dur,
	SUM(diff_backup_size_GB) AS diff_backup_size_GB,
	SUM([# d_files]) [# d_files],
	--dbo.FormatDuration(SUM(diff_restore_dur)) AS diff_restore_dur_fmt,
	SUM(log_backup_size_24h_GB) AS log_backup_size_24h_GB,
	SUM([# l_files]) [# l_files],
	--dbo.FormatDuration(SUM(log_restore_dur_24h)) AS log_restore_dur_24h_fmt,
	dbo.FormatDuration(SUM(ISNULL(base.full_restore_dur,0)+ISNULL(base.diff_restore_dur,0)+ISNULL(log_restore_dur_24h/2,0))) AS total_restore_dur_estimate_fmt,
	SUM(ISNULL(base.full_restore_dur,0)+ISNULL(base.diff_restore_dur,0)+ISNULL(log_restore_dur_24h/2,0)) AS total_restore_dur_estimate
into #backup
FROM (
  SELECT
      f.name,
      f.compressed_backup_size_GB AS full_backup_size_GB,
	  f.[# files] [# f_files],
      f.duration*2 AS full_restore_dur,
      d.compressed_backup_size_GB AS diff_backup_size_GB,
      d.[# files] [# d_files],
	  d.duration*2 AS diff_restore_dur,
      l.compressed_backup_size_GB AS log_backup_size_24h_GB,
      l.[# files] [# l_files],
	  l.duration*3 AS log_restore_dur_24h
  FROM #Full f
  FULL JOIN #DIFF d ON f.name = d.name
  FULL JOIN #Log l ON f.name = l.name
) AS base
GROUP BY GROUPING SETS ((name), ())
ORDER BY GROUPING(name), name;
 
 
 
SELECT
	b.name,
	s.Data_UsedSpace_GB,
	ISNULL(b.full_backup_size_GB,0) full_backup_size_GB,
	ISNULL(b.[# f_files],0) [# f_files],
	--b.full_restore_dur_fmt,
	ISNULL(b.diff_backup_size_GB,0) diff_backup_size_GB,
	ISNULL(b.[# d_files],0) [# d_files],
	--b.diff_restore_dur_fmt,
	ISNULL(b.log_backup_size_24h_GB,0) log_backup_size_24h_GB,
	ISNULL(b.[# l_files],0) [# l_files],
	--b.log_restore_dur_24h_fmt,
	b.total_restore_dur_estimate_fmt,
	b.total_restore_dur_estimate,
	CASE 
		WHEN full_backup_size_GB=0 THEN -1
		WHEN b.full_restore_dur=0 THEN -1
		ELSE full_backup_size_GB*1024/full_restore_dur
	END [Backup Disk speed write index],
	(
		SELECT AVG(full_backup_size_GB*1024/full_restore_dur) 
		FROM #backup 
		WHERE name<>'Grand Total' AND full_backup_size_GB<>0 AND full_restore_dur<>0
	) [AVG Backup Disk speed write index]
FROM #sizes s right join #backup b
ON s.DBName=b.name
WHERE b.name NOT IN ('Grand Total', 'master', 'model', 'msdb')





