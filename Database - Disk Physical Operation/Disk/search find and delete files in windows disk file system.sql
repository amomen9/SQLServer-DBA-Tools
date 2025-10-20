------- Search/Delete Except C Drive------------------------------------------------------------
DECLARE @par NVARCHAR(500)

SELECT @par = fs.full_filesystem_path FROM 
(
	SELECT fixed_drive_path FROM sys.dm_os_enumerate_fixed_drives WHERE 
	drive_type = 3 AND
	LEN(REPLACE(fixed_drive_path,'C:'/*Exclude C Drive*/,''))>=LEN(fixed_drive_path)
) fd 
CROSS APPLY  sys.dm_os_enumerate_filesystem(fd.fixed_drive_path,N'2022FC2_192-Snapshot5.vmsn'/*Include asterisc wildcard if you need*/) fs
WHERE
fs.is_directory = 0
SELECT @par

--SELECT @par += '\*'; EXEC sys.xp_delete_files @par		/* Uncomment this to delete the results */
GO
-------------------------------------------------------------------
------- Search/Delete Only C Drive------------------------------------------------------------
DECLARE @par NVARCHAR(500)

SELECT @par = fs.full_filesystem_path+'\*' FROM 
(
	SELECT fixed_drive_path FROM sys.dm_os_enumerate_fixed_drives WHERE 
	drive_type = 3 AND
	fixed_drive_path = 'C:\'
) fd 
CROSS APPLY  sys.dm_os_enumerate_filesystem(fd.fixed_drive_path,N'2022FC2_192-Snapshot5.vmsn'/*Include asterisc wildcard if you need*/) fs
WHERE
fs.is_directory = 0
SELECT @par

--SELECT @par += '\*'; EXEC sys.xp_delete_files @par		/* Uncomment this to delete the results */
-------------------------------------------------------------------





-------- Simple search ---------------------------------------------------------
SELECT * FROM sys.dm_os_enumerate_filesystem('R:\','*') WHERE file_or_directory_name LIKE N'%TRACES%'
-------------------------------------------------------------------------------