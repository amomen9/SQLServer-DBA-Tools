# \#SQLServer
T-SQL Scripts


- License: Do whatever you wish with these files!!! :smile::laughing: Just please include the Author tag.
If you wish to contribute to the codes or have any suggestions or want to report a flaw,
please give me an email at amomen@gmail.com
These scripts are for SQL Server's general purposes. For full corresponding instructions for each script,
please refer to the README.md file included in its folder.
- Please have a look at my website if you wish at https://amdbablog.blogspot.com/

## Contained Scripts

#### 1. Backup Website (Within T-SQL_Backup&Restore folder):

```
This script performs a full backup of the database and home folder files of the intended website. It can be turned into a
scheduled job to run at specific schedules. The DB backup file name will be in 'DBName_Date_Time + .bak' format.
The home folder backup has a similar name. A checkdb will also be performed prior to the database backup. 
```

#### 2. Restore Website (Within T-SQL_Backup&Restore folder):

```
  Before using this script, please read the comments at the beginning of Backup_Website.sql script thoroughly.
  This script restores the backups performed by the Backup_Website.sql script. You can also specify the destination
  database. If you don't specify the destination database, the database will be restored on its own. This script
  probes inside the backup folder and extracts and restores the latest backup. If the database is to be restored
  on its own, a tail of log backup will be taken first, if the database does not have SIMPLE or Pseudosimple
  recovery model. For the files restore, it overwrites all the files in the destination. By default, the last 
  backup set will be restored, by probing into the backups directory and ignoring the history records of SQL Server
  msdb database. But you can specify the backup location manually. The names are case-insensitive. As the restore
  of Website files is normally time-consuming, the database will be kept in restoring state until the whole script
  is completed. For security reasons, the script enables the extended stored procedure xp_cmdshell
  and disables it again immediately once the procedure is finished executing.
```

#### 3. Execute external tsql
```
  This script executes external tsql file(s) using sqlcmd and xp_cmdshell. As :r is only available in SSMS and it requires turning the
  SQLCMD mode on, it can execute external tsql files without SSMS. It can also run all the tsql files contained within a folder and its
  subdirectories. Sample sp execution statement is as follows:
  EXECUTE master..execute_external_tsql @InputFiles = N'"C:\Users\Ali\Dropbox\learning\SQL SERVER\InstNwnd.sql"' -- Delimited by a semicolon (;), 
  executed by given order, enter the files which their path contains space within double quotations. Relative paths must be relative to %systemroot%\system32
                                     ,@InputFolder = ''	-- This sp executes every *.sql script that finds within the specified folder path. Quote addresses that contain
                                                        --space within double quotations.
                                     ,@Server = NULL
                                     ,@AuthenticationType = NULL -- any value which does not include the word 'sql' means Windows Authentication
                                     ,@UserName = NULL
                                     ,@Password = NULL
                                     ,@DefaultDatabase = NULL
                                     ,@Keep_xp_cmdshell_Enabled = 0
                                     ,@isDAC = 0	-- run files with Dedicated Admin Connection
```

#### 4. Cardinality Factor calculator sp for a table
```
  This stored procedure takes the name of a database and its table and calculates cardinality factor by calculating count(distinct column)/count(*)
  for every column. This may help the tuning experts choose the better candidate column for indexing.
  Example:
  
    DECLARE @temp TABLE(Column_Name SYSNAME, [Crowdedness (IN %)] FLOAT)
    INSERT INTO @temp
    EXECUTE master..CardinalityCalc 'Northwind','saasdsad.orders'

    select * from @temp
    order by 2 desc
```

#### 5. Drop login dependencies
```
  This stored procedure disables a login and revokes any dependecies (that prevent the login from being dropped) on the server 
  for that login. Generally, dropping a login in SQL Server is not recommended but there is an option to drop the login at the 
  end of the process. It may also leave orphaned database users. If the login is windows authentication, you do not have to specify
  the domain or computer name unless there are several identical login names under different domain and computer names. The complete
  windows authentication login name must be in the format: DomainName\LoginName (LoginName@DomainName format is not supported)
  Example:
  
    DECLARE @SID VARBINARY(85)
    EXEC sp_drop_login_dependencies @LoginName = 'test'
                               ,@DropLogin = 1
                               ,@DroppedLoginSID = @SID OUTPUT
                               
```

#### 6. sp_restore_latest_backups_on_other_server
```
  The idea of this script comes from my SQL Server professor P.Aghasadeghi (http://fad.ir/Teacher/Details/10). This stored procedure
  restores the latest backups of a server on another server. Can come in handy sometimes. Please note that this SP benefits from
  Mark Russinovich's PsTools (psexec executable) briefly introduced on Microsoft's website at https://docs.microsoft.com/en-us/sysinternals/downloads/pstools
  and is mandatory for this script. After downloading PsTools, please place psexec from its archive to the source server's path. You can add it to a folder
  which is already in path like %systemroot%\system32\. There is no requirement for psexec on the destination server except for availability of the ports tcp\135
  and tcp\445 which are open by default in Windows Firewall.
  
  Example:
  
  exec sp_restore_latest_backups_on_other_server
	@Source = '192.168.241.3',					-- IPv4, IPv6, or hostname
	@Destination = '192.168.241.100',				-- IPv4, IPv6, or hostname
	@DestinationUser = 'Ali-PC\Ali',				-- Leave user and pass empty if on a domain, and source's SQL Server service account 
									-- must be an administrator on the target machine, Otherwise specify a username
									-- and password of an administrator of the target machine. Provide the username
									-- in full [Domain or Computer name\username] format. The destination user must
									-- also be a windows login and authorized to restore backups on the target SQL Server
	@DestinationPass = 'P@$$W0rd'
```
