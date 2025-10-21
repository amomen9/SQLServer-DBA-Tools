-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2022-12-15"
-- Description:         "Stop Traces"
-- License:             "Please refer to the license file"
-- =============================================



-- Risky: stop traces for your important copyright queries, you do not want the server to fetch
/*
SELECT * FROM sys.traces

SELECT 
	DISTINCT id trace_id 
	,path,
	ei.eventid,
	te.name,
	ei.columnid,
	tc.name,
	tr.status

FROM sys.traces tr
CROSS APPLY sys.fn_trace_geteventinfo(id) ei JOIN sys.trace_events te
ON ei.eventid = te.trace_event_id
JOIN sys.trace_columns tc
ON ei.columnid = tc.trace_column_id
WHERE tr.status = 1 and tc.name IN
(
	N'TextData',
	N'Handle',
	N'SqlHandle',
	N'PlanHandle'
)
*/

SELECT * FROM sys.traces

DROP TABLE IF EXISTS #tmp
GO
CREATE TABLE #tmp (id int)


DECLARE @trace_id INT 
DECLARE executor CURSOR FOR
	SELECT 
	DISTINCT id trace_id --,
	--path,
	--ei.eventid,
	--te.name,
	--ei.columnid,
	--tc.name
	FROM sys.traces tr
	CROSS APPLY sys.fn_trace_geteventinfo(id) ei JOIN sys.trace_events te
	ON ei.eventid = te.trace_event_id
	JOIN sys.trace_columns tc
	ON ei.columnid = tc.trace_column_id
	WHERE tr.status = 1 AND tr.is_default = 0 and tc.name IN
	(
		N'TextData',
		N'Handle',
		N'SqlHandle',
		N'PlanHandle'
	)
OPEN executor
	FETCH NEXT FROM executor INTO @trace_id
	WHILE @@FETCH_STATUS = 0
	BEGIN
		EXEC sys.sp_trace_setstatus @trace_id, 0
		--EXEC sys.sp_trace_setstatus @trace_id, 2	-- Deletes trace
		FETCH NEXT FROM executor INTO @trace_id
    END
CLOSE executor
DEALLOCATE executor
GO

EXEC sys.sp_configure @configname = 'Show Advanced Options', @configvalue = 1; RECONFIGURE; EXEC sys.sp_configure @configname = 'default trace enabled', @configvalue = 0; RECONFIGURE; EXEC sys.sp_configure @configname = 'Show Advanced Options', @configvalue = 0; RECONFIGURE;

---------
SELECT * FROM sys.traces
-- Start the traces again:
EXEC sys.sp_configure @configname = 'Show Advanced Options', @configvalue = 1; RECONFIGURE; EXEC sys.sp_configure @configname = 'default trace enabled', @configvalue = 1; RECONFIGURE; EXEC sys.sp_configure @configname = 'Show Advanced Options', @configvalue = 0; RECONFIGURE;

DECLARE @trace_id INT 
DECLARE executor CURSOR FOR
	SELECT 
	DISTINCT id trace_id --,
	--path,
	--ei.eventid,
	--te.name,
	--ei.columnid,
	--tc.name
	FROM sys.traces tr
	CROSS APPLY sys.fn_trace_geteventinfo(id) ei JOIN sys.trace_events te
	ON ei.eventid = te.trace_event_id
	JOIN sys.trace_columns tc
	ON ei.columnid = tc.trace_column_id
	WHERE tr.status = 0 AND tr.is_default = 0 
	--AND tc.name IN
	--(
	--	N'TextData',
	--	N'Handle',
	--	N'SqlHandle',
	--	N'PlanHandle'
	--)
OPEN executor
	FETCH NEXT FROM executor INTO @trace_id
	WHILE @@FETCH_STATUS = 0
	BEGIN
		EXEC sys.sp_trace_setstatus @trace_id, 1
		FETCH NEXT FROM executor INTO @trace_id
    END
CLOSE executor
DEALLOCATE executor

SELECT * FROM sys.traces

---------------------------------
--EXEC sys.sp_configure @configname = 'show advanced options',                       @configvalue = 1  RECONFIGURE EXEC sys.sp_configure @configname = 'cmdshell',      @configvalue = 1   RECONFIGURE


--EXEC sys.xp_cmdshell '	NET use * "\\vmware-host\Shared Folders" /persistent:yes && fsutil fsinfo drives && whoami '
--EXEC xp_dirtree N'Y:\C\Users\Ali\Dropbox\JobVision\Installation\Setup\'
--exec xp_create_subdir N'C:\Databases\Data\'; exec xp_create_subdir N'C:\Databases\Log\'; 
--RESTORE DATABASE [dbWarden] FROM  DISK = N'Y:\C\Users\Ali\Dropbox\JobVision\Installation\Setup\dbWarden_DB1_truncated_22.05.31.bak' WITH  FILE = 1, MOVE N'dbWarden' TO N'C:\Databases\Data\dbWarden.mdf', MOVE N'dbWardenAudit' TO N'C:\Databases\Data\dbWardenAudit.ndf', MOVE N'DbWardenArchive' TO N'C:\Databases\Data\DbWardenArchive.ndf', MOVE N'dbWardenErrorLog' TO N'C:\Databases\Data\dbWardenErrorLog.mdf', MOVE N'dbWardenPerfmon' TO N'C:\Databases\Data\dbWardenPerfmon.mdf', MOVE N'dbWardenWaitStatistic' TO N'C:\Databases\Data\dbWardenWaitStatistic.mdf', MOVE N'dbWarden_log' TO N'C:\Databases\Log\dbWarden_log.ldf', NOUNLOAD, STATS = 30



SELECT * FROM sys.server_event_sessions
--SELECT * FROM sys.server_events
SELECT * FROM sys.server_event_session_targets
SELECT * FROM sys.server_event_session_actions
--SELECT * FROM sys.server_trigger_events
SELECT * FROM sys.server_event_session_events
SELECT * FROM sys.server_event_session_fields	-- XE trace files
SELECT * FROM sys.trace_xe_event_map	-- Wonderful!!!
SELECT * FROM sys.dm_xe_objects
SELECT * FROM sys.dm_xe_object_columns

SELECT
        object_name,
        file_name,
        file_offset,
        event_data,
        'CLICK_NEXT_CELL_TO_BROWSE_XML RESULTS!'
                AS [CLICK_NEXT_CELL_TO_BROWSE_XML_RESULTS],
        CAST(event_data AS XML) AS [event_data_XML]
                -- TODO: In ssms.exe results grid, double-click this xml cell!
    FROM
        sys.fn_xe_file_target_read_file(
            'M:\Extended Event\CaptureDeadlocks\DB2-CaptureDeadlocks-14000810-224141',
            null, null, null
        );





--EXEC master.sys.sp_cycle_errorlog;
					  