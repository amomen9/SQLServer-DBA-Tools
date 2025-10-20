﻿use msdb
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


CREATE OR ALTER FUNCTION fn_udtvf_elapsedtime(@start_time DATETIME2(3))
RETURNS TABLE
AS
RETURN
(
	SELECT
		REPLICATE('0',2-LEN(DAYS))+DAYS+':'+
		REPLICATE('0',2-LEN(HOURS))+HOURS+':'+
		REPLICATE('0',2-LEN(MINUTES))+MINUTES+':'+
		REPLICATE('0',2-LEN(SECONDS))+SECONDS+'.'+
		REPLICATE('0',3-LEN(MILLISECONDS))+MILLISECONDS [Elapsed DD:HH:MM:SS.ms]
	FROM
	(
		SELECT
			CONVERT(VARCHAR(2),HOURS / 24) [DAYS],
			CONVERT(VARCHAR(2),HOURS % 24) [HOURS],
			CONVERT(VARCHAR(2),MINUTES) [MINUTES],
			CONVERT(VARCHAR(2),SECONDS) [SECONDS],
			CONVERT(VARCHAR(3),MILLISECONDS) [MILLISECONDS]
		FROM
		(
			SELECT 
				MINUTES / 60 [HOURS],
				[MINUTES] % 60 [MINUTES],
				[SECONDS],
				MILLISECONDS
			FROM 
			(
				SELECT		
					SECONDS / 60 [MINUTES],
					SECONDS % 60 [SECONDS],
					MILLISECONDS
				FROM
				(
					SELECT
					diff/1000 [SECONDS],
					diff % 1000 [MILLISECONDS]
					from
					(
						select 	DATEDIFF_BIG(MILLISECOND,@start_time,SYSDATETIME()) [diff]
					) dt
				) dt
			) dt
		) dt
	) dt
);
GO


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
		select p.name [Login Name],p2.name [Member of] 
		FROM sys.server_principals p join sys.server_role_members m on p.principal_id = m.member_principal_id join sys.server_principals p2 on m.role_principal_id = p2.principal_id
	)		
	, cte AS
	(	
		SELECT TOP 10000000
			ROW_NUMBER() OVER (ORDER BY dt.Job_Name, dt.schedule_id, dt.step_id) [global step id],
			ISNULL(CONNECTIONPROPERTY('local_net_address'),'localhost') as [Server IP],
			@@servername as ServerName,
			Job_Name,
			dt.step_id,
			js2.step_name,
			[Job&Sched_enabled],	
			isnull(STUFF(STUFF(STUFF(RIGHT(REPLICATE('0', 8) + CAST(((dt.AverageInSeconds % 60) + ((AverageInSeconds/60)%60)*100 + (dt.AverageInSeconds/3600)*10000) AS VARCHAR(8)), 8), 3, 0, ':'), 6, 0, ':'), 9, 0, ':')+'                    ','No Successful Run Duration Data') 'AVG_Run_Duration (DD:HH:MM:SS)',
			js2.command,
			[MAX_Run_Duration (DD:HH:MM:SS)],
			(SELECT ISNULL(STUFF(STUFF(STUFF(RIGHT(REPLICATE('0', 8) + CAST(MAX(run_duration) AS VARCHAR(8)), 8), 3, 0, ':'), 6, 0, ':'), 9, 0, ':')+'                    ','No Successful Run Duration Data') FROM msdb..SYSJOBHISTORY WHERE instance_id=dt.[Last Instance ID]) 'Last_Run_Duration (DD:HH:MM:SS)',
			Schedule,
			OwnerName,
			[OwnerServerRole(s)],
			dt.job_id
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
				
			LEFT join msdb..sysjobschedules s on j.job_id = s.job_id
		
			left join msdb..ufn_jobsinfo() info on j.name = info.Job_Name
			JOIN login_roles lr ON SUSER_SNAME(j.owner_sid) = lr.[Login Name]
					GROUP BY j.name,j.owner_sid, info.Job_Enabled,info.Schedule_Enabled, info.Frequency,info.Interday_Frequency, [lr].[Member of], jsh.step_id, j.start_step_id, j.job_id, info.schedule_id
		) dt LEFT join dbo.sysjobsteps js2
		ON js2.job_id = dt.job_id AND js2.step_id = dt.step_id
		ORDER BY [global step id]
	)
	SELECT TOP 10000000
		c1.ServerName [Server Name],
		c1.[Job_Name]+IIF(c1.step_id=0,' (Total)','') [Job Name],
		IIF(c1.step_id=0,'0_job', convert(varchar(10),c1.step_id)) [job/step_id],
		c1.step_name [Step Name],
		CASE WHEN ej.step_id=c1.step_id THEN ej.[Elapsed DD:HH:MM:SS.ms] WHEN ej.step_id IS NOT NULL THEN 'Job In Progress' ELSE 'Job Not Running' END [Elapsed Time], 
		c1.[Job&Sched_enabled] [Job&Sched IsEnabled],
		[Command],
		[Last_Run_Duration (DD:HH:MM:SS)],
		[AVG_Run_Duration (DD:HH:MM:SS)],
		[MAX_Run_Duration (DD:HH:MM:SS)],
		[Schedule],
		c1.OwnerName [Owner Name],
		c1.[OwnerServerRole(s)] [Owner Server Role(s)]
	FROM cte c1 
	LEFT JOIN
				(
					SELECT 
						s.session_id
						, (SELECT CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100), SUBSTRING(program_name,30,34),1)) FROM sys.dm_exec_sessions WHERE session_id=s.session_id) job_id
						, (SELECT REPLACE(SUBSTRING(program_name,71,34),')','') FROM sys.dm_exec_sessions WHERE session_id = s.session_id) step_id
						, et.[Elapsed DD:HH:MM:SS.ms]					
					FROM
					sys.dm_exec_sessions s 
					OUTER APPLY fn_udtvf_elapsedtime(s.last_request_start_time) et
					WHERE program_name LIKE 'SQLAgent - TSQL JobStep (Job %'
				) ej
	ON c1.job_id = ej.job_id
	ORDER BY c1.[global step id]
