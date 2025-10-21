-- =============================================
-- Author:				<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			<2023.02.26>
-- Latest Update Date:	<23.02.26>
-- Description:			<instance permissions>
-- License:				<Please refer to the license file> 
-- =============================================


USE master
GO


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



DROP PROC IF EXISTS usp_PrintLong
GO

CREATE OR ALTER PROC usp_PrintLong
	@String NVARCHAR(MAX),
	@Max_Chunk_Size SMALLINT = 4000,
	@Print_String_Length BIT = 0
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
	IF @Print_String_Length = 1
		PRINT '------------------------------'+CHAR(10)+'------String total length:'+CHAR(10)+CONVERT(NVARCHAR(100),(DATALENGTH(@String)/2))+CHAR(10)+'------Total line numbers:'+CHAR(10)+CONVERT(NVARCHAR(100),LEN(@String)-LEN(REPLACE(@String,CHAR(10),'')))+CHAR(10)+'------------------------------'
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
		-- Server Roles: 
		SELECT ar2.name,'SERVER ROLE', ar.name, 'OWNER', NULL, 'OWNER', ar.owning_principal_id, (SELECT is_disabled FROM sys.server_principals WHERE principal_id=ar2.principal_id)								FROM sys.server_principals ar JOIN sys.server_principals ar2 ON ar2.principal_id = ar.owning_principal_id WHERE ar.type_desc = 'SERVER_ROLE' AND ar.owning_principal_id IS NOT NULL
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



EXEC dbo.usp_permissions_for_instance @Login_Filter = '%'    -- sysname 

DROP PROC dbo.usp_PrintLong
GO

DROP PROC dbo.usp_permissions_for_instance
GO






