USE [master]
GO

create or alter trigger tr_sysad_ssms
on all server
for logon
as
begin
	SET NOCOUNT ON
	if ('sysadmin' not in (
						select lr.name as Server_RoleName
						from sys.server_role_members rm inner join sys.server_principals sp
						   on rm.member_principal_id = sp.principal_id 
						   inner join sys.server_principals lr
						   on rm.role_principal_id = lr.principal_id 
						where sp.name = ORIGINAL_LOGIN()
					  ) and APP_NAME() like 'Microsoft SQL Server Management Studio%'
		)
	begin
	
   	    RAISERROR('Only members of sysadmin fixed server role can login to this server via SSMS.',16,1)
		ROLLBACK TRAN;		
	end
end
go

enable trigger tr_sysad_ssms on all server
go

------------------------------- Time restriction for login 'TimeLimited' Trigger:
/*
	The user can only login between 6:00 A.M. and 5:00 P.M.
*/
-- Create login TimeLimited if not exists:

if ((select 1 from sys.syslogins where name = N'TimeLimited') is null)
	CREATE LOGIN [TimeLimited] WITH PASSWORD=N'1', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF
GO

------------------------------------------

create or alter trigger tr_time_restriction_for_TimeLimited
on all server
for logon
as
begin
	SET NOCOUNT ON
	if (ORIGINAL_LOGIN() = 'TimeLimited' and (datepart(hour, getdate())>17 or datepart(hour,getdate())<6)
		)
	begin	
   	    RAISERROR('You cannot login to this server at this time. Contact your Database Administrator.',16,1)
		ROLLBACK TRAN;		
	end
end
go

enable trigger tr_time_restriction_for_TimeLimited on all server
go

------- Connection Limit Trigger ----------------------------------

CREATE TRIGGER connection_limit_trigger  
ON ALL SERVER WITH EXECUTE AS N'login_test'  
FOR LOGON  
AS  
BEGIN  
IF ORIGINAL_LOGIN()= N'login_test' AND  
    (SELECT COUNT(*) FROM sys.dm_exec_sessions  
            WHERE is_user_process = 1 AND  
                original_login_name = N'login_test') > 3  
    ROLLBACK;  
END;  
GO

------- Test Trigger --------------------------------------------

CREATE OR alter TRIGGER Test_Logon_Trigger 
ON ALL SERVER --WITH EXECUTE AS N'sa'  
FOR LOGON  
AS  
BEGIN  
	PRINT SUSER_SNAME()
	PRINT ORIGINAL_LOGIN()
	SET TRAN ISOLATION LEVEL SERIALIZABLE
END;  
GO

enable trigger Test_Logon_Trigger on all server


------- Only Let me in!!!! --------------------------------------------

CREATE OR alter TRIGGER SU_Trigger 
ON ALL SERVER --WITH EXECUTE AS N'sa'  
FOR LOGON  
AS  
BEGIN  
	if (ORIGINAL_LOGIN() <> 'a.momen')
	begin	
   	    RAISERROR('You cannot login to this server at this time. Contact your Database Administrator.',16,1)
		ROLLBACK TRAN;		
	end
END;  
GO

enable trigger SU_Trigger on all SERVER
DISABLE TRIGGER SU_Trigger on all server

