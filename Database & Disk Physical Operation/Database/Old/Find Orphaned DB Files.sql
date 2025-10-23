-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2024-03-13"
-- Description:         "Find Orphaned DB Files Orphan"
-- License:             "Please refer to the license file"
-- =============================================



USE master
GO

CREATE OR ALTER FUNCTION udf_FindOrphanedDBFiles()
RETURNS 
AS
BEGIN
	SELECT 
		DISTINCT
		dt2.full_filesystem_path,dt2.Size_MB, dt2.file_or_directory_name
	FROM
	(
		SELECT 
			full_filesystem_path, file_or_directory_name, size_in_bytes/1024.0/1024 Size_MB
		FROM
		(
			SELECT DISTINCT *
			FROM
			(
				SELECT CONVERT(NVARCHAR(500),'') Folder WHERE 1=2
				UNION ALL
				SELECT DISTINCT LEFT(physical_name,LEN(physical_name)-CHARINDEX('\',REVERSE(physical_name))) FROM sys.master_files mf
				UNION ALL
				SELECT IIF(RIGHT(TRIM(CONVERT(NVARCHAR(500),SERVERPROPERTY('InstanceDefaultDataPath'))),1)='\',LEFT(TRIM(CONVERT(NVARCHAR(500),SERVERPROPERTY('InstanceDefaultDataPath'))),LEN(TRIM(CONVERT(NVARCHAR(500),SERVERPROPERTY('InstanceDefaultDataPath'))))-1),TRIM(CONVERT(NVARCHAR(500),SERVERPROPERTY('InstanceDefaultDataPath'))))
				UNION ALL
				SELECT IIF(RIGHT(TRIM(CONVERT(NVARCHAR(500),SERVERPROPERTY('InstanceDefaultLogPath'))),1)='\',LEFT(TRIM(CONVERT(NVARCHAR(500),SERVERPROPERTY('InstanceDefaultLogPath'))),LEN(TRIM(CONVERT(NVARCHAR(500),SERVERPROPERTY('InstanceDefaultLogPath'))))-1),TRIM(CONVERT(NVARCHAR(500),SERVERPROPERTY('InstanceDefaultLogPath'))))
			) dt -- Defining directories to search within. Add any other directory that you think might contain database data and is not included here.
		) dt1
		CROSS APPLY sys.dm_os_enumerate_filesystem(Folder,'*')
		WHERE	full_filesystem_path NOT LIKE '%.hkckp' AND
				full_filesystem_path NOT LIKE '%.pdb' AND
                full_filesystem_path NOT LIKE '%.obj' AND
                full_filesystem_path NOT LIKE '%.c' AND
                full_filesystem_path NOT LIKE '%.dll' AND
                full_filesystem_path NOT LIKE '%.xml' AND
				full_filesystem_path NOT LIKE '%.out' AND
                full_filesystem_path NOT LIKE '%.cer' AND
                full_filesystem_path NOT LIKE '%.hdr' AND
                full_filesystem_path NOT LIKE '%model_msdbdata.mdf' AND
                full_filesystem_path NOT LIKE '%model_replicatedmaster.mdf' AND
                full_filesystem_path NOT LIKE '%model_msdblog.ldf' AND
                full_filesystem_path NOT LIKE '%model_replicatedmaster.ldf'
	) dt2 LEFT JOIN sys.master_files mf	JOIN sys.databases db
	ON db.database_id = mf.database_id --AND db.user_access_desc = 'MULTI_USER'
	ON dt2.full_filesystem_path=LEFT(physical_name,2)+REPLACE(RIGHT(physical_name,DATALENGTH(physical_name)/2-2),'\\','\')
	WHERE mf.database_id IS NULL
	ORDER BY dt2.Size_MB DESC
END
GO


EXEC usp_FindOrphanedDBFiles
GO

DROP PROC dbo.usp_FindOrphanedDBFiles
GO


--SELECT DISTINCT * FROM
--(
--	SELECT DB_NAME(database_id) COLLATE Persian_100_CI_AI name FROM sys.databases
--	EXCEPT
--	SELECT * FROM OPENQUERY([KARBOARD-DB2,2828],'SELECT DB_NAME(database_id) FROM sys.databases')
--) dt


--SELECT * FROM sys.dm_hadr_database_replica_states
--SELECT * FROM sys.dm_hadr_database_replica_cluster_states


--SELECT * FROM sys.master_files WHERE physical_name LIKE 'D:\Database Data\%'


--SELECT (350000*50000.0/920)*1.5

--ALTER DATABASE SCOPED CONFIGURATION SET 
--SELECT DATABASEPROPERTY('CandoMainDB','IsFulltextEnabled')
--SELECT name,is_fulltext_enabled FROM sys.databases