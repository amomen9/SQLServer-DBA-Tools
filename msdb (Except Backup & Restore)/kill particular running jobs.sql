-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2023-12-20"
-- Description:         "kill particular running jobs"
-- License:             "Please refer to the license file"
-- =============================================



-------------------------- Using kill
DECLARE @SQL NVARCHAR(max)

SELECT @SQL= STRING_AGG('KILL '+dt.session_id+'; --JobName: '+dt.[Job Name],CHAR(10))
FROM
(
	SELECT
		CONVERT(VARCHAR,s.session_id) session_id,
		(SELECT name FROM msdb..sysjobs WHERE job_id=(SELECT CONVERT(VARCHAR(100),CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100), SUBSTRING(program_name,30,34),1))) FROM sys.dm_exec_sessions WHERE session_id=s.session_id)) [Job Name]
	FROM
	sys.dm_exec_sessions s 
	WHERE s.program_name LIKE 'SQLAgent - TSQL JobStep (Job %'
) dt
WHERE dt.[Job Name] LIKE '%IndexOptimize%' OR dt.[Job Name] LIKE '%UpdateStatistics%'

PRINT @SQL
EXEC(@SQL)

-------------------------- Using sp_stop_job

DECLARE @SQL NVARCHAR(max)

SELECT @SQL= STRING_AGG('exec msdb.dbo.sp_stop_job @job_name='''+dt.[Job Name]+'''',CHAR(10))
FROM
(
	SELECT
		CONVERT(VARCHAR,s.session_id) session_id,
		(SELECT name FROM msdb..sysjobs WHERE job_id=(SELECT CONVERT(VARCHAR(100),CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100), SUBSTRING(program_name,30,34),1))) FROM sys.dm_exec_sessions WHERE session_id=s.session_id)) [Job Name]
	FROM
	sys.dm_exec_sessions s 
	WHERE s.program_name LIKE 'SQLAgent - TSQL JobStep (Job %'
) dt
WHERE dt.[Job Name] LIKE '%IndexOptimize%' OR dt.[Job Name] LIKE '%UpdateStatistics%'

PRINT @SQL
EXEC(@SQL)


