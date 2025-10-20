-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2022.08.08>
-- Latest Update Date:	<22.08.08>
-- Description:			<Missing Index, all databases>
-- License:				<Please refer to the license file> 
-- =============================================



DROP TABLE IF EXISTS #ExistingCompanyNames
GO

SELECT name, create_date INTO #ExistingCompanyNames FROM sys.databases WHERE database_id>4 AND state = 0

DECLARE @Index_FILEGROUP sysname = 'NIX'

DROP TABLE IF EXISTS #temp
CREATE TABLE #temp
( 
	[DatabaseID] SMALLINT,
	[Avg_Impact_Percentage] FLOAT(8),
	user_seek_plus_scan BIGINT,
	[Avg_Estimated_Impact] FLOAT(8),
	[Last_User_Seek] datetime,
	[TableName] nvarchar(128),
	[Create_Statement] nvarchar(4000),
	[Covered Columns] NVARCHAR(max),
	[Included Columns] NVARCHAR(max) 
)

DECLARE @CoName sysname
DECLARE @CoID UNIQUEIDENTIFIER
	DECLARE @sql NVARCHAR(MAX)	
	DECLARE @usedb NVARCHAR(MAX)
	DECLARE @Stmts NVARCHAR(MAX)

DECLARE CoFiller CURSOR FOR
	SELECT NEWID(),name FROM #ExistingCompanyNames
	ORDER BY create_date
