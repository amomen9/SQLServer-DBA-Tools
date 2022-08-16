/****** Script for SelectTopNRows command from SSMS  ******/
SELECT [__$start_lsn]
      ,[__$end_lsn]
      ,[__$seqval]
      ,[__$operation]
      ,[__$update_mask]
      ,[OrderID]
      ,[CustomerID]
      ,[EmployeeID]
      ,[OrderDate]
      ,[RequiredDate]
      ,[ShippedDate]
      ,[ShipVia]
      ,[Freight]
      ,[ShipName]
      ,[ShipAddress]
      ,[ShipCity]
      ,[ShipRegion]
      ,[ShipPostalCode]
      ,[ShipCountry]
      ,[__$command_id]
  FROM [Northwind].[cdc].[dbo_Orders_CT]


  USE [MyTemp]
GO


USE [MyTemp]
GO

SELECT [__$start_lsn]
      ,[__$operation]
      ,[__$update_mask]
      ,[OrderID]
      ,[CustomerID]
      ,[EmployeeID]
      ,[OrderDate]
      ,[RequiredDate]
      ,[ShippedDate]
      ,[ShipVia]
      ,[Freight]
      ,[ShipName]
      ,[ShipAddress]
      ,[ShipCity]
      ,[ShipRegion]
      ,[ShipPostalCode]
      ,[ShipCountry]
      ,[__$command_id]
      ,[__$reprocessing]
  FROM [dbo].[OLE DB Destination]

GO

USE [ETL_Settings]
GO

SELECT [name]
      ,[state]
  FROM [dbo].[cdc_states]

GO

TRUNCATE TABLE dbo.Inserted_Orders
TRUNCATE TABLE dbo.Inserted_OrderDetails
TRUNCATE TABLE dbo.Updated_OrderDetails
TRUNCATE TABLE dbo.Updated_Orders
TRUNCATE TABLE dbo.Deleted_OrderDetails
TRUNCATE TABLE dbo.Deleted_Orders