/********************** List of Permissions *******************************\
ALTER
ALTER ANY APPLICATION ROLE
ALTER ANY ASSEMBLY
ALTER ANY ASYMMETRIC KEY
ALTER ANY CERTIFICATE
ALTER ANY CONTRACT
ALTER ANY DATABASE AUDIT
ALTER ANY DATABASE DDL TRIGGER
ALTER ANY DATABASE EVENT NOTIFICATION
ALTER ANY DATASPACE
ALTER ANY EXTERNAL DATA SOURCE
ALTER ANY EXTERNAL FILE FORMAT
ALTER ANY FULLTEXT CATALOG
ALTER ANY MASK
ALTER ANY MESSAGE TYPE
ALTER ANY REMOTE SERVICE BINDING
ALTER ANY ROLE
ALTER ANY ROUTE
ALTER ANY SCHEMA
ALTER ANY SECURITY POLICY
ALTER ANY SENSITIVITY CLASSIFICATION
ALTER ANY SERVICE
ALTER ANY SYMMETRIC KEY
ALTER ANY USER
AUTHENTICATE
BACKUP DATABASE
BACKUP LOG
CHECKPOINT
CONNECT
CONNECT REPLICATION
CONTROL
CREATE AGGREGATE
CREATE ASSEMBLY
CREATE ASYMMETRIC KEY
CREATE CERTIFICATE
CREATE CONTRACT
CREATE DATABASE DDL EVENT NOTIFICATION
CREATE DEFAULT
CREATE FULLTEXT CATALOG
CREATE FUNCTION
CREATE MESSAGE TYPE
CREATE PROCEDURE
CREATE QUEUE
CREATE REMOTE SERVICE BINDING
CREATE ROLE
CREATE ROUTE
CREATE RULE
CREATE SCHEMA
CREATE SEQUENCE
CREATE SERVICE
CREATE SYMMETRIC KEY
CREATE SYNONYM
CREATE TABLE
CREATE TYPE
CREATE VIEW
CREATE XML SCHEMA COLLECTION
DELETE
EXECUTE
IMPERSONATE
INSERT
OWNER
REFERENCES
SELECT
SHOWPLAN
SUBSCRIBE QUERY NOTIFICATIONS
TAKE OWNERSHIP
UNMASK
UPDATE
VIEW ANY COLUMN ENCRYPTION KEY DEFINITION
VIEW ANY COLUMN MASTER KEY DEFINITION
VIEW ANY SENSITIVITY CLASSIFICATION
VIEW CHANGE TRACKING
VIEW DATABASE STATE
VIEW DEFINITION

------ Custom Permission Names by this script:
DATABASE OWNER
OWNER

\**************************************************************************/





USE master
GO


-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2023.02.26>
-- Latest Update Date:	<23.02.26>
-- Description:			<instance permissions>
-- License:				<Please refer to the license file> 
-- =============================================


DROP PROC IF EXISTS usp_PrintLong
GO

CREATE OR ALTER PROC usp_PrintLong
	@String NVARCHAR(MAX),
	@Max_Chunk_Size SMALLINT = 4000
AS
BEGIN
	SET NOCOUNT ON
	SET @Max_Chunk_Size = ISNULL(@Max_Chunk_Size,4000)
	IF @Max_Chunk_Size > 4000 OR @Max_Chunk_Size<50 BEGIN RAISERROR('Wrong @Max_Chunk_Size cannot be bigger than 4000. A value less than 50 for this parameter is also not supported.',16,1) RETURN 1 END
	DECLARE @NewLineLocation INT,
			@TempStr NVARCHAR(4000),
			@Length INT,
			@carriage BIT,
			@SeparatorNewLineFlag BIT,
			@Temp_Max_Chunk_Size INT

	CREATE TABLE #MinSeparator
	(
		id INT IDENTITY PRIMARY KEY NOT NULL,
		Separator VARCHAR(2),
		SeparatorReversePosition INT
	)

	WHILE @String <> ''
	BEGIN
		IF LEN(@String)<=@Max_Chunk_Size
		BEGIN 
			PRINT @String
			BREAK
		END 
		ELSE
        BEGIN
			SET @Temp_Max_Chunk_Size = @Max_Chunk_Size
			StartWithChunk:
			SET @TempStr = SUBSTRING(@String,1,@Temp_Max_Chunk_Size)
			SELECT @NewLineLocation = CHARINDEX(CHAR(10),REVERSE(@TempStr))
			DECLARE @MinSeparator INT

			TRUNCATE TABLE #MinSeparator
			INSERT #MinSeparator
			(
			    Separator,
			    SeparatorReversePosition
			)
			VALUES ('.', CHARINDEX('.',REVERSE(@TempStr))), (')', CHARINDEX(')',REVERSE(@TempStr))), ('(', CHARINDEX('(',REVERSE(@TempStr))), (',', CHARINDEX(',',REVERSE(@TempStr))), ('-', CHARINDEX('-',REVERSE(@TempStr))), ('*', CHARINDEX('*',REVERSE(@TempStr))), ('/', CHARINDEX('/',REVERSE(@TempStr))), ('+', CHARINDEX('+',REVERSE(@TempStr))), (CHAR(32), CHARINDEX(CHAR(32),REVERSE(@TempStr))), (CHAR(9), CHARINDEX(CHAR(9),REVERSE(@TempStr)))
			SELECT @MinSeparator = MIN(SeparatorReversePosition) FROM #MinSeparator WHERE SeparatorReversePosition<>0

			IF @NewLineLocation=0 AND @MinSeparator IS NOT NULL
			BEGIN
				SET @SeparatorNewLineFlag = 0				
				SET @NewLineLocation = @MinSeparator
			END
			ELSE
				IF @NewLineLocation<>0	SET @SeparatorNewLineFlag = 1
			
			IF @NewLineLocation = 0 OR @NewLineLocation=@Max_Chunk_Size BEGIN SET @Temp_Max_Chunk_Size+=50 GOTO StartWithChunk END

			IF CHARINDEX(CHAR(13),REVERSE(@TempStr)) - @NewLineLocation = 1
				SET @carriage = 1
			ELSE
				SET @carriage = 0

			SET @TempStr = LEFT(@TempStr,(@Temp_Max_Chunk_Size-@NewLineLocation)-CONVERT(INT,@carriage))

			PRINT @TempStr
		
			SET @Length = LEN(@String)-LEN(@TempStr)-CONVERT(INT,@carriage)-1+CONVERT(INT,~@SeparatorNewLineFlag)
			SET @String = RIGHT(@String,@Length)
			
		END 
	END
