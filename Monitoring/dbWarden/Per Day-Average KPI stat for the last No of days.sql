

-- ==============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2022.03.19>
-- Latest Update Date:	<2022.05.14>
-- Description:			<Server Resources Reports (DQL, IOPs, CPU Time, CQL, PLE etc.) from dbWarden database>
-- ==============================================




USE dbWarden
GO



CREATE OR ALTER PROC KPI_Stat_Report
	@StartDate DATE,
	@EndDate DATE,
	@StartTime TIME,
	@EndTime TIME,
	@ntile INT = 1,
	@DQL BIT = 0,
	@IOPS BIT = 0,
	@PLE BIT = 0,
	@CPUTime BIT = 0,
    @CQL BIT = 0,
	@UsedWorker BIT = 0,
	@LongRunnigQueries_DataOperationElements BIT = 0		-- Logical Read, Read, Write
AS
BEGIN
	DECLARE @DayCount int
	SELECT @DayCount = DATEDIFF(DAY,@StartDate,@EndDate)+1
	
	SET @DQL = ISNULL(@DQL,0)
	SET @CQL = ISNULL(@CQL,0)
	SET @IOPS = ISNULL(@IOPS,0)
	SET @PLE = ISNULL(@PLE,0)
	SET @CPUTime = ISNULL(@CPUTime,0)
	SET @UsedWorker = ISNULL(@UsedWorker,0)
	        
	SET NOCOUNT on

	DROP TABLE IF EXISTS #temp

	IF NOT EXISTS (SELECT 1 FROM dbWarden.sys.indexes WHERE object_id = OBJECT_ID('dbo.CounterData') AND name = 'IX_CounterData_CounterDateTime' )
		CREATE INDEX IX_CounterData_CounterDateTime ON dbWarden.dbo.CounterData (CounterDateTime) INCLUDE (CounterID, CounterValue)
	
	IF NOT EXISTS (SELECT 1 FROM dbwarden.sys.indexes WHERE object_id = OBJECT_ID('jv.CounterDataArchive') AND name = 'IX_CounterDataArchive_CounterDateTime' )
		CREATE INDEX IX_CounterDataArchive_CounterDateTime ON [dbWarden].[jv].CounterDataArchive (CounterDateTime) INCLUDE (CounterID, CounterValue)

	CREATE TABLE #temp (id INT IDENTITY PRIMARY KEY NOT NULL, date varchar(10))
	

	
	DECLARE @count INT = @DayCount
	WHILE @count>0
	begin
		INSERT #temp
		(
			date
		)
		VALUES
		(
			FORMAT(DATEADD(DAY,1-@count,@EndDate),'yyyy-MM-dd') -- date - varchar(10)
		)
		SET @count-=1
	END
	SET @EndDate=DATEADD(DAY,1,@EndDate)


	CREATE TABLE #CounterData (CounterDateTime datetime NOT null, CounterID int NOT NULL, CounterValue float(8) NOT null)
	INSERT #CounterData
	SELECT * from
		(SELECT LEFT(CounterDateTime,23) CounterDateTime,CounterID,CounterValue from [dbWarden].[dbo].[CounterData]) dt
	WHERE CounterDateTime BETWEEN @StartDate AND @EndDate AND convert(time,CounterDateTime) between @StartTime and @EndTime
	union all
	select * from [dbWarden].[jv].CounterDataArchive
	WHERE CounterDateTime BETWEEN @StartDate AND @EndDate AND convert(time,CounterDateTime) between @StartTime and @EndTime

	SELECT top 2160 CounterDateTime, CounterValue FROM #CounterData WHERE CounterID = 19 order by CounterDateTime --AND CounterValue<0.6;
	--SELECT * FROM dbWarden.[prf.cnt].ImportantCounter

	ALTER TABLE #CounterData ADD CONSTRAINT PK_CD PRIMARY KEY (CounterDateTime,CounterID)
