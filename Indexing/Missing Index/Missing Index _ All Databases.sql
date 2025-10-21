-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2022.08.08>
-- Latest Update Date:	<22.08.08>
-- Name:				<Missing Index, All Databases>, Developed over Pinal Dave's missing index query
-- Description:			"Missing Index, All Databases, find missing index for all databases"
-- License:				<Please refer to the license file> 
-- =============================================



SET TRAN ISOLATION LEVEL READ UNCOMMITTED
GO


CREATE OR ALTER FUNCTION dbo.ConvertSecondsToTime (@seconds INT)
RETURNS NVARCHAR(12)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @hours INT, @minutes INT, @remainingSeconds INT, @milliseconds INT;
    DECLARE @result NVARCHAR(12);
    
    -- Calculate hours, minutes, and remaining seconds
    SET @hours = @seconds / 3600;
    SET @minutes = (@seconds % 3600) / 60;
    SET @remainingSeconds = @seconds % 60;
    SET @milliseconds = 0; -- Adjust as needed if you have a fractional part of seconds

    -- Format result
    SET @result = RIGHT('0' + CAST(@hours AS NVARCHAR(2)), 2) +
                 ':' +
                 RIGHT('0' + CAST(@minutes AS NVARCHAR(2)), 2) +
                 ':' +
                 RIGHT('0' + CAST(@remainingSeconds AS NVARCHAR(2)), 2) +
                 '.000'; -- Hardcoded milliseconds

    RETURN @result;
END;
GO




CREATE OR ALTER PROCEDURE usp_find_missing_index_every_database
-- This will group table names that are numbered. For example: Table1, Table2, Table3, ...
	@Group_Numbered_Table_Names BIT = NULL,
-- There might be some databases, probably with exact same funtionality, only for different customers,
-- that have same name tables with exactly the same structure. This option helps to aggregate such tables
-- over all the databases. The db names will be aggregated using their names and their index statistics
-- will be aggregated uing summation mostly.
	@Group_Databases_Same_Name_Tables BIT = NULL,
-- Only show indexes that do not fill up the database .ldf disk drive, thus can complete the index creation transaction. This acts
-- according to the estimate of (.ldf Drive free space)+(.ldf free space)-1.2*(heap table or clustered index size)
	@Only_Show_Creatable_Indexes BIT = NULL,
	@Only_Show_NonCreatable_Indexes BIT = NULL,
-- Only show missing indexes that have an impact of at least @Index_MIN_Impact_Percentage
	@Add_Log_Backup_And_Shrink_Statement BIT = NULL,
-- If this option is chosen, tables with the same name from different databases will be aggregated together. For examplem,
-- EF_Migrations_History table from different databases. This is usfull for especially for B2B businesses multi-tenant database
-- designs
	@Index_MIN_Impact_Percentage TINYINT = NULL,
-- Show only top # of indexes per table
	@Max_Number_of_indexes_to_show_per_table TINYINT = NULL,
-- Minimum user (seek+scan)
	@min_user_seek_plus_scan BIGINT = NULL,
-- Minimum user (seek+scan)/updates ratio
	@min_user_seek_plus_scan_div_update_ratio FLOAT
