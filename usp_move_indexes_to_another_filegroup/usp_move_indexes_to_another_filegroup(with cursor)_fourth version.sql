/*
This script has been written in 2 variants:
	1. Variant with cursor to make the script functional for databases with numerous indexes. This might be slower but has following advantages:
		a. Error handling for each individual index
		b. Should there be an error among one or more of index transfer statements, others will be applied anyways
		c. If the number of indexes to be transferred is too high and all of the index transfer statements exceed 8000 characters, this variant still works but
			the second won't.
	2. Variant without cursor to speed things up. This variant lacks the advantages mentioned above. I have not included this variant
		if you wish, ask me to send it to you.
*/
------ With CURSOR:

USE sqladministrationdb
GO

CREATE OR ALTER proc usp_move_indexes_to_another_filegroup
(
	@DatabaseName sysname,
	@starting_index_id TINYINT,
	@ending_index_id TINYINT = 10,
	@target_filegroup_or_partition_scheme_name sysname,		-- Possible values: {partition_scheme_name ( column_name ) | filegroup_name | default}. 
															
	@SORT_IN_TEMPDB BIT = 0,
	@STATISTICS_NORECOMPUTE bit = 1,
	@STATISTICS_INCREMENTAL bit = 0,						-- It's not recommended to turn this feature on because you may face the following error:
															/*
																Msg 9108, Level 16, State 9, Line 139
																This type of statistics is not supported to be incremental.
															*/
	@ONLINE BIT = 1,
	@MAXDOP TINYINT = NULL,
	@DATA_COMPRESSION NVARCHAR(10) = 'DEFAULT',				-- Possible values: {DEFAULT|NONE|ROW|PAGE}
	@DATA_COMPRESSION_PARTITIONS NVARCHAR(128) = NULL,		-- Possible values: leave it empty for the whole partitions or for example 1,3,10,11 or 1-8
	@FILESTREAM nvarchar (20) = 'OFF',						-- Possible values: {filestream_filegroup_name | partition_scheme_name | NULL}
	@StartTime DATETIME = NULL,								-- Stored Procedure's execution start time
	@Retry_With_Less_Options BIT = 1,
															-- If some of the transfer statements raise error on first try and this parameter is enabled, the
															-- script retries only those statements by turning off the following switches. What remains will
															-- be reported via email:
															-- 1. @STATISTICS_INCREMENTAL
															-- 2. @ONLINE
	
	@Email_Recipients NVARCHAR(1000) = 'amomen@gmail.com;ava.abshuri@gmail.com',
	@copy_recipients NVARCHAR(1000) = null,
	@blind_copy_recipients NVARCHAR(1000) = null
																															
)
AS
BEGIN	
	SET QUOTED_IDENTIFIER ON
	SET NOCOUNT ON
	
----- Variable Control ----------------------------------------------------------
	IF @Email_Recipients = ''
		SET @Email_Recipients = NULL

	IF @copy_recipients = ''
		SET @copy_recipients = NULL

	IF @blind_copy_recipients = ''
		SET @blind_copy_recipients = NULL

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
	IF @target_filegroup_or_partition_scheme_name IS NULL
	BEGIN
		RAISERROR ('Error. @target_filegroup_or_partition_scheme_name cannot be NULL.', 16, 1)
		RETURN 1
    END
	SET @SORT_IN_TEMPDB = ISNULL(@SORT_IN_TEMPDB,0)
	SET @STATISTICS_NORECOMPUTE = ISNULL(@STATISTICS_NORECOMPUTE,0)
	SET @STATISTICS_INCREMENTAL = ISNULL(@STATISTICS_INCREMENTAL,0)
	SET @ONLINE = ISNULL(@ONLINE,1)
	SET @MAXDOP = ISNULL(@MAXDOP,0)
	SET @DATA_COMPRESSION = ISNULL(@DATA_COMPRESSION,'DEFAULT')
	SET @DATA_COMPRESSION_PARTITIONS = ISNULL(@DATA_COMPRESSION_PARTITIONS,'DEFAULT')
	SET @FILESTREAM = ISNULL(@FILESTREAM,'OFF')
	SET @Retry_With_Less_Options = ISNULL(@Retry_With_Less_Options,1)

