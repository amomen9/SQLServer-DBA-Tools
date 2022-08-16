/****** Script for SelectTopNRows command from SSMS  ******/
SELECT [OrderID]
      ,[OrderDate]
      ,[CustomerID]
      ,[EmployeeID]
      ,[ProductID]
      ,[ShipVia]
      ,[Freight]
      ,[UnitPrice]
      ,[Quantity]
      ,[SalesAmount]
      ,[DiscountAmount]
      ,[NetSalesAmount]
  FROM [NorthwindDW2].[dbo].[V_FactOrders]

go
  USE [NorthwindDW2]
GO

SELECT [ProductKey]
      ,[ProductID]
      ,[ProductName]
      ,[CategoryID]
      ,[CategoryName]
      ,[Status]
      ,[SupplierID]
      ,[StartDate]
      ,[EndDate]
  FROM [dbo].[DimProduct]

GO

USE [NorthwindDW2]
GO

SELECT [OrderID]
      ,[DateKey]
      ,[CustomerKey]
      ,[EmployeeKey]
      ,[ShipperKey]
      ,[ProductKey]
      ,[Freight]
      ,[UnitPrice]
      ,[Quantity]
      ,[SalesAmount]
      ,[DiscountAmount]
      ,[NetSalesAmount]
  FROM [dbo].[FactSale]

GO

USE [ETL_Settings]
GO

SELECT [name]
      ,[state]
  FROM [dbo].[cdc_states]

GO