GO



SELECT * FROM msdb.dbo.v_view_jobs

DROP view v_view_jobs
GO
	
----------------- run times ordered by duration for a specific job descending:
--SELECT 	
--		STUFF(STUFF(RIGHT(REPLICATE('0', 8) + CAST(run_date as varchar(8)), 8), 5, 0, '_'), 8, 0, '_')+'  '+RIGHT(STUFF(STUFF(STUFF(RIGHT(REPLICATE('0', 8)+CAST(run_time as varchar(8)), 8), 3, 0, ':'), 6, 0, ':'), 9, 0, ':'),8) 'Run DATETIME',
--		j.name as Job_Name,
--		isnull(STUFF(STUFF(STUFF(RIGHT(REPLICATE('0', 8) + CAST(run_duration as varchar(8)), 8), 3, 0, ':'), 6, 0, ':'), 9, 0, ':')+'         ','No Run Duration Data') 'Run_Duration (DD:HH:MM:SS)'
--FROM msdb..SYSJOBS j
--	left JOIN msdb..SYSJOBHISTORY h  on h.job_id = j.job_id and h.step_id = 0
--	left join msdb..sysjobschedules s on j.job_id = s.job_id
--	left join msdb..ufn_jobsinfo() info on j.name = info.Job_Name
--	WHERE j.name LIKE 'Nightly Jobs' 
--ORDER BY h.run_duration DESC,
--		 h.run_date desc, h.run_time DESC



--SELECT * FROM msdb.dbo.sysjobs WHERE job_id='9D5F0176-E973-4BA6-B79A-8A62989E9FA6' 


