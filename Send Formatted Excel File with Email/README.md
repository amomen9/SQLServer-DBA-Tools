# Send an Email with a Conditionally Formatted Excel File Attached

This article is part of the wider project of **"Automatic country-wide branch downtime report for the banking system"**.
 The rest of the project cannot be disclosed because it is an asset of the employer bank, and also they are by
 policy defined within the confidentiality level of publish-prohibited materials.

 
---


# Automatic Daily Branch Network Outage Report Dispatch

**Document Originally Written:** 1401/01/14 (2021‑04‑03 Gregorian)

**Document Last Modified:** 1404/07/16 (2025‑10‑05 Gregorian)

---

## 1. Overview

The daily outage status report for bank branches is sent automatically from the email account `report.sending.email@company.com` by the `SQL Server Database Engine` on server `<Reporting Server IP>`.

- Dispatch times:
  - Saturday to Wednesday: 14:30
  - Thursday: 13:00

The report is generated via a stored procedure that invokes external `R` scripts inside `SQL Server` to produce a formatted Excel file and email it through Database Mail.

---

## 2. Minimum System Software Requirements for the Reporting Server

| Component | Minimum Requirement |
|----------|---------------------|
| `SQL Server` | Version 2017 or later |
| Operating System (for `SQL Server 2017+`) | `Windows Server 2016+`, `Windows 10+`, `Ubuntu 16.04+` or other Microsoft-listed Linux distributions |
| External Script Runtime | `R` (via `Machine Learning Services and Languages`) |

---

## 3. Windows Installation and Configuration (Reporting Server)

The reporting system uses the `R` engine in `SQL Server` to convert the report into Excel. Therefore, the `R` feature (`Machine Learning Services and Languages`) must be enabled during `SQL Server` setup.

> During installation, ensure that the `Machine Learning Services and Language` feature with `R` is checked.

---

## 4. Offline Installation of Required R Packages

Because the production servers are disconnected from the Internet:

1. Install `SQL Server` with `R` Machine Learning components on a local (Internet-connected) workstation.  
   Assumptions:
   - Default installation path.
   - Default instance (`MSSQLSERVER`).

2. Navigate to:
   ```
   C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\R_SERVICES\bin
   ```

3. Run `R.exe` as Administrator (Internet required).

4. Install required `R` packages:

   ```r
   # R console (run as Administrator)
   install.packages("openxlsx")
   install.packages("dplyr")
   install.packages("sjmisc")
   ```

5. After installation completes, close the window.

6. Copy the entire contents of:
   ```
   C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\R_SERVICES\library
   ```
   and paste them into the corresponding path on the (offline) Reporting Server.

7. When prompted with a folder merge confirmation, click “No” for replacing existing root folder structure (to preserve any pre-existing components) but ensure package subfolders are copied as needed.

**R Packages Required:**
- `openxlsx`
- `dplyr`
- `sjmisc`

---

## 5. Tools Needed

You need `Microsoft SQL Server Management Studio (SSMS)` (can be installed standalone) to connect to:

- `BHDB Server` (source data)
- `Reporting Server` (report generation and dispatch)

---

## 6. Configuration Steps Overview

### High-Level Sequence

1. On the `BHDB Server`:
   - Create schema and function `[rep].[GhateiShoab]`.
   - Create login for Reporting Server access (`RSL`).
   - Execute additional dependency scripts.
   - Configure (or request) Linked Server to `Branch List Server` database.

2. On the `Reporting Server`:
   - Create `Report` database and stored procedure `sp_save_excel_ghatei`.
   - Create SQL Agent Job `GhateiShoab`.
   - Configure Database Mail.
   - Create Linked Server to `<`BHDB Server` IP>` (`BHDB Server`).
   - Ensure directory structure and file system permissions.
   - Ensure `logo.png` placement.

3. Validate service states and re-mount VHD after restarts (if applicable).

---

## 7. `BHDB Server` Side Setup

### 7.1 Create Schema and Function

