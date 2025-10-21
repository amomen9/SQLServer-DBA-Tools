-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2023-01-03"
-- Description:         "equalize Logins password & SID on all servers"
-- License:             "Please refer to the license file"
-- =============================================



SELECT LOGINPROPERTY('n.shavandi','PasswordHash'), SUSER_SID('n.shavandi'),SUSER_SID('dsfsdfsdfdsff')


SELECT * FROM sys.dm_exec_sessions WHERE original_login_name = 'n.shavandi'

DECLARE @sql NVARCHAR(MAX)
IF (SELECT LOGINPROPERTY('n.shavandi','PasswordHash')) IS NOT NULL
BEGIN
	BEGIN TRY
		BEGIN TRAN
			SET @sql =
				'DROP LOGIN [n.shavandi]'
			EXEC (@sql)
			SET @sql =
				'CREATE LOGIN [N.Shavandi] WITH PASSWORD = 0x0200517824D6E51D6ED8F24EA6BBE4BD07F6AA66EA87F040FCE48877435134B2B5ED2141959183F2BF321FA0195EE4A34C01BA1C9889F59E2D6C785F02F45B9A51D5C15F09B3 HASHED, SID=0x688F7E904D835445BA93FA5EDAEC881C, CHECK_POLICY=OFF, CHECK_EXPIRATION=OFF'
			EXEC (@sql)
		COMMIT
	END TRY
	BEGIN CATCH
		PRINT ERROR_MESSAGE()
		ROLLBACK TRAN
	END CATCH
END

ALTER USER [n.shavandi] WITH LOGIN = [n.shavandi]
--CREATE 

--IF (SELECT @@SERVERNAME)
--IN
--(
--N'TestDB2,2828',
--N'BI-DB,2828',
--N'Cando-Beta-DB1,2828',
--N'Karboard-DB2,2828',
--N'Cando-DB1,2828',
--N'Archive-DB1,2828',
--N'ML-Lab-DB,2828',
--N'DB1,2828',
--N'Log-DB,2828',
--N'DB3,2828',
--N'Search-DB1,2828',
--N'DB5,2828',
--N'CANDO-DB2,2828',
--N'Search-DB2,2828',
--N'DB4,2828',
--N'Test-DB3,2828',
--N'SISS,2828',
--N'BI,2828',
--N'Monitoring-DB,2828',
--N'Karboard-DB1,2828',
--N'TestDBA-DB1,2828',
--N'DB2,2828'
--)
