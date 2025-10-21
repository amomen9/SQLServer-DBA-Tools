-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2022-08-02"
-- Description:         "Drop Databases been offline more than a specific amount of time"
-- License:             "Please refer to the license file"
-- =============================================



﻿USE SQLAdministrationDB
GO

CREATE OR ALTER PROC drop_databases_that_have_been_offline_for_more_than_a_specific_amount_of_time
	@interval_days INT = 60,
	@Only_Show_Databases_Do_Not_Drop BIT = 0 
AS
BEGIN
	SET NOCOUNT ON

	DECLARE @NoofDatabases VARCHAR(10) = CONVERT(VARCHAR(10),(SELECT COUNT(*) [Number of Companies] FROM sys.databases WHERE database_id>4)),
			@CountofErrorFiles INT,
			@ErrLogPath NVARCHAR(500),
			@ErrLogBaseName NVARCHAR(64)

	SELECT 
		@ErrLogPath		= LEFT(dt.ErrBaseName,(LEN(dt.ErrBaseName)-CHARINDEX('\',REVERSE(dt.ErrBaseName))))+'\',
		@ErrLogBaseName = RIGHT(dt.ErrBaseName,CHARINDEX('\',REVERSE(dt.ErrBaseName))-1)
	FROM
	(
		SELECT CONVERT(NVARCHAR(500),SERVERPROPERTY('ErrorLogFileName')) [ErrBaseName]
	) dt

	CREATE TABLE #ErrorLog_Files ( [Path] nvarchar(500), depth INT, [file] int)
	INSERT #ErrorLog_Files
	(
	    Path,
		depth,
		[file]
	)
	EXEC sys.xp_dirtree @ErrLogPath, 1,1
	SELECT @CountofErrorFiles = COUNT(*) FROM #ErrorLog_Files WHERE Path LIKE (@ErrLogBaseName+'%') AND [file] = 1

	CREATE TABLE #ErrLog_Entries ( [LogDate] datetime, [ProcessInfo] nvarchar(12), [Text] nvarchar(3999) )
	SET @CountofErrorFiles-=1
	
	WHILE @CountofErrorFiles >= 0
	BEGIN
		INSERT #ErrLog_Entries
		(
		    LogDate,
		    ProcessInfo,
		    Text
		)
		EXEC sys.sp_readerrorlog @p1 = @CountofErrorFiles, @p2 = 1, @p3 = N'Setting database option OFFLINE to ON for database ';
				

		SET @CountofErrorFiles-=1
	END
	SELECT 
		dt.LogDate,
		LEFT(dt.DBName, LEN(dt.DBName)-2) DBName
	INTO #OfflineDatabases
	FROM
    (
		SELECT 
			ROW_NUMBER() OVER (PARTITION BY [Text] ORDER BY LogDate DESC) row,
			LogDate,
			SUBSTRING(Text,CHARINDEX('''',text)+1,LEN(text)) DBName
		FROM
        #ErrLog_Entries
	) dt
	WHERE dt.row = 1

	
	
	PRINT 'No. of databases before operation: ' + @NoofDatabases

	
	CREATE TABLE #temp (RawData NVARCHAR(MAX), DBName sysname)
	

	DECLARE @DatabaseName sysname
	DECLARE @CoID UNIQUEIDENTIFIER
		DECLARE @sql NVARCHAR(MAX)	
		DECLARE @usedb NVARCHAR(MAX) = ''
		DECLARE @Stmts NVARCHAR(MAX)


	SELECT 
		DBName,
		[How Long Offline?] = DATEDIFF(DAY,LogDate,GETDATE()), 
		IIF(EXISTS (SELECT state_desc FROM sys.databases WHERE name = DBName AND state_desc = 'OFFLINE'),1,0) [Does still exist?]
	FROM #OfflineDatabases
	--WHERE LogDate < DATEADD(DAY,-@interval_days,GETDATE()) and
	ORDER BY 2 desc


	DECLARE CoFiller CURSOR FOR
		SELECT DBName FROM #OfflineDatabases
		WHERE	LogDate < DATEADD(DAY,-@interval_days,GETDATE()) and
				(SELECT state_desc FROM sys.databases WHERE name = DBName) = 'OFFLINE'
	OPEN CoFiller
		FETCH NEXT FROM CoFiller INTO @DatabaseName
		WHILE @@FETCH_STATUS = 0
		BEGIN

			BEGIN TRY	
				DECLARE @CompanyDBName sysname = @DatabaseName

				SET @sql = @usedb+CHAR(10)+
				'				
					print('''+QUOTENAME(@CompanyDBName)+''')
					ALTER DATABASE '+QUOTENAME(@CompanyDBName)+' SET ONLINE							
				'
				
				IF @Only_Show_Databases_Do_Not_Drop = 0
					EXEC (@sql)
				SET @sql = 
				'
					ALTER DATABASE '+QUOTENAME(@CompanyDBName)+' SET SINGLE_USER WITH ROLLBACK IMMEDIATE
				'

				IF @Only_Show_Databases_Do_Not_Drop = 0
					EXEC (@sql)

			END TRY
			BEGIN CATCH
				DECLARE @ErrMsg NVARCHAR(MAX) = ERROR_MESSAGE()
				--RAISERROR(@ErrMsg,16,1)
				PRINT 'Warning!! The database could not be brought back online. We will try to drop it. After that it may have some leftovers on the disk though, which have to be deleted manually.'
			END CATCH
			BEGIN TRY
				SET @sql = @usedb + CHAR(10)+
				'					
					DROP DATABASE '+QUOTENAME(@CompanyDBName)+'			
				'
				
				IF @Only_Show_Databases_Do_Not_Drop = 0
					EXEC (@sql)			
				PRINT 'Database ' +QUOTENAME(@CompanyDBName)+' was dropped.'
			END TRY
			BEGIN CATCH
				SET @ErrMsg = ERROR_MESSAGE()
				RAISERROR(@ErrMsg,16,1)
			END CATCH
			FETCH NEXT FROM CoFiller INTO @DatabaseName    				
	
		END
	CLOSE CoFiller
	DEALLOCATE CoFiller
	
	SET @NoofDatabases = CONVERT(VARCHAR(10),(SELECT COUNT(*) [Number of Companies] FROM sys.databases WHERE database_id>4))
	PRINT 'No. of databases now (after operation): ' + @NoofDatabases

END
GO

EXEC dbo.drop_databases_that_have_been_offline_for_more_than_a_specific_amount_of_time 
			@interval_days = 60, -- int
			@Only_Show_Databases_Do_Not_Drop = 1

GO

--DROP PROC drop_databases_that_have_been_offline_for_more_than_a_specific_amount_of_time
--GO