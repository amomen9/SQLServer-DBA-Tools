
-- =============================================
-- Author:		<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:		<2021.03.11>
-- Description:		
-- =============================================

-- Database provisioning & cloning toolkit (anonymized)
-- Provides: helper functions, external T-SQL executor, backup/restore clone, database clone, company DB creation

-- For information please refer to the README.md file

USE AdminDB;
GO

SET NOCOUNT ON;
DROP TABLE IF EXISTS #tmp;
CREATE TABLE #tmp (ErrorCount int);
INSERT #tmp VALUES (0);
GO

-- Find a non‑existing file path (adds _2 recursively before extension)
CREATE OR ALTER FUNCTION dbo.find_nonexistant_name(@Path NVARCHAR(2000))
RETURNS NVARCHAR(2000)
AS
BEGIN
    DECLARE @Result INT;
    EXEC master.dbo.xp_fileexist @Path, @Result OUTPUT;
    IF @Result <> 0
    BEGIN
        SET @Path = LEFT(@Path,LEN(@Path)-4) + '_2' + RIGHT(@Path,4);
        RETURN dbo.find_nonexistant_name(@Path);
    END
    RETURN @Path;
END;
GO

-- Capitalize first letter of each whitespace-delimited token
CREATE OR ALTER FUNCTION dbo.InitCap(@InputString VARCHAR(4000))
RETURNS VARCHAR(4000)
AS
BEGIN
    DECLARE @t TABLE(id INT IDENTITY PRIMARY KEY, Token NVARCHAR(200));
    INSERT @t SELECT value FROM STRING_SPLIT(@InputString,' ');
    UPDATE @t SET Token = STUFF(Token,1,1,UPPER(LEFT(Token,1)));
    RETURN (SELECT STRING_AGG(Token,' ') FROM @t);
END;
GO

-- Normalize a company English name into a DB‑safe stem
CREATE OR ALTER FUNCTION dbo.NormalizeCompanyDBName(@UnnormalizedName SYSNAME)
RETURNS SYSNAME
AS
BEGIN
    WHILE PATINDEX('%[^ 0-9A-Za-z]%',@UnnormalizedName) > 0
    BEGIN
        DECLARE @p INT = PATINDEX('%[^ 0-9A-Za-z]%',@UnnormalizedName);
        SET @UnnormalizedName = LEFT(@UnnormalizedName,@p-1) + RIGHT(@UnnormalizedName,LEN(@UnnormalizedName)-@p);
    END
    SET @UnnormalizedName = TRIM(@UnnormalizedName);
    SET @UnnormalizedName = dbo.InitCap(@UnnormalizedName);
    SET @UnnormalizedName = REPLACE(@UnnormalizedName,' ','');
    SELECT @UnnormalizedName = CONVERT(VARCHAR(MAX),@UnnormalizedName) COLLATE SQL_Latin1_General_Cp1251_CS_AS;
    SELECT @UnnormalizedName = REPLACE(@UnnormalizedName,'?','') COLLATE Latin1_General_CI_AI;
    IF RIGHT(@UnnormalizedName,3)='log'
        SET @UnnormalizedName += '-99';
    RETURN @UnnormalizedName;
END;
GO

-- Execute external .sql files (secure usage requires controlled environment)
CREATE OR ALTER PROC dbo.usp_execute_external_tsql
      @Change_Directory_To_CD NVARCHAR(3000) = ''
    , @InputFiles NVARCHAR(3000) = ''
    , @InputFolder NVARCHAR(1000) = ''
    , @PreCommand NVARCHAR(MAX) = ''
    , @PostCommand NVARCHAR(MAX) = ''
    , @FileName_REGEX_Filter_PowerShell NVARCHAR(128) = '*.sql'
    , @Include_Subdirectories BIT = 1
    , @Server SYSNAME = '.'
    , @AuthenticationType NVARCHAR(10) = N'Windows'
    , @UserName SYSNAME = ''
    , @Password SYSNAME = ''
    , @DefaultDatabase SYSNAME = N'master'
    , @SQLCMD_and_Shell_CodePage INT = 1252
    , @isDAC BIT = 0
    , @Keep_xp_cmdshell_Enabled BIT = 0
    , @Debug_Mode INT = 1
    , @skip_cmdshell_configuration BIT = 0
    , @DoNot_Dispaly_Full_Path BIT = 1
    , @Stop_On_Error BIT = 0
    , @Show_List_of_Executed_Scripts BIT = 1
    , @Stop_After_Executing_Script NVARCHAR(300) = ''
    , @After_Successful_Execution_Policy TINYINT = 0
    , @MoveTo_Folder_Name NVARCHAR(500) = N'done'
