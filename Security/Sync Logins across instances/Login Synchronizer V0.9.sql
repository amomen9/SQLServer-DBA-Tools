-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2023.01.16>
-- Latest Update Date:	<23.02.01>
-- Description:			<Synchronize Logins>
-- License:				<Please refer to the license file> 
-- =============================================

/*
USE [SQLAdministrationDB]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS InstanceLogins
GO

CREATE TABLE [dbo].[InstanceLogins](
	[LoginName] [sysname] NOT NULL,
	[PasswordPlain] [nvarchar](512) NULL,
	[Purpose] [varchar](50) NOT NULL,
	[AuthenticationType] [varchar](10) NULL,
	[SID]  AS (suser_sid([LoginName])),
	[PasswordHash]  AS (LoginProperty([LoginName],'PasswordHash')),
	[MegaProject] [varchar](50) NULL,
PRIMARY KEY CLUSTERED 
(
	[LoginName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 94, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[InstanceLogins] ADD  CONSTRAINT [DF__InstanceL__Purpo__4D2A7347]  DEFAULT ('Production') FOR [Purpose]
GO

ALTER TABLE [dbo].[InstanceLogins] ADD  CONSTRAINT [DF_InstanceLogins_AuthenticationType]  DEFAULT ('SQL') FOR [AuthenticationType]
GO

drop table if exists SpExHistory
GO 

CREATE TABLE SpExHistory 
(
	id INT IDENTITY PRIMARY KEY NOT NULL,
	sp_name sysname NOT NULL,
	execution_date DATETIME NOT NULL,
	execution_login sysname NOT NULL,
	original_execution_login sysname NOT NULL,
	[duration (s)] DECIMAL(9,3) NOT NULL,
	dop varchar(2) NOT NULL,
	parameter_values NVARCHAR(512) NOT NULL
)

*/

USE SQLAdministrationDB
GO

--CREATE OR ALTER FUNCTION ufn_is_login_disabled(@LoginName sysname)
--	RETURNS BIT
--WITH RETURNS NULL ON NULL INPUT
--AS
--BEGIN
--	RETURN (SELECT is_disabled FROM sys.server_principals WHERE name=@LoginName)
--END
--GO


-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2023.01.16>
-- Latest Update Date:	<23.01.16>
-- Description:			<Synchronize Logins>
-- License:				<Please refer to the license file> 
-- =============================================




CREATE OR ALTER PROC SyncLogins
	@Login_Name sysname = '',
	@Authentication_Type VARCHAR(10) = '',
	@Plain_Password NVARCHAR(512) = '',
	@Purpose VARCHAR(50) = 'Production',
	--@Permission_Type INT = 0,
	@Login_Status BIT = NULL,
	@MegaProject NVARCHAR(10) = 'JV',
	@sync_enabled BIT = 1
