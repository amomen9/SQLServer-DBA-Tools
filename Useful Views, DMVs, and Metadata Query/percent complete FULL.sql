-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2024-02-04"
-- Description:         "percent complete FULL"
-- License:             "Please refer to the license file"
-- =============================================



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



SELECT 
	session_id,
	R.command,
	percent_complete,
	et.[Elapsed DD:HH:MM:SS.ms],
	rt.[Elapsed DD:HH:MM:SS.ms] estimated_remaining_time,
	R.wait_type,
	R.last_wait_type,
	wt.[Elapsed DD:HH:MM:SS.ms] wait_time,
	R.wait_time*100.0/R.total_elapsed_time [wait ratio],
	DATEADD(MILLISECOND,R.estimated_completion_time,GETDATE()) estimated_end_time,
	SUBSTRING(ST.text, R.statement_start_offset / 2, (CASE WHEN R.statement_end_offset = -1 THEN DATALENGTH(ST.text) ELSE R.statement_end_offset END - R.statement_start_offset) / 2 ) AS statement_executing,
	DB_NAME(database_id) DBName
FROM sys.dm_exec_requests R
CROSS APPLY sys.dm_exec_sql_text(R.sql_handle) ST
CROSS APPLY fn_udtvf_elapsedtime(R.start_time) et
CROSS APPLY fn_udtvf_elapsedtime(DATEADD(MILLISECOND,-R.estimated_completion_time,GETDATE())) rt
CROSS APPLY fn_udtvf_elapsedtime(DATEADD(MILLISECOND,-R.wait_time,GETDATE())) wt
where estimated_completion_time<>0



--SELECT R.session_id,
--       ST.text,
--       R.percent_complete,
--       DATEADD(s, 100 / ((R.percent_complete) / (R.total_elapsed_time / 1000)), R.start_time) estim_completion_time,
--       R.total_elapsed_time / 1000 AS elapsed_secs,
--       R.wait_type,
--       R.wait_time,
--       R.last_wait_type,
--       SUBSTRING(   ST.text,
--                    R.statement_start_offset / 2,
--                    (CASE
--                         WHEN R.statement_end_offset = -1 THEN
--                             DATALENGTH(ST.text)
--                         ELSE
--                             R.statement_end_offset
--                     END - R.statement_start_offset
--                    ) / 2
--                ) AS statement_executing
--FROM sys.dm_exec_requests R
--    CROSS APPLY sys.dm_exec_sql_text(R.sql_handle) ST
--WHERE R.percent_complete > 0
--      AND R.session_id <> @@spid
--OPTION (RECOMPILE);