END
GO


-- Server-level Permissions -----------------------------------------------
CREATE OR ALTER PROC usp_permissions_for_instance
	@Login_Filter sysname = ''
AS
BEGIN

	SET NOCOUNT ON
	SET TRAN ISOLATION LEVEL READ UNCOMMITTED
	SELECT DISTINCT
		[LoginName],
		dt.class_desc,
		class_object_name,
		dt.permission_name,
		STRING_AGG(dt.Through,', ') Through,
		dt.state_desc,
		(SELECT STRING_AGG(sprsub.name,', ') FROM sys.server_role_members srmsub JOIN sys.server_principals sprsub ON srmsub.role_principal_id=sprsub.principal_id WHERE srmsub.member_principal_id=dt.principal_id) [Login Server Role Memberships],
		is_disabled
	INTO #1
	FROM 
	(
		SELECT 
			name [LoginName],
			sp.class_desc,
			NULL class_object_name,
			sp.permission_name,
			'Self' Through,
			sp.state_desc,
			principal_id,
			is_disabled	
		FROM sys.server_principals spr JOIN sys.server_permissions sp
		ON spr.principal_id = sp.grantee_principal_id
		UNION ALL

		SELECT SUSER_SNAME(ar.owner_sid),'AVAILABILITY REPLICA', ag.name availability_replica_name ,'OWNER', 'Self', 'OWNER', SUSER_ID(SUSER_SNAME(owner_sid)), (SELECT is_disabled FROM sys.server_principals where sid=ar.owner_sid) 
		FROM sys.availability_replicas ar
		RIGHT JOIN sys.availability_groups ag
		ON ag.group_id = ar.group_id
		WHERE ar.endpoint_url like '%'+@@SERVERNAME+'%' --AND owner_sid IS NOT NULL
		
		UNION ALL
		SELECT SUSER_SNAME(owner_sid),'DATABASE', name, 'OWNER', NULL, 'OWNER', SUSER_ID(SUSER_SNAME(owner_sid)), (SELECT is_disabled FROM sys.server_principals WHERE sid=ar.owner_sid)						FROM sys.databases ar WHERE owner_sid IS NOT NULL
		UNION ALL
		SELECT SUSER_NAME(principal_id),'ENDPOINT', name, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)								FROM sys.database_mirroring_endpoints ar WHERE principal_id IS NOT NULL
		UNION ALL
		SELECT SUSER_NAME(principal_id),'ASSEMBLY', name, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)								FROM master.sys.assemblies ar WHERE principal_id IS NOT NULL
		UNION ALL
		SELECT SUSER_NAME(principal_id),'ASYMMETRIC KEY', name, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)						FROM master.sys.asymmetric_keys ar WHERE principal_id IS NOT NULL
		UNION ALL
		SELECT SUSER_NAME(principal_id),'SYMMETRIC KEY', name, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)							FROM master.sys.symmetric_keys ar WHERE principal_id IS NOT NULL
		UNION ALL
		SELECT SUSER_NAME(principal_id),'CERTIFICATE', name, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)							FROM master.sys.certificates ar WHERE principal_id IS NOT NULL
		UNION ALL
		SELECT SUSER_NAME(principal_id),'FULLTEXT', name, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)								FROM master.sys.fulltext_catalogs ar WHERE principal_id IS NOT NULL
		UNION ALL
		SELECT SUSER_NAME(principal_id),'REMOTE SERVICE BINDING', name, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)				FROM master.sys.remote_service_bindings ar WHERE principal_id IS NOT NULL
		UNION ALL
		SELECT ar2.name,'SERVER ROLE', ar.name, 'OWNER', NULL, 'OWNER', ar.owning_principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)								FROM sys.server_principals ar JOIN sys.server_principals ar2 ON ar2.principal_id = ar.owning_principal_id WHERE ar.type_desc = 'SERVER_ROLE' AND ar.owning_principal_id IS NOT NULL
		UNION ALL
		SELECT SUSER_NAME(principal_id),'ROUTE', name, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)									FROM master.sys.routes ar WHERE principal_id IS NOT NULL
		UNION ALL
		SELECT SUSER_NAME(principal_id),'TYPE', name, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)									FROM master.sys.types ar WHERE principal_id IS NOT NULL
		UNION ALL
		SELECT SUSER_NAME(principal_id),'XML SCHEMA COLLECTION', name, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)					FROM master.sys.xml_schema_collections ar WHERE principal_id IS NOT NULL
		UNION ALL
		SELECT USER_NAME(principal_id),'SCHEMA', name, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)									FROM master.sys.schemas ar WHERE schema_id<>principal_id AND principal_id IS NOT NULL
		UNION ALL
		SELECT SUSER_NAME(principal_id),'MESSAGE TYPE', name COLLATE DATABASE_DEFAULT, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)	FROM master.sys.service_message_types ar WHERE principal_id IS NOT NULL
		UNION ALL
		SELECT SUSER_NAME(principal_id),'SERVICE', name COLLATE DATABASE_DEFAULT, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)		FROM master.sys.services ar WHERE principal_id IS NOT NULL
		UNION ALL
		SELECT SUSER_NAME(principal_id),'CONTRACT', name COLLATE DATABASE_DEFAULT, 'OWNER', NULL, 'OWNER', principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar.principal_id)		FROM master.sys.service_contracts ar WHERE principal_id IS NOT NULL
		UNION ALL
		SELECT TOP 10000000
			spr2.name [LoginName],
			spe.class_desc,
			NULL class_object_name,
			spe.permission_name,
			spr3.name Through,
			spe.state_desc,
			spr2.principal_id,
			spr2.is_disabled
		FROM sys.server_principals spr JOIN sys.server_permissions spe
		ON spr.principal_id = spe.grantee_principal_id
		JOIN sys.server_role_members srm ON
		srm.role_principal_id = spe.grantee_principal_id
		JOIN sys.server_principals spr2
		ON spr2.principal_id = srm.member_principal_id
		JOIN sys.server_principals spr3
		ON srm.role_principal_id = spr3.principal_id 
		ORDER BY LoginName,Through
	
	
	) dt
	GROUP BY dt.LoginName, dt.class_desc, dt.permission_name, dt.state_desc, dt.principal_id, dt.is_disabled, dt.class_object_name

	SELECT 
		#1.* 
	FROM #1		JOIN (SELECT TRIM(value) value FROM STRING_SPLIT(@Login_Filter,',')) dt1
	ON LoginName LIKE dt1.value { ESCAPE '\' }
	
END
GO

--EXEC dbo.usp_permissions_for_instance @Login_Filter = '%'    -- sysname 
GO




USE master
GO

-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2023.02.26>
-- Latest Update Date:	<23.02.26>
-- Description:			<Permissions per database>
-- License:				<Please refer to the license file> 
-- =============================================


-- login role, server role owner location in select statements, create revoke, include guest and dbo

--------  SP multiple Database Permissions -----------------------------------------------------------------------------------
CREATE OR ALTER PROC usp_permissions_for_every_database
	@Type_of_Principal NVARCHAR(4),
	@Principal_Filter_In sysname = '',
	@Database_Filter_In sysname = '',
	@Permission_Filter_In NVARCHAR(500) = '',
	@Permission_Filter_Out NVARCHAR(500) = '',
	@Permission_State_Filter CHAR(5) ='',	
	@Change_Ownership_Username sysname = 'dbo',
	@Show_Effective_Permissions BIT = 1,
	@Change_Permissions_Commands_Action NVARCHAR(6) = 'REVOKE',
	@Execute_Change_Permissions_Commands_Action BIT = 0
AS
BEGIN
	SET NOCOUNT ON
	SET TRAN ISOLATION LEVEL READ UNCOMMITTED
	SET @Principal_Filter_In = ISNULL(@Principal_Filter_In,'%')
	SET @Principal_Filter_In = IIF(@Principal_Filter_In = '','%',@Principal_Filter_In)
	SET @Database_Filter_In = ISNULL(@Database_Filter_In,'%')
	SET @Database_Filter_In = IIF(@Database_Filter_In = '','%',@Database_Filter_In)
	SET @Permission_Filter_In = ISNULL(@Permission_Filter_In,'%')
	SET @Permission_Filter_In = IIF(@Permission_Filter_In = '','%',@Permission_Filter_In)
	SET @Permission_Filter_Out = ISNULL(@Permission_Filter_Out,'ssssssss')
	IF  @Permission_Filter_Out = '' SET @Permission_Filter_Out = 'ssssssss'
	SET @Permission_Filter_Out = IIF(@Permission_Filter_Out = '','%',@Permission_Filter_Out)
	SET @Change_Ownership_Username = ISNULL(@Change_Ownership_Username,'')
	SET @Change_Permissions_Commands_Action = UPPER(@Change_Permissions_Commands_Action)
	SET @Change_Permissions_Commands_Action = ISNULL(@Change_Permissions_Commands_Action,'')
	SET @Execute_Change_Permissions_Commands_Action = ISNULL(@Execute_Change_Permissions_Commands_Action,0)
	SET @Type_of_Principal = ISNULL(@Type_of_Principal,'')
	IF @Type_of_Principal NOT IN ('','ROLE','USER') BEGIN RAISERROR('Invalide @Type_of_Principal specified.',16,1) RETURN 1 END
	--IF @Change_Permissions_Commands_Action NOT BETWEEN 0 AND 2				BEGIN RAISERROR('Invalide @Change_Permissions_Commands_Action specified.',16,1) RETURN 1 END
	IF @Change_Permissions_Commands_Action NOT IN ('','REVOKE','CREATE')		BEGIN RAISERROR('Invalide @Change_Permissions_Commands_Action specified.',16,1) RETURN 1 END
	
	SET @Permission_State_Filter = IIF(@Permission_State_Filter = '' OR @Permission_State_Filter IS NULL,'GRANT, DENY',@Permission_State_Filter)
	


	CREATE TABLE #2 ( [DatabaseName] nvarchar(128), [UserName] nvarchar(128), [class_desc] nvarchar(60), class_object_schema_name sysname NULL, [class_object_name] nvarchar(128), class_column_name sysname NULL, [permission_name] nvarchar(128), [Through] nvarchar(128), [state_desc] nvarchar(60), [User Database Role Memberships (Agg)] nvarchar(1000), [is_user_disabled] INT, [Server Login] sysname, is_login_disabled BIT NULL, [Server Role Memberships (Agg)] NVARCHAR(1000))

	SELECT name INTO #ExistingDatabasesNames FROM sys.databases WHERE state=0 AND source_database_id IS NULL
	
	DECLARE @CoName sysname
	DECLARE @sql NVARCHAR(MAX)	
	DECLARE @Stmt_head NVARCHAR(MAX)
	DECLARE @Stmt_master NVARCHAR(MAX) = ''
	DECLARE @Stmt_tail NVARCHAR(MAX)
	DECLARE @Revoke_Commands_Script NVARCHAR(MAX)
	SET @Stmt_head =	-- Permissions which are granted directly to the principal itself:
	'		
		SELECT DISTINCT
			  DB_NAME() DatabaseName
			, [UserName]
			, dt.class_desc
			, SCHEMA_NAME(schema_id) class_object_schema_name
			, class_object_name
			, ac.name class_column_name
			, dt.permission_name
			, dt.Through
			, dt.state_desc
			, (SELECT STRING_AGG(sprsub.name,'', '') FROM sys.database_role_members srmsub JOIN sys.database_principals sprsub ON srmsub.role_principal_id=sprsub.principal_id WHERE srmsub.member_principal_id=dt.principal_id) [User Database Role Memberships (Agg)]
			, IIF(EXISTS (SELECT 1 FROM sys.database_permissions dp JOIN sys.database_principals dpr ON dp.grantee_principal_id = dpr.principal_id AND dp.grantee_principal_id=dt.principal_id WHERE (dp.permission_name=''CONNECT'' AND dp.state_desc=''GRANT'') or dpr.type_desc=''DATABASE_ROLE''),0,1) [is_user_disabled]
			, ISNULL(dt.[Server Login],
						CASE (SELECT authentication_type_desc+'',''+type_desc FROM sys.database_principals WHERE principal_id=dt.principal_id) 
							WHEN ''INSTANCE,SQL_USER''				THEN ISNULL(SUSER_SNAME((SELECT sid FROM sys.database_principals WHERE principal_id=dt.principal_id)),''ORPHAN'')
							WHEN ''WINDOWS,WINDOWS_USER''			THEN ISNULL(SUSER_SNAME((SELECT sid FROM sys.database_principals WHERE principal_id=dt.principal_id)),''ORPHAN'')
							WHEN ''DATABASE,SQL_USER''				THEN ''DATABASE (Contained)''
							WHEN ''NONE,CERTIFICATE_MAPPED_USER''	THEN ISNULL(SUSER_SNAME((SELECT sid FROM sys.database_principals WHERE principal_id=dt.principal_id)),''ORPHAN'')
							WHEN ''NONE,SQL_USER''					THEN ISNULL(SUSER_SNAME((SELECT sid FROM sys.database_principals WHERE principal_id=dt.principal_id)),''ORPHAN'')
							ELSE ''NONE'' 
						END 
					) [Server Login]
			, ISNULL(is_login_disabled,(SELECT is_disabled FROM sys.server_principals WHERE sid = (SELECT sid FROM sys.database_principals where principal_id=dt.principal_id))) [is_login_disabled]
			, (SELECT STRING_AGG(spr.name,'', '') FROM sys.server_principals spr  JOIN sys.server_role_members srm ON srm.role_principal_id = spr.principal_id JOIN sys.server_principals spr2 ON spr2.principal_id = srm.member_principal_id WHERE spr2.sid=(SELECT sid FROM sys.database_principals WHERE principal_id=dt.principal_id)) [Server Role Memberships (Agg)]
		FROM 
		(
			SELECT 
					spr.name [UserName]
				, sp.class_desc
				, CASE class_desc 
						WHEN ''OBJECT_OR_COLUMN''	THEN OBJECT_NAME(major_id)
						WHEN ''SCHEMA''				THEN SCHEMA_NAME(major_id)
						WHEN ''TYPE''				THEN TYPE_NAME(major_id)
						WHEN ''DATABASE_PRINCIPAL'' THEN USER_NAME(major_id)
				  END class_object_name
				, sp.permission_name
				, ''Self'' Through
				, sp.state_desc
				, spr.principal_id
				, NULL [Server Login]
				, NULL is_login_disabled
				, ao.schema_id
				, sp.major_id
				, sp.minor_id
			FROM sys.database_principals spr JOIN sys.database_permissions sp
			ON spr.principal_id = sp.grantee_principal_id'+CASE @Type_of_Principal WHEN 'ROLE' THEN ' AND spr.type = ''R''' WHEN 'USER' THEN ' AND spr.type <> ''R''' ELSE '' END+/* Filter out type of principal, whether it's ROLE or USER. */'
			LEFT JOIN sys.all_objects ao
			ON ao.object_id = sp.major_id
			UNION ALL'+ IIF(@Type_of_Principal IN ('USER',''),		-- If @Type_of_Principal includes users, add the following "OWNER" queries
				'
				SELECT ''dbo'', ''DATABASE'', DB_NAME(), ''DATABASE OWNER'', ''Self'', ''DATABASE OWNER'', 1, SUSER_SNAME(owner_sid), (SELECT is_disabled FROM sys.server_principals where sid=dbs.owner_sid), NULL, NULL, NULL										FROM sys.databases dbs WHERE database_id=DB_ID()
				UNION ALL
				SELECT SUSER_NAME(principal_id),''ASSEMBLY'', name, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, NULL, NULL, NULL, NULL									FROM sys.assemblies ar WHERE principal_id IS NOT NULL
				UNION ALL
				SELECT SUSER_NAME(principal_id),''ASYMMETRIC KEY'', name, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, NULL, NULL, NULL, NULL								FROM sys.asymmetric_keys ar WHERE principal_id IS NOT NULL
				UNION ALL
				SELECT SUSER_NAME(principal_id),''SYMMETRIC KEY'', name, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, NULL, NULL, NULL, NULL								FROM sys.symmetric_keys ar WHERE principal_id IS NOT NULL
				UNION ALL
				SELECT SUSER_NAME(principal_id),''CERTIFICATE'', name, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, NULL, NULL, NULL, NULL									FROM sys.certificates ar WHERE principal_id IS NOT NULL
				UNION ALL
				SELECT SUSER_NAME(principal_id),''FULLTEXT'', name, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, NULL, NULL, NULL, NULL									FROM sys.fulltext_catalogs ar WHERE principal_id IS NOT NULL
				UNION ALL
				SELECT SUSER_NAME(principal_id),''REMOTE SERVICE BINDING'', name, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, NULL, NULL, NULL, NULL						FROM sys.remote_service_bindings ar WHERE principal_id IS NOT NULL
				UNION ALL
				SELECT SUSER_NAME(principal_id),''TYPE'', name, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, schema_id, NULL, NULL, NULL										FROM sys.types ar WHERE principal_id IS NOT NULL
				UNION ALL
				SELECT SUSER_NAME(principal_id),''XML SCHEMA COLLECTION'', name, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, schema_id, NULL, NULL, NULL						FROM sys.xml_schema_collections ar WHERE principal_id IS NOT NULL
				UNION ALL
				SELECT USER_NAME(principal_id),''SCHEMA'', name, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, NULL, NULL, NULL, NULL										FROM sys.schemas ar WHERE schema_id<>principal_id AND principal_id IS NOT NULL
				UNION ALL
				','')
	IF @Type_of_Principal IN ('','USER') -- If @Type_of_Principal includes users, add the following "OWNER" queries
		SET @Stmt_master = 
			'
			-- For master:
			SELECT SUSER_NAME(principal_id),''ROUTE'', name, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, NULL, NULL, NULL, NULL										FROM sys.routes ar WHERE principal_id IS NOT NULL
			UNION ALL
			SELECT SUSER_NAME(principal_id),''MESSAGE TYPE'', name COLLATE DATABASE_DEFAULT, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, NULL, NULL, NULL, NULL		FROM sys.service_message_types ar WHERE principal_id IS NOT NULL
			UNION ALL
			SELECT SUSER_NAME(principal_id),''SERVICE'', name COLLATE DATABASE_DEFAULT, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, NULL, NULL, NULL, NULL			FROM sys.services ar WHERE principal_id IS NOT NULL
			UNION ALL
			SELECT SUSER_NAME(principal_id),''CONTRACT'', name COLLATE DATABASE_DEFAULT, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, NULL, NULL, NULL, NULL			FROM sys.service_contracts ar WHERE principal_id IS NOT NULL

			UNION ALL
			SELECT SUSER_SNAME(ar.owner_sid),''AVAILABILITY REPLICA'', ag.name availability_replica_name ,''OWNER'', ''Self'', ''OWNER'', SUSER_ID(SUSER_SNAME(owner_sid)), SUSER_SNAME(owner_sid), (SELECT is_disabled FROM sys.server_principals where sid=ar.owner_sid), NULL, NULL, NULL  
			FROM sys.availability_replicas ar
			RIGHT JOIN sys.availability_groups ag
			ON ag.group_id = ar.group_id
			WHERE ar.endpoint_url like ''%''+@@SERVERNAME+''%'' --AND owner_sid IS NOT NULL
			
			UNION ALL
			SELECT SUSER_NAME(principal_id),''ENDPOINT'', name, ''OWNER'', ''Self'', ''OWNER'', principal_id, NULL, NULL, NULL, NULL, NULL									FROM sys.database_mirroring_endpoints ar WHERE principal_id IS NOT NULL
			UNION ALL
			SELECT ar2.name,''SERVER ROLE'', ar.name, ''OWNER'', ''Self'', ''OWNER'', ar.owning_principal_id, NULL, NULL, NULL, NULL, NULL									FROM sys.server_principals ar JOIN sys.server_principals ar2 ON ar2.principal_id = ar.owning_principal_id WHERE ar.type_desc = ''SERVER_ROLE'' AND ar.owning_principal_id IS NOT NULL
			UNION ALL
			'
	SET @Stmt_tail =	-- Permissions which are granted to a principal through its membership in a role:
			'
			SELECT 
					spr2.name [UserName]
				, spe.class_desc
				, CASE class_desc 
						WHEN ''OBJECT_OR_COLUMN''	THEN OBJECT_NAME(major_id)
						WHEN ''SCHEMA''				THEN SCHEMA_NAME(major_id)
						WHEN ''TYPE''				THEN TYPE_NAME(major_id)
						WHEN ''DATABASE_PRINCIPAL'' THEN USER_NAME(major_id)
				  END class_object_name
				, spe.permission_name
				, spr3.name Through
				, spe.state_desc
				, spr2.principal_id
				, NULL
				, NULL
				, ao.schema_id
				, spe.major_id
				, spe.minor_id
			FROM sys.database_principals spr JOIN sys.database_permissions spe
			ON spr.principal_id = spe.grantee_principal_id
			JOIN sys.database_role_members srm ON
			srm.role_principal_id = spe.grantee_principal_id
			JOIN sys.database_principals spr2
			ON spr2.principal_id = srm.member_principal_id'+CASE @Type_of_Principal WHEN 'ROLE' THEN ' AND spr2.type = ''R''' WHEN 'USER' THEN ' AND spr2.type <> ''R''' ELSE '' END+'
			JOIN sys.database_principals spr3
			ON srm.role_principal_id = spr3.principal_id
			LEFT JOIN sys.all_objects ao
			ON ao.object_id = spe.major_id
		) dt
		LEFT JOIN sys.all_columns ac
		ON ac.object_id = dt.major_id AND ac.column_id=dt.minor_id
		ORDER BY 1

	'
	-- Loop through databases and extract permissions:
	DECLARE CoFiller CURSOR FOR
		SELECT name FROM #ExistingDatabasesNames 
		JOIN (SELECT TRIM(value) value FROM STRING_SPLIT(@Database_Filter_In,',')) dt2
		ON name LIKE dt2.value { ESCAPE '\' }
	OPEN CoFiller
		FETCH NEXT FROM CoFiller INTO @CoName
		WHILE @@FETCH_STATUS = 0
		BEGIN
			BEGIN TRY

				DECLARE @CompanyDBName sysname = @CoName
				SET @sql =  'use '+
							QUOTENAME(@CompanyDBName)+CHAR(10)+
							@Stmt_head +
							IIF(@CompanyDBName = 'master',@Stmt_master,'') +
							@Stmt_tail
				
				INSERT INTO #2				
				EXEC (@sql)

			END TRY
			BEGIN CATCH
				DECLARE @Err_Msg NVARCHAR(2000) = ERROR_MESSAGE(),
						@Err_Severity INT = ERROR_SEVERITY(),
						@Err_State INT = ERROR_STATE()
				
				RAISERROR(@Err_Msg,@Err_Severity,@Err_State)
			END CATCH

			FETCH NEXT FROM CoFiller INTO @CoName    			
			
	
		END
	CLOSE CoFiller
	DEALLOCATE CoFiller
	--EXEC dbo.usp_PrintLong @String = @sql -- nvarchar(max)
	SET @sql =
	'
		SELECT 
			#2.DatabaseName, #2.UserName, #2.class_desc, #2.class_object_schema_name, #2.class_object_name, #2.class_column_name, #2.permission_name, '+IIF(@Show_Effective_Permissions = 1,'STRING_AGG(','')+'#2.Through'+IIF(@Show_Effective_Permissions = 1,','', '') ThroughAggregate','')+', '+IIF(@Show_Effective_Permissions = 1,'STRING_AGG(','')+'#2.state_desc'+IIF(@Show_Effective_Permissions = 1,','', '') StateAggregate','')+', #2.[User Database Role Memberships (Agg)], #2.[is_user_disabled], #2.[Server Login], #2.is_login_disabled, #2.[Server Role Memberships (Agg)]
		FROM #2		JOIN (SELECT TRIM(value) value FROM STRING_SPLIT(@Principal_Filter_In,'','')) dt1
		ON UserName LIKE dt1.value { ESCAPE ''\'' }
		JOIN (SELECT TRIM(value) value FROM STRING_SPLIT(@Permission_Filter_In,'','')) dt2
		ON permission_name LIKE dt2.value { ESCAPE ''\'' }
		LEFT JOIN (SELECT TRIM(value) value FROM STRING_SPLIT(@Permission_Filter_Out,'','')) dt3
		ON permission_name LIKE dt3.value { ESCAPE ''\'' }
		WHERE dt3.value IS NULL
					
	'+
	IIF(@Show_Effective_Permissions = 1,'	GROUP BY DatabaseName,UserName,class_desc,class_object_schema_name,class_object_name,class_column_name,permission_name,[User Database Role Memberships (Agg)],[is_user_disabled],[Server Login],is_login_disabled, [Server Role Memberships (Agg)]','')
	
	CREATE TABLE #temptable ( [DatabaseName] nvarchar(128), [UserName] nvarchar(128), [class_desc] nvarchar(60), class_object_schema_name sysname NULL, [class_object_name] nvarchar(128), class_column_name sysname NULL, [permission_name] nvarchar(128), [ThroughAggregate] nvarchar(4000), [StateAggregate] nvarchar(4000), [User Database Role Memberships (Agg)] nvarchar(4000), [is_user_disabled] int, [Server Login] nvarchar(128), [is_login_disabled] BIT,  [Server Role Memberships (Agg)] NVARCHAR(1000))
	
	
	INSERT #temptable
	EXEC sys.sp_executesql @sql,N'@Principal_Filter_In nvarchar(255), @Permission_Filter_In NVARCHAR(500), @Permission_Filter_Out NVARCHAR(500)', @Principal_Filter_In, @Permission_Filter_In, @Permission_Filter_Out
	
	SELECT * FROM #temptable --WHERE is_login_disabled IS NULL AND [Server Login] NOT IN ('ORPHAN','NONE')
	--where username in ('db_developer','db_seniordeveloper','db_executor','db_executer')
	
	IF @Change_Permissions_Commands_Action <> ''
	BEGIN
		SELECT @Revoke_Commands_Script =
			STRING_AGG('USE '+QUOTENAME(DatabaseName)+CHAR(10)+CHAR(10)+dt.permission_command,CHAR(10)+'-----------------------------------------------------------------------'+CHAR(10)+CHAR(10)+CHAR(10))
		FROM
		(
			SELECT
				DatabaseName,
				STRING_AGG(CONVERT(NVARCHAR(max),	
												CASE permission_name
													WHEN 'OWNER'			THEN	'ALTER AUTHORIZATION ON '+class_desc+'::'+QUOTENAME(class_object_name)+' TO '+IIF(@Change_Permissions_Commands_Action = 'CREATE', QUOTENAME([Server Login]), IIF(@Change_Ownership_Username='','[dbo]',QUOTENAME(@Change_Ownership_Username)))
													WHEN 'DATABASE OWNER'	THEN	'ALTER AUTHORIZATION ON DATABASE::'+QUOTENAME(class_object_name)+' TO '+IIF(@Change_Permissions_Commands_Action = 'CREATE', QUOTENAME([Server Login]), IIF(@Change_Ownership_Username='',QUOTENAME(SUSER_SNAME(0x01)),QUOTENAME(@Change_Ownership_Username)))
													ELSE							IIF(@Change_Permissions_Commands_Action='CREATE',TRIM(ss.value),'REVOKE')+' '+permission_name+	(
																													CASE class_desc 
																														WHEN 'DATABASE' THEN ' '+IIF(@Change_Permissions_Commands_Action='CREATE','TO','FROM')+' '+QUOTENAME(UserName)
																														WHEN 'OBJECT_OR_COLUMN' THEN ' ON '+QUOTENAME(class_object_schema_name)+'.'+QUOTENAME(class_object_name)+ISNULL('('+class_column_name+')','')+' '+IIF(@Change_Permissions_Commands_Action='CREATE','TO','FROM')+' '+QUOTENAME(UserName)
																														WHEN 'DATABASE_PRINCIPAL' THEN ' ON USER::'+QUOTENAME(class_object_name)+' '+IIF(@Change_Permissions_Commands_Action='CREATE','TO','FROM')+' '+QUOTENAME(UserName) 
																														ELSE ' ON '+class_desc+'::'+QUOTENAME(class_object_name)+' '+IIF(@Change_Permissions_Commands_Action='CREATE','TO','FROM')+' '+QUOTENAME(UserName) 
																													END
																												)
												END
								)
							, CHAR(10)
						  ) permission_command
		FROM #temptable CROSS APPLY STRING_SPLIT(StateAggregate,',') ss
		WHERE ThroughAggregate = 'Self'
		GROUP BY DatabaseName
		) dt

		EXEC dbo.usp_PrintLong @String = @Revoke_Commands_Script -- nvarchar(max)

		IF @Execute_Change_Permissions_Commands_Action = 1
			EXEC(@Change_Permissions_Commands_Action)

	END
	

END
GO
--CREATE TABLE #temptable ( [DatabaseName] nvarchar(128), [UserName] nvarchar(128), [class_desc] nvarchar(60), [class_object_name] nvarchar(128), [permission_name] nvarchar(128), [ThroughAggregate] nvarchar(4000), [StateAggregate] nvarchar(4000), [User Database Role Memberships] nvarchar(4000), [is_user_disabled] int, [Server Login] nvarchar(128), [is_login_disabled] bit )
--INSERT #temptable
EXEC dbo.usp_permissions_for_every_database @Type_of_Principal = 'user',							--	USER | ROLE. Empty yields both.
											@Principal_Filter_In ='%m.abeyat', 
																--'JvRole_DenySensitive%',							--'JvRole_ReadOnly, JvRole_RWE, JvRole_Alter, JvRole_DenySensitiveFields, %sensitive%',					-- Comma delimited list of database user names. Empty string or NULL yields 'all'. LIKE wildcards are allowed 
											
											@Database_Filter_In = '',					--'test_contained_permission_users',
																									-- Comma delimited list of Database Names in instance. Empty string or NULL yields 'all'. LIKE wildcards are allowed 
											@Permission_Filter_In = '',								-- Comma delimited list of Permission names. Empty string or NULL yields 'all'. LIKE wildcards are allowed 
											@Permission_Filter_Out = '',							--'SELECT, EXECUTE, VIEW%, SHOWPLAN, REFERENCES, CONNECT, AUTHENTICATE',
											@Permission_State_Filter = '',							-- Comma delimited list of Permission State. Empty string or NULL yields 'all'. Possible values: 'GRANT' | 'DENY'
											@Show_Effective_Permissions = 1,						-- Groups by permission states, so that you can figure out if a permission is indeed overally denied or granted.
											@Change_Ownership_Username = '',
											@Change_Permissions_Commands_Action = 'create',			-- Specify whether or not you want to generate revoke or grant/deny commmands. For owner permissions and 'REVOKE', the ownership will be given to the specified user or 'dbo' if not specified.
																									-- Revoking permission also includes revoking ownership.
																									-- Possible values: REVOKE | CREATE | NULL | ''. NULL or empty string yields 'Do not generate'. CREATE means generate GRANT/DENY
											@Execute_Change_Permissions_Commands_Action = 0			-- Choose whether to execute generated @Change_Permissions_Commands_Action or not


GO										

DROP PROC dbo.usp_permissions_for_every_database
GO

DROP PROC dbo.usp_PrintLong
GO


DROP PROC dbo.usp_permissions_for_instance
GO






