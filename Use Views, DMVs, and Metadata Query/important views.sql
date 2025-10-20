SELECT DISTINCT TYPE, type_desc FROM sys.all_objects

SELECT * FROM sys.all_objects WHERE name LIKE 'orders%'
SELECT * FROM sys.schemas
SELECT * FROM sys.triggers
SELECT * FROM sys.server_triggers

SELECT * FROM sys.databases
--Database States:
--0 = ONLINE
--1 = RESTORING
--2 = RECOVERING 1
--3 = RECOVERY_PENDING 1		-- Me:Alert Raising
--4 = SUSPECT					-- Me:Alert Raising
--5 = EMERGENCY 1
--6 = OFFLINE 1
--7 = COPYING 2
--10 = OFFLINE_SECONDARY 2

SELECT COUNT(*) FROM sys.databases WHERE state IN (3,4)

--Note: For Always On databases, query the database_state or database_state_desc columns of sys.dm_hadr_database_replica_states.

--1 Applies to: SQL Server (starting with SQL Server 2008) and Azure SQL Database
--2 Applies to: Azure SQL Database Active Geo-Replication

SELECT * FROM sys.database_files

SELECT * FROM sys.filegroups

SELECT * FROM sys.all_columns

SELECT * FROM master.sys.sysaltfiles

SELECT * FROM sys.systypes

SELECT * FROM msdb.dbo.sysJobs

SELECT * FROM master..sysmessages

SELECT * FROM msdb..suspect_pages

SELECT * FROM sysfilegroups

SELECT * FROM sys.filegroups

SELECT DISTINCT severity FROM master..sysmessages
ORDER BY severity

SELECT * FROM sys.partition_schemes

SELECT * FROM sys.partition_functions

SELECT * FROM sys.partitions WHERE object_id = OBJECT_ID('sales.orders')

-- schema owner:
SELECT s.*,p.name FROM sys.schemas s JOIN sys.database_principals p
ON p.principal_id = s.principal_id

-------- Query ---------------------------------------------------
SELECT * FROM sys.dm_exec_query_stats WHERE sql_handle=0x030005007E7D3C2580AECC00F7B0000001000000000000000000000000000000000000000000000000000000
SELECT TOP 10 * FROM sys.dm_exec_procedure_stats WHERE object_id=OBJECT_ID ('dbo.USP_InsertIntoPersons')
SELECT * FROM sys.dm_exec_cached_plans WHERE plan_handle=0x050005007E7D3C25E002FE6D2002000001000000000000000000000000000000000000000000000000000000

-- collation related -----------------------------------------------

SELECT SERVERPROPERTY('collation')

SELECT name, COLLATIONPROPERTY(name, 'CodePage') AS Code_Page, description
FROM sys.fn_HelpCollations()
WHERE COLLATIONPROPERTY(name, 'CodePage') = 1252


SELECT * FROM sys.fn_helpcollations()
WHERE name LIKE 'Persian_100%'
--and name like '%AS%'
AND name LIKE '%CI%'
AND name LIKE '%AI%'

SELECT * FROM sys.syslanguages
WHERE msglangid = 1252

EXEC sp_helplanguage;

select *, COLLATIONPROPERTY(name,'CodePage') [Code Page] from sys.fn_helpcollations() where name like 'Persian%'

SELECT DATABASEPROPERTYEX('Co-BDOODDB','Collation')
SELECT DATABASEPROPERTYEX('CandoDB','Updateability')	-- READ_ONLY | READ_WRITE

-----------------------------------------------------------------

select j.name ,* from msdb.dbo.sysjobhistory jh
join msdb.dbo.sysjobs j
on jh.job_id = j.job_id
where sql_severity > 0

select * from sysjobhistory where message like 'The job failed.%'

-----------------------------------------------------------------


EXEC sys.sp_spaceused @objname = N''                   -- nvarchar(776)
                      --,@updateusage = ''                -- varchar(5)
                      --,@mode = ''                       -- varchar(11)
                      --,@oneresultset = NULL             -- bit
                      --,@include_total_xtp_storage = NULL -- bit

select * from sys.dm_db_index_usage_stats

declare @DatabaseId smallint, @ObjectId int, @IndexId int, @PartitionNumber int, @Mode nvarchar(20)
select *  from sys.dm_db_index_physical_stats(@DatabaseId,@ObjectId,@IndexId,@PartitionNumber,@Mode)

select object_name(object_id) obj_name,* from sys.indexes

select db_name(4)
GO-------------------------------------------------------------------------------------------------------------
--- show server roles with server roles' owners
-- Server Role	| Role Id	| Owner
SELECT r1.name AS [Name], r1.principal_id AS [ID], r.name as [Owner] FROM sys.server_principals r join sys.server_principals r1 on r.principal_id = r1.owning_principal_id WHERE (r1.type ='R') ORDER BY [Name] ASC

--- show server principals and their roles
-- Login	|	Member of
SELECT p.name [Login Name],p2.name [Member of] 
FROM sys.server_principals p JOIN sys.server_role_members m
ON p.principal_id = m.member_principal_id
JOIN sys.server_principals p2
ON m.role_principal_id = p2.principal_id
LEFT JOIN 
	(
		SELECT 'a.momen' name
		UNION ALL
		SELECT 'r.yekta' name
		UNION ALL
		SELECT 'a.shabani'
		UNION ALL
		SELECT 'a.arani'
		
	) dt 
ON p.name LIKE ('%'+dt.name)
WHERE	p2.name='sysadmin' AND dt.name IS NULL AND p.is_disabled = 0 AND 
		p.name NOT IN	(
							'NT SERVICE\SQLWriter',
							'NT SERVICE\Winmgmt',
							'NT SERVICE\MSSQLSERVER',
							'NT SERVICE\SQLSERVERAGENT',
							'JOBVISION\SQLServer',
							'AppSql',
							'JVSQLAdmin',
							'SQLServer',
							'sa'
						)
		AND p.name LIKE '%.%'

SELECT name schema_name, schema_id, USER_NAME(principal_id) FROM sys.schemas


SELECT * FROM sys.server_principals

SELECT * FROM sys.database_principals

SELECT * FROM sys.syslogins

GO-------------------------------------------------------------------------------------------------------------

SELECT APP_NAME() -- Microsoft SQL Server Management Studio - Query

DBCC SQLPERF(LOGSPACE)
USE "DB_NAME"
SELECT * FROM sys.dm_db_log_info(DB_ID())
SELECT * FROM sys.dm_db_log_stats(DB_ID())
SELECT * FROM sys.dm_db_log_space_usage
DBCC loginfo()

-- memory related -------------------------------------------------------
-- Current Memory Allocation:
SELECT
(total_physical_memory_kb/1024) AS Total_OS_Memory_MB,
(available_physical_memory_kb/1024)  AS Available_OS_Memory_MB
FROM sys.dm_os_sys_memory;

SELECT  
(physical_memory_in_use_kb/1024) AS Memory_used_by_Sqlserver_MB,  
(locked_page_allocations_kb/1024) AS Locked_pages_used_by_Sqlserver_MB,  
(total_virtual_address_space_kb/1024) AS Total_VAS_in_MB,
process_physical_memory_low,  
process_virtual_memory_low  
FROM sys.dm_os_process_memory;


dbcc memorystatus

-------------- Current Memory Utilization:
SELECT 
	CEILING(physical_memory_kb/1048576.0) Total_Physical_Memory_GB,
	CEILING(committed_kb/1048576.0) SQL_Used_Memory_GB,
	CEILING(committed_target_kb/1048576.0) SQL_Target_Memory_GB,
	FLOOR(available_physical_memory_kb/1048576.0) OS_Avail_Memory_GB,
	CEILING(CONVERT(INT,value_in_use)/1024.0) Max_SQLServer_Memory_GB,
	CEILING(physical_memory_kb/1048576.0-CONVERT(INT,value_in_use)/1024.0) Memory_Left_To_OS_GB,
	--system_high_memory_signal_state,
	--system_low_memory_signal_state,
	system_memory_state_desc
FROM sys.dm_os_sys_info, sys.dm_os_sys_memory,sys.configurations WHERE name like 'Max Server Memory%'

SELECT 
	physical_memory_kb/1048576.0 Total_Physical_Memory_GB,
	committed_kb/1048576.0 SQL_Target_Memory_GB,
	committed_target_kb/1048576.0 SQL_Target_Memory_GB,
	available_physical_memory_kb/1048576.0 OS_Avail_Memory_GB,
	CONVERT(INT,value_in_use)/1024.0 Max_SQLServer_Memory_GB,
	physical_memory_kb/1048576.0-CONVERT(INT,value_in_use)/1024.0 Memory_Left_To_OS_GB,
	system_memory_state_desc
FROM sys.dm_os_sys_info, sys.dm_os_sys_memory,sys.configurations WHERE name like 'Max Server Memory%'

SELECT * FROM sys.dm_os_sys_memory
SELECT * FROM sys.dm_os_memory_objects

SELECT
	sqlserver_start_time,
	cpu_count,
	physical_memory_kb/1048576.0 Total_Physical_Memory_GB,
	virtual_memory_kb/1048576.0 Total_Virtual_Memory_GB,
	(committed_kb/1048576.0) SQL_Used_Memory_GB,
	(committed_target_kb/1048576.0) SQL_Target_Memory_GB
FROM sys.dm_os_sys_info

SELECT * FROM sys.all_columns WHERE name LIKE '%stolen%'



