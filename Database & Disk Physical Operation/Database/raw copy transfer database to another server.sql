-- ==============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2022.05.12>
-- Latest Update Date:	<2022.08.19>
-- Description:			<Move Databases' Datafiles>
-- ==============================================



--USE SQLAdministrationDB
--GO



CREATE OR ALTER PROC sp_PrintLong
@String NVARCHAR(MAX)
AS
BEGIN
	DECLARE @NewLineLocation INT,
			@TempStr NVARCHAR(4000)

	WHILE @String <> ''
	BEGIN
		SET @TempStr = SUBSTRING(@String,1,4000)
		SELECT @NewLineLocation = CHARINDEX(CHAR(13),REVERSE(@TempStr))
		SET @TempStr = LEFT(@TempStr,(4000-@NewLineLocation))

		PRINT @TempStr

		SET @String = RIGHT(@String,(LEN(@String)-LEN(@TempStr)))
	END
END
GO


CREATE OR ALTER PROCEDURE sp_MoveDatabases_Datafiles	
	
	@DatabasesToBeMoved sysname = '',
	@New_Datafile_Directory NVARCHAR(300) = 'D:\Database Data', 													
	@New_Logfile_Directory NVARCHAR(300) =  'E:\Database Log',
	@Replace_String_Replacement sysname = '',
	@Replace_Pattern sysname = '',
	@Take_a_Raw_Backup BIT = 0
	

AS
BEGIN
	SET NOCOUNT ON
	DECLARE @DBName sysname
	DECLARE @SQL VARCHAR(max)
	DECLARE @Offline_Database NVARCHAR(1000)
	DECLARE @New_Datafile_Directory_In_Loop NVARCHAR(300),
			@New_Logfile_Directory_In_Loop NVARCHAR(300)
	DECLARE @message NVARCHAR(2000)

	SET @DatabasesToBeMoved = TRIM(ISNULL(@DatabasesToBeMoved,''))
	SET @Replace_String_Replacement = TRIM(ISNULL(@Replace_String_Replacement,''))
	SET @Replace_Pattern = TRIM(ISNULL(@Replace_Pattern,''))
	SET @Take_a_Raw_Backup = ISNULL(@Take_a_Raw_Backup,0)

	SET @New_Datafile_Directory = TRIM(ISNULL(@New_Datafile_Directory,''))
	SET @New_Logfile_Directory = TRIM(ISNULL(@New_Logfile_Directory,''))
	IF @New_Datafile_Directory = '' AND @New_Logfile_Directory = '' AND @Replace_Pattern = '' AND @Replace_String_Replacement = ''	RAISERROR('@New_Datafile_Directory and @New_Logfile_Directory are both undefined.',16,1)

	IF RIGHT(@New_Datafile_Directory,1)<>'\' AND @New_Datafile_Directory<>''
		SET @New_Datafile_Directory+='\'
	IF RIGHT(@New_Logfile_Directory,1)<>'\' AND @New_Logfile_Directory<>''
		SET @New_Logfile_Directory+='\'

	IF @New_Datafile_Directory<>''
		EXEC sys.xp_create_subdir @New_Datafile_Directory
	IF @New_Logfile_Directory<>''
		EXEC sys.xp_create_subdir @New_Logfile_Directory


	EXEC sys.sp_configure @configname = 'show advanced options', -- varchar(35)
						  @configvalue = 1  -- int
	RECONFIGURE
	EXEC sys.sp_configure @configname = 'cmdshell', -- varchar(35)
						  @configvalue = 1  -- int
	RECONFIGURE
	PRINT ''

	-- Temp table for keeping the outputs of CMDSHELL command execution for lator diagnostics and reporting purposes.
	CREATE TABLE #tmp (id INT IDENTITY PRIMARY KEY NOT NULL, [output] NVARCHAR(500)) 

	-- Temp table for user specified database names
	SELECT TRIM(value) dbname INTO #dbnames FROM STRING_SPLIT(@DatabasesToBeMoved,',')
	
	IF NOT EXISTS
		(
		SELECT 1 
		FROM sys.databases d JOIN  #dbnames dbnames
				ON d.name LIKE CASE WHEN @DatabasesToBeMoved = '' THEN '%' ELSE dbnames.dbname END
				AND database_id > CASE WHEN @DatabasesToBeMoved = '' THEN 4 ELSE 1 END
				
				AND state IN (0,1,2,3,5,6)
				AND d.user_access = 0 
		WHERE sys.fn_hadr_is_primary_replica(name) IS NULL
		)
	BEGIN 
		SET @message = 'No Database was found with your given criteria that is not a member of an Availability Group.'+
						CHAR(10)+ 'Note: To move/copy datafiles of databases which are members of an AG, you must first remove them from AG.'
		RAISERROR(@message,16,1)
	END
	DECLARE LoopThroughDatabases CURSOR FOR
		SELECT name 
		FROM sys.databases d JOIN  #dbnames dbnames
				ON d.name LIKE CASE WHEN @DatabasesToBeMoved = '' THEN '%' ELSE dbnames.dbname END
				AND database_id > CASE WHEN @DatabasesToBeMoved = '' THEN 4 ELSE 1 END
				
				AND state IN (0,1,2,3,5,6)
				AND d.user_access = 0 
		WHERE sys.fn_hadr_is_primary_replica(name) IS NULL
