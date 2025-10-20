DROP TABLE IF EXISTS myTable;

CREATE TABLE myTable (
    [Package Name] nvarchar(max) NOT NULL,
    [Package Version] nvarchar(max) NOT NULL
    )
GO
insert into myTable
EXECUTE sp_execute_external_script
@language=N'R'
,@script = N'str(OutputDataSet);
packagematrix <- installed.packages();
Name <- packagematrix[,1];
Version <- packagematrix[,3];
OutputDataSet <- data.frame(Name, Version);'
, @input_data_1 = N''
, @output_data_1_name = N'OutputDataSet'
--WITH RESULT SETS ((PackageName nvarchar(250), PackageVersion nvarchar(max) ))

select * from myTable
where [Package Name] = 'openxlsx'

--sp_configure 'external scripts enabled', 1;
--RECONFIGURE WITH OVERRIDE;  