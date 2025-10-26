-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2025-09-22"
-- Description:         "Servers Particulars (All)"
-- License:             "Please refer to the license file"
-- =============================================



DROP TABLE IF EXISTS #cmdsh
DROP TABLE IF EXISTS #DriveSpec
GO


	--SELECT 
	--	IIF(is_fci_clustered = 1, (SELECT NodeName FROM sys.dm_os_cluster_nodes WHERE is_current_owner=1), ds.Server) Server,
	--	MIN([IP Address])
	--FROM
	--(
	--	SELECT
	--		IIF(EXISTS (SELECT * FROM sys.dm_os_cluster_nodes), 1, 0) [is_fci_clustered],
	--		CONVERT(NVARCHAR(256),SERVERPROPERTY('MachineName')) Server,
	--		CONVERT(NVARCHAR(60),value_data) [IP Address]
	--	FROM sys.dm_server_registry
	--	WHERE value_name = 'IpAddress'
	--) ds
	--WHERE LEN([IP Address])-LEN(REPLACE([IP Address],'.',''))=3 AND ds.[IP Address] NOT LIKE '169.%' AND ds.[IP Address] NOT LIKE '127.%'
DECLARE @os_server_name NVARCHAR(256),
		@os_server_ip VARCHAR(15)

SELECT 
	@os_server_name = MIN(ISNULL(ds.fci_node_name, ds.Server)),
	@os_server_ip = MIN([IP Address])
FROM
(
	SELECT
		IIF(EXISTS (SELECT * FROM sys.dm_os_cluster_nodes), (SELECT NodeName FROM sys.dm_os_cluster_nodes WHERE is_current_owner=1), NULL) fci_node_name,
		CONVERT(NVARCHAR(256),SERVERPROPERTY('MachineName')) Server,
		CONVERT(NVARCHAR(60),value_data) [IP Address]
	FROM sys.dm_server_registry
	WHERE value_name = 'IpAddress'
) ds
WHERE LEN([IP Address])-LEN(REPLACE([IP Address],'.',''))=3 AND ds.[IP Address] NOT LIKE '169.%' AND ds.[IP Address] NOT LIKE '127.%'



CREATE TABLE #DriveSpec ( [DriveLetter] NVARCHAR(3), [logical_volume_name] NVARCHAR(4000), [Size_GB] VARCHAR(103), [free_space_GB] VARCHAR(103), [used_space %] DECIMAL(5,2), [drive_type_desc] NVARCHAR(256), SuggestedNewCapacity VARCHAR(103) )

