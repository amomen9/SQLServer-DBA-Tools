------ First creating Northwind anew
use master
go

EXECUTE sp_execute_external_tsql @InputFiles = N'"%userprofile%\Dropbox\learning\SQL SERVER\InstNwnd.sql"' -- Delimited by a semicolon (;), executed by given order, enter the files which their path contains space within double quotations. Use full path or if not, relative paths must be relative to %systemroot%\system32
                                     ,@InputFolder = ''	-- This sp executes every *.sql script that finds within the specified folder path. Quote addresses that contain space within double quotations.
                                     ,@Server = NULL
                                     ,@AuthenticationType = NULL -- any value which does not include the word 'sql' means Windows Authentication
                                     ,@UserName = NULL
                                     ,@Password = NULL
                                     ,@DefaultDatabase = NULL
                                     ,@Keep_xp_cmdshell_Enabled = 0
                                     ,@isDAC = 0	-- run files with Dedicated Admin Connection
--SELECT * FROM sys.configurations WHERE name = 'xp_cmdshell'

alter database Northwind set recovery full

use northwind 
go

------ create schema Sales
CREATE SCHEMA Sales
GO

ALTER SCHEMA Sales TRANSFER dbo.Customers
GO

ALTER SCHEMA Sales TRANSFER dbo.Orders
GO

ALTER SCHEMA Sales TRANSFER dbo.[Order Details]
GO

ALTER SCHEMA Sales TRANSFER dbo.[Products]
GO

------ create schema HR
CREATE SCHEMA HR
GO

ALTER SCHEMA HR TRANSFER dbo.Employees
GO

------ create filegroups
USE [master]
GO
ALTER DATABASE [Northwind] ADD FILEGROUP [Archive]
GO
ALTER DATABASE [Northwind] ADD FILE ( NAME = N'Northwind_Archive$1', FILENAME = N'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\Northwind_Archive$1.ndf' , SIZE = 8192KB , FILEGROWTH = 65536KB ) TO FILEGROUP [Archive]
GO
ALTER DATABASE [Northwind] ADD FILEGROUP [HR]
GO
ALTER DATABASE [Northwind] ADD FILE ( NAME = N'Northwind_HR$1', FILENAME = N'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\Northwind_HR$1.ndf' , SIZE = 8192KB , FILEGROWTH = 65536KB ) TO FILEGROUP [HR]
GO
ALTER DATABASE [Northwind] ADD FILEGROUP [Sales]
GO
ALTER DATABASE [Northwind] ADD FILE ( NAME = N'Northwind_Sales$1', FILENAME = N'E:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\Northwind_Sales$1.ndf' , SIZE = 8192KB , FILEGROWTH = 65536KB ) TO FILEGROUP [Sales]
GO

------ move tables to filegroups (clustered and non-clustered indexes)
USE Northwind
GO

CREATE UNIQUE CLUSTERED INDEX PK_Orders ON Sales.Orders (OrderID)  
    WITH (DROP_EXISTING = ON, FILLFACTOR = 80 , ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, ONLINE = ON, STATISTICS_NORECOMPUTE = ON, STATISTICS_INCREMENTAL = ON)
    ON Sales

CREATE NONCLUSTERED INDEX CustomerID ON Sales.Orders (CustomerID)  
    WITH (DROP_EXISTING = ON)  
    ON Sales

------ Generate new data

insert into Sales.Orders
	(
		
      [CustomerID]
      ,[EmployeeID]
      ,[OrderDate]
      ,[RequiredDate]
      ,[ShippedDate]
      ,[ShipVia]
      ,[Freight]
      ,[ShipName]
      ,[ShipAddress]
      ,[ShipCity]      
      ,[ShipPostalCode]
      ,[ShipCountry]
	  )
  VALUES ('ALFKI',3,getdate(),getdate(),getdate(),1,25.15,'Alfreds Futterkiste','Obere Str. 57','Berlin',12209,'Germany'),
		 ('ALFKI',3,getdate(),getdate(),getdate(),1,25.15,'Alfreds Futterkiste','Obere Str. 57','Berlin',12209,'Germany')

Go 5

------ create Orders_partitioned table

drop table if exists sales.Orders_partitioned
select * into sales.Orders_partitioned on Sales
from sales.orders

alter table sales.Orders_partitioned
add OrderYear AS isnull(year(OrderDate),0) persisted
GO

------ create partitions
use northwind
go

if (SELECT name FROM sys.partition_schemes where name = 'Orders_PS') is not null
	DROP PARTITION SCHEME Orders_PS
if (SELECT name FROM sys.partition_functions where name = 'Orders_PF') is not null
	DROP PARTITION FUNCTION Orders_PF
GO

CREATE PARTITION FUNCTION [Orders_PF](int) AS RANGE LEFT FOR VALUES (1998, 2021)

GO

CREATE PARTITION SCHEME [Orders_PS] AS PARTITION [Orders_PF] TO ([Archive], [Sales], [Sales])
GO

ALTER TABLE [Sales].[Orders_Partitioned] ADD  CONSTRAINT [PK_Orders_Partitioned] PRIMARY KEY CLUSTERED 
(OrderYear, OrderID) ON Orders_PS(OrderYear)

