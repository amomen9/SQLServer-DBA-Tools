-- =============================================
-- Author:		<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:		<2021.03.11>
-- Description:		<Create CDC Jobs on the secondary replicas>
-- License:			<Please refer to the license file>
-- =============================================

-- For information please refer to the README.md file



IF NOT EXISTS (SELECT 1 FROM msdb.sys.tables WHERE name = 'cdc_jobs')
BEGIN
    
	CREATE TABLE msdb.[dbo].[cdc_jobs](
		[database_id] [int] NOT NULL,
		[job_type] [nvarchar](20) NOT NULL,
		[job_id] [uniqueidentifier] NULL,
		[maxtrans] [int] NULL,
		[maxscans] [int] NULL,
		[continuous] [bit] NULL,
		[pollinginterval] [bigint] NULL,
		[retention] [bigint] NULL,
		[threshold] [bigint] NULL,
	PRIMARY KEY CLUSTERED 
	(
		[database_id] ASC,
		[job_type] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 94, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
	) ON [PRIMARY]

	EXEC msdb.sys.sp_MS_marksystemobject @objname = 'dbo.cdc_jobs'
END

GO

----------------- Capture Job ----------------------------------------------


DECLARE @DBName sysname = DB_NAME()
DECLARE @JobName sysname = N'cdc.'+@DBName+'_capture'
DECLARE @step1_command NVARCHAR(max) = N'IF ISNULL((SELECT sys.fn_hadr_is_primary_replica('''+@DBName+''')),1) = 0
	RETURN
ELSE
	RAISERROR(22801, 10, -1)'
DECLARE @step2_command NVARCHAR(max) = N'IF ISNULL((SELECT sys.fn_hadr_is_primary_replica('''+@DBName+''')),1) = 0
	RETURN
ELSE
	EXEC sys.sp_MScdc_capture_job'

DECLARE @DBID INT = DB_ID()


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [REPL-LogReader]    Script Date: 8/21/2022 10:46:44 AM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'REPL-LogReader' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'REPL-LogReader'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16),
		@jobId_guid UNIQUEIDENTIFIER,
		@schedule_guid UNIQUEIDENTIFIER

EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=@JobName, 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'CDC Log Scan Job', 
		@category_name=N'REPL-LogReader', 
		@owner_login_name=N'AppSQL', @job_id = @jobId OUTPUT
SET @jobId_guid = CONVERT(UNIQUEIDENTIFIER,@jobId)

IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Starting Change Data Capture Collection Agent]    Script Date: 8/21/2022 10:46:44 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Starting Change Data Capture Collection Agent', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=10, 
		@retry_interval=1, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=@step1_command, 
		@server=@@SERVERNAME, 
		@database_name=@DBName, 
		@flags=4
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Change Data Capture Collection Agent]    Script Date: 8/21/2022 10:46:44 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Change Data Capture Collection Agent', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=10, 
		@retry_interval=1, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=@step2_command, 
		@server=@@SERVERNAME, 
		@database_name=@DBName, 
		@flags=4
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'CDC capture agent schedule.', 
		@enabled=1, 
		@freq_type=64, 
		@freq_interval=0, 
		@freq_subday_type=0, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20220820, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=@schedule_guid OUT --N'8b7876a4-d3ac-493e-a0ef-823ae7bb6fb9'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback


INSERT msdb..cdc_jobs
(
    database_id,
    job_type,
    job_id,
    maxtrans,
    maxscans,
    continuous,
    pollinginterval,
    retention,
    threshold
)
VALUES
(   @DBID,    -- database_id - int
    N'capture',  -- job_type - nvarchar(20)
    @jobId_guid, -- job_id - uniqueidentifier
    6000, -- maxtrans - int  Default: 500
    10, -- maxscans - int
    1, -- continuous - bit
    60, -- pollinginterval - bigint Default: 5
    0, -- retention - bigint
    0  -- threshold - bigint
)

COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION

EndSave:
GO


--------------------- Cleanup Job ---------------------------------------------


DECLARE @DBName sysname = DB_NAME()
DECLARE @DBID INT = DB_ID()

DECLARE @JobName sysname = N'cdc.'+@DBName+'_cleanup'
DECLARE @step1_command NVARCHAR(max) = N'IF ISNULL((SELECT sys.fn_hadr_is_primary_replica(''Co-JobVisionDB'')),1) = 0
	RETURN
ELSE
	EXEC sys.sp_MScdc_cleanup_job'


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [REPL-Checkup]    Script Date: 8/21/2022 10:46:49 AM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'REPL-Checkup' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'REPL-Checkup'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END


DECLARE @jobId BINARY(16),
		@jobId_guid UNIQUEIDENTIFIER,
		@schedule_guid UNIQUEIDENTIFIER


EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=@JobName, 
		@enabled=0, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'CDC Cleanup Job', 
		@category_name=N'REPL-Checkup', 
		@owner_login_name=N'AppSQL', @job_id = @jobId OUTPUT

SELECT @jobId_guid = CONVERT(UNIQUEIDENTIFIER,@jobId)

IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Change Data Capture Cleanup Agent]    Script Date: 8/21/2022 10:46:50 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Change Data Capture Cleanup Agent', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=10, 
		@retry_interval=1, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=@step1_command, 
		@server=@@SERVERNAME, 
		@database_name=@DBName, 
		@flags=4
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'CDC cleanup agent schedule.', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=1, 
		@freq_relative_interval=1, 
		@freq_recurrence_factor=0, 
		@active_start_date=20220820, 
		@active_end_date=99991231, 
		@active_start_time=20000, 
		@active_end_time=235959, 
		@schedule_uid=@schedule_guid out --N'9955f19a-8f4a-4c7b-b7b5-bc798860fa25'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

INSERT msdb..cdc_jobs
(
    database_id,
    job_type,
    job_id,
    maxtrans,
    maxscans,
    continuous,
    pollinginterval,
    retention,
    threshold
)
VALUES
(   @DBID,    -- database_id - int
    N'cleanup',  -- job_type - nvarchar(20)
    @jobId_guid, -- job_id - uniqueidentifier
    0, -- maxtrans - int
    0, -- maxscans - int
    0, -- continuous - bit
    0, -- pollinginterval - bigint
    4320, -- retention - bigint
    5000  -- threshold - bigint
)

COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

--------------- Start capture job ---------------------------------------------


DECLARE @DBName sysname = DB_NAME()
DECLARE @JobName sysname = N'cdc.'+@DBName+'_capture'

EXEC msdb..sp_start_job @job_name = @JobName    -- sysname
                       