SELECT * from sys.dm_os_sys_info
--------------

SELECT sql_memory_model_desc FROM sys.dm_os_sys_info;


SELECT * FROM sys.dm_os_process_memory;

SELECT
  physical_memory_in_use_kb/1024 AS sql_physical_memory_in_use_MB,
   large_page_allocations_kb/1024 AS sql_large_page_allocations_MB,
   locked_page_allocations_kb/1024 AS sql_locked_page_allocations_MB,
   virtual_address_space_reserved_kb/1024 AS sql_VAS_reserved_MB,
   virtual_address_space_committed_kb/1024 AS sql_VAS_committed_MB,
   virtual_address_space_available_kb/1024 AS sql_VAS_available_MB,
   page_fault_count AS sql_page_fault_count,
   memory_utilization_percentage AS sql_memory_utilization_percentage,
   process_physical_memory_low AS sql_process_physical_memory_low,
   process_virtual_memory_low AS sql_process_virtual_memory_low
FROM sys.dm_os_process_memory;

SELECT * FROM sys.configurations WHERE name LIKE '%mem%'

SELECT * FROM sys.dm_os_buffer_descriptors

SELECT * FROM sys.dm_os_memory_brokers

SELECT * FROM sys.tables WHERE is_memory_optimized = 1

SELECT * FROM sys.resource_governor_resource_pools
SELECT * FROM sys.dm_resource_governor_resource_pools
SELECT used_memory_kb*100.0/max_memory_kb FROM sys.dm_resource_governor_resource_pools
SELECT * FROM sys.resource_governor_workload_groups

----- classifier function info
SELECT * FROM sys.resource_governor_configuration
SELECT * FROM sys.dm_resource_governor_configuration
---------------------
USE master
SELECT 
		classifier_function_id,
      object_schema_name(classifier_function_id,1) AS [schema_name],  
      object_name(classifier_function_id,1) AS [function_name]  
FROM sys.dm_resource_governor_configuration  
WHERE classifier_function_id <> 0;
---------------------


------ ram usage percentage -----------------------------------------------
SELECT CEILING(total_physical_memory_kb/1024.0/1024) RamSize_GB,(100-available_physical_memory_kb*100.0/total_physical_memory_kb) FROM sys.dm_os_sys_memory
--WHERE (100-available_physical_memory_kb*100.0/total_physical_memory_kb)<80



GO-------------------------------------------------------------------------

SELECT scheduler_id, cpu_id, status, is_online
FROM sys.dm_os_schedulers

SELECT scheduler_id, cpu_id, status, is_online 
FROM sys.dm_os_schedulers 
WHERE status = 'VISIBLE ONLINE'


---------- xp file --------------------------------------------------------------------------
SELECT name FROM master.sys.all_objects
WHERE name LIKE '%xp%file%'

--xp_delete_file
--xp_delete_files
--xp_copy_file
--xp_copy_files
--xp_fileexist

---------- Find user tables that have specific column name ----------
USE CandoDB

SELECT t.name [Table Name], c.name [Column Name]
FROM sys.tables t JOIN sys.all_columns c
ON t.object_id = c.object_id
WHERE c.name LIKE '%address%' 
AND C.NAME NOT LIKE '%AddressID'

-- table: column names, length, type with types GO-------------------------------------------------------------------------------

USE Northwind

SELECT c.name
	   ,max_length
	   ,TYPE_NAME(system_type_id) + ISNULL(
											CASE 
												WHEN TYPE_NAME(system_type_id) IN ('nchar','nvarchar') THEN '(' + 
													CASE max_length 
														WHEN -1 THEN 'max' 
														ELSE CAST(max_length/2 AS NVARCHAR) 
													END+')'
												WHEN TYPE_NAME(system_type_id) IN ('char','varchar','binary','varbinary') THEN '(' + 
													CASE max_length 
														WHEN -1 THEN 'max' 
														ELSE CAST(max_length AS NVARCHAR) 
													END+')'
												--ELSE '(' + 
												--	CASE max_length 
												--		WHEN -1 THEN 'max' 
												--		ELSE CAST(max_length AS NVARCHAR)
												--	END+')' 
											END
										   ,'') [type]		
FROM sys.tables t JOIN sys.all_columns c
ON t.object_id = c.object_id
--where t.object_id = object_id('test')

SELECT is_persisted
FROM sys.computed_columns
WHERE name = 'TotalValue';
---------------------------------------------

SELECT IS_SRVROLEMEMBER('sysadmin') * 1 +IS_SRVROLEMEMBER('serveradmin') * 2 +IS_SRVROLEMEMBER('setupadmin') * 4 +IS_SRVROLEMEMBER('securityadmin') * 8 +IS_SRVROLEMEMBER('processadmin') * 16 +IS_SRVROLEMEMBER('dbcreator') * 32 +IS_SRVROLEMEMBER('diskadmin') * 64+ IS_SRVROLEMEMBER('bulkadmin') * 128
---------------------------------------------
SELECT
(@@microsoftversion / 0x1000000) & 0xff AS [VersionMajor]
---------------------------------------------
SELECT ISNULL(CONNECTIONPROPERTY('local_net_address'),'localhost') AS [Server IP],
		@@servername AS ServerName,
		SERVERPROPERTY('productmajorversion') AS MSSQL_Version



---------------------------------------------

SELECT * FROM sys.syslanguages;
go

SET LANGUAGE US_English
SELECT DATENAME(dw, GETDATE()) day, DATENAME(mm, GETDATE()) month, GETDATE() date

SET LANGUAGE Turkish
SELECT DATENAME(dw, GETDATE()) day, DATENAME(mm, GETDATE()) month, GETDATE() date

SET LANGUAGE French
SELECT DATENAME(dw, GETDATE()) day, DATENAME(mm, GETDATE()) month, GETDATE() date

SET LANGUAGE German
SELECT DATENAME(dw, GETDATE()) day, DATENAME(mm, GETDATE()) month, GETDATE() date

SET LANGUAGE Italian
SELECT DATENAME(dw, GETDATE()) day, DATENAME(mm, GETDATE()) month, GETDATE() date

SET LANGUAGE Russian
SELECT DATENAME(dw, GETDATE()) day, DATENAME(mm, GETDATE()) month, GETDATE() date

select datename(WEEKDAY,'2021-09-08') test
--------------------------------------------------------

select * from sys.external_languages
select * from sys.external_language_files

--------------------------------------------------------

select * from sys.syspermissions

--------------------------------------------------------

SELECT dec.local_net_address
FROM sys.dm_exec_connections AS dec
WHERE dec.session_id = @@SPID;

--------------------------------------------------------
select * from sys.configurations
SELECT * FROM sys.configurations WHERE value <> value_in_use

/*
EXEC sys.sp_configure N'show advanced options', N'1'  RECONFIGURE WITH OVERRIDE
GO
EXEC sys.sp_configure N'max server memory (MB)', N'3001'
GO
RECONFIGURE WITH OVERRIDE
GO
EXEC sys.sp_configure N'show advanced options', N'0'  RECONFIGURE WITH OVERRIDE
GO
*/

EXEC sys.sp_configure N'show advanced options', N'1'  RECONFIGURE WITH OVERRIDE
DROP table IF EXISTS #t
CREATE TABLE #t (name nvarchar(35),minimum int,maximum int,config_value int,run_value int)
insert into #t
EXEC sp_configure ;
select name from #t where name like '%mem%' and name not like '%member%'

----- Performance Counters: ------------------------------------------

SELECT [object_name],
[counter_name],
[cntr_value] FROM sys.dm_os_performance_counters
WHERE [object_name] LIKE '%Manager%'
AND [counter_name] = 'Page life expectancy'

----- Constriants ----------------------------------------------------

SELECT * FROM sys.default_constraints
SELECT * FROM sys.check_constraints
SELECT * FROM sys.key_constraints
SELECT * FROM sys.foreign_key_columns
SELECT * FROM sys.foreign_keys
SELECT * FROM sys.sysforeignkeys

SELECT [Co-JobVisionDB]..OBJECT_NAME(parent_object_id),* FROM [Co-JobVisionDB].sys.foreign_keys

GO-------------------------------------------------------------------------

SELECT f.physical_device_name,s.user_name FROM msdb.dbo.backupset s
JOIN msdb..backupmediafamily f
ON f.media_set_id = s.media_set_id
WHERE database_name='co-modeldb' ORDER BY backup_finish_date desc

GO-------------------------------------------------------------------------
--Viewing the events that cause a trigger to fire:

SELECT TE.*  
FROM sys.trigger_events AS TE  
JOIN sys.triggers AS T ON T.object_id = TE.object_id  
WHERE T.name = 'CompanyNewEntry' --AND T.parent_class = 0;  
GO

GO-------------------------------------------------------------------------
-- Database Mail:

SELECT SCHEMA_NAME(schema_id),* FROM msdb.sys.all_objects  WHERE name LIKE '%exist%'

SELECT TOP 10 * FROM msdb..sysmail_allitems ORDER BY mailitem_id DESC


GO-------------------------------------------------------------------------

SELECT * FROM sys.dm_os_performance_counters   
WHERE object_name LIKE '%SQL%Deprecated Features%'; 

GO-------------------------------------------------------------------------

select sys.fn_hadr_is_primary_replica('JobVisionDB')
SELECT sys.fn_hadr_backup_is_preferred_replica('JobVisionDB')

GO------ Last executed scripts -------------------------------------------------------------------

