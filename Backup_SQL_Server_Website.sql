
-- =============================================
-- Author:		<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:		<2021.03.11>
-- Description:		<Backup Website>
-- =============================================

/*

This script performs a full backup of the database and home folder files of the intended website. It can be turned into a
scheduled job to run at specific schedules. The DB backup file name will be in DBName_Date_Time + .bak format.
The home folder backup has a similar name. A checkdb will also be performed prior to the database backup. 

System requirements:
SQL Server Compatibility: This script is designed to comply with SQL Server 2008 R2 and later. Earlier versions are not tested.
This script utilizes 7zip version 19.0, so install 7-zip first, which is an open source and multiplatform compression software.
Sample 7zip commands
	for compression:
	7z a -tzip -mx9 -mmt4 -y -bd -ssw -stl  -p1234 "D:\Website Backup\21.03.10_0500\DBNAME_File Backup_21.03.10_0500.zip" "C:\inetpub\wwwroot\*"
	for extraction:
	7z x -aoa -spe -p1234 -o"C:\inetpub\wwwroot" "D:\Website Backup\21.03.10_0500\DBNAME_File Backup_21.03.10_0500.zip"
For information regarding 7zip commands and switches please refer to 7zip's manual.

This script also checks for the modification of Database's data files on SQL Server 2016 and later. If the modification is less than 60 pages,
no backup is performed. This number is experimental. To backup regardless, simply set threshold to 0. There will be
only one output file for database backup. For security reasons, the script enables the extended stored procedure xp_cmdshell
and disables it again immediately once the procedure is finished executing. Using website files' archive password is
recommended and this script does not offer an option not to set a password.

Attention: 
	1. This script does not backup home folder on Non-Windows host operating systems, as xp_cmdshell is only
	available on windows by SQL Server 2019
	2. Please do not put anything else inside the backup directory manually or automatically, as it may interfere with
	restore script's functionality and completely wreck the operation.
	3. As leaving xp_cmdshell enabled has security risks, especially for the backup jobs which are meant to be scheduled
	to be triggered at special times, and compressing or decompressing files is time-consuming, this script does not wait for
	the compression or extraction process to complete and then disable xp_cmdshell. It launches a parallel script implicitly
	to disable xp_cmdshell immidiately after it starts. In other words, xp_cmdshell only remains enabled for a very short
	time. It was less than 0.3 second on my computer.

For the restore operation, please use Restore_Website.sql script.

*/

use AdventureWorks2019	-- Choose your database here.
go


--------------- Customizable Variables:
Declare @Files_Backup bit = 1								-- Backs up the files if and only if it is set to 1
Declare @Database_Backup bit = 1							-- Backs up the database if and only if it is set to 1
Declare @Backup_Threshould int = 0							-- Change this number in accordance with your preference. This option of this script
															-- can be used only on SQL Server 2016 and later though.
Declare @Backup_root nvarchar(120) = N'D:\Website Backup'
Declare @Website_root nvarchar(120) = N'C:\inetpub\wwwroot' -- Default for Microsoft IIS home folder
Declare @7zip_install_location nvarchar(500) = N'C:\Program Files\7-zip\'
Declare @Archive_File_Password nvarchar(15) = N'1234'		-- Use only characters and numbers
Declare @Temp_Working_Directory nvarchar(100) = N'C:\Temp'	-- Make sure SQL Service has permission to create this folder


