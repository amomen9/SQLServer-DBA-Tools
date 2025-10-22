-- This script supports unicode carachters


-- =============================================
-- Author:		<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:		<2021.10.11>
-- Description:		See Documentation
-- =============================================

use master
go

create or alter procedure sp_restore_latest_backups_on_other_server
(
	@Source nvarchar(40) = '',						-- IPv4, IPv6, or hostname
	@Destination nvarchar(40) = '',					-- IPv4, IPv6, or hostname
	@DestinationUser nvarchar(128) = '',			-- Leave user and pass empty if on a domain, and source's SQL Server service account 
													-- must be an administrator on the target machine, Otherwise specify a username
													-- and password of an administrator of the target machine. Provide the username
													-- in full [Domain or Computer name\username] format. The destination user must
													-- also be a windows login and authorized to restore backups on the target SQL Server
	@DestinationPass nvarchar(1000) = ''
)
-------------------------------------------
as
begin
	---- variable control
	if len(isnull(@DestinationUser,'')) <> 0
	begin
		set @DestinationUser = '-u ' + @DestinationUser
		set @DestinationPass = '-p ' + @DestinationPass
	end

	if len(isnull(@Source,'')) = 0
		raiserror('A source must be specified',16,1)

	if len(isnull(@Destination,'')) = 0
		raiserror('A destination must be specified',16,1)

	drop table if exists #t

	;WITH T
	AS
	(
	SELECT  ROW_NUMBER() OVER (PARTITION BY Database_Name  ORDER BY Backup_Finish_Date DESC) AS Radif , Database_Name , media_set_id
	FROM msdb..BackupSet
	WHERE [Type] = 'D' 
	)
	SELECT QUOTENAME(T.database_name) dbname, '\\'+@Source+'\'+replace(BMF.physical_device_name,':','$') as [UNC Path]
	into #t
	FROM T INNER JOIN msdb..backupmediafamily BMF 
	  ON T.media_set_id = BMF.media_set_id
	WHERE T.Radif = 1
	ORDER BY 1

	drop table if exists #t2

	select 'psexec -i /accepteula \\'+@Destination+' '+@DestinationUser + ' ' + @DestinationPass + ' sqlcmd -Q "USE [master]; if (select name from sys.databases where name = '''+replace(replace(dbname,'[',''),']','')+''') is not null ALTER DATABASE '+dbname+' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; restore database '+dbname+' from disk = N'''+[UNC Path]+''' with replace; ALTER DATABASE '+dbname+' SET MULTI_USER; "' as Command
	into #t2
	from #t

	-- select * from #t2

	EXECUTE sp_configure 'show advanced options', 1; RECONFIGURE; EXECUTE sp_configure 'xp_cmdshell', 1; RECONFIGURE;

	--------- cursor to execute commands
	declare @command nvarchar(1000)
	declare @dbname sysname
	declare executioner cursor for select * from #t2
	open executioner
		fetch next from executioner into @command
		execute master..xp_cmdshell @command
		while @@FETCH_STATUS = 0
		begin
			fetch next from executioner into @command
			execute master..xp_cmdshell @command
		end 
	CLOSE executioner
	DEALLOCATE executioner
	------------------------------------

	EXECUTE sp_configure 'xp_cmdshell', 0; RECONFIGURE; EXECUTE sp_configure 'show advanced options', 0; RECONFIGURE;
end

go

------ sample execution

exec sp_restore_latest_backups_on_other_server
	@Source = '192.168.241.3',						-- IPv4, IPv6, or hostname
	@Destination = '192.168.241.100',				-- IPv4, IPv6, or hostname
	@DestinationUser = 'Ali-PC\Ali',				-- Leave user and pass empty if on a domain, and source's SQL Server service account 
													-- must be an administrator on the target machine, Otherwise specify a username
													-- and password of an administrator of the target machine. Provide the username
													-- in full [Domain or Computer name\username] format. The destination user must
													-- also be a windows login and authorized to restore backups on the target SQL Server
	@DestinationPass = 'P@$$W0rd'
