-- =============================================
-- Author:		<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:		<2021.03.11>
-- Description:		<Execute external tsql scripts stored on storage>
-- =============================================

-- For information please refer to the README.md file
use SQLAdministrationDB
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

create or alter proc sp_execute_external_tsql

	@Change_Directory_To_CD NVARCHAR(3000) = '',
	@InputFiles nvarchar(3000) = '',  -- Delimited by a semicolon (;), executed by given order, enter the files which their path contains space within double quotations.Enter full paths or relative paths must be relative to %systemroot%\system32. You can also change directory to the desired directory using @Change_Directory_To_CD
	@InputFolder NVARCHAR(1000) = '',  -- This sp executes every *.sql script that finds within the specified folder path. Quote addresses that contain space within double quotations.
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

    DECLARE @CommandtoExecute NVARCHAR(4000)=''
    --print 'external is invoked'
	--if @skip_cmdshell_configuration = 0 
	--begin		
	EXECUTE sp_configure 'show advanced options', 1; RECONFIGURE; EXECUTE sp_configure 'xp_cmdshell', 1; RECONFIGURE; 
    --end
    
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

	--------------------------------------------------

	
	
	Declare @DirTree Table (id INT identity PRIMARY KEY NOT NULL,[file] nvarchar(255))

    IF (@InputFiles = '') AND (@InputFolder = '')
    BEGIN
        RAISERROR('You have to specify either @InputFiles or @InputFolder',16,1)
        RETURN 1
    END
    IF @InputFolder <> ''
    BEGIN
        IF RIGHT(@InputFolder,1) <> '\'
            SET @InputFolder+='\'
        
        DECLARE @cmdshellInput NVARCHAR(500) =  --IIF(@Change_Directory_To_CD = '','',('cd ' + QUOTENAME(@Change_Directory_To_CD,'"') + ' & ')) + 
												'dir /A /B /S /ONG ' + QUOTENAME(@InputFolder,'"') + '*.sql'
		--PRINT @cmdshellInput
        
        insert into @DirTree ([file])
  			EXEC master..xp_cmdshell @cmdshellInput	
			
		
  		if ((select TOP 1 [file] from @DirTree) = 'File Not Found' or (select TOP 1 [file] from @DirTree) = 'The system cannot find the path specified.')
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
        
        
	INSERT INTO @DirTree ([file])
	SELECT * FROM STRING_SPLIT(@InputFiles,';')
    --SELECT @InputFiles += CASE WHEN [file] IS NULL THEN '' ELSE ([file] + '; ') END FROM @DirTree
    delete from @DirTree where ISNULL([file],'') = ''

	if @Stop_After_Executing_Script <> ''
	begin
		delete from @DirTree where id > (select top 1 id from @DirTree where CHARINDEX(@Stop_After_Executing_Script,[file])<>0)
	end

	IF (SELECT COUNT(*) FROM @DirTree) = 0
	BEGIN
		RAISERROR('No input files was specified to be executed',16,1)
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
    
    DECLARE @ConnectionString NVARCHAR(500) = 'chcp '+CONVERT(nchar(4),@SQLCMD_and_Shell_CodePage)+' & sqlcmd '+iif(@Server=N'.' ,'' ,'-S '+ @Server+' ') + CASE WHEN @AuthenticationType <> 'Windows' THEN ' -U ' + @UserName + ' -P ' + @Password ELSE '' END + ' '+CASE @isDAC WHEN 1 THEN ' -A ' ELSE '' END+ iif(@DefaultDatabase = N'master','',' -d ' + QUOTENAME(@DefaultDatabase,'"')) + ' -p1 -f '+CONVERT(nchar(4),@SQLCMD_and_Shell_CodePage)+' '
    
    DECLARE @ScriptPath NVARCHAR(1000)
	CREATE table #output (id int identity not null primary key,[ScriptOrdinal] int,Script NVARCHAR(1000),[output] nvarchar(255),[Estimated Execution Time] varchar(50))
	declare @ScriptOrdinal int = 0
	declare @CommandHolder nvarchar(2000)
	declare @NumberofScripts_to_Execute int = (select count(*) from @DirTree)
	--select * from @DirTree
	DECLARE executor CURSOR FOR SELECT [file] FROM @DirTree ORDER BY id asc
	OPEN executor
		FETCH NEXT FROM executor INTO @ScriptPath
		WHILE @@FETCH_STATUS = 0
		BEGIN

			if CHARINDEX(':',@ScriptPath)=0
			begin
				set @ScriptPath = @Change_Directory_To_CD+@ScriptPath
				update @DirTree set [file] = @ScriptPath where current of executor
			end

			SET @CommandtoExecute = @ConnectionString + '-i ' + QUOTENAME(@ScriptPath,'"')
			--PRINT (@ScriptPath)
			--PRINT @CommandtoExecute
			set @ScriptOrdinal+=1
			--insert #output ([output]) select @ScriptPath
			--insert #output ([output]) select @CommandtoExecute
			declare @StartTime datetime=sysdatetime()
			insert #output ([output])
			EXECUTE master..xp_cmdshell @CommandtoExecute
			--select @StartTime, datediff(day,@StartTime,sysdatetime())
			declare @ExecutionTime_INT int = datediff(microsecond,@StartTime,sysdatetime())
			--select @ExecutionTime_INT/1000000, @ExecutionTime_INT/1e6, @ExecutionTime_INT/3600000000, @ExecutionTime_INT/36/100000000
			declare @ExceutionTime_varchar varchar(50) = convert(varchar(2),(@ExecutionTime_INT/36/100000000))+':'
				+convert(varchar(2),(@ExecutionTime_INT/6/10000000)%60)+':'+convert(varchar(2),(@ExecutionTime_INT/1000000)%3600)+'.'+right(convert(varchar(50),@ExecutionTime_INT),6)

			
			print @commandtoexecute
			update #output set [Estimated Execution Time] = @ExceutionTime_varchar where ScriptOrdinal is NULL
			update #output set ScriptOrdinal = @ScriptOrdinal where ScriptOrdinal is NULL
            update #output set Script = @ScriptPath where Script is null
			
			IF @Stop_On_Error = 1 AND (SELECT COUNT(*) FROM #output WHERE output LIKE '%Sqlcmd:%' or output LIKE '%Msg %, Level %') > 0
			BEGIN
				SET @AbortFlag = 1
				set @CommandHolder = @CommandtoExecute
				GOTO abort
            END
			
			FETCH NEXT FROM executor INTO @ScriptPath
        END
	close executor
	deallocate executor

	abort:



	delete from #output where ISNULL([output],'') = ''
	if @Show_List_of_Executed_Scripts = 1
	begin
		select row_number() over (order by script) Row, Script [Executed Script], iif(@server='.',@@servername,@server) Server, @DefaultDatabase [Database], [Estimated Execution Time] 
		from #output
		group by Script, [Estimated Execution Time]
		union
		select null, 'Total Executed scripts/Total Found Scripts', NULL, NULL, convert(varchar(5),count(distinct ScriptOrdinal))+'/'+convert(varchar(5),@NumberofScripts_to_Execute)+IIF(count(distinct ScriptOrdinal)<>@NumberofScripts_to_Execute,' Warning!!!','') from #output
	end

	--SELECT * FROM #output
	--SELECT SUBSTRING(left(Script,len(script)-charindex('\',reverse(script))+1),LEN(@InputFolder),LEN(script)) RelativeScriptPath, Script  ,
	--	 LEFT(right(Script,charindex('\',reverse(script))-1),(LEN(right(Script,charindex('\',reverse(script))-1))-4))
	--FROM #output GROUP BY ScriptOrdinal, Script ORDER BY MIN(id) 
	--SELECT @InputFolder




	IF @After_Successful_Execution_Policy > 0
	BEGIN
		
		DECLARE FileOperation CURSOR FOR
			SELECT SUBSTRING(left(Script,len(script)-charindex('\',reverse(script))+1),LEN(@InputFolder),LEN(script)) RelativeScriptPath, Script  ,
				right(Script,charindex('\',reverse(script))-1)
			FROM #output GROUP BY ScriptOrdinal, Script ORDER BY MIN(id) 
		OPEN FileOperation
			DECLARE @Script NVARCHAR(2000)
			DECLARE @FileName NVARCHAR(255)
			DECLARE @InputFolder_WithoutEndBackslash NVARCHAR(999) = LEFT(@InputFolder,(LEN(@InputFolder)-1))
			DECLARE @ParentFolder NVARCHAR(2000)=LEFT(@InputFolder_WithoutEndBackslash,(LEN(@InputFolder_WithoutEndBackslash)-CHARINDEX('\',REVERSE(@InputFolder_WithoutEndBackslash))))
			DECLARE @TargetFolder NVARCHAR(2000)=@ParentFolder+'\'+@MoveTo_Folder_Name
			DECLARE @RelativeScriptPath NVARCHAR(1000)

			FETCH NEXT FROM FileOperation INTO @RelativeScriptPath, @Script, @FileName
			
			WHILE @@FETCH_STATUS = 0
			BEGIN
				BEGIN TRY
					--DECLARE @Error int
					IF @After_Successful_Execution_Policy > 1
					BEGIN
						DECLARE @Subdir NVARCHAR(2000) = @TargetFolder+@RelativeScriptPath
						EXEC xp_create_subdir @Subdir
						DECLARE @PathNew NVARCHAR(2000)=@Subdir+@FileName

						IF @After_Successful_Execution_Policy > 2
							SET @PathNew=dbo.find_nonexistant_name(@PathNew)
						
						EXEC sys.xp_copy_file @Script, @PathNew
						--SET @Error = @@ERROR
					END
					--IF @Error < 1
					IF @After_Successful_Execution_Policy < 4
						EXEC xp_delete_files @Script		
				END TRY
				BEGIN CATCH
					DECLARE @ErrMsg NVARCHAR(1000) = ERROR_MESSAGE()
					RAISERROR(@ErrMsg,16,1)
				END CATCH

				FETCH NEXT FROM FileOperation INTO @RelativeScriptPath, @Script, @FileName
            END
		CLOSE FileOperation
		DEALLOCATE FileOperation
    END


		
	--print @debug_mode

	if @Debug_Mode > 1
 	BEGIN
		--print 'why'
		--ALTER TABLE #output ADD [Error Description] VARCHAR(10) NULL
		SELECT id, ScriptOrdinal, left(Script,len(script)-charindex('\',reverse(script))+1) ScriptPath, right(Script,charindex('\',reverse(script))-1) Script, output, lead(output) OVER (ORDER BY id) AS [Error Description] INTO #output2 FROM #output 
		DROP TABLE #output
		
		DELETE FROM #output2 WHERE output NOT LIKE '%Sqlcmd:%' AND output NOT LIKE '%Msg %, Level %'
		UPDATE #output2 SET [Error Description] = NULL WHERE output NOT LIKE '%Msg %, Level %'
		
		--SELECT * FROM #output
		--UPDATE #output SET [Error No.] =
		--IIF(CHARINDEX('Msg',output) <> 0,SUBSTRING(TRIM([output]),CHARINDEX(' ',TRIM(output)),(CHARINDEX(',',TRIM(output))-CHARINDEX(' ',TRIM(output)))),'SQLCMD') 
		declare @TotalErrors INT = (select COUNT(*) FROM #output2)
		if (@TotalErrors) > 0
			SELECT * FROM #output2
			order by id
		--declare @SQLCMD_Error_Count int = (select count(*) from #output where [output] like '%Sqlcmd: Error%')
		--declare @SQL_Error_Count int = (select count(*) from #output where [output] like '%Msg %, Level %')
		--select @SQLCMD_Error_Count [SQLCMD Error Count], @SQL_Error_Count [SQL Error Count]
		--create table #tempSQLCMD ([Script Name] sysname, [Count SQLCMD] int, [Count SQL] int, [Count Distinct SQL] int, [Top SQL Err No.] int)
		--print @debug_mode
		if (@Debug_Mode = 3 or @TotalErrors > 0)
			SELECT (@TotalErrors - count(*)) AS [Count SQLCMD Errors], count(*) [Count SQL Errors], COUNT(DISTINCT LEFT([output],CHARINDEX(',',[output]))) [Count distinct SQL Errors] from #output2 where [output] like '%Msg %, Level %' 
		
	END
    ELSE 
		if @Debug_Mode = 1
			select * from #output -- where ScriptOrdinal = 7
			order by id

	IF @Keep_xp_cmdshell_Enabled = 0 --and @skip_cmdshell_configuration = 0
	begin
		--print @Keep_xp_cmdshell_Enabled
		--print @skip_cmdshell_configuration
		print 'disable xp_cmdshell condition was executed but not applied'
		--EXECUTE sp_configure 'xp_cmdshell', 0; RECONFIGURE; EXECUTE sp_configure 'show advanced options', 0; RECONFIGURE;
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

--SELECT COUNT(*) FROM test.dbo.simple

--SELECT COUNT(*) FROM test.dbo.simple

--/*

-- Warning!!!I have seen this SP to skip some scripts with long paths. (I don't care why, to even think about it :D) When I shortened that path they got executed successfully.
--If you want to make sure that all scripts have been executed, you can set the @Show_List_of_Executed_Scripts switch to 1 to see the list of executed scripts.

EXECUTE sqladministrationdb..sp_execute_external_tsql 
									  @Change_Directory_To_CD = ''
									 ,@InputFiles = N'D:\CandoMigration\test\3).sql'			-- Semicolon delimited list of script files to execute.
                                     ,@InputFolder = ''--'D:\CandoMigration\test'
                                     ,@Server = NULL			-- Server name/IP + instance name. Include port if applicable
                                     ,@AuthenticationType = NULL -- any value which does not include the word 'sql' means Windows Authentication
                                     ,@UserName = NULL
                                     ,@Password = NULL
                                     --,@DefaultDatabase = 'SQLAdministrationDB'
									 ,@DefaultDatabase = 'SQLAdministrationDB'		-- Enter the name of the database unquoted, even if it has special characters or space. Leaving empty means "master"
                                     ,@Keep_xp_cmdshell_Enabled = 1
                                     ,@isDAC = 0	-- run files with Dedicated Admin Connection
									 ,@Debug_Mode = 2	--  none = 0 | simple = 1 | show = 2 | verbose = 3
									 ,@DoNot_Dispaly_Full_Path = 1
									 ,@skip_cmdshell_configuration = 0
									 ,@Stop_On_Error = 0
									 ,@Show_List_of_Executed_Scripts = 1
									 ,@Stop_After_Executing_Script = ''--'3).sql'		-- stops executing scripts after the first occurance of the given script
									 ,@After_Successful_Execution_Policy = 0		-- 0 | 1 | 2 | 3	0 (Default): Do nothing, 1: delete after successful execution, 
																					-- 2: Move to @MoveTo_Folder_Name folder beside @InputFolder after successful execution replacing existings.
																					-- 3: Move to @MoveTo_Folder_Name folder beside @InputFolder after successful execution and rename (add "_2") the files to avoid file replacements
																					-- 4: Copy to @MoveTo_Folder_Name folder beside @InputFolder after successful execution and rename (add "_2") the files to avoid file replacements, but don't delete source files
																					-- in options 2&3 the folders with the same name will be merged. These options work for @InputFolder only, not @InputFiles.
									 ,@MoveTo_Folder_Name = 'old'					-- If you set @After_Successful_Execution_Policy to 2 or more, and leave this empty, the files will be moved/copied to one level up in the directory tree.
																					

--*/


