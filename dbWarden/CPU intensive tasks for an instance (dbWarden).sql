
;WITH dt AS
(
	SELECT
	DBName,
	HostName,
	ProgramName,
	LoginName
	,SUM(CPUTime) [SUM CPUTime]
	,Job_Name_Step = CASE WHEN ProgramName LIKE 'SQLAgent - TSQL JobStep%' THEN 
		'Job: '+ j.name + 
			SUBSTRING(ProgramName,64,(CHARINDEX(')',ProgramName)-64)) ELSE NULL end
	FROM
	(
		SELECT * FROM
		(
			SELECT * FROM [dbWarden].[jv].[LongRunningQuery]			
			UNION ALL
			SELECT * FROM [dbWarden].[jv].[LongRunningQueryArchive]
		) dt
		WHERE DATEDIFF(DAY,DateStamp,GETDATE())<1 AND CONVERT(TIME,StartTime) BETWEEN '08:00:00' AND '20:00:00'
	) dt
	left JOIN msdb..sysjobs j
	ON j.job_id = CASE WHEN dt.ProgramName LIKE 'SQLAgent - TSQL JobStep%' then CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100),SUBSTRING(dt.ProgramName,30,34),1)) ELSE NULL end
	GROUP BY DBName,
	HostName,
	ProgramName,
	LoginName,
	j.name
)

SELECT dt2.LoginName, SUM(dt2.[SUM CPUTime in Seconds]) [SUM CPUTime in Seconds], SUM(dt2.[CPU Time Percentage%]) [CPU Time Percentage%] from
(
SELECT 
ISNULL(CASE WHEN dt.ProgramName LIKE 'SQLAgent%' THEN IIF(dt.ProgramName<>'SQLAgent - Job Manager',dt.Job_Name_Step,'SQLAgent - Job Manager') ELSE dt.ProgramName END, 'The job removed.') [Program/Job Name],
dt.LoginName,
SUM([SUM CPUTime]) [SUM CPUTime in Seconds],
SUM([SUM CPUTime])*100.0/(SELECT SUM([SUM CPUTime]) FROM dt) [CPU Time Percentage%] 
FROM
 dt

GROUP BY 
	CASE WHEN dt.ProgramName LIKE 'SQLAgent%' THEN IIF(dt.ProgramName<>'SQLAgent - Job Manager',dt.Job_Name_Step,'SQLAgent - Job Manager') ELSE dt.ProgramName END
	, dt.LoginName
) dt2
GROUP BY dt2.LoginName
ORDER BY [SUM CPUTime in Seconds] desc




;WITH dt AS
(
	SELECT
	DBName,
	HostName,
	ProgramName,
	LoginName
	,SUM(CPUTime) [SUM CPUTime]
	,Job_Name_Step = CASE WHEN ProgramName LIKE 'SQLAgent - TSQL JobStep%' THEN 
		'Job: '+ j.name + 
			SUBSTRING(ProgramName,64,(CHARINDEX(')',ProgramName)-64)) ELSE NULL end
	FROM
	(
		SELECT * FROM
		(
			SELECT * FROM [dbWarden].[jv].[LongRunningQuery]			
			UNION ALL
			SELECT * FROM [dbWarden].[jv].[LongRunningQueryArchive]
		) dt
		WHERE DATEDIFF(DAY,DateStamp,GETDATE())<1 AND CONVERT(TIME,StartTime) BETWEEN '08:00:00' AND '20:00:00'
	) dt
	left JOIN msdb..sysjobs j
	ON j.job_id = CASE WHEN dt.ProgramName LIKE 'SQLAgent - TSQL JobStep%' then CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100),SUBSTRING(dt.ProgramName,30,34),1)) ELSE NULL end
	GROUP BY DBName,
	HostName,
	ProgramName,
	LoginName,
	j.name
)

SELECT dt2.[Program/Job Name],dt2.LoginName, SUM(dt2.[SUM CPUTime in Seconds]) [SUM CPUTime in Seconds], SUM(dt2.[CPU Time Percentage%]) [CPU Time Percentage%] from
(
SELECT 
ISNULL(CASE WHEN dt.ProgramName LIKE 'SQLAgent%' THEN IIF(dt.ProgramName<>'SQLAgent - Job Manager',dt.Job_Name_Step,'SQLAgent - Job Manager') ELSE dt.ProgramName END, 'The job removed.') [Program/Job Name],
dt.LoginName,
SUM([SUM CPUTime]) [SUM CPUTime in Seconds],
SUM([SUM CPUTime])*100.0/(SELECT SUM([SUM CPUTime]) FROM dt) [CPU Time Percentage%] 
FROM
 dt
GROUP BY 
	CASE WHEN dt.ProgramName LIKE 'SQLAgent%' THEN IIF(dt.ProgramName<>'SQLAgent - Job Manager',dt.Job_Name_Step,'SQLAgent - Job Manager') ELSE dt.ProgramName END
	, dt.LoginName
	
) dt2
GROUP BY [Program/Job Name],dt2.LoginName
ORDER BY [SUM CPUTime in Seconds] desc
