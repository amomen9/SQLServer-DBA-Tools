


CREATE OR ALTER FUNCTION HexCombLSN2Dec(@HexCombLSN NVARCHAR(23))
RETURNS VARCHAR(20)
WITH 
	RETURNS NULL ON NULL INPUT,
	SCHEMABINDING,
	inline=ON
AS
BEGIN
	return
		(select 
			
				(Convert(bigint,Convert(varbinary,Concat('0x',ParseName(lsn,3)),1)) * 10000000000+
				Convert(int,Convert(varbinary,Concat('0x',ParseName(lsn,2)),1))) * 100000+
				Convert(int,Convert(varbinary,Concat('0x',ParseName(lsn,1)),1))
			
		from (select Replace(@HexCombLSN,':','.') lsn) dt)
END
GO

SELECT * FROM
(
	SELECT  
		dbo.hexcomblsn2dec([Current LSN]) converted,
		[Current LSN],
		CONVERT(BIGINT,CONVERT(VARBINARY,'0x'+PARSENAME(REPLACE([Current LSN],':','.'),3),1)) * 10000000000[1],
		CONVERT(INT,CONVERT(VARBINARY,'0x'+PARSENAME(REPLACE([Current LSN],':','.'),2),1)) [2],
		CONVERT(INT,CONVERT(VARBINARY,'0x'+PARSENAME(REPLACE([Current LSN],':','.'),1),1)) [3]
	FROM fn_dblog(NULL,NULL) 
) dt
--WHERE dt.[1]=81 AND 
--dt.[2] = '1' AND 
--dt.[3] = 1 
ORDER BY [Current LSN] DESC
-- 81000000390000001


--SELECT * FROM sys.databases WHERE is_cdc_enabled = 1 AND database_id>4 AND state = 0

--USE test

SELECT 
	--CONVERT(VARBINARY,'0'+dbo.HexCombLSN2Dec([Current LSN]),2),
	CONVERT(VARBINARY,CONVERT(bigint,dbo.HexCombLSN2Dec([Current LSN]))),
	dbo.HexCombLSN2Dec([Current LSN]),
	sys.fn_cdc_map_lsn_to_time(CONVERT(VARBINARY,CONVERT(bigint,dbo.HexCombLSN2Dec([Current LSN])))),
	[Begin Time],
	[End Time],
	* 
FROM fn_dblog(NULL,NULL) 
--WHERE operation = 'LOP_INSERT_ROWS'
ORDER BY [Current LSN] DESC
SELECT sys.fn_cdc_map_lsn_to_time([__$start_lsn]),* FROM cdc.ats_CVFiles_CT 
--WHERE [__$start_lsn] = 0x0000003A000001AD0008
ORDER BY [__$start_lsn] desc
SELECT * FROM Ats.CvFiles
----------------------------------------------------------------------
BEGIN TRAN
-- 1125416165 select convert(varbinary,1125416165)	select 1*0x001035F1
-- 1133724283
SELECT CURRENT_TRANSACTION_ID()
INSERT Ats.CvFiles
(
    CvId,
    FileId,
    FileTypeId,
    FileTitle,
    FileFormat,
    FileID_old,
    CreateDate
    
)
VALUES
( 32364, 1603915, 205, N'رزومه کارجو', N'', NULL, GETDATE() ),
( 32364, 1603915, 205, N'رزومه کارجو', N'', NULL, GETDATE() ),
( 32364, 1603915, 205, N'رزومه کارجو', N'', NULL, GETDATE() )
COMMIT TRAN
EXEC msdb..sp_stop_job @job_name = 'cdc.Co-JobVision-1DB_capture'    -- sysname
EXEC msdb..sp_start_job @job_name = 'cdc.Co-JobVision-1DB_capture'    -- sysname
                        
----------------------------------------------------------------------
DECLARE @script NVARCHAR(max)
SELECT @script = definition FROM sys.all_sql_modules WHERE OBJECT_NAME(object_id) ='fn_cdc_map_lsn_to_time'
PRINT @script
----------------------------------------------------------------------
 
EXEC sys.sp_cdc_enable_db

--SELECT differential_base_lsn FROM sys.database_files
-- 79000002232800106
--BACKUP DATABASE test TO DISK=N'test_full.bak'
-- 81000000390000001
--SELECT sys.fn_cdc_map_lsn_to_time(), sys.lsn

--SELECT CONCAT(100,10,1)

DECLARE @suppress VARBINARY(MAX)
DECLARE @ConvLSN VARCHAR(100)
DECLARE selector CURSOR FOR
	SELECT 
	dbo.HexCombLSN2Dec([Current LSN])
	FROM fn_dblog(NULL,NULL) ORDER BY [Current LSN] DESC
OPEN selector
	FETCH NEXT FROM selector INTO @ConvLSN
	WHILE @@FETCH_STATUS = 0
	BEGIN
		BEGIN TRY        
			SELECT @suppress = CONVERT(VARBINARY,@ConvLSN,2)
		END TRY
		BEGIN CATCH
			SELECT @ConvLSN
		END CATCH
		FETCH NEXT FROM selector INTO @ConvLSN
    END
CLOSE selector
DEALLOCATE selector
SELECT  CONVERT(VARBINARY(MAX),'081000000390000001',2)


SELECT * FROM sys.dm_server_accelerator_status