-------------------------------------------------------------------------------------------	
	IF @DQL = 1
	BEGIN
		;with CounterData
		AS
		(
			SELECT * FROM #CounterData
		)
		, FinalData as
		(
		  SELECT t.date Date,
				dt1.Drive,
				dt1.[MIN Disk Queue Length],
				dt1.[AVG Disk Queue Length],
				dt1.[MAX Disk Queue Length]
				FROM
			(
			  SELECT 
				
				   CONVERT(DATE,counterdatetime) Date
				  ,right([ic].[CounterName],1) [Drive]
				  ,ROUND(MIN([CounterValue]),2) [MIN Disk Queue Length]		-- Who needs this?????
				  ,ROUND(AVG([CounterValue]),2) [AVG Disk Queue Length]
				  ,ROUND(MAX([CounterValue]),2) [MAX Disk Queue Length]
			  FROM 
			  CounterData cd
			  JOIN [dbWarden].[prf.cnt].ImportantCounter ic
			  ON ic.CounterID = cd.CounterID
			  where [ic].CounterID in (SELECT CounterID FROM [prf.cnt].ImportantCounter WHERE CounterName LIKE 'Disk Queue%')
										   										
			  group by [ic].[CounterName], CONVERT(DATE,counterdatetime)
			) dt1 JOIN #temp t
			ON t.date = dt1.Date
		)

		SELECT 
			dtD.Date,
			dtD.Drive Drive_D, dtD.[MIN Disk Queue Length] [MIN DQL_D], dtD.[AVG Disk Queue Length] [AVG DQL_D], dtD.[MAX Disk Queue Length] [MAX DQL_D],
			dtE.Drive Drive_E, dtE.[MIN Disk Queue Length] [MIN DQL_E], dtE.[AVG Disk Queue Length] [AVG DQL_E], dtE.[MAX Disk Queue Length] [MAX DQL_E],
			dtF.Drive Drive_F, dtF.[MIN Disk Queue Length] [MIN DQL_F], dtF.[AVG Disk Queue Length] [AVG DQL_F], dtF.[MAX Disk Queue Length] [MAX DQL_F],
			dtG.Drive Drive_G, dtG.[MIN Disk Queue Length] [MIN DQL_G], dtG.[AVG Disk Queue Length] [AVG DQL_G], dtG.[MAX Disk Queue Length] [MAX DQL_G],
			dtH.Drive Drive_H, dtH.[MIN Disk Queue Length] [MIN DQL_H], dtH.[AVG Disk Queue Length] [AVG DQL_H], dtH.[MAX Disk Queue Length] [MAX DQL_H]
		from
		(SELECT * FROM FinalData WHERE Drive = 'D') dtD LEFT JOIN
		(SELECT Date, Drive, [MIN Disk Queue Length], [AVG Disk Queue Length], [MAX Disk Queue Length] FROM FinalData WHERE Drive = 'E') dtE
		ON dtE.Date = dtD.Date LEFT join
		(SELECT Date, Drive, [MIN Disk Queue Length], [AVG Disk Queue Length], [MAX Disk Queue Length] FROM FinalData WHERE Drive = 'F') dtF
		ON dtF.Date = dtD.Date LEFT join
		(SELECT Date, Drive, [MIN Disk Queue Length], [AVG Disk Queue Length], [MAX Disk Queue Length] FROM FinalData WHERE Drive = 'G') dtG
		ON dtG.Date = dtD.Date LEFT join
		(SELECT Date, Drive, [MIN Disk Queue Length], [AVG Disk Queue Length], [MAX Disk Queue Length] FROM FinalData WHERE Drive = 'H') dtH
		ON dtH.Date = dtD.Date

		order by dtD.Date --MIN(CounterDateTime) desc
	END

-------------------------------------------------------------------------------------------

	IF @IOPS = 1
	BEGIN
		;with CounterData
		AS
		(
			SELECT * FROM #CounterData
		)
		, FinalData as
		(
		  SELECT t.date Date,
				dt1.Drive,
				dt1.[MIN IOPs],
				dt1.[AVG IOPs],
				dt1.[MAX IOPs]
				FROM
			(
			  SELECT 
				
				   CONVERT(DATE,counterdatetime) Date
				  ,right([ic].[CounterName],1) [Drive]
				  ,ROUND(MIN([CounterValue]),2) [MIN IOPs]		-- Who needs this?????
				  ,ROUND(AVG([CounterValue]),2) [AVG IOPs]
				  ,ROUND(MAX([CounterValue]),2) [MAX IOPs]
			  FROM 
			  CounterData cd
			  JOIN [dbWarden].[prf.cnt].ImportantCounter ic
			  ON ic.CounterID = cd.CounterID
			  where [ic].CounterID in (SELECT CounterID FROM [prf.cnt].ImportantCounter WHERE CounterName LIKE 'IOP%')
										   										
			  group by [ic].[CounterName], CONVERT(DATE,counterdatetime)
			) dt1 JOIN #temp t
			ON t.date = dt1.Date
		)

		SELECT 
			dtD.Date,
			dtD.Drive Drive_D, dtD.[MIN IOPs] [MIN IOPs_D], dtD.[AVG IOPs] [AVG IOPs_D], dtD.[MAX IOPs] [MAX IOPs_D],
			dtE.Drive Drive_E, dtE.[MIN IOPs] [MIN IOPs_E], dtE.[AVG IOPs] [AVG IOPs_E], dtE.[MAX IOPs] [MAX IOPs_E],
			dtF.Drive Drive_F, dtF.[MIN IOPs] [MIN IOPs_F], dtF.[AVG IOPs] [AVG IOPs_F], dtF.[MAX IOPs] [MAX IOPs_F],
			dtG.Drive Drive_G, dtG.[MIN IOPs] [MIN IOPs_G], dtG.[AVG IOPs] [AVG IOPs_G], dtG.[MAX IOPs] [MAX IOPs_G],
			dtH.Drive Drive_H, dtH.[MIN IOPs] [MIN IOPs_H], dtH.[AVG IOPs] [AVG IOPs_H], dtH.[MAX IOPs] [MAX IOPs_H]
		from
		(SELECT * FROM FinalData WHERE Drive = 'D') dtD LEFT JOIN
		(SELECT Date, Drive, [MIN IOPs], [AVG IOPs], [MAX IOPs] FROM FinalData WHERE Drive = 'E') dtE
		ON dtE.Date = dtD.Date LEFT join
		(SELECT Date, Drive, [MIN IOPs], [AVG IOPs], [MAX IOPs] FROM FinalData WHERE Drive = 'F') dtF
		ON dtF.Date = dtD.Date LEFT join
		(SELECT Date, Drive, [MIN IOPs], [AVG IOPs], [MAX IOPs] FROM FinalData WHERE Drive = 'G') dtG
		ON dtG.Date = dtD.Date LEFT join
		(SELECT Date, Drive, [MIN IOPs], [AVG IOPs], [MAX IOPs] FROM FinalData WHERE Drive = 'H') dtH
		ON dtH.Date = dtD.Date

		order by dtD.Date --MIN(CounterDateTime) desc
    
	END
