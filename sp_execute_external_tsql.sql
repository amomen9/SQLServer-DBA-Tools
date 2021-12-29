-- =============================================
-- Author:		<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:		<2021.03.11>
-- Description:		<Backup Website>
-- =============================================

-- For information please refer to the README.md file
use master
go

create or alter proc sp_execute_external_tsql

@Change_Directory_To NVARCHAR(3000) = '',
@InputFiles nvarchar(3000) = '',  -- Delimited by a semicolon (;), executed by given order, enter the files which their path contains space within double quotations.Enter full paths or relative paths must be relative to %systemroot%\system32. You can also change directory to the desired directory using @Change_Directory_To
@InputFolder NVARCHAR(1000) = '',  -- This sp executes every *.sql script that finds within the specified folder path. Quote addresses that contain space within double quotations.
@Include_Subdirectories BIT = 0,
@Server sysname = '.',
@AuthenticationType nvarchar(10) = N'Windows',    -- any value which does not include the word 'sql' means Windows Authentication
@UserName sysname = '',
@Password sysname = '',
@DefaultDatabase sysname = N'master',
@Keep_xp_cmdshell_Enabled BIT = 0,
@isDAC bit = 0    -- run script files with Dedicated Admin Connection

AS
BEGIN
SET NOCOUNT on
    DECLARE @CommandtoExecute NVARCHAR(2000)=''
    
    -- To allow advanced options to be changed.  
    EXECUTE sp_configure 'show advanced options', 1;  
  
    -- To update the currently configured value for advanced options.  
    RECONFIGURE;  
  
    -- To enable the feature.  
    EXECUTE sp_configure 'xp_cmdshell', 1;  
  
    -- To update the currently configured value for this feature.  
    RECONFIGURE; 
    
    
    ---------- Parameters Standardizations:-----------
    
    SET @InputFiles = ISNULL(@InputFiles,'')
    
    SET @InputFolder = ISNULL(@InputFolder,'')
    
    SET @AuthenticationType = ISNULL(@AuthenticationType,'')

	SET @InputFiles = TRIM(@InputFiles)

	SET @InputFolder = TRIM(@InputFolder)

	SET @InputFiles = REPLACE(@InputFiles,'"','')

	SET @InputFolder = REPLACE(@InputFolder,'"','')
	
	SET @Change_Directory_To = ISNULL(@Change_Directory_To,'')

	SET @Change_Directory_To = REPLACE(@Change_Directory_To,'"','')

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
        
        DECLARE @cmdshellInput NVARCHAR(500) = IIF(@Change_Directory_To = '','',('cd ' + QUOTENAME(@Change_Directory_To,'"') + ' & ')) + 'dir /A /B /S /ONG ' + QUOTENAME(@InputFolder,'"') + '*.sql'
		PRINT @cmdshellInput
        
        insert into @DirTree ([file])
  			EXEC master..xp_cmdshell @cmdshellInput	
			
		
  		if ((select TOP 1 [file] from @DirTree) = 'File Not Found')
  		BEGIN
    		declare @message nvarchar(150) = 'The folder you specified either does not exist or no tsql scripts exist within that folder or its subdirectories'
    		raiserror(@message, 16, 1)
  			RETURN 1
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
        
        
    END
        
    
    
    IF CHARINDEX('sql',@AuthenticationType) = 0
    BEGIN
      SET @AuthenticationType = 'Windows'
      SET @UserName = ''
      SET @Password = ''
    END
    
    IF ISNULL(@DefaultDatabase,'') = ''
      SET @DefaultDatabase = 'master'
    
    DECLARE @ConnectionString NVARCHAR(50) = ' sqlcmd -S '+ISNULL(@Server,'.') + CASE WHEN @AuthenticationType <> 'Windows' THEN ' -U ' + @UserName + ' -P ' + @Password ELSE '' END + ' '+CASE @isDAC WHEN 1 THEN ' -A ' ELSE '' END+ ' -d ' + @DefaultDatabase + ' -p1 '
    
    DECLARE @ScriptPath NVARCHAR(1000)
	declare @output table (id int identity not null primary key,[ScriptOrdinal] int,[output] nvarchar(255))
	declare @ScriptOrdinal int = 0
	DECLARE executor CURSOR FOR SELECT [file] FROM @DirTree ORDER BY id asc
	OPEN executor
		FETCH NEXT FROM executor INTO @ScriptPath
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @CommandtoExecute = @ConnectionString + '-i ' + QUOTENAME(@ScriptPath,'"')
			PRINT (@ScriptPath)
			--PRINT @CommandtoExecute
			set @ScriptOrdinal+=1
			insert @output ([output]) select @ScriptPath
			
			insert @output ([output])
			EXECUTE master..xp_cmdshell @CommandtoExecute
			update @output set ScriptOrdinal = @ScriptOrdinal where ScriptOrdinal is null
			FETCH NEXT FROM executor INTO @ScriptPath
        END
	close executor
	deallocate executor

	delete from @output where ISNULL([output],'') = ''

	select * from @output -- where ScriptOrdinal = 7
	IF @Keep_xp_cmdshell_Enabled = 0
		EXECUTE sp_configure 'xp_cmdshell', 0; RECONFIGURE; EXECUTE sp_configure 'show advanced options', 0; RECONFIGURE;
    
END
go

EXECUTE master..sp_execute_external_tsql 
									  @Change_Directory_To = '%userprofile%\desktop'
									 ,@InputFiles = N'' -- Delimited by a semicolon (;), executed by given order, relative paths must be relative to %systemroot%\system32. You can also change directory with @Change_Directory_To
                                     ,@InputFolder = 'test'	-- This sp executes every *.sql script that finds within the specified folder path. Quote addresses that contain space within double quotations.
                                     ,@Server = NULL
                                     ,@AuthenticationType = NULL -- any value which does not include the word 'sql' means Windows Authentication
                                     ,@UserName = NULL
                                     ,@Password = NULL
                                     ,@DefaultDatabase = NULL
                                     ,@Keep_xp_cmdshell_Enabled = 0
                                     ,@isDAC = 0	-- run files with Dedicated Admin Connection

