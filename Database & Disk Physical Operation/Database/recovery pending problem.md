# Figure out missing database files

Use a script like the concept of this query `recovery pending problem.sql` to identify the database files that
 are missing and thus have made their respective databases to go into `Recovery Pending` state.

* As you already know, the `Recovery Pending` state is one of the worst database states in SQL Server which means
 that the database is inaccessible.


| state | state_desc        |
| :---- | :---------------- |
| 0     | ONLINE            |
| 1     | RESTORING         |
| 2     | RECOVERING        |
| 3     | RECOVERY_PENDING  |
| 4     | SUSPECT           |
| 5     | EMERGENCY         |
| 6     | OFFLINE           |
| 7     | COPYING           |
| 10    | OFFLINE_SECONDARY |

* If the missing file is only the log file, you can read its data
 and rescue it by taking the database to the `Emergency Mode`, but you cannot modify the data. You can take the database
 into the Emergency Mode using the command below:

```SQL
ALTER DATABASE [YourDatabaseName] SET EMERGENCY;
```
