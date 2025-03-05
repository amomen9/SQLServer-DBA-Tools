# SQL Server Backup and Restore History Analyzer

## Purpose
This script is designed to query and analyze SQL Server backup and restore history, as well as database space usage. It provides insights into:
- Backup history (full, differential, log, etc.).
- Restore history (database, file, log, etc.).
- Database space usage (reserved and used space).

## Features
1. **Backup History**:
   - Retrieves backup details such as database name, backup type, start/finish date, size, and physical device name.
   - Supports filtering by database name and time range.

2. **Restore History**:
   - Retrieves restore details such as database name, restore type, restore date, and source/destination paths.
   - Supports filtering by database name and time range.

3. **Database Space Usage**:
   - Calculates reserved and used space for each database.
   - Compares used space with the latest full backup size.

## Usage
1. Set the `@dbname` variable to filter by a specific database (or `NULL` for all databases).
2. Set the `@days` variable to specify the number of days to look back (default: 30 days).
3. Execute the script to retrieve the desired information.

## Notes
- The script uses system tables (`msdb.dbo.backupset`, `msdb.dbo.restorehistory`, etc.) to gather data.
- Temporary tables are used for intermediate calculations (e.g., `#UsedSpacePerDB`).

## Example Output
- Backup history with details like backup type, size, and device name.
- Restore history with details like restore type, date, and paths.
- Database space usage with reserved space, used space, and percentage utilization.

## Dependencies
- SQL Server 2012 or later.
- Access to `msdb` system database.

---

**Signature**: This script is optimized for readability, performance, and maintainability while preserving the original functionality.