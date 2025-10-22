"C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE" -Q "exec xp_create_subdir N'C:\Databases\Data\'; exec xp_create_subdir N'C:\Databases\Log\'; "


"C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE" -Q "RESTORE DATABASE [dbWarden] FROM  DISK = N'\\Server\C$\Users\a.momen\Desktop\ins\dbWarden_DB1_truncated_22.05.31.bak' WITH  FILE = 1, MOVE N'dbWarden' TO N'C:\Databases\Data\dbWarden.mdf', MOVE N'dbWardenAudit' TO N'C:\Databases\Data\dbWardenAudit.ndf', MOVE N'DbWardenArchive' TO N'C:\Databases\Data\DbWardenArchive.ndf', MOVE N'dbWardenErrorLog' TO N'C:\Databases\Data\dbWardenErrorLog.mdf', MOVE N'dbWardenPerfmon' TO N'C:\Databases\Data\dbWardenPerfmon.mdf', MOVE N'dbWardenWaitStatistic' TO N'C:\Databases\Data\dbWardenWaitStatistic.mdf', MOVE N'dbWarden_log' TO N'C:\Databases\Log\dbWarden_log.ldf', NOUNLOAD, STATS = 30"


"C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE" -i "\\Server\c$\Users\a.momen\Desktop\ins\dbWarden-Jobs.sql"