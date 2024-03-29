reg add "HKLM\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQLServer\SuperSocketNetLib\Tcp\IPAll" /t REG_SZ /v TcpPort /d 55555 /f

powershell New-NetFirewallRule -DisplayName "AGPort" -Direction Inbound -LocalPort 5022 -Protocol TCP -Action Allow
powershell New-NetFirewallRule -DisplayName "AGPort" -Direction Outbound -LocalPort 5022 -Protocol TCP -Action Allow

powershell New-NetFirewallRule -DisplayName "SQLPort" -Direction Inbound -LocalPort 55555 -Protocol TCP -Action Allow
powershell New-NetFirewallRule -DisplayName "SQLPort" -Direction Outbound -LocalPort 55555 -Protocol TCP -Action Allow

net stop mssqlserver /Y && net start mssqlserver && net start sqlserveragent