AS
BEGIN
	SET NOCOUNT ON
	IF  @Only_Show_Creatable_Indexes = 1 AND @Only_Show_NonCreatable_Indexes = 1
	BEGIN
		RAISERROR('Both @Only_Show_Creatable_Indexes AND @Only_Show_NonCreatable_Indexes cannot be enabled.',16,1)
		RETURN 1
	END
	ELSE IF @Only_Show_Creatable_Indexes = 1 SET @Only_Show_NonCreatable_Indexes = 0
	ELSE IF @Only_Show_NonCreatable_Indexes = 1 SET @Only_Show_Creatable_Indexes = 0
	ELSE SELECT @Only_Show_Creatable_Indexes = 0, @Only_Show_NonCreatable_Indexes = 0


	SET @Group_Numbered_Table_Names = ISNULL(@Group_Numbered_Table_Names,0)
	SET @min_user_seek_plus_scan = ISNULL(@min_user_seek_plus_scan,0)
	SET @Add_Log_Backup_And_Shrink_Statement = ISNULL(@Add_Log_Backup_And_Shrink_Statement,1)
	SET @Index_MIN_Impact_Percentage = ISNULL(@Index_MIN_Impact_Percentage,0)
	SET @Group_Databases_Same_Name_Tables = ISNULL(@Group_Databases_Same_Name_Tables,1)
	SET @Max_Number_of_indexes_to_show_per_table = ISNULL(@Max_Number_of_indexes_to_show_per_table,255)
	

	--DROP TABLE IF EXISTS #ExistingDatabaseNames
	--GO
	--create table #ExistingDatabaseNames (DBName sysname)

	SELECT name, create_date INTO #ExistingDatabaseNames FROM sys.databases WHERE database_id>4 AND state = 0

	DROP TABLE IF EXISTS #temp
	--GO
	CREATE TABLE #temp
	( 
		[DatabaseID] SMALLINT,
		[main_index_id] INT,
		index_handle BIGINT,
		unique_compiles BIGINT,
		[Avg_Impact_Percentage] FLOAT(8),
		user_seek_plus_scan BIGINT,
		[Table/CLU_IX Scan Count] BIGINT,
		[RowId/Key Lookup Count] BIGINT,
		user_updates_for_table BIGINT,
		[Avg_Estimated_Impact] FLOAT(8),
		[Last_User_Seek] datetime,
		[TableName] nvarchar(128),
		[Create_Statement] nvarchar(4000),
		[Key Columns] NVARCHAR(4000),
		[Included Columns] NVARCHAR(4000) 
	)
	CREATE TABLE #TableSizeData
	(
		database_id SMALLINT,
		[TableName] NVARCHAR(128),
		[UsedSpaceGB] DECIMAL(26, 6),
		Log_Drive_Free_Space_GB DECIMAL(26,4),
		Log_Free_Space_GB DECIMAL(26,4),
		Log_Drives_Agg NVARCHAR(30)
	)

	DECLARE @DBName sysname
	DECLARE @SQL NVARCHAR(MAX)	
	DECLARE @usedb NVARCHAR(256)

	DECLARE DB_Iterator CURSOR FOR
		SELECT name FROM #ExistingDatabaseNames
		ORDER BY create_date


	OPEN DB_Iterator
		FETCH NEXT FROM DB_Iterator INTO @DBName
		WHILE @@FETCH_STATUS = 0
		BEGIN

			BEGIN TRY	
				SET @usedb = 'use '+QUOTENAME(@DBName)+CHAR(10)

				SET @SQL = @usedb+CHAR(10)+
				'

					print('''+@DBName+''')
					DECLARE @FILEGROUP_name sysname = ''PRIMARY''
					DECLARE @Current_Collation VARCHAR(100) = convert(VARCHAR(100),DATABASEPROPERTYEX(DB_NAME(),''Collation''))
					DECLARE @SQL NVARCHAR(MAX)

					SET @SQL =
					''

						SELECT --TOP 1000
							dm_mid.database_id AS							DatabaseID,
							dm_ius.index_id									main_index_id,
							dm_mid.index_handle								index_handle,
							unique_compiles									unique_compiles,
							dm_migs.avg_user_impact							[Avg_Impact_Percentage],
							dm_migs.user_seeks+dm_migs.user_scans			user_seek_plus_scan,
							dm_ios.range_scan_count							[Table/CLU_IX Scan Count],
							dm_ios.singleton_lookup_count					[RowId/Key Lookup Count],

							dm_ios.leaf_insert_count+dm_ios.leaf_delete_count
								+dm_ios.leaf_update_count					user_updates_for_table,
							dm_migs.avg_user_impact*
								(dm_migs.user_seeks+dm_migs.user_scans)		Avg_Estimated_Impact,		
							dm_migs.last_user_seek							Last_User_Seek,		
							QUOTENAME(OBJECT_SCHEMA_NAME(dm_mid.OBJECT_ID,dm_mid.database_id))+''''.''''+QUOTENAME(OBJECT_NAME(dm_mid.OBJECT_ID,dm_mid.database_id)) 
																			[TableName],

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
							+ '''' ON '''' +''''''+QUOTENAME(@FILEGROUP_name)+'''''' 
																			Create_Statement,
							 ISNULL (dm_mid.equality_columns,'''''''') COLLATE ''+@Current_Collation+''
							+ CASE WHEN dm_mid.equality_columns IS NOT NULL AND dm_mid.inequality_columns 
							IS NOT NULL THEN '''','''' ELSE	'''''''' END + ISNULL (dm_mid.inequality_columns, '''''''')
							COLLATE ''+@Current_Collation+'' 				KeyColumns,
							dm_mid.included_columns COLLATE ''+@Current_Collation+'' 
																			IncludedColumns

						FROM sys.dm_db_missing_index_groups dm_mig WITH (NOLOCK)
						FULL JOIN sys.dm_db_missing_index_group_stats dm_migs
						ON dm_migs.group_handle = dm_mig.index_group_handle
						FULL JOIN sys.dm_db_missing_index_details dm_mid
						ON dm_mig.index_handle = dm_mid.index_handle
						FULL JOIN sys.dm_db_index_usage_stats dm_ius
						ON dm_ius.database_id = DB_ID() AND dm_ius.index_id<2 AND dm_mid.OBJECT_ID=dm_ius.OBJECT_ID
						FULL JOIN sys.dm_db_index_operational_stats(db_id(), NULL, NULL, NULL) dm_ios
						ON dm_ios.database_id = DB_ID() AND dm_ios.index_id<2 AND dm_ios.object_id = dm_ius.object_id
						WHERE dm_mid.database_ID = DB_ID()
						ORDER BY Avg_Estimated_Impact DESC
					''

					--PRINT (@SQL)
					insert #temp
					EXEC (@SQL)
		
				'
				EXEC (@SQL)

				SET @SQL = @usedb+CHAR(10)+
				'
					DECLARE @FILEGROUP_name sysname = ''PRIMARY''
					DECLARE @Current_Collation VARCHAR(100) = convert(VARCHAR(100),DATABASEPROPERTYEX(DB_NAME(),''Collation''))
					DECLARE @SQL NVARCHAR(MAX)

					SET @SQL =
					''
						SELECT
							db_id() database_id,
							QUOTENAME(s.Name)+''''.''''+QUOTENAME(t.NAME) AS TableName,
							--p.rows AS RowCounts,
							--SUM(a.total_pages) /128.0 AS TotalSpaceKB, 
							SUM(a.used_pages) /128.0/1024 AS UsedSpaceGB,
							MIN(dt.Log_Drive_Free_Space_GB),
							MIN(dt.Log_Free_Space_GB),
							MIN(dt.DRIVES)
							--,(SUM(a.total_pages) - SUM(a.used_pages)) /128.0 AS UnusedSpaceKB
						FROM 
							sys.tables t INNER JOIN sys.indexes i 
							ON t.OBJECT_ID = i.object_id AND i.index_id IN (0,1) 
							INNER JOIN sys.partitions p 
							ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
							INNER JOIN sys.allocation_units a 
							ON p.partition_id = a.container_id
							LEFT OUTER JOIN sys.schemas s 
							ON t.schema_id = s.schema_id
							CROSS JOIN
							(SELECT SUM(vs.available_bytes/1048576.0/1024) Log_Drive_Free_Space_GB, SUM((mf.size-FILEPROPERTY(mf.name,''''SpaceUsed''''))/128.0/1024) Log_Free_Space_GB, STRING_AGG(vs.volume_mount_point , '''', '''') DRIVES FROM sys.master_files mf CROSS APPLY sys.dm_os_volume_stats(db_id(), mf.file_id) AS vs WHERE mf.type = 1 /*LOG*/ AND mf.database_id=db_id()) dt

						GROUP BY t.Name, s.Name
					''

					--PRINT (@SQL)
					insert #TableSizeData
					EXEC (@SQL)		
				'
				--PRINT @SQL						
				EXEC (@SQL)
                
			END TRY
			BEGIN CATCH
				DECLARE @ErrMsg NVARCHAR(2000) = ERROR_MESSAGE()
				RAISERROR(@ErrMsg,16,1)
			END CATCH
			FETCH NEXT FROM DB_Iterator INTO @DBName    			
	
	
		END
	CLOSE DB_Iterator
	DEALLOCATE DB_Iterator
--------------SELECT COUNT(*) [Number of Databases] FROM #ExistingDatabaseNames




IF @Group_Numbered_Table_Names = 1
	WITH cte AS
    (
		SELECT DISTINCT TableName,LEFT(LEFT(TableName,LEN(TableName)-1), LEN(TableName)-PATINDEX('%[^0-9]%', REVERSE(LEFT(TableName,LEN(TableName)-1)) + '1'))+']' RawTabName FROM #temp
	)
	UPDATE t
		SET t.TableName = LEFT(t2.RawTabName,LEN(t2.RawTabName)-1)+'##]'
	FROM #temp t JOIN cte t1 JOIN (
						SELECT cte.RawTabName FROM cte
						GROUP BY cte.RawTabName
						HAVING COUNT(cte.RawTabName)>1
					 ) t2
	ON t1.RawTabName=t2.RawTabName
	ON t1.TableName=t.TableName
	

	;WITH Index_Data AS
	(
		SELECT 
				dt.DatabaseName_Agg DatabaseName_Agg,
				TableName,
				dt.[Key Columns],
				dt.[Included Columns],
				dt.Avg_Impact_Percentage Avg_Impact_Percentage,
				dt.user_seek_plus_scan count_user_seek_plus_scan,
				dt.unique_compiles,
				dt.[Database Count] [Database Count],
				ROUND(Avg_Impact_Percentage*SQRT(user_seek_plus_scan),2) [Index_Impact_index],
				STRING_AGG('CREATE '+IIF(main_index_id=1,'NONCLUSTERED','CLUSTERED')+' INDEX '+LEFT('[IX_'+PARSENAME(dt.TableName,1)+'_'+REPLACE(REPLACE(REPLACE(REPLACE([Key Columns],',','_'),' ',''),'[',''),']','')+']',128) +CHAR(10)+ ' ON '+QUOTENAME(TRIM(ss.value))+'.'+dt.TableName+CHAR(10)+'('+dt.[Key Columns]+')'+ISNULL(CHAR(10)+' INCLUDE ('+dt.[Included Columns]+') ',''/*+'ON '+QUOTENAME(@Index_FILEGROUP)*/) +CHAR(10)+ ' WITH (ONLINE = ON, MAXDOP = 1, SORT_IN_TEMPDB = ON)'+CHAR(10)+CHAR(10),CHAR(10)+CHAR(10)) CreateStatement
		FROM
		(
				--** GROUP BY UNIQUE Index STATEMENTS (Different Key Columns, Different Included Columns)
				SELECT	TOP 100 PERCENT
						t.TableName,
						t.main_index_id,
						t.unique_compiles unique_compiles,
						t.[Key Columns],
						t.Avg_Impact_Percentage Avg_Impact_Percentage,
						t.user_seek_plus_scan user_seek_plus_scan, 
						t.Avg_Estimated_Impact Avg_Estimated_Impact,
						t.[Included Columns],
						t3.DatabaseName_Agg DatabaseName_Agg,
						t3.[Database Count] [Database Count]
				FROM 
				(
					SELECT t1.[TableName], t2.main_index_id, t1.[Key Columns], STRING_AGG(t1.[Included Columns],', ') [Included Columns], MAX(t2.Avg_Impact_Percentage) Avg_Impact_Percentage, MAX(t2.user_seek_plus_scan) user_seek_plus_scan, MAX(t2.Avg_Estimated_Impact) Avg_Estimated_Impact, MIN(t2.unique_compiles) [unique_compiles]
					FROM
					(
						SELECT DISTINCT
								t.[TableName],
								--t.index_handle,
								t.[Key Columns],				--(Per Index)
								TRIM(ss.value) [Included Columns]
						FROM #temp t
						OUTER APPLY STRING_SPLIT([Included Columns],',') ss
					) t1 
					JOIN 
					(	
						SELECT 				
							TableName, main_index_id, [Key Columns], MIN([unique_compiles]) [unique_compiles], MAX(Avg_Impact_Percentage) [Avg_Impact_Percentage], SUM(user_seek_plus_scan) [user_seek_plus_scan], MAX(Avg_Estimated_Impact) [Avg_Estimated_Impact]
						FROM #temp 
						GROUP BY TableName, main_index_id, [Key Columns]
					) t2
					ON t2.TableName = t1.TableName AND t2.[Key Columns] = t1.[Key Columns]
					GROUP BY t1.TableName, t2.main_index_id, t1.[Key Columns] 
		
				) t
				JOIN (SELECT t4.TableName, STRING_AGG(DB_NAME(t4.DatabaseID),', ') DatabaseName_Agg, COUNT(t4.DatabaseID) [Database Count] FROM (SELECT TableName, DatabaseID FROM #temp GROUP BY TableName, DatabaseID) t4 GROUP BY t4.TableName) t3
				ON t.TableName=t3.TableName
				ORDER BY t.TableName, t.[Key Columns]				
		) dt
		OUTER APPLY STRING_SPLIT(dt.DatabaseName_Agg,',') ss
		GROUP BY dt.Avg_Impact_Percentage * dt.user_seek_plus_scan, dt.DatabaseName_Agg, dt.TableName, dt.[Key Columns], dt.[Included Columns], dt.Avg_Impact_Percentage, dt.user_seek_plus_scan, dt.unique_compiles, dt.[Database Count] 
	)
	SELECT 
		ROW_NUMBER() OVER (PARTITION BY id1.TableName ORDER BY id1.Index_Impact_index desc) table_index_row,
	    id1.DatabaseName_Agg,
		id1.[TableName],
		id1.[Key Columns],
		id1.[Included Columns],
		id1.Avg_Impact_Percentage,
		id1.count_user_seek_plus_scan,
		IIF([user_updates_for_table]=0,-1,[count_user_seek_plus_scan]*1.0/[user_updates_for_table]) [user_seek+scan/update ratio],
		t.[user_updates_for_table],
		'/*Table Main Index Size: '+ CONVERT(NVARCHAR(50),ts.UsedSpaceGB) +' GB*/'+CHAR(10)+id1.CreateStatement+CHAR(10)+'GO'+CHAR(10)+IIF(UsedSpaceGB>1,'WAITFOR DELAY '''+dbo.ConvertSecondsToTime(ts.UsedSpaceGB*2)+''''+IIF(@Add_Log_Backup_And_Shrink_Statement=1,
'
EXECUTE master.[dbo].[DatabaseBackup]
@Databases = '''+QUOTENAME(id1.DatabaseName_Agg)+''',
@BackupType = ''LOG'',
@Directory = ''R:\Backups'',
@CleanupTime = 360,
@Verify = ''Y'',
@Compress = ''Y'',
@CheckSum = ''Y'',
@LogToTable = ''Y''
'		
,''),'') CreateStatement,
		ts.Log_Drive_Free_Space_GB + ts.Log_Free_Space_GB - 1.2*ts.UsedSpaceGB Estimated_Log_Drive_Space_Remaining_After_Index_Creation,
		ts.Log_Drives_Agg,
		[Index_Impact_index],
		ROUND(id2.Table_MAX_Impact*1.0*SQRT(id2.MAX_count_user_seek_plus_scan*1.0/IIF(t.user_updates_for_table=0,1,t.user_updates_for_table)),2) Table_Importance_index,
		id1.unique_compiles,
		id1.[Database Count]
	INTO #ResultSet
	FROM Index_Data id1
	JOIN (SELECT id.TableName, MAX(id.Avg_Impact_Percentage) Table_MAX_Impact, MAX(id.count_user_seek_plus_scan) MAX_count_user_seek_plus_scan FROM Index_Data id GROUP BY id.TableName) id2
	ON id2.TableName = id1.TableName
	JOIN (SELECT TableName, SUM(user_updates_for_table) user_updates_for_table, SUM([Table/CLU_IX Scan Count]) [Table/CLU_IX Scan Count], SUM([RowId/Key Lookup Count]) [RowId/Key Lookup Count] FROM #temp GROUP BY TableName) t
	ON t.TableName = id1.TableName
	JOIN #TableSizeData ts
	ON ts.TableName = id1.TableName
	WHERE 
		CASE	WHEN @Only_Show_Creatable_Indexes = 1		THEN -(ts.Log_Drive_Free_Space_GB + ts.Log_Free_Space_GB - 1.2*ts.UsedSpaceGB)
				WHEN @Only_Show_NonCreatable_Indexes = 1	THEN  (ts.Log_Drive_Free_Space_GB + ts.Log_Free_Space_GB - 1.2*ts.UsedSpaceGB)
				ELSE -1
				END <0 AND id1.Avg_Impact_Percentage>@Index_MIN_Impact_Percentage	

	SELECT DISTINCT [DatabaseName_Agg], [TableName], [Key Columns], [Included Columns], [Avg_Impact_Percentage], [count_user_seek_plus_scan] [count_user_seek+scan], [user_seek+scan/update ratio], [CreateStatement], [Estimated_Log_Drive_Space_Remaining_After_Index_Creation], [Log_Drives_Agg], [Index_Impact_index], [Table_Importance_index], [unique_compiles], [Database Count] 
	FROM #ResultSet
	WHERE	table_index_row<=@Max_Number_of_indexes_to_show_per_table		-- Most significant indexes per table
			AND [user_seek+scan/update ratio]>=@min_user_seek_plus_scan_div_update_ratio OR [user_seek+scan/update ratio]=-1
			AND count_user_seek_plus_scan>=@min_user_seek_plus_scan
	ORDER BY Table_Importance_index desc, TableName, [Index_Impact_index] desc 

END
GO

EXEC usp_find_missing_index_every_database 
	@Group_Numbered_Table_Names = 1,
	@Only_Show_Creatable_Indexes = 0,
	@Only_Show_NonCreatable_Indexes = 0,
	@Add_Log_Backup_And_Shrink_Statement = 1,
	@Index_MIN_Impact_Percentage=60,
	@Max_Number_of_indexes_to_show_per_table = 2,
	@min_user_seek_plus_scan_div_update_ratio = 0,
	@min_user_seek_plus_scan = 10




DROP PROC dbo.usp_find_missing_index_every_database
GO

-----==============================================================================

--SELECT * FROM ##temptable
--WHERE TableName IN 
--('[dbo].[person_info_entity]','[dbo].[base_event_entity]','[dbo].[mig_detail_entity]','','')