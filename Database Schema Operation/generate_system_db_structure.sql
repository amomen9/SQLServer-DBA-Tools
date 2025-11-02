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

CREATE OR ALTER PROCEDURE usp_get_sys_databases_script
	@TempDB_Sizes_Override_MB decimal(18,2) = NULL, -- Set to a value (in MB) to override all tempdb file sizes
	@Show_DB_Sizes_Info BIT = 1,					-- Show sizes report for the databases data files
	@SQLCMD_Connect_Clause NVARCHAR(MAX) = NULL	-- Connection string to be written in front of :connect if you want to
													-- execute the query on the target machine using SQLCMD Mode
AS
BEGIN

	SET NOCOUNT ON;

	DECLARE @CRLF            nchar(2) = NCHAR(13) + NCHAR(10);
	DECLARE @DoubleCRLF      nchar(4) = NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10);
	DECLARE @Script          nvarchar(MAX) = N'';
	DECLARE @DirectoryScript nvarchar(MAX);
	DECLARE @FileScript      nvarchar(MAX);


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
		SELECT CASE WHEN db.name = N'tempdb' AND @TempDB_Sizes_Override_MB IS NOT NULL THEN CAST(@TempDB_Sizes_Override_MB AS decimal(18,6)) ELSE calc.BaseSizeMB END AS FinalSizeMB
	) AS finalsizes
	CROSS APPLY (
		SELECT
			CAST(CEILING(finalsizes.FinalSizeMB) AS decimal(18,0)) AS SizeNumeric,
			CONVERT(nvarchar(30), CONVERT(bigint, CEILING(finalsizes.FinalSizeMB))) AS SizeText,
			CONVERT(nvarchar(30), CONVERT(bigint, CEILING(finalsizes.FinalSizeMB))) AS SizeCommand,
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

	IF CONVERT(INT,SERVERPROPERTY('ProductMajorVersion'))>15
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
	SELECT @FileScript = '' 

	-- Add required variable declaration:
	DECLARE @VariableDeclaration NVARCHAR(MAX) =
	'
	DECLARE @Override decimal(18,2)
	DECLARE @BaseSizeMB decimal(18,2);
	DECLARE @BaseGrowth nvarchar(100);
	DECLARE @BaseMax nvarchar(100);
	DECLARE @AddSql nvarchar(max)
	'

	-- @FileScript is for database file MOVE,Change Size, Change Autogrowth, etc statements
--------------------------------------------------------------------------------------------
	DECLARE @RemoveScript nvarchar(max);

	-- Build modify/add script (guarantee non-NULL result)
	-- Step 1: Generate the script for modifying/adding files and store it in @FileScript.
	DECLARE @ModifyAddScript nvarchar(max) = N'';
	
	WITH F AS (
	    SELECT *,
	           db_escaped = REPLACE(database_name, N'''', N'''''')
	    FROM #Formatted
	)
	SELECT @ModifyAddScript = 
	@VariableDeclaration +
	STRING_AGG(
	    CONVERT(nvarchar(max),
	        N'-- Database: ' + QUOTENAME(database_name) + N' | File: ' + logical_name + N' (' + type_desc + N')' + @CRLF +
	        N'-- Size (MB): ' + size_mb_text + N' | Growth setting: ' + growth_text + N' | ' + maxsize_text + @CRLF +
	        N'IF EXISTS (SELECT 1 FROM sys.master_files WHERE database_id = DB_ID(N''' + db_escaped + N''') AND file_id = ' + CAST(file_id AS nvarchar(10)) + N')' + @CRLF +
	        N'BEGIN' + @CRLF +
	        N'    ALTER DATABASE ' + QUOTENAME(database_name) + N' MODIFY FILE ( NAME = N''' + logical_name_escaped + N''', FILENAME = N''' + physical_name_escaped + N''', SIZE = ' + size_mb_command + N'MB, FILEGROWTH = ' + growth_text + N', ' + maxsize_text + N' );' + @CRLF +
	        N'END' + @CRLF +
	        N'ELSE' + @CRLF +
	        N'BEGIN' + @CRLF +
	        N'    SELECT @Override = TRY_CONVERT(decimal(18,2), NULLIF('+ISNULL(CONVERT(NVARCHAR(50),@TempDB_Sizes_Override_MB),'NULL')+', N''''));' + @CRLF +
	        N'    SELECT @BaseSizeMB = CASE WHEN N''' + database_name + N''' = N''tempdb'' AND @Override IS NOT NULL THEN @Override ELSE CEILING(size / 128.0) END,' + @CRLF +
	        N'           @BaseGrowth = CASE WHEN is_percent_growth = 1 THEN CAST(growth AS nvarchar(20)) + N''%'' WHEN growth = 0 THEN N''0MB'' ELSE CAST(CEILING(growth / 128.0) AS nvarchar(20)) + N''MB'' END,' + @CRLF +
	        N'           @BaseMax = CASE WHEN max_size = -1 THEN N''UNLIMITED'' WHEN max_size = 0 OR max_size IS NULL THEN N''0MB'' ELSE CAST(CEILING(max_size / 128.0) AS nvarchar(20)) + N''MB'' END' + @CRLF +
	        N'    FROM sys.master_files WHERE database_id = DB_ID(N''' + db_escaped + N''') AND file_id = 1;' + @CRLF +
	        N'    IF @BaseSizeMB IS NULL SET @BaseSizeMB = ' + size_mb_command + N';' + @CRLF +
	        N'    IF @BaseGrowth IS NULL SET @BaseGrowth = N''' + growth_text + N''';' + @CRLF +
	        N'    IF @BaseMax IS NULL SET @BaseMax = N''' + REPLACE(maxsize_text, N'MAXSIZE = ', N'') + N''';' + @CRLF +
	        N'    SELECT @AddSql = N''ALTER DATABASE ' + QUOTENAME(database_name) + CASE WHEN type_desc = N'LOG' THEN N' ADD LOG FILE ' ELSE N' ADD FILE ' END +
	        N'( NAME = N'''' + logical_name_escaped + N'''', FILENAME = N'''' + physical_name_escaped + N'''', SIZE = '' + CONVERT(nvarchar(30), @BaseSizeMB) + N''MB, FILEGROWTH = '' + @BaseGrowth + N'', MAXSIZE = '' + @BaseMax + N'' );'';' + @CRLF +
	        N'    EXEC sys.sp_executesql @AddSql;' + @CRLF +
	        N'END' + @CRLF +
	        N'GO'
	    ),
	    @DoubleCRLF
	) WITHIN GROUP (ORDER BY CASE database_name WHEN N'tempdb' THEN 0 WHEN N'model' THEN 1 WHEN N'msdb' THEN 2 ELSE 3 END, file_id)
	FROM F;
	
	-- Step 2: Generate the script for removing extra files and store it in @RemoveScript.
	--DECLARE @RemoveScript nvarchar(max) = N'';
	WITH Desired AS (
	    SELECT database_name, file_id FROM #Formatted
	),
	ExtraFiles AS (
	    SELECT db.name AS database_name,
	           REPLACE(db.name, N'''', N'''''') AS db_escaped,
	           mf.file_id,
	           mf.name AS logical_name,
	           REPLACE(mf.name, N'''', N'''''') AS logical_name_escaped
	    FROM sys.master_files AS mf
	    JOIN sys.databases AS db ON db.database_id = mf.database_id
	    WHERE db.name IN (SELECT DISTINCT database_name FROM #Formatted)
	      AND NOT EXISTS (SELECT 1 FROM Desired AS d WHERE d.database_name = db.name AND d.file_id = mf.file_id)
	)
	SELECT @RemoveScript = STRING_AGG(
	    CONVERT(nvarchar(max),
	        N'-- Removing extra file: ' + QUOTENAME(database_name) + N' | ' + logical_name + @CRLF +
	        N'IF EXISTS (SELECT 1 FROM sys.master_files WHERE database_id = DB_ID(N''' + db_escaped + N''') AND file_id = ' + CAST(file_id AS nvarchar(10)) + N')' + @CRLF +
	        N'BEGIN' + @CRLF +
	        N'    ALTER DATABASE ' + QUOTENAME(database_name) + N' REMOVE FILE N''' + logical_name_escaped + N''';' + @CRLF +
	        N'END' + @CRLF +
	        N'GO'
	    ),
	    @DoubleCRLF
	)
	FROM ExtraFiles;
	
	-- Step 3: Combine the two generated scripts into the final @FileScript variable.
	SET @FileScript += ISNULL(@ModifyAddScript, N'') +
	                  CASE WHEN LEN(ISNULL(@ModifyAddScript, N'')) > 0 AND LEN(ISNULL(@RemoveScript, N'')) > 0 THEN @DoubleCRLF ELSE N'' END +
	                  ISNULL(@RemoveScript, N'');
	
	-- Append remove script (also non-NULL)
	WITH Desired AS (
	    SELECT database_name, file_id
	    FROM #Formatted
	),
	ExtraFiles AS (
	    SELECT db.name AS database_name,
	           REPLACE(db.name, N'''', N'''''') AS db_escaped,
	           mf.file_id,
	           REPLACE(mf.name, N'''', N'''''') AS logical_name_escaped
	    FROM sys.master_files AS mf
	    JOIN sys.databases AS db ON db.database_id = mf.database_id
	    WHERE db.name IN (N'tempdb', N'model', N'msdb', N'model_replicatedmaster', N'model_msdb')
	      AND NOT EXISTS (
	            SELECT 1
	            FROM Desired AS d
	            WHERE d.database_name = db.name
	              AND d.file_id = mf.file_id
	        )
	)
	SELECT @FileScript =
	       COALESCE(@FileScript, N'') +
	       COALESCE(
	           CASE WHEN EXISTS (SELECT 1 FROM ExtraFiles) THEN
	               @DoubleCRLF +
	               (
	                   SELECT STRING_AGG(
	                              CONVERT(nvarchar(max),
	                                  N'IF EXISTS (SELECT 1 FROM sys.master_files WHERE database_id = DB_ID(N''' + db_escaped + N''') AND file_id = ' + CAST(file_id AS nvarchar(10)) + N')' + @CRLF +
	                                  N'BEGIN' + @CRLF +
	                                  N'    ALTER DATABASE ' + QUOTENAME(database_name) + N' REMOVE FILE N''' + logical_name_escaped + N''';' + @CRLF +
	                                  N'END' + @CRLF +
	                                  N'GO'
	                              ),
	                              @DoubleCRLF
	                          )
	                   FROM ExtraFiles
	               )
	           END,
	           N''
	       );

--SELECT @FileScript

	IF @FileScript IS NOT NULL
	BEGIN
		SET @Script += @FileScript + @CRLF;
	END;

	IF @Show_DB_Sizes_Info = 1
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

	SELECT ':connect '+@SQLCMD_Connect_Clause Script
	WHERE ISNULL(@SQLCMD_Connect_Clause,'') <> ''
	UNION ALL
	SELECT ''
	WHERE ISNULL(@SQLCMD_Connect_Clause,'') <> ''
	UNION ALL
	SELECT value 
	FROM STRING_SPLIT(REPLACE(@Script,CHAR(13),''),CHAR(10));

	EXEC dbo.usp_PrintLong  @Script
END
GO

EXEC dbo.usp_get_sys_databases_script 
			@TempDB_Sizes_Override_MB = NULL, -- decimal(18, 2)
			@Show_DB_Sizes_Info = 0,
			@SQLCMD_Connect_Clause = ''