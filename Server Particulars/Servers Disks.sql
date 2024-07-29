DROP TABLE IF EXISTS #cmdsh
DROP TABLE IF EXISTS #DriveSpec
GO


CREATE TABLE #DriveSpec ( [DriveLetter] NVARCHAR(3), [logical_volume_name] NVARCHAR(4000), [Size_GB] VARCHAR(103), [free_space_GB] VARCHAR(103), [used_space %] DECIMAL(4,2), [drive_type_desc] NVARCHAR(256) )

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
	INSERT INTO #DriveSpec
	SELECT
		[DriveLetter], [logical_volume_name],
		CONVERT(VARCHAR(103),CONVERT(DEC(20,2),cte.Size_bytes/1024.0/1024/1024))+' GB' [Size_GB], 
		CONVERT(VARCHAR(103),CONVERT(DEC(20,2),cte.free_space_bytes/1024.0/1024/1024))+' GB' [free_space_GB],
		
		(cte.Size_bytes-cte.free_space_bytes)*100.0/cte.Size_bytes used_space_percentage,
		[drive_type_desc]
	FROM cte

	SELECT * FROM #DriveSpec


END