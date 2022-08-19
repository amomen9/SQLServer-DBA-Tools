-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Description:			<Transfer Indexes to another FILEGROUP>
-- =============================================


/*
This script was originally written in 2 variants, variant 2 is however not available now:
	1. Variant with cursor to make the script functional for databases with numerous indexes. This might be slower but has following advantages:
		a. Error handling for each individual index
		b. Should there be an error among one or more of index transfer statements, others will be applied anyways
		c. If the number of indexes to be transferred is too high and all of the index transfer statements exceed 8000 characters, this variant still works but
			the second won't.
	2. Variant without cursor to speed things up. This variant lacks the advantages mentioned above. I have not included this variant
		if you wish, ask me to send it to you.

	Note: I have skipped the visualizations for failures' email report
*/

/*
Type of index:

0 = Heap

1 = Clustered rowstore (B-tree)

2 = Nonclustered rowstore (B-tree)

3 = XML

4 = Spatial

5 = Clustered columnstore index. Applies to: SQL Server 2014 (12.x) and later.

6 = Nonclustered columnstore index. Applies to: SQL Server 2012 (11.x) and later.

7 = Nonclustered hash index. Applies to: SQL Server 2014 (12.x) and later.

*/

------ With CURSOR:




USE sqladministrationdb
GO

CREATE OR ALTER PROC usp_move_indexes_to_another_filegroup
(
	@DatabaseName sysname,
	@starting_index_id TINYINT,
	@ending_index_id TINYINT = NULL,
	@source_filegroup_or_partition_scheme_name sysname = '',
	@target_filegroup_or_partition_scheme_name sysname,		-- Possible values: {partition_scheme_name ( column_name ) | filegroup_name | default}. 
															
	@SORT_IN_TEMPDB BIT = 0,
	@STATISTICS_NORECOMPUTE BIT = 1,
	@STATISTICS_INCREMENTAL BIT = 0,						-- It's not recommended to turn this feature on because you may face the following error:
															/*
																Msg 9108, Level 16, State 9, Line 139
																This type of statistics is not supported to be incremental.
															*/
	@ONLINE BIT = 1,
	@MAXDOP TINYINT = NULL,
	@DATA_COMPRESSION NVARCHAR(10) = 'DEFAULT',				-- Possible values: {DEFAULT|NONE|ROW|PAGE}
	@DATA_COMPRESSION_PARTITIONS NVARCHAR(128) = NULL,		-- Possible values: leave it empty for the whole partitions or for example 1,3,10,11 or 1-8
	@FILESTREAM NVARCHAR (20) = 'OFF',						-- Possible values: {filestream_filegroup_name | partition_scheme_name | NULL}
	@StartTime DATETIME = NULL,								-- Stored Procedure's execution start time
	@Retry_With_Less_Options BIT = 1,
															-- If some of the transfer statements raise error on first try and this parameter is enabled, the
															-- script retries only those statements by turning off the following switches. What remains will
															-- be reported via email:
															-- 1. @STATISTICS_INCREMENTAL
															-- 2. @ONLINE
	@Create_or_Update_IndexTransferResults_Table BIT = 1
	--@No_of_Indexes_Moved INT OUT,
																															
)
AS
BEGIN
	
	SET QUOTED_IDENTIFIER ON
	SET NOCOUNT ON
	
----- Variable Control ----------------------------------------------------------
	
	SET @Create_or_Update_IndexTransferResults_Table = ISNULL(@Create_or_Update_IndexTransferResults_Table,1)
	IF @DatabaseName IS NULL
	BEGIN
		RAISERROR ('Error. Database name cannot be NULL.', 16, 1)
		RETURN 1
    END
	IF DB_ID(@DatabaseName) IS NULL
	BEGIN
		RAISERROR ('Error. Database name specified does not exist.', 16, 1)
		RETURN 1
    END
	IF @starting_index_id IS NULL
	BEGIN
		RAISERROR ('Error. @starting_index_id cannot be NULL.', 16, 1)
		RETURN 1
    END
	SET @ending_index_id = ISNULL(@ending_index_id, 255)
	SET @source_filegroup_or_partition_scheme_name = ISNULL(@source_filegroup_or_partition_scheme_name,'')
	IF @target_filegroup_or_partition_scheme_name IS NULL
	BEGIN
		RAISERROR ('Error. @target_filegroup_or_partition_scheme_name cannot be NULL.', 16, 1)
		RETURN 1
    END
	IF @source_filegroup_or_partition_scheme_name = @target_filegroup_or_partition_scheme_name
		RAISERROR('Target and source FILEGROUP names are the same. Check the procedure''s inputs.',16,1)

	SET @SORT_IN_TEMPDB = ISNULL(@SORT_IN_TEMPDB,0)
	SET @STATISTICS_NORECOMPUTE = ISNULL(@STATISTICS_NORECOMPUTE,0)
	SET @STATISTICS_INCREMENTAL = ISNULL(@STATISTICS_INCREMENTAL,0)
	SET @ONLINE = ISNULL(@ONLINE,1)
	SET @MAXDOP = ISNULL(@MAXDOP,0)
	SET @DATA_COMPRESSION = IIF(@DATA_COMPRESSION IS NULL OR @DATA_COMPRESSION = '','DEFAULT',@DATA_COMPRESSION)
	SET @DATA_COMPRESSION_PARTITIONS = IIF(@DATA_COMPRESSION_PARTITIONS IS NULL OR @DATA_COMPRESSION_PARTITIONS = '','DEFAULT',@DATA_COMPRESSION_PARTITIONS)
	SET @FILESTREAM = IIF(@FILESTREAM IS NULL OR @FILESTREAM = '','OFF',@FILESTREAM)
	SET @Retry_With_Less_Options = ISNULL(@Retry_With_Less_Options,1)
	

