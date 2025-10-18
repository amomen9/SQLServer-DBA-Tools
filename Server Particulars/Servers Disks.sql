USE master
GO

/*
CREATE OR ALTER PROCEDURE dbo.GetLastWindowsUpdateDate
AS
BEGIN
    SET NOCOUNT ON;
    
	DECLARE @Result TABLE (OutputText NVARCHAR(4000));

	INSERT INTO @Result
	EXEC xp_cmdshell 'powershell -command "(Get-WinEvent -FilterHashtable @{LogName=''System'';ProviderName=''Microsoft-Windows-WindowsUpdateClient'';ID=19} -MaxEvents 1 | Select-Object -Property TimeCreated,@{Name=''Update'';Expression={($_.Message -split \"`n\" | Where-Object {$_ -match ''update''})[0] -replace ''^.*update '',''''}},@{Name=''KB'';Expression={($_.Message -split '' '' | Where-Object {$_ -match ''KB\d+''})[0]}}).TimeCreated.ToString(''yyyy-MM-dd HH:mm:ss'')"'

	-- Return just the date (filtering out NULL/error rows)
	SELECT OutputText AS LastUpdateDate
	FROM @Result
	WHERE OutputText IS NOT NULL 
	  AND OutputText NOT LIKE '%ERROR%'
	  AND OutputText LIKE '____-__-__ __:__:__';

END
GO
*/


DROP TABLE IF EXISTS #cmdsh
DROP TABLE IF EXISTS #DriveSpec
GO


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

	--EXEC dbo.GetLastWindowsUpdateDate;

	CREATE TABLE #cmdsh (id INT PRIMARY KEY IDENTITY NOT NULL, [output] NVARCHAR(500))

	-- either of the follwoing work:
	SET @SQL = --N'@echo off && cd && for /f "tokens=1,2" %a in (''wmic logicaldisk get DeviceID^, Size'') do if %a NEQ DeviceID (echo %a: %b)'
	N'for /f "tokens=1,2,3" %a in (''wmic logicaldisk get DeviceID^, Size^, VolumeName'') do @if %a NEQ DeviceID (echo %a: %b Volume Name: %c)'
	--N'powershell "Get-PSDrive -PSProvider ''FileSystem'' | Select-Object Name, @{Name=\"TotalCapacityGB\"; Expression={[math]::Round(($_.Used + $_.Free) / 1GB, 2)}} "'
	PRINT @SQL
	INSERT #cmdsh
	EXEC sys.xp_cmdshell @SQL

	WHILE (
		SELECT COUNT(*) 
		FROM sys.dm_exec_requests r
		CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
		WHERE 
			r.status IN ('running', 'suspended', 'runnable')
			AND t.text LIKE '%xp_cmdshell%'
			-- Exclude this detection query itself
			AND t.text NOT LIKE '%SELECT COUNT(*) FROM sys.dm_exec_requests r CROSS APPLY%'
		) > 0
	BEGIN
		WAITFOR DELAY '00:00:00.500'
	END

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
		ISNULL(cn.NodeName,ds.Server) Server,
		ds.[IP Address],
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
			IIF(CHARINDEX('\',@@SERVERNAME)>0,SUBSTRING(@@SERVERNAME,1,CHARINDEX('\',@@SERVERNAME)-1),@@SERVERNAME) Server,
			CONNECTIONPROPERTY('local_net_address') [IP Address],
			[DriveLetter],
			[logical_volume_name],
			SuggestedNewCapacity [Extended Size],
			[used_space %],
			[Size_GB],
			[free_space_GB],
			drive_type_desc
		FROM #DriveSpec
		WHERE SuggestedNewCapacity<>'No extension needed'
	) ds
	LEFT JOIN sys.dm_os_cluster_nodes cn
	ON ds.Server = cn.NodeName

END





--DROP PROC IF EXISTS dbo.GetLastWindowsUpdateDate
--GO