-------------------------------------------------------------------------------------------
	IF @CPUTime = 1
	begin
		;with CounterData
		AS
		(
			SELECT * FROM #CounterData
		)
		, FinalData as
		(
		  SELECT t.date Date,
				dt1.[MIN CPU Time],
				dt1.[AVG CPU Time],
				dt1.[MAX CPU Time]
				FROM
			(
			  SELECT 
				
				   CONVERT(DATE, counterdatetime) Date
				  ,ROUND(MIN([CounterValue]),2) [MIN CPU Time]		-- Who needs this??????
				  ,ROUND(AVG([CounterValue]),2) [AVG CPU Time]
				  ,ROUND(MAX([CounterValue]),2) [MAX CPU Time]
			  FROM 
			  CounterData cd
			  JOIN [dbWarden].[prf.cnt].ImportantCounter ic
			  ON ic.CounterID = cd.CounterID
			  where [ic].CounterID = (SELECT CounterID FROM [prf.cnt].ImportantCounter WHERE CounterName = '% Processor Time' )
										   										
			  group by CONVERT(DATE, counterdatetime)
			) dt1 JOIN #temp t
			ON t.date = dt1.Date
		)

		SELECT 
			*
		FROM FinalData
		order by Date --MIN(CounterDateTime) desc
	END
-------------------------------------------------------------------------------------------
	IF @CQL = 1
	begin
		;with CounterData
		AS
		(
			SELECT * FROM #CounterData
		)
		, FinalData as
		(
		  SELECT t.date Date,
				dt1.[MIN CPU Queue Length],
				dt1.[AVG CPU Queue Length],
				dt1.[MAX CPU Queue Length]
				FROM
			(
			  SELECT 
				
				   CONVERT(DATE, counterdatetime) Date
				  ,ROUND(MIN([CounterValue]),2) [MIN CPU Queue Length]		-- Who needs this??????
				  ,ROUND(AVG([CounterValue]),2) [AVG CPU Queue Length]
				  ,ROUND(MAX([CounterValue]),2) [MAX CPU Queue Length]
			  FROM 
			  CounterData cd
			  JOIN [dbWarden].[prf.cnt].ImportantCounter ic
			  ON ic.CounterID = cd.CounterID
			  where [ic].CounterID = (SELECT CounterID FROM [prf.cnt].ImportantCounter WHERE CounterName = 'Processor Queue Length' )
										   										
			  group by CONVERT(DATE, counterdatetime)
			) dt1 JOIN #temp t
			ON t.date = dt1.Date
		)

		SELECT 
			*
		FROM FinalData
		order by Date --MIN(CounterDateTime) desc
	END
-------------------------------------------------------------------------------------------
	IF @PLE = 1
	begin
		;with CounterData
		AS
		(
			SELECT * FROM #CounterData
		)
		, FinalData as
		(
		  SELECT t.date Date,
				dt1.[MAX Page Life Expectancy],
				dt1.[AVG Page Life Expectancy],
				dt1.[MIN Page Life Expectancy]
				FROM
			(
			  SELECT 
				
				   CONVERT(DATE, counterdatetime) Date
				  ,MAX([CounterValue]) [MAX Page Life Expectancy]		-- Who needs this?????
				  ,ROUND(AVG([CounterValue]),2) [AVG Page Life Expectancy]
				  ,MIN([CounterValue]) [MIN Page Life Expectancy]
			  FROM 
			  CounterData cd
			  JOIN [dbWarden].[prf.cnt].ImportantCounter ic
			  ON ic.CounterID = cd.CounterID
			  where [ic].CounterID = (SELECT CounterID FROM [prf.cnt].ImportantCounter WHERE CounterName = 'Page life expectancy' )
										   										
			  group by CONVERT(DATE, counterdatetime)
			) dt1 JOIN #temp t
			ON t.date = dt1.Date
		)

		SELECT 
			*
		FROM FinalData
		order by Date --MIN(CounterDateTime) desc
	END