SELECT TOP 5 execquery.last_execution_time AS [Date Time], execsql.text AS [Script] FROM sys.dm_exec_query_stats AS execquery
outer APPLY sys.dm_exec_sql_text(execquery.sql_handle) AS execsql
WHERE text LIKE '%availability%'
ORDER BY execquery.last_execution_time DESC

SELECT i.name,o.* FROM sys.indexes i JOIN sys.all_objects o
ON o.object_id = i.object_id
WHERE i.type = 2 AND o.is_ms_shipped = 0--CONVERT(DATE,o.create_date) = '2022-07-17'

GO------ Get Free Disk Spaces Drive --------------------------------------------------------------------

SELECT --@@servername [Server Name],
	(volume_mount_point),
	logical_volume_name,
  total_bytes/1048576 as Size_in_MB, 
  available_bytes/1048576 as Free_in_MB,
  ((available_bytes * 1.0)/(total_bytes) * 100) as FreePercentage,
  100-(select ((available_bytes * 1.0)/(total_bytes) * 100)) AS OccupiedPercentage
FROM sys.master_files AS f CROSS APPLY 
  sys.dm_os_volume_stats(f.database_id, f.file_id)
group by volume_mount_point, logical_volume_name, total_bytes, 
  available_bytes order by 1


SELECT 
	(volume_mount_point),
  total_bytes/1048576/1024.0 as Size_in_GB 
  
  
FROM sys.master_files AS f CROSS APPLY 
  sys.dm_os_volume_stats(f.database_id, f.file_id)
group by volume_mount_point, logical_volume_name, total_bytes, 
  available_bytes order by 1

