select (exec msdb.dbo.sp_help_jobschedule @job_id = 'A1B17FAD-9DAD-4512-B8B6-766FE7BFD22B') from msdb..sysjobs


select * from msdb..sysjobs_view

exec msdb.dbo.sp_help_job
exec msdb..sp_help_jobcount @schedule_id = 8
exec msdb..sp_help_jobschedule

select * from msdb..sysjobschedules
exec msdb..sp_help_schedule
select @@trancount

begin tran
begin tran
begin tran
commit

declare @sql nvarchar(max)='
dbcc checkdb('''+db_name()+''') with no_infomsgs'

exec (@sql)

select FORMAT( 'sunday', 'd', 'de-de' ) 'German'  

select name from sys.all_objects where name like '%vlf%'
select name from sys.all_objects where name like '%log%'

select CURRENT_TIMESTAMP

select DATALENGTH('ds'), DATALENGTH(11), DATALENGTH(N'ds'), DATALENGTH(1.1), DATALENGTH(0.11)

select nullif(' ','                ')

select len(''),len('    '),len('                      ')	-- all are zero as expected

SELECT TRIM('#! ' FROM '    #SQL Tutorial!    ') AS TrimmedString;

SELECT TRANSLATE('Jooooker', 'o', 'b');		-- not replace, but similiar

SELECT TRANSLATE('3*[2+1]/{8-4}', '[]{}', '()()');


SELECT [name], s.database_id,
COUNT(l.database_id) AS 'VLF Count',
SUM(vlf_size_mb) AS 'VLF Size (MB)',
SUM(CAST(vlf_active AS INT)) AS 'Active VLF',
SUM(vlf_active*vlf_size_mb) AS 'Active VLF Size (MB)',
COUNT(l.database_id)-SUM(CAST(vlf_active AS INT)) AS 'In-active VLF',
SUM(vlf_size_mb)-SUM(vlf_active*vlf_size_mb) AS 'In-active VLF Size (MB)'
FROM sys.databases s
CROSS APPLY sys.dm_db_log_info(s.database_id) l
GROUP BY [name], s.database_id
ORDER BY 'VLF Count' DESC
GO