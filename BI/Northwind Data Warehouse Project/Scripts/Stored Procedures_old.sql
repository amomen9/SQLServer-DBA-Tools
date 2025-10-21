-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2022-05-10"
-- Description:         "Stored Procedures_old"
-- License:             "Please refer to the license file"
-- =============================================





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
  FROM [dbo].[V_FactOrders]



SELECT [OrderID]
      ,[DateKey]--
      ,[CustomerKey]-- H --> Country
      ,[EmployeeKey]--
      ,[ShipperKey]--
      ,[ProductKey]-- H --> SupplierID
      ,[Freight]
      ,[UnitPrice]
      ,[Quantity]
      ,[SalesAmount]
      ,[DiscountAmount]
      ,[NetSalesAmount]
  FROM [dbo].[FactSale]

GO

--------- CustomerKeyLookup ------------------------------------------------------------------------------------------------------------------

CREATE OR ALTER PROC CustomerKeyLookup
	@CustomerID NCHAR(5),
	@OrderDate DATETIME,
	@CustomerKey int out
AS
BEGIN
	
	DECLARE @Country NVARCHAR(15)	
	SELECT @Country = Country FROM Northwind..Customers WHERE CustomerID = @CustomerID

	CREATE TABLE #temp(CustomerKey int NOT NULL, CustomerID NCHAR(5) NOT NULL, StartDate DATETIME NOT NULL, EndDate DATETIME, Country NVARCHAR(15))
	INSERT #temp
	(
	    CustomerKey,
		CustomerID,
	    StartDate,
	    EndDate,
	    Country
	)
	SELECT CustomerKey, CustomerID, StartDate, EndDate, Country
	FROM dbo.DimCustomers
	WHERE CustomerID = @CustomerID

	ALTER TABLE #temp ADD CONSTRAINT PK_temp PRIMARY KEY (CustomerKey, CustomerID)

	DECLARE @MinDimDate DATETIME = (SELECT StartDate FROM #temp WHERE CustomerKey=(SELECT MIN(CustomerKey) FROM #temp))
	DECLARE @DimEntityState TINYINT		-- 0|1|2	0: Dimension entity does not exist
										--			1: Dimension entity exists but its historical attribute for the current @ID has chnaged
										--			2: Dimension entity exists with the same historical attribute as the current @ID
	SELECT @OrderDate = IIF(@MinDimDate>@OrderDate, @MinDimDate,@OrderDate)
	SELECT @DimEntityState = CASE 
									WHEN @MinDimDate IS NULL THEN 0	-- Does not exist
									WHEN (SELECT COUNT(*) FROM #temp WHERE @OrderDate BETWEEN StartDate AND ISNULL(EndDate,DATEADD(YEAR,100,GETDATE())) AND Country=@Country) = 0 THEN 1	-- Exists with different identity
									ELSE 2		-- Exists like before
							 END
	
	

	----- Fill inferred record
	IF @DimEntityState = 2
	BEGIN
		SELECT @CustomerKey = CustomerKey 
		FROM #temp
		WHERE CustomerID = @CustomerID
				AND @OrderDate BETWEEN StartDate AND ISNULL(EndDate,DATEADD(YEAR,100,GETDATE()))
				AND Country=@Country
	
    END
	ELSE
		IF @DimEntityState = 0
		BEGIN
		
			INSERT dbo.DimCustomers
			(
				CustomerID,
				CompanyName,
				Country,
				CurrentCountry,
				StartDate,
				EndDate
			)
			SELECT
				@CustomerID,
				CompanyName,
				@Country,
				@Country,
				GETDATE(),
				NULL
			FROM Northwind..Customers
			WHERE CustomerID=@CustomerID
			SELECT @CustomerKey = SCOPE_IDENTITY()
		END
		ELSE
		BEGIN
			UPDATE dbo.DimCustomers
			SET CurrentCountry = @Country
			WHERE CustomerID = @CustomerID

			UPDATE dbo.DimCustomers
			SET EndDate = GETDATE()
			WHERE CustomerID = @CustomerID
					AND EndDate IS NULL

			INSERT dbo.DimCustomers
			(
				CustomerID,
				CompanyName,
				Country,
				CurrentCountry,
				StartDate,
				EndDate
			)
			SELECT
				@CustomerID,
				CompanyName,
				@Country,
				@Country,
				GETDATE(),
				NULL
			FROM Northwind..Customers
			WHERE CustomerID=@CustomerID
			SELECT @CustomerKey = SCOPE_IDENTITY()

        END
			
	
END
GO

------------ ProductKeyLookup ----------------------------------------------------------------------------------------------
--#
CREATE OR ALTER PROC ProductKeyLookup
	@ProductID NCHAR(5),
	@OrderDate DATETIME,
	@ProductKey int out
AS
BEGIN
	DECLARE @SupplierID NVARCHAR(15)	
	SELECT @SupplierID = SupplierID FROM Northwind..Products WHERE ProductID = @ProductID 

	CREATE TABLE #temp(ProductKey INT NOT NULL, ProductID INT NOT NULL, StartDate DATETIME NOT NULL, EndDate DATETIME, SupplierID int)
	INSERT #temp
	(
	    ProductKey,
		ProductID,
	    StartDate,
	    EndDate,
	    SupplierID
	)
	SELECT ProductKey, ProductID, StartDate, EndDate, SupplierID
	FROM dbo.DimProduct
	WHERE ProductID = @ProductID

	ALTER TABLE #temp ADD CONSTRAINT PK_temp PRIMARY KEY (ProductKey, ProductID)

	DECLARE @MinDimDate DATETIME = (SELECT StartDate FROM #temp WHERE ProductKey=(SELECT MIN(ProductKey) FROM #temp))
	DECLARE @DimEntityState TINYINT			-- 0|1|2	0: Dimension entity does not exist
											--			1: Dimension entity exists but its historical attribute for the current @ID has chnaged
											--			2: Dimension entity exists with the same historical attribute as the current @ID
	SELECT @OrderDate = IIF(@MinDimDate>@OrderDate, @MinDimDate,@OrderDate)
	SELECT @DimEntityState = CASE 
									WHEN @MinDimDate IS NULL THEN 0	-- Does not exist
									WHEN (SELECT COUNT(*) FROM #temp WHERE @OrderDate BETWEEN StartDate AND ISNULL(EndDate,DATEADD(YEAR,100,GETDATE())) AND SupplierID=@SupplierID) = 0 THEN 1	-- Exists with different identity
									ELSE 2		-- Exists like before
							 END
	
	
	----- Fill inferred record
	IF @DimEntityState = 2
	BEGIN
		SELECT @ProductKey = ProductKey 
		FROM #temp
		WHERE ProductID = @ProductID
				AND @OrderDate BETWEEN StartDate AND ISNULL(EndDate,DATEADD(YEAR,100,GETDATE()))
				AND SupplierID=@SupplierID
	
    END
	ELSE
		IF @DimEntityState = 0
		BEGIN
		
			INSERT dbo.DimProduct
			(
				ProductID,
				ProductName,
				CategoryID,
				CategoryName,
				Status,
				SupplierID,
				StartDate,
				EndDate
			)
		
			SELECT
				@ProductId,
				cu.ProductName,
				cu.CategoryID,
				ca.CategoryName,
				CASE cu.Discontinued WHEN 1 THEN 'Inactive' ELSE 'Active' END,
				cu.SupplierID,
				GETDATE(),
				NULL
			FROM Northwind..Products cu
				JOIN Northwind..Categories ca
				ON ca.CategoryID = cu.CategoryID
			WHERE ProductID=@ProductId
			SELECT @ProductKey = SCOPE_IDENTITY()
		END
		ELSE
		BEGIN
			
			UPDATE dbo.DimProduct
			SET EndDate = GETDATE()
			WHERE ProductID = @ProductID
					AND EndDate IS NULL

			INSERT dbo.DimProduct
			(
				ProductID,
				ProductName,
				CategoryID,
				CategoryName,
				Status,
				SupplierID,
				StartDate,
				EndDate
			)
		
			SELECT
				@ProductId,
				cu.ProductName,
				cu.CategoryID,
				ca.CategoryName,
				CASE cu.Discontinued WHEN 1 THEN 'Inactive' ELSE 'Active' END,
				cu.SupplierID,
				GETDATE(),
				NULL
			FROM Northwind..Products cu
				JOIN Northwind..Categories ca
				ON ca.CategoryID = cu.CategoryID
			WHERE ProductID=@ProductId
			SELECT @ProductKey = SCOPE_IDENTITY()

        END
			
	
END
GO
--#

--CREATE OR ALTER PROC ProductKeyLookup
--	@ProductId int,
--	@OrderDate DATETIME,
--	@ProductKey int out
--AS
--BEGIN
--	DECLARE @MinDimDate DATETIME = (SELECT MIN(StartDate) FROM dbo.DimProduct)
--	SELECT @OrderDate = IIF(@MinDimDate>@OrderDate, @MinDimDate,@OrderDate)
--	SELECT TOP 1 @ProductKey = ProductKey 
--	FROM dbo.DimProduct
--	WHERE ProductID = @ProductId			
--			AND @OrderDate BETWEEN StartDate AND ISNULL(EndDate,DATEADD(YEAR,100,GETDATE()))
--	ORDER BY ProductKey
--	------ Fill inferred record
--	IF @ProductKey IS NULL
--	BEGIN

--		INSERT dbo.DimProduct
--		(
--		    ProductID,
--		    ProductName,
--		    CategoryID,
--		    CategoryName,
--		    Status,
--		    SupplierID,
--		    StartDate,
--		    EndDate
--		)
		
--		SELECT
--			@ProductId,
--			cu.ProductName,
--			cu.CategoryID,
--			ca.CategoryName,
--			CASE cu.Discontinued WHEN 1 THEN 'Inactive' ELSE 'Active' END,
--			cu.SupplierID,
--			GETDATE(),
--			NULL
--		FROM Northwind..Products cu
--			JOIN Northwind..Categories ca
--			ON ca.CategoryID = cu.CategoryID
--		WHERE ProductID=@ProductId
--		SELECT @ProductKey = SCOPE_IDENTITY()
--    END
--END
--GO

-------------- InsertInferredEmployee -------------------------------------------------------------------------------------------

CREATE OR ALTER PROC InsertInferredEmployee
	@EmployeeID int,
	@EmployeeKey INt OUT
AS
BEGIN
	INSERT dbo.DimEmployee
	(
	    EmployeeID,
	    FirstName,
	    LastName
	)
	SELECT
		@EmployeeID,
		FirstName,
		LastName
	FROM Northwind..Employees
	WHERE EmployeeID = @EmployeeID
	SELECT @EmployeeKey = SCOPE_IDENTITY()
END
GO


CREATE OR ALTER PROC InsertInferredShipper
	@ShipperID int,
	@ShipperKey INt OUT
AS
BEGIN
	INSERT dbo.DimShipper
	(
	    ShipperID,
	    CompanyName
	)
	SELECT
		@ShipperID,
		CompanyName
	FROM Northwind..Shippers
	WHERE ShipperID = @ShipperID
	SELECT @ShipperKey = SCOPE_IDENTITY()
END
GO
