-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2022-01-25"
-- Description:         "sp_delete_backup_history"
-- License:             "Please refer to the license file"
-- =============================================



USE master
GO

CREATE OR ALTER PROC sp_delete_backupset
	@backup_set_id INT,
	@backup_type VARCHAR(15),
	@database_name sysname,
	@is_copy_only bit,
	@Backup_FinishDate_start DATETIME,
	@backup_FinishDate_End DATETIME
AS
BEGIN

	SELECT * FROM msdb.dbo.backupset

	DELETE FROM msdb.dbo.backupfilegroup
	WHERE backup_set_id = 2031

	DELETE FROM msdb.dbo.backupfile
	WHERE backup_set_id = 2031

	DELETE FROM msdb.dbo.restorefile
	WHERE restore_history_id in (SELECT restore_history_id FROM msdb.dbo.restorehistory WHERE backup_set_id=2031)

	DELETE FROM msdb.dbo.restorefilegroup
	WHERE restore_history_id in (SELECT restore_history_id FROM msdb.dbo.restorehistory WHERE backup_set_id=2031)

	DELETE FROM msdb.dbo.restorehistory
	WHERE backup_set_id = 2031


	DELETE FROM msdb..backupset
	WHERE backup_set_id = 2031
END