WITH EXEC AS 'JobVision\SQLServer'
AS
BEGIN
	SET NOCOUNT ON
	DECLARE @begin_timestamp DATETIME = GETDATE(),
			@duration DECIMAL(9,3)
	SET @Login_Name = ISNULL(@Login_Name,'')
	SET @Authentication_Type = ISNULL(@Authentication_Type,'')
	SET @Plain_Password = ISNULL(@Plain_Password,'')
	--SET @Permission_Type = ISNULL(@Permission_Type,0)
	--SET @Login_Status = ISNULL(@Login_Status,1)
	SET @Purpose = ISNULL(@Purpose,'')
	IF	@Authentication_Type NOT IN ('','SQL','WINDOWS') BEGIN RAISERROR('Authentication_Type entered must be one of SQL | WINDOWS',16,1) RETURN 1 END
	IF	@Purpose NOT IN ('Test','Production','') BEGIN RAISERROR('Invalid value specified for @Purpose. Valid values are Test | Production.',16,1) RETURN 1 END
	IF	@Purpose = '' SET @Purpose = 'Production'

	
	IF @Login_Name <> '' 
	BEGIN 
		IF @Authentication_Type = '' 
		BEGIN
			RAISERROR('@Login_Name is specified, as a result @Authentication_Type must also be specified',16,1) 
			RETURN 1 
		END 
		IF CHARINDEX('\',@Login_Name)<>0 
		BEGIN 
			RAISERROR('@Login_Name cannot contain character "\". If you want to create a windows authentication login, do not include domain or pc name. Instead set @Authentication_Type to "WINDOWS".',16,1) 
			RETURN 1 
		END 
		SELECT @Plain_Password
		IF @Plain_Password='' 
		BEGIN 
			IF (@Authentication_Type='SQL') 
			BEGIN 
				RAISERROR('@Plain_Password must be supplied when @Login_Name is specified and Authentication_Type is set to SQL.',16,1) 
				RETURN 1 
			END
		END
		ELSE 
			IF @Authentication_Type = 'WINDOWS'
			BEGIN 
				RAISERROR('@Plain_Password cannot be specified when @Authentication_Type is chosen to be "WINDOWS".',16,1) 
				RETURN 1 
			END 
		 
		IF @Authentication_Type = 'WINDOWS' SELECT @Login_Name='JobVision\'+@Login_Name, @Plain_Password = NULL

		IF EXISTS (SELECT 1 FROM dbo.InstanceLogins WHERE LoginName=@Login_Name)
				UPDATE dbo.InstanceLogins SET Purpose = @Purpose, PasswordPlain = @Plain_Password WHERE LoginName = @Login_Name
		
		INSERT SQLAdministrationDB..InstanceLogins
		(
		    LoginName,
		    PasswordPlain,
		    Purpose,
		    AuthenticationType,
		    MegaProject,
			sync_enabled
		)
		VALUES
		(   
			@Login_Name,    -- LoginName - sysname
		    @Plain_Password,    -- PasswordPlain - nvarchar(512)
		    DEFAULT, -- Purpose - varchar(50)
		    @Authentication_Type,    -- AuthenticationType - varchar(10)
		    @MegaProject,     -- MegaProject - varchar(50)
			@sync_enabled
		)
	END
	ELSE IF @Plain_Password<>'' OR @Authentication_Type<>''
	BEGIN
		
		RAISERROR('When @Login_Name is not specified, @Plain_Password OR @Authentication_Type cannot also be specified.',16,1)
		RETURN 1
	END


	
	INSERT dbo.InstanceLogins
	(
	    LoginName,
	    PasswordPlain,
	    Purpose,
	    AuthenticationType,
	    MegaProject
	)
	SELECT sp.name, NULL, NULL, IIF(CHARINDEX('\',sp.name)<>0,'WINDOWS','SQL'), @MegaProject FROM sys.server_principals sp
	LEFT JOIN dbo.InstanceLogins il ON sp.name COLLATE DATABASE_DEFAULT=il.LoginName
	LEFT JOIN (SELECT '##' name UNION ALL SELECT 'NT SERVICE\' UNION ALL SELECT 'NT AUTHORITY\' UNION ALL SELECT @@SERVERNAME+'\' UNION ALL SELECT SUSER_SNAME()) dt ON sp.name LIKE dt.name+'%' 
	WHERE il.LoginName IS NULL AND dt.name IS NULL AND sp.type IN ('S','U') AND sp.principal_id<>1

	--SELECT name, NULL, NULL, 'SQL', @MegaProject FROM sys.server_principals WHERE type='S'
	
	--SELECT name, NULL, NULL, 'SQL', @MegaProject FROM sys.server_principals sp
	--JOIN dbo.InstanceLogins il ON sp.type='S' AND name NOT IN ('##MS_PolicyTsqlExecutionLogin##','##MS_PolicyEventProcessingLogin##') AND sp.principal_id<>1 AND sp.name=il.LoginName
	--WHERE il.LoginName IS NULL

	--SELECT * FROM SQLAdministrationDB.dbo.InstanceLogins
	


	DECLARE @SQL NVARCHAR(MAX),
			@SQL2 NVARCHAR(MAX),
			@LoginName sysname,
			@PasswordPlain NVARCHAR(500),
			@PasswordHash VARCHAR(200),
			@SID VARCHAR(100),
			@LinkedServer sysname,
			@is_disabled bit
	
	DECLARE @PRINT_or_RAISERROR INT,
			@ErrMsg NVARCHAR(500),
			@ErrLine NVARCHAR(500),
			@ErrNo nvarchar(6),
			@ErrState nvarchar(3),
			@ErrSeverity nvarchar(2),
			@UDErrMsg nvarchar(MAX)


					

	--== Updating logins on Primary Server: ==============================================================

	DECLARE PasswordLoginUpdater CURSOR LOCAL FOR
		SELECT LoginName, PasswordPlain FROM dbo.InstanceLogins WHERE AuthenticationType = 'SQL' AND PasswordPlain IS NOT NULL AND sync_enabled = 1
	OPEN PasswordLoginUpdater
		FETCH NEXT FROM PasswordLoginUpdater INTO @LoginName, @PasswordPlain
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @SQL = 
			'
				IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '''+@LoginName+''')
					CREATE LOGIN '+QUOTENAME(@LoginName)+' WITH PASSWORD = N'''+@PasswordPlain+''', CHECK_POLICY=OFF, CHECK_EXPIRATION=OFF
				ELSE
					ALTER LOGIN '+QUOTENAME(@LoginName)+' WITH PASSWORD = N'''+@PasswordPlain+''', CHECK_POLICY = OFF, CHECK_EXPIRATION=OFF
			'
			IF ISNULL(@Login_Status,~@is_disabled) = 1
				SET @SQL +=
				'
					USE master
					GRANT CONNECT SQL TO '+QUOTENAME(@LoginName)+'
					ALTER LOGIN '+QUOTENAME(@LoginName)+' ENABLE
				'
			ELSE
				SET @SQL +=
				'
					USE master
					DENY CONNECT SQL TO '+QUOTENAME(@LoginName)+'
					ALTER LOGIN '+QUOTENAME(@LoginName)+' DISABLE
				'			
				
			BEGIN TRY				
				EXEC(@SQL)
				UPDATE dbo.InstanceLogins SET PasswordPlain = NULL WHERE LoginName = @LoginName
            END TRY
			BEGIN CATCH
				SET @PRINT_or_RAISERROR = 2			-- 1 for print 2 for RAISERROR
				SET @ErrMsg = ERROR_MESSAGE()
				SET @ErrLine = ERROR_LINE()
				SET @ErrNo = CONVERT(NVARCHAR(6),ERROR_NUMBER())
				SET @ErrState = CONVERT(NVARCHAR(3),ERROR_STATE())
				SET @ErrSeverity = CONVERT(NVARCHAR(2),ERROR_SEVERITY())
				SET @UDErrMsg = 'Something went wrong during the operation. Depending on your preference the operation will fail or continue, skipping this iteration.'+CHAR(10)+'System error message:'+CHAR(10)
						+ 'Msg '+@ErrNo+', Level '+@ErrSeverity+', State '+@ErrState+', Line '+@ErrLine + CHAR(10)
						+ @ErrMsg
				IF @PRINT_or_RAISERROR = 1
				begin
					PRINT @UDErrMsg
					PRINT ''
					PRINT '------------------------------------------------------------------------------------------------------------'
					PRINT ''
				end
				ELSE
				BEGIN
					PRINT ''
					PRINT '------------------------------------------------------------------------------------------------------------'
					PRINT ''
					RAISERROR(@UDErrMsg,16,1)
				END
			END CATCH

			FETCH NEXT FROM PasswordLoginUpdater INTO @LoginName, @PasswordPlain
		END
	CLOSE PasswordLoginUpdater
	DEALLOCATE PasswordLoginUpdater
	
	--== End updating logins on Primary Server ==================================================================





	--== Creating/Updating logins on other servers: =============================================================
	---- SQL Logins:
	DECLARE LoginScriptGenerator CURSOR LOCAL FOR
		SELECT 
			name,
			CONVERT(VARCHAR(200),PasswordHash,1),
			CONVERT(VARCHAR(100),il.SID,1),
			sp.is_disabled
		FROM sys.server_principals sp JOIN dbo.InstanceLogins il
		ON sp.name COLLATE DATABASE_DEFAULT = il.LoginName
		WHERE /*name LIKE 'App%1%' AND*/ il.AuthenticationType = 'SQL' AND PasswordHash IS NOT NULL AND sync_enabled = 1
	OPEN LoginScriptGenerator
		FETCH NEXT FROM LoginScriptGenerator INTO @LoginName, @PasswordHash, @SID, @is_disabled
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @SQL = 
			'
				DECLARE @name sysname
				DECLARE @sql2 NVARCHAR(MAX) = ''''''''
				IF SUSER_SNAME()<>''''''+'''+@LoginName+'''+''''''
				BEGIN
					IF exists (SELECT 1 FROM sys.server_principals WHERE sid='+@SID+' AND name <> ''''''+'''+@LoginName+'''+'''''')
					BEGIN
						SELECT @name = name FROM sys.server_principals WHERE sid='+@SID+'
						SET @sql2 = ''''DENY CONNECT SQL TO ''''+QUOTENAME(@name)
						EXEC(@sql2)
						SET @sql2 = ''''''''
						SELECT @sql2 += ''''KILL '''' + CONVERT(VARCHAR(11), session_id) + '''';''''
						FROM sys.dm_exec_sessions
						WHERE security_id = SUSER_SID('''''+@LoginName+''''')
						EXEC (@sql2)
						SET @sql2 = ''''DROP Login ''''+QUOTENAME(@name)
						EXEC(@sql2)
					END
					IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ''''''+'''+@LoginName+'''+'''''')
						IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE sid = '+@SID+')
							CREATE LOGIN '+QUOTENAME(@LoginName)+' WITH PASSWORD = '+@PasswordHash+' HASHED, SID = '+@SID+', CHECK_POLICY=OFF, CHECK_EXPIRATION=OFF
						ELSE
						BEGIN
							ALTER LOGIN '+QUOTENAME(@LoginName)+' WITH name = '+QUOTENAME(@LoginName)+'
							ALTER LOGIN '+QUOTENAME(@LoginName)+' WITH PASSWORD = '+@PasswordHash+' HASHED, CHECK_POLICY = OFF
						END
					ELSE				
						IF (SELECT sid FROM sys.server_principals WHERE name=''''''+'''+@LoginName+'''+'''''') = '+@SID+'
							ALTER LOGIN '+QUOTENAME(@LoginName)+' WITH PASSWORD = '+@PasswordHash+' HASHED, CHECK_POLICY = OFF
						ELSE
						BEGIN
							/*RAISERROR(''''''+''The login announced from the primary server exists on the target server but with a different sid.''+char(10)+''Server: ''+@Server+''     Login: ''+'''+@LoginName+'''+'''''',16,1)*/
						
							USE master
							DENY CONNECT SQL TO '+QUOTENAME(@LoginName)+'
							ALTER LOGIN '+QUOTENAME(@LoginName)+' DISABLE

							SET @sql2 = ''''''''
							SELECT @sql2 += ''''KILL '''' + CONVERT(VARCHAR(11), session_id) + '''';''''
							FROM sys.dm_exec_sessions
							WHERE security_id = SUSER_SID('''''+@LoginName+''''')
							EXEC (@sql2)

							DROP LOGIN '+QUOTENAME(@LoginName)+'
							CREATE LOGIN '+QUOTENAME(@LoginName)+' WITH PASSWORD = '+@PasswordHash+' HASHED, SID = '+@SID+', CHECK_POLICY=OFF, CHECK_EXPIRATION=OFF
						END
			'
			IF ISNULL(@Login_Status,~@is_disabled) = 1
				SET @SQL +=
				'
						USE master
						GRANT CONNECT SQL TO '+QUOTENAME(@LoginName)+'
						ALTER LOGIN '+QUOTENAME(@LoginName)+' ENABLE
					END
				'
			ELSE
				SET @SQL +=
				'
						USE master
						DENY CONNECT SQL TO '+QUOTENAME(@LoginName)+'
						ALTER LOGIN '+QUOTENAME(@LoginName)+' DISABLE
					END
				'			

			DECLARE ExecutorPerServer CURSOR LOCAL FOR
				SELECT ServerName+','+CONVERT(NVARCHAR(50),Port) FROM SQLAdministrationDB..Servers WHERE MegaProject='JV' AND IsActive=1 AND ServerName<>'DB1'
			OPEN ExecutorPerServer
				FETCH NEXT FROM ExecutorPerServer INTO @LinkedServer
				WHILE @@FETCH_STATUS = 0
				BEGIN
					SET @SQL2 = 
					'
						DECLARE @SQL NVARCHAR(MAX) ='''+@SQL+'''
						EXEC(@SQL) AT '+QUOTENAME(@LinkedServer)+'
					'
					BEGIN TRY
						
						--PRINT '--------------------'+CHAR(10)+@LoginName+CHAR(10)+@LinkedServer

						EXEC sp_executesql @SQL2, N'@Server sysname', @LinkedServer
					END TRY
					BEGIN CATCH
						PRINT @SQL2
						SELECT @LinkedServer, @LoginName
						SET @PRINT_or_RAISERROR = 2			-- 1 for print 2 for RAISERROR
						SET @ErrMsg = ERROR_MESSAGE()
						SET @ErrLine = ERROR_LINE()
						SET @ErrNo = CONVERT(NVARCHAR(6),ERROR_NUMBER())
						SET @ErrState = CONVERT(NVARCHAR(3),ERROR_STATE())
						SET @ErrSeverity = CONVERT(NVARCHAR(2),ERROR_SEVERITY())
						SET @UDErrMsg = 'Something went wrong during the operation. Depending on your preference the operation will fail or continue, skipping this iteration.'+CHAR(10)+'System error message:'+CHAR(10)
								+ 'Msg '+@ErrNo+', Level '+@ErrSeverity+', State '+@ErrState+', Line '+@ErrLine + CHAR(10)
								+ @ErrMsg
						IF @PRINT_or_RAISERROR = 1
						begin
							PRINT @UDErrMsg
							PRINT ''
							PRINT '------------------------------------------------------------------------------------------------------------'
							PRINT ''
						end
						ELSE
						BEGIN
							PRINT ''
							PRINT '------------------------------------------------------------------------------------------------------------'
							PRINT ''
							RAISERROR(@UDErrMsg,16,1)
						END
					END CATCH


					FETCH NEXT FROM ExecutorPerServer INTO @LinkedServer											
				END
			CLOSE ExecutorPerServer
			DEALLOCATE ExecutorPerServer


			FETCH NEXT FROM LoginScriptGenerator INTO @LoginName, @PasswordHash, @SID, @is_disabled
		END
	CLOSE LoginScriptGenerator
	DEALLOCATE LoginScriptGenerator


	---- Windows Logins

	DECLARE LoginScriptGenerator2 CURSOR LOCAL FOR
		SELECT name FROM sys.server_principals sp JOIN dbo.InstanceLogins il
		ON il.LoginName=sp.name COLLATE DATABASE_DEFAULT
		WHERE sp.name LIKE 'JobVision\%' AND sync_enabled = 1
	OPEN LoginScriptGenerator2
		FETCH NEXT FROM LoginScriptGenerator2 INTO @LoginName
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @SQL = 
			'
				IF SUSER_SNAME()<>''''''+'''+@LoginName+'''+''''''
				BEGIN				
					IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ''''''+'''+@LoginName+'''+'''''')
						CREATE LOGIN '+QUOTENAME(@LoginName)+' FROM WINDOWS
			'
			IF ISNULL(@Login_Status,~@is_disabled) = 1
				SET @SQL +=
				'
						USE master
						GRANT CONNECT SQL TO '+QUOTENAME(@LoginName)+'
						ALTER LOGIN '+QUOTENAME(@LoginName)+' ENABLE
					END
				'
			ELSE
				SET @SQL +=
				'
						USE master
						DENY CONNECT SQL TO '+QUOTENAME(@LoginName)+'
						ALTER LOGIN '+QUOTENAME(@LoginName)+' DISABLE
					END
				'			

			DECLARE ExecutorPerServer2 CURSOR LOCAL FOR
				SELECT ServerName+','+CONVERT(NVARCHAR(50),Port) FROM SQLAdministrationDB..Servers WHERE MegaProject='JV' AND IsActive=1 AND ServerName<>'DB1'
			OPEN ExecutorPerServer2
				FETCH NEXT FROM ExecutorPerServer2 INTO @LinkedServer
				WHILE @@FETCH_STATUS = 0
				BEGIN
					SET @SQL2 = 
					'
						EXEC('''+@SQL+''') AT '+QUOTENAME(@LinkedServer)+'
					'
					BEGIN TRY
						EXEC(@SQL2)
					END TRY
					BEGIN CATCH
						SET @PRINT_or_RAISERROR = 2			-- 1 for print 2 for RAISERROR
						SET @ErrMsg = ERROR_MESSAGE()
						SET @ErrLine = ERROR_LINE()
						SET @ErrNo = CONVERT(NVARCHAR(6),ERROR_NUMBER())
						SET @ErrState = CONVERT(NVARCHAR(3),ERROR_STATE())
						SET @ErrSeverity = CONVERT(NVARCHAR(2),ERROR_SEVERITY())
						SET @UDErrMsg = 'Something went wrong during the operation. Depending on your preference the operation will fail or continue, skipping this iteration.'+CHAR(10)+'System error message:'+CHAR(10)
								+ 'Msg '+@ErrNo+', Level '+@ErrSeverity+', State '+@ErrState+', Line '+@ErrLine + CHAR(10)
								+ @ErrMsg
						IF @PRINT_or_RAISERROR = 1
						begin
							PRINT @UDErrMsg
							PRINT ''
							PRINT '------------------------------------------------------------------------------------------------------------'
							PRINT ''
						end
						ELSE
						BEGIN
							PRINT ''
							PRINT '------------------------------------------------------------------------------------------------------------'
							PRINT ''
							RAISERROR(@UDErrMsg,16,1)
						END
					END CATCH


					FETCH NEXT FROM ExecutorPerServer2 INTO @LinkedServer											
				END
			CLOSE ExecutorPerServer2
			DEALLOCATE ExecutorPerServer2


			FETCH NEXT FROM LoginScriptGenerator2 INTO @LoginName
		END
	CLOSE LoginScriptGenerator2
	DEALLOCATE LoginScriptGenerator2

	--== End creating/Updating logins on other servers =============================================================



	DECLARE @dop VARCHAR(2) = (SELECT STRING_AGG(CONVERT(VARCHAR(2),dop),', ') FROM sys.dm_exec_requests WHERE session_id=@@SPID)
	SET @duration = DATEDIFF_BIG(MILLISECOND,@begin_timestamp,GETDATE())/1000.0
	
	INSERT dbo.SpExHistory
	(
	    sp_name,
	    execution_date,
	    execution_login,
	    original_execution_login,
	    [duration (s)],
	    dop,
	    parameter_values
	)
	VALUES
	(   
		'SyncLogins',      -- sp_name - sysname
	    @begin_timestamp, -- execution_date - datetime
	    SUSER_SNAME(),      -- execution_login - sysname
	    ORIGINAL_LOGIN(),      -- original_execution_login - sysname
	    @duration,      -- duration (s) - bigint
		@dop,
		'
    	@Login_Name = '''+@Login_Name+''',
		@Authentication_Type = '''+@Authentication_Type+''',
		@Plain_Password = '''+IIF(@Plain_Password<>'','#########','')+''',
		@Purpose = '''+@Purpose+''',
		--@Permission_Type = ,
		@Login_Status = '+CONVERT(CHAR(1),@Login_Status)+'
		@MegaProject = '''+@MegaProject+'''
		@sync_enabled = '+CONVERT(CHAR(1),@sync_enabled)+'
		'
	 )
	 
	 
END
GO

--EXEC dbo.SyncLogins --@Login_Name = 'Apptestsp1',@Authentication_Type = 'SQL',@Plain_Password='PP'
--EXEC AS LOGIN = 'jobvision\sqlserver'
--SELECT SUSER_SNAME(),USER_NAME()
	--SELECT ASCII(RIGHT(ServerName,1)), ServerName FROM SQLAdministrationDB..Servers
	--UPDATE SQLAdministrationDB..Servers SET ServerName = REPLACE(ServerName,CHAR(13),'')

--SELECT * FROM sys.server_principals
--SELECT * FROM dbo.InstanceLogins where sync_enabled=1

--EXEC SQLAdministrationDB.sys.sp_MS_marksystemobject @objname = 'dbo.SyncLogins'
--SELECT * FROM SQLAdministrationDB..SpExHistory


--ALTER TABLE SQLAdministrationDB.dbo.InstanceLogins ADD is_disabled AS dbo.ufn_is_login_disabled(LoginName)


--SELECT * FROM servers



