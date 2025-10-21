-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2022-09-19"
-- Description:         "Change Collation of all table columns within a database"
-- License:             "Please refer to the license file"
-- =============================================



CREATE OR ALTER PROC usp_Collation_Changer
AS
BEGIN
	DECLARE @schema_name sysname,
			@table_name sysname,
			@column_name sysname,
			@type sysname,
			@max_length VARCHAR(4),
			@SQL NVARCHAR(max),
			@is_nullable BIT,
			@Database_Collation NVARCHAR(100) = CONVERT(NVARCHAR(100), DATABASEPROPERTYEX(DB_NAME(),'Collation'))
        
	DECLARE CollationChanger CURSOR FOR
		SELECT
			SCHEMA_NAME(t.schema_id),
			OBJECT_NAME(c.object_id) table_name,
			c.name column_name,
			TYPE_NAME(c.user_type_id) type,
			CONVERT(VARCHAR(4),c.max_length),
			c.is_nullable
		FROM sys.all_columns c JOIN sys.tables t
		ON t.object_id = c.object_id
		WHERE c.collation_name IS NOT NULL and c.collation_name <> @Database_Collation
			AND c.is_computed = 0  
	OPEN CollationChanger
		FETCH NEXT FROM CollationChanger INTO @schema_name, @table_name, @column_name, @type, @max_length, @is_nullable
		WHILE @@FETCH_STATUS = 0
		BEGIN
			BEGIN TRY 
				SET @SQL = 'ALTER TABLE '+QUOTENAME(@schema_name)+'.'+QUOTENAME(@table_name)+' ALTER COLUMN '+QUOTENAME(@column_name)+' '+@type+ 
							CASE 
								WHEN @type IN ('char','varchar') THEN '('+IIF(@max_length<> -1,@max_length,'MAX')+')'
								WHEN @type IN ('nchar','nvarchar') THEN '('+IIF(@max_length<> -1,CONVERT(VARCHAR(4),CONVERT(INT,@max_length)/2),'MAX')+')'
								ELSE ''
							END +
							' COLLATE '+@Database_Collation +
							IIF(@is_nullable = 1, ' NULL', ' NOT NULL')
				--PRINT @SQL
				EXEC (@SQL)
			END TRY
			BEGIN CATCH
				DECLARE @PRINT_or_RAISERROR INT = 2			-- 1 for print 2 for RAISERROR
				DECLARE @ErrMsg NVARCHAR(500) = ERROR_MESSAGE()
				DECLARE @ErrLine NVARCHAR(500) = ERROR_LINE()
				DECLARE @ErrNo nvarchar(6) = CONVERT(NVARCHAR(6),ERROR_NUMBER())
				DECLARE @ErrState nvarchar(2) = CONVERT(NVARCHAR(2),ERROR_STATE())
				DECLARE @ErrSeverity nvarchar(2) = CONVERT(NVARCHAR(2),ERROR_SEVERITY())
				DECLARE @UDErrMsg nvarchar(MAX) = 'Something went wrong during the operation. Depending on your preference the operation will fail or continue, skipping this iteration.'+CHAR(10)+'System error message:'+CHAR(10)
						+ 'Msg '+@ErrNo+', Level '+@ErrSeverity+', State '+@ErrState+', Line '++@ErrLine + CHAR(10)
						+ @ErrMsg
				IF @PRINT_or_RAISERROR = 1
				begin
					PRINT @UDErrMsg
					PRINT (CHAR(10))
					PRINT '------------------------------------------------------------------------------------------------------------'
					PRINT (CHAR(10))
				end
				ELSE
				BEGIN
					PRINT (CHAR(10))
					PRINT '------------------------------------------------------------------------------------------------------------'
					PRINT (CHAR(10))
					RAISERROR(@UDErrMsg,16,1)
				END 
			END CATCH


			FETCH NEXT FROM CollationChanger INTO @schema_name, @table_name, @column_name, @type, @max_length, @is_nullable
		END
	CLOSE CollationChanger
	DEALLOCATE CollationChanger
END
GO

EXEC dbo.usp_Collation_Changer


DROP PROC dbo.usp_Collation_Changer
GO

--SELECT * FROM sys.all_columns WHERE collation_name LIKE 'persian%'