---------------------------------------------------------------------------------
	DECLARE @TableName sysname
	DECLARE @RetryFlag BIT = 0
	DECLARE @DBCollation NVARCHAR(128) = CONVERT(NVARCHAR(128),DATABASEPROPERTYEX(@DatabaseName,'Collation'))
	DECLARE @Try_Count TINYINT = @Retry_With_Less_Options
	CREATE TABLE #temp (FG_Name sysname, FG_DataspaceID TINYINT)
	DECLARE @DataspaceID_Query VARCHAR(400) = 'use ' + QUOTENAME(@DatabaseName) + ' SELECT name, data_space_id from sys.filegroups where name in (''' + @target_filegroup_or_partition_scheme_name + ''','''+@source_filegroup_or_partition_scheme_name+''')'
	
	
	INSERT INTO #temp	
	EXEC (@DataspaceID_Query)
	
	DECLARE @Source_FG_DataspaceID TINYINT = (SELECT TOP 1 FG_DataspaceID FROM #temp WHERE FG_Name=@source_filegroup_or_partition_scheme_name)
	DECLARE @Target_FG_DataspaceID TINYINT = (SELECT TOP 1 FG_DataspaceID FROM #temp WHERE FG_Name=@target_filegroup_or_partition_scheme_name)

	DECLARE @SQL VARCHAR(MAX) = ''
	DECLARE @IndexStatement VARCHAR(max)
	IF @Target_FG_DataspaceID IS NULL OR (@Source_FG_DataspaceID IS NULL AND @source_filegroup_or_partition_scheme_name <> '')
	BEGIN
		DECLARE @EM NVARCHAR(300) = 'The filegroup name ''' + IIF(@Source_FG_DataspaceID IS NULL, @source_filegroup_or_partition_scheme_name, @target_filegroup_or_partition_scheme_name) + ''', specified does not exist for the database ' + @DatabaseName +'. Depending on your preference, the process will continue for the next databases or abort.'
		RAISERROR(@EM,16,1)
		RETURN 1
    END

	
	
	
	IF (SELECT OBJECT_ID('IndexTransferResults')) IS NULL AND @Create_or_Update_IndexTransferResults_Table = 1
		CREATE TABLE IndexTransferResults 
		(
			StatementID INT PRIMARY KEY IDENTITY NOT NULL,
			DatabaseName sysname NOT NULL,
			TableName sysname NOT NULL,
			EntireOpeartionStartTime DATETIME NOT NULL,
			IndexTransferStatement VARCHAR(8000),
			IsErrorRaised BIT DEFAULT 0,
			ErrorNo INT,
			ErrorSeverity TINYINT,
			ErrorState TINYINT,
			ErrorLine INT,
			ErrorMessage VARCHAR(MAX),
			StatementStartTime DATETIME,
			StatementEndTime DATETIME
		)
	
	
	--DROP TABLE IF EXISTS #IndexWorkingSpace
	CREATE TABLE #IndexWorkingSpace (IndexStatement VARCHAR(4000) NOT NULL, TableName sysname NOT NULL)	
		
	IF (0>=@starting_index_id)
	BEGIN

		DECLARE @IndexWorkingSpace VARCHAR(8000) =
		'
			use ' + QUOTENAME(@DatabaseName) + '

			SELECT 
				''USE '' + ''' + QUOTENAME(@DatabaseName)+ ''' + CHAR(10) + ''CREATE CLUSTERED INDEX temp98439gfjkgdfjskgj4859 ON '' + QUOTENAME(SchemaName) + ''.'' + QUOTENAME(TableName) + '' ('' + (SELECT TOP 1 name from sys.all_columns WHERE object_id = TableID) + '') ON '' + ''' + QUOTENAME(@target_filegroup_or_partition_scheme_name) + ''' + ''
				 DROP INDEX temp98439gfjkgdfjskgj4859 ON '' + QUOTENAME(SchemaName) + ''.'' + QUOTENAME(TableName) + CHAR(10) AS IndexStatement,
				 QUOTENAME(SchemaName) + ''.'' + QUOTENAME(TableName) AS TableName
			FROM		  
				(SELECT i.data_space_id, SCHEMA_NAME(t.schema_id) as SchemaName, OBJECT_NAME(i.object_id) TableName, i.object_id TableID
					FROM sys.tables t
					JOIN sys.indexes i 
					ON t.object_id = i.object_id AND t.is_ms_shipped=0
					WHERE i.index_id = 0
				) AS uind

			JOIN sys.filegroups fg
			ON uind.data_space_id = fg.data_space_id
			WHERE uind.data_space_id ' +
					IIF(@source_filegroup_or_partition_scheme_name='',
						'<> ' + CONVERT(VARCHAR(2),@Target_FG_DataspaceID),
						'= ' + CONVERT(VARCHAR(2),@Source_FG_DataspaceID)
					   )

		
		INSERT #IndexWorkingSpace		
		EXEC (@IndexWorkingSpace)
		

--		IF (SELECT COUNT(*) FROM #IndexWorkingSpace) <> 0
--		BEGIN        
			DECLARE IndexTransfer CURSOR 
			FOR
			(
				SELECT * FROM #IndexWorkingSpace	
			)
			OPEN IndexTransfer

				FETCH NEXT FROM IndexTransfer INTO @IndexStatement, @TableName			
				WHILE @@FETCH_STATUS = 0
				BEGIN
	-------------------------------------------------------------------------------------------------------------------------------
					BEGIN TRY
						IF @Create_or_Update_IndexTransferResults_Table = 1						
							INSERT INTO IndexTransferResults
							(
								DatabaseName,
								TableName,
								EntireOpeartionStartTime,
								IndexTransferStatement,
								StatementStartTime
							)
							VALUES
							(   
								@DatabaseName,
								@TableName,
								@StartTime,
								@IndexStatement,       -- IndexTransferStatement - varchar(8000)					    
								SYSDATETIME()
							)
						EXEC(@IndexStatement)						
						IF @Create_or_Update_IndexTransferResults_Table = 1												
							UPDATE IndexTransferResults SET StatementEndTime = SYSDATETIME() WHERE StatementID = SCOPE_IDENTITY()
				
					END TRY
					BEGIN CATCH
						PRINT(ERROR_MESSAGE()+'HEAP')
						--------Error Logging-------------------------------------------------------------------------------------
						IF @Create_or_Update_IndexTransferResults_Table = 1	
							UPDATE IndexTransferResults SET
								IsErrorRaised	= 1,
								ErrorNo			= ERROR_NUMBER(),
								ErrorSeverity	= ERROR_SEVERITY(),
								ErrorState		= ERROR_STATE(),
								ErrorLine		= ERROR_LINE(),
								ErrorMessage	= ERROR_MESSAGE(),
								StatementEndTime			= SYSDATETIME()
							WHERE StatementID = SCOPE_IDENTITY()					
						-----------------------------------------------------------------------------------------------------------
				
					END CATCH
	-------------------------------------------------------------------------------------------------------------------------------				
					FETCH NEXT FROM IndexTransfer INTO @IndexStatement, @TableName
				END 
			CLOSE IndexTransfer
			DEALLOCATE IndexTransfer						
--		END
		SET @starting_index_id = 1
    END

	IF (@ending_index_id > 0)
	BEGIN		

		DECLARE @Statement NVARCHAR(MAX)
		SET @Statement = CONCAT(

		'

			use ' , QUOTENAME(@DatabaseName) , '
			
			SELECT 
			''USE '' + QUOTENAME(@DatabaseName COLLATE '+@DBCollation+') + CHAR(10) + ''CREATE '' + CASE uind.is_unique WHEN 1 THEN ''UNIQUE '' ELSE '''' END  +  CASE uind.index_id WHEN 1 then ''CLUSTERED '' ELSE '''' END + ''INDEX '' + QUOTENAME(uind.name) + '' ON '' + QUOTENAME(SchemaName) + ''.'' + QUOTENAME(TableName) + CHAR(10) +
			'' ('' + 
			(
				SELECT STRING_AGG(QUOTENAME(name)+CASE is_descending_key WHEN 1 THEN '' desc'' ELSE '''' end,'','' + CHAR(10) + CHAR(9))
				FROM
				(
					SELECT top 10000 name, ic.is_descending_key
					from sys.all_columns c JOIN sys.index_columns ic
					ON ic.column_id = c.column_id AND c.object_id = uind.TableID AND ic.object_id = uind.TableID AND ic.key_ordinal <> 0 AND index_id=uind.index_id
					order by ic.key_ordinal
				) dt
			)
			+ '')'' + 
			ISNULL(('' include('' + (SELECT STRING_AGG(QUOTENAME(name),'','') from sys.all_columns c JOIN sys.index_columns ic ON ic.column_id = c.column_id WHERE c.object_id = uind.TableID AND ic.object_id = uind.TableID AND ic.is_included_column = 1 AND index_id=uind.index_id) + '')''),'''') + CHAR(10) +
			ISNULL((''where '' + uind.filter_definition + CHAR(10)), '''') +
			
			''WITH (DROP_EXISTING = ON'' +
			CASE uind.ignore_dup_key WHEN 1 then '', IGNORE_DUP_KEY = ON'' ELSE '''' END +
			CASE uind.fill_factor WHEN 0 then '''' ELSE '', FILLFACTOR = '' + CONVERT(CHAR(3), uind.fill_factor) END +
			CASE uind.is_padded WHEN 1 then '', PAD_INDEX = ON'' ELSE '''' end +
			CASE @SORT_IN_TEMPDB WHEN 1 then '', SORT_IN_TEMPDB = ON'' ELSE '''' END +
			CASE uind.allow_row_locks WHEN 1 then '', ALLOW_ROW_LOCKS = ON'' ELSE '''' END +
			CASE uind.allow_page_locks WHEN 1 then '', ALLOW_PAGE_LOCKS = ON'' ELSE '''' END +
			CASE uind.optimize_for_sequential_key WHEN 1 then '', OPTIMIZE_FOR_SEQUENTIAL_KEY = ON'' ELSE '''' END +
			CASE @ONLINE WHEN 1 THEN '', ONLINE = ON'' ELSE '''' END +
			CASE @STATISTICS_NORECOMPUTE WHEN 1 THEN '', STATISTICS_NORECOMPUTE = ON'' ELSE '''' END +
			CASE @STATISTICS_INCREMENTAL WHEN 1 THEN '', STATISTICS_INCREMENTAL = ON'' ELSE '''' END +
			CASE @MAXDOP WHEN 0 THEN '''' ELSE '', MAXDOP = '' + CONVERT(NVARCHAR(3),@MAXDOP) END +
			CASE @DATA_COMPRESSION COLLATE '+@DBCollation+' WHEN ''DEFAULT'' THEN '''' ELSE '', DATA_COMPRESSION = '' + @DATA_COMPRESSION COLLATE '+@DBCollation+' END +
			CASE @DATA_COMPRESSION_PARTITIONS COLLATE '+@DBCollation+' WHEN ''DEFAULT'' THEN '''' ELSE '' ON PARTITIONS ('' + @DATA_COMPRESSION_PARTITIONS COLLATE '+@DBCollation+' + '')'' END +
			'')'' + CHAR(10) +
			''on '' + QUOTENAME(@target_filegroup_or_partition_scheme_name COLLATE '+@DBCollation+') + CHAR(10) +
			CASE @FILESTREAM COLLATE '+@DBCollation+' WHEN ''OFF'' THEN '''' ELSE ''FILESTREAM_ON '' + @FILESTREAM COLLATE '+@DBCollation+' + CHAR(10) END +
			CASE uind.is_disabled WHEN 1 THEN ''ALTER INDEX ''+ uind.name +'' ON ''+ uind.TableName + CHAR(10) +''DISABLE;'' ELSE '''' END,            			
			QUOTENAME(SchemaName) + ''.'' + QUOTENAME(TableName) AS TableName


			FROM		  
				(
					SELECT 
							i.data_space_id,
							OBJECT_NAME(i.object_id) TableName,
							SCHEMA_NAME(schema_id) SchemaName,
							i.object_id TableID,
							i.name,
							i.is_unique,
							i.is_disabled,
							i.filter_definition,
							i.ignore_dup_key,
							i.fill_factor,
							i.is_padded,
							i.allow_row_locks,
							i.allow_page_locks,
							i.optimize_for_sequential_key,
							i.index_id			
					FROM sys.tables t
					JOIN sys.indexes i 
					ON t.object_id = i.object_id AND t.is_ms_shipped=0
					WHERE i.index_id between @starting_index_id AND @ending_index_id
				) AS uind		-- user indexes

			JOIN sys.filegroups fg
			ON uind.data_space_id = fg.data_space_id
			WHERE uind.data_space_id <> @Target_FG_DataspaceID
		'
		)
        --PRINT @Statement
		DECLARE @params NVARCHAR(MAX) =
		'
			@DatabaseName sysname,
			@SORT_IN_TEMPDB BIT,
			@ONLINE BIT,
			@STATISTICS_NORECOMPUTE BIT,
			@STATISTICS_INCREMENTAL BIT,
			@MAXDOP tinyint,
			@DATA_COMPRESSION NVARCHAR(10),
			@DATA_COMPRESSION_PARTITIONS NVARCHAR(128),
			@target_filegroup_or_partition_scheme_name sysname,
			@FILESTREAM nvarchar (20),
			@starting_index_id tinyint,
			@ending_index_id tinyint,
			@Target_FG_DataspaceID tinyint
		'
		
		
		INSERT #IndexWorkingSpace
		EXEC sp_executesql 
		@Statement,
		@params,
		@DatabaseName,
		@SORT_IN_TEMPDB,
		@ONLINE,
		@STATISTICS_NORECOMPUTE,
		@STATISTICS_INCREMENTAL,
		@MAXDOP,
		@DATA_COMPRESSION,
		@DATA_COMPRESSION_PARTITIONS,
		@target_filegroup_or_partition_scheme_name,
		@FILESTREAM,
		@starting_index_id,
		@ending_index_id,
		@Target_FG_DataspaceID
		
		SELECT * FROM #IndexWorkingSpace

--		IF (SELECT COUNT(*) FROM #IndexWorkingSpace) <> 0
--		BEGIN
			DECLARE IndexTransfer CURSOR 
			FOR
			(
				SELECT * FROM #IndexWorkingSpace	
			)
			OPEN IndexTransfer

				FETCH NEXT FROM IndexTransfer INTO @IndexStatement, @TableName			
				WHILE @@FETCH_STATUS = 0
				BEGIN
	-------------------------------------------------------------------------------------------------------------------------------				
					
					IF @Create_or_Update_IndexTransferResults_Table = 1
						INSERT INTO IndexTransferResults
						(
							DatabaseName,
							TableName,
							EntireOpeartionStartTime,
							IndexTransferStatement,
							StatementStartTime
						)
						VALUES
						(   
							@DatabaseName,
							@TableName,
							@StartTime,
							@IndexStatement,       -- IndexTransferStatement - varchar(8000)					    
							SYSDATETIME()
						)

					TRYPOINT:
					IF @RetryFlag = 1
					BEGIN
						PRINT 'retrying'
						SET @RetryFlag = 0
					END
					BEGIN TRY
						EXEC(@IndexStatement)
						IF @Create_or_Update_IndexTransferResults_Table = 1
							UPDATE IndexTransferResults SET StatementEndTime = SYSDATETIME() WHERE StatementID = SCOPE_IDENTITY()
					END TRY
					BEGIN CATCH
						IF @Try_Count > 0
						BEGIN
							SET @IndexStatement = REPLACE(@IndexStatement,', STATISTICS_INCREMENTAL = ON','')
							SET @IndexStatement = REPLACE(@IndexStatement,', ONLINE = ON','')
							SET @Try_Count-=1
							SET @RetryFlag = 1
							GOTO trypoint
						END
						PRINT(ERROR_MESSAGE()+'Clustered or Non-Clustered'+DB_NAME()+SUSER_SNAME())
						--------Error Logging-------------------------------------------------------------------------------------
						IF @Create_or_Update_IndexTransferResults_Table = 1	
							UPDATE IndexTransferResults SET
								IsErrorRaised	= 1,
								ErrorNo			= ERROR_NUMBER(),
								ErrorSeverity	= ERROR_SEVERITY(),
								ErrorState		= ERROR_STATE(),
								ErrorLine		= ERROR_LINE(),
								ErrorMessage	= ERROR_MESSAGE(),
								StatementEndTime			= SYSDATETIME()
							WHERE StatementID = SCOPE_IDENTITY()					
						-----------------------------------------------------------------------------------------------------------				
					END CATCH
	-------------------------------------------------------------------------------------------------------------------------------				
					FETCH NEXT FROM IndexTransfer INTO @IndexStatement, @TableName
				END 
			CLOSE IndexTransfer
			DEALLOCATE IndexTransfer						
--		END
    END

	
	
END
GO

--==================================================================================
	/* Now executing procedure for every desired database*/

CREATE OR ALTER PROC usp_move_indexes_to_another_filegroup_per_every_database
	@starting_index_id TINYINT,
	@ending_index_id TINYINT = NULL,
	@source_filegroup_or_partition_scheme_name sysname = '',
	@target_filegroup_or_partition_scheme_name sysname,		-- Possible values: {partition_scheme_name ( column_name ) | filegroup_name | default}. 
															
	@SORT_IN_TEMPDB BIT = 0,
	@STATISTICS_NORECOMPUTE BIT = 1,
	@STATISTICS_INCREMENTAL BIT = 0,						-- It's not recommended to turn this feature on because you may face the following error:
															/*
																Msg 9108, Level 16, State 9, Line 139
																This type of statistics is not supported to be incremental.
															*/
	@ONLINE BIT = 1,
	@MAXDOP TINYINT = NULL,
	@DATA_COMPRESSION NVARCHAR(10) = 'DEFAULT',				-- Possible values: {DEFAULT|NONE|ROW|PAGE}
	@DATA_COMPRESSION_PARTITIONS NVARCHAR(128) = NULL,		-- Possible values: leave it empty for the whole partitions or for example 1,3,10,11 or 1-8
	@FILESTREAM NVARCHAR (20) = 'OFF',						-- Possible values: {filestream_filegroup_name | partition_scheme_name | NULL}
	@Retry_With_Less_Options BIT = 1,
															-- If some of the transfer statements raise error on first try and this parameter is enabled, the
															-- script retries only those statements by turning off the following switches. What remains will
															-- be reported via email:
															-- 1. @STATISTICS_INCREMENTAL
															-- 2. @ONLINE

	@Email_Recipients NVARCHAR(1000) = 'amomen@gmail.com',
	@copy_recipients NVARCHAR(1000) = NULL,
	@blind_copy_recipients NVARCHAR(1000) = NULL,
	@Create_or_Update_IndexTransferResults_Table BIT = 1
AS
BEGIN
	SET NOCOUNT ON
	DECLARE @ErrMsg VARCHAR(4000)
	DECLARE @DBName sysname
	DECLARE @Start_Time DATETIME = GETDATE()
	DECLARE @Accumulated_Error_List NVARCHAR(MAX) = ''
		SET @Email_Recipients = ISNULL(@Email_Recipients,'')
	SET @copy_recipients = ISNULL(@copy_recipients,'')
	SET @blind_copy_recipients = ISNULL(@blind_copy_recipients,'')

	IF @Email_Recipients = ''
		SET @Email_Recipients = NULL

	IF @copy_recipients = ''
		SET @copy_recipients = NULL

	IF @blind_copy_recipients = ''
		SET @blind_copy_recipients = NULL

	CREATE TABLE #databases_filegroups (DBID sysname NOT NULL, FG_NAME sysname NOT NULL)

	INSERT #databases_filegroups
	EXEC sp_msforeachdb 'USE [?] SELECT DB_ID(), name fg_name FROM sys.filegroups'

	IF NOT EXISTS (SELECT 1 FROM #databases_filegroups WHERE FG_NAME = @target_filegroup_or_partition_scheme_name)
	BEGIN
		SET @ErrMsg = 'The target filegroup '''+@target_filegroup_or_partition_scheme_name+''' mentioned does not exist for any of the databases on this server.'
		SET @ErrMsg = 'Warning!!! '+@ErrMsg+' No action was carried out.'+CHAR(10)
		PRINT @ErrMsg
		--RAISERROR(@ErrMsg,16,1)
	END

	IF (SELECT OBJECT_ID('IndexTransferResults')) IS NULL
		CREATE TABLE IndexTransferResults 
		(
			StatementID INT PRIMARY KEY IDENTITY NOT NULL,
			DatabaseName sysname NOT NULL,
			TableName sysname NOT NULL,
			EntireOpeartionStartTime DATETIME NOT NULL,
			IndexTransferStatement VARCHAR(8000),
			IsErrorRaised BIT DEFAULT 0,
			ErrorNo INT,
			ErrorSeverity TINYINT,
			ErrorState TINYINT,
			ErrorLine INT,
			ErrorMessage VARCHAR(MAX),
			StatementStartTime DATETIME,
			StatementEndTime DATETIME
		)



	DECLARE executor_per_database CURSOR FOR

		SELECT DB_NAME(database_id) FROM sys.databases d
		JOIN #databases_filegroups dfg
		ON dfg.DBID = d.database_id
		and database_id > 4 AND
			DB_NAME(database_id) NOT IN ('SQLAdministrationDB','dbWarden') AND
			(
			sys.fn_hadr_is_primary_replica(DB_NAME(database_id)) = 1 OR
			sys.fn_hadr_is_primary_replica(DB_NAME(database_id)) IS NULL
			)
		AND dfg.FG_NAME = @target_filegroup_or_partition_scheme_name

	OPEN executor_per_database
		FETCH NEXT FROM executor_per_database INTO @DBName
		WHILE (@@FETCH_STATUS = 0)
		BEGIN
			BEGIN try
				EXEC usp_move_indexes_to_another_filegroup

					@DatabaseName = @DBName,
					@starting_index_id = @starting_index_id,
					@ending_index_id = @ending_index_id,
					@target_filegroup_or_partition_scheme_name = @target_filegroup_or_partition_scheme_name,		-- Possible values: {partition_scheme_name ( column_name ) | filegroup_name | default}. 
															
					@SORT_IN_TEMPDB = @SORT_IN_TEMPDB,
					@STATISTICS_NORECOMPUTE = @STATISTICS_NORECOMPUTE,
					@STATISTICS_INCREMENTAL = @STATISTICS_INCREMENTAL,						-- It's not recommended to turn this feature on because you may face the following error:
																			/*
																				Msg 9108, Level 16, State 9, Line 139
																				This type of statistics is not supported to be incremental.
																			*/
					@ONLINE = @ONLINE,
					@MAXDOP = @MAXDOP,
					@DATA_COMPRESSION = @DATA_COMPRESSION,				-- Possible values: {DEFAULT|NONE|ROW|PAGE}
					@DATA_COMPRESSION_PARTITIONS = @DATA_COMPRESSION_PARTITIONS,		-- Possible values: leave it empty for the whole partitions or for example 1,3,10,11 or 1-8
					@FILESTREAM = @FILESTREAM,						-- Possible values: {filestream_filegroup_name | partition_scheme_name | NULL}
					@StartTime = @Start_Time,								-- Stored Procedure's execution start time
					@Retry_With_Less_Options = @Retry_With_Less_Options,
																			-- If some of the transfer statements raise error on first try and this parameter is enabled, the
																			-- script retries only those statements by turning off the following switches. What remains will
																			-- be reported via email:
																			-- 1. @STATISTICS_INCREMENTAL
																			-- 2. @ONLINE
					@Create_or_Update_IndexTransferResults_Table = @Create_or_Update_IndexTransferResults_Table 


			END TRY
			BEGIN CATCH
				DECLARE @AccumulateMsgs_or_RAISERROR INT = 2			-- 1 for print 2 for RAISERROR
				SET @ErrMsg = ERROR_MESSAGE()
				DECLARE @ErrLine NVARCHAR(500) = ERROR_LINE()
				DECLARE @ErrNo nvarchar(6) = CONVERT(NVARCHAR(6),ERROR_NUMBER())
				DECLARE @ErrState nvarchar(2) = CONVERT(NVARCHAR(2),ERROR_STATE())
				DECLARE @ErrSeverity nvarchar(2) = CONVERT(NVARCHAR(2),ERROR_SEVERITY())
				DECLARE @UDErrMsg nvarchar(MAX) = 'Something went wrong during the operation. Depending on your preference the operation will fail or continue, skipping this iteration. System error message:'+CHAR(10)
						+ 'Msg '+@ErrSeverity+', Level '+@ErrSeverity+', State '+@ErrState+', Line '++@ErrLine + CHAR(10)
						+ @ErrMsg
				IF @AccumulateMsgs_or_RAISERROR = 1
				begin
					SET @Accumulated_Error_List += @UDErrMsg +
						CHAR(10) +
						'------------------------------------------------------------------------------------------------------------' +
						CHAR(10)
				end
				ELSE
				BEGIN
					PRINT (CHAR(10))
					PRINT '------------------------------------------------------------------------------------------------------------'
					PRINT (CHAR(10))
					RAISERROR(@UDErrMsg,16,1)
				END
/*
				DECLARE @mailitem_id INT;
				EXEC msdb..sp_send_dbmail @profile_name = 'PocketProfile',                -- sysname
				                          @recipients = '; amomen@gmail.com',                    -- varchar(max)
				                          @copy_recipients = '',               -- varchar(max)
				                          @blind_copy_recipients = '',         -- varchar(max)
				                          @subject = N'Failed index transfer attempts',                      -- nvarchar(255)
				                          @body = @UDErrMsg,                         -- nvarchar(max)
				                          @body_format = 'TEXT',                   -- varchar(20)
				                          --@importance = '',                    -- varchar(6)
				                          --@sensitivity = '',                   -- varchar(12)
				                          --@file_attachments = N'',             -- nvarchar(max)
				                          --@query = N'',                        -- nvarchar(max)
				                          --@execute_query_database = NULL,      -- sysname
				                          --@attach_query_result_as_file = NULL, -- bit
				                          --@query_attachment_filename = N'',    -- nvarchar(260)
				                          --@query_result_header = NULL,         -- bit
				                          --@query_result_width = 0,             -- int
				                          --@query_result_separator = '',        -- char(1)
				                          --@exclude_query_output = NULL,        -- bit
				                          --@append_query_error = NULL,          -- bit
				                          --@query_no_truncate = NULL,           -- bit
				                          --@query_result_no_padding = NULL,     -- bit
				                          @mailitem_id = @mailitem_id OUTPUT,  -- int
				                          @from_address = '',                  -- varchar(max)
				                          @reply_to = ''                       -- varchar(max)
*/				
			END CATCH

			FETCH NEXT FROM executor_per_database INTO @DBName
        END

		CLOSE executor_per_database
		DEALLOCATE executor_per_database

		------ Error Reporting-----------------------------------------------------------------------------------------------------
		IF (SELECT COUNT(*) FROM IndexTransferResults WHERE IsErrorRaised = 1 AND EntireOpeartionStartTime = @Start_Time) <> 0
		AND (@Email_Recipients <> '' AND @copy_recipients <> '' AND @blind_copy_recipients <> '') --COALESCE(@Email_Recipients ,@copy_recipients ,@blind_copy_recipients) IS NOT NULL)
		BEGIN   
			DECLARE @Title VARCHAR(50)
			SET @Title = CONCAT(CONVERT(VARCHAR(12), CAST(GETDATE() AS DATE), 109),'-',@@SERVERNAME, '-Job Error Email')
		
			DECLARE @ErrorNo VARCHAR(300) = ''
			SELECT @ErrorNo += STRING_AGG(CONVERT(VARCHAR(10),ErrorNo),', ')
			FROM IndexTransferResults

			DECLARE @ERROR_MESSAGE NVARCHAR(4000)
			SELECT @ERROR_MESSAGE = CONCAT(N'
		Transferring of Indexes Error: 

	   Job: $(ESCAPE_SQUOTE(JOBNAME)) 
	   Step: $(ESCAPE_SQUOTE(STEPNAME))'
	   ,'Error Number: ', @ErrorNo 
	   --Error Severity: ',ERROR_SEVERITY(),N'
	   --Error State: ',ERROR_STATE(),N'
	   ,'Error Procedure: ','usp_move_indexes_to_another_filegroup'
	   --Error line: ',ERROR_LINE(),N'
	   ,'Description: ','A possible combination of error messages occured, error code(s) received:', CHAR(10), @ErrorNo
	   );

	
			DECLARE @query NVARCHAR(1000) = N'SELECT * FROM IndexTransferResults' + ' WHERE IsErrorRaised = 1 AND EntireOpeartionStartTime = ' + @Start_Time 
		--	DECLARE @mailitem_id INT;
	
			EXEC msdb.dbo.sp_send_dbmail @profile_name = 'PocketProfile',                -- sysname
										 @recipients = @Email_Recipients,                    -- varchar(max)
										 @copy_recipients = @copy_recipients,               -- varchar(max)
										 @blind_copy_recipients = @blind_copy_recipients,         -- varchar(max)
										 @subject = @Title,                      -- nvarchar(255)
										 @body = @ERROR_MESSAGE,                         -- nvarchar(max)
										 @body_format = 'HTML',                   -- varchar(20)
		--	                             @importance = '',                    -- varchar(6)
		--	                             @sensitivity = '',                   -- varchar(12)
		--	                             @file_attachments = N'',             -- nvarchar(max)
										 @query = @query,                        -- nvarchar(max)
										 @execute_query_database = 'SQLAdministrationDB',      -- sysname
		--	                             @attach_query_result_as_file = NULL, -- bit
		--	                             @query_attachment_filename = N'',    -- nvarchar(260)
										 @query_result_header = 1,         -- bit
		--	                             @query_result_width = 0,             -- int
		--	                             @query_result_separator = '',        -- char(1)
		--	                             @exclude_query_output = NULL,        -- bit
										 @append_query_error = 1          -- bit
		--	                             @query_no_truncate = 1,           -- bit
		--	                             @query_result_no_padding = NULL,     -- bit
		--	                             @mailitem_id = @mailitem_id OUTPUT,  -- int
	--									 @from_address = 'amomen@gmail.com',                  -- varchar(max)
	--									 @reply_to = 'amomen@gmail.com'                       -- varchar(max)					
		

	--		;THROW 50000, @ERROR_MESSAGE , 1;  
		END
		ELSE
			PRINT('SP compeleted successfully')
END
GO

/*
TRUNCATE TABLE dbo.IndexTransferResults
DECLARE @StartTime DATETIME = GETDATE()
EXEC dbo.usp_move_indexes_to_another_filegroup @DatabaseName = 'JobVisionDB',                              -- sysname
                                               @starting_index_id = 0,                            -- tinyint
                                               @ending_index_id = 255,                              -- tinyint
                                               @source_filegroup_or_partition_scheme_name = 'PRIMARY', -- sysname
                                               @target_filegroup_or_partition_scheme_name = 'FGT', -- sysname
                                               @SORT_IN_TEMPDB = NULL,                            -- bit
                                               @STATISTICS_NORECOMPUTE = NULL,                    -- bit
                                               @STATISTICS_INCREMENTAL = NULL,                    -- bit
                                               @ONLINE = 1,                                    -- bit
                                               @MAXDOP = 4,                                       -- tinyint
                                               @DATA_COMPRESSION = N'',                           -- nvarchar(10)
                                               @DATA_COMPRESSION_PARTITIONS = N'',                -- nvarchar(128)
                                               @FILESTREAM = N'',                                 -- nvarchar(20)
                                               @StartTime = @StartTime,                -- datetime
                                               @Retry_With_Less_Options = NULL,                    -- bit
											   @Create_or_Update_IndexTransferResults_Table = 0
*/


EXEC dbo.usp_move_indexes_to_another_filegroup_per_every_database @starting_index_id = 2,                            -- tinyint
                                                            @ending_index_id = 255,                           -- tinyint
                                                            @target_filegroup_or_partition_scheme_name = 'NIX', -- sysname
                                                            @SORT_IN_TEMPDB = 0,                               -- bit
                                                            @STATISTICS_NORECOMPUTE = 0,                       -- bit
                                                            @STATISTICS_INCREMENTAL = 0,                       -- bit
                                                            @ONLINE = 1,                                       -- bit
                                                            @MAXDOP = 16,                                    -- tinyint
                                                            @DATA_COMPRESSION = 'NONE',                     -- nvarchar(10)
                                                            @DATA_COMPRESSION_PARTITIONS = NULL,               -- nvarchar(128)
                                                            @FILESTREAM = NULL,                               -- nvarchar(20)
                                                            @Retry_With_Less_Options = 1,                      -- bit
                                                            @Email_Recipients = 'ava.abshuri@gmail.com; amomen@gmail.com',                          -- nvarchar(1000)
                                                            @copy_recipients = NULL,                           -- nvarchar(1000)
                                                            @blind_copy_recipients = NULL,                      -- nvarchar(1000)
															@Create_or_Update_IndexTransferResults_Table = 0

GO

DROP PROC usp_move_indexes_to_another_filegroup
GO
DROP PROC dbo.usp_move_indexes_to_another_filegroup_per_every_database
GO


