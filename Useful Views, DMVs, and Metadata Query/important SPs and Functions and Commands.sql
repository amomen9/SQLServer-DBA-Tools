EXEC sp_help 'dbo.mytable';

--------------------------------------------------------------------

select format(getdate(),'D','fa-ir'),format(getdate(),'d','fa-ir')

---- Conventional TIMESTAMP
SELECT Format(getdate(),'yyMMdd_HHmm','en-us')
--SELECT CURRENT_TIMESTAMP

-- DATENAME ( datepart , date )  
select datename(w,getdate())

--------------------------------------------------------------------
exec xp_dirtree N'e:\backup' , 0 , 1	-- the first number is depth. enter 0 for unlimited. The second number is entity type, either folder or file, enter 0 for folder and else for both

select sys.fn_hadr_is_primary_replica(db_name())
select sys.fn_hadr_backup_is_preferred_replica(db_name())

--------------------------------------------------------------------

DBCC SQLPERF("sys.dm_os_wait_stats", CLEAR) WITH NO_INFOMSGS

--------------------------------------------------------------------

DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS

-------------------------------------------------------------------- File Operation:


SELECT file_exists, file_is_a_directory, parent_directory_exists FROM sys.dm_os_file_exists('D:\sadasdadsd')
SELECT * FROM sys.dm_os_file_exists('C:\Windows\System32\cmd.exe')
SELECT * FROM sys.dm_os_file_exists('C:\Windows\System32')
SELECT * FROM sys.dm_os_file_exists('%windir%\system32\')	-- Wrong

/* Coulmns:
	[file_exists] tinyint,
	[file_is_a_directory] tinyint,
	[parent_directory_exists] tinyint
*/


DECLARE @result INT
EXEC master.dbo.xp_fileexist 'C:\Users\Ali\Desktop\test\17)dsadasd.sqla', @result OUTPUT
SELECT @result
------
EXEC xp_delete_files
xp_delete_file

-- xp_copy_file
EXEC master.sys.xp_copy_file '/var/opt/mssql/data/samples/albums.csv', '/var/opt/mssql/data/samples/albums2.csv';

-- Copy Multiple Files
EXEC sys.xp_copy_files 'C:\Users\Ali\Desktop\test\17)dsadasd.sql','C:\Users\Ali\Desktop\test2\'
EXEC master.sys.xp_copy_files '/var/opt/mssql/data/samples/albums*.csv','/var/opt/mssql/data/samples/final';

GO-------------------------------------------------------------------- sp_executesql

DECLARE @TblZimz    NVARCHAR(256)
DECLARE @IdModul    INTEGER
DECLARE @Id         INTEGER
DECLARE @SqlQuery NVARCHAR(MAX)

SET @SqlQuery = 'SELECT TOP (1) @Id = ([ID]) FROM '
                + @TblZimz + ' WHERE [ModulId] = @IdModul'

EXEC SP_EXECUTESQL
  @SqlQuery,
  N'@Id INT OUTPUT, @IdModul INT',
  @IdModul = @IdModul,
  @Id = @Id OUTPUT 


--------------------------------------------------------------------- checksum

DROP TABLE IF EXISTS test..test25
DROP TABLE IF EXISTS test..test26
go
CREATE TABLE test..test25(c1 INT, c2 int)
CREATE TABLE test..test26(c1 INT, c2 int)
GO

INSERT test.dbo.test25
(
    c1
	,c2
)
VALUES
(1,2  -- c1 - int
    ),(2,2),(3,2)

INSERT test.dbo.test26
(
    c1
	,c2
)
VALUES
(2,3  -- c1 - int
    ),(3,3),(4,3),(5,3)

SELECT * FROM test..test25 FULL OUTER JOIN test..test26 ON test25.c1 = test26.c1
--EXCEPT
SELECT * FROM test..test25 FULL JOIN test..test26 ON test25.c1 = test26.c1

SELECT * FROM test..test25 JOIN test..test26 ON test25.c1 = test26.c1
WHERE CHECKSUM(test25.c1,dbo.test25.c2)<>CHECKSUM(test26.c1,dbo.test26.c2)


-------New Execute AS-------------------------------------------------------------------

EXECUTE AS LOGIN = 'login1';
SELECT SUSER_NAME(), USER_NAME();
EXECUTE AS USER = 'user2';
SELECT SUSER_NAME(), USER_NAME();

------ Extended Property ---------------------------------------------------------------

EXEC sys.sp_addextendedproperty @name=N'NewCoAppr_WaitForDBCreate', @value=N'0' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'Companies'
GO

EXEC sys.sp_updateextendedproperty  @name = 'NewCoAppr_WaitForDBCreate'       -- sysname
                                   ,@value = '1'      -- sql_variant
                                   ,@level0type = ''   -- varchar(128)
                                   ,@level0name = NULL -- sysname
                                   ,@level1type = ''   -- varchar(128)
                                   ,@level1name = NULL -- sysname
                                   ,@level2type = ''   -- varchar(128)
                                   ,@level2name = NULL  -- sysname

EXEC sys.sp_dropextendedproperty @name = NULL,       -- sysname
						  	@level0type = '',   -- varchar(128)
						  	@level0name = NULL, -- sysname
						  	@level1type = '',   -- varchar(128)
						  	@level1name = NULL, -- sysname
						  	@level2type = '',   -- varchar(128)
						  	@level2name = NULL  -- sysname
						  	   
						  	   

SELECT * from sys.extended_properties

SELECT * from CandoMainDB.sys.extended_properties WHERE CONVERT(VARCHAR(max),value)='0'

SELECT * FROM ::fn_listextendedproperty ('SNO', 'Schema', 'dbo', 'Table', 'mytest', 'Column', 'sno')

SELECT * FROM sys.fn_listextendedproperty ('NewCoAppr_WaitForDBCreate', 'Schema', 'dbo', 'Table', 'Companies', NULL, NULL)

---------------------------------------------------------------------------------------

EXEC sys.sp_helpextendedproc @funcname = NULL -- sysname

------- RAISERROR ---------------------------------------------------------------------

-- Syntax for SQL Server and Azure SQL Database  
  
RAISERROR ( { msg_id | msg_str | @local_variable }  
    { ,severity ,state }  
    [ ,argument [ ,...n ] ] )  
    [ WITH option [ ,...n ] ]

------ error log ----------------------------------------------------------
-- view error log files
EXEC master.sys.xp_enumerrorlogs;

-- view error log records:
--columns:
-----------   ---------------  --------
--LogDate		ProcessInfo		 Text
EXEC sys.xp_readerrorlog 0, 1, N'Manufacturer';

EXEC sys.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'HARDWARE\DESCRIPTION\System\CentralProcessor\0', N'ProcessorNameString';
EXEC sys.xp_readerrorlog 0, 1, N'The tempdb database has';
EXEC sys.xp_readerrorlog 0, 1, N'detected', N'socket';
EXEC sys.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'HARDWARE\DESCRIPTION\System\BIOS', N'BiosReleaseDate';
EXEC xp_readerrorlog 0, 1, N'taking longer than 15 seconds';
EXEC xp_readerrorlog 1, 1, N'taking longer than 15 seconds';

declare @DefaultData nvarchar (512)
exec master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultData', @DefaultData output
select @DefaultData as DefaultData

DECLARE @DefaultLog nvarchar (512)
exec master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultLog', @DefaultLog output
select @DefaultLog as DefaultLog


declare @MasterData nvarchar (512)
exec master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer\Parameters', N'SqlArg0', @MasterData output
select @MasterData=substring (@MasterData, 3, 255)
select @MasterData=substring (@MasterData, 1, len (@MasterData) - charindex ('\', reverse (@MasterData)))
select @MasterData as DefaultMasterData

--------------------------------------
EXEC sys.sp_rename @objname = N'',  -- nvarchar(1035)
                   @newname = NULL, -- sysname
                   @objtype = ''    -- varchar(13)

EXEC sys.sp_renamedb @dbname = NULL, -- sysname
                     @newname = NULL -- sysname

--examples:
--column:
USE AdventureWorks2012;  
GO  
EXEC sp_rename 'Sales.SalesTerritory.TerritoryID', 'TerrID', 'COLUMN';  
GO


-------- To be researched:

sys.sp_add_log_file_recover_suspect_db  @dbName = NULL,   -- sysname
                                       @name = N'',      -- nvarchar(260)
                                       @filename = N'',  -- nvarchar(260)
                                       @size = N'',      -- nvarchar(20)
                                       @maxsize = N'',   -- nvarchar(20)
                                       @filegrowth = N'' -- nvarchar(20)

----------- Brent Ozar childish query -----------------------------------------------------------------

SELECT 'ALTER DATABASE tempdb MODIFY FILE (NAME = [' + f.name + '],'
	+ ' FILENAME = ''E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\TempDB\' + f.name
	+ CASE WHEN f.type = 1 THEN '.ldf' ELSE '.mdf' END
	+ ''');'
FROM sys.master_files f
WHERE f.database_id = DB_ID(N'tempdb');

ALTER DATABASE tempdb add FILE (NAME = [temp7], FILENAME = 'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\TempDB\temp7.ndf', SIZE=1GB,MAXSIZE=UNLIMITED,FILEGROWTH=512MB);

ALTER DATABASE tempdb remove FILE [temp7]

CREATE TABLE #temp(id int)
INSERT #temp
(
    id
)
VALUES
(1  -- id - int
    ),(2)

SELECT * FROM #temp


ALTER DATABASE tempdb MODIFY FILE (NAME = [tempdev], FILENAME = 'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\TempDB\tempdev.mdf');
ALTER DATABASE tempdb MODIFY FILE (NAME = [templog], FILENAME = 'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\TempDB\templog.ldf');
ALTER DATABASE tempdb MODIFY FILE (NAME = [temp2], FILENAME = 'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\TempDB\temp2.mdf');
ALTER DATABASE tempdb MODIFY FILE (NAME = [temp3], FILENAME = 'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\TempDB\temp3.mdf');
ALTER DATABASE tempdb MODIFY FILE (NAME = [temp4], FILENAME = 'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\TempDB\temp4.mdf');
ALTER DATABASE tempdb MODIFY FILE (NAME = [temp5], FILENAME = 'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\TempDB\temp5.mdf');
ALTER DATABASE tempdb MODIFY FILE (NAME = [temp6], FILENAME = 'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\TempDB\temp6.mdf');
ALTER DATABASE tempdb MODIFY FILE (NAME = [temp7], FILENAME = 'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\TempDB\temp7.mdf');

-- The file "temp3" has been modified in the system catalog. The new path will be used the next time the database is started.

--------------------------------------------------------------------------------------------------------------------------

USE [master]
EXEC sp_detach_db CandoFileDB;
GO

EXEC sys.sp_attach_db @dbname = NULL,    -- sysname
                      @filename1 = N'',  -- nvarchar(260)
                      @filename2 = N'',  -- nvarchar(260)
                      @filename3 = N'',  -- nvarchar(260)
                      @filename4 = N'',  -- nvarchar(260)
                      @filename5 = N'',  -- nvarchar(260)
                      @filename6 = N'',  -- nvarchar(260)
                      @filename7 = N'',  -- nvarchar(260)
                      @filename8 = N'',  -- nvarchar(260)
                      @filename9 = N'',  -- nvarchar(260)
                      @filename10 = N'', -- nvarchar(260)
                      @filename11 = N'', -- nvarchar(260)
                      @filename12 = N'', -- nvarchar(260)
                      @filename13 = N'', -- nvarchar(260)
                      @filename14 = N'', -- nvarchar(260)
                      @filename15 = N'', -- nvarchar(260)
                      @filename16 = N''  -- nvarchar(260)
-- Alternatively:

USE [master]
GO
CREATE DATABASE [CandoMainDB_test2] ON 
( FILENAME = N'E:\TestRaw\Database Data\CandoMainDB_test.mdf' ),
( FILENAME = N'E:\TestRaw\Database Log\CandoMainDB_test_log.ldf' ),
( FILENAME = N'E:\TestRaw\Database Data\CandoMainDB_test_Entities.ndf' ),
( FILENAME = N'E:\TestRaw\Database Data\CandoMainDB_test_NIX.ndf' )
 FOR ATTACH
GO


------- trace ------------------------------------------------------------------------------------------------------------
SELECT SCHEMA_NAME(ao.schema_id)+'.'+
OBJECT_NAME(ao.object_id) [Object Name], ao.type_desc [Object Type] 
FROM sys.all_objects ao
WHERE name LIKE '%trace%' AND ao.type_desc IN ('VIEW','USER_TABLE')


SELECT * FROM sys.traces
SELECT * FROM sys.trace_event_bindings
SELECT * FROM sys.trace_events
SELECT * FROM sys.trace_xe_action_map
SELECT * FROM sys.trace_columns
SELECT * FROM sys.trace_xe_event_map
SELECT * FROM sys.trace_categories
SELECT * FROM sys.trace_subclass_values
SELECT * FROM ::fn_trace_getinfo(default)

--SELECT * FROM sys.configurations WHERE name = 'default trace enabled'
EXEC sys.sp_configure @configname = 'Show Advanced Options', @configvalue = 1; RECONFIGURE; 
EXEC sys.sp_configure @configname = 'default trace enabled', @configvalue = 0; RECONFIGURE; 
EXEC sys.sp_configure @configname = 'Show Advanced Options', @configvalue = 0; RECONFIGURE;


-- second argument: number of files to read
SELECT * FROM sys.fn_trace_gettable('M:\Trace Files\Long Queries\AllDatabase\TraceFile-LongQuery-AllDatabase-14010327.trc',5)
SELECT * FROM sys.fn_trace_gettable('C:\windows\system32\JV.trc',5)

SELECT * FROM sys.fn_trace_getinfo(0)
/*
sys.fn_trace_getinfo ( { trace_id | NULL | 0 | DEFAULT } )
NULL, 0, and DEFAULT are equivalent values in this context

ROW		Column name			Data type		Description
		-----------			---------		-----------
1		traceid				int				ID of the trace.
2		property			int				Property of the trace:

											1= Trace options. For more information, see @options in sp_trace_create (Transact-SQL).

											2 = File name

											3 = Max size

											4 = Stop time

											5 = Current trace status. 0 = stopped. 1 = running.
3		value				sql_variant		Information about the property of the trace specified.

*/

-- create and manipulate traces:

DECLARE @RC int, @TraceID int, @on BIT
EXEC @rc = sp_trace_create 
							@traceid =@TraceID output,
							@options =2,
							@tracefile =N'C:\SampleTrace',
							@maxfilesize = 20, -- MB
							@stoptime = NULL,
							@filecount = 6
/*
SELECT * FROM sys.all_parameters WHERE object_id = (SELECT OBJECT_ID('sp_trace_create'))	-- returns null results!!!!

sp_trace_create [ @traceid = ] trace_id OUTPUT   
          , [ @options = ] option_value   no default
          , [ @tracefile = ] 'trace_file'   
     [ , [ @maxfilesize = ] max_file_size ] Megabytes default value of 5
     [ , [ @stoptime = ] 'stop_time' ]  default value of NULL
     [ , [ @filecount = ] 'max_rollover_files' ] This parameter is valid only if the TRACE_FILE_ROLLOVER option is specified

*/
-- 12 is SQL:BatchCompleted, 15 is EndTime  
EXEC sp_trace_setevent @TraceID, 12, 15, @on

EXEC sp_trace_setStatus @TraceID,1   -- 1=start , 0=stop , 2=drop

SELECT * FROM sys.trace_columns
SELECT * FROM sys.trace_events 
--WHERE name LIKE '%mirror%'
SELECT * FROM sys.fn_trace_geteventinfo(2)	-- input trace_id and get the list of columns and events set for that trace




--SELECT ei.eventid,te.name,ei.columnid,tc.name FROM sys.fn_trace_geteventinfo(2) ei JOIN sys.trace_events te
--ON ei.eventid = te.trace_event_id
--JOIN sys.trace_columns tc
--ON ei.columnid = tc.trace_column_id

--SELECT * FROM sys.trace_columns WHERE name LIKE '%handle%'

SELECT id trace_id, path, ei.eventid,te.name,ei.columnid,tc.name FROM sys.traces tr
CROSS APPLY sys.fn_trace_geteventinfo(id) ei JOIN sys.trace_events te
ON ei.eventid = te.trace_event_id
JOIN sys.trace_columns tc
ON ei.columnid = tc.trace_column_id
WHERE tc.name IN
(
N'TextData',
N'Handle',
N'SqlHandle',
N'PlanHandle'

)
/*
(
N'TextData',
N'BinaryData',
N'NTUserName',
N'HostName',
N'LoginName',
N'Handle',
N'TargetUserName',
N'DBUserName',
N'LoginSid',
N'TargetLoginName',
N'TargetLoginSid',
N'LinkedServerName',
N'OwnerID',
N'SqlHandle',
N'SessionLoginName',
N'PlanHandle'
)
*/





/*
EXEC sys.sp_trace_getdata @traceid = 1, -- int
                          @records = 10  -- int
sp_trace_getdata is used by SQL Profiler to read it's trace and return the results to the SQL Profiler GUI/application

SELECT OBJECT_NAME(object_id), * FROM sys.all_parameters WHERE name LIKE '%trace%id%' AND name NOT LIKE '%tracer%'
sp_trace_getdata
*/
------- extended Events XE ------------------------------------------------------------------------------------------------------------

-- CREATE EVENT SESSION ...

SELECT name
    FROM sys.all_objects
    WHERE
        (name LIKE 'database\_%' { ESCAPE '\' } OR
         name LIKE 'server\_%' { ESCAPE '\' })
        AND name LIKE '%\_event%' { ESCAPE '\' }
        AND type = 'V'
    ORDER BY name;


SELECT text, COUNT(text) count_text, MIN(dt.Timestamp) min_timestamp, DATEDIFF_BIG(MICROSECOND,MIN(dt.Timestamp), MAX(dt.Timestamp))/1000000.0 timestamp_interval, IIF(DATEDIFF_BIG(MICROSECOND,MIN(dt.Timestamp),MAX(dt.Timestamp))=0,NULL,COUNT(text)*1000000.0/DATEDIFF_BIG(MICROSECOND,MIN(dt.Timestamp),MAX(dt.Timestamp))) count_per_second
INTO #queries
FROM
(
	SELECT 
		timestamp_utc [Timestamp],
		CONVERT(XML,event_data).value('(/event/action[@name=''sql_text'']/value)[1]','varchar(max)') text
	FROM sys.fn_xe_file_target_read_file('E:\Intel\batch*',NULL,NULL,NULL)
) dt
GROUP BY dt.text
ORDER BY 2 DESC

SELECT * FROM #queries

SELECT * FROM sys.fn_xe_file_target_read_file('C:\Intel\batch_0_133250848969190000.xel',NULL,NULL,NULL)

SELECT * FROM sys.dm_xe_sessions
SELECT * FROM sys.dm_xe_map_values
SELECT * FROM sys.dm_xe_object_columns
SELECT * FROM sys.dm_xe_objects
SELECT * FROM sys.dm_xe_packages
SELECT * FROM sys.dm_xe_session_event_actions
SELECT * FROM sys.dm_xe_session_events
SELECT * FROM sys.dm_xe_session_object_columns
SELECT * FROM sys.dm_xe_session_targets


SELECT event_session_id,e.name event_name,* FROM sys.dm_xe_sessions s
RIGHT JOIN sys.server_event_sessions e ON e.name = s.name

SELECT * FROM sys.server_event_sessions
SELECT * FROM sys.server_event_notifications
--SELECT * FROM sys.server_events

SELECT e.name event_name,e.event_session_id,t.target_id,t.name,t.package,t.module FROM sys.server_event_session_targets t
RIGHT JOIN sys.server_event_sessions e ON e.event_session_id = t.event_session_id

SELECT e.name event_name,a.* FROM sys.server_event_session_actions a
RIGHT JOIN sys.server_event_sessions e ON e.event_session_id = a.event_session_id

--SELECT * FROM sys.server_trigger_events

SELECT e.name event_name,ee.* FROM sys.server_event_session_events ee
RIGHT JOIN sys.server_event_sessions e ON e.event_session_id = ee.event_session_id

SELECT e.name event_name,f.* FROM sys.server_event_session_fields f	-- XE trace files
RIGHT JOIN sys.server_event_sessions e ON e.event_session_id = f.event_session_id


SELECT * FROM sys.trace_columns	-- This has nothing to do with the next line
SELECT * FROM sys.trace_xe_event_map	-- Wonderful!!!
SELECT * FROM sys.trace_xe_action_map	-- Wonderful!!!
SELECT * FROM sys.dm_xe_objects
SELECT * FROM sys.dm_xe_object_columns

GO------- Error Logs ----------------------------------------------------------------------------------------------------


EXEC sys.sp_enumerrorlogs;

/*
EXEC xp_readerrorlog 
    0, 
    1, 
    N'Recovery', 
    N'', 
    N'2019-11-07 00:00:01.000', 
    N'2019-11-07 09:00:01.000',
    N'desc'

LogNumber: It is the log number of the error log. You can see the lognumber in the above screenshot. Zero is always referred to as the current log file
LogType: We can use this command to read both SQL Server error logs and agent logs
	1 - To read the SQL Server error log
	2 - To read SQL Agent logs
SearchItem1: In this parameter, we specify the search keyword
SearchItem2: We can use additional search items. Both conditions ( SearchItem1 and SearchItem2) should be satisfied with the results
StartDate,
EndDate: We can filter the error log between StartDate and EndDate
SortOrder: We can specify ASC (Ascending) or DSC (descending) for sorting purposes


*/



DROP TABLE IF EXISTS #tmp
GO
CREATE TABLE #tmp (id INT IDENTITY PRIMARY KEY NOT NULL, [LogDate] datetime, [ProcessInfo] nvarchar(12), [Text] nvarchar(3999) )
TRUNCATE TABLE #tmp
INSERT #tmp
EXEC sys.xp_readerrorlog 
						0, -- 4
						1,
						N'',
						N'',
						N'2022-06-22 06:00:00',
						N'2022-09-22 16:23:16.190',
						N'desc'


SELECT * FROM #tmp
WHERE text LIKE '%availability%' OR text like '%JobVisionDB%'
ORDER BY LogDate asc


-------- Linked-Server -------------------------------------------------------------------------
USE [master]
GO
EXEC master.dbo.sp_serveroption @server=N'172.16.40.50,2828', @optname=N'rpc', @optvalue=N'true'
EXEC master.dbo.sp_serveroption @server = NULL, -- sysname
                                @optname = '',  -- varchar(35)
                                @optvalue = N'' -- nvarchar(128)

GO

EXEC sys.sp_addlinkedserver @server = NULL,     -- sysname
                            @srvproduct = N'',  -- nvarchar(128)
                            @provider = N'',    -- nvarchar(128)
                            @datasrc = N'',     -- nvarchar(4000)
                            @location = N'',    -- nvarchar(4000)
                            @provstr = N'',     -- nvarchar(4000)
                            @catalog = NULL,    -- sysname
                            @linkedstyle = NULL -- bit


---------- SQL Text & Query Plan -------------------------------------------------------------------------------------

SELECT 
	dbid,
	objectid,
	number,
	encrypted,
	text
FROM sys.dm_exec_sql_text(0x03005B00061F8C070735CE00B5AE0000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000)

SELECT 
	dbid,
	objectid,
	number,
	encrypted,
	query_plan
FROM sys.dm_exec_query_plan(0x0600430033C9070DB03161780B02000001000000000000000000000000000000000000000000000000000000)
/*
ROW	Column name		Data type		Description
---	-----------		---------		-----------
1	dbid			smallint		ID of database.

									For ad hoc and prepared SQL statements, the ID of the database where the statements were compiled.
2	objectid		int				ID of object.

									Is NULL for ad hoc and prepared SQL statements.
3	number			smallint		For a numbered stored procedure, this column returns the number of the stored procedure. For more information, see sys.numbered_procedures (Transact-SQL).

									Is NULL for ad hoc and prepared SQL statements.
4	encrypted		bit				1 = SQL text is encrypted.

									0 = SQL text is not encrypted.
5	text			nvarchar(max)	Text of the SQL query.

									Is NULL for encrypted objects.
*/

--======== Update job step ============================================================
USE [msdb]
GO
EXEC msdb.dbo.sp_update_jobstep @job_name = 'move_nc_indexes_to_another_filegroup', @step_id=1 , 
		@command=N''
GO


--============ resource pool ==========================================================

EXEC sp_xtp_bind_db_resource_pool 'IMOLTP_DB', 'Pool_IMOLTP'

EXEC sp_xtp_unbind_db_resource_pool 'IMOLTP_DB', 'Pool_IMOLTP'


-------- Read XEL files -------------------------------------------------------------------------------
SELECT  
xml_data.value('(event/@name)[1]','varchar(max)') AS 'Name'  
,xml_data.value('(event/@package)[1]','varchar(max)') AS 'Package'  
,xml_data.value('(event/@timestamp)[1]','datetime') AS 'Time'  
,xml_data.value('(event/data[@name=''state'']/value)[1]','int') AS 'State'  
,xml_data.value('(event/data[@name=''state_desc'']/text)[1]','varchar(max)') AS 'State Description'  
,xml_data.value('(event/data[@name=''failure_condition_level'']/value)[1]','int') AS 'Failure Conditions'  
,xml_data.value('(event/data[@name=''node_name'']/value)[1]','varchar(max)') AS 'Node_Name'  
,xml_data.value('(event/data[@name=''instancename'']/value)[1]','varchar(max)') AS 'Instance Name'  
,xml_data.value('(event/data[@name=''creation time'']/value)[1]','datetime') AS 'Creation Time'  
,xml_data.value('(event/data[@name=''component'']/value)[1]','varchar(max)') AS 'Component'  
,xml_data.value('(event/data[@name=''data'']/value)[1]','varchar(max)') AS 'Data'  
,xml_data.value('(event/data[@name=''info'']/value)[1]','varchar(max)') AS 'Info'  
FROM  
 ( SELECT object_name AS 'event'  
  ,CONVERT(xml,event_data) AS 'xml_data'  
  FROM sys.fn_xe_file_target_read_file('C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Log\SQLNODE1_MSSQLSERVER_SQLDIAG_0_129936003752530000.xel',NULL,NULL,NULL)   
)   
AS XEventData  
ORDER BY Time;  



SELECT  
xml_data.value('(event/@name)[1]','varchar(max)') AS 'Name'  
,xml_data.value('(event/@timestamp)[1]','datetime') AS 'Time'  
,xml_data.value('(event/data[@name=''node_name'']/value)[1]','varchar(max)') AS 'Node_Name'  
,xml_data.value('(event/data[@name=''component'']/value)[1]','varchar(max)') AS 'Component'  
,xml_data.value('(event/data[@name=''data'']/value)[1]','varchar(max)') AS 'Data'  

FROM  
 ( SELECT object_name AS 'event'  
  ,CONVERT(xml,event_data) AS 'xml_data'  
  FROM sys.fn_xe_file_target_read_file('\\DB1\C$\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Log\DB1_MSSQLSERVER_SQLDIAG_0_133186248491990000.xel',NULL,NULL,NULL)   
)   
AS XEventData  
ORDER BY Time;  

---------------------------------------------------------------------------------

SELECT * FROM sys.dm_os_enumerate_filesystem('\\DB1\C$\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Log\','*.xel')
WHERE last_write_time > '2023-01-19 21:30:00'
ORDER BY creation_time

-------- Jobs -------------------------------------------------------------------
EXEC msdb..sp_help_job
EXEC msdb..sp_help_jobactivity
EXEC msdb..[sp_help_jobhistory]
EXEC msdb..[sp_get_composite_job_info]
EXECUTE master.sys.xp_sqlagent_enum_jobs

EXEC msdb.dbo.sp_start_job @job_name = NULL,    -- sysname
                           @job_id = NULL,      -- uniqueidentifier
                           @error_flag = 0,     -- int
                           @server_name = NULL, -- sysname
                           @step_name = NULL,   -- sysname
                           @output_flag = 0     -- int

EXEC msdb.dbo.sp_stop_job @job_name = NULL,           -- sysname
                          @job_id = NULL,             -- uniqueidentifier
                          @originating_server = NULL, -- sysname
                          @server_name = NULL         -- sysname