exec xp_fixeddrives
EXEC sys.sp_MSSharedFixedDisk
SELECT * FROM sys.dm_os_enumerate_fixed_drives
SELECT * FROM sys.fn_servershareddrives()
SELECT full_filesystem_path FROM sys.dm_os_enumerate_filesystem('\\172.16.40.35\Backup\Backup\Database','*.bak')
SELECT * FROM sys.dm_os_volume_stats(1,1)
SELECT * FROM sys.dm_enumerate_blobdirectory('d:\')

exec xp_fixeddrives


SELECT 
  ((available_bytes * 1.0)/(total_bytes) * 100) as FreePercentage
FROM sys.master_files AS f CROSS APPLY 
  sys.dm_os_volume_stats(f.database_id, f.file_id)
  WHERE volume_mount_point = 'M:\'
group by volume_mount_point, logical_volume_name, total_bytes, 
  available_bytes



GO------ To be read ------------------------------------------------------------------------------

SELECT TOP 1000 execquery.last_execution_time AS [Date Time], execsql.text AS [Script] FROM sys.dm_exec_query_stats AS execquery
CROSS APPLY sys.dm_exec_sql_text(execquery.sql_handle) AS execsql
ORDER BY execquery.last_execution_time DESC

GO------ MSDB mail -------------------------------------------------------------------------------

USE msdb
GO

SELECT TOP 100 * FROM msdb.dbo.sysmail_mailitems ORDER BY mailitem_id desc

GO------ Good instance data-----------------------------------------------------------------------

SELECT * FROM sys.dm_server_services --

SELECT * FROM sys.dm_hadr_database_replica_states --
SELECT * from sys.availability_replicas

SELECT * FROM sys.dm_hadr_physical_seeding_stats

SELECT * FROM sys.dm_os_sys_memory

SELECT * FROM sys.dm_os_process_memory

SELECT * FROM sys.dm_io_virtual_file_stats()
SELECT * FROM sys.dm_os_memory_allocations
SELECT * FROM sys.dm_os_memory_clerks
SELECT DISTINCT type FROM sys.dm_os_memory_objects
SELECT * FROM sys.dm_os_server_diagnostics_log_configurations
SELECT * FROM sys.dm_os_sys_info --
SELECT container_type_desc, * FROM sys.dm_os_sys_info



SELECT * FROM sys.dm_os_virtual_address_dump
SELECT * FROM sys.dm_server_audit_status --
SELECT  filename,
        creation_time,
        size_in_bytes/1024.0/1024 FROM sys.dm_server_memory_dumps
SELECT * FROM sys.dm_xe_objects ORDER BY name
SELECT * FROM sys.dm_xe_sessions
SELECT * FROM sys.fn_dbslog(NULL,NULL)
union
SELECT * FROM sys.fn_full_dblog(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)
union
SELECT TOP 1 * FROM sys.fn_dblog(NULL,NULL)
SELECT * FROM sys.fulltext_index_fragments
SELECT * FROM sys.sequences 
SELECT * FROM sys.server_event_sessions--
SELECT * FROM sys.server_file_audits --
SELECT * FROM sys.service_broker_endpoints
SELECT * FROM sys.sysaltfiles
sys.sysbrickfiles
sys.syscscolsegments
--SELECT * FROM sys.syscsdictionaries
SELECT * FROM sys.sysdevices
SELECT * FROM sys.sysfiles
--SELECT * FROM sys.sysfos
--SELECT * FROM sys.sysftinds
--SELECT * FROM sys.sysprufiles
SELECT * FROM sys.trace_events
SELECT * FROM sys.trace_columns
SELECT * FROM sys.traces WHERE is_default = 0--
SELECT s.login_name, s.status FROM sys.traces t JOIN sys.dm_exec_sessions s ON s.session_id=t.reader_spid  WHERE is_default = 0--
SELECT * FROM sys.dm_exec_sessions

----------- Find objects: specific column name -------------
USE Northwind

select o.name [Object Name], c.name [Column Name]
from sys.all_objects o join sys.all_columns c
on o.object_id = c.object_id
where --type_desc like '%user_table%' and --'view%'
--o.is_ms_shipped = 0 and
c.name like '%filestream%'


SELECT SCHEMA_NAME(ao.schema_id)+'.'+OBJECT_NAME(ac.object_id) [Object Name],ao.type_desc ,ac.name [Column Name] 
FROM sys.all_columns ac JOIN sys.all_objects ao
ON ao.object_id = ac.object_id  WHERE ac.name LIKE '%lock%'

SELECT SCHEMA_NAME(ao.schema_id)+'.'+
OBJECT_NAME(ao.object_id) [Object Name], ao.type_desc [Object Type] 
FROM sys.all_objects ao
WHERE name LIKE '%trace%' AND ao.type_desc IN ('VIEW','USER_TABLE')

USE JobVisionDB
SELECT SCHEMA_NAME(ao.schema_id),
OBJECT_NAME(ao.object_id) [Object Name], ao.type_desc [Object Type] 
FROM sys.all_objects ao
WHERE name LIKE '%job%' AND ao.type_desc = 'USER_TABLE'
ORDER BY [Object Name]

SELECT * FROM msdb.sys.all_objects WHERE name LIKE '%restore%'

SELECT object_id,
default_object_id,
is_column_set,
rule_object_id,
--graph_type_desc,
is_sparse, is_hidden,
is_masked, is_filestream,
is_column_set,
precision,
--generated_always_type_desc,
encryption_type_desc,
encryption_algorithm_name,
column_encryption_key_id,
column_encryption_key_database_name
FROM sys.all_columns
--WHERE generated_always_type_desc <> 'NOT_APPLICABLE'


-- Schema	|	Object Name	|	Owner
SELECT SCHEMA_NAME(ao.schema_id)+'.'+OBJECT_NAME(object_id) [Object Name], dp.name [Database Principal Name]
FROM sys.all_objects ao JOIN sys.database_principals dp
ON dp.principal_id = ao.principal_id

SELECT * FROM sys.all_objects WHERE principal_id IS NOT NULL
ALTER AUTHORIZATION ON customers TO [public_user]

SELECT fixed_drive_path, drive_type_desc, 
CONVERT(DECIMAL(18,2), free_space_in_bytes/1073741824.0) AS [Available Space (GB)]
FROM sys.dm_os_enumerate_fixed_drives WITH (NOLOCK) OPTION (RECOMPILE);


----- Cluster and AG and hadr -------------------------------------------------------------------

SELECT * FROM sys.availability_replicas
SELECT * FROM sys.availability_groups
SELECT * FROM sys.dm_hadr_availability_replica_states
SELECT primary_replica,* FROM sys.dm_hadr_availability_group_states

SELECT ar.replica_server_name, ars.role_desc FROM sys.availability_replicas ar FULL JOIN sys.dm_hadr_availability_replica_states ars
ON ar.replica_id = ars.replica_id




SELECT * FROM sys.availability_replicas
SELECT * FROM sys.dm_hadr_database_replica_cluster_states
-- 
SELECT 
	ar.replica_server_name,
	DATEDIFF(MILLISECOND,last_redone_time,last_hardened_time)/1000.0 [Redo Lag (s)],
	ar.availability_mode_desc,
	dhdrs.* 
FROM sys.dm_hadr_database_replica_states dhdrs JOIN sys.availability_replicas ar
ON ar.replica_id = dhdrs.replica_id
ORDER BY 2 DESC

SELECT 
	dhdrs.last_redone_time,
	DB_NAME(dhdrs.database_id) DBName,
	ar.replica_server_name,
	DATEDIFF(MILLISECOND,last_redone_time,last_hardened_time)/1000.0 [Redo Lag (s)],
	tt.[Elapsed DD:HH:MM:SS.ms] redo_lag_time,
	ar.availability_mode_desc,
	dhdrs.* 
FROM sys.dm_hadr_database_replica_states dhdrs JOIN sys.availability_replicas ar
ON ar.replica_id = dhdrs.replica_id
OUTER APPLY fn_udtvf_elapsedtime(last_redone_time,last_hardened_time) tt
ORDER BY 2 DESC

;WITH reps1 AS
(
	SELECT
		ROW_NUMBER() OVER (ORDER BY dhdrs.synchronization_state DESC) row,
		ar.replica_server_name,
		ar.replica_id,
		dhdrs.last_commit_time
		--dhdrs.synchronization_state		/*2: SYNCHRONIZED 1:SYNCHRONIZING*/
	FROM sys.dm_hadr_database_replica_states dhdrs JOIN sys.availability_replicas ar
	ON ar.replica_id = dhdrs.replica_id
	--WHERE dhdrs.group_database_id = (SELECT group_database_id FROM sys.databases WHERE name='AG-SQLAdministrationDB')
	--WHERE dhdrs.synchronization_health =2 /*HEALTHY*/
),
availability_replicas as		-- finds availability replicas which AG-SQLAdministrationDB database is not far behind in synchronization
(
	SELECT 
		reps1.replica_server_name,
		reps1.replica_id				
	FROM reps1
	--WHERE ABS(DATEDIFF_BIG(SECOND,(SELECT last_commit_time FROM reps1 WHERE row = 1),last_commit_time)) < '+CONVERT(VARCHAR,@AGSQLAdministrationDB_tolerable_lag_s)+'
	--ORDER BY reps1.replica_server_name
),	
cte AS
(
	SELECT
		ROW_NUMBER() OVER (PARTITION BY dhdrs.group_database_id ORDER BY dhdrs.synchronization_state DESC) row,
		ar.replica_server_name,
		dhdrs.group_database_id,
		dhdrs.last_commit_time
		--dhdrs.synchronization_state		/*2: SYNCHRONIZED 1:SYNCHRONIZING*/
	FROM sys.dm_hadr_database_replica_states dhdrs JOIN availability_replicas ar
	ON ar.replica_id = dhdrs.replica_id
	WHERE dhdrs.synchronization_health =2 /*HEALTHY*/
	--ORDER BY dhdrs.group_database_id,ar.replica_server_name		
)
SELECT		-- finds AG databases of all replicas which are not so much behind in synchronization.
	cte.replica_server_name,
	cte.group_database_id,
	ABS(DATEDIFF_BIG(SECOND,dt.last_commit_time,cte.last_commit_time)) data_lag_seconds
FROM cte join
	(SELECT * FROM cte WHERE cte.row = 1) dt
ON dt.group_database_id = cte.group_database_id --AND dt.row = cte.row
ORDER BY cte.group_database_id, cte.replica_server_name



SELECT * FROM sys.dm_hadr_db_threads
--
SELECT * FROM sys.dm_hadr_availability_replica_cluster_nodes

SELECT * FROM sys.dm_hadr_cached_database_replica_states

SELECT * FROM sys.dm_hadr_cached_replica_states
--
SELECT * FROM sys.dm_hadr_cluster

SELECT * FROM sys.dm_hadr_cluster_networks

SELECT * FROM sys.dm_hadr_cluster_members

SELECT * FROM sys.availability_group_listener_ip_addresses

SELECT * FROM sys.availability_group_listeners

SELECT * FROM sys.dm_os_cluster_properties
--
SELECT * FROM sys.availability_groups_cluster
--
SELECT * FROM sys.dm_cluster_endpoints

SELECT cluster_name, quorum_type_desc, quorum_state_desc
FROM sys.dm_hadr_cluster WITH (NOLOCK) OPTION (RECOMPILE);
--
SELECT * FROM sys.dm_hadr_ag_threads
--
--SELECT * FROM sys.fn_hadr_distributed_ag_database_replica()	-- (lag_id, database_id)

--SELECT * FROM sys.fn_hadr_distributed_ag_replica()	-- lag_id, replica_id
-- primary replica per AG
SELECT primary_replica, at.name ag_name 
FROM sys.dm_hadr_availability_group_states ags JOIN sys.dm_hadr_ag_threads at
ON ags.group_id=at.group_id

SELECT ag.name AS AG_Name,*
FROM sys.availability_groups ag
JOIN sys.dm_hadr_availability_replica_states ar
ON ag.group_id = ar.group_id
WHERE ar.role_desc = 'PRIMARY';



DBCC FREEPROCCACHE;



-----------------------------------------------------------------------------------

SELECT 
DATEDIFF(DAY,last_request_start_time,GETDATE()),
DATEDIFF(SECOND,last_request_start_time,GETDATE()),
DATEDIFF(MILLISECOND,last_request_start_time,GETDATE()),
DATEDIFF(NANOSECOND,last_request_start_time,GETDATE())
FROM sys.dm_exec_sessions
WHERE session_id <> @@spid

----------------------------------------------------------------------------------
-- Todo: headblocker, sp name, job name, contains delay

SELECT * FROM sys.dm_os_ring_buffers
SELECT
         cpu_idle = record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int'),
         cpu_sql = record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')
FROM (
         SELECT TOP 1 CONVERT(XML, record) AS record
         FROM sys.dm_os_ring_buffers
         WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
         AND record LIKE '% %'
		 ORDER BY TIMESTAMP DESC
) AS cpu_usage

EXEC dbWarden.srv.SpViewImportantCounter
--------------------------------------------------------------------------------------------

SELECT 
	text,
	r.cpu_time*100000.0/DATEDIFF_BIG(MICROSECOND,start_time,SYSDATETIME()) [CPU Time%*all cores],
	r.cpu_time/1000.0 [CPU Time ms],
	dop,
	DATEDIFF_BIG(MICROSECOND,start_time,GETDATE())/1000000.0 [Execution Time s]
	--,*
FROM sys.dm_exec_requests r JOIN sys.dm_exec_sessions s
ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(sql_handle)
WHERE s.session_id<>@@SPID AND s.is_user_process = 1
ORDER BY 2 desc 


SELECT * FROM sys.dm_exec_requests WHERE session_id=@@SPID


SELECT
	s.session_id
	, dt.transaction_id, DB_NAME(s.database_id) db_name
	, database_transaction_begin_time
	, database_transaction_log_bytes_used/1024.0/1024/1024 db_tran_log_used_gb
	, database_transaction_log_bytes_reserved/1024.0/1024/1024 db_tran_log_resrv_gb
	, database_transaction_log_bytes_used_system/1024.0/1024/1024 db_sys_tran_log_used_gb
	--s.cpu_time,
	--r.cpu_time,
	, GETDATE() [Report Date]
	, s.session_id [Session ID]	  
	, r.request_id
	, CONVERT(DECIMAL(12,3),IIF(s.status='RUNNING',DATEDIFF_BIG(MINUTE,s.last_request_start_time,SYSDATETIME()),NULL)) [Elapsed Time minute]
	, CONVERT(DECIMAL(10,3),IIF(s.status='RUNNING',DATEDIFF_BIG(MINUTE,s.last_request_start_time,SYSDATETIME())/60.0,NULL)) [Elapsed Time hour]
	, s.host_name [Host Name Connected to Server]
	, s.original_login_name [Original Login Name]
	, s.login_name [Impersonated Login Name]
	, s.nt_user_name [Windows/Domain Account Name]
	, s.status [Status]
	, DB_NAME(s.database_id) [Database Name]
	, DB_NAME(s.authenticating_database_id) [Authenticating Database Name]
	, s.program_name [Application Name]
	, IIF(s.program_name LIKE 'SQLAgent - TSQL JobStep (Job %',
			(SELECT name FROM msdb..sysjobs WHERE job_id=(SELECT CONVERT(VARCHAR(100),CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100), SUBSTRING(program_name,30,34),1))) FROM sys.dm_exec_sessions WHERE session_id=s.session_id))
			, NULL
		 ) [Job Name]
	, IIF(r.blocking_session_id<>0, 'Yes', 'No') [Is Being Blocked?]	
	, IIF(r.blocking_session_id<>0, r.blocking_session_id, NULL) [Session Blocking This Session]
	, s.open_transaction_count [Open Transaction Count]
	, s.cpu_time/1000.0 session_cpu_time
	, r.cpu_time/1000.0 [request_cpu_time]
	--(SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE')
	, CONVERT(DECIMAL(14,3),r.cpu_time)*100.0/((CONVERT(DECIMAL(17,0),DATEDIFF_BIG(MICROSECOND,s.last_request_start_time,SYSDATETIME()))/1000.0-CONVERT(DECIMAL(14,3),r.wait_time))*(SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE')) [active average CPU Usage %]
	--, r.cpu_time*100.0/IIF(DATEDIFF_BIG(MILLISECOND,s.last_request_start_time,ISNULL(s.last_request_end_time,SYSDATETIME()))=0,-r.cpu_time*100.0,DATEDIFF_BIG(MILLISECOND,s.last_request_start_time,ISNULL(s.last_request_end_time,SYSDATETIME()))) [CPU Usage %]
	--, DATEDIFF(MILLISECOND,s.last_request_start_time,SYSDATETIME())
	, r.logical_reads [Logical Reads]
	, r.reads [Reads]
	, r.writes [Writes]
	, (s.memory_usage * 8) [Memory Usage (KB)]
	, r.granted_query_memory
	, qmg.granted_memory_kb
	, r.wait_type [Wait Type]
	, r.wait_time [Wait Time]
	, r.last_wait_type [Last Wait Type]
	, s.deadlock_priority [Deadlock Priority]
	, c.client_net_address [Client Address]
	, c.client_tcp_port [Client Outgoing Port]
	, s.client_interface_name [Client Connection Driver]
	, IIF(c.net_transport='session', 'MARS', c.net_transport) [Client Connection Protocol]
	, e.name [Endpoint]
	, r.estimated_completion_time [Estimated Completion Time]
	, r.percent_complete [Percent Complete]
	, r.dop [Degree of Parallelism]
	, r.nest_level [Code Nest Level]
	--, (SELECT name FROM msdb.dbo.sysschedules WHERE schedule_id =r.scheduler_id) [Schedule Name]	
	, r.command [Command Type]
	, sh.text [Script Text]
	, rsh.text [Last Script Text]
	, qp.query_plan
	, r.plan_handle
	, r.row_count [Row Count]
	, s.is_user_process
		
FROM
sys.dm_exec_sessions s 
LEFT JOIN sys.dm_exec_connections c
ON s.session_id = c.session_id
LEFT JOIN sys.dm_exec_requests r
ON s.session_id = r.session_id
LEFT JOIN sys.endpoints e
ON s.endpoint_id = e.endpoint_id
LEFT JOIN sys.dm_exec_query_memory_grants qmg
ON c.session_id = qmg.session_id
LEFT JOIN sys.dm_tran_session_transactions st
ON st.session_id = s.session_id
LEFT JOIN sys.dm_tran_database_transactions dt
ON dt.transaction_id = st.transaction_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) sh
OUTER APPLY sys.dm_exec_sql_text(r.statement_sql_handle) rsh
OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) qp
WHERE 
--s.is_user_process = 1 AND
--s.status IN ('running') AND
--r.command <> 'WAITFOR' AND
--r.blocking_session_id <> 0 and
(sh.text IS NULL OR sh.text <> 'sp_server_diagnostics')
--c.net_transport <> 'session' and
AND s.session_id <> @@spid 
ORDER BY [active average CPU Usage %] DESC, [Elapsed Time minute] DESC
    --s.memory_usage desc



SELECT
	st.session_id
	, dt.transaction_id, database_id
	, database_transaction_begin_time
	, database_transaction_log_bytes_used/1024.0/1024/1024 db_tran_log_used_gb
	, database_transaction_log_bytes_reserved/1024.0/1024/1024 db_tran_log_resrv_gb
	, database_transaction_log_bytes_used_system/1024.0/1024/1024 db_sys_tran_log_used_gb
	--, * 
FROM sys.dm_tran_database_transactions dt JOIN sys.dm_tran_session_transactions st
ON st.transaction_id = dt.transaction_id
WHERE database_transaction_type <> 3 AND database_transaction_begin_time IS NOT NULL



SELECT COUNT(CASE when blocking_session_id<>0 THEN 1 END) FROM sys.dm_exec_requests




--EXEC msdb..sp_stop_job @job_name = 'cdc.Co-JobVisionDB_capture'
--EXEC msdb..sp_start_job @job_name = 'cdc.Co-JobVisionDB_capture'
SELECT * FROM sys.dm_exec_sessions WHERE original_login_name LIKE '%hoss%'     
KILL 92
------------------ Monitor Jobs:

SELECT
	--s.cpu_time,
	--r.cpu_time,
	  GETDATE() [Report Date]
	, s.session_id [Session ID]	  
	, r.request_id
	, CONVERT(DECIMAL(10,2),DATEDIFF(MINUTE,s.last_request_start_time,GETDATE())) [Elapsed Time minute]
	, CONVERT(DECIMAL(8,2),DATEDIFF(MINUTE,s.last_request_start_time,GETDATE())/60.0) [Elapsed Time hour]
	, s.host_name [Host Name Connected to Server]
	, s.original_login_name [Original Login Name]
	, s.login_name [Impersonated Login Name]
	, s.nt_user_name [Windows/Domain Account Name]
	, s.status [Status]
	, DB_NAME(s.database_id) [Database Name]
	, DB_NAME(s.authenticating_database_id) [Authenticating Database Name]
	, s.program_name [Application Name]
	, IIF(s.program_name LIKE 'SQLAgent - TSQL JobStep (Job %',
			(SELECT name FROM msdb..sysjobs WHERE job_id=(SELECT CONVERT(VARCHAR(100),CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100), SUBSTRING(program_name,30,34),1))) FROM sys.dm_exec_sessions WHERE session_id=s.session_id))
			, NULL
		 ) [Job Name]
	, IIF(r.blocking_session_id<>0, 'Yes', 'No') [Is Being Blocked?]	
	, IIF(r.blocking_session_id<>0, r.blocking_session_id, NULL) [Session Blocking This Session]
	, s.open_transaction_count [Open Transaction Count]
	, r.cpu_time/1000.0 [req CPU Usage(sec)]
	, s.cpu_time/1000.0 [sess CPU Usage(sec)]
	--, r.cpu_time*100.0/DATEDIFF(MILLISECOND,s.last_request_start_time,GETDATE()) [CPU Usage %]
	--, DATEDIFF(MILLISECOND,s.last_request_start_time,GETDATE())
	, r.logical_reads [Logical Reads]
	, r.reads [Reads]
	, r.writes [Writes]
	, (s.memory_usage * 8) [Memory Usage (KB)]
	, r.granted_query_memory
	, qmg.granted_memory_kb
	, r.wait_type [Wait Type]
	, r.wait_time [Wait Time]
	, r.last_wait_type [Last Wait Type]
	, s.deadlock_priority [Deadlock Priority]
	, c.client_net_address [Client Address]
	, c.client_tcp_port [Client Outgoing Port]
	, s.client_interface_name [Client Connection Driver]
	, IIF(c.net_transport='session', 'MARS', c.net_transport) [Client Connection Protocol]
	, e.name [Endpoint]
	, r.estimated_completion_time [Estimated Completion Time]
	, r.percent_complete [Percent Complete]
	, r.dop [Degree of Parallelism]
	, r.nest_level [Code Nest Level]
	--, (SELECT name FROM msdb.dbo.sysschedules WHERE schedule_id =r.scheduler_id) [Schedule Name]	
	, r.command [Command Type]
	, rsh.text [Request Script Text]
	, rsh.text [Request Statement Text]
	, cmrsh.text [Connection Most Recent Text]
	, qp.query_plan
	, r.plan_handle
	, r.row_count [Row Count]
	, ~s.is_user_process [is ms process?]	
