-- =============================================
-- Author:		<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:		<2021.03.11>
-- Description:		<Backup Website>
-- =============================================

-- For information please refer to the README.md

USE [master]
GO
create or alter procedure sp_drop_login_dependencies
	@LoginName sysname,
	@DropLogin bit = 0,
	@DroppedLoginSID varbinary(85) OUTPUT
as
begin
	
	Declare @LoginSID varbinary(85)
	declare @GuestLogin sysname

	set @LoginName = (select name from sys.server_principals where name like ('%'+@LoginName) and type in ('S','U'))


	-- select len(newid())
	set @GuestLogin = replace(('Guest_'+@LoginName+'_'+left(cast(newid() as nvarchar(36)),6)),'\','-')

	--------------- create login to transfer jobs to
	declare @sql0 nvarchar(max)='
	create login '+quotename(@GuestLogin)+' with password = N'''+cast(newid() as nvarchar(36))+'''
	DENY CONNECT SQL TO '+quotename(@GuestLogin)+'
	ALTER LOGIN '+quotename(@GuestLogin)+' DISABLE
	'
	
	exec (@sql0)

	--select @GuestLogin
	if @LoginName is null
		raiserror('The login name specified does not exist server wide.',16,1)

	select @LoginSID = suser_sid(@LoginName)
	-- select suser_sid('sa')
	-- select suser_sname(0x01)

	-------------- Deny connect to sql to current login before dropping it
	declare @sql1 nvarchar(500) = '

	DENY CONNECT SQL TO '+quotename(@LoginName)+'

	ALTER LOGIN '+quotename(@LoginName)+' DISABLE

	'
	exec (@sql1)

	-------------- Killing existing sessions of current login before dropping it
	DECLARE @sql2 NVARCHAR(MAX) = ''

	SELECT @sql2 += 'KILL ' + CONVERT(VARCHAR(11), session_id) + ';'
	FROM sys.dm_exec_sessions
	WHERE security_id = @LoginSID
	EXEC (@sql2)

	-------------- Revoking ownerships of current login of databases before dropping it
	declare @sql3 nvarchar(max) = ''
	select @sql3 += 'alter authorization on database::'+name+' to '+quotename(suser_sname(0x01))+char(10)
	from sys.databases where owner_sid = @LoginSID
	exec (@sql3)

	-------------- Revoking ownerships of current login of jobs before dropping it
	declare @sql4 nvarchar(max)=''

	select @sql4 += 'EXEC msdb.dbo.sp_update_job @job_id=N'''+cast(job_id as nvarchar(36))+''', 
							@owner_login_name=N'''+@GuestLogin+''', @enabled=0'+char(10)
	from msdb.dbo.sysJobs
	where owner_sid = @LoginSID
	exec(@sql4)

	-------------- Revoking ownerships of current login of Server Roles before dropping it
	declare @sql5 nvarchar(max)=''

	select @sql5 += 'ALTER AUTHORIZATION ON SERVER ROLE::'+quotename(sp2.name)+' TO '+quotename(suser_sname(0x01))+char(10)
	from sys.server_principals sp1 join sys.server_principals sp2 on sp1.principal_id = sp2.owning_principal_id
	where sp1.name = @LoginName
	exec (@sql5)

	-------------- Finally dropping the login
	if (@DropLogin = 1)
	begin
		declare @sql6 nvarchar(200)
		set @sql6 = 'drop login '+quotename(@LoginName)
		exec (@sql6)
		set @DroppedLoginSID = @LoginSID
	end
end
GO