```sql
-- Script 1 (`BHDB Server`)
-- =============================================
-- Author: <A.Momen>
-- Email: <amomen@gmail.com>
-- =============================================

USE WhatsUp;
GO

IF (SELECT name FROM sys.schemas WHERE name = N'rep') IS NOT NULL
    DROP SCHEMA rep;
GO

CREATE SCHEMA rep;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE FUNCTION [rep].[GhateiShoab] ()
RETURNS @gs TABLE
(
    [ردیف] [bigint] NULL,
    [نام شعبه] [nvarchar](100) NULL,
    [استان] [nvarchar](100) NULL,
    [کد مهرگستر شعبه] [int] NULL,
    [لینکهای شعبه جدید] [nvarchar](4000) NULL,
    [تاریخ شروع] [varchar](200) NULL,
    [زمان شروع] [varchar](8) NULL,
    [زمان پایان] [varchar](8) NULL,
    [مدت زمان قطعی به ساعت / دقیقه / ثانیه] [nvarchar](max) NULL,
    [وضعیت] [nvarchar](30) NULL
)
AS
BEGIN
    WITH temp1
    (
        [نام شعبه],
        [استان],
        [کد مهرگستر شعبه],
        [لینکهای شعبه جدید],
        [تاریخ شروع],
        [زمان شروع],
        [زمان پایان],
        [مدت زمان قطعی به ساعت / دقیقه / ثانیه]
    ) AS
    (
        SELECT
            [نام شعبه],
            [استان],
            [کد مهرگستر شعبه],
            REPLACE([لینکهای شعبه جدید], N'ADSL', N'VSAT') AS [لینکهای شعبه جدید],
            [تاریخ شروع],
            [زمان شروع],
            [زمان پایان],
            [مدت زمان قطعی به ساعت / دقیقه / ثانیه]
        FROM WhatsUp.dbo.fn_GetReportDwon(
            REPLACE(CONVERT(DATE, CONVERT(DATETIME, GETDATE(), 114)), '-', ''),
            REPLACE(CONVERT(DATE, CONVERT(DATETIME, DATEADD(DAY, 1, GETDATE()), 114)), '-', ''),
            7,
            14.5,
            20
        )
        WHERE [نام شعبه] IS NOT NULL
          AND [استان] IS NOT NULL
    ),
    temp2
    (
        [Radif],
        [نام شعبه],
        [استان],
        [کد مهرگستر شعبه],
        [لینکهای شعبه جدید],
        [تاریخ شروع],
        [زمان شروع],
        [زمان پایان],
        [مدت زمان قطعی به ساعت / دقیقه / ثانیه]
    ) AS
    (
        SELECT
            ROW_NUMBER() OVER (ORDER BY [زمان شروع]) AS [Radif],
            [نام شعبه],
            [استان],
            [کد مهرگستر شعبه],
            CASE
                WHEN [استان] = N'خوزستان' OR [استان] = N'ايلام'
                    THEN REPLACE([لینکهای شعبه جدید], N'interanet -', '')
                WHEN [استان] <> N'خوزستان' AND [استان] <> N'ايلام'
                    THEN [لینکهای شعبه جدید]
            END AS N'لینکهای شعبه جدید',
            [تاریخ شروع],
            [زمان شروع],
            [زمان پایان],
            [مدت زمان قطعی به ساعت / دقیقه / ثانیه]
        FROM temp1
    ),
    temp3
    (
        [Radif],
        [نام شعبه],
        [استان],
        [کد مهرگستر شعبه],
        [لینکهای شعبه جدید],
        [تاریخ شروع],
        [زمان شروع],
        [زمان پایان],
        [مدت زمان قطعی به ساعت / دقیقه / ثانیه],
        [وضعیت]
    ) AS
    (
        SELECT
            *,
            CASE
                WHEN [لینکهای شعبه جدید] = N'VSAT -Interanet -'
                  OR [لینکهای شعبه جدید] = N'Interanet -VSAT -'
                    THEN N'قطعی ارتباط روتر ایرانسولار'
                WHEN LEN([لینکهای شعبه جدید]) - LEN(REPLACE([لینکهای شعبه جدید], ' -', '')) = 2
                    THEN N'قطعی خط دیتا'
                ELSE N'در حال بررسی'
            END AS 'وضعیت'
        FROM temp2
    )
    INSERT @gs
    SELECT * FROM temp3;
    RETURN;
END;
GO
```

