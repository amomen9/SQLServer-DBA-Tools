DROP FUNCTION IF EXISTS fn_udtvf_elapsedtime
GO

CREATE FUNCTION fn_udtvf_elapsedtime(@start_time DATETIME2(3))
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
	r.session_id,
	r.command,
	DB_NAME(r.database_id) DBName,
	percent_complete,
	et.[Elapsed DD:HH:MM:SS.ms],
	rt.[Elapsed DD:HH:MM:SS.ms] estimated_remaining_time,
	r.wait_type,
	r.last_wait_type,
	wt.[Elapsed DD:HH:MM:SS.ms] wait_time,
	r.wait_time*100.0/r.total_elapsed_time [wait/elapsed ratio],
	DATEADD(MILLISECOND,r.estimated_completion_time,GETDATE()) estimated_end_time,
	SUBSTRING(ST.text, r.statement_start_offset / 2, (CASE WHEN r.statement_end_offset = -1 THEN DATALENGTH(ST.text) ELSE r.statement_end_offset END - r.statement_start_offset) / 2 ) AS [statement_executing (fragment)],
	s.original_login_name
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) ST
CROSS APPLY fn_udtvf_elapsedtime(r.start_time) et
CROSS APPLY fn_udtvf_elapsedtime(DATEADD(MILLISECOND,-r.estimated_completion_time,GETDATE())) rt
CROSS APPLY fn_udtvf_elapsedtime(DATEADD(MILLISECOND,-r.wait_time,GETDATE())) wt
where estimated_completion_time<>0


