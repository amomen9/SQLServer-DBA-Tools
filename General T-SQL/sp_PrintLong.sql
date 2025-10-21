-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2022-12-14"
-- Description:         "sp_PrintLong"
-- License:             "Please refer to the license file"
-- =============================================



﻿--USE master
--DROP PROC dbo.sp_PrintLong

USE master
GO



CREATE OR ALTER PROC sp_PrintLong
@String NVARCHAR(MAX)
AS
BEGIN
	DECLARE @NewLineLocation INT,
			@TempStr NVARCHAR(4000),
			@Length INT,
			@carriage BIT

	WHILE @String <> ''
	BEGIN
		IF LEN(@String)<=4000
		BEGIN 
			PRINT @String
			BREAK
		END 
		ELSE
        BEGIN 
			SET @TempStr = SUBSTRING(@String,1,4000)
			SELECT @NewLineLocation = CHARINDEX(CHAR(10),REVERSE(@TempStr))

			IF CHARINDEX(CHAR(13),REVERSE(@TempStr)) - @NewLineLocation = 1
				SET @carriage = 1
			ELSE
				SET @carriage = 0

			SET @TempStr = LEFT(@TempStr,(4000-@NewLineLocation)-CONVERT(INT,@carriage))

			PRINT @TempStr
		
			SET @Length = LEN(@String)-LEN(@TempStr)-CONVERT(INT,@carriage)-1
			SET @String = RIGHT(@String,@Length)
			
		END 
	END
END
GO

--============================================================================================

DECLARE @def NVARCHAR(MAX)
--SELECT @def=definition FROM sys.all_sql_modules WHERE OBJECT_ID > 0 AND LEN(definition) = (SELECT MAX(LEN(definition)) FROM sys.all_sql_modules WHERE OBJECT_ID > 0)
SELECT TOP 1 @def = definition FROM sys.all_sql_modules ORDER BY LEN(definition) DESC
PRINT (LEN(@def))
EXEC dbo.sp_PrintLong @String = @def -- nvarchar(max)


DROP PROC dbo.sp_PrintLong
GO