FROM
sys.dm_exec_sessions s 
LEFT JOIN sys.dm_exec_connections c
ON s.session_id = c.session_id
LEFT JOIN sys.dm_exec_requests r
ON s.session_id = r.session_id
LEFT JOIN sys.endpoints e
ON s.endpoint_id = e.endpoint_id
LEFT JOIN sys.dm_exec_query_memory_grants qmg
ON s.session_id = qmg.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) rsh
OUTER APPLY sys.dm_exec_sql_text(r.statement_sql_handle) rssh
OUTER APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) cmrsh
OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) qp
WHERE
--s.program_name LIKE 'SQLAgent - TSQL JobStep (Job %' AND
--s.is_user_process = 1 AND
--s.status = 'running' AND
--r.command <> 'WAITFOR' AND
--r.blocking_session_id <> 0 and
--sh.text <> 'sp_server_diagnostics' AND
--c.net_transport <> 'session' and
s.session_id <> @@spid --AND s.session_id=70 
ORDER BY	[sess CPU Usage(sec)] DESC,
			[Elapsed Time minute] DESC





			KILL 70

--Command Type	Script Text
--KILLED/ROLLBACK	xp_cmdshell







SELECT session_id, login_name, DB_Name(s.database_id), cpu_time, s.status, IIF(s.program_name LIKE 'SQLAgent - TSQL JobStep (Job %',
			(SELECT name FROM msdb..sysjobs WHERE job_id=(SELECT CONVERT(VARCHAR(100),CONVERT(UNIQUEIDENTIFIER,CONVERT(VARBINARY(100), SUBSTRING(program_name,30,34),1))) FROM sys.dm_exec_sessions WHERE session_id=s.session_id))
			, NULL
		 ) [Job Name]
FROM sys.dm_exec_sessions s WHERE s.login_name NOT IN ('a.momen') AND status='running' ORDER BY cpu_time desc

SELECT 
	text,*
FROM sys.dm_exec_requests r OUTER APPLY sys.dm_exec_sql_text(r.statement_sql_handle)
WHERE r.session_id=299

SELECT * FROM sys.dm_exec_sessions WHERE session_id=299


SELECT CASE transaction_isolation_level 
    WHEN 0 THEN 'Unspecified' 
    WHEN 1 THEN 'ReadUncommitted' 
    WHEN 2 THEN 'ReadCommitted' 
    WHEN 3 THEN 'Repeatable' 
    WHEN 4 THEN 'Serializable' 
    WHEN 5 THEN 'Snapshot' END AS TRANSACTION_ISOLATION_LEVEL 
FROM sys.dm_exec_sessions 
WHERE session_id = @@SPID

SELECT session_id, COUNT(session_id) FROM sys.dm_exec_requests GROUP BY session_id HAVING COUNT(session_id)>1
SELECT COUNT(*) FROM sys.dm_exec_requests GROUP BY session_id HAVING COUNT(*)>1
--SELECT s.session_id s, r.session_id r FROM sys.dm_exec_sessions s FULL JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
--WHERE s.session_id IS NULL AND r.session_id IS NOT NULL
SELECT s.session_id s, COUNT(r.session_id) count FROM sys.dm_exec_sessions s FULL JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
GROUP BY s.session_id

