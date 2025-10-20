--batch_text	--RedGateIgnore          
SET NOCOUNT ON;
SELECT TOP 200
       wait_type,
       waiting_tasks_count,
       wait_time_ms,
       signal_wait_time_ms,
       0 AS affected_queries_zero
FROM sys.dm_os_wait_stats
WHERE wait_time_ms > 0
      AND [wait_type] NOT IN ( N'BROKER_EVENTHANDLER', N'BROKER_INIT', N'BROKER_MASTERSTART',
                               N'BROKER_RECEIVE_WAITFOR', N'BROKER_REGISTERALLENDPOINTS', N'BROKER_SERVICE',
                               N'BROKER_SHUTDOWN', N'BROKER_TASK_STOP', N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER',
                               N'CHECKPOINT_QUEUE', N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE',
                               N'DBMIRROR_DBM_MUTEX', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL',
                               N'DISPATCHER_QUEUE_SEMAPHORE', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
                               N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP',
                               N'LOGMGR_QUEUE', N'MISCELLANEOUS', N'OGMGR_QUEUE', N'ONDEMAND_TASK_QUEUE',
                               N'PARALLEL_BACKUP_QUEUE', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
                               N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', N'REQUEST_DISPENSER_PAUSE',
                               N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE', N'SLEEP_BPOOL_FLUSH',
                               N'SLEEP_DBSTARTUP', N'SLEEP_DCOMSTARTUP', N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK',
                               N'SLEEP_TASK', N'SLEEP_TEMPDBSTARTUP', N'SP_SERVER_DIAGNOSTICS_SLEEP',
                               N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'TRACEWRITE',
                               N'WAITFOR', N'XE_DISPATCHER_JOI', N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT',
                               N'HADR_WORK_QUEUE', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'LOGMGR_QUEUE',
                               N'HADR_TIMER_TASK', N'HADR_CLUSAPI_CALL', N'HADR_LOGCAPTURE_WAIT',
                               N'QDS_SHUTDOWN_QUEUE', N'HADR_NOTIFICATION_DEQUEUE', N'CXCONSUMER',
                               N'PARALLEL_REDO_WORKER_WAIT_WORK', N'PARALLEL_REDO_DRAIN_WORKER',
                               N'PARALLEL_REDO_LOG_CACHE', N'PARALLEL_REDO_TRAN_LIST', N'PARALLEL_REDO_WORKER_SYNC',
                               N'SOS_WORK_DISPATCHER', N'QDS_ASYNC_QUEUE', N'VDI_CLIENT_OTHER',
                               N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'RESOURCE_GOVERNOR_IDLE', N'PVS_PREALLOCATE',
                               N'HADR_FABRIC_CALLBACK', N'PWAIT_EXTENSIBILITY_CLEANUP_TASK', N'WAIT_XTP_HOST_WAIT'
                             )
ORDER BY wait_time_ms DESC,
         signal_wait_time_ms DESC;