### 7.2 Create Login for Reporting Server Access

```sql
-- Script 2 (`BHDB Server`)
-- Login used by Reporting Server to query WhatsUp data
USE [master];
GO

CREATE LOGIN [RSL]
WITH PASSWORD = N'Kesh@v@rz!NoC33admin',
     DEFAULT_DATABASE = [master],
     DEFAULT_LANGUAGE = [us_english],
     CHECK_EXPIRATION = OFF,
     CHECK_POLICY = OFF;
GO
```

### 7.3 Additional Dependency Scripts

Execute the following (order-sensitive) provided scripts on `BHDB Server` (already authored elsewhere)
. The `5131_dbo.SolarDate.sql` script can be replaced by `SQL Server`'s
built-in inline `FORMAT` function which is also a better solution:

```
5131_dbo.SolarDate.sql
5131_dbo.GregorianDate.sql
5131_dbo.fn_getUpTime.sql
5131_dbo.fn_GetReportDwon_Prev.sql
5131_dbo.fn_GetReportDwon.sql
```

### 7.4 Linked Server to `Branch List Server`

A script named (example):

```
5131_<Branch List Server IP>_Branch List Server_Linked-Server.sql
```

This must be coordinated with the Software Department for proper setup.

---

## 8. Reporting Server Setup

### 8.1 Create Database and Stored Procedure