SELECT * FROM msdb..sysjobsteps ORDER BY step_name ASC

SELECT * FROM (SELECT SUM(memory_usage) MemUsage1 FROM sys.dm_exec_sessions) dt1, (SELECT SUM(memory_usage) MemUsage2 FROM
sys.dm_exec_sessions s 
LEFT JOIN sys.dm_exec_connections c
ON s.session_id = c.session_id
LEFT JOIN sys.dm_exec_requests r
ON s.session_id = r.session_id
LEFT JOIN sys.endpoints e
ON s.endpoint_id = e.endpoint_id
LEFT JOIN sys.dm_exec_query_memory_grants qmg
ON c.session_id = qmg.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) sh
OUTER APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) rsh
WHERE 
--s.is_user_process = 1 AND
--s.status = 'running' AND
--r.command <> 'WAITFOR' AND
--sh.text <> 'sp_server_diagnostics' AND
s.session_id <> @@spid 
) dt2
--SELECT * FROM sys.sysprocesses ORDER BY memusage desc
SELECT 1655/651.0

KILL 146

SELECT * FROM sys.endpoints

SELECT * FROM sys.dm_os_schedulers

SELECT * FROM sys.dm_exec_sessions WHERE is_user_process=1 AND status='running' AND session_id<>@@spid

SELECT * FROM sys.dm_exec_query_memory_grants


--------- Partition, data space, filegroup etc. ---------------------------------------------------------------------------

SELECT * FROM sys.filegroups
SELECT * FROM sys.data_spaces