GO

CREATE NONCLUSTERED INDEX [IX_Orders_Partitioned_CustomerID] ON [Sales].[Orders_Partitioned]
(
	[CustomerID] ASC
) ON Orders_PS(OrderYear)

------ check indexes' partitions

use northwind
go

SELECT o.[name] AS TableName, i.[name] AS IndexName, fg.[name] AS FileGroupName
FROM sys.indexes i
INNER JOIN sys.filegroups fg ON i.data_space_id = fg.data_space_id
INNER JOIN sys.all_objects o ON i.[object_id] = o.[object_id]
WHERE i.data_space_id = fg.data_space_id AND o.type = 'U' and o.[name] = 'Orders_partitioned'

------ set filegroup as read-only

use northwind
go

declare @readonly bit
SELECT @readonly=convert(bit, (status & 0x08)) FROM sysfilegroups WHERE groupname=N'Archive'
if(@readonly=0)
begin
	alter database Northwind set single_user with rollback immediate 
	ALTER DATABASE [Northwind] MODIFY FILEGROUP [Archive] READONLY
	alter database Northwind set MULTI_USER
end
GO

------ check filegroup 'Archive' status

use northwind
go

select is_read_only from sys.database_files where name = 'Northwind_Archive$1'

update  Sales.Orders_partitioned
set ShipCity = N'Tehran'
where OrderID = 10250
go
-- Error occurs

update  Sales.Orders_partitioned
set ShipCity = N'Zanjan'
where OrderID = 11078
-- Success!!! The record resides on the writable table partition (OrderYear>1998)

------ Now performing a full backup

DECLARE @Backup_Destination NVARCHAR(1000) = N'e:\backup\test_read-only\'
EXEC xp_create_subdir @Backup_Destination
DECLARE @Backup_Path NVARCHAR(1000) = @Backup_Destination + 'NW_Full_backup_0240.bak'

backup database northwind to disk=@Backup_Path with init, checksum
-- size: 1,292 KB



/*
For educational purposes:





------ performing backup of the read-only filegroup

BACKUP DATABASE [Northwind] FILEGROUP = N'Archive' TO  DISK = N'e:\Backup\test_read-only\NW_FG-Archive_Full_0244.bak'  WITH INIT, checksum
-- size: 192 KB

------ Generating some workload on the modifiable part of the database

UPDATE Sales.Customers
set City = N'Tehran'
go

insert into sales.[order details]
	(	
		[OrderID]
      ,[ProductID]
      ,[UnitPrice]
      ,[Quantity]
      ,[Discount]
	)
	values  (11087,1,100,5,0),
			(11087,2,100,5,0),
			(11087,3,100,5,0),
			(11087,4,100,5,0),
			(11087,5,100,5,0),
			(11087,6,100,5,0),
			(11087,7,100,5,0),
			(11087,8,100,5,0),
			(11087,9,100,5,0),
			(11087,10,100,5,0),
			(11087,11,100,5,0),
			(11087,12,100,5,0),
			(11087,13,100,5,0),
			(11087,14,100,5,0),
			(11087,15,100,5,0),
			(11087,16,100,5,0),
			(11087,17,100,5,0),
			(11087,18,100,5,0)
go 
  
------ partial backup from only read-write filegroups

BACKUP DATABASE Northwind READ_WRITE_FILEGROUPS TO DISK = N'e:\backup\test_read-only\NW_readwrite_0316.bak' with init, checksum
-- size: 1,112 KB

------ performing Log backup

use master
go

backup log Northwind to disk = N'e:\backup\test_read-only\NW_Log_1045.trn' with init, checksum , norecovery

------ Restore only read-write filegroups always containing PRIMARY filegroup

restore database Northwind from disk = N'e:\backup\test_read-only\NW_readwrite_0316.bak' with norecovery
-- Success!!!

------ restore read-only filegroup

RESTORE DATABASE Northwind FILE='Northwind_Archive$1' FROM DISK=N'e:\Backup\test_read-only\NW_FG-Archive_Full_0244.bak' with norecovery
-- Success!!!

------ restoring log backup

RESTORE LOG [Northwind] FROM  DISK = N'e:\Backup\test_read-only\NW_Log_1045.trn'

------ now dropping the database

use master
go
alter database northwind set single_user with rollback immediate
drop database northwind


------ restoring read-write only
restore database Northwind FILEGROUP='primary',FILEGROUP='HR', FILEGROUP='sales' from disk = N'e:\backup\test_read-only\NW_readwrite_0316.bak' with norecovery
-- Success!!! but the table Sales.Orders_partitioned is not accessible because file group 'Archive'
-- is not yet restored

RESTORE LOG [Northwind] FROM  DISK = N'e:\Backup\test_read-only\NW_Log_1045.trn'

------ restoring read-only filegroup
RESTORE DATABASE Northwind FILE='Northwind_Archive$1' FROM DISK=N'e:\Backup\test_read-only\NW_FG-Archive_Full_0244.bak'
-- Success!!! now sales.orders_partitioned is accessible. It is not possible to restore read-only backup before 
--read-write backup when the database does not exist.
GO

*/