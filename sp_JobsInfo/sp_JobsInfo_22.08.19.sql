-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2021.08.19>
-- Description:			<Jobs Info>
-- =============================================

-- For information please refer to the README.md





use master
go

CREATE OR ALTER FUNCTION fn_bigint2datetime(@datetimeint bigint)
RETURNS CHAR(19)
WITH 
--inline=ON,
SCHEMABINDING,
RETURNS NULL ON NULL INPUT
AS
BEGIN
	RETURN STUFF(STUFF(STUFF(STUFF(STUFF(CONVERT(CHAR(14),@datetimeint),5,0,'-'),8,0,'-'),11,0,' '),14,0,':'),17,0,':')
END
GO

CREATE or alter FUNCTION fn_Int2TimeString (@time INT) -- This function has been taken from the following URL written by Alan Jefferson:

RETURNS VARCHAR(20)
WITH 
--inline = ON,
SCHEMABINDING,
RETURNS NULL ON NULL INPUT
AS
BEGIN
    DECLARE @return VARCHAR(20);
    SET @return = '';
    IF @time IS NOT NULL
       AND @time >= 0
       AND @time < 240000
        SELECT
            @return
            = REPLACE( CONVERT(VARCHAR(20), CONVERT(TIME, LEFT(RIGHT('000000'
                     + CONVERT(VARCHAR(6), @time), 6), 2)
                     + ':'
                     + SUBSTRING(RIGHT('000000' + CONVERT(VARCHAR(6), @time), 6), 3, 2) + ':'
                     + RIGHT('00' + CONVERT(VARCHAR(6), @time), 2)),109),'.0000000',' '
 );
    RETURN @return;
END;
go

--------------------------------------------------------------------------------------------

create or alter function ufn_jobsinfo() -- The body of this function has been taken from the following URL written by Alan Jefferson
-- with minor changes:
-- https://www.sqlservercentral.com/articles/how-to-decipher-sysschedules

returns @result TABLE
(
	Server_Name nvarchar(128),
    Job_Name nvarchar(128),
    Job_Enabled tinyint,
    Schedule_Name nvarchar(128),
	Schedule_Id INT,
    Schedule_Enabled int,
    Frequency varchar(500),
    Interday_Frequency varchar(500),
    active_start_date datetime,
    active_start_time varchar(20),
    active_end_date datetime,
    active_end_time varchar(20)
)

