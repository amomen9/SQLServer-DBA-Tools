-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2025-10-08"
-- Description:         "Index Help"
-- License:             "Please refer to the license file"
-- =============================================



---- Before SQL2022
--SELECT
--	'['+DB_NAME()+'].'+'['+SCHEMA_NAME(ao.schema_id)+'].['+ao.name+']' [Table],
--	QUOTENAME(i.name) index_name,
--	ao.object_id,
--	ao.type_desc object_type,
--	i.type_desc index_type,
--	--ic.index_column_id,
--	STRING_AGG(CONVERT(NVARCHAR(MAX),IIF(ic.is_included_column = 1, NULL, QUOTENAME(col.name))),', ') 
--		--WITHIN GROUP (ORDER BY ic.key_ordinal) 
--		key_columns,
--	STRING_AGG(CONVERT(NVARCHAR(MAX),IIF(ic.is_included_column = 0, NULL, QUOTENAME(col.name))),', ') 
--		--WITHIN GROUP (ORDER BY ic.key_ordinal) 
--		included_columns,
--	i.filter_definition,
--	IIF(c.name IS NULL,'DROP INDEX ['+i.name+'] ON ['+DB_NAME()+'].'+'['+SCHEMA_NAME(ao.schema_id)+'].['+ao.name+']','ALTER TABLE ['+DB_NAME()+'].['+SCHEMA_NAME(ao.schema_id)+'].['+ao.name+'] DROP CONSTRAINT ['+c.name+']')
--	 [DROP Stmt],
--	CONVERT(BIT,IIF(c.name IS NULL,0,1)) IsUniqueConstraint,
--	ius.user_seeks,
--	ius.user_scans,
--	ius.user_lookups
--FROM sys.all_objects ao JOIN sys.indexes i
--ON ao.type IN ('v','u') AND ao.is_ms_shipped = 0 AND ao.object_id = i.object_id
--JOIN sys.dm_db_index_usage_stats ius
--ON ius.object_id = i.object_id AND ius.index_id = i.index_id
--LEFT JOIN sys.index_columns ic 
--ON i.object_id = ic.object_id AND i.index_id = ic.index_id
--LEFT JOIN sys.columns col 
--ON ic.object_id = col.object_id AND ic.column_id = col.column_id
--LEFT JOIN  sys.key_constraints c
--ON c.type = 'UQ' AND c.parent_object_id = i.object_id AND c.unique_index_id = i.index_id
--WHERE ao.object_id = OBJECT_ID('dbo.transaction_log') 
--GROUP BY ao.object_id, ao.name, ao.schema_id, i.index_id, i.name, ao.type_desc, i.type_desc, i.filter_definition, c.name, ius.user_seeks, ius.user_scans, ius.user_lookups --ORDER BY i.index_id
--ORDER BY i.index_id																								  


-- After SQL2022
SELECT 
    [Table],
    [index_name],
    [object_id],
    [object_type],
    [index_type],
    [key_columns],
    [included_columns],
    [Total Columns],
    [Sum of key+inc columns],
    [filter_definition],
    [DROP Stmt],
    [IsUniqueConstraint],
	CASE WHEN dt.key_constraint_type IS NULL
			THEN 'CREATE '+dt.index_type+' INDEX '+[index_name]+' ON ['+DB_NAME+'].'+'['+schema_name+'].['+object_name+']'+CHAR(10)+'('+CHAR(10)+CHAR(9)+dt.key_columns+CHAR(10)+')'+ISNULL('INCLUDE('+dt.included_columns+') '+CHAR(10),CHAR(10))+'WITH(SORT_IN_TEMPDB = ON, ONLINE = ON, DATA_COMPRESSION = PAGE)'
		 WHEN dt.key_constraint_type = 'UQ'
			THEN 'CREATE UNIQUE '+dt.index_type+' INDEX '+[index_name]+' ON ['+DB_NAME+'].'+'['+schema_name+'].['+object_name+']'+CHAR(10)+'('+CHAR(10)+CHAR(9)+dt.key_columns+CHAR(10)+')'+ISNULL('INCLUDE('+dt.included_columns+') '+CHAR(10),CHAR(10))+'WITH(SORT_IN_TEMPDB = ON, ONLINE = ON, DATA_COMPRESSION = PAGE)'
		 ELSE
			'ALTER TABLE ['+DB_NAME+'].['+schema_name+'].['+object_name+'] ADD CONSTRAINT '+dt.index_name+' PRIMARY KEY '+dt.index_type+CHAR(10)+'('+CHAR(10)+CHAR(9)+dt.key_columns+CHAR(10)+')'+CHAR(10)+'WITH(SORT_IN_TEMPDB = ON, ONLINE = ON, DATA_COMPRESSION = PAGE)'
	END 
	 [CREATE Stmt]

