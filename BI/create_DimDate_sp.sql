-- =============================================
-- Author:		<a-momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:		<2022.02.04>
-- Description:		<create DimDate "Gregorian & Second Culture(Persian, can be replaced with another culture)">
-- =============================================


USE NorthwindDW
go


CREATE OR ALTER FUNCTION Persian_DayofYear(@GregorianDate DATETIME)
RETURNS int
AS
BEGIN
	DECLARE @MonthDay INT = CONVERT(INT,FORMAT(@GregorianDate,'MMdd','en-uk'))
	DECLARE @GregorianYear INT = YEAR(@GregorianDate)
	IF @MonthDay < 321
		SET @GregorianYear-=1
	
	DECLARE @FirstPersianDayofYear_Gregorian DATETIME
	DECLARE @FirstDayEstimate_Gregorian VARCHAR(8) = CONVERT(VARCHAR(4),@GregorianYear)+'0321'
	DECLARE @RightofPersianDate int = CONVERT(INT,FORMAT(convert(datetime, @FirstDayEstimate_Gregorian),'dd','fa-ir'))
	IF @RightofPersianDate > 20
		SET @FirstPersianDayofYear_Gregorian = DATEADD(DAY,1,CONVERT(DATETIME,@FirstDayEstimate_Gregorian))
	ELSE
		IF @RightofPersianDate = 1
			SET @FirstPersianDayofYear_Gregorian = CONVERT(DATETIME,@FirstDayEstimate_Gregorian)
		ELSE 
			SET @FirstPersianDayofYear_Gregorian = DATEADD(DAY,(~@RightofPersianDate+2),CONVERT(DATETIME,@FirstDayEstimate_Gregorian))
	RETURN (DATEDIFF(DAY,@FirstPersianDayofYear_Gregorian,@GregorianDate)+1)
END
GO

CREATE OR ALTER FUNCTION Persian_WeekofYear(@PersianDayofYear INT, @DayofWeek int)
RETURNS int
AS
BEGIN
	DECLARE @BaseNum INT = @PersianDayofYear / 7 + 1
	DECLARE @Remainder INT = @PersianDayofYear % 7
	IF (@DayofWeek<@Remainder)
		SET @BaseNum+=1
	RETURN @BaseNum
END
go


