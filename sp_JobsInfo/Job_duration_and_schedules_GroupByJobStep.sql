use msdb
go

CREATE or alter FUNCTION fn_IntToTimeString (@time INT) -- This function has been taken from the following URL written by Alan Jefferson:
-- https://www.sqlservercentral.com/articles/how-to-decipher-sysschedules

RETURNS VARCHAR(20)
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

use msdb
go

create or alter function ufn_jobsinfo() 
returns @result TABLE
(
	Server_Name nvarchar(128),
    Job_Name nvarchar(128),
    Job_Enabled tinyint,
	Schedule_Id INT,
    Schedule_Name nvarchar(128),
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
			Server_Name = @@ServerName,
			Job_Name = sj.name,
			Job_Enabled = sj.enabled,
			schedule_id = ss.schedule_id,
		    Schedule_Name = ss.name,
		    Schedule_Enabled = ss.enabled,
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
							   ),
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
													+ dbo.fn_IntToTimeString(active_start_time)
													+ CASE
														  WHEN ss.freq_subday_type IN ( 2, 4, 8) THEN ' Ending at '
															  + dbo.fn_IntToTimeString(active_end_time)
														  ELSE ''
													  END
												ELSE ''
											END
										),
		    active_start_date = CONVERT(DATETIME, CONVERT( VARCHAR(8), ss.active_start_date, 114 )),
		    active_start_time = dbo.fn_IntToTimeString(active_start_time),
		    active_end_date = CONVERT(DATETIME, CONVERT(VARCHAR(8), ss.active_end_date, 114)),
		    active_end_time = dbo.fn_IntToTimeString(active_end_time)
		FROM
			msdb.dbo.sysjobs sj
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
		return
end
go






------- ******************************************************************** --------

CREATE OR ALTER VIEW v_view_jobs
AS

	WITH login_roles
	AS
	(
		SELECT p.name [Login Name],p2.name [Member of] 
		FROM sys.server_principals p JOIN sys.server_role_members m ON p.principal_id = m.member_principal_id JOIN sys.server_principals p2 ON m.role_principal_id = p2.principal_id
	)		
	, cte AS
	(	
		SELECT TOP 10000000
			ROW_NUMBER() OVER (ORDER BY dt.Job_Name, dt.schedule_id, dt.step_id) [global step id],
			ISNULL(CONNECTIONPROPERTY('local_net_address'),'localhost') AS [Server IP],
			@@servername AS ServerName,
			Job_Name,
			dt.step_id,
			js2.step_name,
			[Job&Sched_enabled],	
			ISNULL(STUFF(STUFF(STUFF(RIGHT(REPLICATE('0', 8) + CAST(((dt.AverageInSeconds % 60) + ((AverageInSeconds/60)%60)*100 + (dt.AverageInSeconds/3600)*10000) AS VARCHAR(8)), 8), 3, 0, ':'), 6, 0, ':'), 9, 0, ':')+'                    ','No Successful Run Duration Data') 'AVG_Run_Duration (DD:HH:MM:SS)',
			js2.command,
			[MAX_Run_Duration (DD:HH:MM:SS)],
			(SELECT ISNULL(STUFF(STUFF(STUFF(RIGHT(REPLICATE('0', 8) + CAST(MAX(run_duration) AS VARCHAR(8)), 8), 3, 0, ':'), 6, 0, ':'), 9, 0, ':')+'                    ','No Successful Run Duration Data') FROM msdb..SYSJOBHISTORY WHERE instance_id=dt.[Last Instance ID]) 'Last_Run_Duration (DD:HH:MM:SS)',
			Schedule,
			OwnerName,
			[OwnerServerRole(s)]
		FROM
		(
			SELECT
				j.name AS Job_Name
				, jsh.step_id
				, ISNULL(CONVERT(NVARCHAR(20), info.Job_Enabled*info.Schedule_Enabled),'On Demand Only') [Job&Sched_enabled]
				, AVG((jsh.run_duration/10000)*3600+((jsh.run_duration/100)%100)*60+jsh.run_duration%100) AverageInSeconds
				, ISNULL(STUFF(STUFF(STUFF(RIGHT(REPLICATE('0', 8) + CAST(MAX(run_duration) AS VARCHAR(8)), 8), 3, 0, ':'), 6, 0, ':'), 9, 0, ':')+'                    ','No Successful Run Duration Data') 'MAX_Run_Duration (DD:HH:MM:SS)'
				, ISNULL(REPLACE(info.Frequency+' '+info.Interday_Frequency,'Every Day Every','Every'),'On Demand Only') AS Schedule
				, SUSER_SNAME(j.owner_sid) AS OwnerName
				, [lr].[Member of] AS [OwnerServerRole(s)]
				, MIN(jsh.job_id) job_id
				, MAX(jsh.instance_id) [Last Instance ID]
				, (SELECT name FROM dbo.sysjobsteps WHERE step_id =j.start_step_id AND job_id=j.job_id) [Starting Step]
				, info.schedule_id
			FROM msdb..SYSJOBS j

			LEFT JOIN 
					( 
						SELECT 
							h.run_duration,
							ISNULL(h.job_id,js.job_id) job_id,
							h.instance_id,
							ISNULL(h.step_id,js.step_id) step_id						
						 FROM (SELECT job_id, step_id FROM sysjobsteps UNION ALL SELECT DISTINCT job_id, 0 FROM dbo.sysjobsteps) js FULL JOIN msdb..sysjobhistory h
						 ON h.job_id = js.job_id AND h.step_id = js.step_id AND h.run_status = 1
					 				 					 
					 ) jsh ON jsh.job_id = j.job_id
				
			LEFT JOIN msdb..sysjobschedules s ON j.job_id = s.job_id
		
			LEFT JOIN msdb..ufn_jobsinfo() info ON j.name = info.Job_Name
			JOIN login_roles lr ON SUSER_SNAME(j.owner_sid) = lr.[Login Name]
					GROUP BY j.name,j.owner_sid, info.Job_Enabled,info.Schedule_Enabled, info.Frequency,info.Interday_Frequency, [lr].[Member of], jsh.step_id, j.start_step_id, j.job_id, info.schedule_id
		) dt LEFT JOIN dbo.sysjobsteps js2
		ON js2.job_id = dt.job_id AND js2.step_id = dt.step_id
		ORDER BY [global step id]
	)
	SELECT TOP 10000000
		[ServerName], c1.[Job_Name]+IIF(step_id=0,' (Total)','') Job_Name, IIF(step_id=0,'0_job', CONVERT(VARCHAR(10),step_id)) [job/step_id], c1.step_name, [Job&Sched_enabled], [command], [AVG_Run_Duration (DD:HH:MM:SS)], [MAX_Run_Duration (DD:HH:MM:SS)], [Last_Run_Duration (DD:HH:MM:SS)], [Schedule], c1.OwnerName, c1.[OwnerServerRole(s)] 
	FROM cte c1
	ORDER BY c1.[global step id]
GO


SELECT * FROM msdb.dbo.v_view_jobs 

DROP VIEW v_view_jobs
GO
	


