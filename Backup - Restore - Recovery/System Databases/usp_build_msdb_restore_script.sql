
-- =============================================
-- Author:				<a.momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			
-- Latest Update Date:	
-- Description:			
-- License:				<Please refer to the license file> 
-- =============================================

/*
Use usp_build_one_db_restore_script.sql inside usp_build_one_db_restore_script.sql file
and specific to msdb parameters below to dynamically build restore script for the msdb
system database

*/


DECLARE @SQLCMD_Connect_Clause NVARCHAR(1000)
SELECT @SQLCMD_Connect_Clause = dt.DRName+','+dt.SQLPort
FROM
(
	SELECT 'FADWH01'       AS MainServer, 'FADWH01'       AS [SQL Name], '172.23.104.1'  AS MainIP,   'FADWHDR'       AS DRName,      '172.23.104.201' AS DRIP, '1433'      AS SQLPort
	UNION ALL SELECT 'FAIToolsDB01',   'FAIToolsDB01',   '172.23.204.1',  'FAIToolLogDR',  '172.23.204.211', '1678'
	UNION ALL SELECT 'FAIToolsLogDB01','FAIToolsLogDB01','172.23.204.11', 'FAIToolsDBDR',  '172.23.204.201', '1679'
	UNION ALL SELECT 'FALGODBFC2',     'FALGOSQL0',      '172.23.148.24', 'FAlgoDBDR',     '172.23.148.211', '1565'
	UNION ALL SELECT 'FDPDBFC02',      'FDPRSQL',        '172.23.184.4',  'FDPDBDR',       '172.23.184.201', '1433'
	UNION ALL SELECT 'FEMOFIDFC02',    'FEMOFIDFCISQL',  '172.23.136.4',  'FeMofidDBDR',   '172.23.136.201', '1566'
	UNION ALL SELECT 'FGLDBFC1',       'FGLSQL',         '172.23.160.24', 'FGLDBDR',       '172.23.160.201', '4524'
	UNION ALL SELECT 'FMCPIDBFC2',     'FMCPISQL',       '172.23.160.44', 'FMCPIDBDR',     '172.23.160.211', '5690'
	UNION ALL SELECT 'FMCSDBFC1',      'FMCSDBSQL',      '172.23.160.84', 'FMCSDBDR',      '172.23.160.231', '1917'
	UNION ALL SELECT 'FOAKDBFC2',      'FOAKDBFCISQL',   '172.23.128.44', 'FOAKDBDR',      '172.23.128.221', '1843'
	UNION ALL SELECT 'FOGTDBFC1',      'FOGTSQL',        '172.23.200.4',  'FOGTDBDR',      '172.23.200.201', '1677'
	UNION ALL SELECT 'FONLINEMFC1',    'FONLINEMSQL',    '172.23.164.4',  'FOnlineMDR',    '172.23.164.201', '1811'
	UNION ALL SELECT '' ,              '' ,              '172.23.104.1',  'FOnlineDB1DR',  '172.23.164.221', '1844'
	UNION ALL SELECT 'FONLINESH1,FONLINESH2','FONLINESHSQL1','172.23.164.24','FOnlineSHDR','172.23.164.211','1824,1825'
	UNION ALL SELECT 'FPELLEKANFC2',   'FPELLEKANSQL',   '172.23.144.4',  'FPellekanDR',   '172.23.144.201', '1556'
	UNION ALL SELECT 'FPMDB2',         'FPMSQL',         '172.23.128.5',  'FPMDBDR',       '172.23.128.201', '1850'
	UNION ALL SELECT 'FPOUYAFC1',      'FPOUYASQL',      '172.23.148.4',  'FPouyaDBDR',    '172.23.148.201', '1569'
) dt WHERE dt.[SQL Name] = CONVERT(NVARCHAR(256),SERVERPROPERTY('MachineName'))
DECLARE @BeforeRestoreScript NVARCHAR(MAX) = '

DECLARE @AgentServiceName NVARCHAR(256)
SELECT @AgentServiceName = IIF(@@SERVICENAME=''MSSQLSERVER'',''SQLSERVERAGENT'',''SQLAgent$''+@@SERVICENAME)

