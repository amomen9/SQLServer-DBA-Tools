-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2025-09-22"
-- Description:         "simple instance & databases (all) login memberships"
-- License:             "Please refer to the license file"
-- =============================================



-- Drop temporary table if it exists
DROP TABLE IF EXISTS #temp;

-- Create temporary table to store user and role information with sufficient column sizes
CREATE TABLE #temp (
    id INT IDENTITY PRIMARY KEY NOT NULL,
    DBName sysname,
    [Server Login Name] sysname NULL,
    [Database User Name] sysname NULL,
    [User Scope] NVARCHAR(60) NULL,
    [User Database Role Membership] NVARCHAR(MAX) NULL, -- Increased size to NVARCHAR(MAX)
    [Server Role(s)] NVARCHAR(MAX) NULL, -- Increased size to NVARCHAR(MAX)
    isDisabled BIT NOT NULL
);

-- Declare variable to hold dynamic SQL
DECLARE @sql NVARCHAR(MAX);

-- Construct the dynamic SQL query
SET @sql = '
SELECT 
    DBName,
    [Server Login Name],
    [Database User Name],
    [User Scope],
    STRING_AGG([User Database Role Membership], '', '') AS [User Database Role Membership],
    STRING_AGG([Server Role(s)], '', '') AS [Server Role(s)],
    isDisabled
FROM (
    SELECT DISTINCT
        DBName,
        [Server Login Name],
        [Database User Name],
        [User Scope],
        [User Database Role Membership],
        [Server Role(s)],
        isDisabled
    FROM (
        SELECT 
            db_name() AS DBName,
            sp.name AS [Server Login Name],
            IIF(dp.name IS NULL AND ISNULL(p2.name, '''') = ''sysadmin'', ''dbo'', ISNULL(dp.name, ''__No Database Access__'')) AS [Database User Name],
            ISNULL(dp.authentication_type_desc, ''INSTANCE'') AS [User Scope],
            dp2.name AS [User Database Role Membership],
            p2.name AS [Server Role(s)],
            CASE 
                WHEN sp.is_disabled IS NOT NULL THEN sp.is_disabled 
                ELSE IIF(dper.state IN (''G'', ''W''), 0, 1) 
            END AS isDisabled
        FROM sys.server_principals sp
        FULL JOIN sys.database_principals dp ON sp.sid = dp.sid
        LEFT JOIN sys.database_role_members rm ON dp.principal_id = rm.member_principal_id
        LEFT JOIN sys.database_principals dp2 ON rm.role_principal_id = dp2.principal_id
        LEFT JOIN sys.server_role_members m ON sp.principal_id = m.member_principal_id
        LEFT JOIN sys.server_principals p2 ON m.role_principal_id = p2.principal_id
        LEFT JOIN sys.database_permissions dper ON dper.grantee_principal_id = dp.principal_id
        WHERE ISNULL(sp.principal_id, 0) <> 1 
        AND ISNULL(dp.principal_id, 16383) BETWEEN 5 AND 16383
    ) dt
) dt2
GROUP BY 
    DBName,
    [Server Login Name],
    [Database User Name],
    [User Scope],
    isDisabled
';

-- Wrap the dynamic SQL to execute for each database except those starting with '%pattern%'
SET @sql = '
USE [?];
IF ''?'' IN (SELECT name FROM sys.databases WHERE name NOT LIKE ''%pattern%'')
BEGIN
' + @sql + '
END
';

-- Insert results into the temporary table
INSERT INTO #temp
EXEC sp_msforeachdb @sql;

-- Select and display the results
SELECT 
    DBName,
    [Server Login Name],
    [Database User Name],
    [User Scope],
    [User Database Role Membership],
    [Server Role(s)],
    isDisabled
FROM #temp
ORDER BY DBName, [Database User Name];