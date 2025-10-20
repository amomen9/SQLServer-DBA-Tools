select @@SERVERNAME, SERVERPROPERTY(N'ServerName')

DECLARE @actualname NVARCHAR(100)
DECLARE @currentname NVARCHAR(100)
DECLARE @atatservername NVARCHAR(128)

SELECT @actualname = CONVERT(NVARCHAR(100), SERVERPROPERTY(N'ServerName'))
SELECT @currentname = (SELECT name from sys.servers WHERE server_id=0)
SELECT @atatservername = @@SERVERNAME


IF (@actualname = @currentname)
BEGIN
	IF @atatservername=@currentname
		RAISERROR('@actualname and @currentname parameters are the same. You do not need to update your local server name.',16,1)		
	ELSE 
	BEGIN
		RAISERROR('You have corrected your server name and for that change to take effect, a SQL Server service restart is required.',16,1)		
		RETURN
	END
END
else
begin
	EXEC sp_dropserver @currentname
	EXEC sp_addserver @actualname, local	
		
end


select * from sys.servers


select @@SERVERNAME, SERVERPROPERTY(N'ServerName')