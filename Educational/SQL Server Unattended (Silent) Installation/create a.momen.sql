IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'A.Momen')
                  BEGIN
CREATE LOGIN [A.Momen] WITH PASSWORD = 0x02007A1DDF9137B419A4216F57C91CB65622FCE357F2108C50F93BA8DC040287A335CC16AA213D6F0F018DE45EE65B56D68193039F669CE3724FFFC7860ECF51F0178E002E4C HASHED, SID = 0x43E7090B8133FB43ABEBC8FC4BCE2197, DEFAULT_DATABASE = [master], DEFAULT_LANGUAGE = [us_english], CHECK_POLICY = ON, CHECK_EXPIRATION = ON

          EXEC master.dbo.sp_addsrvrolemember @loginame='A.Momen', @rolename='sysadmin'
END
GO

alter server role sysadmin add member [a.momen]
GO