DECLARE @ConnectionString NVARCHAR(MAX)
OPEN CoFiller
	FETCH NEXT FROM CoFiller INTO @CoID,@CoName
	WHILE @@FETCH_STATUS = 0
	BEGIN

		BEGIN TRY	
			DECLARE @CompanyDBName sysname = @CoName
			SET @usedb = 'use '+QUOTENAME(@CompanyDBName)+CHAR(10)

			SET @sql = @usedb+CHAR(10)+
			'
				--select '''+@CompanyDBName+''' from sys.databases where name = '''+@CompanyDBName+'''
				print('''+@CompanyDBName+''')
				DECLARE @FILEGROUP_name sysname = ''PRIMARY''
				DECLARE @Current_Collation VARCHAR(100) = convert(VARCHAR(100),DATABASEPROPERTYEX(DB_NAME(),''Collation''))
				DECLARE @SQL NVARCHAR(MAX)

				SET @sql =
				''

				SELECT TOP 25
				dm_mid.database_id AS DatabaseID,		--1
				dm_migs.avg_user_impact avg_user_impact_percentage,
				dm_migs.user_seeks+dm_migs.user_scans user_seek_plus_scan,
				dm_migs.avg_user_impact*(dm_migs.user_seeks+dm_migs.user_scans) Avg_Estimated_Impact,		--2
				dm_migs.last_user_seek AS Last_User_Seek,		--3
				QUOTENAME(OBJECT_SCHEMA_NAME(dm_mid.OBJECT_ID,dm_mid.database_id))+''''.''''+QUOTENAME(OBJECT_NAME(dm_mid.OBJECT_ID,dm_mid.database_id)) AS [TableName],		--4

					''''CREATE INDEX [IX_'''' + OBJECT_NAME(dm_mid.OBJECT_ID,dm_mid.database_id) COLLATE ''+@Current_Collation+'' + ''''_''''
					+ REPLACE(REPLACE(REPLACE(ISNULL(dm_mid.equality_columns,''''''''),'''', '''',''''_''''),''''['''',''''''''),'''']'''','''''''')  COLLATE ''+@Current_Collation+''
					+ CASE
					WHEN dm_mid.equality_columns IS NOT NULL
					AND dm_mid.inequality_columns IS NOT NULL THEN ''''_''''
					ELSE ''''''''
					END
					+ REPLACE(REPLACE(REPLACE(ISNULL(dm_mid.inequality_columns,''''''''),'''', '''',''''_''''),''''['''',''''''''),'''']'''','''''''') COLLATE ''+@Current_Collation+''
					+ '''']''''
					+ '''' ON '''' + quotename(parsename(dm_mid.statement,2)) + ''''.'''' + quotename(parsename(dm_mid.statement,1))
					+ '''' ('''' + ISNULL (dm_mid.equality_columns,'''''''') COLLATE ''+@Current_Collation+''
					+ CASE WHEN dm_mid.equality_columns IS NOT NULL AND dm_mid.inequality_columns 
					IS NOT NULL THEN '''','''' ELSE
					'''''''' END
					+ ISNULL (dm_mid.inequality_columns, '''''''') COLLATE ''+@Current_Collation+''
					+ '''')''''
					+ ISNULL ('''' INCLUDE ('''' + dm_mid.included_columns + '''')'''', '''''''') COLLATE ''+@Current_Collation+''
					+ '''' ON '''' +''''''+QUOTENAME(@FILEGROUP_name)+'''''' AS Create_Statement,
					 ISNULL (dm_mid.equality_columns,'''''''') COLLATE ''+@Current_Collation+''
					+ CASE WHEN dm_mid.equality_columns IS NOT NULL AND dm_mid.inequality_columns 
					IS NOT NULL THEN '''','''' ELSE
					'''''''' END
					+ ISNULL (dm_mid.inequality_columns, '''''''') COLLATE ''+@Current_Collation+'' AS CoveredColumns,
					ISNULL (dm_mid.included_columns , '''''''') COLLATE ''+@Current_Collation+'' AS IncludedColumns

				FROM sys.dm_db_missing_index_groups dm_mig
				INNER JOIN sys.dm_db_missing_index_group_stats dm_migs
				ON dm_migs.group_handle = dm_mig.index_group_handle
				INNER JOIN sys.dm_db_missing_index_details dm_mid
				ON dm_mig.index_handle = dm_mid.index_handle
				WHERE dm_mid.database_ID = DB_ID()
				ORDER BY Avg_Estimated_Impact DESC
				''

				--PRINT (@SQL)
				insert #temp
				EXEC (@sql)
			
			'
			
			EXEC (@sql)
		END TRY
		BEGIN CATCH
			DECLARE @ErrMsg NVARCHAR(MAX) = ERROR_MESSAGE()
			RAISERROR(@ErrMsg,16,1)
		END CATCH
	
		FETCH NEXT FROM CoFiller INTO @CoID,@CoName    			
	
	
	END
CLOSE CoFiller
DEALLOCATE CoFiller

SELECT COUNT(*) [Number of Databases] FROM #ExistingCompanyNames


SELECT COUNT(Create_Statement) Create_Statement_Count, COUNT(DISTINCT Create_Statement) Distinct_Create_Statement_Count FROM #temp


SELECT 
		TableName,
		STRING_AGG(CONVERT(VARCHAR(50),Avg_Impact_Percentage)+':::'+[Covered Columns] + ISNULL('----' + [Included Columns],''),' || ') Columns,
		AVG(Avg_Impact_Percentage) Avg_Impact_Percentage,
		sum(user_seek_plus_scan) count_user_seek_plus_scan,
		AVG(Avg_Impact_Percentage)*sum(user_seek_plus_scan) [avg impact],
		MIN(DatabaseName) [Databases],
		MIN([Database Count]) [Database Count],
		REPLACE(STRING_AGG('CREATE INDEX [IX_'+PARSENAME(dt.TableName,1)+'_'+REPLACE(REPLACE(REPLACE(REPLACE([Covered Columns],',','_'),' ',''),'[',''),']','')+']' + ' ON '+dt.TableName+'('+dt.[Covered Columns]+')'+CHAR(10)+IIF([Included Columns]='' OR [Included Columns] IS NULL,'',' INCLUDE ('+dt.[Included Columns]+') '/*+'ON '+QUOTENAME(@Index_FILEGROUP)*/),CHAR(10)+CHAR(10)),CHAR(10)+CHAR(10),'g90-4-hkgghkpddl') CreateStatement
FROM
(
	SELECT TOP 1000000 
		TableName,
		[Covered Columns],
		STRING_AGG(IIF([Included Columns]='',NULL,[Included Columns]),', ') [Included Columns],
		MAX(Avg_Impact_Percentage) Avg_Impact_Percentage,
		MAX(user_seek_plus_scan) user_seek_plus_scan,
		MAX(Avg_Estimated_Impact) Avg_Estimated_Impact,
		MIN(DatabaseName) DatabaseName,
		MIN(dt.[Database Count]) [Database Count]
	FROM 
	(
		SELECT	
				TableName,
				[Covered Columns],
				MAX(t.Avg_Impact_Percentage) Avg_Impact_Percentage,
				SUM(t.user_seek_plus_scan) user_seek_plus_scan, 
				MAX(t.Avg_Estimated_Impact) Avg_Estimated_Impact,
				STRING_AGG(CONVERT(VARCHAR(128),QUOTENAME(DB_NAME(DatabaseID))),', ') DatabaseName,
				COUNT(DatabaseID) [Database Count],
				trim(ss.value) [Included Columns]
		FROM #temp t
		CROSS APPLY STRING_SPLIT([Included Columns],',') ss
		GROUP BY TableName,	[Covered Columns], TRIM(ss.value)
		

	) dt
	GROUP BY TableName, [Covered Columns]
	ORDER BY TableName, [Covered Columns]
) dt
WHERE DatabaseName LIKE '%co-%db%' -- Filtering multi-tenant databases, leave this condition empty to include all databases.

GROUP BY TableName
--HAVING AVG(user_seek_plus_scan) > 10
ORDER BY [avg impact] DESC

