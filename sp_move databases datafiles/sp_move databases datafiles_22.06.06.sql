-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2022.05.12>
-- Latest Update Date:	<2022.06.06>
-- Description:			<Move Databases' Datafiles>
-- License:				<Please refer to the license file>
-- =============================================



USE SQLAdministrationDB
GO
-- select * from sys.databases
CREATE OR ALTER PROC sp_PrintLong
@String NVARCHAR(MAX)
AS
BEGIN
  DECLARE @Substring nvarchar(4000)
  declare @RepeatTime int = (len(@String)/4000) + 1;
  declare @counter VARCHAR(3) = '0';
  while (@counter < @RepeatTime)
  BEGIN
	SET @Substring = substring(@String,((@counter*4000)+1),4000)
	SELECT @String string ,@Substring  substring, @counter counter, (@counter*4000)+1 stepbegin 
  	set @counter+=1
  END
END
GO

CREATE OR ALTER PROCEDURE sp_MoveDatabases_Datafiles	
	 @DatabasesToBeMoved sysname = '',
	 @New_Datafile_Directory NVARCHAR(300) = --'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA' 
													'D:\Database Data' 
													--'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA'
	,@New_Logfile_Directory NVARCHAR(300) =  --'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\LogLog' 
													'E:\Database Log' 
													--'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA'
