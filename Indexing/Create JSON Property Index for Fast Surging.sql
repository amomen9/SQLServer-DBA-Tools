SELECT  COUNT(*) FROM dbo.RawData
SELECT * FROM dbo.RawData

------- Cardinality Related ----------------------------
SELECT COUNT(DISTINCT vdataid)*100.0/COUNT(*) c_vdataid, COUNT(DISTINCT vDataAddDate)*100.0/COUNT(*) c_vDataAddDate FROM dbo.RawData WITH (NOLOCK)
--------------------------------------------------------
SELECT  FROM sys.all_columns WHERE object_id = OBJECT_ID('dbo.RawData') AND name IN ('vdataid','vDataAddDate')
SELECT name, COLUMNPROPERTY(OBJECT_ID('dbo.RawData'),name,'IsDeterministic') IsDeterministic, is_persisted FROM sys.computed_columns WHERE object_id = OBJECT_ID('dbo.RawData') AND name IN ('vdataid','vDataAddDate')


---------- Adding computed columns ---------------------
ALTER TABLE dbo.RawData
DROP COLUMN IF EXISTS vDataId

ALTER TABLE dbo.RawData
ADD vDataId AS JSON_VALUE([Data],'$.id') --PERSISTED

ALTER TABLE dbo.RawData
DROP COLUMN IF EXISTS vDataAddDate

ALTER TABLE dbo.RawData
ADD vDataAddDate AS CONVERT(DATE, JSON_VALUE([DATA], '$.add'),120) --PERSISTED
--------------------------------------------------------
SELECT CONVERT(DATE,GETDATE(),120)

CREATE INDEX IX_RawData_json_DataAddDate
ON dbo.RawData(vDataAddDate)
INCLUDE(vDataId,Data)
WITH(ONLINE=ON, MAXDOP=1, SORT_IN_TEMPDB = ON)

USE KarBoardDivarDB 
SELECT   COUNT(DISTINCT JSON_VALUE([DATA], '$.id') COLLATE Persian_100_CS_AS) 
FROM dbo.RawData 
WHERE CONVERT(DATE, JSON_VALUE([DATA], '$.add'),120) between '2022-10-12' and '2022-10-21' 
GROUP by CONVERT(DATE, JSON_VALUE([DATA], '$.add'),120)


-------------------------------------------------------
USE KarBoardDivarDB
GO

select *
FROM dbo.RawData
WHERE vDataId = 'AZuQGP1R'
