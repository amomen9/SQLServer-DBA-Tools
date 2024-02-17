USE master
GO
-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2024.01.23>
-- Description:			<MonitorServer_all (WhatIsActive)_Requests (lite)>
-- =============================================

-- For information please refer to the README.md

DROP FUNCTION IF EXISTS fn_udtvf_elapsedtime
DROP FUNCTION IF EXISTS fn_udtvf_monitorserver_all_lite
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




CREATE FUNCTION fn_udtvf_monitorserver_all_lite()
RETURNS TABLE
AS
RETURN
(
	WITH requests AS
	(
		SELECT CONVERT(VARCHAR(200),r.session_id) blocked, CONVERT(VARCHAR(200),r.blocking_session_id) blocker, REPLACE (t.text, CHAR(10), ' ') AS sql_text
		FROM sys.dm_exec_requests r
		CROSS APPLY sys.dm_exec_sql_text(r.SQL_HANDLE) t WHERE r.session_id<>@@SPID
	),
	blocking_sequence (blocked, blocker, sql_text, precedence)
	AS
	(
		SELECT 
			p.blocked, p.blocker, p.sql_text, p.blocked precedence
		FROM requests p
		WHERE blocker = 0
		AND EXISTS (SELECT 0 FROM requests pr WHERE pr.blocker = p.blocked AND pr.blocker <> pr.blocked)
		UNION ALL
		SELECT 
			p.blocked, p.blocker, p.sql_text, CONVERT(VARCHAR(200),precedence + ',' + p.blocked) precedence
		FROM requests p
		INNER JOIN blocking_sequence bs ON p.blocker = bs.blocked WHERE p.blocker > 0 AND p.blocker <> p.blocked
	)
	,
	hb1 AS
	(
		SELECT 
			LEFT(hb_precedence,CHARINDEX(',',hb_precedence)-1) head_blocker,
			dt.blocked,
			dt.sql_text
		FROM 
		(
			SELECT 
				bs.sql_text,
				blocked,
				blocker,
				(SELECT TOP 1 precedence FROM blocking_sequence bsi WHERE DATALENGTH(REPLACE(precedence,bs.blocked,''))<DATALENGTH(precedence) AND bsi.blocker<>0 ORDER BY LEN(bsi.precedence) DESC) AS hb_precedence,
				bs.precedence
			FROM blocking_sequence bs
			WHERE blocker<>0
		) dt
	),
	hb2 AS
    (
		SELECT hb1_1.head_blocker+CHAR(9)+'|'+CHAR(9)+ hb1_1.sql_text hb, hb1_1.blocked, hb1_2.count_blocked
		FROM hb1 hb1_1 JOIN (SELECT CONVERT(VARCHAR,COUNT(*)) count_blocked, hb1.head_blocker FROM hb1 GROUP BY hb1.head_blocker) hb1_2 
		ON hb1_1.head_blocker = hb1_2.head_blocker
	)
	SELECT TOP 100 PERCENT
			GETDATE() [Report Date]
		, r.session_id [Session ID]
		, et.[Elapsed DD:HH:MM:SS.ms]
		, r.cpu_time/1000.0 [request_cpu_time(s)]
		, r.STATUS [Status]
		, r.logical_reads [Logical Reads]
		, r.reads [Reads]
		, r.writes [Writes]
		--, (s.memory_usage * 8) [Memory Usage (KB)]
		, ISNULL(sh.text,rsh.text) [Most Recent Script Text]
		, SUBSTRING(sh.text, r.statement_start_offset / 2, (CASE WHEN r.statement_end_offset = -1 THEN DATALENGTH(sh.text) ELSE r.statement_end_offset END - r.statement_start_offset) / 2 ) AS fragment_executing
		, qp.query_plan [Live Plan]
		, database_transaction_log_bytes_used/1024.0/1024/1024 db_tran_log_used_gb
		, database_transaction_log_bytes_used_system/1024.0/1024/1024 db_sys_tran_log_used_gb
		
		--, s.cpu_time/1000.0 [session_cpu_time(s)]
		, DB_NAME(r.database_id) [Database Name]
		, s.original_login_name [Original Login Name]
		, s.nt_user_name [Windows/Domain Account Name]
		, s.HOST_NAME [Host Name Connected to Server]
		, s.program_name [Application Name]
		, s.login_name [Impersonated Login Name]
		, r.request_id
		, r.start_time request_start_time
		, dt.transaction_id
		, database_transaction_begin_time
		, database_transaction_log_bytes_reserved/1024.0/1024/1024 db_tran_log_resrv_gb
		--, DB_NAME(s.authenticating_database_id) [Authenticating Database Name]
		, IIF(s.program_name LIKE 'SQLAgent - TSQL JobStep (Job %',
				(SELECT NAME FROM msdb..sysjobs WHERE job_id=(SELECT CONVERT(VARCHAR(100),CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100), SUBSTRING(program_name,30,34),1))) FROM sys.dm_exec_sessions WHERE session_id=r.session_id))
				, NULL
				) [Job Name]
		, IIF(s.program_name LIKE 'SQLAgent - TSQL JobStep (Job %',
				(SELECT CONVERT(VARCHAR(100),CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100), SUBSTRING(program_name,30,34),1))) FROM sys.dm_exec_sessions WHERE session_id=r.session_id)
				, NULL
				) [Job id]			
		, IIF(s.program_name LIKE 'SQLAgent - TSQL JobStep (Job %',
				ISNULL((SELECT STRING_AGG(sch.NAME+':::'+IIF(sch.ENABLED=1,'enabled','disabled'),', ') job_schedule_name FROM msdb.dbo.sysjobschedules js JOIN msdb.dbo.sysschedules sch ON sch.schedule_id = js.schedule_id WHERE js.job_id = (SELECT CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100), SUBSTRING(program_name,30,34),1)) FROM sys.dm_exec_sessions WHERE session_id=r.session_id) GROUP BY js.job_id ), NULL)
				, NULL
				) [Job Schedule Name(s)]			
		, IIF(r.blocking_session_id<>0, 'Yes', 'No') [Is Being Blocked?]	
		, IIF(r.blocking_session_id<>0, r.blocking_session_id, NULL) [Session Blocking This Session]
		, IIF(r.blocking_session_id<>0, (SELECT '#'+count_blocked+' ::: '+hb.hb FROM hb2 hb WHERE hb.blocked=s.session_id), NULL) [#CountBlocked_HeadBlocker]
		, r.open_transaction_count [Open Transaction Count]
		, CONVERT(DECIMAL(14,3),r.cpu_time)*100.0/(NULLIF(CONVERT(DECIMAL(17,0),DATEDIFF_BIG(MILLISECOND,r.start_time,GETDATE())),0)/*-CONVERT(DECIMAL(14,3),r.wait_time)*/*(SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE STATUS = 'VISIBLE ONLINE')) [active average CPU Usage %]
		, r.granted_query_memory
		, qmg.granted_memory_kb
		, r.wait_type [Wait Type]
		, wt.[Elapsed DD:HH:MM:SS.ms] [Wait Time DD:HH:MM:SS.ms]
		, r.last_wait_type [Last Wait Type]
		, r.wait_resource [Wait Resource]
		, r.deadlock_priority
		, c.client_net_address [Client Address]
		, c.client_tcp_port [Client Outgoing Port]		
		, s.client_interface_name [Client Connection Driver]
		, IIF(c.net_transport='session', 'MARS', c.net_transport) [Client Connection Protocol]
		, e.name [Endpoint]
		, r.estimated_completion_time [Estimated Completion Time]
		, r.percent_complete [Percent Complete]
		, r.dop [Degree of Parallelism]
		, r.nest_level [Code Nest Level]
		, r.command [Command Type]
		, sh.text [Request Script Text]
		, r.row_count [Row Count]
		, s.is_user_process
		
	FROM
	sys.dm_exec_sessions s 
	JOIN sys.dm_exec_connections c
	ON s.session_id = c.session_id
	JOIN sys.dm_exec_requests r
	ON s.session_id = r.session_id
	LEFT JOIN sys.endpoints e
	ON s.endpoint_id = e.endpoint_id
	LEFT JOIN sys.dm_exec_query_memory_grants qmg
	ON r.session_id = qmg.session_id AND r.request_id = qmg.request_id
	LEFT JOIN sys.dm_tran_session_transactions st
	ON st.session_id = s.session_id
	LEFT JOIN sys.dm_tran_database_transactions dt
	ON dt.transaction_id = st.transaction_id
	OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) sh
	OUTER APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) rsh
	OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) qp
	OUTER APPLY fn_udtvf_elapsedtime(r.start_time) et
	OUTER APPLY fn_udtvf_elapsedtime(DATEADD(MILLISECOND,-r.wait_time,GETDATE())) wt
	WHERE 
	(sh.text IS NULL OR sh.text <> 'sp_server_diagnostics')
	AND s.session_id <> @@spid
	--AND COALESCE(r.wait_type,r.last_wait_type) NOT IN (N'BROKER_EVENTHANDLER', -- https://www.sqlskills.com/help/waits/BROKER_EVENTHANDLER
	--						N'BROKER_RECEIVE_WAITFOR', -- https://www.sqlskills.com/help/waits/BROKER_RECEIVE_WAITFOR
	--						N'BROKER_TASK_STOP', -- https://www.sqlskills.com/help/waits/BROKER_TASK_STOP
	--						N'BROKER_TO_FLUSH', -- https://www.sqlskills.com/help/waits/BROKER_TO_FLUSH
	--						N'BROKER_TRANSMITTER', -- https://www.sqlskills.com/help/waits/BROKER_TRANSMITTER
	--						N'CHECKPOINT_QUEUE', -- https://www.sqlskills.com/help/waits/CHECKPOINT_QUEUE
	--						N'CHKPT', -- https://www.sqlskills.com/help/waits/CHKPT
	--						N'CLR_AUTO_EVENT', -- https://www.sqlskills.com/help/waits/CLR_AUTO_EVENT
	--						N'CLR_MANUAL_EVENT', -- https://www.sqlskills.com/help/waits/CLR_MANUAL_EVENT
	--						N'CLR_SEMAPHORE') -- https://www.sqlskills.com/help/waits/CLR_SEMAPHORE
	ORDER BY [Elapsed DD:HH:MM:SS.ms] DESC
);
GO

SET STATISTICS TIME,IO on


SELECT * FROM fn_udtvf_monitorserver_all_lite()
WHERE is_user_process = 1 --AND [Session ID]=60
ORDER BY [request_cpu_time(s)] desc



