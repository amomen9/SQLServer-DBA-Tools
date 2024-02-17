USE master
GO
-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2024.01.23>
-- Description:			<monitorserver_waits (WhatIsActive)_Sessions>
-- =============================================

-- For information please refer to the README.md

DROP FUNCTION IF EXISTS fn_udtvf_elapsedtime
DROP FUNCTION IF EXISTS fn_udtvf_monitorserver_waits
DROP FUNCTION IF EXISTS fn_udtvf_waitexceptions
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



CREATE FUNCTION fn_udtvf_waitexceptions
(	
	@HADR_waits BIT = 1,
	@Parallelism_waits BIT = 1,
	@Mirroring_waits BIT = 1,
	@AG_waits BIT = 1,
	@blocking_waits BIT = 1
)
RETURNS @wait_types TABLE ( wait_group VARCHAR(20) NOT NULL, spec_wait VARCHAR(60) NOT NULL, PRIMARY KEY(wait_group,spec_wait)) 
AS
BEGIN
	INSERT @wait_types
	SELECT wait_group, spec_wait
	FROM
	(
		SELECT
			-- These wait types are almost 100% never a problem and so they are
			-- filtered out to avoid them skewing the results. Click on the URL
			-- for more information.
			   'useless' wait_group, N'BROKER_EVENTHANDLER' spec_wait -- https://www.sqlskills.com/help/waits/BROKER_EVENTHANDLER
		UNION ALL
		SELECT 'useless', N'BROKER_RECEIVE_WAITFOR' -- https://www.sqlskills.com/help/waits/BROKER_RECEIVE_WAITFOR
		UNION ALL
		SELECT 'useless', N'BROKER_TASK_STOP' -- https://www.sqlskills.com/help/waits/BROKER_TASK_STOP
		UNION ALL
		SELECT 'useless', N'BROKER_TO_FLUSH' -- https://www.sqlskills.com/help/waits/BROKER_TO_FLUSH
		UNION ALL
		SELECT 'useless', N'BROKER_TRANSMITTER' -- https://www.sqlskills.com/help/waits/BROKER_TRANSMITTER
		UNION ALL
		SELECT 'useless', N'CHECKPOINT_QUEUE' -- https://www.sqlskills.com/help/waits/CHECKPOINT_QUEUE
		UNION ALL
		SELECT 'useless', N'CHKPT' -- https://www.sqlskills.com/help/waits/CHKPT
		UNION ALL
		SELECT 'useless', N'CLR_AUTO_EVENT' -- https://www.sqlskills.com/help/waits/CLR_AUTO_EVENT
		UNION ALL
		SELECT 'useless', N'CLR_MANUAL_EVENT' -- https://www.sqlskills.com/help/waits/CLR_MANUAL_EVENT
		UNION ALL
		SELECT 'useless', N'CLR_SEMAPHORE' -- https://www.sqlskills.com/help/waits/CLR_SEMAPHORE
		UNION ALL

		-- parallelism issues
		SELECT 'parallelism', N'CXCONSUMER' -- https://www.sqlskills.com/help/waits/CXCONSUMER
		UNION ALL

		-- mirroring issues
		SELECT 'mirroring', N'DBMIRROR_DBM_EVENT' -- https://www.sqlskills.com/help/waits/DBMIRROR_DBM_EVENT
		UNION ALL
		SELECT 'mirroring', N'DBMIRROR_EVENTS_QUEUE' -- https://www.sqlskills.com/help/waits/DBMIRROR_EVENTS_QUEUE
		UNION ALL
		SELECT 'mirroring', N'DBMIRROR_WORKER_QUEUE' -- https://www.sqlskills.com/help/waits/DBMIRROR_WORKER_QUEUE
		UNION ALL
		SELECT 'mirroring', N'DBMIRRORING_CMD' -- https://www.sqlskills.com/help/waits/DBMIRRORING_CMD
		UNION ALL
		SELECT 'mirroring', N'DIRTY_PAGE_POLL' -- https://www.sqlskills.com/help/waits/DIRTY_PAGE_POLL
		UNION ALL
		SELECT 'mirroring', N'DISPATCHER_QUEUE_SEMAPHORE' -- https://www.sqlskills.com/help/waits/DISPATCHER_QUEUE_SEMAPHORE
		UNION ALL
		SELECT 'mirroring', N'EXECSYNC' -- https://www.sqlskills.com/help/waits/EXECSYNC
		UNION ALL
		SELECT 'mirroring', N'FSAGENT' -- https://www.sqlskills.com/help/waits/FSAGENT
		UNION ALL
		SELECT 'mirroring', N'FT_IFTS_SCHEDULER_IDLE_WAIT' -- https://www.sqlskills.com/help/waits/FT_IFTS_SCHEDULER_IDLE_WAIT
		UNION ALL
		SELECT 'mirroring', N'FT_IFTSHC_MUTEX' -- https://www.sqlskills.com/help/waits/FT_IFTSHC_MUTEX
		UNION ALL
			
		-- AG issues
		SELECT 'AG', N'HADR_CLUSAPI_CALL' -- https://www.sqlskills.com/help/waits/HADR_CLUSAPI_CALL
		UNION ALL
		SELECT 'AG', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION' -- https://www.sqlskills.com/help/waits/HADR_FILESTREAM_IOMGR_IOCOMPLETION
		UNION ALL
		SELECT 'AG', N'HADR_LOGCAPTURE_WAIT' -- https://www.sqlskills.com/help/waits/HADR_LOGCAPTURE_WAIT
		UNION ALL
		SELECT 'AG', N'HADR_NOTIFICATION_DEQUEUE' -- https://www.sqlskills.com/help/waits/HADR_NOTIFICATION_DEQUEUE
		UNION ALL
		SELECT 'AG', N'HADR_TIMER_TASK' -- https://www.sqlskills.com/help/waits/HADR_TIMER_TASK
		UNION ALL
		SELECT 'AG', N'HADR_WORK_QUEUE' -- https://www.sqlskills.com/help/waits/HADR_WORK_QUEUE
		UNION ALL
		SELECT 'AG', N'KSOURCE_WAKEUP' -- https://www.sqlskills.com/help/waits/KSOURCE_WAKEUP
		UNION ALL
		SELECT 'AG', N'LAZYWRITER_SLEEP' -- https://www.sqlskills.com/help/waits/LAZYWRITER_SLEEP
		UNION ALL
		SELECT 'AG', N'LOGMGR_QUEUE' -- https://www.sqlskills.com/help/waits/LOGMGR_QUEUE
		UNION ALL
		SELECT 'AG', N'MEMORY_ALLOCATION_EXT' -- https://www.sqlskills.com/help/waits/MEMORY_ALLOCATION_EXT
		UNION ALL
		SELECT 'AG', N'ONDEMAND_TASK_QUEUE' -- https://www.sqlskills.com/help/waits/ONDEMAND_TASK_QUEUE
		UNION ALL
		SELECT 'AG', N'PARALLEL_REDO_DRAIN_WORKER' -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_DRAIN_WORKER
		UNION ALL
		SELECT 'AG', N'PARALLEL_REDO_LOG_CACHE' -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_LOG_CACHE
		UNION ALL
		SELECT 'AG', N'PARALLEL_REDO_TRAN_LIST' -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_TRAN_LIST
		UNION ALL
		SELECT 'AG', N'PARALLEL_REDO_WORKER_SYNC' -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_WORKER_SYNC
		UNION ALL
		SELECT 'AG', N'PARALLEL_REDO_WORKER_WAIT_WORK' -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_WORKER_WAIT_WORK
		UNION ALL
		SELECT 'AG', N'PREEMPTIVE_OS_FLUSHFILEBUFFERS' -- https://www.sqlskills.com/help/waits/PREEMPTIVE_OS_FLUSHFILEBUFFERS
		UNION ALL
		SELECT 'AG', N'PREEMPTIVE_XE_GETTARGETSTATE' -- https://www.sqlskills.com/help/waits/PREEMPTIVE_XE_GETTARGETSTATE
		UNION ALL
		SELECT 'AG', N'PVS_PREALLOCATE' -- https://www.sqlskills.com/help/waits/PVS_PREALLOCATE
		UNION ALL
		SELECT 'AG', N'PWAIT_ALL_COMPONENTS_INITIALIZED' -- https://www.sqlskills.com/help/waits/PWAIT_ALL_COMPONENTS_INITIALIZED
		UNION ALL
		SELECT 'AG', N'PWAIT_DIRECTLOGCONSUMER_GETNEXT' -- https://www.sqlskills.com/help/waits/PWAIT_DIRECTLOGCONSUMER_GETNEXT
		UNION ALL
		SELECT 'AG', N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP' -- https://www.sqlskills.com/help/waits/QDS_PERSIST_TASK_MAIN_LOOP_SLEEP
		UNION ALL
		SELECT 'AG', N'QDS_ASYNC_QUEUE' -- https://www.sqlskills.com/help/waits/QDS_ASYNC_QUEUE
		UNION ALL
		SELECT 'AG', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP' -- https://www.sqlskills.com/help/waits/QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP
		UNION ALL
		SELECT 'AG', N'QDS_SHUTDOWN_QUEUE' -- https://www.sqlskills.com/help/waits/QDS_SHUTDOWN_QUEUE
		UNION ALL
		SELECT 'AG', N'REDO_THREAD_PENDING_WORK' -- https://www.sqlskills.com/help/waits/REDO_THREAD_PENDING_WORK
		UNION ALL
		SELECT 'AG', N'REQUEST_FOR_DEADLOCK_SEARCH' -- https://www.sqlskills.com/help/waits/REQUEST_FOR_DEADLOCK_SEARCH
		UNION ALL
		SELECT 'AG', N'RESOURCE_QUEUE' -- https://www.sqlskills.com/help/waits/RESOURCE_QUEUE
		UNION ALL
		SELECT 'AG', N'SERVER_IDLE_CHECK' -- https://www.sqlskills.com/help/waits/SERVER_IDLE_CHECK
		UNION ALL
		SELECT 'AG', N'SLEEP_BPOOL_FLUSH' -- https://www.sqlskills.com/help/waits/SLEEP_BPOOL_FLUSH
		UNION ALL
		SELECT 'AG', N'SLEEP_DBSTARTUP' -- https://www.sqlskills.com/help/waits/SLEEP_DBSTARTUP
		UNION ALL
		SELECT 'AG', N'SLEEP_DCOMSTARTUP' -- https://www.sqlskills.com/help/waits/SLEEP_DCOMSTARTUP
		UNION ALL
		SELECT 'AG', N'SLEEP_MASTERDBREADY' -- https://www.sqlskills.com/help/waits/SLEEP_MASTERDBREADY
		UNION ALL
		SELECT 'AG', N'SLEEP_MASTERMDREADY' -- https://www.sqlskills.com/help/waits/SLEEP_MASTERMDREADY
		UNION ALL
		SELECT 'AG', N'SLEEP_MASTERUPGRADED' -- https://www.sqlskills.com/help/waits/SLEEP_MASTERUPGRADED
		UNION ALL
		SELECT 'AG', N'SLEEP_MSDBSTARTUP' -- https://www.sqlskills.com/help/waits/SLEEP_MSDBSTARTUP
		UNION ALL
		SELECT 'AG', N'SLEEP_SYSTEMTASK' -- https://www.sqlskills.com/help/waits/SLEEP_SYSTEMTASK
		UNION ALL
		SELECT 'AG', N'SLEEP_TASK' -- https://www.sqlskills.com/help/waits/SLEEP_TASK
		UNION ALL
		SELECT 'AG', N'SLEEP_TEMPDBSTARTUP' -- https://www.sqlskills.com/help/waits/SLEEP_TEMPDBSTARTUP
		UNION ALL
		SELECT 'AG', N'SNI_HTTP_ACCEPT' -- https://www.sqlskills.com/help/waits/SNI_HTTP_ACCEPT
		UNION ALL
		SELECT 'AG', N'SOS_WORK_DISPATCHER' -- https://www.sqlskills.com/help/waits/SOS_WORK_DISPATCHER
		UNION ALL
		SELECT 'AG', N'SP_SERVER_DIAGNOSTICS_SLEEP' -- https://www.sqlskills.com/help/waits/SP_SERVER_DIAGNOSTICS_SLEEP
		UNION ALL
		SELECT 'AG', N'SQLTRACE_BUFFER_FLUSH' -- https://www.sqlskills.com/help/waits/SQLTRACE_BUFFER_FLUSH
		UNION ALL
		SELECT 'AG', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP' -- https://www.sqlskills.com/help/waits/SQLTRACE_INCREMENTAL_FLUSH_SLEEP
		UNION ALL
		SELECT 'AG', N'SQLTRACE_WAIT_ENTRIES' -- https://www.sqlskills.com/help/waits/SQLTRACE_WAIT_ENTRIES
		UNION ALL
		SELECT 'AG', N'VDI_CLIENT_OTHER' -- https://www.sqlskills.com/help/waits/VDI_CLIENT_OTHER
		UNION ALL
		SELECT 'AG', N'WAIT_FOR_RESULTS' -- https://www.sqlskills.com/help/waits/WAIT_FOR_RESULTS
		UNION ALL
		SELECT 'AG', N'WAITFOR' -- https://www.sqlskills.com/help/waits/WAITFOR
		UNION ALL
		SELECT 'AG', N'WAITFOR_TASKSHUTDOWN' -- https://www.sqlskills.com/help/waits/WAITFOR_TASKSHUTDOWN
		UNION ALL
		SELECT 'AG', N'WAIT_XTP_RECOVERY' -- https://www.sqlskills.com/help/waits/WAIT_XTP_RECOVERY
		UNION ALL
		SELECT 'AG', N'WAIT_XTP_HOST_WAIT' -- https://www.sqlskills.com/help/waits/WAIT_XTP_HOST_WAIT
		UNION ALL
		SELECT 'AG', N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG' -- https://www.sqlskills.com/help/waits/WAIT_XTP_OFFLINE_CKPT_NEW_LOG
		UNION ALL
		SELECT 'AG', N'WAIT_XTP_CKPT_CLOSE' -- https://www.sqlskills.com/help/waits/WAIT_XTP_CKPT_CLOSE
		UNION ALL
		SELECT 'AG', N'XE_DISPATCHER_JOIN' -- https://www.sqlskills.com/help/waits/XE_DISPATCHER_JOIN
		UNION ALL
		SELECT 'AG', N'XE_DISPATCHER_WAIT' -- https://www.sqlskills.com/help/waits/XE_DISPATCHER_WAIT
		UNION ALL
		SELECT 'AG', N'XE_TIMER_EVENT' -- https://www.sqlskills.com/help/waits/XE_TIMER_EVENT
		UNION ALL

		-- bloking issues
		SELECT 'blocking','LCK_M_IX'
		UNION ALL
		SELECT 'blocking','LCK_M_IU'
		UNION ALL
		SELECT 'blocking','LCK_M_IS'
		UNION ALL
		SELECT 'blocking','LCK_M_X'
		UNION ALL
		SELECT 'blocking','LCK_M_UIX'
		UNION ALL
		SELECT 'blocking','LCK_M_U'
		UNION ALL
		SELECT 'blocking','LCK_M_SIX'
		UNION ALL
		SELECT 'blocking','LCK_M_SIU'
		UNION ALL
		SELECT 'blocking','LCK_M_SCH_S'
		UNION ALL
		SELECT 'blocking','LCK_M_SCH_M'
		UNION ALL
		SELECT 'blocking','LCK_M_S'
		UNION ALL
		SELECT 'blocking','LCK_M_RI_X'
		UNION ALL
		SELECT 'blocking','LCK_M_RI_U'
		UNION ALL
		SELECT 'blocking','LCK_M_RI_S'
		UNION ALL
		SELECT 'blocking','LCK_M_RI_NL'
		UNION ALL
		SELECT 'blocking','LCK_M_RX_X'
		UNION ALL
		SELECT 'blocking','LCK_M_RX_U'
		UNION ALL
		SELECT 'blocking','LCK_M_RX_S'
		UNION ALL
		SELECT 'blocking','LCK_M_RS_U'
		UNION ALL
		SELECT 'blocking','LCK_M_RS_S'
		UNION ALL
		SELECT 'blocking','LCK_M_BU'

	) dt
	WHERE wait_group IN (IIF(@HADR_waits=1,'AG',''), IIF(@Mirroring_waits=1,'mirroring',''), IIF(@Parallelism_waits=1,'parallelism',''), IIF(@Parallelism_waits=1,'blocking',''))
	RETURN
