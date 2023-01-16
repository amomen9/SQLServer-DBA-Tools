-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2023.01.16>
-- Latest Update Date:	<23.01.16>
-- Description:			<Restore Backups>
-- License:				<Please refer to the license file> 
-- =============================================



USE SQLAdministrationDB
GO

CREATE OR ALTER PROC SyncLogins
	@Login_Name sysname = '',
	@Authentication_Type VARCHAR(10) = '',
	@Plain_Password NVARCHAR(512) = '',
	@Purpose VARCHAR(50) = 'Production',
	--@Permission_Type INT = 0,
	@Login_Status BIT = 1
WITH EXEC AS 'JobVision\SQLServer'
AS
BEGIN
	SET NOCOUNT ON
	SET @Login_Name = ISNULL(@Login_Name,'')
	SET @Authentication_Type = ISNULL(@Authentication_Type,'')
	SET @Plain_Password = ISNULL(@Plain_Password,'')
	--SET @Permission_Type = ISNULL(@Permission_Type,0)
	SET @Login_Status = ISNULL(@Login_Status,1)
	SET @Purpose = ISNULL(@Purpose,'')
	IF	@Authentication_Type NOT IN ('','SQL','WINDOWS') BEGIN RAISERROR('Authentication_Type entered must be one of SQL | WINDOWS',16,1) RETURN 1 END
	IF	@Purpose NOT IN ('Test','Production','') BEGIN RAISERROR('Invalid value specified for @Purpose. Valid values are Test | Production.',16,1) RETURN 1 END
	IF	@Purpose = '' SET @Purpose = 'Production'

	
	IF @Login_Name <> '' 
	BEGIN 
		IF @Authentication_Type = '' BEGIN RAISERROR('@Login_Name is specified, as a result @Authentication_Type must also be specified',16,1) RETURN 1 END IF CHARINDEX('\',@Login_Name)<>0 BEGIN RAISERROR('@Login_Name cannot contain character "\". If you want to create a windows authentication login, do not include domain or pc name. Instead set @Authentication_Type to "WINDOWS".',16,1) RETURN 1 END IF @Plain_Password='' BEGIN IF (@Authentication_Type='SQL') BEGIN RAISERROR('@Plain_Password must be supplied when @Login_Name is specified and Authentication_Type is set to SQL.',16,1) RETURN 1 END ELSE IF @Authentication_Type = 'WINDOWS' BEGIN RAISERROR('@Plain_Password cannot be specified when @Authentication_Type is chosen to be "WINDOWS".',16,1) RETURN 1 END END 
		IF @Authentication_Type = 'WINDOWS' SELECT @Login_Name='JobVision\'+@Login_Name, @Plain_Password = NULL

		IF EXISTS (SELECT 1 FROM dbo.InstanceLogins WHERE LoginName=@Login_Name)
				UPDATE dbo.InstanceLogins SET Purpose = @Purpose, PasswordPlain = @Plain_Password WHERE LoginName = @Login_Name
		
		INSERT SQLAdministrationDB..InstanceLogins
		(
		    LoginName,
		    PasswordPlain,
		    Purpose,
		    AuthenticationType,
		    MegaProject
		)
		VALUES
		(   @Login_Name,    -- LoginName - sysname
		    @Plain_Password,    -- PasswordPlain - nvarchar(512)
		    DEFAULT, -- Purpose - varchar(50)
		    @Authentication_Type,    -- AuthenticationType - varchar(10)
		    'JV'     -- MegaProject - varchar(50)
		)
	END
	ELSE IF @Plain_Password<>'' OR @Authentication_Type<>''
	BEGIN
		
		RAISERROR('When @Login_Name is not specified, @Plain_Password OR @Authentication_Type cannot also be specified.',16,1)
		RETURN 1
	END
	
	DECLARE @SQL NVARCHAR(MAX),
			@SQL2 NVARCHAR(MAX),
			@LoginName sysname,
			@PasswordPlain NVARCHAR(500),
			@PasswordHash VARCHAR(200),
			@SID VARCHAR(100),
			@LinkedServer sysname
	
	DECLARE @PRINT_or_RAISERROR INT,
			@ErrMsg NVARCHAR(500),
			@ErrLine NVARCHAR(500),
			@ErrNo nvarchar(6),
			@ErrState nvarchar(3),
			@ErrSeverity nvarchar(2),
			@UDErrMsg nvarchar(MAX)


					



	DECLARE PasswordLoginUpdater CURSOR LOCAL FOR
		SELECT LoginName, PasswordPlain FROM dbo.InstanceLogins WHERE AuthenticationType = 'SQL'
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
			IF @Login_Status = 1
				SET @SQL
					GRANT CONNECT SQL TO '+QUOTENAME(@LoginName)+'
					ALTER LOGIN '+QUOTENAME(@LoginName)+' ENABLE
					DENY CONNECT SQL TO [A.Hashemi]
					ALTER LOGIN [A.Hashemi] DISABLE
			ELSE
				
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

	--SELECT * FROM sys.servers

	DECLARE LoginScriptGenerator CURSOR LOCAL FOR
		SELECT 
			name,
			CONVERT(VARCHAR(200),LOGINPROPERTY(name,'PasswordHash'),1),
			CONVERT(VARCHAR(100),il.SID,1)
		FROM sys.server_principals sp JOIN dbo.InstanceLogins il
		ON sp.name COLLATE Persian_100_CI_AI = il.LoginName
		WHERE name LIKE 'App%1%'
	OPEN LoginScriptGenerator
		FETCH NEXT FROM LoginScriptGenerator INTO @LoginName, @PasswordHash, @SID
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @SQL = 
			'
				IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ''''''+'''+@LoginName+'''+'''''')
					CREATE LOGIN '+QUOTENAME(@LoginName)+' WITH PASSWORD = '+@PasswordHash+' HASHED, SID = '+@SID+', CHECK_POLICY=OFF, CHECK_EXPIRATION=OFF
				ELSE
					ALTER LOGIN '+QUOTENAME(@LoginName)+' WITH PASSWORD = '+@PasswordHash+' HASHED, CHECK_POLICY = OFF
			'
			DECLARE ExecutorPerServer CURSOR LOCAL FOR
				SELECT ServerName+','+CONVERT(NVARCHAR(50),Port) FROM SQLAdministrationDB..Servers WHERE MegaProject='JV' AND IsActive=1 AND ServerName<>'DB1'
			OPEN ExecutorPerServer
				FETCH NEXT FROM ExecutorPerServer INTO @LinkedServer
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


					FETCH NEXT FROM ExecutorPerServer INTO @LinkedServer											
				END
			CLOSE ExecutorPerServer
			DEALLOCATE ExecutorPerServer


			FETCH NEXT FROM LoginScriptGenerator INTO @LoginName, @PasswordHash, @SID
		END
	CLOSE LoginScriptGenerator
	DEALLOCATE LoginScriptGenerator





	DECLARE LoginScriptGenerator2 CURSOR LOCAL FOR
		SELECT name FROM sys.server_principals WHERE name LIKE 'JobVision\App%'
	OPEN LoginScriptGenerator2
		FETCH NEXT FROM LoginScriptGenerator2 INTO @LoginName
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @SQL = 
			'
				IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ''''''+'''+@LoginName+'''+'''''')
					CREATE LOGIN '+QUOTENAME(@LoginName)+' FROM WINDOWS
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
END
GO

EXEC dbo.SyncLogins --@Login_Name = 'Apptestsp1',@Authentication_Type = 'SQL',@Plain_Password='PP'
--EXEC AS LOGIN = 'jobvision\sqlserver'
--SELECT SUSER_SNAME(),USER_NAME()
	--SELECT ASCII(RIGHT(ServerName,1)), ServerName FROM SQLAdministrationDB..Servers
	--UPDATE SQLAdministrationDB..Servers SET ServerName = REPLACE(ServerName,CHAR(13),'')

--SELECT * FROM sys.server_principals
--SELECT * FROM dbo.InstanceLogins

--EXEC msdb.sys.sp_MS_marksystemobject @objname = 'dbo.cdc_jobs'