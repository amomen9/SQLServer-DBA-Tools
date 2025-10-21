-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2022-06-01"
-- Description:         "trigger"
-- License:             "Please refer to the license file"
-- =============================================



DROP TRIGGER if exists [ddl_master] ON DATABASE
GO


CREATE TRIGGER [ddl_master]   
ON DATABASE   
FOR CREATE_TABLE,
		DROP_TABLE,
		 ALTER_TABLE,
		 CREATE_PROCEDURE,
		DROP_PROCEDURE,
		 ALTER_PROCEDURE,
		 CREATE_FUNCTION,
		 ALTER_FUNCTION,
		 DROP_FUNCTION,
		 CREATE_INDEX,
		 ALTER_INDEX,
		 DROP_INDEX,
		 CREATE_SCHEMA,
		 ALTER_SCHEMA,
		 DROP_SCHEMA,
		 CREATE_USER,
		 ALTER_USER,
		 DROP_USER,
		 CREATE_PARTITION_FUNCTION,
		 ALTER_PARTITION_FUNCTION,
		 DROP_PARTITION_FUNCTION,
		 CREATE_PARTITION_SCHEME,
		 ALTER_PARTITION_SCHEME,
		 DROP_PARTITION_SCHEME    
AS   
   PRINT 'You must disable Trigger "ddl_master" to drop or alter or create certain objects on the master database! See the trigger''s body for more details'   
   ROLLBACK;

GO

ENABLE TRIGGER [ddl_master] ON DATABASE
GO