EXEC sp_executesql N'SELECT

        CASE WHEN ((SELECT tblidx.is_memory_optimized FROM sys.tables tblidx WHERE tblidx.object_id = idx.object_id)=1 or
        (SELECT ttidx.is_memory_optimized FROM sys.table_types ttidx WHERE ttidx.type_table_object_id = idx.object_id)=1)
        THEN ISNULL((SELECT ds.name FROM sys.data_spaces AS ds WHERE ds.type=''FX''), N'''')
        ELSE CASE WHEN ''FG''=dsidx.type THEN dsidx.name ELSE N'''' END
        END
       AS [FileGroup]
FROM
sys.tables AS tbl
INNER JOIN sys.indexes AS idx ON 
        idx.object_id = tbl.object_id and (idx.index_id < @_msparam_0  or (tbl.is_memory_optimized = 1 and idx.index_id = (select min(index_id) from sys.indexes where object_id = tbl.object_id)))
      
LEFT OUTER JOIN sys.data_spaces AS dsidx ON dsidx.data_space_id = idx.data_space_id
WHERE
(tbl.name=@_msparam_1 and SCHEMA_NAME(tbl.schema_id)=@_msparam_2)',N'@_msparam_0 nvarchar(4000),@_msparam_1 nvarchar(4000),@_msparam_2 nvarchar(4000)',@_msparam_0=N'2',@_msparam_1=N'Customers',@_msparam_2=N'dbo'



-----------------------------------------------------------------------------------------------------------

--DATABASE states:
--0 = ONLINE
--1 = RESTORING
--2 = RECOVERING 1
--3 = RECOVERY_PENDING 1
--4 = SUSPECT
--5 = EMERGENCY 1
--6 = OFFLINE 1
--7 = COPYING 2
--10 = OFFLINE_SECONDARY 2

------------- Assembly: ------------------------------------------------------------------------

SELECT * FROM sys.assemblies
SELECT * FROM sys.assembly_files
SELECT * FROM sys.assembly_modules
SELECT * FROM sys.assembly_references
SELECT * FROM sys.assembly_types

------------ Missing Index --------------------------------------------------------------------

SELECT name
FROM sys.all_objects
WHERE
    name LIKE 'dm_db_missing_index\_%' { ESCAPE '\' } 
    --AND type = 'V'
ORDER BY name;

SELECT * FROM sys.dm_db_missing_index_details
SELECT * FROM sys.dm_db_missing_index_groups

SELECT * FROM sys.dm_db_missing_index_group_stats
SELECT * FROM sys.dm_db_missing_index_group_stats_query

SELECT text,last_statement_sql_handle,sq.* FROM sys.dm_db_missing_index_group_stats_query sq
CROSS APPLY sys.dm_exec_sql_text(last_sql_handle) t

SELECT * FROM sys.dm_db_missing_index_columns(17693) -- index handle and not index_group_handle
SELECT * FROM sys.dm_db_missing_index_columns(17694) -- wrong!
/* Columns:
column_id	column_name		column_usage
---------	-----------		------------
*/

-- This shows that the both columns index_group_handle and index_handle are unique alltogether
SELECT COUNT(*),COUNT(DISTINCT index_group_handle), COUNT(DISTINCT index_handle) FROM sys.dm_db_missing_index_groups




SELECT 
	OBJECT_NAME(objectid) object_name_c,
	dbid,
	objectid,
	number,
	encrypted,
	OBJECT_ID('[dbo].[usp_Ats_Candidate_CandidateProfileBaseInfo]') oiotoitt_c,
	text
FROM sys.dm_exec_sql_text(0x03005B00061F8C070735CE00B5AE0000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000)


SELECT 
	OBJECT_NAME(objectid) object_name_c,
	dbid,
	objectid,
	number,
	encrypted,
	OBJECT_ID('[dbo].[usp_Ats_Candidate_CandidateProfileBaseInfo]') oiotoitt_c,
	text
FROM sys.dm_exec_sql_text(0x020000003126B901497EFBA9352E6E498F1E2E14DEE6176500000000000000000000000000000000000000000000000000000000000000000000000000000000)

------- all_sql_modules ---------------------------------------------------------------------------------------

SELECT 
	o.type_desc,
	sm.* 
FROM sys.all_sql_modules sm JOIN sys.all_objects o
ON o.object_id = sm.object_id


DECLARE @definition NVARCHAR(max)
SELECT @definition = definition
FROM sys.all_sql_modules
WHERE OBJECT_ID = 571149080

PRINT @definition

SELECT * FROM sys.sysindexes
SELECT * FROM sys.system_views
SELECT * FROM sys.sysusers
SELECT * FROM sys.syscurconfigs
SELECT * FROM sys.syspermissions

----------- Workers -------------------------------------------------------------

SELECT last_wait_type,COUNT(last_wait_type) FROM sys.dm_os_workers GROUP BY last_wait_type ORDER BY 2 DESC
SELECT * FROM sys.dm_os_workers

-- Microsoft Query
SELECT   
    t1.session_id,  
    CONVERT(varchar(10), t1.status) AS status,  
    CONVERT(varchar(15), t1.command) AS command,  
    CONVERT(varchar(10), t2.state) AS worker_state,  
    w_suspended =   
      CASE t2.wait_started_ms_ticks  
        WHEN 0 THEN 0  
        ELSE   
          t3.ms_ticks - t2.wait_started_ms_ticks  
      END,  
    w_runnable =   
      CASE t2.wait_resumed_ms_ticks  
        WHEN 0 THEN 0  
        ELSE   
          t3.ms_ticks - t2.wait_resumed_ms_ticks  
      END  
  FROM sys.dm_exec_requests AS t1  
  INNER JOIN sys.dm_os_workers AS t2  
    ON t2.task_address = t1.task_address  
  CROSS JOIN sys.dm_os_sys_info AS t3  
  WHERE t1.scheduler_id IS NOT NULL;  

-- Cando1 default Max Worker Threads 512, CPUCores 8, Arch 64-bit
SELECT *,
		(512+(dt.CPUCores-4)*16) RecommendedMaxWorker
FROM
(
	SELECT (SELECT COUNT(*) FROM sys.dm_os_workers) WorkersCount,max_workers_count, (SELECT COUNT(*) FROM sys.dm_os_threads) threads,(SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status='VISIBLE ONLINE') CPUCores FROM sys.dm_os_sys_info
) dt


SELECT CHECKSUM('a'),ASCII('a'),CHECKSUM('11111'),CHECKSUM(11111)

/*
| Logical processors |		   32-bit architecture		  |		    64-bit architecture        |
| ------------------ | ---------------------------------- | ---------------------------------- |
|					 |									  |									   |
|		 <= 4 		 |			   	  256				  |					512				   |
|	> 4 and <= 64 	 |	 256 + (logical CPUs - 4) * 8 	  |    512 + (logical CPUs - 4) * 16   |
|		 > 64 		 |	 256 + (logical CPUs - 4) * 32    |	   512 + (logical CPUs - 4) * 32   |
*/
----------- Transaction Related -----------------------------------------
SELECT [Transaction SID],* FROM sys.fn_dblog(NULL,NULL)


SELECT * FROM sys.dm_tran_session_transactions


SELECT * FROM sys.dm_dw_tran_manager_commit_cache

SELECT * FROM sys.dm_tran_commit_table

SELECT * FROM sys.dm_tran_global_transactions_log
------------------------------
SELECT
	st.session_id
	, dt.transaction_id, database_id
	, database_transaction_begin_time
	, database_transaction_log_bytes_used/1024.0/1024/1024 db_tran_log_used_gb
	, database_transaction_log_bytes_reserved/1024.0/1024/1024 db_tran_log_resrv_gb
	, database_transaction_log_bytes_used_system/1024.0/1024/1024 db_sys_tran_log_used_gb
	--, * 
FROM sys.dm_tran_database_transactions dt JOIN sys.dm_tran_session_transactions st
ON st.transaction_id = dt.transaction_id
WHERE database_transaction_type <> 3 AND database_transaction_begin_time IS NOT NULL


SELECT * FROM sys.dm_tran_aborted_transactions

SELECT * FROM sys.dm_tran_active_snapshot_database_transactions

SELECT * FROM sys.dm_tran_active_transactions

SELECT * FROM sys.dm_tran_current_transaction

SELECT * FROM sys.dm_tran_global_transactions

DBCC OPENTRAN
------ Extended events ------------------------------------------------------

SELECT * FROM sys.dm_xe_session_targets

-- get xel file paths:
select s.name as session_name, convert(XML,t.target_data).value('(/EventFileTarget/File/@name)[1]', 'nvarchar(256)')
from sys.dm_xe_sessions as s
join sys.dm_xe_session_targets as t
on s.address = t.event_session_address
where t.target_name = 'event_file'


SELECT * FROM sys.dm_xe_object_columns
SELECT * FROM sys.dm_xe_objects
SELECT * FROM sys.dm_xe_packages
SELECT * FROM sys.dm_xe_session_event_actions
SELECT * FROM sys.dm_xe_session_events
SELECT * FROM sys.dm_xe_session_object_columns WHERE column_name = 'filename'

------- identify large transactions ------------------------------------------------------------
begin tran
SELECT database_transaction_log_bytes_used,* FROM sys.dm_tran_database_transactions
SELECT * FROM sys.dm_tran_active_transactions

commit tran
---- query to identify redo from undo log record and the previous and next values using fn_dblog function
SELECT 
[Current LSN], 
[Operation], 
[AllocUnitName], 
[Transaction ID], 
[Begin Time], 
[Transaction Name], 
CONVERT (INT, [RowLog Contents 0]) AS RedoRecord, 
CONVERT (INT, [RowLog Contents 1]) AS UndoRecord
FROM fn_dblog (NULL, NULL) 
WHERE 
AllocUnitName = 'dbo.YourTableName' 
AND Operation = 'LOP_MODIFY_ROW'
AND [Transaction Name] = 'UPDATE';

SELECT 
[Current LSN], 
[Operation], 
[AllocUnitName], 
[Transaction ID], 
[Begin Time], 
[Transaction Name], 
CONVERT (INT, [RowLog Contents 0]) AS RedoRecord, 
CONVERT (INT, [RowLog Contents 1]) AS UndoRecord
FROM fn_dblog (NULL, NULL) 
WHERE 
AllocUnitName = 'dbo.YourTableName' 
AND Operation = 'LOP_MODIFY_ROW'
AND [Transaction Name] = 'UPDATE';



--------- index key columns of a table -------------------------------
sp_helpindex
SELECT distinct i.name, c.name FROM sys.indexes i join sys.index_columns ic
ON ic.index_id = i.index_id
JOIN sys.columns c
ON c.object_id = i.object_id and c.column_id = ic.column_id
WHERE i.object_id = object_id('STP_OfflineOrders') and ic.object_id = object_id('STP_OfflineOrders') and index_column_id = 1 /*and i.index_id<>1*/ and key_ordinal = 1
--and c.name = 'AgreementId'
ORDER by i.name

--------- xe extended events trace junction map table ----------------


USE MASTER;
GO
SELECT DISTINCT
    tb.trace_event_id,
    te.name            AS 'Event Class',
    em.package_name    AS 'Package',
    em.xe_event_name   AS 'XEvent Name',
    tb.trace_column_id,
    tc.name            AS 'SQL Trace Column',
    am.xe_action_name  AS 'Extended Events action'
FROM
              sys.trace_events         te
    LEFT JOIN sys.trace_xe_event_map   em ON te.trace_event_id  = em.trace_event_id
    LEFT JOIN sys.trace_event_bindings tb ON em.trace_event_id  = tb.trace_event_id
    LEFT JOIN sys.trace_columns        tc ON tb.trace_column_id = tc.trace_column_id
    LEFT JOIN sys.trace_xe_action_map  am ON tc.trace_column_id = am.trace_column_id
ORDER BY te.name, tc.name

---------------------------------------------------------------------

sp_spaceused
sp_help

---------------------------------------------------------------------

EXEC msdb.dbo.sp_stop_job


----------- XML 1: --------------------------------------------------
<TASK_LOCAL_STORAGE>
  <STORAGE_ENGINE>
    <LATCH_TRACKING type="CountOnly" />
  </STORAGE_ENGINE>
</TASK_LOCAL_STORAGE>

Ex:
SELECT xmlCol.value('(/TASK_LOCAL_STORAGE/STORAGE_ENGINE/LATCH_TRACKING/@type)[1]', 'varchar(20)') AS type
FROM yourTable

--Msg 2203, Level 16, State 1, Line 12
--XQuery [value()]: Only 'http://www.w3.org/2001/XMLSchema#decimal?', 'http://www.w3.org/2001/XMLSchema#boolean?' or 'node()*' expressions allowed as predicates, found 'xs:string'


----------- XML 2: --------------------------------------------------

<Config xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <HighTimeSpan>600</HighTimeSpan>
  <HighEnabled>true</HighEnabled>
  <MediumTimeSpan>600</MediumTimeSpan>
  <MediumEnabled>true</MediumEnabled>
  <LowTimeSpan>600</LowTimeSpan>
  <LowEnabled>false</LowEnabled>
  <HighThreshold>0.5</HighThreshold>
  <MediumThreshold>0.3</MediumThreshold>
  <LowThreshold>0.85</LowThreshold>
</Config>

SELECT 
	dt.Name,
	dt.Description,
	dt._AlertType,	
	CASE NewXML.value('(/Config/HighEnabled)[1]'	,'nvarchar(max)') WHEN 'true' THEN NewXML.value('(/Config/HighThreshold)[1]'	,'nvarchar(max)') WHEN 'false' THEN 'Disabled' ELSE 'N/A' END [HighThreshold],
	CASE NewXML.value('(/Config/MediumEnabled)[1]'	,'nvarchar(max)') WHEN 'true' THEN NewXML.value('(/Config/MediumThreshold)[1]'	,'nvarchar(max)') WHEN 'false' THEN 'Disabled' ELSE 'N/A' END [MediumThreshold],
	CASE NewXML.value('(/Config/LowEnabled)[1]'		,'nvarchar(max)') WHEN 'true' THEN NewXML.value('(/Config/LowThreshold)[1]'		,'nvarchar(max)') WHEN 'false' THEN 'Disabled' ELSE 'N/A' END [LowThreshold],
	CASE NewXML.value('(/Config/HighEnabled)[1]'	,'nvarchar(max)') WHEN 'true' THEN NewXML.value('(/Config/HighTimeSpan)[1]'		,'nvarchar(max)') WHEN 'false' THEN 'Disabled' ELSE 'N/A' END [HighTimeSpan],
	CASE NewXML.value('(/Config/MediumEnabled)[1]'	,'nvarchar(max)') WHEN 'true' THEN NewXML.value('(/Config/MediumTimeSpan)[1]'	,'nvarchar(max)') WHEN 'false' THEN 'Disabled' ELSE 'N/A' END [MediumTimeSpan],
	CASE NewXML.value('(/Config/LowEnabled)[1]'		,'nvarchar(max)') WHEN 'true' THEN NewXML.value('(/Config/LowTimeSpan)[1]'		,'nvarchar(max)') WHEN 'false' THEN 'Disabled' ELSE 'N/A' END [LowTimeSpan],	
	dt.NewXML

FROM 
(
	SELECT
		at.Name,
		at.Description,
		_AlertType,	
		ac._Configuration,
		--CONVERT(XML,REPLACE(CONVERT(VARCHAR(MAX),_Configuration),'xmlns="v1"','')).value('(Config/HighEnabled)[1]','nvarchar(max)'),
		CONVERT(XML,REPLACE(CONVERT(VARCHAR(MAX),_Configuration),' xmlns="v1"','')) NewXML

	FROM config.AlertConfiguration ac JOIN alert.Alert_Type AT
	ON ac._AlertType = AT.AlertType
) dt


---------- Global Variables ---------------------------------------
SELECT
		@@SERVERNAME [SERVERNAME],		-- SQLServer Instance Name (SQL Server Network Name for FCI, rest of the cases HOSTNAME)
		@@SERVICENAME [SERVICENAME],
		@@REMSERVER [REMSERVER],
		@@TEXTSIZE [TEXTSIZE],
		@@TIMETICKS [TIMETICKS],
		@@TOTAL_ERRORS [TOTAL_ERRORS],
		@@ROWCOUNT [ROWCOUNT],
		@@TOTAL_READ [TOTAL_READ],
		@@TOTAL_WRITE [TOTAL_WRITE],
		@@TRANCOUNT [TRANCOUNT],
		@@VERSION [VERSION],
		@@CONNECTIONS [CONNECTIONS],
		@@CURSOR_ROWS [CURSOR_ROWS],
		@@DATEFIRST [DATEFIRST],
		@@ERROR [ERROR],
		@@IDLE [IDLE],
		@@IDENTITY [IDENTITY],
		@@LANGID [LANGID],
		@@LANGUAGE [LANGUAGE],
		@@DBTS [DBTS],				-- the last timestamp that has been used within a rowversion column in the scope of a database
		@@CPU_BUSY [CPU_BUSY],
		@@FETCH_STATUS [FETCH_STATUS],
		@@IO_BUSY [IO_BUSY],
		@@LOCK_TIMEOUT [LOCK_TIMEOUT],
		@@MAX_CONNECTIONS [MAX_CONNECTIONS],
		@@MAX_PRECISION [MAX_PRECISION],
		@@NESTLEVEL [NESTLEVEL],
		@@OPTIONS [OPTIONS],
		@@PACK_RECEIVED [PACK_RECEIVED],
		@@PACK_SENT [PACK_SENT],
		@@PACKET_ERRORS [PACKET_ERRORS],
		@@PROCID [PROCID],		-- the current module object_id
		@@SPID [SPID]

GO

CREATE OR ALTER PROC ttt
AS
BEGIN
	SELECT object_name(@@PROCID)
END
GO


EXEC ttt


---------- Server -------------------------------------------------

SELECT * FROM sys.servers
SELECT * FROM sys.sysservers

SELECT * FROM 

EXEC sys.sp_server_info @attribute_id = 0 -- int


EXEC sys.sp_helpserver @server = NULL,     -- sysname
                       @optname = '',      -- varchar(35)
                       @show_topology = '' -- varchar(1)

EXEC sys.sp_addlinkedserver @server = NULL,     -- sysname
                            @srvproduct = N'',  -- nvarchar(128)
                            @provider = N'',    -- nvarchar(128)
                            @datasrc = N'',     -- nvarchar(4000)
                            @location = N'',    -- nvarchar(4000)
                            @provstr = N'',     -- nvarchar(4000)
                            @catalog = NULL,    -- sysname
                            @linkedstyle = NULL -- bit

EXEC sys.sp_linkedservers

EXEC sys.sp_server_info @attribute_id = 0 -- int

EXEC sys.sp_linkedservers_rowset @srvname = NULL -- sysname

EXEC sys.sp_linkedservers_rowset2

EXEC sys.sp_server_diagnostics

EXEC sys.sp_start_flight_server

EXEC sys.sp_addserver @server = NULL,    -- sysname
                      @local = '',       -- varchar(10)
                      @duplicate_ok = '' -- varchar(13)

EXEC sys.sp_helpserver @server = NULL,     -- sysname
                       @optname = '',      -- varchar(35)
                       @show_topology = '' -- varchar(1)

EXEC sys.sp_serveroption @server = NULL, -- sysname
                         @optname = '',  -- varchar(35)
                         @optvalue = N'' -- nvarchar(128)

EXEC sys.sp_testlinkedserver

EXEC sys.fn_getserverportfromproviderstring @provider_str = NULL -- sysname

EXEC sys.sp_fido_glm_server_execute_batch

EXEC sys.sp_MSGetServerProperties

--------------------------------------------------------
SELECT * FROM sys.dm_os_hosts

--SELECT * FROM sys.dm_os_tasks
'
<TASK_LOCAL_STORAGE>
  <STORAGE_ENGINE>
    <LATCH_TRACKING type="CountOnly" />
  </STORAGE_ENGINE>
</TASK_LOCAL_STORAGE>
'

SELECT CONVERT(XML,task_local_storage).value('(/TASK_LOCAL_STORAGE/STORAGE_ENGINE[''cpu_time'']/value)[1]','VARCHAR(50)') 
FROM sys.dm_os_tasks


SELECT DISTINCT task_local_storage FROM sys.dm_os_tasks
SELECT DISTINCT task_state FROM sys.dm_os_tasks

---------------------------------------------------------------------
-- service accounts

SELECT        
	servicename,
	--startup_type,
	startup_type_desc,
	--status,
	status_desc,
	--process_id,
	--last_startup_time,
	service_account,
	REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(service_account,'@mofid.dc',''),'@emofid.com',''),'mofid.dc\',''),'emofid.com\',''),'@mofid',''),'@emofid',''),'mofid\',''),'emofid\','') [unqualified service_account],
	--filename, 
	--is_clustered,
	--cluster_nodename,
	instant_file_initialization_enabled
FROM sys.dm_server_services


-------------- Find files/directories with a specific name in non os windows drive 

SELECT fs.full_filesystem_path FROM 
(
	SELECT fixed_drive_path FROM sys.dm_os_enumerate_fixed_drives WHERE 
	drive_type = 3 AND
	LEN(REPLACE(fixed_drive_path,'C:',''))>=LEN(fixed_drive_path)
) fd 
CROSS APPLY  sys.dm_os_enumerate_filesystem(fd.fixed_drive_path,'traces') fs
WHERE
fs.is_directory = 1


--------------- Partition/Partitioning ---------------------------------------
------ View definition of partition function
SELECT 
pf.name AS PartitionFunctionName,
prs.value AS RangeValue,
prs.boundary_id AS BoundaryID
FROM 
sys.partition_functions AS pf
JOIN sys.partition_range_values AS prs
ON pf.function_id = prs.function_id
WHERE 
pf.name = 'YourPartitionFunctionName';


------ more detailed view that includes the partition scheme and filegroup information, use an extended version of the query:
SELECT DISTINCT
ps.name AS PartitionSchemeName,
pf.name AS PartitionFunctionName,
fg.name AS FileGroupName,
prv.value AS RangeValue,
prv.boundary_id AS BoundaryID,
dds.destination_id
FROM 
sys.partition_schemes AS ps
JOIN sys.partition_functions AS pf
ON ps.function_id = pf.function_id
JOIN sys.destination_data_spaces AS dds
ON ps.data_space_id = dds.partition_scheme_id
JOIN sys.filegroups AS fg
ON dds.data_space_id = fg.data_space_id
LEFT JOIN sys.partition_range_values AS prv
ON pf.function_id = prv.function_id
ORDER BY 
PartitionSchemeName,
PartitionFunctionName,
dds.destination_id



------ view partition function boundaries for a table partitioned by year quarter --------
SELECT 
pf.name AS PartitionFunctionName,
CEILING(CONVERT(INT,prs.value)/100)/100+(((CEILING(CONVERT(INT,prs.value)/100)%100)/4)+1)/4 year,
IIF((((CEILING(CONVERT(INT,prs.value)/100)%100)/4)+2)%4<>0,
		(((CEILING(CONVERT(INT,prs.value)/100)%100)/4)+2)%4,4) quarter,
prs.boundary_id AS BoundaryID
FROM 
sys.partition_functions AS pf
JOIN sys.partition_range_values AS prs
ON pf.function_id = prs.function_id




----------- find non-matching directory contents -------------------------
------ find non-matching names
DECLARE @dir1 NVARCHAR(256) = 'D:\1'
DECLARE @dir2 NVARCHAR(256) = 'D:\2'
SET @dir1 = TRIM(@dir1) SET @dir2=TRIM(@dir2) IF RIGHT(@dir1,1)<> '\' SET @dir1+='\' IF RIGHT(@dir2,1)<> '\' SET @dir2+='\' 

SELECT dir1.full_filesystem_path, dir2.full_filesystem_path 
FROM sys.dm_os_enumerate_filesystem(@dir1,'*') dir1 FULL JOIN
	 sys.dm_os_enumerate_filesystem(@dir2,'*') dir2
ON REPLACE(dir2.full_filesystem_path,@dir2,'') = REPLACE(dir1.full_filesystem_path,@dir1,'')
WHERE	dir1.full_filesystem_path IS NULL OR dir2.full_filesystem_path IS NULL
		AND ISNULL(dir1.level,0) = 0 AND ISNULL(dir2.level,0)=0
GO

------ find non-matching names and file sizes
DECLARE @dir1 NVARCHAR(256) = 'D:\1'
DECLARE @dir2 NVARCHAR(256) = 'D:\2'
SET @dir1 = TRIM(@dir1) SET @dir2=TRIM(@dir2) IF RIGHT(@dir1,1)<> '\' SET @dir1+='\' IF RIGHT(@dir2,1)<> '\' SET @dir2+='\' 

SELECT dir1.full_filesystem_path, dir2.full_filesystem_path 
FROM sys.dm_os_enumerate_filesystem(@dir1,'*') dir1 FULL JOIN
	 sys.dm_os_enumerate_filesystem(@dir2,'*') dir2
ON REPLACE(dir2.full_filesystem_path,@dir2,'') = REPLACE(dir1.full_filesystem_path,@dir1,'')
WHERE	--(dir1.full_filesystem_path IS NULL OR dir2.full_filesystem_path IS NULL) OR 
		dir1.size_in_bytes<>dir2.size_in_bytes

GO

---------------------------------------------------------------------------------
-- values clause example
SELECT 
	dtq.a value 
FROM
(VALUES (0331), (0631), (0930), (1230)) dtq (a)	

SELECT * FROM 
(
	SELECT 
		--dty.b*10000+
		dtq.a value 
	FROM
	(	VALUES (0331)	,(0631)	,(0930)	,(1230)	) dtq (a)
	
	--,(	VALUES	 (1397)	,(1398)	,(1399)	,(1400)	,(1401)	,(1402)	,(1403)	,(1404)	,(1405)	,(1406)	,(1407)	,(1408)	,(1409)	,(1410)	) dty (b)
) dt 
--FULL JOIN sys.partition_range_values prv
--ON prv.value = dt.value
--WHERE dt.value IS NULL OR prv.value IS NULL
ORDER BY 1