FROM
(
	SELECT
		DB_NAME() COLLATE DATABASE_DEFAULT DB_NAME,
		c.type key_constraint_type,
		SCHEMA_NAME(ao.schema_id) schema_name,
		ao.name object_name,
		'['+DB_NAME()+'].'+'['+SCHEMA_NAME(ao.schema_id)+'].['+ao.name+']' [Table],
		QUOTENAME(i.name) index_name,
		ao.object_id,
		ao.type_desc object_type,
		i.type_desc index_type,
		--ic.index_column_id,
		STRING_AGG(CONVERT(NVARCHAR(MAX),IIF(ic.is_included_column = 1, NULL, QUOTENAME(col.name))),', ') 
			WITHIN GROUP (ORDER BY ic.key_ordinal) 
			key_columns,
		STRING_AGG(CONVERT(NVARCHAR(MAX),IIF(ic.is_included_column = 0, NULL, QUOTENAME(col.name))),', ') 
			WITHIN GROUP (ORDER BY ic.key_ordinal) 
			included_columns,
		dt.cobj [Total Columns],
		SUM(IIF(ic.is_included_column = 0, 0, 1)+IIF(ic.is_included_column = 1, 0, 1))
		[Sum of key+inc columns],	
		i.filter_definition,
		IIF(c.name IS NULL,'DROP INDEX ['+i.name+'] ON ['+DB_NAME()+'].'+'['+SCHEMA_NAME(ao.schema_id)+'].['+ao.name+']','ALTER TABLE ['+DB_NAME()+'].['+SCHEMA_NAME(ao.schema_id)+'].['+ao.name+'] DROP CONSTRAINT ['+c.name+']')
		 [DROP Stmt],
		CONVERT(BIT,IIF(c.name IS NULL,0,1)) IsUniqueConstraint

	FROM sys.all_objects ao JOIN sys.indexes i
	ON ao.type in ('v','u') AND ao.is_ms_shipped = 0 AND ao.object_id = i.object_id
	LEFT JOIN sys.index_columns ic 
	ON i.object_id = ic.object_id AND i.index_id = ic.index_id
	LEFT JOIN sys.columns col 
	ON ic.object_id = col.object_id AND ic.column_id = col.column_id
	LEFT JOIN  sys.key_constraints c
	ON c.type = 'UQ' AND c.parent_object_id = i.object_id AND c.unique_index_id = i.index_id
	CROSS JOIN 
	(SELECT COUNT(object_id) cobj, object_id FROM sys.all_columns GROUP BY object_id) dt 
	WHERE ao.object_id = OBJECT_ID('dbo.UserActivities') AND i.name IN ('IX_UserActivities_CreateDateTime','IX_LogoutDate_DeletedByAdmin')
 --LIKE '%'
		AND ao.object_id = dt.object_id
	GROUP BY ao.object_id, dt.cobj, ao.name, ao.schema_id, i.name, ao.type_desc, i.type_desc, i.filter_definition, c.name, c.type --ORDER BY i.name
) dt
ORDER BY key_columns



--EXEC sp_helpindex '[dbo].[TradeSetting]'

/*
ALTER INDEX <IndexName> 
ON <SchemaName>.<TableName> 
DISABLE;


Disabling a Unique Constraint
ALTER TABLE <SchemaName>.<TableName> 
    NOCHECK CONSTRAINT <ConstraintName>;
*/