---------------------------------------------------------------------------------
	DECLARE @Try_Count TINYINT = @Retry_With_Less_Options
	CREATE TABLE #temp (FG_DataspaceID TINYINT)
	DECLARE @DataspaceID_Query VARCHAR(400) = 'use ' + QUOTENAME(@DatabaseName) + ' SELECT data_space_id from sys.filegroups where name = ''' + @target_filegroup_or_partition_scheme_name + ''''
	
	
	INSERT INTO #temp	
	EXEC (@DataspaceID_Query)
	
	DECLARE @FG_DataspaceID tinyint = (select TOP 1 FG_DataspaceID FROM #temp)

	DECLARE @SQL VARCHAR(MAX) = ''
	DECLARE @IndexStatement VARCHAR(max)
	IF @FG_DataspaceID IS NULL
	BEGIN
		DECLARE @EM nvarchar(300) = 'The filegroup name ''' + @target_filegroup_or_partition_scheme_name + ''', specified does not exist for the database ' + @DatabaseName 
		RAISERROR(@EM,16,1)
		RETURN 1
    END

	
	
	
	IF OBJECT_ID('IndexTransferResults') IS NULL
		CREATE TABLE IndexTransferResults 
		(
			StatementID INT PRIMARY KEY IDENTITY NOT NULL,
			DatabaseName sysname NOT NULL,
			EntireOpeartionStartTime DATETIME NOT NULL,
			IndexTransferStatement VARCHAR(8000),
			IsErrorRaised BIT DEFAULT 0,
			ErrorNo INT,
			ErrorSeverity TINYINT,
			ErrorState TINYINT,
			ErrorLine INT,
			ErrorMessage VARCHAR(MAX),
			StatementStartTime AS SYSDATETIME(),
			StatementEndTime datetime
		)
	
		
	IF (0>=@starting_index_id)
	BEGIN

		DECLARE @IndexWorkingSpace VARCHAR(8000) =
		'
			use ' + QUOTENAME(@DatabaseName) + '

			SELECT 
				''USE '' + ''' + QUOTENAME(@DatabaseName)+ ''' + CHAR(10) + ''CREATE CLUSTERED INDEX temp98439gfjkgdfjskgj4859 ON '' + QUOTENAME(SchemaName) + ''.'' + QUOTENAME(TableName) + '' ('' + (SELECT TOP 1 name from sys.all_columns WHERE object_id = TableID) + '') ON '' + ''' + QUOTENAME(@target_filegroup_or_partition_scheme_name) + ''' + ''
				 DROP INDEX temp98439gfjkgdfjskgj4859 ON '' + QUOTENAME(TableName) + CHAR(10) AS IndexStatement
			FROM		  
				(SELECT i.data_space_id, SCHEMA_NAME(t.schema_id) as SchemaName, OBJECT_NAME(i.object_id) TableName, i.object_id TableID
					FROM sys.tables t
					JOIN sys.indexes i 
					ON t.object_id = i.object_id
					WHERE i.index_id = 0
				) AS uind

			JOIN sys.filegroups fg
			ON uind.data_space_id = fg.data_space_id
			WHERE uind.data_space_id <> ' + CONVERT(VARCHAR(2),@FG_DataspaceID) + '	
		'

		DROP TABLE IF EXISTS #IndexWorkingSpace
		CREATE TABLE #IndexWorkingSpace (IndexStatement VARCHAR(4000) NOT null)
		
		INSERT #IndexWorkingSpace		
		EXEC (@IndexWorkingSpace)
		


--		IF (SELECT COUNT(*) FROM #IndexWorkingSpace) <> 0
--		BEGIN        
			declare IndexTransfer cursor 
			FOR
			(
				SELECT * FROM #IndexWorkingSpace	
			)
			open IndexTransfer

				fetch next from IndexTransfer into @IndexStatement			
				while @@FETCH_STATUS = 0
				begin
	-------------------------------------------------------------------------------------------------------------------------------
					BEGIN TRY

						INSERT INTO IndexTransferResults
						(
							DatabaseName,
							EntireOpeartionStartTime,
							IndexTransferStatement					    
						)
						VALUES
						(   
							@DatabaseName,
							@StartTime,
							@IndexStatement       -- IndexTransferStatement - varchar(8000)					    
						)
						EXEC(@IndexStatement)
						
						UPDATE IndexTransferResults SET StatementEndTime = SYSDATETIME() WHERE StatementID = SCOPE_IDENTITY()
					END TRY
					BEGIN CATCH
						PRINT(ERROR_MESSAGE()+'HEAP')
						--------Error Logging-------------------------------------------------------------------------------------
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
					fetch next from IndexTransfer into @IndexStatement
				end 
			CLOSE IndexTransfer
			DEALLOCATE IndexTransfer						
--		END
		SET @starting_index_id = 1
    END

	IF (@ending_index_id > 0)
	BEGIN		

		DECLARE @Statement NVARCHAR(max)
		SET @Statement = CONCAT(

		'

			use ' , QUOTENAME(@DatabaseName) , '
			
			SELECT 
			''USE '' + QUOTENAME(@DatabaseName) + CHAR(10) + ''CREATE '' + CASE uind.is_unique WHEN 1 THEN ''UNIQUE '' ELSE '''' END  +  CASE uind.index_id WHEN 1 then ''CLUSTERED '' ELSE '''' END + ''INDEX '' + QUOTENAME(uind.name) + '' ON '' + QUOTENAME(SchemaName) + ''.'' + QUOTENAME(TableName) + '' ('' + (SELECT STRING_AGG(QUOTENAME(name)+CASE ic.is_descending_key WHEN 1 THEN '' desc'' ELSE '''' end,'','') from sys.all_columns c JOIN sys.index_columns ic ON ic.column_id = c.column_id WHERE c.object_id = uind.TableID AND ic.object_id = uind.TableID AND ic.key_ordinal <> 0 AND index_id=uind.index_id) + '')'' + 
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
			CASE @DATA_COMPRESSION WHEN ''DEFAULT'' THEN '''' ELSE '', DATA_COMPRESSION = '' + @DATA_COMPRESSION END + CASE @DATA_COMPRESSION_PARTITIONS WHEN ''DEFAULT'' THEN '''' ELSE '' ON PARTITIONS ('' + @DATA_COMPRESSION_PARTITIONS + '')'' END +
			'')'' + CHAR(10) +
			''on '' + QUOTENAME(@target_filegroup_or_partition_scheme_name) + CHAR(10) +
			CASE @FILESTREAM WHEN ''OFF'' THEN '''' ELSE ''FILESTREAM_ON '' + @FILESTREAM + CHAR(10) END +
			CASE uind.is_disabled WHEN 1 THEN ''ALTER INDEX ''+ uind.name +'' ON ''+ uind.TableName + CHAR(10) +''DISABLE;'' ELSE '''' END            			

			FROM		  
				(SELECT i.data_space_id, OBJECT_NAME(i.object_id) TableName, SCHEMA_NAME(schema_id) SchemaName, i.object_id TableID, i.name, i.is_unique, i.is_disabled, i.filter_definition, i.ignore_dup_key, i.fill_factor, i.is_padded, i.allow_row_locks, i.allow_page_locks, i.optimize_for_sequential_key, i.index_id
			
					FROM sys.tables t
					JOIN sys.indexes i 
					ON t.object_id = i.object_id
					WHERE i.index_id between @starting_index_id AND @ending_index_id
				) AS uind		-- user indexes

			JOIN sys.filegroups fg
			ON uind.data_space_id = fg.data_space_id
			WHERE uind.data_space_id <> @FG_DataspaceID
		'
		)

		DROP TABLE IF EXISTS #IndexWorkingSpace2
		CREATE TABLE #IndexWorkingSpace2 (IndexStatement VARCHAR(8000) NOT null)
		DECLARE @params NVARCHAR(max) =
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
			@FG_DataspaceID tinyint
		'
		
		
		INSERT #IndexWorkingSpace2
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
		@FG_DataspaceID
		
