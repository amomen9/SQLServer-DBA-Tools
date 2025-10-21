-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2022-05-12"
-- Description:         "DML"
-- License:             "Please refer to the license file"
-- =============================================



SELECT * FROM dbo.DimCustomers
UPDATE Northwind.dbo.Customers
SET Country='Iran'
WHERE CustomerID = 'AAAA1'



INSERT northwind.dbo.Customers
(
    CustomerID,
    CompanyName,
    ContactName,
    ContactTitle,
    Address,
    City,
    Region,
    PostalCode,
    Country,
    Phone,
    Fax
)
VALUES
(   N'AAAA1', -- CustomerID - nchar(5)
    N'All A', -- CompanyName - nvarchar(40)
    N'', -- ContactName - nvarchar(30)
    N'', -- ContactTitle - nvarchar(30)
    N'', -- Address - nvarchar(60)
    N'', -- City - nvarchar(15)
    N'', -- Region - nvarchar(15)
    N'', -- PostalCode - nvarchar(10)
    N'', -- Country - nvarchar(15)
    N'', -- Phone - nvarchar(24)
    N''  -- Fax - nvarchar(24)
)
DECLARE @id int
INSERT Northwind..Orders
(
    CustomerID,
    EmployeeID,
    OrderDate,
    RequiredDate,
    ShippedDate,
    ShipVia,
    Freight,
    ShipName,
    ShipAddress,
    ShipCity,
    ShipRegion,
    ShipPostalCode,
    ShipCountry
)
VALUES
(   N'AAAA1',       -- CustomerID - nchar(5)
    1,         -- EmployeeID - int
    GETDATE(), -- OrderDate - datetime
    GETDATE(), -- RequiredDate - datetime
    GETDATE(), -- ShippedDate - datetime
    3,         -- ShipVia - int
    10,      -- Freight - money
    N'',       -- ShipName - nvarchar(40)
    N'',       -- ShipAddress - nvarchar(60)
    N'',       -- ShipCity - nvarchar(15)
    N'',       -- ShipRegion - nvarchar(15)
    N'',       -- ShipPostalCode - nvarchar(10)
    N''        -- ShipCountry - nvarchar(15)
)
SELECT @id = SCOPE_IDENTITY()
INSERT Northwind..[Order Details]
(
    OrderID,
    ProductID,
    UnitPrice,
    Quantity,
    Discount
)
VALUES
(   11078,    -- OrderID - int
    3,    -- ProductID - int
    11, -- UnitPrice - money
    15,    -- Quantity - smallint
    0.0   -- Discount - real
    )