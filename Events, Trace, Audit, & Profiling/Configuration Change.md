# SQL Server Configuration and Trace Analysis Script

This is a very simple script to check the status of the `cmdshell` feature in SQL Server and analyze related events in the default trace file. Below is a breakdown of the script's purpose and the results it generates:

** This is the script (Check the .sql file for the latest version though): **

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
    AND T.TextData LIKE '%cmdshell%' AND T.TextDate LIKE 'sp_configure'
ORDER BY T.StartTime ASC;
```

</details>



1. **Check if 'cmdshell' is enabled**  
   The script queries the `sys.configurations` system view to determine whether the `cmdshell` feature is currently enabled. The `value_in_use` column indicates the status (1 for enabled, 0 for disabled).

2. **Retrieve the path of the default trace file**  
   The script declares a variable `@tracepath` and assigns it the path of the default trace file by querying the `sys.traces` system view. This path is used to access the trace data.

3. **Query the default trace file for 'cmdshell' events (Check when and by who the cmdshell server configuration has been enabled or disabled)**  
   The script uses the `fn_trace_gettable` function to read the default trace file and filters for events related to `cmdshell` that occurred on the current day. It retrieves the following details:
   - `ServerName`: The name of the SQL Server instance.
   - `EventName`: The name of the trace event (e.g., `SQL:BatchStarting`).
   - `DatabaseName`: The database where the event occurred.
   - `ApplicationName`: The application that triggered the event.
   - `LoginName`: The login associated with the event.
   - `StartTime`: The timestamp of the event.
   - `TextData`: The SQL statement or command executed.

   The results are ordered by the earliest event timestamp (`StartTime`) and limited to the top 1 result.
