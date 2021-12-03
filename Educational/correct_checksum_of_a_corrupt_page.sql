USE Northwind
GO

CREATE OR ALTER FUNCTION reorder(@input NCHAR(8)) -- This function turns string '12345678' to '78563412'
	RETURNS NCHAR(8)
AS
BEGIN
	DECLARE @temp NCHAR(8) = RIGHT(@input,2)+SUBSTRING(@input,5,2)+SUBSTRING(@input,3,2)+LEFT(@input,2)
	RETURN @temp
END
GO

CREATE OR ALTER function dbo.fn_hexstr2varbin(@input varchar(8000))
  returns varbinary(8000)
as
begin
 declare @result varbinary(8000), @i int, @l int
  set @result = 0x
  set @l = len(@input)/2
  set @i = 2
  while @i <= @l
  begin
    set @result = @result +
      cast(cast(case lower(substring(@input, @i*2-1, 1))
        when '0' then 0x00
        when '1' then 0x10
        when '2' then 0x20
        when '3' then 0x30
        when '4' then 0x40
        when '5' then 0x50
        when '6' then 0x60
        when '7' then 0x70
        when '8' then 0x80
        when '9' then 0x90
        when 'a' then 0xa0
        when 'b' then 0xb0
        when 'c' then 0xc0
        when 'd' then 0xd0
        when 'e' then 0xe0
        when 'f' then 0xf0
      end as tinyint) |
      cast(case lower(substring(@input, @i*2, 1))
        when '0' then 0x00
        when '1' then 0x01
        when '2' then 0x02
        when '3' then 0x03
        when '4' then 0x04
        when '5' then 0x05
        when '6' then 0x06
        when '7' then 0x07
        when '8' then 0x08
        when '9' then 0x09
        when 'a' then 0x0a
        when 'b' then 0x0b
        when 'c' then 0x0c
        when 'd' then 0x0d
        when 'e' then 0x0e
        when 'f' then 0x0f
      end as tinyint) as binary(1))
    set @i = @i + 1
  end
  return @result
end
go


DECLARE @PageNo INT
DECLARE @SQL VARCHAR(MAX)
DECLARE @CorrectChecksum NCHAR(10)
DECLARE @IncorrectChecksum NCHAR(10)
DECLARE @ErrMsg VARCHAR(700)
DECLARE @ShipCity_new_name nvarchar(6) = N'Shiraz'


DECLARE @temp VARCHAR(25) 

-- Find database page containing OrderID 10255

-- The row we want to change at a low level:
SELECT * FROM Orders WHERE orderid=10255


BEGIN try
	SELECT @PageNo = CONVERT(INT,PARSENAME(REPLACE(sys.fn_PhysLocFormatter(%%PhysLoc%%) ,':','.'),'2')) FROM Orders WHERE orderid=10255	
END TRY
BEGIN CATCH
	set @ErrMsg = ERROR_MESSAGE()
	set @temp = SUBSTRING(@ErrMsg,CHARINDEX('page',@ErrMsg),25)
	SET @PageNo = SUBSTRING(@temp,(CHARINDEX(':',@temp)+1),(CHARINDEX(')',@temp)-(CHARINDEX(':',@temp))-1))
	SET @InCorrectChecksum = SUBSTRING(@ErrMsg,CHARINDEX('(',@ErrMsg)+11,10)
	SET @CorrectChecksum = SUBSTRING(@ErrMsg,CHARINDEX('(',@ErrMsg)+31,10)
	PRINT(@CorrectChecksum)
	PRINT(@IncorrectChecksum)
	PRINT(@PageNo)
END CATCH

-- SELECT @PageNo

DROP TABLE IF EXISTS tempdb..tmpTable
CREATE TABLE tempdb..tmpTable (
	id INT PRIMARY KEY IDENTITY NOT NULL,
    ParentObject nvarchar(255),
    Object nvarchar(255),
    Field nvarchar(255),
    VALUE nvarchar(255))


SET @sql = 'DBCC PAGE(''Northwind'' , 1 , '+CONVERT(NVARCHAR(10),@PageNo)+' , 2) WITH TABLERESULTS, NO_INFOMSGS'
PRINT @SQL
INSERT tempdb..tmpTable
EXECUTE (@sql)

-----------------------------------------------------------------

SELECT * FROM tempdb..tmpTable WHERE VALUE = 'Genève'

--- Let's corrupt data!! ----------------------------------------

USE Northwind
ALTER DATABASE Northwind SET SINGLE_USER WITH ROLLBACK IMMEDIATE

DECLARE @x varBinary(4000)
SET @x = CONVERT(varBinary(4000) , @ShipCity_new_name)