AS
BEGIN
    SET NOCOUNT ON;
    DROP TABLE IF EXISTS #output, #output2;
    DECLARE @AbortFlag BIT = 0;

    IF @skip_cmdshell_configuration = 0
    BEGIN
        EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
        EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE;
    END

    SELECT
        @InputFiles = ISNULL(TRIM(REPLACE(@InputFiles,'"','')),''),
        @InputFolder = ISNULL(TRIM(REPLACE(@InputFolder,'"','')),''),
        @AuthenticationType = ISNULL(@AuthenticationType,''),
        @Change_Directory_To_CD = ISNULL(TRIM(REPLACE(@Change_Directory_To_CD,'"','')),''),
        @PreCommand = ISNULL(@PreCommand,''),
        @PostCommand = ISNULL(@PostCommand,''),
        @UserName = ISNULL(@UserName,''),
        @Password = ISNULL(@Password,''),
        @DefaultDatabase = NULLIF(ISNULL(@DefaultDatabase,'master'),'') ,
        @Stop_After_Executing_Script = ISNULL(@Stop_After_Executing_Script,''),
        @SQLCMD_and_Shell_CodePage = ISNULL(@SQLCMD_and_Shell_CodePage,1252);

    IF @Change_Directory_To_CD<>'' AND RIGHT(@Change_Directory_To_CD,1) <> '\'
        SET @Change_Directory_To_CD += '\';

    IF @After_Successful_Execution_Policy > 1 AND ISNULL(@MoveTo_Folder_Name,'') = ''
    BEGIN
        RAISERROR('Move target required when policy > 1.',16,1);
        RETURN 1;
    END
    IF EXISTS (SELECT 1 FROM (VALUES('\'),('/'),(':'),('*'),('?'),('"'),('<'),('>'),('|')) v(c) WHERE CHARINDEX(c,@MoveTo_Folder_Name)>0)
    BEGIN
        RAISERROR('Move folder contains illegal characters.',16,1);
        RETURN 1;
    END

    CREATE TABLE #DirTree(id INT IDENTITY PRIMARY KEY, [file] NVARCHAR(MAX), isFile BIT NOT NULL DEFAULT 1);

    IF @PreCommand <> ''
    BEGIN
        SET IDENTITY_INSERT #DirTree ON;
        INSERT #DirTree(id,[file],isFile) VALUES (0,@PreCommand,0);
        SET IDENTITY_INSERT #DirTree OFF;
    END

    IF (@InputFiles='' AND @InputFolder='' AND @PostCommand='' AND @PreCommand='') 
    BEGIN
        RAISERROR('Nothing to execute.',16,1);
        RETURN 1;
    END

    IF @InputFolder <> ''
    BEGIN
        IF RIGHT(@InputFolder,1) <> '\' SET @InputFolder += '\';
        DECLARE @cmdshellInput VARCHAR(1000) =
            'powershell "Get-ChildItem -Recurse -File '''+@InputFolder+@FileName_REGEX_Filter_PowerShell+''' | %{ $_.FullName }"';
        INSERT INTO #DirTree([file]) EXEC master..xp_cmdshell @cmdshellInput;
        DELETE FROM #DirTree WHERE ISNULL([file],'')='';
        IF NOT EXISTS (SELECT 1 FROM #DirTree WHERE isFile=1)
        BEGIN
            RAISERROR('Folder not found or no matching scripts.',16,1);
            RETURN 1;
        END
    END

    IF @InputFiles <> ''
    BEGIN
        WHILE RIGHT(@InputFiles,1)=';' SET @InputFiles = LEFT(@InputFiles,LEN(@InputFiles)-1);
        INSERT INTO #DirTree([file]) SELECT value FROM STRING_SPLIT(@InputFiles,';');
        DELETE FROM #DirTree WHERE ISNULL([file],'')='';
    END

    IF @Stop_After_Executing_Script <> ''
        DELETE FROM #DirTree WHERE id > (SELECT TOP 1 id FROM #DirTree WHERE CHARINDEX(@Stop_After_Executing_Script,[file])<>0);

    IF @PostCommand <> ''
        INSERT #DirTree([file],isFile) VALUES (@PostCommand,0);

    IF (SELECT COUNT(*) FROM #DirTree)=0
    BEGIN
        RAISERROR('No scripts after filtering.',16,1);
        RETURN 1;
    END

    IF CHARINDEX('sql',LOWER(@AuthenticationType)) = 0
        SELECT @AuthenticationType='Windows', @UserName='', @Password='';

    IF ISNULL(@DefaultDatabase,'')='' SET @DefaultDatabase='master';

    DECLARE @ConnectionString VARCHAR(4000) =
        'sqlcmd ' + CASE WHEN @Server='.' THEN '' ELSE '-S '+@Server+' ' END +
        CASE WHEN @AuthenticationType <> 'Windows' THEN '-U ' + QUOTENAME(@UserName,'"') + ' -P ' + QUOTENAME(@Password,'"') + ' ' ELSE '' END +
        CASE WHEN @isDAC=1 THEN '-A ' ELSE '' END +
        CASE WHEN @DefaultDatabase='master' THEN '' ELSE '-d ' + QUOTENAME(@DefaultDatabase,'"') + ' ' END +
        '-p1' + CASE WHEN @SQLCMD_and_Shell_CodePage IS NOT NULL THEN ' -f '+CONVERT(CHAR(4),@SQLCMD_and_Shell_CodePage) ELSE '' END + ' ';

    CREATE TABLE #output
    (
        id INT IDENTITY PRIMARY KEY,
        ScriptOrdinal INT NULL,
        Script NVARCHAR(MAX) NULL,
        [output] NVARCHAR(255) NULL,
        [Estimated Execution Time] VARCHAR(50) NULL,
        isSuccessful BIT NULL,
        isFile BIT NULL
    );

    DECLARE @ScriptPath NVARCHAR(MAX), @isFile BIT, @id INT, @CommandToExecute NVARCHAR(MAX), @CommandHolder NVARCHAR(MAX);

    DECLARE executor CURSOR FAST_FORWARD FOR
        SELECT [file], isFile, id FROM #DirTree ORDER BY id;
    OPEN executor;
    FETCH NEXT FROM executor INTO @ScriptPath, @isFile, @id;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF CHARINDEX(':',@ScriptPath)=0
        BEGIN
            SET @ScriptPath = @Change_Directory_To_CD + @ScriptPath;
            UPDATE #DirTree SET [file]=@ScriptPath WHERE id=@id;
        END
        SET @CommandToExecute = @ConnectionString + CASE WHEN @isFile=1 THEN '-i ' ELSE '-Q ' END + '"' + @ScriptPath + '"';

        DECLARE @StartTime DATETIME2(7)=SYSDATETIME();
        INSERT #output([output]) EXEC master..xp_cmdshell @CommandToExecute;
        DECLARE @ExecUs BIGINT = DATEDIFF(MICROSECOND,@StartTime,SYSDATETIME());
        DECLARE @Elapsed VARCHAR(50)=RIGHT('00'+CONVERT(VARCHAR(2),@ExecUs/3600000000),2)+':' +
                                     RIGHT('00'+CONVERT(VARCHAR(2),(@ExecUs/60000000)%60),2)+':' +
                                     RIGHT('00'+CONVERT(VARCHAR(2),(@ExecUs/1000000)%60),2)+'.' +
                                     RIGHT(REPLICATE('0',6)+CONVERT(VARCHAR(6),@ExecUs%1000000),6);

        DECLARE @SuccessFlag BIT = IIF((SELECT COUNT(*) FROM #output WHERE ScriptOrdinal IS NULL AND (output LIKE '%Sqlcmd:%' OR output LIKE '%Msg %, Level %'))=0,1,0);

        UPDATE #output
            SET ScriptOrdinal = @id,
                Script = @ScriptPath,
                [Estimated Execution Time] = @Elapsed,
                isSuccessful = @SuccessFlag,
                isFile = @isFile
        WHERE ScriptOrdinal IS NULL;

        IF @Stop_On_Error=1 AND @SuccessFlag=0
        BEGIN
            SET @AbortFlag=1;
            SET @CommandHolder = @CommandToExecute;
            BREAK;
        END

        FETCH NEXT FROM executor INTO @ScriptPath, @isFile, @id;
    END
    CLOSE executor; DEALLOCATE executor;

    DELETE FROM #output WHERE ISNULL([output],'')='';

    IF @Show_List_of_Executed_Scripts = 1
    BEGIN
        SELECT ROW_NUMBER() OVER(ORDER BY MIN(id))-1 AS Row,
               Script AS [Executed Script],
               IIF(@Server='.',@@SERVERNAME,@Server) AS Server,
               @DefaultDatabase AS [Database],
               IIF(@UserName='','Integrated Authentication',@UserName) AS UserName,
               [Estimated Execution Time],
               isSuccessful AS [Was Successful?]
        FROM #output
        GROUP BY Script,[Estimated Execution Time],isSuccessful

        UNION ALL
        SELECT NULL,'Total Executed scripts/Total Found Scripts',NULL,NULL,NULL,
               CONVERT(VARCHAR(10),COUNT(DISTINCT ScriptOrdinal)) + '/' + CONVERT(VARCHAR(10),(SELECT COUNT(*) FROM #DirTree)) +
               IIF(COUNT(DISTINCT ScriptOrdinal)<>(SELECT COUNT(*) FROM #DirTree),' Warning!!!',''),
               NULL
        FROM #output;
    END

    IF @After_Successful_Execution_Policy > 0
    BEGIN
        DECLARE FileOperation CURSOR FAST_FORWARD FOR
            SELECT SUBSTRING(LEFT(Script,LEN(Script)-CHARINDEX('\',REVERSE(Script))+1),LEN(@InputFolder),LEN(Script)) RelativeScriptPath,
                   Script,
                   RIGHT(Script,CHARINDEX('\',REVERSE(Script))-1) FileName,
                   isSuccessful,
                   isFile
            FROM #output
            WHERE isFile=1
            GROUP BY ScriptOrdinal, Script, isSuccessful, isFile
            ORDER BY MIN(id);

        DECLARE @RelativeScriptPath NVARCHAR(1000), @FileName NVARCHAR(255), @Success BIT;
        DECLARE @InputFolderNoSlash NVARCHAR(1000)=LEFT(@InputFolder,LEN(@InputFolder)-1);
        DECLARE @ParentFolder NVARCHAR(2000)=LEFT(@InputFolderNoSlash,LEN(@InputFolderNoSlash)-CHARINDEX('\',REVERSE(@InputFolderNoSlash)));
        DECLARE @TargetFolder NVARCHAR(2000)=@ParentFolder + '\' + @MoveTo_Folder_Name;

        OPEN FileOperation;
        FETCH NEXT FROM FileOperation INTO @RelativeScriptPath,@ScriptPath,@FileName,@Success,@isFile;
        WHILE @@FETCH_STATUS=0
        BEGIN
            IF @Success=1
            BEGIN
                BEGIN TRY
                    IF @After_Successful_Execution_Policy > 1
                    BEGIN
                        DECLARE @Subdir NVARCHAR(2000) = @TargetFolder + @RelativeScriptPath;
                        EXEC xp_create_subdir @Subdir;
                        DECLARE @PathNew NVARCHAR(2000) = @Subdir + @FileName;
                        IF @After_Successful_Execution_Policy > 2
                            SET @PathNew = dbo.find_nonexistant_name(@PathNew);
                        EXEC sys.xp_copy_file @ScriptPath, @PathNew;
                    END
                    IF @After_Successful_Execution_Policy < 4
                        EXEC xp_delete_files @ScriptPath;
                END TRY
                BEGIN CATCH
                    RAISERROR(ERROR_MESSAGE(),16,1);
                END CATCH
            END
            FETCH NEXT FROM FileOperation INTO @RelativeScriptPath,@ScriptPath,@FileName,@Success,@isFile;
        END
        CLOSE FileOperation;
        DEALLOCATE FileOperation;
    END

    IF @Debug_Mode > 1
    BEGIN
        SELECT id, ScriptOrdinal,
               IIF(isFile=1,LEFT(Script,LEN(Script)-CHARINDEX('\',REVERSE(Script))+1),'N/A') AS ScriptPath,
               IIF(isFile=1,RIGHT(Script,CHARINDEX('\',REVERSE(Script))-1),Script) AS Script,
               output,
               LEAD(output) OVER(ORDER BY id) AS [Error Description]
        INTO #output2
        FROM #output
        WHERE isSuccessful = 0;

        DELETE FROM #output2 WHERE output NOT LIKE '%Sqlcmd:%' AND output NOT LIKE '%Msg %, Level %';
        UPDATE #output2 SET [Error Description]=NULL WHERE output NOT LIKE '%Msg %, Level %';

        DECLARE @TotalErrors INT = (SELECT COUNT(*) FROM #output2);
        IF @TotalErrors > 0
            SELECT * FROM #output2 ORDER BY id;

        IF (@Debug_Mode=3 OR @TotalErrors>0)
            SELECT (@TotalErrors - COUNT(*)) AS [Count SQLCMD Errors],
                   COUNT(*) AS [Count SQL Errors],
                   COUNT(DISTINCT LEFT([output],CHARINDEX(',',[output]))) AS [Count distinct SQL Errors]
            FROM #output2
            WHERE [output] LIKE '%Msg %, Level %';
    END
    ELSE IF @Debug_Mode = 1
        SELECT * FROM #output ORDER BY id;

    IF @Keep_xp_cmdshell_Enabled = 0 AND @skip_cmdshell_configuration = 0
    BEGIN
        EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE;
        EXEC sp_configure 'show advanced options', 0; RECONFIGURE;
    END

    IF @AbortFlag = 1
    BEGIN
        RAISERROR('Aborted due to error and Stop_On_Error set.',16,1);
        PRINT 'Last command executed:';
        PRINT @CommandHolder;
        RETURN 1;
    END
END;
GO

-- Complete restore (single backup file) with optional relocation
CREATE OR ALTER PROC dbo.sp_complete_restore
      @Drop_Database_if_Exists BIT = 0
    , @Restore_DBName SYSNAME
    , @Restore_Suffix SYSNAME = ''
    , @Restore_Prefix SYSNAME = ''
    , @Ignore_Existant BIT = 0
    , @Backup_Location NVARCHAR(1000)
    , @Destination_Database_DataFiles_Location NVARCHAR(300) = ''
    , @Destination_Database_LogFile_Location NVARCHAR(300) = ''
    , @Take_tail_of_log_backup BIT = 1
    , @Keep_Database_in_Restoring_State BIT = 0
    , @DataFileSeparatorChar NVARCHAR(2) = '_'
    , @Change_Target_RecoveryModel_To NVARCHAR(20) = 'same'
    , @Set_Target_Database_ReadOnly BIT = 0
    , @STATS TINYINT = 50
    , @Generate_Statements_Only BIT = 0
    , @Delete_Backup_File BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET @STATS = ISNULL(@STATS,0);
    SET @Restore_Suffix = ISNULL(@Restore_Suffix,'');
    SET @Restore_Prefix = ISNULL(@Restore_Prefix,'');
    SET @Restore_DBName = @Restore_Prefix + @Restore_DBName + @Restore_Suffix;
    IF (@Change_Target_RecoveryModel_To IS NULL) OR (@Change_Target_RecoveryModel_To='')
        SET @Change_Target_RecoveryModel_To='same';
    SET @Destination_Database_DataFiles_Location = ISNULL(@Destination_Database_DataFiles_Location,'');
    SET @Destination_Database_LogFile_Location = ISNULL(@Destination_Database_LogFile_Location,'');

    IF (@Change_Target_RecoveryModel_To NOT IN ('FULL','BULK-LOGGED','SIMPLE','SAME'))
    BEGIN
        RAISERROR('Invalid recovery model.',16,1);
        RETURN 1;
    END

    IF (@Destination_Database_DataFiles_Location = '')
        SET @Destination_Database_DataFiles_Location = CONVERT(NVARCHAR(1000),SERVERPROPERTY('InstanceDefaultDataPath'));
    IF (@Destination_Database_LogFile_Location = '')
        SET @Destination_Database_LogFile_Location = CONVERT(NVARCHAR(1000),SERVERPROPERTY('InstanceDefaultLogPath'));

    DECLARE @Back_DateandTime NVARCHAR(20) = REPLACE(CONVERT(DATE,GETDATE()),'-','.') + '_' +
                                            SUBSTRING(REPLACE(CONVERT(NVARCHAR(10),CONVERT(TIME,GETDATE())),':',''),1,4);
    DECLARE @DB_Restore_Script NVARCHAR(MAX) = '';
    DECLARE @DropDatabaseStatement NVARCHAR(MAX) = '';

    PRINT('--- Restore: '+@Restore_DBName);

    IF DB_ID(@Restore_DBName) IS NOT NULL
    BEGIN
        IF @Ignore_Existant = 1
        BEGIN
            RAISERROR('Target database exists.',16,1);
            RETURN 1;
        END

        DECLARE @dbinfo TABLE(ParentObject NVARCHAR(100),Object NVARCHAR(100),Field NVARCHAR(100),[VALUE] NVARCHAR(100));
        DECLARE @DBCCStatement NVARCHAR(200)='DBCC DBINFO('+QUOTENAME(@Restore_DBName)+') WITH TABLERESULTS, NO_INFOMSGS';
        INSERT @dbinfo EXEC (@DBCCStatement);

        DECLARE @isPseudoSimple_or_Simple BIT = 0;
        IF CAST(CAST(SERVERPROPERTY('ProductVersion') AS CHAR(4)) AS FLOAT) <= 10.5
        BEGIN
            IF (SELECT TOP 1 [VALUE] FROM @dbinfo WHERE [Object]='dbi_dbbackupLSN' ORDER BY ParentObject)='0'
                SET @isPseudoSimple_or_Simple = 1;
        END
        ELSE
        BEGIN
            IF (SELECT TOP 1 [VALUE] FROM @dbinfo WHERE Field='dbi_dbbackupLSN' ORDER BY ParentObject)='0:0:0 (0x00000000:00000000:0000)'
                SET @isPseudoSimple_or_Simple = 1;
        END

        IF (SELECT state FROM sys.databases WHERE name=@Restore_DBName)=0
        BEGIN
            SET @DB_Restore_Script += 'USE '+QUOTENAME(@Restore_DBName)+'; ALTER DATABASE '+QUOTENAME(@Restore_DBName)+' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
            IF @Generate_Statements_Only=0 EXEC (@DB_Restore_Script);
            SET @DB_Restore_Script='';
        END

        IF (@isPseudoSimple_or_Simple <> 1 AND @Take_tail_of_log_backup=1)
        BEGIN
            DECLARE @TailofLOG_Backup_Name NVARCHAR(100)='TailofLOG_'+@Restore_DBName+'_Backup_'+@Back_DateandTime+'.trn';
            DECLARE @TailScript NVARCHAR(MAX)='BACKUP LOG '+QUOTENAME(@Restore_DBName)+' TO DISK = '''+@TailofLOG_Backup_Name+
                                              ''' WITH FORMAT, NAME='''+@TailofLOG_Backup_Name+''', NOREWIND, NOUNLOAD, NORECOVERY;';
            IF @Generate_Statements_Only=0 EXEC (@TailScript);
        END

        IF @Drop_Database_if_Exists=1
        BEGIN
            SET @DropDatabaseStatement = 'DROP DATABASE '+QUOTENAME(@Restore_DBName)+';';
            GOTO restoreanew;
        END

        SET @DB_Restore_Script = 'RESTORE DATABASE '+QUOTENAME(@Restore_DBName)+' FROM DISK='''+@Backup_Location+
                                 ''' WITH FILE=1, NOUNLOAD, REPLACE, KEEP_CDC, KEEP_REPLICATION';
        IF @Keep_Database_in_Restoring_State=1
            SET @DB_Restore_Script += ', NORECOVERY';
    END
    ELSE
    BEGIN
RESTOREANEW:
        IF OBJECT_ID('tempdb..#Backup_Files_List') IS NOT NULL DROP TABLE #Backup_Files_List;
        CREATE TABLE #Backup_Files_List
        (
            LogicalName NVARCHAR(128),
            PhysicalName NVARCHAR(260),
            [Type] CHAR(1),
            FileGroupName NVARCHAR(128) NULL,
            Size NUMERIC(20,0),
            MaxSize NUMERIC(20,0),
            FileID BIGINT,
            CreateLSN NUMERIC(25,0),
            DropLSN NUMERIC(25,0) NULL,
            UniqueID UNIQUEIDENTIFIER,
            ReadOnlyLSN NUMERIC(25,0) NULL,
            ReadWriteLSN NUMERIC(25,0) NULL,
            BackupSizeInBytes BIGINT,
            SourceBlockSize INT,
            FileGroupID INT,
            LogGroupGUID UNIQUEIDENTIFIER NULL,
            DifferentialBaseLSN NUMERIC(25,0) NULL,
            DifferentialBaseGUID UNIQUEIDENTIFIER NULL,
            IsReadOnly BIT,
            IsPresent BIT
        );
        IF CAST(CAST(SERVERPROPERTY('ProductVersion') AS CHAR(4)) AS FLOAT) > 9
            ALTER TABLE #Backup_Files_List ADD TDEThumbprint VARBINARY(32) NULL;
        IF CAST(CAST(SERVERPROPERTY('ProductVersion') AS CHAR(2)) AS FLOAT) > 12
            ALTER TABLE #Backup_Files_List ADD SnapshotURL NVARCHAR(360) NULL;

        DECLARE @sql NVARCHAR(MAX)='RESTORE FILELISTONLY FROM DISK=@Backup_Path';
        INSERT INTO #Backup_Files_List
        EXEC master.sys.sp_executesql @sql, N'@Backup_Path nvarchar(150)', @Backup_Location;

        SET @DB_Restore_Script = @DropDatabaseStatement + 'RESTORE DATABASE '+QUOTENAME(@Restore_DBName)+' FROM DISK = N''' +
                                 @Backup_Location + ''' WITH FILE=1, KEEP_CDC, KEEP_REPLICATION';

        IF ((@Restore_Suffix<>'' OR @Restore_Prefix<>'') OR @Destination_Database_DataFiles_Location <> 'same')
        BEGIN
            IF @Generate_Statements_Only=0 AND @Destination_Database_DataFiles_Location <> 'same'
                EXEC xp_create_subdir @Destination_Database_DataFiles_Location;
            IF @Generate_Statements_Only=0 AND @Destination_Database_DataFiles_Location <> 'same'
                EXEC xp_create_subdir @Destination_Database_LogFile_Location;

            SELECT @DB_Restore_Script +=
                   ', MOVE N''' + LogicalName + ''' TO N''' +
                   CASE WHEN FileID=2 THEN
                        IIF(@Destination_Database_DataFiles_Location <> 'same',
                            @Destination_Database_LogFile_Location,
                            LEFT(PhysicalName,LEN(PhysicalName)-CHARINDEX('\',REVERSE(PhysicalName))))
                        ELSE
                        IIF(@Destination_Database_DataFiles_Location <> 'same',
                            @Destination_Database_DataFiles_Location,
                            LEFT(PhysicalName,LEN(PhysicalName)-CHARINDEX('\',REVERSE(PhysicalName))))
                   END + '\' + @Restore_DBName +
                   RIGHT(PhysicalName,
                         CASE WHEN CHARINDEX(@DataFileSeparatorChar,RIGHT(PhysicalName,CHARINDEX('\',REVERSE(PhysicalName))))<>0
                              THEN CHARINDEX(@DataFileSeparatorChar,REVERSE(PhysicalName))
                              ELSE CHARINDEX('.',REVERSE(PhysicalName)) END) + ''''
            FROM #Backup_Files_List;
        END
        ELSE IF (@Destination_Database_DataFiles_Location='same' AND @Generate_Statements_Only=0)
        BEGIN
            DECLARE mkdir CURSOR FAST_FORWARD FOR SELECT PhysicalName FROM #Backup_Files_List;
            DECLARE @DirPath NVARCHAR(1000);
            OPEN mkdir;
            FETCH NEXT FROM mkdir INTO @DirPath;
            WHILE @@FETCH_STATUS=0
            BEGIN
                SELECT @DirPath = LEFT(@DirPath,LEN(@DirPath)-CHARINDEX('\',REVERSE(@DirPath)));
                EXEC xp_create_subdir @DirPath;
                FETCH NEXT FROM mkdir INTO @DirPath;
            END
            CLOSE mkdir; DEALLOCATE mkdir;
        END

        IF @Keep_Database_in_Restoring_State=1
            SET @DB_Restore_Script += ', NORECOVERY';

        SET @DB_Restore_Script += ', NOUNLOAD, REPLACE';
    END

    IF @STATS<>0 SET @DB_Restore_Script += ', STATS = '+CONVERT(VARCHAR(3),@STATS);
    PRINT @DB_Restore_Script;
    IF @Generate_Statements_Only = 0 EXEC (@DB_Restore_Script);

    IF @@ERROR = 0 AND @Delete_Backup_File=1
    BEGIN
        EXEC xp_delete_files @Backup_Location;
    END

    IF ((SELECT state FROM sys.databases WHERE name=@Restore_DBName)=0 AND @Generate_Statements_Only=0)
    BEGIN
        DECLARE @post NVARCHAR(MAX)='';
        IF @Change_Target_RecoveryModel_To <> 'same'
            SET @post += 'ALTER DATABASE '+QUOTENAME(@Restore_DBName)+' SET RECOVERY ' + @Change_Target_RecoveryModel_To + ';';
        SET @post += 'ALTER DATABASE '+QUOTENAME(@Restore_DBName)+' SET MULTI_USER;';
        EXEC (@post);

        IF @Change_Target_RecoveryModel_To='SIMPLE'
        BEGIN
            DECLARE @shrink NVARCHAR(MAX) =
                'USE '+QUOTENAME(@Restore_DBName)+'; DECLARE @FileName SYSNAME = (SELECT name FROM sys.database_files WHERE file_id=2); ' +
                'DECLARE @SQL NVARCHAR(400)= ''DBCC SHRINKFILE(''+QUOTENAME(@FileName,'''')+'',0) WITH NO_INFOMSGS''; EXEC (@SQL);';
            EXEC (@shrink);
        END

        IF @Set_Target_Database_ReadOnly=1
            EXEC ('ALTER DATABASE '+QUOTENAME(@Restore_DBName)+' SET READ_ONLY;');
    END
END;
GO

-- Clone DB using backup/restore (full copy)
CREATE OR ALTER PROC dbo.sp_CloneDB
(
      @Source_Server_ConnectionString NVARCHAR(500) = ''
    , @Target_Server_Connection_String NVARCHAR(500) = ''
    , @SourceDB_Name NVARCHAR(128)
    , @TargetDB_Name SYSNAME
    , @Temporary_Directory NVARCHAR(500) = ''
    , @Schema_only BIT = 0
    , @Replace_if_Exists BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET @Replace_if_Exists = ~@Replace_if_Exists; -- reuse logic from original (invert meaning)
    DECLARE @TimeStamp VARCHAR(11)=FORMAT(GETDATE(),'yyMMdd_hhmm','en');
    SET @Temporary_Directory = CONVERT(NVARCHAR(2000),SERVERPROPERTY('InstanceDefaultBackupPath'));
    DECLARE @Backup_Path NVARCHAR(2000) = @Temporary_Directory + '\' + @SourceDB_Name + '_' + @TimeStamp + '.bak';

    BACKUP DATABASE @SourceDB_Name TO DISK=@Backup_Path WITH INIT, COPY_ONLY, CHECKSUM, COMPRESSION, STOP_ON_ERROR;

    IF @@ERROR = 0
        EXEC dbo.sp_complete_restore
              @Drop_Database_if_Exists = 0
            , @Restore_DBName = @TargetDB_Name
            , @Restore_Suffix = ''
            , @Restore_Prefix = ''
            , @Ignore_Existant = @Replace_if_Exists
            , @Backup_Location = @Backup_Path
            , @Destination_Database_DataFiles_Location = N''
            , @Destination_Database_LogFile_Location = N''
            , @Take_tail_of_log_backup = 0
            , @Keep_Database_in_Restoring_State = 0
            , @DataFileSeparatorChar = N'_'
            , @Change_Target_RecoveryModel_To = N'FULL'
            , @Set_Target_Database_ReadOnly = 0
            , @STATS = 50
            , @Generate_Statements_Only = 0
            , @Delete_Backup_File = 1;
END;
GO

-- Provision a new organization database from template and seed data
CREATE OR ALTER PROC dbo.sp_create_new_OrgDB
(
      @OrgID INT
    , @SendSuccessEmail BIT = 1
)
WITH EXECUTE AS 'dbo'
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @OrgStem SYSNAME = dbo.NormalizeCompanyDBName((SELECT NameEn FROM AppMainDB.dbo.Companies WHERE Id=@OrgID));
        IF @OrgStem IS NULL
        BEGIN
            RAISERROR('Normalized name invalid.',16,1);
            RETURN 1;
        END

        DECLARE @CompanyDBName SYSNAME = 'Org-'+@OrgStem+'DB';
        DECLARE @ConnString NVARCHAR(2000) = N'Server=10.10.10.10,1433;database='+@CompanyDBName+';user id=AppPublic;password=StrongPassword!;multipleactiveresultsets=true';
        PRINT '--- Creating database from template: '+@CompanyDBName;

        EXEC dbo.sp_CloneDB
              @SourceDB_Name = N'Org-TemplateDB'
            , @TargetDB_Name = @CompanyDBName
            , @Schema_only = 0;

        DELETE FROM AppMainDB.dbo.CompanyConnStrings WHERE CompanyId=@OrgID;
        INSERT AppMainDB.dbo.CompanyConnStrings(ConnectionString,CompanyId,IsDeleted) VALUES (@ConnString,@OrgID,0);

        UPDATE AppMainDB.dbo.Companies
           SET ConnectionString = 'Server=10.10.10.10,1433;database='+@OrgStem+';multipleactiveresultsets=true'
         WHERE Id=@OrgID;

        DECLARE @SQL NVARCHAR(MAX);

        -- Seed operator record
        SET @SQL = '
            UPDATE '+QUOTENAME(@CompanyDBName)+'.Ats.Operators
               SET FullName = src.FullName,
                   SubmitTime = src.CreatedDate,
                   SubmitterOperatorId = src.SubmitterOperatorId,
                   UserGuid = src.Id,
                   FullNameEn = src.FullNameEn,
                   OperatorEmail = src.OperatorEmail,
                   PhoneNumber = src.PhoneNumber,
                   UserEmail = src.Email,
                   CompanyUserID_old = src.CompanyUserID_old
            FROM (
                SELECT a.Id,
                       c.FullName,
                       c.CreatedDate,
                       NULL SubmitterOperatorId,
                       '''' FullNameEn,
                       '''' OperatorEmail,
                       c.PhoneNumber,
                       c.Email,
                       NULL CompanyUserID_old
                FROM AppMainDB.dbo.CompanyUsers c
                JOIN IdentityDB.dbo.AspNetUsers a ON c.UserId=a.Id
                WHERE c.CompanyId = '+CONVERT(VARCHAR(10),@OrgID)+'
            ) src
            WHERE '+QUOTENAME(@CompanyDBName)+'.Ats.Operators.Id = 1;';
        EXEC (@SQL);

        -- Seed configuration
        SET @SQL = '
            UPDATE '+QUOTENAME(@CompanyDBName)+'.dbo.Configuration
               SET CompanyFaName = src.NameFa,
                   CompanyEnName = src.NameEn,
                   SubmitTime = src.SubmitTime,
                   SubmitterOperatorId = 1,
                   ProductId = 1,
                   CompanyAddressLat = 0,
                   CompanyAddressLng = 0,
                   CompanyId = src.Id
            FROM (
                SELECT Id, NameFa, NameEn, SubmitTime
                FROM AppMainDB.dbo.Companies
                WHERE Id = '+CONVERT(VARCHAR(10),@OrgID)+'
            ) src;';
        EXEC (@SQL);

        -- Copy configuration snapshot
        SET @SQL = '
            DELETE FROM AppMainDB.dbo.CompaniesConfigurations WHERE DBName = '''+@CompanyDBName+''';
            INSERT AppMainDB.dbo.CompaniesConfigurations
            SELECT CompanyFaName, CompanyEnName, LogoFileId, BannerTitle, BannerDescription, BannerFileId,
                   AboutUs, InstagramLink, LinkedinLink, TelegramLink, TwitterLink, WebsiteAddress, IndustryId,
                   SubmitTime, SubmitterOperatorId, EditTime, EditorOperatorId, ProductId, AboutUsFileId,
                   CompanyAddress, CompanyBrandColor, CompanyAddressLat, CompanyAddressLng, CompanyTelephone,
                   CompanyValue, CompanyValueFileId, LogoFileId_old, BannerFileId_old, AboutUsFileId_old,
                   CompanyValueFileId_old, CompanyId, BannerType, DepartmentDisplayFilter, BannerFileIds,
                   HasAutoMerge, AutoMergePeriodTime, InterviewAssessmentNotifyIntervalTime,
                   '''+@CompanyDBName+''' AS DBName, HasBranch, ''Production'', 0
            FROM '+QUOTENAME(@CompanyDBName)+'.dbo.Configuration;';
        EXEC (@SQL);

        -- Execute permissions / auth script
        EXEC dbo.usp_execute_external_tsql
             @InputFiles = N'"\\fileserver\AppMigration\DBA\Modules\orgDB_auth.sql"'
           , @DefaultDatabase = @CompanyDBName
           , @Debug_Mode = 2;

        UPDATE AppMainDB.dbo.Companies SET StatusId = 30 WHERE Id=@OrgID;

        DECLARE @UserId UNIQUEIDENTIFIER = (SELECT TOP 1 UserId FROM AppMainDB.dbo.CompanyUsers WHERE CompanyId=@OrgID AND Product=1);
        DECLARE @UserFullName NVARCHAR(MAX) = (SELECT FullName FROM IdentityDB.dbo.AspNetUsers WHERE Id=@UserId);
        DECLARE @UserEmail NVARCHAR(256) = (SELECT Email FROM IdentityDB.dbo.AspNetUsers WHERE Id=@UserId);
        DECLARE @UserPhone NVARCHAR(MAX) = (SELECT PhoneNumber FROM IdentityDB.dbo.AspNetUsers WHERE Id=@UserId);
        DECLARE @CompanyFaName NVARCHAR(40) = (SELECT NameFa FROM AppMainDB.dbo.Companies WHERE Id=@OrgID);
        DECLARE @CompanyEnName NVARCHAR(40) = (SELECT NameEn FROM AppMainDB.dbo.Companies WHERE Id=@OrgID);

        -- Calendar seed
        SET @SQL = 'USE '+QUOTENAME(@CompanyDBName)+';
            DELETE FROM Calendar.AccessGrants;
            DBCC CHECKIDENT(''Calendar.AccessGrants'',RESEED,1) WITH NO_INFOMSGS;
            DELETE FROM Calendar.Calendars;
            DBCC CHECKIDENT(''Calendar.Calendars'',RESEED,1) WITH NO_INFOMSGS;
            DELETE FROM Calendar.Operators;
            DBCC CHECKIDENT(''Calendar.Operators'',RESEED,1) WITH NO_INFOMSGS;';
        EXEC (@SQL);

        SET @SQL = 'USE '+QUOTENAME(@CompanyDBName)+';
            INSERT Calendar.Operators(UserId,FullName,CreatedAt,LastModifiedAt,LastModifiedBy,IsDeleted)
            SELECT UserGuid,FullName,SubmitTime,NULL,NULL,
                   CASE WHEN StatusId=31 THEN 0 WHEN StatusId=32 THEN 1 END
            FROM Ats.Operators WHERE Id<>0;

            INSERT Calendar.Calendars(Name,IsSync,IsDefault,OperatorId,CreatedAt,LastModifiedAt,LastModifiedBy,IsDeleted)
            SELECT ''default'',0,1,Id,CreatedAt,NULL,NULL,IsDeleted FROM Calendar.Operators;

            INSERT Calendar.AccessGrants(AccessedOperatorId,AccessedCalendarId,EventType,AccessType,CreatedBy,CreatedAt,LastModifiedAt,LastModifiedBy,IsDeleted)
            SELECT o.Id AS AccessedOperatorId, c.Id AS AccessedCalendarId, 1,1,1,c.CreatedAt,NULL,NULL,0
            FROM Calendar.Calendars c
            CROSS JOIN (
                SELECT co.Id
                FROM Ats.Operators o
                JOIN Ats.OperatorRoleBranches r ON r.OperatorId=o.Id
                JOIN Calendar.Operators co ON co.UserId=o.UserGuid
                WHERE r.RoleId=1
            ) o
            WHERE o.Id <> c.OperatorId;';
        EXEC (@SQL);

        -- Notification seed
        DELETE FROM NotifyDB.dbo.OperatorNotificationParties WHERE CompanyId=@OrgID;
        BEGIN TRY
            INSERT NotifyDB.dbo.Companies(Id,SendingSMSMethod,Name)
            VALUES (@OrgID,1,@CompanyEnName);
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER()<>2627 RAISERROR(ERROR_MESSAGE(),16,1);
        END CATCH;

        SET @SQL = '
            DECLARE @FirstOperatorId INT = (SELECT TOP 1 Id FROM '+QUOTENAME(@CompanyDBName)+'.Ats.Operators WHERE Id>0 ORDER BY Id);
            INSERT NotifyDB.dbo.OperatorNotificationParties
            (IsDeleted,SendingEmailMethod,OperatorId,CompanyId,Name)
            VALUES
            (0,1,0,@OrgID,(SELECT FullName FROM '+QUOTENAME(@CompanyDBName)+'.Ats.Operators WHERE Id=0)),
            (0,1,@FirstOperatorId,@OrgID,(SELECT FullName FROM '+QUOTENAME(@CompanyDBName)+'.Ats.Operators WHERE Id=@FirstOperatorId));';
        EXEC sp_executesql @SQL,N'@OrgID int',@OrgID;

        -- Availability Group add (if on designated servers)
        IF @@SERVERNAME LIKE 'App-DB%'
        BEGIN
            DECLARE @SecondaryServer SYSNAME =
                (SELECT TOP 1 name FROM sys.servers WHERE server_id<>0 AND name LIKE 'App-DB%');
            IF @SecondaryServer IS NOT NULL
            BEGIN
                SELECT @SecondaryServer = LEFT(@SecondaryServer,CHARINDEX(',',@SecondaryServer+',')-1);
                SET @SQL = 'ALTER AVAILABILITY GROUP [AG-AppDB] MODIFY REPLICA ON N'''+@SecondaryServer+''' WITH (SEEDING_MODE = AUTOMATIC);';
                EXEC (@SQL);
                SET @SQL = 'ALTER AVAILABILITY GROUP [AG-AppDB] ADD DATABASE '+QUOTENAME(@CompanyDBName)+';';
                EXEC (@SQL);
                SET @SecondaryServer += ',1433';
                SET @SQL = 'EXEC (''ALTER AVAILABILITY GROUP [AG-AppDB] GRANT CREATE ANY DATABASE;'') AT '+QUOTENAME(@SecondaryServer)+';';
                EXEC (@SQL);
            END
        END

        -- Success email
        IF @SendSuccessEmail = 1 AND @@SERVERNAME IN ('App-DB1','App-DB2')
        BEGIN
            DECLARE @MailBody NVARCHAR(MAX) =
            '<!doctype html><html><body>' +
            '<p><b>Organization database created</b></p>' +
            '<p>Name: '+ISNULL(@OrgStem,'(null)')+'</p>' +
            '<ul>' +
            '<li>Org ID: '+ISNULL(CONVERT(NVARCHAR(10),@OrgID),'')+'</li>' +
            '<li>Contact: '+ISNULL(@UserFullName,'')+'</li>' +
            '<li>Email: '+ISNULL(@UserEmail,'')+'</li>' +
            '<li>Phone: '+ISNULL(@UserPhone,'')+'</li>' +
            '<li>DB: '+ISNULL(@CompanyDBName,'')+'</li>' +
            '</ul>' +
            '</body></html>';

            DECLARE @recipients NVARCHAR(MAX) =
                (SELECT Recipients FROM AppMainDB.dbo.EmailRecipients WHERE RecipientGroupDescription='NewOrgRegistration');

            EXEC msdb.dbo.sp_send_dbmail
                  @profile_name = 'AppMailProfile'
                , @recipients = @recipients
                , @subject = N'Organization database created'
                , @body = @MailBody
                , @body_format = 'HTML'
                , @reply_to = 'noreply@example.com';
        END

        PRINT 'Provisioning complete.';
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(MAX)=ERROR_MESSAGE();
        DECLARE @CompanyDBName SYSNAME='Org-'+ISNULL(@OrgStem,'Unknown')+'DB';
        DECLARE @MailBody NVARCHAR(MAX)=ISNULL(@CompanyDBName,'(null)')+CHAR(10)+CHAR(10)+'Error:'+CHAR(10)+ISNULL(@ErrMsg,'(null)');
        EXEC msdb.dbo.sp_send_dbmail
              @profile_name='AppMailProfile'
            , @recipients='dba@example.com'
            , @subject=N'Provision failure'
            , @body=@MailBody
            , @reply_to='dba@example.com';
        RAISERROR(@ErrMsg,16,1);
    END CATCH
END;
GO

-- Safety check: prevent accidental run on unintended server
IF COALESCE(CONVERT(NVARCHAR(20),DATABASEPROPERTYEX('IdentityDB','Updateability')),'Read_Only')='Read_Only'
    OR @@SERVERNAME NOT LIKE 'App-DB%'
BEGIN
    RAISERROR('Wrong connection context.',16,1);
    RETURN;
END;
GO

-- Example (commented):
-- EXEC dbo.sp_create_new_OrgDB @OrgID = 1001, @SendSuccessEmail = 0;
GO

-- Optional cleanup definitions (comment out if you need to retain objects)
/*
DROP FUNCTION dbo.find_nonexistant_name;
DROP FUNCTION dbo.InitCap;
DROP FUNCTION dbo.NormalizeCompanyDBName;
DROP PROC dbo.usp_execute_external_tsql;
DROP PROC dbo.sp_complete_restore;
DROP PROC dbo.sp_CloneDB;
DROP PROC dbo.sp_create_new_OrgDB;
GO
*/