END
GO




CREATE FUNCTION fn_udtvf_monitorserver_waits
(
	@HADR_waits BIT = 1,
	@Parallelism_waits BIT = 1,
	@Mirroring_waits BIT = 1,
	@AG_waits BIT = 1,
	@blocking_waits BIT = 1
)
RETURNS TABLE
AS
RETURN
(
	WITH requests AS
	(
		SELECT CONVERT(varchar(200),r.session_id) blocked, CONVERT(varchar(200),r.blocking_session_id) blocker, REPLACE (t.text, CHAR(10), ' ') AS sql_text
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
				(SELECT TOP 1 precedence FROM blocking_sequence bsi WHERE DATALENGTH(REPLACE(precedence,bs.blocked,''))<DATALENGTH(precedence) AND bsi.blocker<>0 ORDER BY LEN(bsi.precedence) desc) AS hb_precedence,
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
		, s.session_id [Session ID]
		, et.[Elapsed DD:HH:MM:SS.ms]
		, r.wait_type [Wait Type]
		, wt.[Elapsed DD:HH:MM:SS.ms] [Wait Time DD:HH:MM:SS.ms]
		, r.last_wait_type [Last Wait Type]
		, r.wait_resource [Wait Resource]
		, IIF(r.blocking_session_id<>0, 'Yes', 'No') [Is Being Blocked?]	
		, IIF(r.blocking_session_id<>0, r.blocking_session_id, NULL) [Session Blocking This Session]
		, IIF(r.blocking_session_id<>0, (SELECT '#'+count_blocked+' ::: '+hb.hb FROM hb2 hb WHERE hb.blocked=s.session_id), NULL) [#CountBlocked_HeadBlocker]
		, r.cpu_time/1000.0 [request_cpu_time(s)]
		, s.STATUS [Status]
		, r.logical_reads [Logical Reads]
		, r.reads [Reads]
		, r.writes [Writes]
		, (s.memory_usage * 8) [Memory Usage (KB)]
		, ISNULL(sh.text,rsh.text) [Most Recent Script Text]
		, SUBSTRING(sh.text, r.statement_start_offset / 2, (CASE WHEN r.statement_end_offset = -1 THEN DATALENGTH(sh.text) ELSE r.statement_end_offset END - r.statement_start_offset) / 2 ) AS fragment_executing
		, qp.query_plan [Live Plan]
		, database_transaction_log_bytes_used/1024.0/1024/1024 db_tran_log_used_gb
		, database_transaction_log_bytes_used_system/1024.0/1024/1024 db_sys_tran_log_used_gb
		, s.cpu_time/1000.0 [session_cpu_time(s)]
		, DB_NAME(s.database_id) [Database Name]
		, s.original_login_name [Original Login Name]
		, s.nt_user_name [Windows/Domain Account Name]
		, s.HOST_NAME [Host Name Connected to Server]
		, s.program_name [Application Name]
		, s.login_name [Impersonated Login Name]
		--, r.request_id
		--, r.start_time request_start_time
		--, dt.transaction_id
		, database_transaction_begin_time
		, database_transaction_log_bytes_reserved/1024.0/1024/1024 db_tran_log_resrv_gb
		, DB_NAME(s.authenticating_database_id) [Authenticating Database Name]
		--, IIF(s.program_name LIKE 'SQLAgent - TSQL JobStep (Job %',
		--		(SELECT NAME FROM msdb..sysjobs WHERE job_id=(SELECT CONVERT(VARCHAR(100),CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100), SUBSTRING(program_name,30,34),1))) FROM sys.dm_exec_sessions WHERE session_id=s.session_id))
		--		, NULL
		--		) [Job Name]
		--, IIF(s.program_name LIKE 'SQLAgent - TSQL JobStep (Job %',
		--		(SELECT CONVERT(VARCHAR(100),CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100), SUBSTRING(program_name,30,34),1))) FROM sys.dm_exec_sessions WHERE session_id=s.session_id)
		--		, NULL
		--		) [Job id]			
		--, IIF(s.program_name LIKE 'SQLAgent - TSQL JobStep (Job %',
		--		ISNULL((SELECT STRING_AGG(sch.NAME+':::'+IIF(sch.ENABLED=1,'enabled','disabled'),', ') job_schedule_name FROM msdb.dbo.sysjobschedules js JOIN msdb.dbo.sysschedules sch ON sch.schedule_id = js.schedule_id WHERE js.job_id = (SELECT CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100), SUBSTRING(program_name,30,34),1)) FROM sys.dm_exec_sessions WHERE session_id=s.session_id) GROUP BY js.job_id ), NULL)
		--		, NULL
		--		) [Job Schedule Name(s)]			
		--, s.open_transaction_count [Open Transaction Count]
		--, CONVERT(DECIMAL(14,3),r.cpu_time)*100.0/(NULLIF(CONVERT(DECIMAL(17,0),DATEDIFF_BIG(MILLISECOND,r.start_time,GETDATE())),0)/*-CONVERT(DECIMAL(14,3),r.wait_time)*/*(SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE STATUS = 'VISIBLE ONLINE')) [active average CPU Usage %]
		--, r.granted_query_memory
		--, qmg.granted_memory_kb
		--, s.deadlock_priority [Deadlock Priority]
		--, c.client_net_address [Client Address]
		--, c.client_tcp_port [Client Outgoing Port]
		--, s.client_interface_name [Client Connection Driver]
		--, IIF(c.net_transport='session', 'MARS', c.net_transport) [Client Connection Protocol]
		--, e.name [Endpoint]
		--, r.estimated_completion_time [Estimated Completion Time]
		, r.percent_complete [Percent Complete]
		, r.dop [Degree of Parallelism]
		--, r.nest_level [Code Nest Level]
		, r.command [Command Type]
		--, sh.text [Request Script Text]
		--, r.plan_handle
		--, r.row_count [Row Count]
		, s.is_user_process
		
	FROM
	sys.dm_exec_sessions s 
	LEFT JOIN sys.dm_exec_connections c
	ON s.session_id = c.session_id
	LEFT JOIN sys.dm_exec_requests r
	ON s.session_id = r.session_id
	LEFT JOIN sys.endpoints e
	ON s.endpoint_id = e.endpoint_id
	LEFT JOIN sys.dm_exec_query_memory_grants qmg
	ON c.session_id = qmg.session_id AND qmg.request_id = r.request_id
	LEFT JOIN sys.dm_tran_session_transactions st
	ON st.session_id = s.session_id
	LEFT JOIN sys.dm_tran_database_transactions dt
	ON dt.transaction_id = st.transaction_id
	JOIN dbo.fn_udtvf_waitexceptions(@HADR_waits,@Parallelism_waits,@Mirroring_waits,@AG_waits,@blocking_waits) we
	ON ISNULL(r.wait_type,r.last_wait_type) = we.spec_wait
	OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) sh
	OUTER APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) rsh
	OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) qp
	OUTER APPLY fn_udtvf_elapsedtime(r.start_time) et
	OUTER APPLY fn_udtvf_elapsedtime(DATEADD(MILLISECOND,-r.wait_time,GETDATE())) wt
	WHERE 
		(rsh.text IS NULL OR rsh.text <> 'sp_server_diagnostics')
		AND s.session_id <> @@spid
	ORDER BY [Elapsed DD:HH:MM:SS.ms] DESC
);
GO

SET STATISTICS TIME,IO on


SELECT * FROM fn_udtvf_monitorserver_waits(1,1,1,1,1)
WHERE is_user_process = 1 --AND [Session ID]=60
--ORDER BY [request_cpu_time(s)] desc




--SELECT * FROM fn_udtvf_waitexceptions(1,1,1,1)


--ALTER TABLE dbo.AcademicField ADD CONSTRAINT PK_sdad PRIMARY KEY CLUSTERED(AcademicFieldID)
--ALTER TABLE dbo.AcademicField ADD PRIMARY KEY CLUSTERED(AcademicFieldID)



