-- =============================================
-- Author:		<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:		<2021.03.11>
-- Description:		<Backup Website>
-- =============================================

-- For information please refer to the README.md file
use master
go

create or alter proc execute_external_tsql

@InputFiles nvarchar(3000),  -- Delimited by a semicolon (;), executed by given order, enter the files which their path contains space within double quotations. Relative paths must be relative to %systemroot%\system32
@InputFolder NVARCHAR(1000) = '',  -- This sp executes every *.sql script that finds within the specified folder path. Quote addresses that contain space within double quotations.
@Server sysname = '.',
@AuthenticationType nvarchar(10) = N'Windows',    -- any value which does not include the word 'sql' means Windows Authentication
@UserName sysname,
@Password sysname,
@DefaultDatabase sysname = N'master',
@Keep_xp_cmdshell_Enabled BIT = 0,
@isDAC bit = 0    -- run script files with Dedicated Admin Connection

AS
BEGIN
    DECLARE @CommandtoExecute NVARCHAR(2000)=''
    
    -- To allow advanced options to be changed.  
    EXECUTE sp_configure 'show advanced options', 1;  
  
    -- To update the currently configured value for advanced options.  
    RECONFIGURE;  
  
    -- To enable the feature.  
    EXECUTE sp_configure 'xp_cmdshell', 1;  
  
    -- To update the currently configured value for this feature.  
    RECONFIGURE; 
    
    
    ---------- Parameters Standardizations:
    IF @InputFiles IS NULL
        SET @InputFiles = ''
    IF @InputFolder IS NULL
        SET @InputFolder = ''
    IF @AuthenticationType IS NULL
        SET @AuthenticationType = ''
    IF (@InputFiles = '') AND (@InputFolder = '')
    BEGIN
        RAISERROR('You have to specify either @InputFiles or @InputFolder',16,1)
        RETURN 1
    END
    IF @InputFolder <> ''
    BEGIN
        IF RIGHT(@InputFolder,1) <> '\'
            SET @InputFolder+='\'
        Declare @DirTree Table ([file] nvarchar(255))
        DECLARE @cmdshellInput NVARCHAR(500) = 'dir /A /B /S ' + @InputFolder + '*.sql'
        
        insert into @DirTree
  			EXEC master..xp_cmdshell @cmdshellInput		
  		  if ((select TOP 1 [file] from @DirTree) = 'File Not Found')
  		  BEGIN
    			declare @message nvarchar(150) = 'The folder you specified either does not exist or no tsql scripts exist within that folder or its subdirectories'
    			raiserror(@message, 16, 1)
  			  return 1
    		END
        IF @InputFiles <> ''
        BEGIN
            WHILE (RIGHT(@InputFiles,1) = ' ' OR RIGHT(@InputFiles,1) = ';')
            BEGIN
                SET @InputFiles = LEFT(@InputFiles,LEN(@InputFiles)-1)
            END        
            SET @InputFiles += ';'
        END
        
        
        SELECT @InputFiles += CASE WHEN [file] IS NULL THEN '' ELSE ([file] + '; ') END FROM @DirTree
        
        
    END
        
    SET @InputFiles = ';' + @InputFiles
    WHILE RIGHT(@InputFiles,1) = ' ' OR RIGHT(@InputFiles,1) = ';'
    BEGIN
        SET @InputFiles = LEFT(@InputFiles,LEN(@InputFiles)-1)
    END
    IF CHARINDEX('sql',@AuthenticationType) = 0
    BEGIN
      SET @AuthenticationType = 'Windows'
      SET @UserName = ''
      SET @Password = ''
    END
    SET @InputFiles = replace (@InputFiles, ';', ' -i ')
    IF ISNULL(@DefaultDatabase,'') = ''
      SET @DefaultDatabase = 'master'
    
    DECLARE @ConnectionString NVARCHAR(50) = ' sqlcmd -S '+ISNULL(@Server,'.') + CASE WHEN @AuthenticationType <> 'Windows' THEN ' -U ' + @UserName + ' -P ' + @Password ELSE '' END + ' '+CASE @isDAC WHEN 1 THEN ' -A ' ELSE '' END+ ' -d ' + @DefaultDatabase + ' -p1 '
    
    SET @CommandtoExecute =CASE @Keep_xp_cmdshell_Enabled WHEN 0 THEN (@ConnectionString+'-Q "USE master EXECUTE sp_configure ''xp_cmdshell'', 0; RECONFIGURE; EXECUTE sp_configure ''show advanced options'', 0; RECONFIGURE;" &') ELSE '' END+
                            @ConnectionString+@InputFiles
    
--    DECLARE @tempt TABLE ([output] NVARCHAR(255))
--    INSERT INTO @tempt
     
    EXECUTE master..xp_cmdshell @CommandtoExecute
--    DECLARE @cmdshell_msg NVARCHAR(MAX)
--    SELECT @cmdshell_msg+= ISNULL([output],CHAR(10)) FROM @tempt
--    EXECUTE master..PrintLong @cmdshell_msg
    
END

/*
EXECUTE master..execute_external_tsql @InputFiles = N'"C:\Users\Ali\Dropbox\learning\SQL SERVER\InstNwnd.sql"' -- Delimited by a semicolon (;), executed by given order, enter the files which their path contains space within double quotations. Relative paths must be relative to %systemroot%\system32
                                     ,@InputFolder = ''	-- This sp executes every *.sql script that finds within the specified folder path. Quote addresses that contain space within double quotations.
                                     ,@Server = NULL
                                     ,@AuthenticationType = NULL -- any value which does not include the word 'sql' means Windows Authentication
                                     ,@UserName = NULL
                                     ,@Password = NULL
                                     ,@DefaultDatabase = NULL
                                     ,@Keep_xp_cmdshell_Enabled = 0
                                     ,@isDAC = 0	-- run files with Dedicated Admin Connection
*/
