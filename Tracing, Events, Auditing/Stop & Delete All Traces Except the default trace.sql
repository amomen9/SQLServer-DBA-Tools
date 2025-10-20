-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2022.07.15>
-- Latest Update Date:	<2022.07.15>
-- Description:			<Stop All Traces>
-- =============================================



-- Risky: traces keep trace of what is happening on your instance. Stop them cautiously


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
	WHERE tr.status = 1 AND tr.is_default = 0 

OPEN executor
	FETCH NEXT FROM executor INTO @trace_id
	WHILE @@FETCH_STATUS = 0
	BEGIN
		EXEC sys.sp_trace_setstatus @trace_id, 0		-- stop trace
		EXEC sys.sp_trace_setstatus @trace_id, 2		-- delete trace
		FETCH NEXT FROM executor INTO @trace_id
    END
CLOSE executor
DEALLOCATE executor
GO

/*
Stop the default trace:

EXEC sys.sp_configure @configname = 'Show Advanced Options', @configvalue = 1; RECONFIGURE; EXEC sys.sp_configure @configname = 'default trace enabled', @configvalue = 0; RECONFIGURE; EXEC sys.sp_configure @configname = 'Show Advanced Options', @configvalue = 0; RECONFIGURE;

*/