```sql
-- Script 1 (Reporting Server)
-- =============================================
-- Author: <A.Momen>
-- Email: <amomen@gmail.com>
-- =============================================

DROP DATABASE IF EXISTS Report;
CREATE DATABASE Report;
GO

USE Report;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_save_excel_ghatei]
AS
BEGIN
    DECLARE @DayofWeek INT = DATEPART(WEEKDAY, GETDATE());
    DECLARE @DayofWeekPersian NVARCHAR(10);
    DECLARE @FileName NVARCHAR(MAX) = N'test';
    DECLARE @DatePersian NVARCHAR(20);
    DECLARE @subject NVARCHAR(MAX);
    DECLARE @FullDate NVARCHAR(50);

    SELECT @DayofWeekPersian =
        CASE
            WHEN @DayofWeek = 7 THEN N'شنبه'
            WHEN @DayofWeek = 1 THEN N'یکشنبه'
            WHEN @DayofWeek = 2 THEN N'دوشنبه'
            WHEN @DayofWeek = 3 THEN N'سه شنبه'
            WHEN @DayofWeek = 4 THEN N'چهارشنبه'
            WHEN @DayofWeek = 5 THEN N'پنج شنبه'
            WHEN @DayofWeek = 6 THEN N'جمعه'
        END;

    SELECT @DatePersian =
        (SELECT * FROM OPENQUERY([<`BHDB Server` IP>],
         'SELECT [WhatsUp].[dbo].SolarDate(GetDate())'));

    SET @FullDate = @DayofWeekPersian + N' ' + @DatePersian;
    SET @FileName = REPLACE(@DatePersian, N'/', N'.');

    DECLARE @rscript NVARCHAR(MAX);

    SET @rscript = N'
       OutputDataSet <- SqlData;

       library(openxlsx)
       library(dplyr)
       library(sjmisc)

       wb <- createWorkbook()
       addWorksheet(wb, sheetName = mytname)

       startrow <- 1

       setColWidths(wb, mytname, cols = 1:10,
                    widths = c(3, 18, 18, 14, 22, 11, 9, 9, 18, 22))
       setRowHeights(wb, mytname, rows = (1), heights = c(53))
       setRowHeights(wb, mytname, rows = (1+startrow), heights = c(28))
       setRowHeights(wb, mytname, rows = (2+startrow), heights = c(38))
       setRowHeights(wb, mytname,
                     rows = (3+startrow):(nrow(OutputDataSet)+2+startrow),
                     heights = c(20))

       addStyle(wb, sheet = 1,
                style = createStyle(
                  border = c("top","bottom","left","right"),
                  halign = "center",
                  valign = "center"),
                rows = (1+startrow):(nrow(OutputDataSet)+2+startrow),
                cols = 1:(ncol(OutputDataSet)),
                gridExpand= TRUE, stack=TRUE)

       # Column background styling
       addStyle(wb, sheet = 1,
                style = createStyle(fgFill = "#daeef3"),
                rows = (1+startrow):(nrow(OutputDataSet)+2+startrow),
                cols = 1L, stack=TRUE)

       addStyle(wb, sheet = 1,
                style = createStyle(fgFill = "#daeef3"),
                rows = (1+startrow):(nrow(OutputDataSet)+2+startrow),
                cols = 10L, stack=TRUE)

       # Header rows
       addStyle(wb, sheet = 1,
                style = createStyle(fgFill = "#00b0f0", textDecoration="bold"),
                rows = (1+startrow),
                cols = 1:(ncol(OutputDataSet)), stack=TRUE)

       addStyle(wb, sheet = 1,
                style = createStyle(fgFill = "#538dd5",
                                    fontColour="#FFFFFF",
                                    textDecoration="bold",
                                    wrapText = TRUE),
                rows = (2+startrow),
                cols = 1:(ncol(OutputDataSet)), stack=TRUE)

       addStyle(wb, sheet = 1,
                style = createStyle(textRotation = 90),
                rows = (2+startrow), cols = 1, stack=TRUE)

       # Merge and image
       mergeCells(wb, sheet = 1, cols = 1:10, rows = 1)
       insertImage(wb, sheet = 1, "e:\\\\Template\\\\logo.png",
                   width = 1.9, height = 0.7, startRow = 1, startCol = 5.5)

       addStyle(wb, sheet = 1,
                style = createStyle(
                  border = c("top","bottom","left","right"),
                  halign = "center",
                  valign = "center"),
                rows = 1, cols = 1:(ncol(OutputDataSet)),
                stack=TRUE)

       mergeCells(wb, sheet = 1, cols = 1:10, rows = (1+startrow))

       y <- "وضعیت قطعی ارتباط شبکه شعب (عدم سرویس‌دهی شعب به مشتریان) در تاریخ "
       y <- paste(y, fulldate, sep="")

       writeData(wb, mytname, OutputDataSet, xy=c(1,2+startrow))
       writeData(wb, mytname, y, xy=c(1,1+startrow))

       for (i in 1:nrow(OutputDataSet)) {
         if(!str_contains(OutputDataSet[i,10], "در حال")) {
           addStyle(wb, sheet = 1,
                    style = createStyle(fgFill = "#FFFF00"),
                    rows = (i+2+startrow), cols = 10L, stack=TRUE)
         }
       }

       saveWorkbook(wb,
         file = paste(paste("e:\\\\ReportArchive\\\\GhateiShoab\\\\",
                            mytname, sep=""), ".xlsx", sep=""),
         overwrite = TRUE);
    ';

    DECLARE @sqlscript NVARCHAR(MAX) = N'SELECT * FROM Temp';

    EXEC sp_execute_external_script
        @language = N'R',
        @script = @rscript,
        @input_data_1 = @sqlscript,
        @input_data_1_name = N'SqlData',
        @params = N'@mytname nvarchar(20), @fulldate nvarchar(50)',
        @mytname = @FileName,
        @fulldate = @FullDate;
END;
GO
```

### 8.2 Create SQL Agent Job

