@echo off


rem make SQLServer account the local admin of the server:
NET localgroup administrators Ali-PC\SQLServer /add
echo "end administrators membership"


fsutil 8dot3name set 1
fsutil behavior set disablelastaccess 1


SET conf="\\Server\C$\Users\a.momen\Desktop\ins\ConfigurationFile.ini"


rem powershell Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
rem powershell Start-Service sshd
rem powershell Set-Service -Name sshd -StartupType 'Automatic'
rem powershell Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths" /f
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\ssms.exe" /ve /d "C:\Program Files (x86)\Microsoft SQL Server Management Studio 18\Common7\IDE\Ssms.exe" /f
echo "end reg"


"\\172.16.40.20\c$\Sql Server 2019\SQLServer2019-x64-ENU.iso"
timeout /t 3

title "Install SQL Server"
%1:\setup.exe /ConfigurationFile=%conf% /SAPWD="%2" /PID="%4" /SQLTEMPDBFILECOUNT="%5"
echo "end SQL Server setup"

title "Install SSMS"
"\\172.16.40.20\c$\Sql Server 2019\SSMS-Setup-ENU.exe" /Passive
echo "end SSMS setup"
sc query mssqlserver


title "Install CU"
"\\172.16.40.20\c$\Sql Server 2019\SQLServer2019-CU14\SQLServer2019-KB5007182-x64.exe" /action=patch /instancename=MSSQLSERVER /quiet /IAcceptSQLServerLicenseTerms
echo "end CU setup"


"\\172.16.40.20\c$\Sql Server 2019\MsSqlCmdLnUtils.msi" /passive
echo "end SQLCMD setup"


call "\\Server\c$\Users\a.momen\Desktop\ins\SQL port-firewall.bat"
echo "end port/firewall"


title "SQL Scripts"

"C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE" -Q "ALTER LOGIN sa WITH NAME = [AppSQL];"


"C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE" -i "\\Server\c$\Users\a.momen\Desktop\ins\trigger.sql"


"C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE" -Q "EXEC sys.sp_configure N'show advanced options', N'1'  RECONFIGURE WITH OVERRIDE EXEC sys.sp_configure N'max degree of parallelism', N'%3' RECONFIGURE WITH OVERRIDE EXEC sys.sp_configure N'show advanced options', N'0'  RECONFIGURE WITH OVERRIDE"


call "\\Server\c$\Users\a.momen\Desktop\ins\dbWarden.bat"


"C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE" -Q "RESTORE DATABASE [SQLAdministrationDB] FROM  DISK = N'\\172.16.40.35\ManualBackups\SQLADDB_22.06.06.bak' WITH  FILE = 1,  MOVE N'SQLAdministrationDB_log' TO N'D:\Database Log\SQLAdministrationDB_log.ldf',  NOUNLOAD"


"C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE" -i "\\Server\c$\Users\a.momen\Desktop\ins\my login.sql"
echo "end SQL Server scripts"



title "Process Finished"
echo Process Finished.

set /p id="Press enter to shutdown the system. Warning! The shutdown will be immediate. Close the window to avoid it . . ."

shutdown /r /f /t 0 /d p:1:4
