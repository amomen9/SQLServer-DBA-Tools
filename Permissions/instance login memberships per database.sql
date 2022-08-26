



DROP TABLE IF EXISTS #temp
CREATE TABLE #temp 
(
id INT IDENTITY PRIMARY KEY NOT NULL,
DBName sysname,
[Server Login Name] sysname null,
[Database User Name] sysname null,
[User Scope] NVARCHAR(60) null,
[User Database Role Membership] sysname null,
[Server Role(s)] sysname NULL,
isDisabled BIT NOT NULL
)
DECLARE @sql NVARCHAR(MAX)
SET @sql=
'
select 
		DBName,
		[Server Login Name],
		[Database User Name],
		[User Scope],
		STRING_AGG([User Database Role Membership],'', ''),
		STRING_AGG([Server Role(s)],'', ''),
		isDisabled
FROM
(
	SELECT  DISTINCT
			DBName,
			[Server Login Name],
			[Database User Name],
			[User Scope],
			[User Database Role Membership],
			[Server Role(s)],
			isDisabled  
	FROM
	(
	SELECT 
	--dp.principal_id,
	db_name() [DBName],
	sp.name AS [Server Login Name],
	IIF(dp.name IS NULL AND ISNULL(p2.name,'''') = ''sysadmin'',''dbo'', ISNULL(dp.name,''__No Database Access__'')) [Database User Name],
	ISNULL(dp.authentication_type_desc,''INSTANCE'') [User Scope], 
	dp2.name [User Database Role Membership],
	p2.name [Server Role(s)],
	CASE WHEN sp.is_disabled IS NOT NULL THEN sp.is_disabled ELSE IIF(dper.state IN (''G'',''W''), 0, 1) END isDisabled

	FROM sys.server_principals sp FULL JOIN sys.database_principals dp 
			ON sp.sid=dp.sid
			LEFT JOIN sys.database_role_members rm
			ON dp.principal_id = rm.member_principal_id
			LEFT JOIN sys.database_principals dp2
			ON rm.role_principal_id=dp2.principal_id

			LEFT JOIN sys.server_role_members m 
			ON sp.principal_id = m.member_principal_id 
			LEFT JOIN sys.server_principals p2 
			ON m.role_principal_id = p2.principal_id

			LEFT JOIN sys.database_permissions dper
			ON dper.grantee_principal_id=dp.principal_id

	WHERE   --ISNULL(sp.type,''S'')=''S'' AND 
			--ISNULL(sp.is_disabled,0) = 0 AND 
			ISNULL(sp.principal_id,0)<>1 AND 
			ISNULL(dp.principal_id,16383) BETWEEN 5 and 16383

	) dt
) dt2
group by	
			[DBName],
			[Server Login Name],
			[Database User Name],
			[User Scope],
			
			isDisabled 

'
--PRINT @sql
SET @sql='use [?]
if ''?'' in (select name from sys.databases where name not like ''co-%db'')
begin
--select ''?'' [Server Login Name], NULL [Database User Name], NULL [User Scope], NULL [User Database Role Membership], NULL [Server Role(s)]

' + @sql +
'
end
'

INSERT #temp
EXEC sp_msforeachdb @sql

SELECT  
		DBName,
        [Server Login Name],
        [Database User Name],
        [User Scope],
        [User Database Role Membership],
        [Server Role(s)],
        isDisabled 
FROM #temp
--WHERE [Server Login Name] = 'a.heidari'
--AND [Database User Name] = 'a.heidari'
ORDER BY DBName, [Database User Name]
