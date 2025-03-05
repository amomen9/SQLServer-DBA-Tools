/*
declare @t nvarchar(23) = ''

if (@t is not null)
	print ('not NULL')
else
	print('NULL')
select len(@t)
*/

--select * from msdb.dbo.backupmediaset -- this is not
SELECT * FROM msdb.dbo.backupset
--select * from msdb.dbo.backupfile -- This is not
--select * from msdb.dbo.smart_backup_files -- this is not
SELECT * FROM msdb.dbo.backupmediafamily


----------------------------------------------------------------------------------------

SELECT TOP 1000 b.database_name, b.backup_start_date, b.type,* FROM msdb..backupset b WHERE b.is_copy_only=0 ORDER BY b.backup_set_id DESC



SELECT TOP 1000 MIN(backup_set_id),FORMAT(backup_start_date,'HH:mm','en-uk'), type FROM msdb..backupset WHERE is_copy_only=0 AND type='L' GROUP BY backup_start_date, type ORDER BY MIN(backup_set_id) DESC

SELECT TOP 1000 MIN(backup_set_id),FORMAT(backup_start_date,'yyyy-MM-dd     HH:mm','en-uk'), type, database_name FROM msdb..backupset WHERE is_copy_only=0 AND type='D' GROUP BY backup_start_date, type, database_name ORDER BY MIN(backup_set_id) DESC
-- FORMAT(backup_start_date,'HH:mm','en-uk')


SELECT top 1000 b.database_name, b.backup_start_date, b.type,* FROM msdb..backupset b JOIN msdb..backupfile f ON f.backup_set_id = b.backup_set_id WHERE b.is_copy_only=0 ORDER BY b.backup_set_id DESC


-- SELECT TOP 1000 * FROM msdb..backupfile  X

-- SELECT TOP 1000 * FROM msdb..backupmediafamily true

SELECT top 1000 b.database_name, b.backup_start_date, b.type,f.physical_device_name,b.backup_size/1024.0 FROM msdb..backupset b JOIN msdb..backupmediafamily f ON f.media_set_id = b.media_set_id WHERE b.is_copy_only=0 ORDER BY b.backup_set_id DESC

--SELECT * FROM sys.databases WHERE DB_NAME(database_id) <> 'tempdb'

-- distinct LogBackup or FullBackup L: Log	D: Full	I: Differential	
SELECT DISTINCT a.database_name from
	(SELECT top 10000 b.database_name, b.backup_start_date, b.type,b.backup_size/1024.0 backup_size FROM msdb..backupset b WHERE b.is_copy_only=0 and TYPE='D' ORDER BY b.backup_set_id DESC) a

-- Very simple: DB Name, BK Date, BK Tyoe, BK Size

SELECT top 10000 b.database_name, b.backup_start_date, b.type,b.backup_size/1024.0 backup_size FROM msdb..backupset b WHERE b.is_copy_only=0 
AND TYPE='L' 
ORDER BY b.backup_set_id DESC
--BACKUP DATABASE [Co-ModelDB] TO DISK=N'd:\junk\testdiff.diff' WITH INIT, DIFFERENTIAL


----------------- BACKUP HISTORY --------------------------- Very Good


/*
https://learn.microsoft.com/en-us/sql/relational-databases/system-tables/backupset-transact-sql?view=sql-server-ver16
D = Database
I = Differential database
L = Log
F = File or filegroup
G = Differential file
P = Partial
Q = Differential partial
*/
DECLARE @dbname sysname, @days int
SET @dbname = 'TPCG_WaitStats' --substitute for whatever database name you want
SET @days = -30 --previous number of days, script will default to 30
SELECT 
	b.database_name,
	b.backup_start_date,
	b.backup_finish_date,
	CASE	
		WHEN b.type = 'D' THEN 'Database'
		WHEN b.type = 'F' THEN 'File or filegroup'
		WHEN b.type = 'G' THEN 'Differential file'
		WHEN b.type = 'I' THEN 'Differential database'
		WHEN b.type = 'L' THEN 'Log'
		WHEN b.type = 'P' THEN 'Partial'
		WHEN b.type = 'Q' THEN 'Differential partial'
		ELSE b.type 
	END AS [Backup Type],

	b.backup_size/1024.0/1024/1024 backup_size_GB,
	b.compressed_backup_size/1024.0/1024/1024 compressed_backup_size_GB,
	f.physical_device_name,
	b.user_name
	