DECLARE @SQL VARCHAR(8000) 
IF (SELECT host_platform FROM sys.dm_os_host_info) = 'Windows'
BEGIN 
	DECLARE @cmdshell_initial_status BIT = (SELECT CONVERT(CHAR(1),value_in_use) FROM sys.configurations WHERE name ='xp_cmdshell')

	IF @cmdshell_initial_status=0
	BEGIN
		EXECUTE sp_configure 'show advanced options', 1; RECONFIGURE; EXECUTE sp_configure 'xp_cmdshell', 1; RECONFIGURE;
	END


	SET NOCOUNT ON

	CREATE TABLE #cmdsh (id INT PRIMARY KEY IDENTITY NOT NULL, [output] NVARCHAR(500))

	-- either of the follwoing work:
	SET @SQL = --N'@echo off && cd && for /f "tokens=1,2" %a in (''wmic logicaldisk get DeviceID^, Size'') do if %a NEQ DeviceID (echo %a: %b)'
	N'for /f "tokens=1,2,3" %a in (''wmic logicaldisk get DeviceID^, Size^, VolumeName'') do @if %a NEQ DeviceID (echo %a: %b Volume Name: %c)'
	--N'powershell "Get-PSDrive -PSProvider ''FileSystem'' | Select-Object Name, @{Name=\"TotalCapacityGB\"; Expression={[math]::Round(($_.Used + $_.Free) / 1GB, 2)}} "'
	PRINT @SQL
	INSERT #cmdsh
	EXEC sys.xp_cmdshell @SQL


	IF @cmdshell_initial_status = 0
	BEGIN
		EXECUTE sp_configure 'xp_cmdshell', 0; RECONFIGURE; --EXECUTE sp_configure 'show advanced options', 0; RECONFIGURE;
	END



	DELETE FROM #cmdsh WHERE output IS NULL
	DELETE FROM #cmdsh WHERE id = (SELECT MAX(id) FROM #cmdsh )
	--SELECT * FROM #cmdsh
	
		--	SELECT STRING_AGG(REPLACE(ss1.value,'Volume Name',''),',') Drives FROM #cmdsh CROSS APPLY STRING_SPLIT(output,':') ss1
		--WHERE TRIM(ss1.value) NOT IN ('',',')
		--GROUP BY id

	--SELECT *,
	
	--LEFT(dt.Drives,1)+':\' DriveLetter,
	--	TRIM(RIGHT(dt.Drives, CHARINDEX(',',REVERSE(dt.Drives))-1)) logical_volume_name,
	--	CONVERT	(VARCHAR(100),
	--		CONVERT	(DECIMAL(20,2),
	--			CONVERT	(bigint,
	--						LEFT(RIGHT(dt.Drives,LEN(dt.Drives)-2),
	--								CHARINDEX(',',RIGHT(dt.Drives,LEN(dt.Drives)-2))-1
	--							)
	--					)--/1024.0/1024/1204
	--				)
	--			)
	--FROM 
	--(
	--	SELECT STRING_AGG(REPLACE(ss1.value,'Volume Name',''),',') Drives FROM #cmdsh CROSS APPLY STRING_SPLIT(output,':') ss1
	--	WHERE TRIM(ss1.value) NOT IN ('',',')
	--	GROUP BY id
	--) dt

	; WITH cte as
	(
		SELECT	
			LEFT(dt.Drives,1)+':\' DriveLetter,
			TRIM(RIGHT(dt.Drives, CHARINDEX(',',REVERSE(dt.Drives))-1)) logical_volume_name,
				
			CONVERT	(bigint,
						LEFT(RIGHT(dt.Drives,LEN(dt.Drives)-2),
								CHARINDEX(',',RIGHT(dt.Drives,LEN(dt.Drives)-2))-1
							)
					) Size_bytes,

			fd.free_space_in_bytes free_space_bytes,
		
			fd.drive_type_desc
		FROM
		(
			SELECT STRING_AGG(REPLACE(ss1.value,'Volume Name',''),',') Drives FROM #cmdsh CROSS APPLY STRING_SPLIT(output,':') ss1
			WHERE TRIM(ss1.value) NOT IN ('',',')
			GROUP BY id
		) dt JOIN sys.dm_os_enumerate_fixed_drives fd
		ON fd.fixed_drive_path = LEFT(dt.Drives,1)+':\'
	)
	, results_in_GB AS
	(
		SELECT
			[DriveLetter], [logical_volume_name],
			CONVERT(DEC(20,2),cte.Size_bytes/1024.0/1024/1024) [Size_GB], 
			CONVERT(DEC(20,2),cte.free_space_bytes/1024.0/1024/1024) [free_space_GB],		
			(cte.Size_bytes-cte.free_space_bytes)*100.0/cte.Size_bytes used_space_percentage,
			[drive_type_desc]
		FROM cte
	)
	INSERT INTO #DriveSpec
	SELECT
		[DriveLetter], [logical_volume_name],
		CONVERT(VARCHAR(103),[Size_GB]) +' GB' [Size_GB],
		CONVERT(VARCHAR(103),[free_space_GB])+' GB' [free_space_GB],
		rig.used_space_percentage,
		rig.drive_type_desc,
		-- Return the target desired drive size value if it requires extension
		IIF(rig.used_space_percentage>=80,CONVERT(VARCHAR(103),CEILING((rig.Size_GB-rig.free_space_GB)/70.0)*100)+ ' GB','No extension needed') SuggestedNewCapacity
	FROM results_in_GB rig
	WHERE drive_type_desc = 'DRIVE_FIXED'

	SELECT 
		@os_server_name [Server Name],
		@os_server_ip [Server IP],
		ds.DriveLetter,
		ds.logical_volume_name,
		ds.[Extended Size],
		ds.[used_space %],
		ds.Size_GB,
		ds.free_space_GB,
		ds.drive_type_desc
	FROM
	(
		SELECT
			[DriveLetter],
			[logical_volume_name],
			SuggestedNewCapacity [Extended Size],
			[used_space %],
			[Size_GB],
			[free_space_GB],
			drive_type_desc
		FROM #DriveSpec
--		WHERE SuggestedNewCapacity<>'No extension needed'
	) ds