```sql
-- Script 2 (Reporting Server)
-- =============================================
-- Author: <A.Momen>
-- Email: <amomen@gmail.com>
-- =============================================

USE [msdb];
GO

BEGIN TRANSACTION;
DECLARE @ReturnCode INT = 0;
DECLARE @jobId BINARY(16);

IF NOT EXISTS (
    SELECT name FROM msdb.dbo.syscategories
    WHERE name = N'[Uncategorized (Local)]' AND category_class = 1
)
BEGIN
    EXEC @ReturnCode = msdb.dbo.sp_add_category
        @class = N'JOB', @type = N'LOCAL',
        @name = N'[Uncategorized (Local)]';
    IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;
END

EXEC @ReturnCode = msdb.dbo.sp_add_job
    @job_name = N'GhateiShoab',
    @enabled = 1,
    @notify_level_eventlog = 0,
    @notify_level_email = 2,
    @notify_level_netsend = 0,
    @notify_level_page = 0,
    @delete_level = 0,
    @description = N'No description available.',
    @category_name = N'[Uncategorized (Local)]',
    @owner_login_name = N'RSL',
    @notify_email_operator_name = N'momen-a',
    @job_id = @jobId OUTPUT;
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

-- Step 1: Data retrieval, preprocessing, and Excel generation
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep
    @job_id = @jobId,
    @step_name = N'1',
    @step_id = 1,
    @on_success_action = 3,
    @on_fail_action = 2,
    @retry_attempts = 3,
    @retry_interval = 1,
    @subsystem = N'TSQL',
    @database_name = N'Report',
    @command = N'
USE Report;
DROP TABLE IF EXISTS Temp;

SELECT * INTO Temp2
FROM OPENQUERY([<`BHDB Server` IP>], ''SELECT * FROM [WhatsUp].[rep].GhateiShoab()'');

DECLARE @set INT;
DECLARE @counter INT = 1;
DECLARE @SaatS TIME;
DECLARE @SaatP TIME;

SELECT @set = COUNT(*) FROM Temp2;

WHILE @counter < @set
BEGIN
    SELECT @SaatS = [زمان شروع] FROM Temp2 WHERE [ردیف] = @counter;
    SELECT @SaatP = [زمان پایان] FROM Temp2 WHERE [ردیف] = @counter;

    DELETE FROM Temp2
    WHERE [ردیف] > @counter AND [زمان پایان] = @SaatP;

    SET @counter = @counter + 1;
END;

SELECT ROW_NUMBER() OVER (ORDER BY [زمان شروع]) AS [ردیف],
       [نام شعبه],
       [استان],
       [کد مهرگستر شعبه],
       [لینکهای شعبه جدید],
       [تاریخ شروع],
       [زمان شروع],
       [زمان پایان],
       [مدت زمان قطعی به ساعت / دقیقه / ثانیه],
       [وضعیت]
INTO Temp
FROM Temp2;

DROP TABLE Temp2;

EXECUTE sp_save_excel_ghatei;
',
    @output_file_name = N'E:\Log\Job\OutputFile.log',
    @flags = 20;
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

-- Step 2: Email dispatch
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep
    @job_id = @jobId,
    @step_name = N'2',
    @step_id = 2,
    @subsystem = N'TSQL',
    @database_name = N'Report',
    @on_success_action = 1,
    @on_fail_action = 2,
    @command = N'
DECLARE @MailBody NVARCHAR(MAX);
DECLARE @DayofWeek INT = DATEPART(WEEKDAY, GETDATE());
DECLARE @DayofWeekPersian NVARCHAR(10);
DECLARE @FileName NVARCHAR(MAX);
DECLARE @DatePersian NVARCHAR(20);
DECLARE @subject NVARCHAR(MAX);
DECLARE @FilePath NVARCHAR(MAX);
DECLARE @recipients NVARCHAR(MAX);

SELECT @DayofWeekPersian =
    CASE
        WHEN @DayofWeek = 7 THEN N''شنبه''
        WHEN @DayofWeek = 1 THEN N''یکشنبه''
        WHEN @DayofWeek = 2 THEN N''دوشنبه''
        WHEN @DayofWeek = 3 THEN N''سه شنبه''
        WHEN @DayofWeek = 4 THEN N''چهارشنبه''
        WHEN @DayofWeek = 5 THEN N''پنج شنبه''
        WHEN @DayofWeek = 6 THEN N''جمعه''
    END;

SELECT @DatePersian =
 (SELECT * FROM OPENQUERY([<`BHDB Server` IP>],
   ''SELECT [WhatsUp].[dbo].SolarDate(GetDate())''));

SET @MailBody = N''<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>گزارش روزانه وضعیت قطعی ارتباط شبکه شعب (عدم سرویس‌دهی شعب به مشتریان)</title>
</head>
<body style="font-family:B Nazanin; color:#000;">
<p dir="RTL" style="font-size:22px;"><b>با سلام و احترام</b></p>
<p dir="RTL" style="font-size:20px;">به پیوست گزارش روزانه وضعیت قطعی ارتباط شبکه شعب (عدم سرویس‌دهی شعب به مشتریان) در روز '' + @DayofWeekPersian + N'' مورخه <span dir="LTR">'' + @DatePersian + N''</span> جهت استحضار حضورتان ارسال می‌گردد.</p>
<p dir="RTL" style="font-size:20px;">مرکز خدمات پشتیبانی <b>NOC</b></p>
</body>
</html>''';

SET @subject = N''گزارش روزانه وضعیت قطعی ارتباط شبکه شعب (عدم سرویس‌دهی شعب به مشتریان) در ''
               + @DayofWeekPersian + N'' مورخ '' + @DatePersian;

SET @FileName = REPLACE(@DatePersian, N''/'', N''.'') + N''.xlsx'';
SET @FilePath = N''e:\ReportArchive\GhateiShoab\'' + @FileName;

SET @recipients = N''noc@agri-bank.com'';

EXEC msdb.dbo.sp_send_dbmail
    @profile_name = N''DBEmail3'',
    @body = @MailBody,
    @body_format = N''HTML'',
    @recipients = @recipients,
    @subject = @subject,
    @file_attachments = @FilePath;
',
    @output_file_name = N'E:\Log\Job\OutputFile2.log',
    @flags = 20;
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

EXEC @ReturnCode = msdb.dbo.sp_update_job
    @job_id = @jobId, @start_step_id = 1;
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

-- Schedule: Thursday 13:00
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule
    @job_id = @jobId,
    @name = N'13Recurring',
    @enabled = 1,
    @freq_type = 8,
    @freq_interval = 16,
    @freq_recurrence_factor = 1,
    @active_start_date = 20210116,
    @active_end_date = 99991231,
    @active_start_time = 130000;
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

-- Schedule: Saturday–Wednesday 14:30
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule
    @job_id = @jobId,
    @name = N'14:30Recurring',
    @enabled = 1,
    @freq_type = 8,
    @freq_interval = 79,
    @freq_recurrence_factor = 1,
    @active_start_date = 20210108,
    @active_end_date = 99991231,
    @active_start_time = 143000;
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

-- Disabled test schedule
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule
    @job_id = @jobId,
    @name = N'test',
    @enabled = 0,
    @freq_type = 8,
    @freq_interval = 127,
    @freq_recurrence_factor = 1,
    @active_start_date = 20210116,
    @active_end_date = 99991231,
    @active_start_time = 123000;
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

EXEC @ReturnCode = msdb.dbo.sp_add_jobserver
    @job_id = @jobId,
    @server_name = N'(local)';
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

COMMIT TRANSACTION;
GOTO EndSave;

QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
EndSave:
GO
```

