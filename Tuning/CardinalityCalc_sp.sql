use master
go

create or alter proc CardinalityCalc
	@DatabaseName sysname,
	@TableName sysname
AS
BEGIN
	
	DECLARE @sql1 NVARCHAR(MAX)='
		use '+@DatabaseName+'
	  Declare @TableName sysname    
	  DECLARE @InputValidity BIT = 1
		IF '''+@TableName+''' > ''''
		begin
		  
			if parsename('''+@TableName+''',1) not in 
				(select name from '+@DatabaseName+'.sys.tables where Schema_Name(schema_id) = ISNULL(PARSENAME('''+@TableName+''',2),''dbo'') )
			begin
				raiserror(''The specified table and/or schema name does not exist'',16,1)
				set @InputValidity = 0
			end else
				if CHARINDEX(''.'','''+@TableName+''') > 0
					set @TableName = '''+@DatabaseName+'''+''.''+'''+@TableName+'''
				else
					set @TableName = '''+@DatabaseName+'''+''..''+'''+@TableName+'''
		
		  	

		end
		
	  if @InputValidity = 1
	  BEGIN
		 declare @sql nvarchar(max) 
		 select @sql= STUFF((
		 select '' union all select ''+ quotename([name], '''''''')+'' as Column_Name, count(distinct '', quotename([name]), '')*100.0/Count(*) as [crowdedness(in %)] ''+
				 ''from ''+ @TableName
		 FROM '+@DatabaseName+'.sys.all_columns
		 WHERE object_id = OBJECT_ID(@TableName)
		 FOR XML PATH('''') ), 1, 10, '''')           
		 exec(@sql) 
	  END
--	  ELSE
--			SELECT NULL,NULL
	'
	
	EXEC (@sql1)
END
GO

/* Example:
DECLARE @temp TABLE(Column_Name SYSNAME, [Crowdedness (IN %)] FLOAT)
INSERT INTO @temp
EXECUTE master..CardinalityCalc 'Northwind','saasdsad.orders'

select * from @temp
order by 2 desc
*/
