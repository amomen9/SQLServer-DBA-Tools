CREATE OR ALTER FUNCTION fn_udtvf_elapsedtime(@start_time DATETIME2(3))
RETURNS TABLE
AS
RETURN
(
	SELECT
		REPLICATE('0',2-LEN(DAYS))+DAYS+':'+
		REPLICATE('0',2-LEN(HOURS))+HOURS+':'+
		REPLICATE('0',2-LEN(MINUTES))+MINUTES+':'+
		REPLICATE('0',2-LEN(SECONDS))+SECONDS+':'+
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
        GETDATE() [current_time],
	DATEADD(MILLISECOND,R.estimated_completion_time,GETDATE()) estimated_end_datetime,
	R.wait_type,
	R.last_wait_type,
	ST.text [query_text]
FROM sys.dm_exec_requests R
CROSS APPLY sys.dm_exec_sql_text(R.sql_handle) ST
CROSS APPLY fn_udtvf_elapsedtime(R.start_time) et
CROSS APPLY fn_udtvf_elapsedtime(DATEADD(MILLISECOND,-R.estimated_completion_time,GETDATE())) rt
where estimated_completion_time<>0
