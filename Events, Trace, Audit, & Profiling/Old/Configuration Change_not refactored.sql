-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2024-07-30"
-- Description:         "Configuration Change_not refactored"
-- License:             "Please refer to the license file"
-- =============================================



SELECT value_in_use FROM sys.configurations 
WHERE name LIKE '%cmdshell%'


DECLARE @tracepath NVARCHAR(256);
SELECT @tracepath = path
FROM sys.traces
WHERE is_default = 1;


SELECT TOP 1 
@@SERVERNAME,
TE.name AS EventName,
T.DatabaseName,
T.ApplicationName,
T.LoginName,
T.StartTime,
T.TextData
FROM 
fn_trace_gettable(@tracepath, DEFAULT) T
JOIN sys.trace_events TE ON T.EventClass = TE.trace_event_id
WHERE CONVERT(DATE,StartTime) = CONVERT(DATE,GETDATE()) AND T.TextData LIKE '%cmdshell%' --AND
--te.name IN
--(	
--	'Audit Server Alter Trace Event', 
--'Audit Server Object GDR Event', 
--'Audit Server Operation Event', 
--'Audit Server Principal Change Group', 
--'Audit Server Role Member Change Group',
--'Audit Server Object Change Event'
--)
ORDER BY 
T.StartTime ASC;