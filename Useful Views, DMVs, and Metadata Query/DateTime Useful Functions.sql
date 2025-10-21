
-- higher precision functions 
SELECT SYSDATETIME()       AS 'DateAndTime';        -- return datetime2(7)       
SELECT SYSDATETIMEOFFSET() AS 'DateAndTime+Offset'; -- datetimeoffset(7)
SELECT SYSUTCDATETIME()    AS 'DateAndTimeInUtc';   -- returns datetime2(7)
select GETDATE()
select CURRENT_TIMESTAMP

----------------------------------------------------------------------

-- date and time parts - returns nvarchar 
SELECT DATENAME(YEAR, GETDATE())        AS 'Year';        
SELECT DATENAME(QUARTER, GETDATE())     AS 'Quarter';     
SELECT DATENAME(MONTH, GETDATE())       AS 'Month';       
SELECT DATENAME(DAYOFYEAR, GETDATE())   AS 'DayOfYear';   
SELECT DATENAME(DAY, GETDATE())         AS 'Day';         
SELECT DATENAME(WEEK, GETDATE())        AS 'Week';        
SELECT DATENAME(WEEKDAY, GETDATE())     AS 'WeekDay';     
SELECT DATENAME(HOUR, GETDATE())        AS 'Hour';        
SELECT DATENAME(MINUTE, GETDATE())      AS 'Minute';      
SELECT DATENAME(SECOND, GETDATE())      AS 'Second';      
SELECT DATENAME(MILLISECOND, GETDATE()) AS 'MilliSecond'; 
SELECT DATENAME(MICROSECOND, GETDATE()) AS 'MicroSecond'; 
SELECT DATENAME(NANOSECOND, GETDATE())  AS 'NanoSecond';  
SELECT DATENAME(ISO_WEEK, GETDATE())    AS 'Week';  

----------------------------------------------------------------------

-- date and time parts - returns int
SELECT DATEPART(YEAR, GETDATE())        AS 'Year';        
SELECT DATEPART(QUARTER, GETDATE())     AS 'Quarter';     
SELECT DATEPART(MONTH, GETDATE())       AS 'Month';       
SELECT DATEPART(DAYOFYEAR, GETDATE())   AS 'DayOfYear';   
SELECT DATEPART(DAY, GETDATE())         AS 'Day';         
SELECT DATEPART(WEEK, GETDATE())        AS 'Week';        
SELECT DATEPART(WEEKDAY, GETDATE())     AS 'WeekDay';     
SELECT DATEPART(HOUR, GETDATE())        AS 'Hour';        
SELECT DATEPART(MINUTE, GETDATE())      AS 'Minute';      
SELECT DATEPART(SECOND, GETDATE())      AS 'Second';      
SELECT DATEPART(MILLISECOND, GETDATE()) AS 'MilliSecond'; 
SELECT DATEPART(MICROSECOND, GETDATE()) AS 'MicroSecond'; 
SELECT DATEPART(NANOSECOND, GETDATE())  AS 'NanoSecond';  
SELECT DATEPART(ISO_WEEK, GETDATE())    AS 'Week';      

---------------------------------------------------------------------

SELECT DAY(GETDATE())   AS 'Day';                            
SELECT MONTH(GETDATE()) AS 'Month';                       
SELECT YEAR(GETDATE())  AS 'Year';  

---------------------------------------------------------------------

-- date and time from parts
SELECT DATEFROMPARTS(2019,1,1)                         AS 'Date';          -- returns date
SELECT DATETIME2FROMPARTS(2019,1,1,6,0,0,0,1)          AS 'DateTime2';     -- returns datetime2
SELECT DATETIMEFROMPARTS(2019,1,1,6,0,0,0)             AS 'DateTime';      -- returns datetime
SELECT DATETIMEOFFSETFROMPARTS(2019,1,1,6,0,0,0,0,0,0) AS 'Offset';        -- returns datetimeoffset
SELECT SMALLDATETIMEFROMPARTS(2019,1,1,6,0)            AS 'SmallDateTime'; -- returns smalldatetime
SELECT TIMEFROMPARTS(6,0,0,0,0)                        AS 'Time';          -- returns time

---------------------------------------------------------------------

--Date and Time Difference
SELECT DATEDIFF(DAY, 2019-31-01, 2019-01-01)      AS 'DateDif'    -- returns int
SELECT DATEDIFF_BIG(DAY, 2019-31-01, 2019-01-01)  AS 'DateDifBig' -- returns bigint

---------------------------------------------------------------------

-- modify date and time
SELECT DATEADD(DAY,1,GETDATE())        AS 'DatePlus1';          -- returns data type of the date argument
SELECT EOMONTH(GETDATE(),1)            AS 'LastDayOfNextMonth'; -- returns start_date argument or date
SELECT SWITCHOFFSET(GETDATE(), -6)     AS 'NowMinus6';          -- returns datetimeoffset
SELECT TODATETIMEOFFSET(GETDATE(), -2) AS 'Offset';             -- returns datetimeoffset

---------------------------------------------------------------------

-- validate date and time - returns int
SELECT ISDATE(GETDATE()) AS 'IsDate'; 
SELECT ISDATE(NULL) AS 'IsDate';

---------------------------------------------------------------------

select Format(GetDate(), 'yyyyMMdd', 'fa-IR')
SELECT FORMAT(cast('07:35' as time), N'hh\:mm'); --> returns 07:35
SELECT FORMAT(SYSDATETIME(), N'hh:mm tt'); -- returns 03:46 PM

---------------------------------------------------------------------

select datename (day,getdate())
select datename (WEEK,GETDATE())
select datename (WEEKDAY,GETDATE())

--------------------------------------------------------------------
--SQL 2022:
DECLARE @origin DATE = '2022/01/01';
DECLARE @bucketsize INT = 4
SELECT 
 date_bucket(week, @bucketsize, CAST('2022/01/15' as date), @origin),
 date_bucket(week, @bucketsize, CAST('2022/01/30' as date), @origin),
 date_bucket(week, @bucketsize, CAST('2022/02/25' as date), @origin),
 date_bucket(week, @bucketsize, CAST('2022/03/04' as date), @origin)