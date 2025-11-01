/*
    generate_system_db_structure.sql
    ---------------------------------
    Run this script on the source SQL Server instance ("server 1").
    It emits T-SQL that can be executed on the target instance ("server 2")
    to mirror the physical layout (paths, logical names, sizes, growth
    settings) of key system databases: tempdb, model, model_replicatedmaster,
    model_replicatedmsdb, and msdb. The generated script also includes
    xp_create_subdir calls for any directories required by those files.
*/

CREATE OR ALTER PROC usp_PrintLong
	@String NVARCHAR(MAX),
	@Max_Chunk_Size SMALLINT = 4000,
	@Print_String_Length BIT = 0
AS
BEGIN
	SET NOCOUNT ON
	SET @Max_Chunk_Size = ISNULL(@Max_Chunk_Size,4000)
	IF @Max_Chunk_Size > 4000 OR @Max_Chunk_Size<50 BEGIN RAISERROR('Wrong @Max_Chunk_Size cannot be bigger than 4000. A value less than 50 for this parameter is also not supported.',16,1) RETURN 1 END
	DECLARE @NewLineLocation INT,
			@TempStr NVARCHAR(4000),
			@Length INT,
			@carriage BIT,
			@SeparatorNewLineFlag BIT,
			@Temp_Max_Chunk_Size INT

	CREATE TABLE #MinSeparator
	(
		id INT IDENTITY PRIMARY KEY NOT NULL,
		Separator VARCHAR(2),
		SeparatorReversePosition INT
	)

	WHILE @String <> ''
	BEGIN
		IF LEN(@String)<=@Max_Chunk_Size
		BEGIN 
			PRINT @String
			BREAK
		END 
		ELSE
        BEGIN
			SET @Temp_Max_Chunk_Size = @Max_Chunk_Size
			StartWithChunk:
			SET @TempStr = SUBSTRING(@String,1,@Temp_Max_Chunk_Size)
			SELECT @NewLineLocation = CHARINDEX(CHAR(10),REVERSE(@TempStr))
			DECLARE @MinSeparator INT

			TRUNCATE TABLE #MinSeparator
			INSERT #MinSeparator
			(
			    Separator,
			    SeparatorReversePosition
			)
			VALUES ('.', CHARINDEX('.',REVERSE(@TempStr))), (')', CHARINDEX(')',REVERSE(@TempStr))), ('(', CHARINDEX('(',REVERSE(@TempStr))), (',', CHARINDEX(',',REVERSE(@TempStr))), ('-', CHARINDEX('-',REVERSE(@TempStr))), ('*', CHARINDEX('*',REVERSE(@TempStr))), ('/', CHARINDEX('/',REVERSE(@TempStr))), ('+', CHARINDEX('+',REVERSE(@TempStr))), (CHAR(32), CHARINDEX(CHAR(32),REVERSE(@TempStr))), (CHAR(9), CHARINDEX(CHAR(9),REVERSE(@TempStr)))
			SELECT @MinSeparator = MIN(SeparatorReversePosition) FROM #MinSeparator WHERE SeparatorReversePosition<>0

			IF @NewLineLocation=0 AND @MinSeparator IS NOT NULL
			BEGIN
				SET @SeparatorNewLineFlag = 0				
				SET @NewLineLocation = @MinSeparator
			END
			ELSE
				IF @NewLineLocation<>0	SET @SeparatorNewLineFlag = 1
			
			IF @NewLineLocation = 0 OR @NewLineLocation=@Max_Chunk_Size BEGIN SET @Temp_Max_Chunk_Size+=50 GOTO StartWithChunk END

			IF CHARINDEX(CHAR(13),REVERSE(@TempStr)) - @NewLineLocation = 1
				SET @carriage = 1
			ELSE
				SET @carriage = 0

			SET @TempStr = LEFT(@TempStr,(@Temp_Max_Chunk_Size-@NewLineLocation)-CONVERT(INT,@carriage))

			PRINT @TempStr
		
			SET @Length = LEN(@String)-LEN(@TempStr)-CONVERT(INT,@carriage)-1+CONVERT(INT,~@SeparatorNewLineFlag)
			SET @String = RIGHT(@String,@Length)
			
		END 
	END
	IF @Print_String_Length = 1
		PRINT '------------------------------'+CHAR(10)+'------String total length:'+CHAR(10)+CONVERT(NVARCHAR(100),(DATALENGTH(@String)/2))+CHAR(10)+'------Total line numbers:'+CHAR(10)+CONVERT(NVARCHAR(100),LEN(@String)-LEN(REPLACE(@String,CHAR(10),'')))+CHAR(10)+'------------------------------'
