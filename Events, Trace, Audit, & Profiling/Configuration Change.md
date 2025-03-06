# SQL Server Trace and Configuration Analyzer

<details>
<summary>(click to expand) The complete script file with added explanations:</summary>

```sql
-- Check if 'cmdshell' is enabled in SQL Server configurations
SELECT value_in_use 
FROM sys.configurations 
WHERE name LIKE '%cmdshell%';

-- Retrieve the path of the default trace file
DECLARE @tracepath NVARCHAR(256);
SELECT @tracepath = path
FROM sys.traces
WHERE is_default = 1;

-- Query the default trace file for events related to 'cmdshell' on the current day
SELECT TOP 1 
    @@SERVERNAME AS ServerName,
    TE.name AS EventName,
    T.DatabaseName,
    T.ApplicationName,
    T.LoginName,
    T.StartTime,
    T.TextData
FROM fn_trace_gettable(@tracepath, DEFAULT) T
JOIN sys.trace_events TE ON T.EventClass = TE.trace_event_id
WHERE CONVERT(DATE, StartTime) = CONVERT(DATE, GETDATE()) 
    AND T.TextData LIKE '%cmdshell%'
ORDER BY T.StartTime ASC;