> To change the email body or subject later:
> - Modify the `@MailBody` HTML block for content.
> - Modify the `@subject` assignment line for subject wording.

### 8.3 Configure Database Mail

```sql
-- Script 3 (Reporting Server)
-- =============================================
-- Author: <A.Momen>
-- Email: <amomen@gmail.com>
-- =============================================

DECLARE
    @profile_name SYSNAME,
    @account_name SYSNAME,
    @SMTP_servername SYSNAME,
    @email_address NVARCHAR(128),
    @display_name NVARCHAR(128),
    @user_name NVARCHAR(50),
    @pass NVARCHAR(50);

SET @profile_name    = 'DBEmail3';
SET @account_name    = 'NOC WAN';
SET @SMTP_servername = 'mail.agri-bank.com';
SET @email_address   = 'report.sending.email@company.com';
SET @display_name    = 'NOC WAN';
SET @user_name       = 'noc-wan';
SET @pass            = 'NOC-wan';

IF EXISTS (SELECT * FROM msdb.dbo.sysmail_profile WHERE name = @profile_name)
BEGIN
    RAISERROR('The specified Database Mail profile (DBEmail3) already exists.', 16, 1);
    GOTO done;
END;

IF EXISTS (SELECT * FROM msdb.dbo.sysmail_account WHERE name = @account_name)
BEGIN
    RAISERROR('The specified Database Mail account (report.sending.email@company.com) already exists.', 16, 1);
    GOTO done;
END;

BEGIN TRANSACTION;
DECLARE @rv INT;

EXEC @rv = msdb.dbo.sysmail_add_account_sp
    @account_name  = @account_name,
    @email_address = @email_address,
    @display_name  = @display_name,
    @mailserver_name = @SMTP_servername,
    -- @port = 465,
    -- @enable_ssl = 1,
    @username = @user_name,
    @password = @pass;
IF @rv <> 0
BEGIN
    RAISERROR('Failed to create the specified Database Mail account (report.sending.email@company.com).', 16, 1);
    GOTO done;
END;

EXEC @rv = msdb.dbo.sysmail_add_profile_sp
    @profile_name = @profile_name;
IF @rv <> 0
BEGIN
    RAISERROR('Failed to create the specified Database Mail profile (DBEmail3).', 16, 1);
    ROLLBACK TRANSACTION;
    GOTO done;
END;

EXEC @rv = msdb.dbo.sysmail_add_profileaccount_sp
    @profile_name = @profile_name,
    @account_name = @account_name,
    @sequence_number = 1;
IF @rv <> 0
BEGIN
    RAISERROR('Failed to associate the specified profile with the specified account (report.sending.email@company.com).', 16, 1);
    ROLLBACK TRANSACTION;
    GOTO done;
END;

COMMIT TRANSACTION;
done:
GO
```

