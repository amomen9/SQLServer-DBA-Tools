-- =============================================
-- Author:				<a.momen>
-- Contact & Report:	<amomen@gmail.com>
-- Create date:			
-- Description:			Formats elapsed time (in microseconds) to a readable string
--                      with configurable precision and biggest unit
-- License:				<Please refer to the license file> 
-- =============================================

USE msdb;
GO

CREATE OR ALTER FUNCTION dbo.udf_TIME_Formatter
(
    @ElapsedMicroseconds BIGINT,        -- Elapsed time in microseconds
    @Precision VARCHAR(20),             -- 'microsecond', 'millisecond', 'second', 'minute', 'hour', 'day', 'week', 'month', 'year'
    @Biggest_Unit VARCHAR(20)           -- Same values as @Precision - defines the largest unit to display
)
RETURNS NVARCHAR(200)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @Result NVARCHAR(200) = '';
    DECLARE @Format NVARCHAR(200) = '';
    
    -- Unit hierarchy (from smallest to largest)
    DECLARE @UnitLevel_Precision INT;
    DECLARE @UnitLevel_Biggest INT;
    
    -- Map precision to level
    SET @UnitLevel_Precision = CASE LOWER(@Precision)
        WHEN 'microsecond' THEN 1
        WHEN 'millisecond' THEN 2
        WHEN 'second' THEN 3
        WHEN 'minute' THEN 4
        WHEN 'hour' THEN 5
        WHEN 'day' THEN 6
        WHEN 'week' THEN 7
        WHEN 'month' THEN 8
        WHEN 'year' THEN 9
        ELSE 3  -- default to second
    END;
    
    -- Map biggest unit to level
    SET @UnitLevel_Biggest = CASE LOWER(@Biggest_Unit)
        WHEN 'microsecond' THEN 1
        WHEN 'millisecond' THEN 2
        WHEN 'second' THEN 3
        WHEN 'minute' THEN 4
        WHEN 'hour' THEN 5
        WHEN 'day' THEN 6
        WHEN 'week' THEN 7
        WHEN 'month' THEN 8
        WHEN 'year' THEN 9
        ELSE 6  -- default to day
    END;
    
    -- Extract time components
    DECLARE @Remaining BIGINT = @ElapsedMicroseconds;
    DECLARE @Microseconds INT = 0;
    DECLARE @Milliseconds INT = 0;
    DECLARE @Seconds INT = 0;
    DECLARE @Minutes INT = 0;
    DECLARE @Hours INT = 0;
    DECLARE @Days INT = 0;
    DECLARE @Weeks INT = 0;
    DECLARE @Months INT = 0;
    DECLARE @Years INT = 0;
    
    -- First, extract fractional seconds (microseconds and milliseconds)
    SET @Microseconds = @Remaining % 1000;
    SET @Remaining = @Remaining / 1000;  -- now in milliseconds
    
    SET @Milliseconds = @Remaining % 1000;
    SET @Remaining = @Remaining / 1000;  -- now in seconds
    
    -- Calculate based on biggest unit (this determines rollover behavior)
    IF @UnitLevel_Biggest >= 9  -- year is biggest
    BEGIN
        SET @Years = @Remaining / (365 * 24 * 3600);
        SET @Remaining = @Remaining % (365 * 24 * 3600);
    END
    
    IF @UnitLevel_Biggest >= 8  -- month
    BEGIN
        SET @Months = @Remaining / (30 * 24 * 3600);
        SET @Remaining = @Remaining % (30 * 24 * 3600);
    END
    
    IF @UnitLevel_Biggest >= 7  -- week
    BEGIN
        SET @Weeks = @Remaining / (7 * 24 * 3600);
        SET @Remaining = @Remaining % (7 * 24 * 3600);
    END
    
    IF @UnitLevel_Biggest >= 6  -- day
    BEGIN
        SET @Days = @Remaining / (24 * 3600);
        SET @Remaining = @Remaining % (24 * 3600);
    END
    
    IF @UnitLevel_Biggest >= 5  -- hour
    BEGIN
        SET @Hours = @Remaining / 3600;
        SET @Remaining = @Remaining % 3600;
    END
    
    IF @UnitLevel_Biggest >= 4  -- minute
    BEGIN
        SET @Minutes = @Remaining / 60;
        SET @Remaining = @Remaining % 60;
    END
    
    IF @UnitLevel_Biggest >= 3  -- second
    BEGIN
        SET @Seconds = @Remaining;
    END
    ELSE IF @UnitLevel_Biggest = 2  -- millisecond is biggest (accumulate all seconds into milliseconds)
    BEGIN
        SET @Milliseconds = @Milliseconds + (@Remaining * 1000);
    END
    ELSE IF @UnitLevel_Biggest = 1  -- microsecond is biggest (accumulate all into microseconds)
    BEGIN
        SET @Microseconds = @Microseconds + (@Remaining * 1000000) + (@Milliseconds * 1000);
        SET @Milliseconds = 0;
    END
    
    -- Build result string: always show from biggest unit down to precision
    -- Start from biggest and work down
    IF @UnitLevel_Biggest >= 9  -- year
    BEGIN
        SET @Result = RIGHT('00' + CAST(@Years AS VARCHAR), 2) + ':';
        SET @Format = 'YY:';
    END
    
    IF @UnitLevel_Biggest >= 8  -- month
    BEGIN
        SET @Result = @Result + RIGHT('00' + CAST(@Months AS VARCHAR), 2) + ':';
        SET @Format = @Format + 'MO:';
    END
    
    IF @UnitLevel_Biggest >= 7  -- week
    BEGIN
        SET @Result = @Result + RIGHT('00' + CAST(@Weeks AS VARCHAR), 2) + ':';
        SET @Format = @Format + 'WW:';
    END
    
    IF @UnitLevel_Biggest >= 6  -- day (show if biggest >= 6)
    BEGIN
        SET @Result = @Result + RIGHT('00' + CAST(@Days AS VARCHAR), 2) + ':';
        SET @Format = @Format + 'DD:';
    END
    
    IF @UnitLevel_Biggest >= 5  -- hour (show if biggest >= 5)
    BEGIN
        SET @Result = @Result + RIGHT('00' + CAST(@Hours AS VARCHAR), 2) + ':';
        SET @Format = @Format + 'HH:';
    END
    
    IF @UnitLevel_Biggest >= 4  -- minute (show if biggest >= 4)
    BEGIN
        SET @Result = @Result + RIGHT('00' + CAST(@Minutes AS VARCHAR), 2) + ':';
        SET @Format = @Format + 'mm:';
    END
    
    -- Now handle seconds and below based on precision
    IF @UnitLevel_Biggest >= 3  -- second level or higher
    BEGIN
        SET @Result = @Result + RIGHT('00' + CAST(@Seconds AS VARCHAR), 2);
        SET @Format = @Format + 'ss';
        
        -- Add fractional seconds if precision requires
        IF @UnitLevel_Precision <= 2  -- show millisecond
        BEGIN
            SET @Result = @Result + '.' + RIGHT('000' + CAST(@Milliseconds AS VARCHAR), 3);
            SET @Format = @Format + '.ms';
            
            IF @UnitLevel_Precision = 1  -- show microsecond
            BEGIN
                SET @Result = @Result + RIGHT('000' + CAST(@Microseconds AS VARCHAR), 3);
                SET @Format = @Format + 'us';
            END
        END
    END
    ELSE IF @UnitLevel_Biggest = 2  -- millisecond is biggest unit
    BEGIN
        SET @Result = @Result + CAST(@Milliseconds AS VARCHAR);
        SET @Format = @Format + 'ms';
        
        IF @UnitLevel_Precision = 1  -- show microseconds
        BEGIN
            SET @Result = @Result + '.' + RIGHT('000' + CAST(@Microseconds AS VARCHAR), 3);
            SET @Format = @Format + '.us';
        END
    END
    ELSE IF @UnitLevel_Biggest = 1  -- microsecond is biggest unit
    BEGIN
        SET @Result = @Result + CAST(@Microseconds AS VARCHAR);
        SET @Format = @Format + 'us';
    END
    
    -- Remove trailing colon if any
    IF RIGHT(@Result, 1) = ':'
        SET @Result = LEFT(@Result, LEN(@Result) - 1);
    IF RIGHT(@Format, 1) = ':'
        SET @Format = LEFT(@Format, LEN(@Format) - 1);
    
    RETURN @Result + ' [' + @Format + ']';
END
GO

-- Example Usage:
DECLARE @TimeStamp DATETIME2(6) = SYSDATETIME();
WAITFOR DELAY '00:00:02.123';  -- simulate 2.123 seconds elapsed
DECLARE @Elapsed BIGINT = DATEDIFF_BIG(microsecond, @TimeStamp, SYSDATETIME());

SELECT 
    @Elapsed AS ElapsedMicroseconds,
    dbo.udf_TIME_Formatter(@Elapsed, 'microsecond', 'day') AS [Microsecond precision, Day biggest],
    dbo.udf_TIME_Formatter(@Elapsed, 'millisecond', 'day') AS [Millisecond precision, Day biggest],
    dbo.udf_TIME_Formatter(@Elapsed, 'second', 'hour') AS [Second precision, Hour biggest],
    dbo.udf_TIME_Formatter(@Elapsed, 'second', 'minute') AS [Second precision, Minute biggest];
GO