-- 0x578 + 0x86 = 1534 decimal
DBCC WRITEPAGE('Northwind' , 1 , @PageNo , 1534 , 12 , @x , 1) WITH NO_INFOMSGS

ALTER DATABASE Northwind SET MULTI_USER
-----------------------------------------------------------------

USE Northwind

-- Now if we run this:
-- SELECT * FROM dbo.Orders WHERE OrderID = 10255
-- SQL Server returns The following consistency checksum error:
/*
Msg 824, Level 24, State 2, Line 41
SQL Server detected a logical consistency-based I/O error: 
incorrect checksum (expected: 0x48a55e33; actual: 0xc8adde30). 
It occurred during a read of page (1:568) in database ID 7 at offset 0x00000000470000
in file 'D:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\Northwind.mdf'.
Additional messages in the SQL Server error log or operating system error log may provide
more detail. This is a severe error condition that threatens database integrity and must be
corrected immediately. Complete a full database consistency check (DBCC CHECKDB).
This error can be caused by many factors; for more information, see SQL Server Books Online.
*/
-- We read the page again to find the incorrect checksum

BEGIN try
	SELECT ShipCity FROM Orders WHERE orderid=10255		-- The pointer will jump to 'catch' statement because the page is corrupt
END TRY
BEGIN CATCH	
	set @ErrMsg = ERROR_MESSAGE()
	PRINT(@ErrMsg)
	set @temp = SUBSTRING(@ErrMsg,CHARINDEX('page',@ErrMsg),25)
	SET @PageNo = SUBSTRING(@temp,(CHARINDEX(':',@temp)+1),(CHARINDEX(')',@temp)-(CHARINDEX(':',@temp))-1))
	SET @IncorrectChecksum = SUBSTRING(@ErrMsg,CHARINDEX('(',@ErrMsg)+11,10)
	SET @CorrectChecksum = SUBSTRING(@ErrMsg,CHARINDEX('(',@ErrMsg)+31,10)
--	PRINT(@CorrectChecksum)
--	PRINT(@IncorrectChecksum)
--	PRINT(@PageNo)
END CATCH

-- 30deadc8
-- 335ea548

SELECT * FROM tempdb..tmpTable WHERE value LIKE ('%'+dbo.reorder(RIGHT(@IncorrectChecksum,8))+'%') -- incorrect checksum
-- row number 58

--DECLARE @IncorrectChecksum NVARCHAR(10) = '335ea548'
--SELECT id FROM tempdb.dbo.tmpTable WHERE value LIKE ('%'+@IncorrectChecksum+'%')

DECLARE @Checksum_Row_ID INT 

SELECT @Checksum_Row_ID = id FROM tempdb..tmpTable WHERE value LIKE ('%'+dbo.reorder(RIGHT(@IncorrectChecksum,8))+'%')

DECLARE @Value_of_checksum_row NVARCHAR(255) = (SELECT VALUE FROM tempdb.dbo.tmpTable WHERE id = @Checksum_Row_ID)

--- Value of checksum row
SELECT @Value_of_checksum_row [Value Containing Checksum to be corrected]

SELECT RIGHT(LEFT(@Value_of_checksum_row, (CHARINDEX(':',@Value_of_checksum_row)-1)),2) offset

DECLARE @offset_string NCHAR(4) = '0x' + RIGHT(LEFT(@Value_of_checksum_row, (CHARINDEX(':',@Value_of_checksum_row)-1)),2)
DECLARE @offset_int INT = CONVERT(INT,dbo.fn_hexstr2varbin(@offset_string))

SELECT @offset_string offset_string, @offset_int offset_int

------------- Now we correct the wrong checksum:-----------------

USE Northwind
ALTER DATABASE Northwind SET SINGLE_USER WITH ROLLBACK IMMEDIATE

-- reorder correct checksum
DECLARE @correct_checksum_reordered VARCHAR(10) = dbo.reorder(RIGHT(@CorrectChecksum,8))
SET @correct_checksum_reordered = '0x'+@correct_checksum_reordered
SELECT @correct_checksum_reordered

DECLARE @correct_checksum_varbinary VARBINARY(8) = dbo.fn_hexstr2varbin(@correct_checksum_reordered)

DBCC WRITEPAGE('Northwind' , 1 , @PageNo , @offset_int , 4 , @correct_checksum_varbinary , 1) WITH NO_INFOMSGS

ALTER DATABASE Northwind SET MULTI_USER

------------------------------------------------------------------

------ Now we get back to the corrupt row and see if we can access it:

SELECT * FROM Orders WHERE orderid=10255