AS
BEGIN
	SET NOCOUNT ON
	DECLARE @DBName sysname
	DECLARE @SQL VARCHAR(max)
	DECLARE @Offline_Database NVARCHAR(1000)
	SET @DatabasesToBeMoved = TRIM(ISNULL(@DatabasesToBeMoved,''))

	EXEC sys.xp_create_subdir @New_Datafile_Directory
	EXEC sys.xp_create_subdir @New_Logfile_Directory

	SET @New_Datafile_Directory = TRIM(@New_Datafile_Directory)
	SET @New_Logfile_Directory = TRIM(@New_Logfile_Directory)

	IF RIGHT(@New_Datafile_Directory,1)<>'\'
		SET @New_Datafile_Directory+='\'
	IF RIGHT(@New_Logfile_Directory,1)<>'\'
		SET @New_Logfile_Directory+='\'


	EXEC sys.sp_configure @configname = 'show advanced options', -- varchar(35)
						  @configvalue = 1  -- int
	RECONFIGURE
	EXEC sys.sp_configure @configname = 'cmdshell', -- varchar(35)
						  @configvalue = 1  -- int
	RECONFIGURE


	-- Temp table for keeping the outputs of CMDSHELL command execution for lator diagnostics and reporting purposes.
	CREATE table #tmp (id INT IDENTITY PRIMARY KEY NOT NULL, [output] NVARCHAR(500)) 

	-- Temp table for user specified database names
	SELECT TRIM(value) dbname INTO #dbnames FROM STRING_SPLIT(@DatabasesToBeMoved,',')
	


	DECLARE LoopThroughDatabases CURSOR FOR
		SELECT name 
		FROM sys.databases d JOIN  #dbnames dbnames
				ON d.name like CASE WHEN @DatabasesToBeMoved = '' then '%' else dbnames.dbname END
				AND database_id > CASE WHEN @DatabasesToBeMoved = '' then 4 else 1 END
				--AND (database_id > 4 OR database_id = IIF(@DatabasesToBeMoved='TempDB',2,5)) 
				AND state in (0,1,2,3,5,6)
				AND d.user_access = 0 --AND name <> 'dbWarden'
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
				
	OPEN LoopThroughDatabases
		FETCH NEXT FROM LoopThroughDatabases INTO @DBName
		WHILE @@FETCH_STATUS = 0
		BEGIN
			--IF (SELECT 1 FROM sys.master_files WHERE database_id=DB_ID(@DBName) AND type_desc='FILESTREAM') IS NOT NULL
			--BEGIN
			--	FETCH NEXT FROM LoopThroughDatabases INTO @DBName
			--	CONTINUE            
			--END
			
			SELECT @DBName [Database Name]
			DECLARE @DBPrint NVARCHAR(256) = 'Begining movement of Database: ' + @DBName
			print('-----------------------------------------------------------------------------------------------------------')
			PRINT @DBPrint			
			PRINT('')
		
			BEGIN try		
				IF (SELECT state FROM sys.databases WHERE database_id = DB_ID(@DBName)) IN (0,5)
				BEGIN
					IF NOT EXISTS (		SELECT 1 from
										(
											SELECT
												CASE type
														WHEN 1 then
															@New_Logfile_Directory+right(physical_name, CHARINDEX('\',REVERSE(physical_name))-1)
														ELSE
															@New_Datafile_Directory+right(physical_name, CHARINDEX('\',REVERSE(physical_name))-1)
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
					DECLARE @CMDSHELL_Command varchar(1000)
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
							IF (@Physical_Directory = '''+@New_Datafile_Directory+''')
							BEGIN
								FETCH NEXT FROM MoveDatafiles INTO @FileLogicalName, @PhysicalName, @FileName, @Physical_Directory
								CONTINUE            
							END
							
							BEGIN TRY
								SET @NewPath = '''+@New_Datafile_Directory+''' + @FileName
							'
							IF @DBName <> 'TempDB'
								SET @SQL +=
								'
									TRUNCATE TABLE #tmp
								
									SET @CMDSHELL_Command = ''ROBOCOPY "'' + @Physical_Directory + '' " "'' + '''+@New_Datafile_Directory+''' + '' " "'' + @FileName + ''" /J /COPY:DATSOU /MOV /MT:8 /R:3 /W:1 /UNILOG+:ROBOout.log /TEE /UNICODE''
									--EXEC sys.xp_copy_files @PhysicalName, @NewPath
									print @CMDSHELL_Command
									insert #tmp
									exec xp_cmdshell @CMDSHELL_Command
									SELECT @Error_Line = id from #tmp where [output] like ''%ERROR%''
									SELECT @Error_Message = (select string_agg([output],char(10)) from #tmp where id between @Error_Line and (@Error_Line+1))
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
								IF (select file_exists from sys.dm_os_file_exists(@NewPath)) = 1
									EXEC (@FileRelocate)
								else
									raiserror(''Something has went wrong in the file movement process. The relocation in the system catalogs will not be applied.'',16,1)

							END TRY
							BEGIN CATCH
								SET @ErrMessage = ''Something went wrong trying to copy/move datafile "''+@PhysicalName+''". The operation will not continue. System Error Message:
								''+ ERROR_MESSAGE()
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
					EXEC (@SQL)
					SET @SQL =
					'
					DECLARE @PhysicalName nvarchar(260)
					DECLARE @ErrMessage VARCHAR(700)
					DECLARE @FileName NVARCHAR(255)
					DECLARE @FileLogicalName NVARCHAR(255)
					DECLARE @NewPath NVARCHAR(500)
					DECLARE @FileRelocate NVARCHAR(max)
					DECLARE @CMDSHELL_Command varchar(1000)
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
							IF (@Physical_Directory = '''+@New_Logfile_Directory+''')
							BEGIN
								FETCH NEXT FROM MoveLogfiles INTO @FileLogicalName, @PhysicalName, @FileName, @Physical_Directory
								CONTINUE            
							END
							BEGIN TRY
								SET @NewPath = '''+@New_Logfile_Directory+''' + @FileName
					'
					IF @DBName <> 'TempDB'
						SET @SQL +=
						'
									TRUNCATE TABLE #tmp
								
									SET @CMDSHELL_Command = ''ROBOCOPY "'' + @Physical_Directory + '' " "'' + '''+@New_Logfile_Directory+''' + '' " "'' + @FileName + ''" /J /COPY:DATSOU /MOV /MT:8 /R:3 /W:1 /UNILOG+:ROBOout.log /TEE /UNICODE''
									--EXEC sys.xp_copy_files @PhysicalName, @NewPath
									insert #tmp
									exec xp_cmdshell @CMDSHELL_Command
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
								IF (select file_exists from sys.dm_os_file_exists(@NewPath)) = 1
									EXEC (@FileRelocate)
								else
									raiserror(''Something has went wrong in the file movement process. The relocation in the system catalogs will not be applied.'',16,1)
							END TRY
							BEGIN CATCH
								SET @ErrMessage = ''Something went wrong trying to copy/move datafile "''+@PhysicalName+''". The operation will not continue. System Error Message:
								''+ ERROR_MESSAGE()
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
				EXEC (@SQL)
			
				IF @DBName <> 'TempDB'
				begin
					SET @SQL =
					'
						ALTER DATABASE '+QUOTENAME(@DBName)+' SET ONLINE
					'
					EXEC (@SQL)
					PRINT ''
					SET @DBPrint = 'End database movement, if you see no errors, the database has been successfully brought back ONLINE.'
				
				END
				ELSE
				BEGIN
					PRINT ''
					SET @DBPrint = 'TempDB datafiles have been moved inside system catalog. To put this cold feature of SQL Server into effect, a service restart is required.'
				END
				PRINT @DBPrint
				PRINT ''
			end	TRY
			BEGIN CATCH
				DECLARE @PRINT_or_RAISERROR INT = 2			-- 1 for print 2 for RAISERROR
				DECLARE @ErrMsg NVARCHAR(500) = ERROR_MESSAGE()
				DECLARE @ErrLine NVARCHAR(500) = ERROR_LINE()
				DECLARE @ErrNo nvarchar(6) = CONVERT(NVARCHAR(6),ERROR_NUMBER())
				DECLARE @ErrState nvarchar(2) = CONVERT(NVARCHAR(2),ERROR_STATE())
				DECLARE @ErrSeverity nvarchar(2) = CONVERT(NVARCHAR(2),ERROR_SEVERITY())
				DECLARE @UDErrMsg nvarchar(MAX) = 'Something went wrong during the operation. Depending on your preference the operation will fail or continue, skipping this database.'+CHAR(10)+'System error message:'+CHAR(10)
						+ 'Msg '+@ErrSeverity+', Level '+@ErrSeverity+', State '+@ErrState+', Line '++@ErrLine + CHAR(10)
						+ @ErrMsg
				IF @PRINT_or_RAISERROR = 1
				begin
					PRINT @UDErrMsg
					--PRINT (CHAR(10))
					----PRINT '------------------------------------------------------------------------------------------------------------'
					--PRINT (CHAR(10))
				end
				ELSE
				BEGIN
					--PRINT (CHAR(10))
					----PRINT '------------------------------------------------------------------------------------------------------------'
					--PRINT (CHAR(10))
					RAISERROR(@UDErrMsg,16,1)
				END

			END CATCH
			FETCH NEXT FROM LoopThroughDatabases INTO @DBName
		END
		
	CLOSE LoopThroughDatabases
	DEALLOCATE LoopThroughDatabases
	
	EXEC sys.sp_configure @configname = 'cmdshell', -- varchar(35)
						  @configvalue = 0  -- int
	RECONFIGURE


	EXEC sys.sp_configure @configname = 'show advanced options', -- varchar(35)
						  @configvalue = 0
						  -- int
	RECONFIGURE



							--ALTER DATABASE Northwind SET online
													--ALTER DATABASE Northwind SET ONLINE


		--SELECT physical_database_name, name FROM sys.databases WHERE name <> physical_database_name

--SELECT name,is_name_reserved FROM sys.master_files WHERE name='Northwind'
END
GO


EXEC dbo.sp_MoveDatabases_Datafiles 
									@DatabasesToBeMoved = 'KarBoardMachineLearningLogDB, KarBoardMachineLearningDB',				-- enter database's name, including wildcard character %. Leaving this empty or null means all databases except some certain databases. This script can only work for tempdb in system databases. 
									@New_Datafile_Directory = 'D:\Database Data', -- nvarchar(300)
                                    @New_Logfile_Directory = 'E:\Database Log'    -- nvarchar(300)


GO

DROP PROC dbo.sp_PrintLong
GO
DROP PROC dbo.sp_MoveDatabases_Datafiles
GO





--SELECT d.name dbname,
--		mf.name filename,
--		mf.physical_name path,
--		right(mf.physical_name,charindex('\',reverse(mf.physical_name))-1) PhysicalFileName

--FROM sys.master_files mf JOIN sys.databases d
--ON d.database_id = mf.database_id
--WHERE d.database_id>4 AND d.name LIKE 'CandoMainDB'


--SELECT file_exists,* FROM sys.master_files
--CROSS APPLY
--sys.dm_os_file_exists(physical_name)
--WHERE database_id = DB_ID('8_dbWarden_8')

--DECLARE @FileRelocate NVARCHAR(max)
--SET @FileRelocate =
--		'
--			ALTER DATABASE '+QUOTENAME(''+'Northwind'+'')+'
--			MODIFY FILE (NAME=' + QUOTENAME('Northwind') + ',
--			FILENAME = ''' + 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA' + ''')
--		'
--PRINT @FileRelocate

--ALTER DATABASE [Northwind]
--			MODIFY FILE (NAME=[Northwind_log],
--			FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\Northwind_log.ldf')
--ALTER DATABASE Northwind SET ONLINE

--IF (SELECT state FROM sys.databases WHERE database_id = DB_ID('Northwind')) IN (0,5)
--	PRINT 'Good'
--ELSE
--	PRINT 'Not Good'

--SELECT right(PhysicalName, CHARINDEX('\',REVERSE(PhysicalName))-1) 
--from
--(
--SELECT physical_name PhysicalName FROM sys.master_files
--) dt