BEGIN TRY
	IF EXISTS (SELECT * FROM sys.dm_server_services WHERE status_desc = ''Running'' AND servicename LIKE ''SQL Server Agent%'')
	EXEC xp_servicecontrol ''stop'', ''SQLAgent$DBDR'';
END TRY
BEGIN CATCH
END CATCH

EXEC xp_servicecontrol ''querystate'', ''SQLAgent$DBDR'';
ALTER DATABASE msdb SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
'
DECLARE @AfterRestoreScript NVARCHAR(MAX) = '
ALTER DATABASE msdb SET MULTI_USER
BEGIN TRY
	EXEC xp_servicecontrol ''start'', ''SQLAgent$DBDR'';
END TRY
BEGIN CATCH
END CATCH

EXEC sp_CONFIGURE ''SHOW ADVANCED OPTIONS'',1;
RECONFIGURE WITH OVERRIDE;
EXEC sp_CONFIGURE ''AGENT'',1;
RECONFIGURE WITH OVERRIDE;
USE [msdb];

DECLARE @agent_new_log_path NVARCHAR(256)
SELECT @agent_new_log_path =
	LEFT(dt.ErrLogFile, LEN(dt.ErrLogFile)-dt.backslash_pos+1) + ''SQLAgent.out''
FROM 
(
	SELECT CONVERT(NVARCHAR(256),SERVERPROPERTY(''ErrorLogFileName'')) ErrLogFile, CHARINDEX(''\'',REVERSE(CONVERT(NVARCHAR(256),SERVERPROPERTY(''ErrorLogFileName'')))) backslash_pos
) dt
EXEC msdb.dbo.sp_set_sqlagent_properties 
    @errorlog_file=@agent_new_log_path;
UPDATE js
SET js.command=
''IF NOT EXISTS (SELECT * FROM sys.dm_hadr_availability_group_states WHERE primary_replica=@@SERVERNAME)
	return
	
''+ REPLACE(REPLACE(js.command,''@Directory = ''''R:\'',''@Directory = ''''R:\''),''@MirrorDirectory = ''''R:\'',''@MirrorDirectory = ''''R:\'')
FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j
ON js.job_id = j.job_id
WHERE 
	js.subsystem = ''TSQL'' AND 
	js.command not like ''IF NOT EXISTS (SELECT * FROM sys.dm_hadr_availability_group_states%'' AND
	j.name LIKE ''Database%'' AND j.name NOT LIKE ''%system%''
EXEC msdb.dbo.sp_purge_jobhistory
DECLARE @oldest_date DATETIME2(3) = GETDATE()
EXEC msdb.dbo.sp_delete_backuphistory @oldest_date = @oldest_date
DBCC CHECKDB(''msdb'') WITH NO_INFOMSGS
'

EXEC dbo.usp_build_one_db_restore_script @DatabaseName = 'msdb',	-- sysname
                                         @RestoreDBName = 'msdb',
										 @Restore_DataPath = 'C:\Program Files\Microsoft SQL Server\MSSQL16.DBDR\MSSQL\DATA\',
										 @Restore_LogPath = 'C:\Program Files\Microsoft SQL Server\MSSQL16.DBDR\MSSQL\DATA\',
										 @StopAt = '',				-- datetime
                                         @WithReplace = 1,				-- bit
										 @IncludeLogs = 1,
										 @IncludeDiffs = 1,
										 @RestoreUpTo_TIMESTAMP = '2026-10-28 09:52:10.553',
										 @Recovery = 1,
										 @backup_path_replace_string = 'REPLACE(Devices,''R:'',''\\''+CONVERT(NVARCHAR(256),SERVERPROPERTY(''MachineName'')))',
										 @BeforeRestoreScript = @BeforeRestoreScript,
										 @AfterRestoreScript = @AfterRestoreScript,
										 @Verbose = 0,
										 @SQLCMD_Connect_Clause = @SQLCMD_Connect_Clause
						 
GO