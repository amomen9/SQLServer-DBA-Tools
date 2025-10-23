-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2023-01-15"
-- Description:         "attach dettached databases"
-- License:             "Please refer to the license file"
-- =============================================



DROP TABLE IF EXISTS #DataFilePaths
DROP TABLE IF EXISTS #DBDetails
SET NOCOUNT ON
DECLARE @path NVARCHAR(255)
DECLARE @SQL NVARCHAR(MAX)
DECLARE @CounterForNestedCursor INT = 0
DECLARE @PRINT_or_RAISERROR INT
DECLARE @ErrMsg NVARCHAR(500)
DECLARE @ErrLine NVARCHAR(500)
DECLARE @ErrNo nvarchar(6)
DECLARE @ErrState nvarchar(3)
DECLARE @ErrSeverity nvarchar(2)
DECLARE @UDErrMsg nvarchar(MAX)


CREATE TABLE #DataFilePaths(id INT NOT NULL IDENTITY PRIMARY KEY,[status] int, [fileid] smallint, [name] nchar(128), [filename] nchar(260))
CREATE TABLE #DBDetails (id INT NOT NULL IDENTITY PRIMARY KEY, [property] nvarchar(128), [value_sqlv] SQL_VARIANT, [value] AS CONVERT(sysname,value_sqlv) )

DECLARE Attacher CURSOR FOR
	SELECT full_filesystem_path FROM sys.dm_os_enumerate_filesystem('M:\SQLData','*.mdf')
OPEN Attacher
	FETCH NEXT FROM Attacher INTO @path
	WHILE @@FETCH_STATUS=0
	BEGIN
		TRUNCATE TABLE #DataFilePaths
		SET @SQL = 'DBCC checkprimaryfile(N'''+@path+''',3) WITH NO_INFOMSGS'
		BEGIN TRY
			--PRINT @path
			INSERT #DataFilePaths
			EXEC(@SQL)

			SET @SQL = 'DBCC checkprimaryfile(N'''+@path+''',2) WITH NO_INFOMSGS'
			TRUNCATE TABLE #DBDetails
			INSERT #DBDetails
			EXEC(@SQL)

			BEGIN TRY
				--PRINT @path
				SELECT @SQL = STRING_AGG(REPLICATE(CHAR(9),7)+'@filename'+CONVERT(NVARCHAR,id)+' = N'''+TRIM(filename)+'''',','+CHAR(10))
				FROM #DataFilePaths
				
				SET @SQL =
					CHAR(9)+'EXEC sys.sp_attach_db'+CHAR(9)+'@dbname = '''+(SELECT value FROM #DBDetails WHERE property='Database name')+''','+CHAR(10)+@SQL
				PRINT(@SQL)
				EXEC(@SQL)

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
				BEGIN
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

		FETCH NEXT FROM Attacher INTO @path
    END
CLOSE Attacher
DEALLOCATE Attacher