as
begin
		DECLARE @daysOfWeek TABLE
		(
		[dayNumber]   TINYINT,
		[dayCode]     TINYINT,
		[dayName]  VARCHAR(11)
		)
		INSERT INTO
			  @daysOfWeek
			  (
			  [dayNumber],
			  [dayCode],
		  [dayName]
			  )
		VALUES
			  (1,1, 'Sunday'),
			  (2,2, 'Monday'),
			  (3,4, 'Tuesday'),
			  (4,8, 'Wednesday'),
			  (5,16, 'Thursday'),
			  (6,32, 'Friday'),
			  (7,64, 'Saturday');
		DECLARE @daysOfWeek_relative TABLE
		(
		[dayNumber] INT,
		[dayCode]   INT,
		[dayText] VARCHAR(250)
		)
		INSERT INTO
			  @daysOfWeek_relative
			  (
			  [dayNumber],
			  [dayCode],
			  [dayText]
			  )
		VALUES
			  (1,1, 'On the <<wk>> Sunday of every <<n>> Month(s)'),
			  (2,2, 'On the <<wk>> Monday of every <<n>> Month(s)'),
			  (3,3, 'On the <<wk>> Tuesday of every <<n>> Month(s)'),
			  (4,4, 'On the <<wk>> Wednesday of every <<n>> Month(s)'),
			  (5,5, 'On the <<wk>> Thursday of every <<n>> Month(s)'),
			  (6,6, 'On the <<wk>> Friday of every <<n>> Month(s)'),
			  (7,7, 'On the <<wk>> Saturday of every <<n>> Month(s)'),
			  (8,8, 'Each Day of the <<wk>> week of every <<n>> Month(s)'),
			  (9,9, 'Each Weekday of the <<wk>> week of every <<n>> Month(s)'),
			  (10,10, 'Each Weekend Day of the <<wk>> week of every <<n>> Month(s)');
		DECLARE @weeksOfMonth TABLE
		(
		[womNumber]   TINYINT,
		[womCode]     TINYINT,
		[womName]  VARCHAR(11)
		)
		INSERT INTO
			  @weeksOfMonth
			  (
			  [womNumber],
			  [womCode],
			  [womName]
			  )
		VALUES
		(1, 1, 'First'),
		(2, 2, 'Second'),
		(3, 4, 'Third'),
		(4, 8, 'Fourth'),
		(5, 16, 'Last');
		DECLARE @Ordinal TABLE
		(OrdinalID int,
		OrdinalCode int,
		OrdinalName varchar(20))
		insert into @Ordinal (OrdinalID, OrdinalCode, OrdinalName)
		values
		(1,1,'1st'),
		(2,2,'2nd'),
		(3,3,'3rd'),
		(4,4,'4th'),
		(5,5,'5th'),
		(6,6,'6th'),
		(7,7,'7th'),
		(8,8,'8th'),
		(9,9,'9th'),
		(10,10,'10th'),
		(11,11,'11th'),
		(12,12,'12th'),
		(13,13,'13th'),
		(14,14,'14th'),
		(15,15,'15th'),
		(16,16,'16th'),
		(17,17,'17th'),
		(18,18,'18th'),
		(19,19,'19th'),
		(20,20,'20th'),
		(21,21,'21st'),
		(22,22,'22nd'),
		(23,23,'23rd'),
		(24,24,'24th'),
		(25,25,'25th'),
		(26,26,'26th'),
		(27,27,'27th'),
		(28,28,'28th'),
		(29,29,'29th'),
		(30,30,'30th'),
		(31,31,'31st');
		;WITH CTE_DOW
		AS (SELECT DISTINCT
				schedule_id,
				Days_of_Week = CONVERT(VARCHAR(250), STUFF(
										  (
											  SELECT ', ' + DOW.dayName
											  FROM @daysOfWeek DOW
											  WHERE
												  ss.freq_interval & DOW.dayCode = DOW.dayCode
											  FOR XML PATH('')
										  ), 1, 2, '')
									  )
			FROM msdb.dbo.sysschedules ss
		   ),
		CTE_WOM
		AS (SELECT DISTINCT
				schedule_id,
				Weeks_of_Month = CONVERT(VARCHAR(250), STUFF(
											(
												SELECT ', ' + WOM.womName
												FROM @WeeksOfMonth WOM
												WHERE
													ss.freq_relative_interval
													& WOM.womCode = WOM.womCode
												FOR XML PATH('')
											), 1, 2, '')
										)
			FROM msdb.dbo.sysschedules ss
		   )
		insert into @result
			SELECT
				Server_Name = @@ServerName,	-- 0
				Job_Name = sj.name, -- 1
				Job_Enabled = sj.enabled, -- 1
				Schedule_Name = ss.name, -- 0
				sjs.schedule_id, -- 1
				Schedule_Enabled = ss.enabled, -- 1
				[Frequency Description] = CONVERT(VARCHAR(500), CASE freq_type	
			WHEN 1 THEN 'One Time Only'
			WHEN 4 THEN 'Every ' + case ss.freq_interval when 1 then 'Day' else CONVERT(VARCHAR(10),ss.freq_interval) + ' Day(s)' end
			WHEN 8 THEN 'Every ' + ISNULL(DOW.Days_of_Week, '')
			+ ' of every '
			+ CASE ss.freq_recurrence_factor WHEN 1 THEN 'Week.' else CONVERT(VARCHAR(3), ss.freq_recurrence_factor ) + ' Week(s).' end
			WHEN 16 THEN 'On the ' + ISNULL(od.OrdinalName, '') 
					+ ' day of every '
			+ CASE ss.freq_recurrence_factor WHEN 1 THEN 'Month.' ELSE CONVERT(VARCHAR(3), ss.freq_recurrence_factor ) + ' Month(s).' end
			WHEN 32 THEN REPLACE(REPLACE(DOWR.dayText, '<<wk>>', ISNULL(WOM.Weeks_of_Month,'')),'<<n>>',
														  CONVERT(VARCHAR(3), ss.freq_recurrence_factor))
													WHEN 64 THEN 'When SQL Server Starts'
			WHEN 128 THEN 'WHEN SQL Server is Idle'
			ELSE '' 
									   END
								   ),	-- Frequency 1
				 CONVERT(VARCHAR(500), CASE 
			WHEN freq_type NOT IN ( 64, 128 ) THEN
														CASE freq_subday_type
												WHEN 0 THEN ' at '
															WHEN 1 THEN 'Once at '
															WHEN 2 THEN 'Every ' + case ss.freq_subday_interval when 1 then 'Second starting at ' else CONVERT(VARCHAR(10),ss.freq_subday_interval) + ' Second(s) starting at ' end
		
			WHEN 4 THEN 'Every ' + case ss.freq_subday_interval when 1 then 'Minute starting at ' else CONVERT(VARCHAR(10),ss.freq_subday_interval) + ' Minute(s) starting at ' end
															
										WHEN 8 THEN 'Every '+ case ss.freq_subday_interval when 1 then 'Hour starting at ' else CONVERT(VARCHAR(10),ss.freq_subday_interval) + ' Hour(s) starting at ' end
															
										ELSE ''
														END
														+ dbo.fn_Int2TimeString(active_start_time)
														+ CASE
															  WHEN ss.freq_subday_type IN ( 2, 4, 8) THEN ' Ending at '
																  + dbo.fn_Int2TimeString(active_end_time)
															  ELSE ''
														  END
													ELSE ''
												END
											),	--Interday_Frequency 1
				active_start_date = CONVERT(DATETIME, CONVERT( VARCHAR(8), ss.active_start_date, 114 )),
				active_start_time = dbo.fn_Int2TimeString(active_start_time),
				active_end_date = CONVERT(DATETIME, CONVERT(VARCHAR(8), ss.active_end_date, 114)),
				active_end_time = dbo.fn_Int2TimeString(active_end_time)
			FROM
				msdb.dbo.sysjobs sj WITH (NOLOCK)
				JOIN msdb.dbo.sysjobschedules sjs
					ON sj.job_id = sjs.job_id
				JOIN msdb.dbo.sysschedules ss
					ON sjs.schedule_id = ss.schedule_id
				LEFT JOIN CTE_DOW DOW
					ON ss.schedule_id = DOW.schedule_id
				LEFT JOIN CTE_WOM WOM
					ON ss.schedule_id = WOM.schedule_id
				LEFT JOIN @Ordinal od
					ON ss.freq_interval = od.OrdinalCode
				LEFT JOIN @Ordinal om
					ON ss.freq_recurrence_factor = om.OrdinalCode
				LEFT JOIN @daysOfWeek_relative DOWR
					ON ss.freq_interval = DOWR.dayCode;
				
		RETURN 
