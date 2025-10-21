-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2024-05-10"
-- Description:         "Partition Info_not refactored"
-- License:             "Please refer to the license file"
-- =============================================



SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

DROP TABLE IF EXISTS ##temp
DROP TABLE IF EXISTS ##temp2
GO


-------- Classification of partiton boundaries (Seasonal Granularity) ----------------------------

;WITH ctein AS
(
	SELECT
		--TOP 1000000
			ROW_NUMBER() OVER (PARTITION BY pf.name ORDER BY prv.boundary_id DESC) BoundaryRow
		, pf.name AS PartitionFunctionName
		, CONVERT(INT,prv.value)/100/100 year
		, CEILING(((CONVERT(INT,prv.value)/100.0)%100)/4.0) quarter
		, prv.boundary_id AS BoundaryID
		, pf.function_id
		, prv.boundary_id
	FROM 
	sys.partition_functions AS pf
	JOIN sys.partition_range_values AS prv
	ON prv.function_id = pf.function_id
)
, cte AS
(
	SELECT  
		  fg.name filegroup_name
		, OBJECT_NAME(i.object_id) [table_name]
		, i.name index_name
		, CONVERT(CHAR(4),ctein.year) [year], CONVERT(CHAR(1),ctein.quarter) [Season]
		, ps.name [scheme_name]
		, ctein.PartitionFunctionName
		, ctein.BoundaryID
		, ctein.function_id
		, i.object_id
		, i.index_id
	FROM ctein
	RIGHT JOIN sys.partition_schemes ps
	ON ps.function_id = ctein.function_id
	LEFT JOIN sys.indexes i
	ON i.object_id>100 AND i.data_space_id>60000 AND i.data_space_id = ps.data_space_id
	LEFT JOIN sys.destination_data_spaces dds
	ON dds.partition_scheme_id = ps.data_space_id AND dds.destination_id = ctein.BoundaryID
	LEFT JOIN sys.filegroups fg
	ON fg.data_space_id = dds.data_space_id
)
SELECT cte.table_name,cte.index_name, cte.year, cte.Season, cte.scheme_name, cte.PartitionFunctionName, cte.filegroup_name 
INTO ##temp
FROM cte 


--------- Grouped, assuming the last 4 charachters of the filegroup names are for year, filegroup_year and filegroup_common_name columns are made

SELECT 
	table_name,
	STRING_AGG(CONVERT(varCHAR(10),year)+'-'+CONVERT(VARCHAR(1),Season),', ') Periods,
	scheme_name,
	PartitionFunctionName,
	LEFT(filegroup_name,LEN(dt.filegroup_name)-4) filegroup_common_name,
	STRING_AGG(RIGHT(filegroup_name,4),', ') filegroup_year
INTO ##temp2
FROM (SELECT DISTINCT TOP 10000000 table_name, scheme_name, Season, PartitionFunctionName, year, filegroup_name FROM ##temp ORDER BY table_name,year,Season) dt 
GROUP BY table_name,
         scheme_name,
         PartitionFunctionName,
		 LEFT(filegroup_name,LEN(dt.filegroup_name)-4)

SELECT * FROM ##temp2


------------ Unaggregated Raw Data
SELECT table_name, year, Season, scheme_name, PartitionFunctionName, filegroup_name, index_name 
FROM ##temp 
--WHERE table_name = 'FactCustomerSession'
ORDER BY table_name, year, Season