### 8.4 Create Linked Server to `BHDB Server`

```sql
-- Script 4 (Reporting Server)
-- =============================================
-- Author: <A.Momen>
-- Email: <amomen@gmail.com>
-- =============================================

USE [master];
GO

EXEC master.dbo.sp_addlinkedserver
    @server = N'<`BHDB Server` IP>',
    @srvproduct = N'SQL Server';

EXEC master.dbo.sp_addlinkedsrvlogin
    @rmtsrvname = N'<`BHDB Server` IP>',
    @useself = N'False',
    @locallogin = NULL,
    @rmtuser = N'RSL',
    @rmtpassword = 'Kesh@v@rz!NoC33admin';

EXEC master.dbo.sp_addlinkedsrvlogin
    @rmtsrvname = N'<`BHDB Server` IP>',
    @useself = N'False',
    @locallogin = N'RSL',
    @rmtuser = N'RSL',
    @rmtpassword = 'Kesh@v@rz!NoC33admin';
GO

EXEC master.dbo.sp_serveroption @server=N'<`BHDB Server` IP>', @optname=N'collation compatible', @optvalue=N'false';
EXEC master.dbo.sp_serveroption @server=N'<`BHDB Server` IP>', @optname=N'data access', @optvalue=N'true';
EXEC master.dbo.sp_serveroption @server=N'<`BHDB Server` IP>', @optname=N'dist', @optvalue=N'false';
EXEC master.dbo.sp_serveroption @server=N'<`BHDB Server` IP>', @optname=N'pub', @optvalue=N'false';
EXEC master.dbo.sp_serveroption @server=N'<`BHDB Server` IP>', @optname=N'rpc', @optvalue=N'true';
EXEC master.dbo.sp_serveroption @server=N'<`BHDB Server` IP>', @optname=N'rpc out', @optvalue=N'true';
EXEC master.dbo.sp_serveroption @server=N'<`BHDB Server` IP>', @optname=N'sub', @optvalue=N'false';
EXEC master.dbo.sp_serveroption @server=N'<`BHDB Server` IP>', @optname=N'connect timeout', @optvalue=N'0';
EXEC master.dbo.sp_serveroption @server=N'<`BHDB Server` IP>', @optname=N'collation name', @optvalue=NULL;
EXEC master.dbo.sp_serveroption @server=N'<`BHDB Server` IP>', @optname=N'lazy schema validation', @optvalue=N'false';
EXEC master.dbo.sp_serveroption @server=N'<`BHDB Server` IP>', @optname=N'query timeout', @optvalue=N'0';
EXEC master.dbo.sp_serveroption @server=N'<`BHDB Server` IP>', @optname=N'use remote collation', @optvalue=N'true';
EXEC master.dbo.sp_serveroption @server=N'<`BHDB Server` IP>', @optname=N'remote proc transaction promotion', @optvalue=N'true';
GO
```