END
GO


DROP TABLE IF EXISTS #submodels
DROP TABLE IF EXISTS #Formatted
GO

SET NOCOUNT ON;

DECLARE @CRLF            nchar(2) = NCHAR(13) + NCHAR(10);
DECLARE @DoubleCRLF      nchar(4) = NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10);
DECLARE @Script          nvarchar(MAX) = N'';
DECLARE @DirectoryScript nvarchar(MAX);
DECLARE @FileScript      nvarchar(MAX);
DECLARE @TempdbOverrideMB decimal(18,2) = NULL; -- Set to a value (in MB) to override all tempdb file sizes

CREATE TABLE #Formatted
(
    database_name        sysname,
    file_id              int,
    type_desc            nvarchar(60),
    logical_name         sysname,
    physical_name        nvarchar(260),
    directory_path       nvarchar(4000),
    size_kb              bigint,
    size_mb_numeric      decimal(18,6),
    max_size             int,
    growth               int,
    is_percent_growth    bit,
    logical_name_escaped nvarchar(520),
    physical_name_escaped nvarchar(520),
    size_mb_text         nvarchar(30),
    size_mb_command      nvarchar(30),
    growth_text          nvarchar(40),
    maxsize_text         nvarchar(60)
);

INSERT INTO #Formatted
(
    database_name,
    file_id,
    type_desc,
    logical_name,
    physical_name,
    directory_path,
    size_kb,
    size_mb_numeric,
    max_size,
    growth,
    is_percent_growth,
    logical_name_escaped,
    physical_name_escaped,
    size_mb_text,
    size_mb_command,
    growth_text,
    maxsize_text
)
SELECT
    db.name AS database_name,
    mf.file_id,
    mf.type_desc,
    mf.name AS logical_name,
    mf.physical_name,
    CASE
        WHEN CHARINDEX(N'\', mf.physical_name) = 0 THEN mf.physical_name
        ELSE LEFT(mf.physical_name, LEN(mf.physical_name) - CHARINDEX(N'\', REVERSE(mf.physical_name)))
    END AS directory_path,
    CAST(mf.size AS bigint) * 8 AS size_kb,
    finalfmt.SizeNumeric,
    mf.max_size,
    mf.growth,
    mf.is_percent_growth,
    REPLACE(mf.name, NCHAR(39), NCHAR(39) + NCHAR(39)),
    REPLACE(mf.physical_name, NCHAR(39), NCHAR(39) + NCHAR(39)),
    finalfmt.SizeText,
    finalfmt.SizeCommand,
    finalfmt.GrowthText,
    finalfmt.MaxSizeText
FROM sys.master_files AS mf
INNER JOIN sys.databases AS db
    ON db.database_id = mf.database_id
CROSS APPLY (
    SELECT
        CAST(mf.size AS decimal(18,6)) / 128.0 AS BaseSizeMB,
        CASE WHEN mf.is_percent_growth = 1 THEN NULL ELSE CAST(mf.growth AS decimal(18,6)) / 128.0 END AS GrowthMB,
        CASE WHEN mf.max_size > 0 THEN CAST(mf.max_size AS decimal(18,6)) / 128.0 END AS MaxMB
) AS calc
CROSS APPLY (
    SELECT CASE WHEN db.name = N'tempdb' AND @TempdbOverrideMB IS NOT NULL THEN CAST(@TempdbOverrideMB AS decimal(18,6)) ELSE calc.BaseSizeMB END AS FinalSizeMB
) AS finalsizes
CROSS APPLY (
    SELECT
        finalsizes.FinalSizeMB AS SizeNumeric,
        CONVERT(nvarchar(30), CONVERT(decimal(18,2), finalsizes.FinalSizeMB)) AS SizeText,
        CASE
            WHEN ABS(finalsizes.FinalSizeMB - FLOOR(finalsizes.FinalSizeMB)) < 0.000001
                THEN CONVERT(nvarchar(30), CONVERT(bigint, FLOOR(finalsizes.FinalSizeMB)))
            ELSE CONVERT(nvarchar(30), CONVERT(decimal(18,2), finalsizes.FinalSizeMB))
        END AS SizeCommand,
        CASE
            WHEN mf.is_percent_growth = 1 THEN CAST(mf.growth AS nvarchar(20)) + N'%'
            WHEN calc.GrowthMB IS NULL OR calc.GrowthMB = 0 THEN N'0MB'
            WHEN ABS(calc.GrowthMB - FLOOR(calc.GrowthMB)) < 0.000001
                THEN CONVERT(nvarchar(30), CONVERT(bigint, FLOOR(calc.GrowthMB))) + N'MB'
            ELSE CONVERT(nvarchar(30), CONVERT(decimal(18,2), calc.GrowthMB)) + N'MB'
        END AS GrowthText,
        CASE
            WHEN mf.max_size = -1 THEN N'MAXSIZE = UNLIMITED'
            WHEN mf.max_size = 0 THEN N'MAXSIZE = 0MB'
            WHEN calc.MaxMB IS NULL THEN N'MAXSIZE = 0MB'
            WHEN ABS(calc.MaxMB - FLOOR(calc.MaxMB)) < 0.000001
                THEN N'MAXSIZE = ' + CONVERT(nvarchar(30), CONVERT(bigint, FLOOR(calc.MaxMB))) + N'MB'
            ELSE N'MAXSIZE = ' + CONVERT(nvarchar(30), CONVERT(decimal(18,2), calc.MaxMB)) + N'MB'
        END AS MaxSizeText
) AS finalfmt
WHERE db.name IN (N'tempdb', N'model', N'msdb');


CREATE TABLE #submodels
(
    parentdb sysname,
    database_name sysname,
    logical_name sysname,
    logical_name_escaped sysname NULL,
    physical_basename NVARCHAR(256),
    physical_basename_escaped NVARCHAR(256) NULL,
    type_desc NVARCHAR(60),
	file_id SMALLINT
);
INSERT #submodels
(
	parentdb,
    database_name,
    logical_name,
    physical_basename,
	logical_name_escaped,
	physical_basename_escaped,
	type_desc,
	file_id
)
SELECT 'model' parentdb, 'model_msdb' database_name, 'MSDBData' logical_name, 'model_msdbdata.mdf' physical_basename, NULL logical_name_escaped, NULL physical_basename_escaped, 'ROWS' type_desc, 1 file_id
UNION ALL 
SELECT 'model' parentdb, 'model_msdb' database_name, 'MSDBLog' logical_name, 'model_msdblog.ldf' physical_basename, NULL logical_name_escaped, NULL physical_basename_escaped, 'LOG' type_desc, 2 file_id
-------------------
UNION ALL 
-------------------
SELECT 'model' parentdb, 'model_replicatedmaster' database_name, 'replicatedmaster' logical_name, 'model_replicatedmaster.mdf' physical_basename, NULL logical_name_escaped, NULL physical_basename_escaped, 'ROWS' type_desc, 1 file_id
UNION ALL 
SELECT 'model' parentdb, 'model_replicatedmaster' database_name, 'replicatedmasterlog' logical_name, 'model_replicatedmaster.ldf' physical_basename, NULL logical_name_escaped, NULL physical_basename_escaped, 'LOG' type_desc, 2 file_id

UPDATE #submodels
SET logical_name_escaped = REPLACE(logical_name, NCHAR(39), NCHAR(39) + NCHAR(39)),
	physical_basename_escaped = REPLACE(physical_basename, NCHAR(39), NCHAR(39) + NCHAR(39))


INSERT #Formatted
SELECT
    models.database_name,
    models.file_id,
    models.type_desc,
    models.logical_name,
    LEFT(f.physical_name, LEN(f.physical_name) - CHARINDEX('\', REVERSE(f.physical_name))) + '\' + models.physical_basename physical_name,
    directory_path,
    size_kb,
    size_mb_numeric,
    max_size,
    growth,
    is_percent_growth,
    models.logical_name_escaped,
    LEFT(f.physical_name, LEN(f.physical_name_escaped) - CHARINDEX('\', REVERSE(f.physical_name_escaped))) + '\' + models.physical_basename_escaped physical_name_escaped,
    size_mb_text,
    size_mb_command,
    growth_text,
    maxsize_text
FROM #Formatted f JOIN #submodels models
ON f.database_name = models.parentdb AND models.file_id = f.file_id



-- @DirectoryScript is for EXEC master.dbo.xp_create_subdir statements to create directories on target
SELECT @DirectoryScript =
    STRING_AGG(CONVERT(NVARCHAR(MAX),N'EXEC master.dbo.xp_create_subdir N''' + REPLACE(directory_path, NCHAR(39), NCHAR(39) + NCHAR(39)) + N''';'), @CRLF)
    WITHIN GROUP (ORDER BY directory_path)
FROM (
    SELECT DISTINCT directory_path
    FROM #Formatted
    WHERE directory_path IS NOT NULL AND LEN(directory_path) > 0
) AS dirs;

IF @DirectoryScript IS NOT NULL
BEGIN
    SET @Script += N'-- Ensure directory structure exists on target server' + @CRLF
                 + @DirectoryScript + @CRLF
                 + N'GO' + @CRLF + @CRLF;
END;

-- Always switch to master before adjusting system database files.
SET @Script += N'USE [master];' + @CRLF + N'GO' + @CRLF + @CRLF;


-- @FileScript is for database file MOVE,Change Size, Change Autogrowth, etc statements
SELECT @FileScript =
    STRING_AGG(CONVERT(NVARCHAR(MAX),
        N'-- Database: ' + QUOTENAME(database_name) + N' | File: ' + logical_name + N' (' + type_desc + N')' + @CRLF +
        N'-- Size (MB): ' + size_mb_text + N' | Growth setting: ' + growth_text + N' | ' + maxsize_text + @CRLF +
        N'ALTER DATABASE ' + QUOTENAME(database_name) + N' MODIFY FILE ( NAME = N''' + logical_name_escaped + N''', FILENAME = N''' + physical_name_escaped + N''', SIZE = ' + size_mb_command + N'MB, FILEGROWTH = ' + growth_text + N', ' + maxsize_text + N' );' + @CRLF +
    N'GO')
    , @DoubleCRLF
    ) WITHIN GROUP (
        ORDER BY CASE database_name
                     WHEN N'tempdb' THEN 0
                     WHEN N'model' THEN 1
                     WHEN N'msdb' THEN 2
                     WHEN N'model_replicatedmaster' THEN 3
                     WHEN N'model_msdb' THEN 4
                     ELSE 5
                 END,
                 file_id
    )
FROM #Formatted;

IF @FileScript IS NOT NULL
BEGIN
    SET @Script += @FileScript + @CRLF;
END;

SELECT
    database_name,
    STRING_AGG(logical_name + N' (' + size_mb_text + N' MB)', N'; ') WITHIN GROUP (ORDER BY file_id) AS files_and_sizes,
    CONVERT(decimal(18,2), SUM(size_mb_numeric)) AS total_size_mb
FROM #Formatted
GROUP BY database_name
ORDER BY CASE database_name
             WHEN N'tempdb' THEN 0
             WHEN N'model' THEN 1
             WHEN N'msdb' THEN 2
             WHEN N'model_replicatedmaster' THEN 3
             WHEN N'model_msdb' THEN 4
             ELSE 5
         END;

-- Prepend header metadata for clarity.
SET @Script = N'-- Generated on ' + CONVERT(nvarchar(30), SYSDATETIME(), 126) + N' from ' + QUOTENAME(@@SERVERNAME) + @CRLF +
              N'-- Execute on target server to align system database file layout with source.' + @CRLF + @CRLF +
              @Script;

SELECT value Script
FROM STRING_SPLIT(REPLACE(@Script,CHAR(13),''),CHAR(10));


EXEC dbo.usp_PrintLong  @Script