--------------- Other Variables: !!!! Warning: Please do not modify these variables !!!!
Declare @Back_DateandTime nvarchar(20) = replace(convert(date, GetDate()),'-','.') + '_' + substring(replace(convert(nvarchar(10),convert(time, GetDate())), ':', ''),1,4) 
Declare @DB_Back_Name nvarchar(50) = DB_Name()+'_Backup_'+@Back_DateandTime
Declare @DB_Backup_Script nvarchar(500)
Declare @DB_Modified_Degree int = -1
Declare @Back_Path nvarchar(150) = @Backup_root + '\' + DB_NAME() + '_' + @Back_DateandTime
Declare @CommandtoExecute nvarchar(1000)
Declare @File_Backup_Name nvarchar(100) = DB_Name()+'_File Backup_'+@Back_DateandTime+'.zip'
Declare @CheckDB_Statement nvarchar(100) = N'DBCC CHECKDB ('''+DB_NAME()+N''') with no_infomsgs'
Declare @DirTree Table (subdirectory nvarchar(255), depth int, [file] int)


-- Begin Body:

SET NOCOUNT ON

Declare @DB_Modiefied_Degree_SQL nvarchar(100) = 'select sum(modified_extent_page_count) from sys.dm_db_file_space_usage'
IF cast(cast(SERVERPROPERTY('ProductVersion') as char(2)) as float) > 13 -- Equal to or greater than 2016
BEGIN
	if (OBJECT_ID('tempdb..#Temp') is not null)
		drop table #Temp
	create table #Temp (sum_modified_extent_page_count int)
	insert #Temp
	EXEC(@DB_Modiefied_Degree_SQL)
	select @DB_Modified_Degree = sum_modified_extent_page_count from #Temp
END ELSE
	set @DB_Modiefied_Degree_SQL = NULL
	


EXEC (@CheckDB_Statement)
print ('End CheckDB')

IF ((@Files_Backup = 0 and @Database_Backup = 0))
	RAISERROR('You have chosen not to backup anything!!!!',16,1)


IF((@DB_Modified_Degree>=@Backup_Threshould or @DB_Modified_Degree = -1) and (@Files_Backup != 0 or @Database_Backup != 0))
BEGIN

	
	EXEC master.sys.xp_create_subdir @Backup_root
	EXEC master.sys.xp_create_subdir @Back_Path
	
	----------------------------------------------- Backing up Database:
	
	IF( @Database_Backup = 1 )
	BEGIN

		set @DB_Backup_Script = REPLACE('BACKUP DATABASE ['+DB_NAME()+'] TO  DISK = N''' +@Back_Path+'\'+@DB_Back_Name+'.bak'' WITH  NOFORMAT, INIT,  NAME = N'''+DB_NAME()+' - Database Backup_' + @Back_DateandTime + ''', SKIP, NOREWIND, NOUNLOAD, COMPRESSION, CHECKSUM, CONTINUE_AFTER_ERROR',
				'_Backup_', '_Full Backup_') 	
		EXEC (@DB_Backup_Script)
		print('End Database Backup') 

	END


	----------------------------------------------- Backing up Files:
	
	/* 
		The if condition checks if the SQL Server host is windows, for on Linux xp_cmdshell is not available. To check the host's os
		you can use "select host_platform from sys.dm_os_host_info) = 'Windows'" statement but sys.dm_os_host_info is incompatible with
		SQL Server 2016 and earlier. To support these versions I used the global variable @@version instead.
	*/
	Declare @Linux_Position int
	SELECT @Linux_Position = CHARINDEX('Linux', @@VERSION)
	IF (@Linux_Position != 0 and @Files_Backup = 1)
		raiserror('You cannot backup website files on Linux host!', 16, 1)
	ELSE
		IF(@Files_Backup = 1)
		BEGIN
		
		insert into @DirTree
			EXEC xp_dirtree @7zip_install_location, 1, 1		
		if ((select count(*) from @DirTree) = 0)
		BEGIN
			declare @message nvarchar(150) = '7-zip is either not installed to ' + @7zip_install_location + ' or SQL Server service does not have permission to this folder'
			raiserror(@message, 16, 1)
		END ELSE
		BEGIN
			
			print(SYSDATETIME())

			-- To allow advanced options to be changed.  
			EXECUTE sp_configure 'show advanced options', 1;  
  
			-- To update the currently configured value for advanced options.  
			RECONFIGURE;  
  
			-- To enable the feature.  
			EXECUTE sp_configure 'xp_cmdshell', 1;  

			-- To update the currently configured value for this feature.  
			RECONFIGURE;  
	
			set @CommandtoExecute = 'sqlcmd -Q "/* To disable the feature.  */ EXECUTE sp_configure ''xp_cmdshell'', 0; /* To update the currently configured value for this feature.  */ RECONFIGURE; /* To deny advanced options to be changed.  */ EXECUTE sp_configure ''show advanced options'', 0; /* To update the currently configured value for advanced options.  */ RECONFIGURE; print(SYSDATETIME())" -o C:\Temp\MyOutput.txt & "' + @7zip_install_location + N'7z" a -tzip -mx9 -mmt4 -y -bd -ssw -stl  -p' + @Archive_File_Password +' "' + @Back_Path + '\' + @File_Backup_Name + '" "' + @Website_root + '\*"'
	
			print ('Begin file backup')
			
			EXECUTE xp_create_subdir @Temp_Working_Directory /* This directory keeps the log of disabling xp_cmdshell and
			'show advanced options' in the form of "MyOutput.txt".
			*/

			if OBJECT_ID('tempdb..#temp3') is not null
				drop table #temp3
	
			

			create table #temp3 (output nvarchar(500))
			insert #temp3
			EXECUTE master..xp_cmdshell @CommandtoExecute

			----------------- Alter #temp3 collation with the database's default collation to avoid collation mismatch in charindex function
			Declare @AlterTempCollation nvarchar(300) = 'ALTER TABLE #temp3 
				ALTER COLUMN [output] nvarchar(500) COLLATE ' + cast(DATABASEPROPERTYEX(DB_NAME(), 'Collation') as nvarchar(60))
			EXEC (@AlterTempCollation)
			-------------------------------------

			Declare @cmdshell_output nvarchar(max) = ''
			select @cmdshell_output = @cmdshell_output + isNULL([output],'') + char(10)
			from #temp3
			
			print(@cmdshell_output)			-- Attention! 'print' truncates strings bigger than 4000 nvarchar characters

			if(CHARINDEX(N'Everything is Ok', cast(@cmdshell_output AS nvarchar(max))) = 0)
			BEGIN
				declare @7zip_Error nvarchar(max) = 'Something went wrong trying to make the archive. More information on this error from 7-zip: ' + @cmdshell_output
				raiserror(@7zip_Error,16,1)
			END
			
			/*	The following configurations are already set by xp_cmdshell and they must not be executed again:

				-- To disable the feature.  
				EXECUTE sp_configure 'xp_cmdshell', 0;  
	  
				-- To update the currently configured value for this feature.  
				RECONFIGURE;  
	  
				-- To deny advanced options to be changed.  
				EXECUTE sp_configure 'show advanced options', 0;  
	  
				-- To update the currently configured value for advanced options.  
				RECONFIGURE; 
			*/
		END

	END
	
	  


	/*
	declare @backupSetId as int
	select @backupSetId = position from msdb..backupset where database_name=N'Northwind' and backup_set_id=(select max(backup_set_id) from msdb..backupset where database_name=N'Northwind' )
	if @backupSetId is null begin raiserror(N'Verify failed. Backup information for database ''Northwind'' not found.', 16, 1) end
	RESTORE VERIFYONLY FROM  DISK = N'F:\NorthwindDB_21.02.23_0406.dif' WITH  FILE = @backupSetId,  NOUNLOAD,  NOREWIND
	GO
	*/
 

END ELSE
	print ('Nothing backed up')