---

## 9. Adjusting Job Schedules (SSMS GUI)

1. In `Object Explorer`, expand:
   - `SQL Server Agent` → `Jobs`.
2. Right-click the job `GhateiShoab` → `Properties`.
3. Go to the `Schedules` page.
4. To add a new schedule: Click `New`.
5. To edit an existing schedule: Select it → `Edit`.
6. Save changes.

---

## 10. Troubleshooting Job Failures

1. Open `SQL Server Agent` → `Jobs`.
2. If the job icon shows a red X ❌ it failed; green check ✅ means success.
3. Right-click the job → `View History`.
4. Use the log viewer to inspect step details (e.g., missing file, permission issue, R execution failure).

---

## 11. File System Preparation

1. Create drive `E:` (ensure it exists; may be mounted from a VHD).
2. Create directory:
   ```
   E:\ReportArchive\GhateiShoab
   ```
3. Create:
   ```
   E:\Template
   ```
   Place the bank logo file as:
   ```
   E:\Template\logo.png
   ```

4. Right-click drive `E:` → `Properties` → `Security` tab:
   - Add principals:
     - `Everyone`
     - `ALL APPLICATION PACKAGES`
   - Grant Full Control (ensure inheritance remains enabled).
   - This enables `SQL Server` service account to write Excel files.

---

## 12. Post-Restart Actions (Reporting Server `<Reporting Server IP>`)

After a system restart:

1. Navigate to `D:` and locate `Report.vhd`.  
   - Double-click to mount it.  
   - Confirm that `E:` reappears and contains the expected folders.

2. Open Windows Start Menu → type `Configuration` → run `SQL Server 2019 Configuration Manager`.

3. Ensure required services are `Running`:
   - `SQL Server (MSSQLSERVER)`
   - `SQL Server Agent (MSSQLSERVER)`
   - `SQL Server Launchpad (MSSQLSERVER)` (for external scripts)
   - `SQL Server Browser` (if used)

---

## 13. Archive Location

Historical Excel reports are stored at:

```
E:\ReportArchive\GhateiShoab
```

or via UNC path:

```
\\<Reporting Server IP>\E$\ReportArchive\GhateiShoab
```

---

## 14. Notes

- No `Microsoft Office` installation is required on the Reporting Server; Excel files are generated via the `openxlsx` `R` package.
- All usernames and passwords in this document reflect the current (original) system configuration.
- Full execution sequence of scripts is required for initial provisioning.
- The `R` external script execution depends on `SQL Server Launchpad` service being active.

---

## 15. Script Package

A compressed archive containing all referenced scripts:

```
NOC_Reporting.rar
```

Naming conventions:
- `5133` → `Reporting Server`
- `5131` → `BHDB Server`
- `<Branch List Server IP>` → `Branch List Server` (current)

---

## 16. Summary Checklist ✅

| Step | Action | Status (to fill) |
|------|--------|------------------|
| 1 | Enable `R` in SQL setup |  |
| 2 | Install & export R packages |  |
| 3 | Copy `library` to Reporting Server |  |
| 4 | Create function on BHDB |  |
| 5 | Create login `RSL` |  |
| 6 | Execute dependency scripts |  |
| 7 | Create Linked Server(s) |  |
| 8 | Create `Report` DB & procedure |  |
| 9 | Create SQL Agent Job |  |
| 10 | Configure Database Mail |  |
| 11 | Create folders & permissions |  |
| 12 | Add logo image |  |
| 13 | Test manual job run |  |
| 14 | Verify email received |  |
| 15 | Validate archive creation |  |

---

## 17. Example Manual Test

```sql
-- Optional: Manually test job steps
EXEC msdb.dbo.sp_start_job @job_name = N'GhateiShoab';
GO
```

---

> End of Document.