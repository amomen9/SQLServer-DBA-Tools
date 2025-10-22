Command-line usage:
Install SQL Server.cmd 1 2 3 4 5
1: drive which SQL Server image is going to mount or is mounted
Ex: H
2: sa user password
Ex: $@PA$$W0RD
3: Instance MAXDOP configuration
Ex: 8
4: SQL Server product id
Ex: #####-#####-#####-#####-#####
5: TempDB File Count
Ex: 4

Ex:
"\\Server\c$\Users\a.momen\Desktop\ins\Install SQL Server.cmd" H $@PA$$W0RD 2 #####-#####-#####-#####-##### 4


Other configurations will be in the config file