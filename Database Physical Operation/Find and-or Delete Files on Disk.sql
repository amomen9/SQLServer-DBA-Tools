DECLARE @par NVARCHAR(500)

SELECT @par = fs.full_filesystem_path+'\*' FROM 
(
	SELECT fixed_drive_path FROM sys.dm_os_enumerate_fixed_drives WHERE 
	drive_type = 3 AND
	LEN(REPLACE(fixed_drive_path,'C:',''))>=LEN(fixed_drive_path)	-- exclude the C: drive
) fd 
CROSS APPLY  sys.dm_os_enumerate_filesystem(fd.fixed_drive_path,'traces') fs
WHERE
fs.is_directory = 1

EXEC sys.xp_delete_files @par


SELECT fs.full_filesystem_path+'\*' FROM 
(
	SELECT fixed_drive_path FROM sys.dm_os_enumerate_fixed_drives WHERE 
	drive_type = 3 AND
	LEN(REPLACE(fixed_drive_path,'C:',''))>=LEN(fixed_drive_path)	-- exclude the C: drive
) fd 
CROSS APPLY  sys.dm_os_enumerate_filesystem(fd.fixed_drive_path,'traces') fs
WHERE
fs.is_directory = 1


SELECT * FROM sys.dm_os_enumerate_filesystem('R:\','*') WHERE file_or_directory_name LIKE '%TRACES%'




SELECT fs.full_filesystem_path+'\*' FROM 
(
	SELECT fixed_drive_path FROM sys.dm_os_enumerate_fixed_drives WHERE 
	drive_type = 3 AND
	LEN(REPLACE(fixed_drive_path,'C:',''))>=LEN(fixed_drive_path)	-- exclude the C: drive
) fd 
CROSS APPLY  sys.dm_os_enumerate_filesystem(fd.fixed_drive_path,'traces') fs

SELECT file_or_directory_name,full_filesystem_path 
FROM sys.dm_os_enumerate_filesystem('C:\Users\Ali\Dropbox\Mofid\Scripts\git Mofid\a.momen PostgreSQL\postgresql\pgpool\4.5.2 Ubuntu 22.04','*') 
WHERE 
	file_or_directory_name LIKE '%.sh%'
	--OR file_or_directory_name LIKE '%%'

SELECT file_or_directory_name,full_filesystem_path 
FROM sys.dm_os_enumerate_filesystem('G:\.shortcut-targets-by-id\1KSCfZIBPbSRzxDcjbA20_co_GaN1AfpC\Ali Momen','*') 
WHERE 
	file_or_directory_name LIKE '%birth%'
