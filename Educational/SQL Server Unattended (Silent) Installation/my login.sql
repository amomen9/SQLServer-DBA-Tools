-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2022-08-26"
-- Description:         "my login"
-- License:             "Please refer to the license file"
-- =============================================



IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'A.Momen')
                  BEGIN
CREATE LOGIN [A.Momen] WITH PASSWORD = 'P@$$WD', SID = 0x43E7090B8133AAAAAAAAA8FC4BCE2197, DEFAULT_DATABASE = [master], DEFAULT_LANGUAGE = [us_english], CHECK_POLICY = ON, CHECK_EXPIRATION = ON

          EXEC master.dbo.sp_addsrvrolemember @loginame='A.Momen', @rolename='sysadmin'
END