FROM msdb.dbo.backupset b JOIN msdb..backupmediafamily f 
ON f.media_set_id = b.media_set_id 
WHERE	database_name = ISNULL(@dbname, database_name) --if no dbname, then return all
		AND b.backup_finish_date >= DATEADD(dd, ISNULL(@days, -30), GETDATE()) --want to search for previous days

ORDER BY b.backup_finish_date DESC



------------ USED SPACE PER DB --------------------------------------------------


DROP TABLE IF EXISTS #UsedSpacePerDB
GO

CREATE TABLE #UsedSpacePerDB(id INT IDENTITY PRIMARY KEY NOT NULL, database_id INT NOT NULL, SUMUsedSpace FLOAT NOT NULL)

INSERT #UsedSpacePerDB
(
    database_id,
	SUMUsedSpace
)
EXEC sys.sp_MSforeachdb 'USE [?] SELECT DB_ID(), SUM(FILEPROPERTY(name,''SpaceUsed''))/128.0 [Used Space] FROM sys.database_files WHERE file_id<>2'

SELECT 
	dt.[DB Name],
	dt.[Reserved Space MB],
	dt.[Used Space MB],
	dt.backup_size_MB,
	dt.[Used Space MB]/dt.[Reserved Space MB]*100
	--dt.[Used Space]/dt.backup_size_MB*100
FROM
(
	SELECT 
		DB_NAME(mf.database_id) [DB Name],
		SUM(size)/128.0 [Reserved Space MB],
		MIN(US.SUMUsedSpace) [Used Space MB],
		(
			SELECT TOP 1
				backup_size/1024.0/1024 backup_size_MB
			
			FROM msdb.dbo.backupset
			WHERE type = 'D' AND DB_ID(database_name) = mf.database_id
			ORDER BY backup_finish_date DESC
		) backup_size_MB
	FROM sys.master_files mf JOIN #UsedSpacePerDB US
	ON US.database_id = mf.database_id
	
	WHERE file_id<>2
	GROUP BY mf.database_id
) dt


--*******************************************************************************************
SELECT database_name,backup_finish_date 
FROM msdb..backupset

SELECT 
	* 
FROM msdb..restorehistory
WHERE destination_database_name = 'JobVisionLogDB'
--AND restore_type = 'D'
ORDER BY restore_date desc

--USE Northwind

--SELECT * FROM [order details] WHERE orderid>10300

--DELETE FROM [ORDER details] WHERE ORDERid>10300


--BACKUP log Northwind TO DISK=N'd:\backup\nw2022.trn' WITH COPY_ONLY


--SELECT * FROM fn_dblog(NULL,Null) WHERE operation LIKE '%delete%'



-------- RESTORE HISTORY ------------------------------------------------------------


DECLARE @dbname sysname, @days int
SET @dbname = NULL --substitute for whatever database name you want
SET @days = -30 --previous number of days, script will default to 30
SELECT
 rsh.destination_database_name AS [Database],
 rsh.user_name AS [Restored By],
 CASE WHEN rsh.restore_type = 'D' THEN 'Database'
  WHEN rsh.restore_type = 'F' THEN 'File'
  WHEN rsh.restore_type = 'G' THEN 'Filegroup'
  WHEN rsh.restore_type = 'I' THEN 'Differential'
  WHEN rsh.restore_type = 'L' THEN 'Log'
  WHEN rsh.restore_type = 'V' THEN 'Verifyonly'
  WHEN rsh.restore_type = 'R' THEN 'Revert'
  ELSE rsh.restore_type 
 END AS [Restore Type],
 rsh.restore_date AS [Restore Started],
 bmf.physical_device_name AS [Restored From], 
 rf.destination_phys_name AS [Restored To]
FROM msdb.dbo.restorehistory rsh
 INNER JOIN msdb.dbo.backupset bs ON rsh.backup_set_id = bs.backup_set_id
 INNER JOIN msdb.dbo.restorefile rf ON rsh.restore_history_id = rf.restore_history_id
 INNER JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE rsh.restore_date >= DATEADD(dd, ISNULL(@days, -30), GETDATE()) --want to search for previous days
AND destination_database_name = ISNULL(@dbname, destination_database_name) --if no dbname, then return all

ORDER BY rsh.restore_history_id DESC
GO