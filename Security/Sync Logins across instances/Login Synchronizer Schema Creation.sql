-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2023-02-26"
-- Description:         "Login Synchronizer Schema Creation"
-- License:             "Please refer to the license file"
-- =============================================



USE [SQLAdministrationDB]
GO
/****** Object:  UserDefinedFunction [dbo].[ufn_is_login_disabled]    Script Date: 2/21/2023 3:10:53 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE   FUNCTION [dbo].[ufn_is_login_disabled](@LoginName sysname)
	RETURNS BIT
WITH RETURNS NULL ON NULL INPUT
AS
BEGIN
	RETURN (SELECT is_disabled FROM sys.server_principals WHERE name=@LoginName)
END
GO
/****** Object:  Table [dbo].[InstanceLogins]    Script Date: 2/21/2023 3:10:53 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS dbo.InstanceLogins
GO

CREATE TABLE [dbo].[InstanceLogins](
	[LoginName] [sysname] NOT NULL,
	[PasswordPlain] [nvarchar](512) NULL,
	[Purpose] [varchar](50) NULL,
	[AuthenticationType] [varchar](10) NULL,
	[SID]  AS (suser_sid([LoginName])),
	[PasswordHash]  AS (LoginProperty([LoginName],'PasswordHash')),
	[MegaProject] [varchar](50) NULL,
	[is_disabled]  AS ([dbo].[ufn_is_login_disabled]([LoginName])),
	[set_password_expiry_enabled] BIT NULL,
	[sync_enabled] [bit] NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[LoginName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 94, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[Servers]    Script Date: 2/21/2023 3:10:54 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Servers](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[ServerName] [sysname] NOT NULL,
	[ServerIP] [nvarchar](50) NULL,
	[IsActive] [bit] NULL,
	[MegaProject] [nvarchar](50) NULL,
	[Port] [int] NULL,
 CONSTRAINT [PK_Servers_ServerName] PRIMARY KEY CLUSTERED 
(
	[ServerName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 94, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[SpExHistory]    Script Date: 2/21/2023 3:10:54 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[SpExHistory](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[sp_name] [sysname] NOT NULL,
	[execution_date] [datetime] NOT NULL,
	[execution_login] [sysname] NOT NULL,
	[original_execution_login] [sysname] NOT NULL,
	[duration (s)] [decimal](9, 3) NOT NULL,
	[dop] [varchar](2) NOT NULL,
	[parameter_values] [nvarchar](512) NOT NULL,
	[WasSuccessful] [bit] NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 94, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO




----------- Data Insertion ---------------------------------------------



GO
ALTER TABLE [dbo].[InstanceLogins] ADD  CONSTRAINT [DF__InstanceL__Purpo__4D2A7347]  DEFAULT ('Production') FOR [Purpose]
GO
ALTER TABLE [dbo].[InstanceLogins] ADD  CONSTRAINT [DF_InstanceLogins_AuthenticationType]  DEFAULT ('SQL') FOR [AuthenticationType]
GO
ALTER TABLE [dbo].[InstanceLogins] ADD  DEFAULT ((0)) FOR [sync_enabled]
GO
ALTER TABLE [dbo].[SpExHistory] ADD  DEFAULT ((1)) FOR [WasSuccessful]
GO
/****** Object:  StoredProcedure [dbo].[SyncLogins]    Script Date: 2/21/2023 3:10:54 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

