USE NorthwindDW

/*

NorthwindDW

Dimensions:

1)DimEmployee:  EmployeeKey , EmployeeID , FirstName , LastName
               identity (PK)
*/
CREATE TABLE DimEmployee (EmployeeKey INT IDENTITY(1,1) PRIMARY KEY NOT NULL , EmployeeID INT NOT null, FirstName NVARCHAR(10), LastName NVARCHAR(20))

INSERT INTO NorthwindDW.dbo.DimEmployee
SELECT EmployeeID , FirstName , LastName
FROM Northwind.dbo.Employees


--ALTER TABLE NorthwindDW.dbo.DimEmployee ADD PRIMARY KEY (EmployeeKey)

2)DimCustomer:  CustomerKey , CustomerID , CompanyName , Country  (--+Current Country)
                               BK          Type 0         Type2
CREATE TABLE DimCustomer (CustomerKey INT IDENTITY PRIMARY key NOT NULL , CustomerID NCHAR(5), CompanyName NVARCHAR(40), Country NVARCHAR(15))

3)DimProduct:

*/

SELECT IDENTITY(INT,1,1) AS ProductKey, P.ProductID , P.ProductName , C.CategoryID , C.CategoryName , CASE P.Discontinued
																		TYPE 1			type 1			WHEN 0 THEN 'Active'
																										ELSE 'Inactive'
																								  END AS [Status] , P.SupplierID
																											TYPE 1		-- Type 2
FROM Products P INNER JOIN Categories C
   ON P.CategoryID = C.CategoryID

 /*

4) DimSupplier:  SupplierKey , SupplierID , CompanyName , Country
                 SK             BK          Type 0         Type 1

*/
SELECT IDENTITY(INT,1,1) SupplierKey, s1.SupplierID, s1.CompanyName , s1.Country
INTO NorthwindDW..DimSupplier
FROM Northwind..Suppliers s1 JOIN Northwind..Suppliers s2 ON s1.SupplierID = s2.SupplierID
WHERE 1=2

ALTER TABLE NorthwindDW..DimSupplier ADD CONSTRAINT PK_DimSupplier PRIMARY KEY (SupplierKey)

SELECT FROM Nort
/*

DimSupplier <----------- DimProduct <---------- FactSale

5) DimShipper:   ShipperKey , ShipperID , ComapnyName
                    SK          BK          Type 0
*/

SELECT IDENTITY(INT,1,1) AS ShipperKey, ShipperID, CompanyName
INTO NorthwindDW..DimShippers
FROM Northwind..Shippers s1 JOIN Northwind..Shippers s2
ON s1.ShipperID = s2.ShipperID

ALTER TABLE NorthwindDW..DimShippers ADD CONSTRAINT PK_DimShipper PRIMARY KEY (ShipperKey)

*/

6) DimDate: DateKey, DisplayDate , Year , Quarter , MonthID , MonthName , DOW_ID , DOW_Name , DayOfYear , WeekNo
     1996 - 1998
	 1990 - 2040
	*/

ALTER DATABASE NorthwindDW SET RECOVERY SIMPLE