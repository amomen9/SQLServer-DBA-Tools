-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2025-09-15"
-- Description:         "hard kill"
-- License:             "Please refer to the license file"
-- =============================================



USE master
GO

SET DEADLOCK_PRIORITY 10

DROP TABLE IF EXISTS #logins
GO

-- logins for specific database
DECLARE @DBName sysname = 'OptionDb_delete'
-- specific login (throw login out of server immediately)
DECLARE @LoginName sysname = 'tadbir'


SELECT DISTINCT login_name 
INTO #logins
FROM sys.dm_exec_sessions
WHERE --login_name=@LoginName 
	database_id = DB_ID(@DBName)


WHILE 1=1
BEGIN
	DECLARE @SQL NVARCHAR(MAX) = ''

	INSERT #logins
	SELECT DISTINCT s.login_name 
	FROM sys.dm_exec_sessions s
	LEFT JOIN #logins l
	ON l.login_name = s.login_name
	WHERE l.login_name IS NULL AND 
		database_id = DB_ID(@DBName)
	
	SELECT @SQL=STRING_AGG('DENY CONNECT SQL TO ['+ login_name+']'+CHAR(10)+'ALTER LOGIN ['+login_name+'] DISABLE'+CHAR(10),CHAR(10))
	FROM
	(
		SELECT * FROM #logins
	) dt
	PRINT @SQL
	EXEC(@SQL)

	SET @SQL=''

	SELECT @SQL += 'KILL ' + CONVERT(VARCHAR(11), session_id) + '; ' + CHAR(10)
	FROM sys.dm_exec_sessions
	WHERE --login_name=@LoginName 
		database_id = DB_ID(@DBName)

       


	BEGIN TRY
		PRINT @SQL
		EXEC (@SQL)
		IF NOT EXISTS (SELECT 1	FROM sys.dm_exec_sessions 
				WHERE --login_name=@LoginName 
						database_id = DB_ID(@DBName)
						)
			BREAK
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 3701
			BREAK
		ELSE
			PRINT ERROR_MESSAGE()
	END CATCH
END

SELECT @SQL=''	
--SELECT @SQL+='DROP DATABASE ['+@DBName+']'+CHAR(10)
--SELECT @SQL+='ALTER DATABASE ['+@DBName+'] MODIFY NAME = OptionDb_delete;'+CHAR(10)
SELECT @SQL+='ALTER DATABASE ['+@DBName+'] SET OFFLINE;'+CHAR(10)
--SELECT @SQL+='ALTER DATABASE ['+@DBName+'] SET MULTI_USER'+CHAR(10)
BEGIN TRY
	EXEC(@SQL)
END TRY
BEGIN CATCH
	PRINT ERROR_MESSAGE()
END CATCH


SELECT @SQL = STRING_AGG('GRANT CONNECT SQL TO ['+ login_name+']'+CHAR(10)+'ALTER LOGIN ['+login_name+'] ENABLE'+CHAR(10),CHAR(10))
FROM
(
	SELECT * FROM #logins
) dt
PRINT @SQL
EXEC(@SQL)

--DROP LOGIN [tadbir]

--ALTER DATABASE hive_Stage1 SET MULTI_USER


--DECLARE @schema VARCHAR(MAX);
--EXEC dbo.sp_WhoIsActive 



--	SELECT 'KILL ' + CONVERT(VARCHAR(11), session_id) + '; ' + CHAR(10)
--	FROM sys.dm_exec_sessions
--	WHERE --login_name=@LoginName 
--		database_id = DB_ID('PooyaFinance_MigrationStage')

--SELECT 1	
--FROM sys.dm_exec_sessions 
--				WHERE --login_name=@LoginName 
--		database_id = DB_ID('PooyaFinance_MigrationStage')