END 
GO

--========= Main SP: ================================================================

CREATE OR ALTER PROC usp_JobsInfo
	@Start_DATETIME DATETIME = '1980-01-01 00:00:00',
	@End_DATETIME DATETIME = '2200-01-01 00:00:00',
	@Start_Time TIME = '00:00:00',
	@End_Time TIME = '23:59:59',
	@Only_Show_Entries_With_History_Data BIT = 0
AS
BEGIN

	SET @Start_DATETIME = IIF(@Start_DATETIME IS NULL OR @Start_DATETIME = '', '1980-01-01 00:00:00', @Start_DATETIME)
	SET @End_DATETIME = IIF(@End_DATETIME IS NULL OR @End_DATETIME = '', '2200-01-01 00:00:00', @End_DATETIME)

	SET @Start_TIME = IIF(@Start_TIME IS NULL OR @Start_Time = '', '00:00:00', @Start_Time)
	SET @End_TIME = IIF(@End_TIME IS NULL OR @End_Time = '', '23:59:59', @End_Time)

	DECLARE @Start_TIME_INT INT = DATEPART(HOUR,@Start_TIME)*10000+DATEPART(MINUTE,@Start_TIME)*100+DATEPART(SECOND,@Start_TIME)
	DECLARE @End_TIME_INT INT = DATEPART(HOUR,@End_TIME)*10000+DATEPART(MINUTE,@End_TIME)*100+DATEPART(SECOND,@End_TIME)

	SET @Only_Show_Entries_With_History_Data = ISNULL(@Only_Show_Entries_With_History_Data,0)

	DECLARE   @StartDatetime bigint = CONVERT(bigINT,REPLACE(CONVERT(VARCHAR(10),LEFT(CONVERT(date,@Start_DATETIME),10)),'-','')+REPLACE(CONVERT(VARCHAR(8),LEFT(CONVERT(TIME,@Start_DATETIME),8)),':',''))
			, @EndDatetime bigINT = CONVERT(bigINT,REPLACE(CONVERT(VARCHAR(10),LEFT(CONVERT(date,@End_DATETIME),10)),'-','')+REPLACE(CONVERT(VARCHAR(8),LEFT(CONVERT(TIME,@End_DATETIME),8)),':',''))
	
	CREATE TABLE #sysjobsteps
	(
		job_id uniqueidentifier,
		step_id int,
		step_uid UNIQUEIDENTIFIER,
		step_name nvarchar(128),
	)
	INSERT #sysjobsteps
	(
		job_id,
		step_id,
		step_uid,
		step_name
	)
	SELECT sj.job_id, dt.step_id, dt.step_uid, dt.step_name FROM
	(
		SELECT job_id,step_id,step_uid,step_name FROM msdb..sysjobsteps
		UNION ALL
		SELECT DISTINCT job_id,0,job_id,'(Job outcome)' FROM msdb..sysjobsteps	
	) dt RIGHT JOIN
	msdb..sysjobs sj
	ON sj.job_id = dt.job_id

	CREATE CLUSTERED INDEX CS_IX_sysjobsteps ON #sysjobsteps (job_id,step_id)
	;WITH login_roles
	AS
	(
		select p.name [Login Name],STRING_AGG(p2.name,', ') [Member of] 
		FROM sys.server_principals p WITH (NOLOCK) join sys.server_role_members m on p.principal_id = m.member_principal_id join sys.server_principals p2 on m.role_principal_id = p2.principal_id
		GROUP BY p.name
	)
	, cte2
	AS
	(
		SELECT * FROM
        (
			SELECT 
				h.run_duration,
				SuccussfulRun_duration = IIF(h.run_status=1, run_duration, NULL),		
				js.job_id,
				h.instance_id,
				js.step_id,
				js.step_name,
				js.step_uid,				
				h.run_status,
				(CONVERT(BIGINT,h.run_date)*1000000+h.run_time) [Run Datetime]
					
				FROM #sysjobsteps js WITH (NOLOCK) left JOIN msdb..sysjobhistory h WITH (NOLOCK)
				ON  js.job_id =h.job_id AND				
				js.step_id = h.step_id AND 
				(CONVERT(BIGINT,h.run_date)*1000000+h.run_time) BETWEEN @StartDatetime AND @EndDatetime AND
                h.run_time BETWEEN @Start_TIME_INT AND @End_TIME_INT
				where
                ISNULL(h.run_duration,'') = CASE @Only_Show_Entries_With_History_Data WHEN 0 THEN ISNULL(h.run_duration,'') ELSE h.run_duration END
				
		) dt		
		
	)
	
	SELECT
	
		ISNULL(CONNECTIONPROPERTY('local_net_address'),'localhost') as [Server IP],
		@@servername as ServerName,
		Job_Name+' '+IIF(dt.step_id=0,'(Total)','') [Job Name],
		ISNULL(dt.Schedule_Name,'No Schedule') [Schedule Name]
		,dt.step_id,
		dt.step_name [Step Name],
		[Job&Sched_enabled],	
		IIF([Total Runs]<>0,CONVERT(VARCHAR(6),CONVERT(DECIMAL(5,2),[dt].[Successfull First Runs]*100.0/[dt].[Total Runs])),'No run data in history') [Successful Run Percentage],
		isnull(STUFF(STUFF(STUFF(RIGHT(REPLICATE('0', 8) + CAST(((dt.AverageInSeconds % 60) + ((AverageInSeconds/60)%60)*100 + (dt.AverageInSeconds/3600)*10000) as varchar(8)), 8), 3, 0, ':'), 6, 0, ':'), 9, 0, ':')+'         ','No Run Duration Data') 'AVG_Successfull_Run_Duration (DD:HH:MM:SS)',
		[MAX_Successfull_Run_Duration (DD:HH:MM:SS)],
		(SELECT ISNULL(STUFF(STUFF(STUFF(RIGHT(REPLICATE('0', 8) + CAST(max(run_duration) as varchar(8)), 8), 3, 0, ':'), 6, 0, ':'), 9, 0, ':')+'         ','No Run Duration Data') FROM msdb..SYSJOBHISTORY WHERE instance_id=dt.[Last Instance ID] AND run_status=1) 'Last_Successfull_Run_Duration (DD:HH:MM:SS)',
		Schedule,
		OwnerName,
		[dt].[OwnerServerRole(s) (Aggregated)],		
		[dt].[First Job/Step Start_Date (Within Boundry)],
		[dt].[Last Job/Step Start_Date (Within Boundry)],
		[dt].[Is currently running?]
		FROM
		(
			SELECT
			j.name as Job_Name,
			jsh.step_id,
			jsh.step_name,
			info.Schedule_Name,
			info.Schedule_Id,
			[Job&Sched_enabled] = isnull(convert(nvarchar(20), info.Job_Enabled*info.Schedule_Enabled),'On Demand Only'),
			AVG((jsh.SuccussfulRun_duration/10000)*3600+((jsh.SuccussfulRun_duration/100)%100)*60+jsh.SuccussfulRun_duration%100) AverageInSeconds,
			isnull(STUFF(STUFF(STUFF(RIGHT(REPLICATE('0', 8) + CAST(max(SuccussfulRun_duration) as varchar(8)), 8), 3, 0, ':'), 6, 0, ':'), 9, 0, ':')+'         ','No Run Duration Data') 'MAX_Successfull_Run_Duration (DD:HH:MM:SS)',
			isnull(REPLACE(info.Frequency+' '+info.Interday_Frequency,'Every Day Every','Every'),'On Demand Only') as Schedule,
			SUSER_SNAME(j.owner_sid) as OwnerName,
			[lr].[Member of] AS [OwnerServerRole(s) (Aggregated)],
			CASE		
				WHEN CHARINDEX(binary_job_id,(SELECT STRING_AGG(program_name,'') FROM sys.dm_exec_sessions WHERE program_name LIKE ('%'+binary_job_id+'%') )) <> 0 AND step_id = 0
					THEN 1
				WHEN CHARINDEX(binary_job_id,(SELECT STRING_AGG(program_name,'') FROM sys.dm_exec_sessions WHERE program_name LIKE ('%'+binary_job_id+' : Step '+CONVERT(VARCHAR(3),step_id)+')%') )) <> 0
					THEN 1
				ELSE 0
			END [Is currently running?]

			, MAX(jsh.instance_id) [Last Instance ID]
			, MIN([Successfull First Runs]) [Successfull First Runs]						-- aggregated to prevent group by clause
			, MIN([Total Runs]) [Total Runs]												-- aggregated to prevent group by clause
			, MIN([jsh].[First Job/Step StartDate]) [First Job/Step Start_Date (Within Boundry)]	-- aggregated to prevent group by clause
			, MAX(jsh.[Last Job/Step StartDate]) [Last Job/Step Start_Date (Within Boundry)]		-- aggregated to prevent group by clause
			FROM msdb..SYSJOBS j WITH (NOLOCK)
			JOIN 
					( 
						SELECT WithoutAggregate.*,[WithAggregate].[Successfull First Runs], [Total Runs], [First Job/Step StartDate], [Last Job/Step StartDate], CONVERT(VARCHAR(34),CONVERT(VARBINARY(100),job_id),1) binary_job_id  FROM cte2 WithoutAggregate
						JOIN 
						(
							SELECT
									  cte2.step_uid,
									  count(IIF(run_status = 1, step_uid, NULL)) [Successfull First Runs]
									, COUNT(run_status) [Total Runs]
									, dbo.fn_bigint2datetime(MIN(cte2.[Run Datetime])) [First Job/Step StartDate]
									, dbo.fn_bigint2datetime(MAX(cte2.[Run Datetime])) [Last Job/Step StartDate]
							FROM cte2 WITH (NOLOCK)
							GROUP BY cte2.step_uid
						) WithAggregate
						ON WithAggregate.step_uid = WithoutAggregate.step_uid
					 ) jsh 
			ON jsh.job_id = j.job_id
			LEFT join msdb..sysjobschedules s 
			ON j.job_id = s.job_id
			left join ufn_jobsinfo() info 
			ON j.name = info.Job_Name
			JOIN login_roles lr 
			ON SUSER_SNAME(j.owner_sid) = lr.[Login Name]
			GROUP BY j.name,
					 j.owner_sid,
					 info.Job_Enabled,
					 info.Schedule_Enabled,
					 info.Frequency,
					 info.Schedule_Name,
					 info.Interday_Frequency,
					 [lr].[Member of],
					 jsh.step_id,
					 info.Schedule_Id,
					 jsh.step_name,
					 binary_job_id
		) dt
		
		ORDER BY dt.Job_Name, [Schedule Name], dt.step_id --dt.Job_Name

END
GO
-------------------------------------------------------------------------

EXEC usp_JobsInfo 
					@Start_DATETIME = '',	--'2022-02-15 00:00:00',
					@End_DATETIME = '',		--'2022-03-01 00:00:00',
					@Start_Time = '',		--'00:00:00',
					@End_Time = '',			--'23:59:59',
					@Only_Show_Entries_With_History_Data = 1


EXEC dbo.usp_JobsInfo 



GO
DROP PROC dbo.usp_JobsInfo
GO
DROP FUNCTION dbo.fn_bigint2datetime
GO
DROP FUNCTION dbo.ufn_jobsinfo
GO
DROP FUNCTION dbo.fn_Int2TimeString
GO

--DECLARE @1 DATETIME2 = SYSDATETIME()
--WAITFOR DELAY '00:02:06'
--PRINT (DATEDIFF(MILLISECOND,@1,SYSDATETIME()))