--DATABASE states:
--0 = ONLINE
--1 = RESTORING
--2 = RECOVERING 1
--3 = RECOVERY_PENDING 1
--4 = SUSPECT
--5 = EMERGENCY 1
--6 = OFFLINE 1
--7 = COPYING 2
--10 = OFFLINE_SECONDARY 2

-- In order to move databases, they have to be first set offline. This is not possible for databases which are in 'restoring' state,
-- consequently, 'restoring' databases will not be processed.
				
	OPEN LoopThroughDatabases
		FETCH NEXT FROM LoopThroughDatabases INTO @DBName
		WHILE @@FETCH_STATUS = 0
		BEGIN			
			
			--SELECT @DBName [Database Name]
			DECLARE @DBPrint NVARCHAR(256) = 'Begining '+IIF(@Take_a_Raw_Backup=0,'movement','a raw copy')+' of Database: ' + @DBName
			PRINT('-----------------------------------------------------------------------------------------------------------')
			PRINT @DBPrint			
			PRINT('')

			IF @New_Datafile_Directory = ''
				SELECT @New_Datafile_Directory_In_Loop = LEFT(physical_name,(LEN(physical_name)-CHARINDEX('\',REVERSE(physical_name))+1)) FROM sys.master_files WHERE database_id = DB_ID(@DBName) AND file_id = 1 
			ELSE
				SELECT @New_Datafile_Directory_In_Loop = @New_Datafile_Directory
			IF @New_Logfile_Directory = ''
				SELECT @New_Logfile_Directory_In_Loop = LEFT(physical_name,(LEN(physical_name)-CHARINDEX('\',REVERSE(physical_name))+1)) FROM sys.master_files WHERE database_id = DB_ID(@DBName) AND file_id = 2 
			ELSE
				SELECT @New_Logfile_Directory_In_Loop = @New_Logfile_Directory

			BEGIN TRY		
				IF (SELECT state FROM sys.databases WHERE database_id = DB_ID(@DBName)) IN (0,5)
				BEGIN

					IF NOT EXISTS (		SELECT 1 FROM
										(
											SELECT
												CASE type
														WHEN 1 THEN
															@New_Logfile_Directory_In_Loop+RIGHT(physical_name, CHARINDEX('\',REVERSE(physical_name))-1)
														ELSE
															@New_Datafile_Directory_In_Loop+RIGHT(physical_name, CHARINDEX('\',REVERSE(physical_name))-1)
												END [Target Path]
											FROM sys.master_files
											WHERE database_id = DB_ID(@DBName)
											EXCEPT
											SELECT 
												physical_name 
											FROM sys.master_files
											WHERE database_id = DB_ID(@DBName)
										) dt
								  )
					BEGIN
						FETCH NEXT FROM LoopThroughDatabases INTO @DBName
						PRINT 'No Datafile movement for the database '+QUOTENAME(@DBName)+' is required.'
						CONTINUE
                    END
					IF @DBName <> 'TempDB'
					BEGIN
						SET @sql =
						'
							USE '+QUOTENAME(@DBName)+'
							
							ALTER DATABASE '+QUOTENAME(@DBName)+' SET SINGLE_USER WITH ROLLBACK IMMEDIATE
							EXEC sys.sp_flush_log
							CHECKPOINT
							ALTER DATABASE '+QUOTENAME(@DBName)+' SET MULTI_USER
							USE master 
						'
						EXEC (@SQL)
								
						SET @SQL =
						'							
							ALTER DATABASE '+QUOTENAME(@DBName)+' SET OFFLINE
						'
						EXEC (@SQL)
					END
				END
                
				SET @sql =
				'
					DECLARE @PhysicalName nvarchar(260)
					DECLARE @ErrMessage VARCHAR(700)
					DECLARE @FileName NVARCHAR(255)
					DECLARE @FileLogicalName NVARCHAR(255)
					DECLARE @NewPath NVARCHAR(500)
					DECLARE @FileRelocate NVARCHAR(max)					
					DECLARE @CMDSHELL_Command1 varchar(1000),
							@CMDSHELL_Command2 varchar(1000)
					DECLARE @Error_Line int
					DECLARE @Error_Message NVARCHAR(300)
					DECLARE @Physical_Directory NVARCHAR(500)

					DECLARE MoveDatafiles CURSOR FOR 
						SELECT
							mf.name FileLogicalName,
							mf.physical_name,
							right(physical_name,charindex(''\'',reverse(physical_name))-1) FileName,
							left(physical_name,LEN(mf.physical_name)-CHARINDEX(''\'',reverse(physical_name))+1) physical_directory

						FROM 
						sys.master_files mf JOIN sys.databases d
						ON d.database_id = mf.database_id
						WHERE d.name=''' + @DBName + ''' AND file_id<>2
					OPEN MoveDatafiles
						FETCH NEXT FROM MoveDatafiles INTO @FileLogicalName, @PhysicalName, @FileName, @Physical_Directory
						WHILE @@FETCH_STATUS = 0
						BEGIN
							IF (@Physical_Directory = '''+@New_Datafile_Directory_In_Loop+''')
							BEGIN
								FETCH NEXT FROM MoveDatafiles INTO @FileLogicalName, @PhysicalName, @FileName, @Physical_Directory
								CONTINUE            
							END
							
							BEGIN TRY
								SET @NewPath = '''+@New_Datafile_Directory_In_Loop+''' + @FileName
							'
							IF @DBName <> 'TempDB'
								SET @SQL +=
								'
									TRUNCATE TABLE #tmp

									IF (SELECT file_is_a_directory FROM sys.dm_os_file_exists(@PhysicalName)) <> 1
									BEGIN
										SET @CMDSHELL_Command1 = ''ROBOCOPY "'' + @Physical_Directory + '' " "'' + '''+@New_Datafile_Directory_In_Loop+''' + '' " "'' + @FileName + ''" /J /COPY:DATSOU '+IIF(@Take_a_Raw_Backup=0,''+IIF(@Take_a_Raw_Backup=0,'/MOV','')+'','')+' /MT:8 /R:3 /W:1 /UNILOG+:ROBOout.log /TEE /UNICODE''										
										insert #tmp
										exec xp_cmdshell @CMDSHELL_Command1
										IF ('''+@Replace_Pattern+'''<>'''' or '''+@Replace_String_Replacement+'''<>'''')
										BEGIN
											SET @CMDSHELL_Command2 = ''CD '' + ''"'' + '''+@New_Datafile_Directory_In_Loop+''' + ''"'' + '' && REN '' + @FileName + '' '' + (''' + @Replace_Pattern + ''' + @FileName + ''' + @Replace_String_Replacement + ''') 
										END
									END
									ELSE
									BEGIN
										EXEC xp_create_subdir @NewPath
										SET @CMDSHELL_Command1 = ''ROBOCOPY '+IIF(@Take_a_Raw_Backup=0,'/MOV','')+' /E /COMPRESS "''+@PhysicalName+''" "''+@NewPath+''"''
										insert #tmp
										exec xp_cmdshell @CMDSHELL_Command1										
									END
									--EXEC sys.xp_copy_files @PhysicalName, @NewPath
									print @CMDSHELL_Command1
									
									SELECT @Error_Line = id from #tmp where [output] like ''%ERROR%''
									SELECT @Error_Message = (select string_agg([output],char(10)) from #tmp where id between @Error_Line and (@Error_Line+1))
									if @Error_Line is not null
									BEGIN
										declare @Warning_Message nvarchar(300) = ''Warning!!! Copy process failed:''+char(10)+@Error_Message
										print @Warning_Message
									END
									--ELSE
									--	EXEC xp_delete_files @PhysicalName
								'
								--PRINT @SQL
					SET @SQL +=
					'
								SET @FileRelocate =
								''
									ALTER DATABASE ''+QUOTENAME('''+@DBName+''')+''
									MODIFY FILE (NAME='' + QUOTENAME(@FileLogicalName) + '',
									FILENAME = '''''' + @NewPath + '''''')
								''
					'
					IF @DBName <> 'TempDB'
						SET @SQL +=
						'
									IF '+CONVERT(CHAR(1),@Take_a_Raw_Backup)+'=0
										IF (select file_exists+file_is_a_directory from sys.dm_os_file_exists(@NewPath)) = 1 
											EXEC (@FileRelocate)
										else
											raiserror(''Something has went wrong in the file movement process. The relocation in the system catalogs will not be applied.'',16,1)
						'
					ELSE
						SET @SQL +=
						'									
									EXEC (@FileRelocate)									
						'
					SET @SQL +=
					'
							END TRY
							BEGIN CATCH
								SET @ErrMessage = ''Something went wrong trying to '+IIF(@Take_a_Raw_Backup=0,'move','copy')+' datafile "''+@PhysicalName+''". The operation will not continue. System Error Message:''+CHAR(10)+
								ERROR_MESSAGE()
								RAISERROR(@ErrMessage,16,1)
								RETURN
							END CATCH
							--BEGIN TRY
							--	EXEC sys.xp_delete_files @PhysicalName			
							--END TRY
							--BEGIN CATCH
							--	set @ErrMessage = ''Warning, deleting the source datafile "''+@PhysicalName+''" failed. The process will continue anyway. System Error Message:
							--	''+ ERROR_MESSAGE()
							--	PRINT @ErrMessage			
							--END CATCH
        
							FETCH NEXT FROM MoveDatafiles INTO @FileLogicalName, @PhysicalName, @FileName, @Physical_Directory
						END
					CLOSE MoveDatafiles
					DEALLOCATE MoveDatafiles
					'
					IF @New_Datafile_Directory_In_Loop <> ''
						EXEC (@SQL)

					--------- Move Log Files: ---------
					SET @SQL =
					'
					DECLARE @PhysicalName nvarchar(260)
					DECLARE @ErrMessage VARCHAR(700)
					DECLARE @FileName NVARCHAR(255)
					DECLARE @FileLogicalName NVARCHAR(255)
					DECLARE @NewPath NVARCHAR(500)
					DECLARE @FileRelocate NVARCHAR(max)
					DECLARE @CMDSHELL_Command1 varchar(1000),
							@CMDSHELL_Command2 varchar(1000)
					DECLARE @Error_Line int
					DECLARE @Error_Message NVARCHAR(300)
					DECLARE @Physical_Directory NVARCHAR(500)

					DECLARE MoveLogfiles CURSOR FOR 
						SELECT 
							mf.name FileLogicalName,
							mf.physical_name,
							right(physical_name,charindex(''\'',reverse(physical_name))-1) FileName,
							left(physical_name,LEN(mf.physical_name)-CHARINDEX(''\'',reverse(physical_name))+1) physical_directory

						FROM 
						sys.master_files mf JOIN sys.databases d
						ON d.database_id = mf.database_id
						WHERE d.name='''+@DBName+''' AND file_id=2
					OPEN MoveLogfiles
						FETCH NEXT FROM MoveLogfiles INTO @FileLogicalName, @PhysicalName, @FileName, @Physical_Directory
						WHILE @@FETCH_STATUS = 0
						BEGIN
							IF (@Physical_Directory = '''+@New_Logfile_Directory_In_Loop+''')
							BEGIN
								FETCH NEXT FROM MoveLogfiles INTO @FileLogicalName, @PhysicalName, @FileName, @Physical_Directory
								CONTINUE            
							END
							BEGIN TRY
								SET @NewPath = '''+@New_Logfile_Directory_In_Loop+''' + @FileName
					'
					IF @DBName <> 'TempDB'
						SET @SQL +=
						'
									TRUNCATE TABLE #tmp
								
									SET @CMDSHELL_Command1 = ''ROBOCOPY "'' + @Physical_Directory + '' " "'' + '''+@New_Logfile_Directory_In_Loop+''' + '' " "'' + @FileName + ''" /J /COPY:DATSOU '+IIF(@Take_a_Raw_Backup=0,'/MOV','')+' /MT:8 /R:3 /W:1 /UNILOG+:ROBOout.log /TEE /UNICODE''
									print @CMDSHELL_Command1
									--EXEC sys.xp_copy_files @PhysicalName, @NewPath
									insert #tmp
									exec xp_cmdshell @CMDSHELL_Command1
									SELECT @Error_Line = id from #tmp where [output] like ''%ERROR%''
									SELECT @Error_Message = (select string_agg([output],char(10)) from #tmp where id between @Error_Line and (@Error_Line+1))--(select [output] from #tmp where id=(@Error_Line+1))
									
									if @Error_Line is not null
									BEGIN
										declare @Warning_Message nvarchar(300) = ''Warning!!! Copy process failed:''+char(10)+@Error_Message
										print @Warning_Message
									END
						'
					SET @SQL +=
					'
								SET @FileRelocate =
								''
									ALTER DATABASE ''+QUOTENAME('''+@DBName+''')+''
									MODIFY FILE (NAME='' + QUOTENAME(@FileLogicalName) + '',
									FILENAME = '''''' + @NewPath + '''''')
								''
					'
					IF @DBName <> 'TempDB'
						SET @SQL +=
						'
									IF '+CONVERT(CHAR(1),@Take_a_Raw_Backup)+' = 0
										IF (select file_exists from sys.dm_os_file_exists(@NewPath)) = 1 
											EXEC (@FileRelocate)
										else
											raiserror(''Something has went wrong in the file movement process. The relocation in the system catalogs will not be applied.'',16,1)
						'
					ELSE
						SET @SQL +=
						'									
									EXEC (@FileRelocate)									
						'
					SET @SQL +=
					'
							END TRY
							BEGIN CATCH
								SET @ErrMessage = ''Something went wrong trying to '+IIF(@Take_a_Raw_Backup=0,'move','copy')+' datafile "''+@PhysicalName+''". The operation will not continue. System Error Message:''+CHAR(10)+
								ERROR_MESSAGE()
								RAISERROR(@ErrMessage,16,1)
								RETURN
							END CATCH
							--BEGIN try	
							--	EXEC sys.xp_delete_files @PhysicalName			
							--END TRY
							--BEGIN CATCH
							--	set @ErrMessage = ''Warning, deleting the source Log file "''+@PhysicalName+''" failed. The process will continue anyway. System Error Message:
							--	''+ ERROR_MESSAGE()
							--	PRINT @ErrMessage			
							--END CATCH
        
							FETCH NEXT FROM MoveLogfiles INTO @FileLogicalName, @PhysicalName, @FileName, @Physical_Directory
						END
					CLOSE MoveLogfiles
					DEALLOCATE MoveLogfiles
				'
				IF @New_Logfile_Directory_In_Loop <> ''
					EXEC (@SQL)
			
				IF @DBName <> 'TempDB'
				begin
					SET @SQL =
					'
						ALTER DATABASE '+QUOTENAME(@DBName)+' SET ONLINE
					'
					EXEC (@SQL)
					PRINT ''
					SET @DBPrint = 'End database '+IIF(@Take_a_Raw_Backup=0,'movement','files copy')+', if you see no errors, the database has been successfully brought back ONLINE again.'+IIF(@Take_a_Raw_Backup=0,'',' You can now attach these files to a SQL Server instance.')
				
				END
				ELSE
				BEGIN
					PRINT ''
					SET @DBPrint = 'TempDB datafiles have been moved inside system catalog. To put this cold feature of SQL Server into effect, a service restart is required.'
				END
				PRINT @DBPrint
				
			end	TRY
			BEGIN CATCH
				DECLARE @PRINT_or_RAISERROR INT = 2			-- 1 for print 2 for RAISERROR
				DECLARE @ErrMsg NVARCHAR(500) = ERROR_MESSAGE()
				DECLARE @ErrLine NVARCHAR(500) = ERROR_LINE()
				DECLARE @ErrNo nvarchar(6) = CONVERT(NVARCHAR(6),ERROR_NUMBER())
				DECLARE @ErrState nvarchar(2) = CONVERT(NVARCHAR(2),ERROR_STATE())
				DECLARE @ErrSeverity nvarchar(2) = CONVERT(NVARCHAR(2),ERROR_SEVERITY())
				DECLARE @UDErrMsg nvarchar(MAX) = 'Something went wrong during the operation. Depending on your preference the operation will fail or continue, skipping this database.'+CHAR(10)+'System error message:'+CHAR(10)
						+ 'Msg '+@ErrNo+', Level '+@ErrSeverity+', State '+@ErrState+', Line '++@ErrLine + CHAR(10)
						+ @ErrMsg
				IF @PRINT_or_RAISERROR = 1
				begin
					PRINT @UDErrMsg					
				end
				ELSE
				BEGIN					
					RAISERROR(@UDErrMsg,16,1)
				END

			END CATCH
			FETCH NEXT FROM LoopThroughDatabases INTO @DBName
		END
		
	CLOSE LoopThroughDatabases
	DEALLOCATE LoopThroughDatabases
	
	
	PRINT('-----------------------------------------------------------------------------------------------------------'+CHAR(10))

	EXEC sys.sp_configure @configname = 'cmdshell', -- varchar(35)
						  @configvalue = 0  -- int
	RECONFIGURE

	EXEC sys.sp_configure @configname = 'show advanced options', -- varchar(35)
						  @configvalue = 0						  -- int
	RECONFIGURE

				
END
GO

DECLARE @SQL NVARCHAR(max)
-------
DECLARE @DBName_Raw sysname = 'jobvision'
DECLARE @DBName sysname = 'co-'+@DBName_Raw+'DB'
PRINT @DBName
-------
SET @SQL =
'
ALTER AVAILABILITY GROUP [AG-CandoDB]
REMOVE DATABASE '+QUOTENAME(@DBName)+';
'
EXEC (@sql)
--SET @SQL =	
--'
--WHILE (SELECT state from sys.databases where name = '''+@DBName+''')<>1
--	WAITFOR DELAY ''00:00:01''' + CHAR(10) +
--			'RESTORE DATABASE '+QUOTENAME(@DBName) + ' WITH RECOVERY' + CHAR(10) +
--			'ALTER DATABASE '+QUOTENAME(@DBName) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE' + CHAR(10) +
--			'DROP DATABASE '+QUOTENAME(@DBName)
--EXEC (@SQL) AT [CANDO-DB2,2828]



EXEC dbo.sp_MoveDatabases_Datafiles 
			@DatabasesToBeMoved		= @DBName,						-- enter database's name, including wildcard character %. Leaving this empty or null means all databases except some certain databases. This script can only work for tempdb in system databases. 
			@New_Datafile_Directory = '\\Cando-Beta-DB1\D$\Database Data',						-- nvarchar(300), if left empty, data files will not be moved
            @New_Logfile_Directory	= '\\Cando-Beta-DB1\E$\Database Log',		-- nvarchar(300), if left empty, log files will not be moved
			@Replace_Pattern	= '',							-- pattern to find inside database files physical names. After this pattern was found, it will be replaced with @Replace_String_Replacement
			@Replace_String_Replacement	= '',					-- this will replace @Replace_Pattern in the database file names to rename them.
			@Take_a_Raw_Backup = 1								-- when set to 1, the database files will be copied (not moved) to the target, but their location will not change in the system catalog for the database


SET @SQL = 
'
	use master
	ALTER AVAILABILITY GROUP [AG-CandoDB]
	ADD DATABASE '+QUOTENAME(@DBName)+';
'
EXEC (@SQL)


GO

DROP PROC dbo.sp_PrintLong
GO
DROP PROC dbo.sp_MoveDatabases_Datafiles
GO