-------------------------------------------------------------------------------------------
	IF @UsedWorker = 1
	begin
		;with CounterData
		AS
		(
			SELECT * FROM jv.WorkerCountHistory
			WHERE DateStamp BETWEEN @StartDate AND @EndDate AND convert(time,DateStamp) between @StartTime and @EndTime
			UNION ALL
            SELECT * FROM jv.WorkerCountHistoryArchive
			WHERE DateStamp BETWEEN @StartDate AND @EndDate AND convert(time,DateStamp) between @StartTime and @EndTime
		)
		, FinalData as
		(
		  SELECT t.date Date,
				dt1.[MIN UsedWorker%],
				dt1.[AVG UsedWorker%],
				dt1.[MAX UsedWorker%]
				FROM
			(
			  SELECT 
				
				   CONVERT(DATE, DateStamp) Date
				  ,ROUND(MIN(WorkerCount*1.0/MaxWorkerCount)*100,2) [MIN UsedWorker%]		-- Who needs this?????
				  ,ROUND(AVG(WorkerCount*1.0/MaxWorkerCount)*100,2) [AVG UsedWorker%]
				  ,ROUND(MAX(WorkerCount*1.0/MaxWorkerCount)*100,2) [MAX UsedWorker%]
			  FROM 
			  CounterData 										   										
			  group by CONVERT(DATE, DateStamp)
			) dt1 JOIN #temp t
			ON t.date = dt1.Date
		)

		SELECT 
			*
		FROM FinalData
		order by Date --MIN(CounterDateTime) desc
	END
-------------------------------------------------------------------------------------------

	IF @LongRunnigQueries_DataOperationElements = 1
	begin
		;with ScriptData
		AS
		(
			SELECT DateStamp, LogicalReads, Reads, Writes FROM jv.LongRunningQuery
			WHERE DateStamp BETWEEN @StartDate AND @EndDate AND convert(time,DateStamp) between @StartTime and @EndTime
			UNION ALL
            SELECT DateStamp, LogicalReads, Reads, Writes FROM jv.LongRunningQueryArchive
			WHERE DateStamp BETWEEN @StartDate AND @EndDate AND convert(time,DateStamp) between @StartTime and @EndTime
		)
		, FinalData as
		(
		  SELECT
				
				t.date Date,
				dt1.[SUM Logical Read],
				dt1.[SUM Reads],
				IIF([dt1].[SUM Reads]=0,-1,dt1.[SUM Logical Read]*1.0/dt1.[SUM Reads]) [Logical Read/Reads Ratio],
				dt1.[SUM Writes]
				FROM
			(
			  SELECT 
				
				    CONVERT(DATE, DateStamp) Date				  
				  , SUM(ScriptData.LogicalReads) [SUM Logical Read]
				  , MAX(ScriptData.LogicalReads) [MAX Logical Read]
				  , SUM(ScriptData.Reads) [SUM Reads]
				  , MAX(ScriptData.Reads) [MAX Reads]
				  , SUM(ScriptData.Writes) [SUM Writes]
				  , MAX(ScriptData.Writes) [MAX Writes]
			  FROM 
			  ScriptData 										   										
			  group by CONVERT(DATE, DateStamp)
			) dt1 JOIN #temp t
			ON t.date = dt1.Date
		)

		SELECT 
			ROW_NUMBER() OVER (ORDER BY FinalData.[Logical Read/Reads Ratio] DESC) [order],
			*
		FROM FinalData
		order by [order]
	END
-------------------------------------------------------------------------------------------
	
END
GO

EXEC dbo.KPI_Stat_Report @StartDate = '2022-07-17', -- date
                         @EndDate = '2022-07-17',   -- date
                         @StartTime = '09:00:00',   -- time
                         @EndTime = '23:00:00',     -- time
						 @ntile = 0,				-- int
                         @DQL = 0,                  -- bit
                         @IOPS = 0,                 -- bit
                         @PLE = 0,                  -- bit
                         @CPUTime = 0,              -- bit
                         @CQL = 0,                  -- bit
                         @UsedWorker = 0,            -- bit
						 @LongRunnigQueries_DataOperationElements = 0


DROP PROC dbo.KPI_Stat_Report

