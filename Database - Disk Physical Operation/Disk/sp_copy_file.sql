--DROP TYPE IF EXISTS File_Table
IF not EXISTS (SELECT 1 FROM sys.types WHERE name = 'File_Table')
	CREATE TYPE File_Table AS TABLE   
	( 
		[file or directory] NVARCHAR(2000) NOT NULL,
		[Destination] NVARCHAR(2000) NOT NULL  		
	);  
ELSE
	PRINT 'Warning! The File_Table type already exists, it may be different than what this stored procedure needs.'
GO


CREATE OR ALTER PROC sp_copy_files
	@File_Table File_Table READONLY,
	@move BIT = 0,
	@Replace_String_Replacement sysname = '',
	@Replace_Pattern sysname = '',
	@NO_INFOMSGS BIT = 0
AS
BEGIN
	SET NOCOUNT on
	DECLARE @PhysicalName NVARCHAR(2000),
			@Destination NVARCHAR(2000),
			@CMDSHELL_Command1 VARCHAR(1000),
			@CMDSHELL_Command2 VARCHAR(1000),
			@FileName NVARCHAR(255),
			@New_Datafile_Directory NVARCHAR(300),
			@Physical_Directory NVARCHAR(500),
			@NewPath NVARCHAR(500),
			@Error_Line INT,
			@message NVARCHAR(300),
			@isfile BIT 


	SELECT 
		*
	INTO #File_Table
	FROM @File_Table

	UPDATE #File_Table
	SET [file or directory] = TRIM(REPLACE([file or directory],'"',''))

	UPDATE #File_Table
	SET Destination = TRIM(REPLACE(Destination,'"',''))

	
	WHILE @@ROWCOUNT<>0
		UPDATE #File_Table
		SET [file or directory]=LEFT([file or directory],LEN([file or directory])-1)
		WHERE RIGHT([file or directory],1)='\'
	
	
	UPDATE #File_Table
	SET Destination+='\'
	WHERE RIGHT(Destination,1)<>'\'
	


	EXEC sys.sp_configure @configname = 'show advanced options', -- varchar(35)
						  @configvalue = 1  -- int
	RECONFIGURE
	EXEC sys.sp_configure @configname = 'cmdshell', -- varchar(35)
						  @configvalue = 1  -- int
	RECONFIGURE
	PRINT ''

	CREATE TABLE #tmp (id INT IDENTITY PRIMARY KEY NOT NULL, [output] NVARCHAR(500)) 
	
	IF NOT EXISTS (SELECT 1 FROM #File_Table WHERE ISNULL(Destination,'') <> '')
	BEGIN 
		RAISERROR('All the destinations you have specified are invalid',16,1)
		RETURN 1
	END 

	IF NOT EXISTS (SELECT 1 FROM #File_Table CROSS APPLY sys.dm_os_file_exists([file or directory]) WHERE (file_exists+file_is_a_directory)=1)
	BEGIN 
		RAISERROR('None of the files you want to copy exist.',16,1)
		RETURN 1
	END 

	DECLARE Copier CURSOR FOR
		SELECT 
			[file or directory],
			right([file or directory],charindex('\',reverse([file or directory]))-1) FileName,
			left([file or directory],LEN([file or directory])-CHARINDEX('\',reverse([file or directory]))+1) physical_directory,
			Destination
		FROM #File_Table
	OPEN Copier
		FETCH NEXT FROM Copier INTO @PhysicalName, @FileName, @Physical_Directory, @Destination
		WHILE @@FETCH_STATUS=0
		BEGIN
			BEGIN TRY
				IF @Destination<>''
					EXEC sys.xp_create_subdir @Destination
				TRUNCATE TABLE #tmp
				SET @NewPath = @Destination + @FileName
				IF (SELECT file_exists FROM sys.dm_os_file_exists(@PhysicalName)) = 1
				BEGIN					
					SET @CMDSHELL_Command1 = 'ROBOCOPY "' + @Physical_Directory + ' " "' + @Destination + ' " "' + @FileName + '" /J /COPY:DATSOU '+IIF(@move = 1,'/MOV','')+' /MT:8 /R:3 /W:1 /UNILOG+:ROBOout.log /TEE /UNICODE'
					SET @isfile = 1
					INSERT #tmp					
					EXEC master.sys.xp_cmdshell @CMDSHELL_Command1
                END
				ELSE 
					IF (SELECT file_is_a_directory FROM sys.dm_os_file_exists(@PhysicalName)) = 1
					BEGIN
						
						SET @CMDSHELL_Command1 = 'ROBOCOPY '+IIF(@move = 1,'/MOVE','')+' /E /COMPRESS "'+@PhysicalName+'" "'+@NewPath+'"'
						SET @isfile = 0
						INSERT #tmp						
						EXEC master.sys.xp_cmdshell @CMDSHELL_Command1
					END
					ELSE
						RAISERROR('The source file/directory you specified does not exist.',16,1)
					SELECT @Error_Line = id from #tmp where [output] like '%ERROR%'
					SELECT @message = (select string_agg([output],char(10)) from #tmp where id between @Error_Line and (@Error_Line+1))
					if @Error_Line is not null
					BEGIN
						declare @Warning_Message nvarchar(300) = 'Warning!!! Copy process failed:'+char(10)+@message
						print @Warning_Message
					END
					ELSE
						IF (SELECT file_exists+file_is_a_directory FROM sys.dm_os_file_exists(@NewPath))=1
						BEGIN 
							IF @NO_INFOMSGS = 0
							BEGIN 
								SET @message = 'The '+IIF(@isfile = 1,'file','folder')+CHAR(9)+'"'+@FileName+'" was successfully '+IIF(@move=1,'moved','copied')+' from "'+@Physical_Directory+'" to "'+@Destination+'".'
								RAISERROR(@message,0,1) WITH NOWAIT
							END 
						END 
                    
            END TRY
			BEGIN CATCH
				DECLARE @PRINT_or_RAISERROR INT = 1			-- 1 for print 2 for RAISERROR
				DECLARE @ErrMsg NVARCHAR(500) = ERROR_MESSAGE()
				DECLARE @ErrLine NVARCHAR(500) = ERROR_LINE()
				DECLARE @ErrNo nvarchar(6) = CONVERT(NVARCHAR(6),ERROR_NUMBER())
				DECLARE @ErrState nvarchar(3) = CONVERT(NVARCHAR(3),ERROR_STATE())
				DECLARE @ErrSeverity nvarchar(2) = CONVERT(NVARCHAR(2),ERROR_SEVERITY())
				DECLARE @UDErrMsg nvarchar(MAX) = 'Something went wrong during the operation. Depending on your preference the operation will fail or continue, skipping this iteration.'+CHAR(10)+'System error message:'+CHAR(10)
						+ 'Msg '+@ErrNo+', Level '+@ErrSeverity+', State '+@ErrState+', Line '++@ErrLine + CHAR(10)
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
			FETCH NEXT FROM Copier INTO @PhysicalName, @FileName, @Physical_Directory, @Destination
		END
	CLOSE Copier
	DEALLOCATE Copier	               

	PRINT ''
	EXEC sys.sp_configure @configname = 'cmdshell', -- varchar(35)
						  @configvalue = 0  -- int
	RECONFIGURE

	EXEC sys.sp_configure @configname = 'show advanced options', -- varchar(35)
						  @configvalue = 0						  -- int
	RECONFIGURE



END
GO

DECLARE @File_Table File_Table 
INSERT @File_Table
(
    [file or directory],
    Destination
)
VALUES
(   
	N'D:\1\d1\\\\\\', -- file or directory - nvarchar(2000)
    N'D:\2' -- Destination - nvarchar(2000)
),
(   
	N'D:\1\f1.docx', -- file or directory - nvarchar(2000)
    N'D:\2' -- Destination - nvarchar(2000)
)

EXEC dbo.sp_copy_files @File_Table = @File_Table,               -- File_Table
                       @move = 1,                        -- bit
                       @Replace_String_Replacement = '', -- sysname
                       @Replace_Pattern = ''             -- sysname

GO

DROP PROCEDURE dbo.sp_copy_files
GO
