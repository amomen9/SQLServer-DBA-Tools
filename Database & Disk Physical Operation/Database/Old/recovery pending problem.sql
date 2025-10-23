-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2024-04-06"
-- Description:         "recovery pending problem"
-- License:             "Please refer to the license file"
-- =============================================



SELECT DB_NAME(mf.database_id) DBName, mf.type_desc, name logical_file_name, mf.physical_name [physical_name_sys_cat], fe.file_exists FROM sys.master_files mf CROSS APPLY
sys.dm_os_file_exists(mf.physical_name) fe
WHERE fe.file_exists = 0
















