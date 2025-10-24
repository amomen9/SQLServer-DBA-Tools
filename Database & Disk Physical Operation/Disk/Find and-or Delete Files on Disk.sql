/* Example 1: 

	Search for a directory in all disk drives except the 'C:\' drive and 
	delete its contents with WILDCARD *. The 'C:\' drive (or whatever your
	OS root drive is) is excluded because it contains thousands of OS and
	program files which heavily slow down the search operation. For this
	drive, a specific search is preferred.
*/

DECLARE @directory_full_path NVARCHAR(500),
		@wildcard_path NVARCHAR(500),
		@directory_to_find NVARCHAR(500)
SELECT @directory_full_path = fs.full_filesystem_path FROM 
(
	SELECT fixed_drive_path FROM sys.dm_os_enumerate_fixed_drives WHERE 
	drive_type = 3 AND
	LEN(REPLACE(fixed_drive_path,'C:',''))>=LEN(fixed_drive_path)	-- exclude the C: drive
) fd 
CROSS APPLY  sys.dm_os_enumerate_filesystem(fd.fixed_drive_path,'traces') fs
WHERE
fs.is_directory = 1

-- Optionally delete directory contents
SELECT @wildcard_path=@directory_full_path+'\*'
EXEC sys.xp_delete_files @directory_full_path

GO


DECLARE @directory_full_path NVARCHAR(500),
		@wildcard_path NVARCHAR(500),
		@directory_to_find NVARCHAR(500)
SELECT @directory_full_path = fs.full_filesystem_path FROM 
(
	SELECT fixed_drive_path FROM sys.dm_os_enumerate_fixed_drives WHERE 
	drive_type = 3 AND
	LEN(REPLACE(fixed_drive_path,'C:',''))>=LEN(fixed_drive_path)	-- exclude the C: drive
) fd 
CROSS APPLY  sys.dm_os_enumerate_filesystem(fd.fixed_drive_path,'*.sql') fs
WHERE fs.is_directory = 0

