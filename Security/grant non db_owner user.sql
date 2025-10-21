CREATE LOGIN [Mofid\Man.Asgari] FROM WINDOWS
CREATE LOGIN [Mofid\F.Nazari]	FROM WINDOWS
CREATE LOGIN tadbir WITH PASSWORD = N'987321@bB'

 
USE hive_Image_Stage4
GO

CREATE USER [mofid\ma.heidari]  FOR LOGIN [mofid\ma.heidari] 
CREATE USER [MA.Heidari]	FOR LOGIN [MA.Heidari]
DROP USER tadbir

DROP USER [mofid\ma.heidari] [MA.Heidari]


IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE type_desc='DATABASE_ROLE' AND name = 'db_strong')
	CREATE ROLE [db_strong]
ALTER ROLE 		db_datareader 			ADD MEMBER db_strong
ALTER ROLE 		db_datawriter 			ADD MEMBER db_strong
ALTER ROLE 		db_ddladmin 			ADD MEMBER db_strong
ALTER ROLE 		db_securityadmin 		ADD MEMBER db_strong
GRANT 			SHOWPLAN 				TO db_strong
GRANT 			EXECUTE 				TO db_strong
GRANT 			VIEW DATABASE STATE 	TO db_strong
GRANT 			VIEW DEFINITION 		TO db_strong
GRANT 			REFERENCES 				TO db_strong

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE type_desc='DATABASE_ROLE' AND name = 'db_prod')
	CREATE ROLE [db_prod]
ALTER ROLE 	db_datareader 			ADD MEMBER db_prod
GRANT 		VIEW DATABASE STATE 	TO db_prod
GRANT 		VIEW DEFINITION 		TO db_prod



ALTER ROLE db_strong ADD MEMBER [MA.Heidari] 
ALTER ROLE db_strong ADD MEMBER [mofid\ma.heidari]


ALTER USER tadbir WITH LOGIN = tadbir




WAITFOR DELAY '00:00:00.001'