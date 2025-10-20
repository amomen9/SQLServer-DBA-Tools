	
	USE master
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
    
	
----------------------- SELECT #1: Each Datafile for every database: ----------------------------
SELECT d.create_date,#sd.* FROM #sd JOIN sys.databases d
ON DBName=d.name COLLATE Persian_100_CI_AI
WHERE type_desc='ROWS'-- AND Drive = 'd:'
--	DBName LIKE 'Co-%DB' AND 
--	max_size <> 0
ORDER BY (Size_GB-UsedSpace_GB) DESC


----------------------- Each Database (Aggregated over datafiles): ----------------------------
--SELECT d.create_date,s.[Server IP],s.DBName,type_desc,STRING_AGG(s.Drive,', '), SUM(s.Size_GB) Size_GB, SUM(s.UsedSpace_GB) UsedSpace_GB, SUM(s.UsedSpace_GB)*100.0/SUM(s.Size_GB) [UsedSpace%], s.[database state], s.log_reuse_wait_desc FROM #sd s JOIN sys.databases d
--ON DBName=d.name COLLATE Persian_100_CI_AI
--WHERE type_desc='ROWS'--Drive = 'd:'
--GROUP BY d.create_date, s.[Server IP], s.DBName, type_desc, s.[database state], s.log_reuse_wait_desc
----	DBName LIKE 'Co-%DB' AND 
----	max_size <> 0
--ORDER BY Size_GB DESC




---------------------- SELECT #2: Each Database (Aggregated over database files): -----------------------
SELECT * FROM 
(
	SELECT 
		dt1.create_date,
		dt1.DBName,
		dt1.Size_GB Data_Size_GB,
		dt2.Size_GB Log_Size_GB,
		dt1.UsedSpace_GB Data_UsedSpace_GB,
		dt1.Size_GB-dt1.UsedSpace_GB Data_FreeSpace_GB,
		STRING_AGG(dt1.Drive,', ') [Data Spanned over Drives],
		dt2.UsedSpace_GB Log_UsedSpace_GB,
		dt2.Size_GB-dt2.UsedSpace_GB Log_FreeSpace_GB,
		STRING_AGG(dt2.Drive,', ') [Log Spanned over Drives],
		dt1.[UsedSpace%] [Data_UsedSpace%],
		dt2.[UsedSpace%] [Log_UsedSpace%],
		dt1.[database state],
		dt1.log_reuse_wait_desc
	FROM 
	(
		SELECT d.create_date,#sd.DBName, Drive, type_desc, SUM(Size_GB) Size_GB, SUM(UsedSpace_GB) UsedSpace_GB, SUM(UsedSpace_GB)*100.0/SUM(Size_GB) [UsedSpace%], [database state], #sd.log_reuse_wait_desc
		FROM #sd JOIN sys.databases d
		ON DBName=d.name COLLATE Persian_100_CI_AI
		WHERE type_desc='ROWS' AND Drive = 'd:'
	
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
ORDER BY  ISNULL(Data_FreeSpace_GB,1000000000) DESC--+ISNULL(Log_UsedSpace_GB,0) desc--Size_GB DESC




------------------------- SELECT #3: Log files per database: ------------------------------------
SELECT DBName, [database state], STRING_AGG(Drive,', ') Drives, log_reuse_wait_desc, type_desc, [Logical Name],  SUM(Size_GB) size_GB, SUM(UsedSpace_GB) LogUsedSpace_GB, SUM(UsedSpace_GB)*100.0/SUM(Size_GB) [LogUsedSpace%] 
FROM #sd
WHERE type_desc='Log'
GROUP BY DBName, [database state], log_reuse_wait_desc,type_desc, [Logical Name]
ORDER BY  [LogUsedSpace%] 

------------------------- SELECT #4: temp for cando: --------------------------------------------

SELECT DBName, [database state], STRING_AGG(Drive,', ') Drives, #sd.log_reuse_wait_desc, type_desc, [Logical Name],  SUM(Size_GB) size_GB, SUM(UsedSpace_GB) LogUsedSpace_GB, SUM(UsedSpace_GB)*100.0/SUM(Size_GB) [LogUsedSpace%], dbs.user_access_desc, dbs.state_desc 
FROM #sd JOIN sys.databases dbs ON DBName=name COLLATE Persian_100_CI_AI
WHERE type_desc='Log'
GROUP BY DBName, [database state], #sd.log_reuse_wait_desc,type_desc, [Logical Name], dbs.user_access_desc, dbs.state_desc 
ORDER BY  size_GB DESC,[LogUsedSpace%] 



-- Reorganize and resize:
/*
USE JobVisionMatchDB
GO
DBCC SHRINKFILE (N'JobVisionMatchDB' , 70000)
GO
*/

-- Release Unused Space:
/*
USE [JobVisionMachineLearningDB]
GO
DBCC SHRINKFILE (N'JobVisionMachineLearningDB' , 0, TRUNCATEONLY)
GO
*/



--BACKUP LOG JobVisionCandidateLogDB TO DISK=N'\\172.16.40.35\Backup\Backup\Database\Log\JobVisionCandidateLogDB_Log_202211011324.trn' WITH STATS = 10



-- Find log files that are not on E drive:
--SELECT 
--	DB_NAME(database_id) DBName,
--	LEFT(physical_name,CHARINDEX('\',physical_name)) [Drive],
--	type_desc
--FROM sys.master_files
--WHERE database_id>4 and type_desc = 'LOG' AND LEFT(physical_name,CHARINDEX('\',physical_name)) <> 'E:\'


--USE KarBoardDB
--GO
--DBCC SHRINKDATABASE(N'KarBoardDB' )
--GO
--USE KarBoardDB_stage
--GO
--DBCC SHRINKDATABASE(N'KarBoardDB_stage' )
--GO
