-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2022-06-05"
-- Description:         "create columnstore index"
-- License:             "Please refer to the license file"
-- =============================================




USE [NorthwindDW2]
GO

IF(SELECT MIN(index_id) FROM sys.indexes WHERE object_id=OBJECT_ID('[dbo].[DimSupplier]')) = 0
	CREATE CLUSTERED COLUMNSTORE INDEX CCSI_DimSupplier ON dbo.DimSupplier
	


ALTER TABLE [dbo].[DimSupplier] ADD  CONSTRAINT [PK_DimSupplier] PRIMARY KEY NONCLUSTERED
	(
	 [SupplierKey] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

SELECT * FROM sys.index_columns WHERE object_id = OBJECT_ID('dimsupplier')

------------------------------------------------------------------------------------------------

USE [NorthwindDW2]
GO

/****** Object:  Index [PK_DimCustomers]    Script Date: 5/10/2022 10:21:14 AM ******/
IF(SELECT MIN(index_id) FROM sys.indexes WHERE object_id=OBJECT_ID('[dbo].[DimCustomers]')) = 0
	CREATE CLUSTERED COLUMNSTORE INDEX CCSI_DimCustomers ON dbo.DimCustomers
GO


USE [NorthwindDW2]
GO

/****** Object:  Index [IX_DimCustomers_CustomersID]    Script Date: 5/10/2022 10:21:41 AM ******/
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('[dbo].[DimCustomers]') AND name = 'CSIX_DimCustomers_CustomersID_CustomersKey')
	CREATE NONCLUSTERED COLUMNSTORE INDEX [CSIX_DimCustomers_CustomersID_CustomersKey] ON [dbo].[DimCustomers]
(
 [CustomerID],
 [CustomerKey]
)
WITH (ONLINE = OFF) ON [PRIMARY]
GO

------------------------------------------------------------------------------------------------

USE [NorthwindDW2]
GO

/****** Object:  Index [PK_DimProduct]    Script Date: 5/10/2022 10:21:14 AM ******/
IF(SELECT MIN(index_id) FROM sys.indexes WHERE object_id=OBJECT_ID('[dbo].[DimProduct]')) = 0
	CREATE CLUSTERED COLUMNSTORE INDEX CCSI_DimProduct ON dbo.DimProduct
GO

USE [NorthwindDW2]
GO

/****** Object:  Index [IX_DimProduct_ProductID]    Script Date: 5/10/2022 10:21:41 AM ******/
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('[dbo].[DimProduct]') AND name = 'CSIX_DimProduct_ProductID_ProductKey')
	CREATE NONCLUSTERED COLUMNSTORE INDEX [CSIX_DimProduct_ProductID_ProductKey] ON [dbo].[DimProduct]
(
 [ProductID],
 [ProductKey]
)
WITH (ONLINE = OFF) ON [PRIMARY]
GO


IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_DimProduct_DimSupplier_SupplierID')
	ALTER TABLE dbo.DimProduct
   ADD CONSTRAINT FK_DimProduct_DimSupplier_SupplierID FOREIGN KEY (SupplierID)
      REFERENCES dbo.DimSupplier (SupplierKey)

----------------------------------------------------------------------------------------------------------------


IF ('a'<>null)
	PRINT 'null'
ELSE
	PRINT 'NOT NULL'


IF NOT EXISTS (SELECT * FROM sys.indexes WHERE OBJECT_ID = OBJECT_ID('dbo.DimSupplier') AND index_id>1)
	ALTER TABLE dbo.DimProduct ADD CONSTRAINT PK_DimProduct PRIMARY KEY NONCLUSTERED (ProductKey)

	CREATE CLUSTERED COLUMNSTORE INDEX CCI_DIMPRODUCT ON dbo.DimProduct