CREATE OR ALTER PROCEDURE Create_DimDate
(
	@StartDate_Gregorian VARCHAR(8) = '20210101',
	@EndDate_Gregorian VARCHAR(8) = '20401231',
	@Drop_Last_DimDate_If_Exists BIT = 0
)
AS
BEGIN
	SET NOCOUNT on

	
	
	
	IF @Drop_Last_DimDate_If_Exists = 1
		DROP TABLE IF EXISTS DimDate	
		
	
	IF OBJECT_ID('DimDate') IS NULL
		CREATE TABLE DimDate ( 
								--------------- Gregorian:
								DateKey_Gregorian INT NOT NULL,
								DisplayDate_Gregorian VARCHAR(10) NOT NULL,						
								Year_Gregorian INT NOT NULL ,
								Quarter_Gregorian TINYINT NOT NULL ,
								MonthID_Gregorian TINYINT NOT NULL ,
								MonthName_Gregorian VARCHAR(15) NOT NULL ,
								DOW_ID_Gregorian TINYINT NOT NULL ,
								DOW_Name_Gregorian VARCHAR(12) NOT NULL ,
								DayOfYear_Gregorian INT NOT NULL ,
								WeekNo_Gregorian TINYINT NOT NULL,
								--------------- Persian:
								DateKey_Persian INT NOT NULL,
								DisplayDate_Persian VARCHAR(10) NOT NULL,
								Year_Persian INT NOT NULL ,
								Quarter_Persian TINYINT NOT NULL ,
								MonthID_Persian TINYINT NOT NULL ,
								MonthName_Persian NVARCHAR(100) NOT NULL ,
								DOW_ID_Persian TINYINT NOT NULL ,
								DOW_Name_Persian NVARCHAR(10) NOT NULL ,
								DayOfYear_Persian INT NOT NULL ,
								WeekNo_Persian TINYINT NOT NULL,								
							 )


	
	DECLARE @LoopDate INT 
	DECLARE @LoopDate_string VARCHAR(8)
	DECLARE @LoopDate_datetime DATETIME
	DECLARE @Iteration_Count INT =datediff(DAY,CONVERT(DATETIME,@StartDate_Gregorian),CONVERT(DATETIME,@EndDate_Gregorian))
	DECLARE @StartDate_Gregorian_datetime DATETIME=CONVERT(DATETIME,@StartDate_Gregorian)


	DECLARE @LoopDate_SecondCulture INT 
	DECLARE @LoopDate_SecondCulture_string VARCHAR(8)
	DECLARE @LoopDate_SecondCulture_datetime DATETIME

	DECLARE @FirstDayofYear_Equivalent DATETIME
	DECLARE @Persian_DayofYear INT
	DECLARE @PersianDayofWeek int

	

	DECLARE @count INT = 0
	WHILE @count < @Iteration_Count
	BEGIN
	
		SET @LoopDate=CONVERT(INT,FORMAT(DATEADD(DAY,@count,@StartDate_Gregorian),'yyyyMMdd','en-uk'))
		SET @LoopDate_string = CONVERT(VARCHAR(8),@LoopDate)
		SET @LoopDate_datetime = CONVERT(DATETIME,@LoopDate_string)

		SET @LoopDate_SecondCulture = CONVERT(INT,FORMAT(@LoopDate_datetime,'yyyyMMdd','fa-ir'))
		SET @LoopDate_SecondCulture_string = CONVERT(VARCHAR(8),@LoopDate_SecondCulture)
	
		SET @Persian_DayofYear = dbo.Persian_DayofYear(@LoopDate_datetime)
		
		SET @PersianDayofWeek = CASE DATEPART(WEEKDAY,@LoopDate_datetime) WHEN 7 THEN 1 ELSE DATEPART(WEEKDAY,@LoopDate_datetime)+1 END
    
		INSERT dbo.DimDate
		(
			DateKey_Gregorian,
			DisplayDate_Gregorian,
			Year_Gregorian,
			Quarter_Gregorian,
			MonthID_Gregorian,
			MonthName_Gregorian,
			DOW_ID_Gregorian,
			DOW_Name_Gregorian,
			DayOfYear_Gregorian,
			WeekNo_Gregorian,
			DateKey_Persian,
			DisplayDate_Persian,
			Year_Persian,
			Quarter_Persian,
			MonthID_Persian,
			MonthName_Persian,
			DOW_ID_Persian,
			DOW_Name_Persian,
			DayOfYear_Persian,
			WeekNo_Persian
		)
	
		SELECT 
			@LoopDate,   -- DateKey_Gregorian - INT
			STUFF(STUFF(@LoopDate_string, 5, 0, '-'),8,0,'-'),  -- DisplayDate_Gregorian - varchar(10)
			DATEPART(YEAR,@LoopDate_datetime),   -- Year_Gregorian - INT
			DATEPART(QUARTER,@LoopDate_datetime),   -- Quarter_Gregorian - tinyint
			DATEPART(MONTH,@LoopDate_datetime),   -- MonthID_Gregorian - tinyint
			DATENAME(MONTH,@LoopDate_datetime), -- MonthName_Gregorian - varchar(15)
			DATEPART(WEEKDAY,@LoopDate_datetime),   -- DOW_ID_Gregorian - tinyint
			DATENAME(WEEKDAY,@LoopDate_datetime),   -- DOW_Name_Gregorian - varchar(12)
			DATEPART(DAYOFYEAR,@LoopDate_datetime),   -- DayOfYear_Gregorian - INT
			DATEPART(WEEK,@LoopDate_datetime),   -- WeekNo_Gregorian - tinyint
			--------------------
			@LoopDate_SecondCulture,   -- DateKey_Persian - INT
			STUFF(STUFF(@LoopDate_SecondCulture_string, 5, 0, '\'),8,0,'\'),  -- DisplayDate_Persian - varchar(10)
			DATEPART(YEAR,(LEFT(@LoopDate_SecondCulture_string,6)+'01')),   -- Year_Persian - INT
			DATEPART(QUARTER,(LEFT(@LoopDate_SecondCulture_string,6)+'01')),   -- Quarter_Persian - tinyint
			DATEPART(MONTH,(LEFT(@LoopDate_SecondCulture_string,6)+'01')),   -- MonthID_Persian - tinyint
			FORMAT(@LoopDate_datetime, 'MMMM', 'fa-ir'), -- MonthName_Persian - nvarchar(100)
			@PersianDayofWeek,   -- DOW_ID_Persian - tinyint
			FORMAT(@LoopDate_datetime, 'dddd', 'fa-ir'),   -- DOW_Name_Persian - nvarchar(10)
			@Persian_DayofYear,   -- DayOfYear_Persian - INT
			dbo.Persian_WeekofYear(@Persian_DayofYear,@PersianDayofWeek)    -- WeekNo_Persian - tinyint
	    
			SET @count+=1
	END

	ALTER TABLE dbo.DimDate ADD CONSTRAINT PK_DimDate_GregorianDateKey PRIMARY KEY CLUSTERED (DateKey_Gregorian)
	WITH (FILLFACTOR=100)


	CREATE UNIQUE INDEX IX_DimDate_Persian ON DimDate (DateKey_Persian)
	INCLUDE (DisplayDate_Persian,Year_Persian,Quarter_Persian,MonthID_Persian,
			MonthName_Persian,DOW_ID_Persian,DOW_Name_Persian,DayOfYear_Persian,WeekNo_Persian)
	WITH (FILLFACTOR=100)


END
GO

--Example:

EXEC dbo.Create_DimDate @StartDate_Gregorian = '19900101', -- varchar(8)
                        @EndDate_Gregorian = '20401231',    -- varchar(8)
						@Drop_Last_DimDate_If_Exists = 1

