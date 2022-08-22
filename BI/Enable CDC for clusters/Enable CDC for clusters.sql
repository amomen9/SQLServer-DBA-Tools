-- =============================================
-- Author:		<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:		<2021.03.11>
-- Description:		<Enable CDC for Clusters>
-- License:			<Please refer to the license file>
-- =============================================

-- For information please refer to the README.md file


use master
go

CREATE OR ALTER FUNCTION find_nonexistant_name(@Path NVARCHAR(2000))
RETURNS NVARCHAR(2000)
AS
BEGIN
	DECLARE @Result INT
	
    EXEC master.dbo.xp_fileexist @Path, @result OUTPUT
	
	IF @Result <> 0
	BEGIN
		SET @Path=LEFT(@Path,LEN(@Path)-4)+'_2'+'.sql'
		RETURN dbo.find_nonexistant_name(@Path)
	end	
	RETURN @Path
END
go

CREATE OR ALTER PROC sp_execute_external_tsql

	@Change_Directory_To_CD NVARCHAR(3000) = '',
	@InputFiles nvarchar(3000) = '',  -- Delimited by a semicolon (;), executed by given order, enter the files which their path contains space within double quotations.Enter full paths or relative paths must be relative to %systemroot%\system32. You can also change directory to the desired directory using @Change_Directory_To_CD
	@InputFolder NVARCHAR(1000) = '',  -- This sp executes every *.sql script that finds within the specified folder path. Quote addresses that contain space within double quotations.
	@PreCommand NVARCHAR(max) = '',
	@PostCommand NVARCHAR(max) = '',
	@FileName_REGEX_Filter_PowerShell NVARCHAR(128) = '*.sql',
	@Include_Subdirectories BIT = 1,
	@Server sysname = '.',
	@AuthenticationType nvarchar(10) = N'Windows',    -- any value which does not include the word 'sql' means Windows Authentication
	@UserName sysname = '',
	@Password sysname = '',
	@DefaultDatabase sysname = N'master',
	@SQLCMD_and_Shell_CodePage INT = 1256,
	@isDAC bit = 0,    -- run script files with Dedicated Admin Connection
	@Keep_xp_cmdshell_Enabled BIT = 0,
	@Debug_Mode int = 1,
	@skip_cmdshell_configuration bit = 0,
	@DoNot_Dispaly_Full_Path bit = 1,
	@Stop_On_Error BIT = 0,
	@Show_List_of_Executed_Scripts bit = 1,
	@Stop_After_Executing_Script nvarchar(300) = '',
	@After_Successful_Execution_Policy tinyint = 0,
	@MoveTo_Folder_Name nvarchar(500) = N'done'