--		IF (SELECT COUNT(*) FROM #IndexWorkingSpace2) <> 0
--		BEGIN
			DECLARE IndexTransfer cursor 
			FOR
			(
				SELECT * FROM #IndexWorkingSpace2	
			)
			open IndexTransfer

				fetch next from IndexTransfer into @IndexStatement			
				while @@FETCH_STATUS = 0
				begin
	-------------------------------------------------------------------------------------------------------------------------------				
					BEGIN TRY

						INSERT INTO IndexTransferResults
						(
							DatabaseName,
							EntireOpeartionStartTime,
							IndexTransferStatement					    
						)
						VALUES
						(   
							@DatabaseName,
							@StartTime,
							@IndexStatement       -- IndexTransferStatement - varchar(8000)					    
						)

						TRYPOINT:
						EXEC(@IndexStatement)
						UPDATE IndexTransferResults SET StatementEndTime = SYSDATETIME() WHERE StatementID = SCOPE_IDENTITY()
					END TRY
					BEGIN CATCH
						IF @Try_Count > 0
						begin
							SET @IndexStatement = REPLACE(@IndexStatement,', STATISTICS_INCREMENTAL = ON','')
							SET @IndexStatement = REPLACE(@IndexStatement,', ONLINE = ON','')
							SET @Try_Count-=1
							GOTO trypoint
						END
						PRINT(ERROR_MESSAGE()+'Clustered or Non-Clustered'+DB_NAME()+SUSER_SNAME())
						--------Error Logging-------------------------------------------------------------------------------------
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
					fetch next from IndexTransfer into @IndexStatement
				end 
			CLOSE IndexTransfer
			DEALLOCATE IndexTransfer						
--		END
    END
	------ Error Reporting-----------------------------------------------------------------------------------------------------
	IF ((SELECT COUNT(*) FROM IndexTransferResults WHERE IsErrorRaised = 1 AND EntireOpeartionStartTime = @StartTime) <> 0
	AND COALESCE(@Email_Recipients ,@copy_recipients ,@blind_copy_recipients) IS NOT NULL)
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

	
		DECLARE @query NVARCHAR(1000) = N'SELECT * FROM IndexTransferResults' + ' WHERE IsErrorRaised = 1 AND EntireOpeartionStartTime = ' + @StartTime 
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
go

/*
	EXEC usp_move_indexes_to_another_filegroup

			@DatabaseName,
			@starting_index_id,
			@ending_index_id,
			@target_filegroup_or_partition_scheme_name,		-- Possible values: {partition_scheme_name ( column_name ) | filegroup_name | default}. 
															
			@SORT_IN_TEMPDB = 0,
			@STATISTICS_NORECOMPUTE = 1,
			@STATISTICS_INCREMENTAL = 0,						-- It's not recommended to turn this feature on because you may face the following error:
																	/*
																		Msg 9108, Level 16, State 9, Line 139
																		This type of statistics is not supported to be incremental.
																	*/
			@ONLINE = 1,
			@MAXDOP = 4,
			@DATA_COMPRESSION = 'NONE',				-- Possible values: {DEFAULT|NONE|ROW|PAGE}
			@DATA_COMPRESSION_PARTITIONS = NULL,		-- Possible values: leave it empty for the whole partitions or for example 1,3,10,11 or 1-8
			@FILESTREAM = NULL,						-- Possible values: {filestream_filegroup_name | partition_scheme_name | NULL}
			@StartTime = GETDATE(),								-- Stored Procedure's execution start time
			@Retry_With_Less_Options = 1,
																	-- If some of the transfer statements raise error on first try and this parameter is enabled, the
																	-- script retries only those statements by turning off the following switches. What remains will
																	-- be reported via email:
																	-- 1. @STATISTICS_INCREMENTAL
																	-- 2. @ONLINE
	
			@Email_Recipients,
			@copy_recipients,
			@blind_copy_recipients
																															

																															
*/


--SELECT * FROM sys.all_sql_modules