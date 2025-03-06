-- Set isolation level to avoid locking issues during read operations
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- Drop temporary tables if they exist
DROP TABLE IF EXISTS ##temp;
DROP TABLE IF EXISTS ##temp2;
GO

-- CTE to classify partition boundaries by year and quarter (seasonal granularity)
WITH PartitionBoundaries AS (
    SELECT
        ROW_NUMBER() OVER (PARTITION BY pf.name ORDER BY prv.boundary_id DESC) AS BoundaryRow,
        pf.name AS PartitionFunctionName,
        CONVERT(INT, prv.value) / 100 / 100 AS Year,
        CEILING((CONVERT(INT, prv.value) / 100.0) % 100 / 4.0) AS Quarter,
        prv.boundary_id AS BoundaryID,
        pf.function_id,
        prv.boundary_id
    FROM sys.partition_functions AS pf
    JOIN sys.partition_range_values AS prv
        ON prv.function_id = pf.function_id
),
-- CTE to join partition schemes, indexes, and filegroups
PartitionDetails AS (
    SELECT
        fg.name AS filegroup_name,
        OBJECT_NAME(i.object_id) AS table_name,
        i.name AS index_name,
        CONVERT(CHAR(4), pb.Year) AS Year,
        CONVERT(CHAR(1), pb.Quarter) AS Season,
        ps.name AS scheme_name,
        pb.PartitionFunctionName,
        pb.BoundaryID,
        pb.function_id,
        i.object_id,
        i.index_id
    FROM PartitionBoundaries pb
    RIGHT JOIN sys.partition_schemes ps
        ON ps.function_id = pb.function_id
    LEFT JOIN sys.indexes i
        ON i.object_id > 100
        AND i.data_space_id > 60000
        AND i.data_space_id = ps.data_space_id
    LEFT JOIN sys.destination_data_spaces dds
        ON dds.partition_scheme_id = ps.data_space_id
        AND dds.destination_id = pb.BoundaryID
    LEFT JOIN sys.filegroups fg
        ON fg.data_space_id = dds.data_space_id
)
-- Store partition details in a temporary table
SELECT
    table_name,
    index_name,
    Year,
    Season,
    scheme_name,
    PartitionFunctionName,
    filegroup_name
INTO ##temp
FROM PartitionDetails;

-- Group data by table, scheme, and partition function, assuming the last 4 characters of filegroup names represent the year
SELECT
    table_name,
    STRING_AGG(CONVERT(VARCHAR(10), Year) + '-' + CONVERT(VARCHAR(1), Season), ', ') AS Periods,
    scheme_name,
    PartitionFunctionName,
    LEFT(filegroup_name, LEN(filegroup_name) - 4) AS filegroup_common_name,
    STRING_AGG(RIGHT(filegroup_name, 4), ', ') AS filegroup_year
INTO ##temp2
FROM (
    SELECT DISTINCT
        table_name,
        scheme_name,
        Season,
        PartitionFunctionName,
        Year,
        filegroup_name
    FROM ##temp
    
) AS DistinctData
GROUP BY
    table_name,
    scheme_name,
    PartitionFunctionName,
    LEFT(filegroup_name, LEN(filegroup_name) - 4), Year, Season
ORDER BY table_name, Year, Season;
-- Output grouped data
SELECT * FROM ##temp2;

-- Output unaggregated raw data for detailed analysis
SELECT
    table_name,
    Year,
    Season,
    scheme_name,
    PartitionFunctionName,
    filegroup_name,
    index_name
FROM ##temp
ORDER BY table_name, Year, Season;