AS
BEGIN
SET NOCOUNT on
	drop table if exists #output
	drop table if exists #output2
	DECLARE @AbortFlag BIT = 0

    DECLARE @CommandtoExecute VARCHAR(8000)=''

	EXECUTE sp_configure 'show advanced options', 1; RECONFIGURE; EXECUTE sp_configure 'xp_cmdshell', 1; RECONFIGURE; 

    
    ---------- Parameters Standardizations:-----------
    
    SET @InputFiles = ISNULL(@InputFiles,'')
    
    SET @InputFolder = ISNULL(@InputFolder,'')
    
    SET @AuthenticationType = ISNULL(@AuthenticationType,'')

	SET @InputFiles = TRIM(@InputFiles)

	SET @InputFolder = REPLACE(@InputFolder,'"','')

	SET @InputFolder = TRIM(@InputFolder)

	SET @InputFiles = REPLACE(@InputFiles,'"','')	
	
	SET @Change_Directory_To_CD = ISNULL(@Change_Directory_To_CD,'')

	SET @Change_Directory_To_CD = REPLACE(@Change_Directory_To_CD,'"','')

	set @Change_Directory_To_CD = TRIM(@Change_Directory_To_CD)

	set @Server = isnull(@Server,'.')

	set @Stop_After_Executing_Script = isnull(@Stop_After_Executing_Script,'')

	IF @Change_Directory_To_CD <> '' and RIGHT(@Change_Directory_To_CD,1) <> '\'
            SET @Change_Directory_To_CD+='\'

	SET @PreCommand = ISNULL(@PreCommand,'')

	SET @PostCommand = ISNULL(@PostCommand,'')

	SET @UserName = ISNULL(@UserName,'')

	SET @Password = ISNULL(@Password,'')

	SET @SQLCMD_and_Shell_CodePage = ISNULL(@SQLCMD_and_Shell_CodePage,'')

	--------------------------------------------------

	IF @After_Successful_Execution_Policy > 1 AND isnull(@MoveTo_Folder_Name,'') = ''
	BEGIN    
		RAISERROR('You have set @After_Successful_Execution_Policy to 2 or bigger but you have not provided @MoveTo_Folder_Name.',16,1)
		RETURN 1
	END
	IF EXISTS (SELECT a FROM (SELECT '\' a UNION SELECT '/' UNION SELECT ':' UNION SELECT '*' UNION SELECT '?' UNION SELECT '"' UNION SELECT '<' UNION SELECT '>' UNION SELECT '|' ) b
				WHERE CHARINDEX(a,@MoveTo_Folder_Name) > 0
			  )
	BEGIN
		RAISERROR('Directory name entered for @MoveTo_Folder_Name contains illegal characters.',16,1)
		RETURN 1
    END

	CREATE table #DirTree (id INT identity PRIMARY KEY NOT NULL,[file] nvarchar(max),isFile BIT NOT NULL DEFAULT 1)
	
	IF @PreCommand<>''
	begin
		SET IDENTITY_INSERT #DirTree on
		INSERT #DirTree
		(
			id,
			[file],
			isFile
		)
		VALUES
		(   
			0,
			@PreCommand, -- file - nvarchar(max)
			0 -- isFile - bit
		)
		SET IDENTITY_INSERT #DirTree OFF
	END

    IF (@InputFiles = '') AND (@InputFolder = '') AND @PostCommand = '' AND @PreCommand = ''
    BEGIN
        RAISERROR('SP Error: You have to specify either @InputFiles or @InputFolder or @PostCommand or @PreCommand',16,1)
        RETURN 1
    END
    IF @InputFolder <> ''
    BEGIN
        IF RIGHT(@InputFolder,1) <> '\'
            SET @InputFolder+='\'
        
        DECLARE @cmdshellInput VARCHAR(1000) =  --IIF(@Change_Directory_To_CD = '','',('cd ' + QUOTENAME(@Change_Directory_To_CD,'"') + ' & ')) + 
												--'dir /A /B /S /ONG ' + QUOTENAME(@InputFolder,'"') + '*.sql'					--CommandLine
												'powershell ' + '"GET-ChildItem -Recurse -File \"'+@InputFolder+@FileName_REGEX_Filter_PowerShell+'\" | %{ $_.FullName }"'			--PowerShell
		PRINT @cmdshellInput
        
        insert into #DirTree ([file])
  			EXEC master..xp_cmdshell @cmdshellInput	
			
		DECLARE @DirQueryHeadLine NVARCHAR(255) = (select TOP 1 [file] from #DirTree WHERE isfile=1)

  		if (CHARINDEX('Cannot find path',@DirQueryHeadLine) <> 0 or @DirQueryHeadLine = 'File Not Found' or @DirQueryHeadLine = 'The system cannot find the path specified.')
  		BEGIN
    		declare @message nvarchar(150) = 'The folder you specified either does not exist or no tsql scripts exist within that folder or its subdirectories'
    		raiserror(@message, 16, 1)
  			RETURN 1
    	END
        
        
        
    END
        
    IF @InputFiles <> ''
    BEGIN
        WHILE (RIGHT(@InputFiles,1) = ';')
        BEGIN
            SET @InputFiles = LEFT(@InputFiles,LEN(@InputFiles)-1)
        END        
            
    END
        
        
	INSERT INTO #DirTree ([file])
	SELECT * FROM STRING_SPLIT(@InputFiles,';')

    delete from #DirTree where ISNULL([file],'') = ''

	if @Stop_After_Executing_Script <> ''
	begin
		delete from #DirTree where id > (select top 1 id from #DirTree where CHARINDEX(@Stop_After_Executing_Script,[file])<>0)
	end

	IF @PostCommand <> ''
		INSERT #DirTree
		(
			[file],
			isFile
		)
		VALUES
		(   @PostCommand, -- file - nvarchar(max)
			0 -- isFile - bit
		)


	IF (SELECT COUNT(*) FROM #DirTree) = 0
	BEGIN
		RAISERROR('No input files or commands were specified to be executed',16,1)
		RETURN 1
    END


    IF CHARINDEX('sql',@AuthenticationType) = 0
    BEGIN
      SET @AuthenticationType = 'Windows'
      SET @UserName = ''
      SET @Password = ''
    END
    
    IF ISNULL(@DefaultDatabase,'') = ''
      SET @DefaultDatabase = 'master'
    
    DECLARE @ConnectionString VARCHAR(4000) = --'chcp '+CONVERT(nchar(4),@SQLCMD_and_Shell_CodePage)+' & '+
												'sqlcmd '+iif(@Server=N'.' ,'' ,'-S '+ @Server+' ') + CASE WHEN @AuthenticationType <> 'Windows' THEN '-U ' + @UserName + ' -P ' + @Password ELSE '' END + CASE @isDAC WHEN 1 THEN '-A ' ELSE '' END+ iif(@DefaultDatabase = N'master','','-d ' + QUOTENAME(@DefaultDatabase,'"')+' ') + '-p1'+IIF(@SQLCMD_and_Shell_CodePage<>'',' -f '+CONVERT(nchar(4),@SQLCMD_and_Shell_CodePage),'')+' '

    
	DECLARE @ScriptPath NVARCHAR(max)
	DECLARE @isFile BIT
    
	CREATE table #output (id int identity not null primary key,[ScriptOrdinal] int,Script NVARCHAR(max),[output] nvarchar(255),[Estimated Execution Time] varchar(50), isSuccessful BIT, isFile bit)
	declare @ScriptOrdinal int = 0
	DECLARE @id int
	declare @CommandHolder nvarchar(max)
	declare @NumberofScripts_to_Execute int = (select count(*) from #DirTree)

	
	DECLARE executor CURSOR FOR

		SELECT [file],isFile,id FROM #DirTree ORDER BY id asc
	
	OPEN executor
		FETCH NEXT FROM executor INTO @ScriptPath, @isFile, @id
		WHILE @@FETCH_STATUS = 0
		BEGIN

			if CHARINDEX(':',@ScriptPath)=0
			begin
				set @ScriptPath = @Change_Directory_To_CD+@ScriptPath
				update #DirTree set [file] = @ScriptPath where current of executor
			end
			
			SET @CommandtoExecute = @ConnectionString + IIF(@isFile = 1,'-i ','-Q ') + '"' + @ScriptPath + '"'

			declare @StartTime datetime=sysdatetime()
			insert #output ([output])
			EXECUTE master..xp_cmdshell @CommandtoExecute

			declare @ExecutionTime_INT int = datediff(microsecond,@StartTime,sysdatetime())

			declare @ExceutionTime_varchar varchar(50) = convert(varchar(2),(@ExecutionTime_INT/36/100000000))+':'
				+convert(VARCHAR(2),(@ExecutionTime_INT/6/10000000)%60)+':'+convert(varchar(2),(@ExecutionTime_INT/1000000)%3600)+'.'+right(convert(varchar(50),@ExecutionTime_INT),6)

			
			print @commandtoexecute
			DECLARE @SuccessFlag BIT = IIF((SELECT COUNT(*) FROM #output WHERE ScriptOrdinal IS NULL and (output LIKE '%Sqlcmd:%' or output LIKE '%Msg %, Level %')) = 0,1,0)
			update #output 
			SET [Estimated Execution Time] = @ExceutionTime_varchar,
				ScriptOrdinal = @id,
				Script = @ScriptPath, 
				isSuccessful = @SuccessFlag, 
				isFile = @isFile
			WHERE ScriptOrdinal is NULL
			
			IF @Stop_On_Error = 1 AND @SuccessFlag = 0
			BEGIN
				SET @AbortFlag = 1
				set @CommandHolder = @CommandtoExecute
				GOTO abort
            END
			
			FETCH NEXT FROM executor INTO @ScriptPath, @isFile, @id
        END
	close executor
	deallocate executor

	abort:



	delete from #output where ISNULL([output],'') = ''
	if @Show_List_of_Executed_Scripts = 1
	begin
		select row_number() over (order by MIN(id))-1 Row, Script [Executed Script], iif(@server='.',@@servername,@server) Server, @DefaultDatabase [Database], IIF(@UserName = '', 'Integrated Authentication',@UserName) UserName ,[Estimated Execution Time], isSuccessful [Was Successfull?]
		from #output
		group by Script, [Estimated Execution Time], isSuccessful
		union
		select null, 'Total Executed scripts/Total Found Scripts', NULL, NULL, NULL, convert(varchar(5),count(distinct ScriptOrdinal))+'/'+convert(varchar(5),@NumberofScripts_to_Execute)+IIF(count(distinct ScriptOrdinal)<>@NumberofScripts_to_Execute,' Warning!!!',''),NULL from #output
	end



	IF @After_Successful_Execution_Policy > 0
	BEGIN
		DECLARE FileOperation CURSOR FOR
		
			SELECT 
				SUBSTRING(left(Script,len(script)-charindex('\',reverse(script))+1),LEN(@InputFolder),LEN(script)) RelativeScriptPath,
				Script,
				right(Script,charindex('\',reverse(script))-1) FileName,
				isSuccessful,
				isFile
			FROM #output 
			WHERE isFile = 1
			GROUP BY ScriptOrdinal, Script, isSuccessful, isFile 			
			ORDER BY MIN(id) 

		OPEN FileOperation
			DECLARE @Script NVARCHAR(2000)
			DECLARE @FileName NVARCHAR(255)
			DECLARE @InputFolder_WithoutEndBackslash NVARCHAR(999) = LEFT(@InputFolder,(LEN(@InputFolder)-1))
			DECLARE @ParentFolder NVARCHAR(2000)=LEFT(@InputFolder_WithoutEndBackslash,(LEN(@InputFolder_WithoutEndBackslash)-CHARINDEX('\',REVERSE(@InputFolder_WithoutEndBackslash))))
			DECLARE @TargetFolder NVARCHAR(2000)=@ParentFolder+'\'+@MoveTo_Folder_Name
			DECLARE @RelativeScriptPath NVARCHAR(1000)
			DECLARE @isSuccessful BIT

			FETCH NEXT FROM FileOperation INTO @RelativeScriptPath, @Script, @FileName, @isSuccessful, @isFile
			WHILE @@FETCH_STATUS = 0
			BEGIN
				IF @isSuccessful = 0
					GOTO NextIteration
				BEGIN TRY

					IF @After_Successful_Execution_Policy > 1
					BEGIN
						DECLARE @Subdir NVARCHAR(2000) = @TargetFolder+@RelativeScriptPath
						EXEC xp_create_subdir @Subdir
						DECLARE @PathNew NVARCHAR(2000)=@Subdir+@FileName

						IF @After_Successful_Execution_Policy > 2
							SET @PathNew=dbo.find_nonexistant_name(@PathNew)
						
						EXEC sys.xp_copy_file @Script, @PathNew

					END

					IF @After_Successful_Execution_Policy < 4
						EXEC xp_delete_files @Script		
				END TRY
				BEGIN CATCH
					DECLARE @ErrMsg NVARCHAR(1000) = ERROR_MESSAGE()
					RAISERROR(@ErrMsg,16,1)
				END CATCH

				NextIteration:
				FETCH NEXT FROM FileOperation INTO @RelativeScriptPath, @Script, @FileName, @isSuccessful, @isFile
            END
		CLOSE FileOperation
		DEALLOCATE FileOperation
    END


		

	if @Debug_Mode > 1
 	BEGIN

		SELECT 
			id,
			ScriptOrdinal,
			IIF(isFile=1,left(Script,len(script)-charindex('\',reverse(script))+1),'N/A') ScriptDirectory,
			IIF(isFile=1,right(Script,charindex('\',reverse(script))-1),Script) Script,
			iif(@server='.',@@servername,@server) Server,
			@DefaultDatabase [Database],
			IIF(@UserName = '', 'Integrated Authentication',@UserName) UserName,
			output,
			LEAD(output) OVER (ORDER BY id) AS [Error Description]
		INTO #output2
		FROM #output
		WHERE isSuccessful = 0
		
		DROP TABLE #output
		

		DELETE FROM #output2 WHERE output NOT LIKE '%Sqlcmd:%' AND output NOT LIKE '%Msg %, Level %'
		UPDATE #output2 SET [Error Description] = NULL WHERE output NOT LIKE '%Msg %, Level %'
		

		declare @TotalErrors INT = (select COUNT(*) FROM #output2)
		if (@TotalErrors) > 0
			SELECT * FROM #output2
			order by id
		
		IF (@TotalErrors > 0 OR @Debug_Mode = 3)
			SELECT (@TotalErrors - count(*)) AS [Count SQLCMD Errors], count(*) [Count SQL Errors], COUNT(DISTINCT LEFT([output],CHARINDEX(',',[output]))) [Count distinct SQL Errors] from #output2 where [output] like '%Msg %, Level %' 
		
	END
    ELSE 
		if @Debug_Mode = 1
			select * from #output -- where ScriptOrdinal = 7
			order by id

	IF @Keep_xp_cmdshell_Enabled = 0 --and @skip_cmdshell_configuration = 0
	begin

		print 'disable xp_cmdshell condition was executed but not applied'

    END

	IF @AbortFlag = 1
	BEGIN		
		RAISERROR('Error was returned on the last executed script and @Stop_On_Error was specified, so the process will abort.',16,1)
		print 'The following shell command is the last command that was executed:'
		print @CommandHolder
		RETURN 1
    END
    
END
go

------------------------------------------------------------------------------------------------

USE [master]

GO

DECLARE @DBName sysname = 'Co-JobVisionDB',
		@SQL nvarchar(MAX)

------- Remove the database from the availability group: ---------------------------------------

SET @SQL =
'
USE master
ALTER AVAILABILITY GROUP [AG-CandoDB]
REMOVE DATABASE ['+@DBName+'];
'
EXEC(@SQL)

------- Remove contained users: ------------------------------------------------------------------
SET @SQL =
'
USE ['+@DBName+']

DECLARE @UserName sysname,
		@SQL NVARCHAR(max)

DECLARE UserRemover CURSOR FOR
	SELECT name FROM sys.database_principals WHERE authentication_type_desc = ''DATABASE''
OPEN UserRemover
	FETCH NEXT FROM UserRemover INTO @UserName
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @SQL =
		''
			DROP USER [''+@UserName+'']
		''
		EXEC(@SQL)
		FETCH NEXT FROM UserRemover INTO @UserName
	END
CLOSE UserRemover
DEALLOCATE UserRemover
'
EXEC(@SQL)


------- Remove database containment: -------------------------------------------------------
SET @SQL =
'
USE ['+@DBName+']

ALTER DATABASE ['+@DBName+'] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
ALTER DATABASE ['+@DBName+'] SET MULTI_USER
USE [master]

ALTER DATABASE ['+@DBName+'] SET CONTAINMENT = NONE WITH NO_WAIT
'
EXEC(@SQL)

-------- Enable CDC on the database --------------------------------------------------------------------
SET @SQL =
'
USE ['+@DBName+']


ALTER AUTHORIZATION ON DATABASE::['+@DBName+'] TO ['+SUSER_SNAME(0x01)+']

EXEC sp_cdc_enable_db 
'
EXEC(@SQL)


--------- Enable CDC on the intended tables -----------------------------------------------------------
SET @SQL =
'
USE ['+@DBName+']

EXEC sys.sp_cdc_enable_table  @source_schema = N''ats'',@source_name = N''CandidateTags'',@role_name = NULL , @Supports_Net_Changes = 1
'
EXEC(@SQL)


SET @SQL =
'
USE ['+@DBName+']
EXEC sys.sp_cdc_enable_table  @source_schema = N''ats'',@source_name = N''CVFiles'',@role_name = NULL , @Supports_Net_Changes = 1
'
EXEC(@SQL)

SET @SQL =
'
USE ['+@DBName+']
EXEC sys.sp_cdc_enable_table  @source_schema = N''ats'',@source_name = N''Comments'',@role_name = NULL , @Supports_Net_Changes = 1
'
EXEC(@SQL)

--sp_cdc_change_job @job_type='cleanup', @retention=minutes

--------- Drop database on secondary replica ----------------------------------------------------------
EXEC ('DROP DATABASE ['+@DBName+']') AT [CANDO-DB2,2828]


--------- Add the database to the AG again ------------------------------------------------------------
SET @SQL =
'
USE master

ALTER AVAILABILITY GROUP [AG-CandoDB]
ADD DATABASE ['+@DBName+']
'
EXEC(@SQL)

---------- Disable CDC cleanup job ---------------------------------------------------------------------
SET @SQL =
'
USE msdb
EXEC dbo.sp_update_job        
						@job_name = N''cdc.'+@DBName+'_cleanup'',						
						@enabled = 0 ;
'
EXEC(@SQL)


DECLARE @DBName sysname = 'Co-JobVisionDB',
		@SQL nvarchar(MAX)

-------- Change the polling interval --------------------------------------------------------------------
SET @SQL =
'
USE ['+@DBName+']
EXEC sys.sp_cdc_change_job @job_type = N''capture'',      -- nvarchar(20)
                           @maxtrans = 500,        -- int
                           @maxscans = 10,        -- int
                           @continuous = 1,   -- bit
                           @pollinginterval = 15 -- bigint
                           
                           
'
EXEC (@SQL)

--------- Add primary replica check to the jobs commands ------------------------------------------------
SET @SQL=
'
DECLARE @JobID UNIQUEIDENTIFIER = (SELECT job_id from msdb..sysjobs WHERE name = ''cdc.'+@DBName+'_capture'')
UPDATE msdb..sysjobsteps
SET command = 
''IF ISNULL((SELECT sys.fn_hadr_is_primary_replica('''''+@DBName+''''')),1) = 0
	RETURN
ELSE
'' +char(9)+ command
WHERE job_id = @JobID and step_id = 1

UPDATE msdb..sysjobsteps
SET command = 
''IF ISNULL((SELECT sys.fn_hadr_is_primary_replica('''''+@DBName+''''')),1) = 0
	RETURN
ELSE
'' + char(9) + ''EXEC '' + command
WHERE job_id = @JobID and step_id = 2


SET @JobID = (SELECT job_id from msdb..sysjobs WHERE name = ''cdc.'+@DBName+'_cleanup'')
UPDATE msdb..sysjobsteps
SET command = 
''IF ISNULL((SELECT sys.fn_hadr_is_primary_replica('''''+@DBName+''''')),1) = 0
	RETURN
ELSE
'' + char(9) + ''EXEC '' + command
WHERE job_id = @JobID

'
EXEC(@SQL)

------------ Restart job for the commands' changes to take effect --------------------------------------------------

--DECLARE @DBName sysname = 'Co-JobVisionDB'
DECLARE @JobName sysname = N'cdc.'+@DBName+'_capture'

EXEC msdb..sp_stop_job @job_name = @JobName				-- sysname 

EXEC msdb..sp_start_job @job_name = @JobName			-- sysname
                        
------------ Create jobs on the secondary replica by executing the following external script file: -----------------
-- "create CDC Jobs On Secondary.sql"

EXEC dbo.sp_execute_external_tsql 
									--@Change_Directory_To_CD = '',                -- nvarchar(3000)
                                  @InputFiles = '"\\172.16.40.81\CandoMigration\DBA-Cando\Main\Modules\create CDC Jobs On Secondary.sql"',                            -- nvarchar(3000)
                                  @InputFolder = '',                           -- nvarchar(1000)
                                  @PreCommand = '',                            -- nvarchar(max)
                                  @PostCommand = '',                           -- nvarchar(max)
                                  @FileName_REGEX_Filter_PowerShell = '*.sql', -- nvarchar(128)
                                  @Include_Subdirectories = 1,                 -- bit
                                  @Server = 'Cando-DB2,2828',                               -- sysname
                                  @AuthenticationType = N'Windows',            -- nvarchar(10)
                                  @UserName = '',                              -- sysname
                                  @Password = '',                              -- sysname
                                  @DefaultDatabase = @DBName,                -- sysname
                                  @SQLCMD_and_Shell_CodePage = 1256,           -- int
                                  @isDAC = 0,                                  -- bit
                                  @Keep_xp_cmdshell_Enabled = 0,               -- bit
                                  @Debug_Mode = 1,                             -- int
                                  @skip_cmdshell_configuration = 0,            -- bit
                                  --@DoNot_Dispaly_Full_Path = 1,                -- bit
                                  @Stop_On_Error = 0,                          -- bit
                                  @Show_List_of_Executed_Scripts = 0,          -- bit
                                  @Stop_After_Executing_Script = '',           -- nvarchar(300)
                                  @After_Successful_Execution_Policy = 0       -- tinyint
                                  --@MoveTo_Folder_Name = N'done'                -- nvarchar(500)


GO

DROP PROC dbo.sp_execute_external_tsql
GO



SELECT * FROM msdb..cdc_jobs
GO



