USE JobVisionDB_test_test

--DBCC UPDATEUSAGE(0)
SELECT 
	*
	,IIF(dt.data_used_mb<>0,POWER(dt.user_interactions,2)/dt.data_used_mb,NULL) usefulness
FROM 
(
	SELECT 
		dt.schema_name, dt.object_name, MAX(dt.object_row_count) object_row_count, SUM(dt.data_used_mb) data_used_mb, SUM(dt.data_reserved_mb) data_reserved_mb, SUM(dt.user_interactions) user_interactions
		--, dt.index_id
	FROM
	(
		SELECT
			SCHEMA_NAME(o.schema_id) schema_name,
			o.name object_name,
			i.index_id,
			i.name index_name,
			SUM(ps.row_count) object_row_count,
			SUM(ps.used_page_count)/128.0 data_used_mb,
			SUM(ps.reserved_page_count)/128.0 data_reserved_mb,
			ISNULL(SUM(ixs.user_seeks+ixs.user_scans+ixs.user_lookups+ixs.user_updates),0) user_interactions	
		FROM sys.all_objects o JOIN sys.indexes i 
		ON i.object_id = o.object_id AND o.is_ms_shipped = 0 AND o.type_desc IN ('VIEW','USER_TABLE') --i.index_id IS NOT NULL
		LEFT JOIN sys.dm_db_partition_stats ps
		ON ps.object_id = o.object_id AND ps.index_id = i.index_id
		LEFT JOIN sys.dm_db_index_usage_stats ixs
		ON ixs.object_id = o.object_id AND ixs.index_id = i.index_id
		GROUP BY ixs.object_id, i.index_id, i.name, o.name, o.schema_id
	) dt
	GROUP BY dt.schema_name, dt.object_name
--HAVING SUM(dt.user_interactions)<>0
) dt
ORDER BY usefulness

--SELECT OBJECT_NAME(object_id) FROM sys.dm_db_index_usage_stats
----WHERE user_seeks+user_scans+user_lookups+user_updates<>0
--SELECT * FROM sys.dm_db_partition_stats

--sp_spaceused 'candidate.candidates'

--SELECT TOP 1* FROM employer.RequestToCandidates

