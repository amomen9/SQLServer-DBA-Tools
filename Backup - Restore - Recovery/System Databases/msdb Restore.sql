-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2025-10-21"
-- Description:         "msdb Restore"
-- License:             "Please refer to the license file"
-- =============================================



-- Do the following operation in the Database Engine's normal mode.
-- It does not require that you bring the Database Engine up with
-- any specific startup parameters including enabling/diabling any trace flags 


USE [master];
GO
ALTER DATABASE msdb SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO

-- Restore and replace database msdb to desired target location
RESTORE DATABASE msdb
   FROM DISK = '\\FSFSQL\Backups\FSFSQL\msdb\FULL\FSFSQL_msdb_FULL_20250909_032522.bak'
   WITH 
     MOVE 'MSDBData' TO 'M:\MSSQL15.MSSQLSERVER\MSSQL\DATA\MSDBData.mdf',
     MOVE 'MSDBLog'  TO 'M:\MSSQL15.MSSQLSERVER\MSSQL\DATA\MSDBLog.ldf',
     REPLACE;
GO
ALTER DATABASE msdb SET MULTI_USER;
GO
sp_CONFIGURE 'SHOW ADVANCED OPTIONS',1;
GO
RECONFIGURE WITH OVERRIDE;
GO
sp_CONFIGURE 'AGENT',1;
GO
RECONFIGURE WITH OVERRIDE;
GO



USE [msdb];
GO
-- Rectify the restored msdb's original log path and set it to be at the "Current server's error log directory"
-- Sample server's log path: M:\MSSQL15.MSSQLSERVER\MSSQL\Log\SQLAGENT.OUT
DECLARE @agent_new_log_path NVARCHAR(256)
-- Find current server's error log directory and assign it to @agent_new_log_path
SELECT @agent_new_log_path =
	LEFT(dt.ErrLogFile, LEN(dt.ErrLogFile)-dt.backslash_pos+1) + 'SQLAgent.out'
FROM 
(
	SELECT CONVERT(NVARCHAR(256),SERVERPROPERTY('ErrorLogFileName')) ErrLogFile, CHARINDEX('\',REVERSE(CONVERT(NVARCHAR(256),SERVERPROPERTY('ErrorLogFileName')))) backslash_pos
) dt

EXEC msdb.dbo.sp_set_sqlagent_properties 
    @errorlog_file=@agent_new_log_path;
GO


-- Update jobs, set their steps to skip execution if the current server is not the primary replica
UPDATE js
SET js.command=
'IF NOT EXISTS (SELECT * FROM sys.dm_hadr_availability_group_states WHERE primary_replica=@@SERVERNAME)
--	exec msdb.dbo.sp_stop_job @job_name = ''$(ESCAPE_SQUOTE(JOBNAME)) ''
	return
	
'+ REPLACE(REPLACE(js.command,'@Directory = ''R:\','@Directory = ''M:\'),,'@MirrorDirectory = ''R:\','@MirrorDirectory = ''M:\')
FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j
ON js.job_id = j.job_id
WHERE 
	js.subsystem = 'TSQL' AND 
	js.command not like 'IF NOT EXISTS (SELECT * FROM sys.dm_hadr_availability_group_states%' AND
	j.name LIKE 'Database%' AND j.name NOT LIKE '%system%'


-- purge msdb job history
EXEC msdb.dbo.sp_purge_jobhistory


-- purge msdb backup history
DECLARE @oldest_date DATETIME2(3) = GETDATE()
EXEC msdb.dbo.sp_delete_backuphistory @oldest_date = @oldest_date

-- Perform a CHECKDB of the restored msdb database to ensure its health
DBCC CHECKDB('msdb') WITH NO_INFOMSGS