END ELSE
BEGIN
	SELECT fixed_drive_path mount_point, drive_type_desc, CONVERT(DECIMAL(10,2),free_space_in_bytes/1024.0/1024) free_space_mb FROM sys.dm_os_enumerate_fixed_drives
	--SELECT @SQL = STRING_AGG(''''+Size_in_GB+''''+' '''+volume+'''',' ,') WITHIN GROUP (ORDER BY dt.volume)
	--FROM
	--(
	--	SELECT TOP 100000000 
	--		ISNULL(volume_mount_point, dr.drive_letter) volume,
	--		ISNULL(CONVERT(VARCHAR,CEILING(total_bytes/1048576.0/1024))+'GB'+IIF(logical_volume_name='','',' ('+ logical_volume_name+')'),'-') Size_in_GB
	--	FROM 
	--	(
	--		SELECT
	--			f.physical_name DriveLetter,
	--			f.database_id,
	--			f.file_id					
	--		FROM sys.master_files AS f
	--		UNION ALL
	--		SELECT 'C:\', NULL, NULL
	--	) dti 
	--		OUTER APPLY 
	--		sys.dm_os_volume_stats(dti.database_id, dti.file_id) 
	--	LEFT JOIN (SELECT 'C:\' drive_letter UNION ALL 
	--				SELECT 'D:\' UNION ALL SELECT 'E:\' UNION ALL SELECT 'F:\' UNION ALL 
	--				SELECT 'G:\' UNION ALL SELECT 'H:\' UNION ALL SELECT 'I:\' UNION ALL
	--				SELECT 'J:\' UNION ALL SELECT 'K:\' UNION ALL SELECT 'L:\' UNION ALL
	--				SELECT 'M:\' UNION ALL SELECT 'N:\' UNION ALL SELECT 'O:\' UNION ALL
	--				SELECT 'P:\' UNION ALL SELECT 'Q:\' UNION ALL SELECT 'R:\' UNION ALL 
	--				SELECT 'S:\' UNION ALL SELECT 'T:\' UNION ALL SELECT 'U:\' UNION ALL 
	--				SELECT 'V:\' UNION ALL SELECT 'W:\' UNION ALL SELECT 'X:\' UNION ALL
	--				SELECT 'Y:\' UNION ALL SELECT 'Z:\' 
	--		) dr
	--	ON ISNULL(volume_mount_point,0) = dr.drive_letter
	--	GROUP by volume_mount_point, dr.drive_letter, logical_volume_name, total_bytes, available_bytes 
	--	ORDER by dr.drive_letter
	--) dt
	--SET @SQL = 'SELECT '+@SQL
	--PRINT @SQL
	--EXEC(@SQL)
END
GO





DECLARE @columns NVARCHAR(MAX), @sql NVARCHAR(MAX);
-- Construct the column list for the IN clause
-- Either through getting distinct entries from #DriveSpec:
/*
SELECT @columns = COALESCE(@columns + ',','') + QUOTENAME(DriveLetter)
FROM (SELECT DISTINCT DriveLetter FROM #DriveSpec WHERE drive_type_desc = 'DRIVE_FIXED') AS DriveLetters;
*/
-- Or using all drive letters regardless of what drives exist on the system.
SELECT @columns = '[C:\], [D:\], [E:\], [F:\], [G:\], [H:\], [I:\], [J:\], [K:\], [L:\], [M:\], [N:\], [O:\], [P:\], [Q:\], [R:\], [S:\], [T:\], [U:\], [V:\], [W:\], [X:\], [Y:\], [Z:\]'


-- Construct the full pivot query
SET @sql = '
	SELECT ' + @columns + '
	FROM (
		SELECT 
		DriveLetter,
		Size_GB + IIF(LEN(REPLACE(REPLACE(logical_volume_name, CHAR(32), ''''), CHAR(13), '''')) > 0, '' ('' + logical_volume_name + '') '', '' (No Logical Name)'') AS VolumeInfo
		FROM #DriveSpec
		WHERE drive_type_desc = ''DRIVE_FIXED''
	) AS SourceTable
	PIVOT (
	MAX(VolumeInfo)
	FOR DriveLetter IN (' + @columns + ')
	) AS PivotTable;
';

-- Execute the pivot query
EXEC sp_executesql @sql;
GO



--SELECT 	
--	volume_mount_point +IIF(logical_volume_name='','',' ('+ logical_volume_name+')') volume,
--	CEILING(total_bytes/1048576.0/1024) as Size_in_GB 
--FROM sys.master_files AS f CROSS APPLY
--	sys.dm_os_volume_stats(f.database_id, f.file_id) 
--GROUP by volume_mount_point, logical_volume_name, total_bytes, available_bytes
--ORDER by volume 


--SELECT DISTINCT local_net_address, local_tcp_port FROM sys.dm_exec_connections c  JOIN sys.dm_exec_sessions s
--ON s.session_id = c.session_id
--WHERE local_net_address IS NOT NULL 
GO


IF (SELECT host_platform FROM sys.dm_os_host_info) = 'Windows'
	SELECT 
		dto.server,
		STRING_AGG(local_net_address,', ') [IPAddress(s)],
		dto.PORT,
		dto.SQLVersion,
		dto.CU,
		REPLACE(dto.os_version_name,'(Hypervisor)','') os_version_name,
		IIF(dto.os_version_name LIKE '%(Hypervisor)%','VM','Physical') machine_type
	FROM 
	(
		SELECT DISTINCT dt1.server, dt1.SQLVersion, dt1.CU, dt2.PORT, dt1.os_version_name
		FROM (SELECT @@SERVERNAME server,SERVERPROPERTY('ProductMajorVersion') SQLVersion, SERVERPROPERTY('ProductUpdateLevel') CU,SUBSTRING(@@VERSION, CHARINDEX('on Windows', @@VERSION) + 10, LEN(@@VERSION)) AS os_version_name) dt1,
		(select RIGHT(ar.read_only_routing_url,CHARINDEX(':',REVERSE(ar.read_only_routing_url))-1) PORT from sys.availability_replicas ar WHERE ar.replica_server_name = @@SERVERNAME) dt2
	) dto
		CROSS JOIN (SELECT DISTINCT local_net_address, local_tcp_port FROM sys.dm_exec_connections c  JOIN sys.dm_exec_sessions s
		ON s.session_id = c.session_id
		WHERE local_net_address IS NOT NULL) dt3
		GROUP BY dto.server, dto.SQLVersion, dto.CU, dto.PORT, dto.os_version_name	
ELSE
	SELECT dt1.server, STRING_AGG(local_net_address,', ') [IPAddress(s)], dt1.SQLVersion, dt1.CU, dt1.os_version_name
	FROM (SELECT @@SERVERNAME server,SERVERPROPERTY('ProductMajorVersion') SQLVersion, SERVERPROPERTY('ProductUpdateLevel') CU,SUBSTRING(@@VERSION, CHARINDEX('on Windows', @@VERSION) + 10, LEN(@@VERSION)) AS os_version_name) dt1
	CROSS JOIN (	SELECT DISTINCT local_net_address, local_tcp_port FROM sys.dm_exec_connections c  JOIN sys.dm_exec_sessions s
	ON s.session_id = c.session_id
	WHERE local_net_address IS NOT NULL ) dt3
	GROUP BY dt1.server, dt1.SQLVersion, dt1.CU, dt1.os_version_name

GO


SELECT
--cpu_count AS logical_processors,
cpu_count / hyperthread_ratio AS sockets
,hyperthread_ratio AS logical_per_physical
,CEILING(physical_memory_kb/1024.0/1024) ram_GB
--,(SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE') AS visible_online_processors
FROM sys.dm_os_sys_info
GO


IF (SELECT host_platform FROM sys.dm_os_host_info) <> 'Windows'
	SELECT 'Extracting BackupDirectory and DataRootDirectory is only available on Windows Operating System.' [Error Message]
ELSE
BEGIN
	DECLARE @DataRoot nvarchar(512);
	EXEC master.dbo.xp_instance_regread
	N'HKEY_LOCAL_MACHINE',
	N'Software\Microsoft\MSSQLServer\Setup',
	N'SQLDataRoot',
	@DataRoot OUTPUT;


	DECLARE @BackupDirectory nvarchar(4000);
	EXEC master.dbo.xp_instance_regread
	N'HKEY_LOCAL_MACHINE',
	N'Software\Microsoft\Microsoft SQL Server\MSSQLServer',
	N'BackupDirectory',
	@BackupDirectory OUTPUT;

SELECT 
	@DataRoot AS DataRootDirectory,
	@BackupDirectory DefaultBackupDirectory,
	serverproperty('InstanceDefaultDataPath') InstanceDefaultDataPath,
	SERVERPROPERTY('InstanceDefaultLogPath') InstanceDefaultLogPath,
	SERVERPROPERTY('Collation') Collation
END
GO



SELECT 
	servicename,
	service_account,
	startup_type_desc,
	instant_file_initialization_enabled
FROM sys.dm_server_services
GO


SELECT SERVERPROPERTY('Edition') [License Edition],
	host_platform,
	host_distribution,
	container_type_desc
FROM sys.dm_os_host_info, sys.dm_os_sys_info
GO


--SELECT feature_name, feature_id
--FROM sys.dm_db_persisted_sku_features;

--IF (SELECT host_platform FROM sys.dm_os_host_info) = 'Windows'
--BEGIN
--	
--	DECLARE @cmdshell_initial_status BIT = (SELECT CONVERT(CHAR(1),value_in_use) FROM sys.configurations WHERE name ='xp_cmdshell')
--
--	IF @cmdshell_initial_status=0
--	BEGIN
--		EXECUTE sp_configure 'show advanced options', 1; RECONFIGURE; EXECUTE sp_configure 'xp_cmdshell', 1; RECONFIGURE;
--	END
--
--
--	TRUNCATE TABLE #cmdsh
--	INSERT #cmdsh
--	EXEC sys.xp_cmdshell 'powershell "get-wmiobject win32_product | where {$_.Name -match \"SQL\" -AND $_.vendor -eq \"Microsoft Corporation\"}"'
--	
--	DELETE FROM #cmdsh WHERE output IS NULL OR (output NOT LIKE 'Name%' AND output NOT LIKE 'Version%') 
--
--	IF @cmdshell_initial_status = 0
--	BEGIN
--		EXECUTE sp_configure 'xp_cmdshell', 0; RECONFIGURE; --EXECUTE sp_configure 'show advanced options', 0; RECONFIGURE;
--	END
--
--
--	; WITH cte AS
--    (
--		SELECT 
--			ROW_NUMBER() over (ORDER BY id) + ROW_NUMBER() over (ORDER BY id)%2 in_row,
--			* 
--		FROM #cmdsh
--	)
--	, cte2
--	AS
--    (
--		SELECT cte.in_row
--		FROM cte
--		WHERE output LIKE '%vend%' 
--		OR output LIKE '%IdentifyingNumber%' 
--		OR output LIKE '%caption%' 
--		OR output LIKE '%SQL Server Management Studio%'
--		OR output LIKE '%Microsoft ODBC Driver%'
--		OR output LIKE '%Microsoft OLE DB Driver%'
--		OR output LIKE '%Database Engine Shared%'
--		OR output LIKE '%T-SQL%'
--		OR output LIKE '%XEvent%'
--		OR output LIKE '%Connection Info%'
--		OR output LIKE '%common%'
--		OR output LIKE '%RsFx%'
--		OR output LIKE '%VSS Writer for SQL Server%'
--		OR output LIKE '%Microsoft SQL Server%Setup%'
--		OR output LIKE '%Shared%'
--		OR output LIKE '%Browser for SQL Server%'
--		OR output LIKE '%Extension%'
--		OR output LIKE '%Diagnostic%'
--		OR output LIKE '%Batch%'
--		OR output LIKE '%DMF%'
--		OR output LIKE '%Native Client%'
--		OR output LIKE '%Diagnostic%'
--		OR output LIKE '%Diagnostic%'
--	)
--	, cte3 as
--	(
--		SELECT cte.id, cte.in_row, LEAD(cte.in_row) OVER (ORDER BY id) lead_row, cte.output + REPLICATE(CHAR(32),11) + LEAD(cte.output) OVER (ORDER BY id) feature_details FROM cte left JOIN cte2
--		ON cte.in_row = cte2.in_row
--		WHERE cte2.in_row IS NULL
--	)
--	, cte4 as
--	(
--		SELECT DISTINCT
--			cte3.feature_details
--		FROM cte3
--		WHERE in_row = lead_row
--	)
--	SELECT ROW_NUMBER() OVER (ORDER BY cte4.feature_details) row,
--		cte4.feature_details
--	FROM cte4
--
--
--END ELSE		
--		SELECT 'Getting installed features is not available on Linux.' [Error Message]
		



