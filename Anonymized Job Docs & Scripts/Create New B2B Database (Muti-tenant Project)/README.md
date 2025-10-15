# 📘 Database Provisioning & Cloning Toolkit Documentation

This document describes the anonymized T-SQL toolkit used to provision, clone, and configure per-organization (multi-tenant) databases.  
It includes helper functions, automation stored procedures, and orchestration logic.

---

## 🧱 Schema Overview

| Component Type | Name | Purpose |
|----------------|------|---------|
| Function | dbo.find_nonexistant_name | Ensures a file path is unique by appending suffixes. |
| Function | dbo.InitCap | Title-cases tokens in a string. |
| Function | dbo.NormalizeCompanyDBName | Produces a clean DB name stem from an input name. |
| Stored Procedure | dbo.usp_execute_external_tsql | Controlled batch executor for external SQL files / ad‑hoc commands. |
| Stored Procedure | dbo.sp_complete_restore | Flexible single-file database restore with relocation, tail-log handling. |
| Stored Procedure | dbo.sp_CloneDB | Clones a source database (full copy) into a target (optionally replacing). |
| Stored Procedure | dbo.sp_create_new_OrgDB | End‑to‑end provisioning of a new tenant database, seeding metadata, security, notifications. |

---

## ⚙️ Helper Functions

### 1. 🔍 `dbo.find_nonexistant_name(@Path NVARCHAR(2000))`
Ensures a file path does not already exist (checked via `xp_fileexist`).  
If it exists, inserts `_2` before the final 3 / 4-character extension recursively.

**Use Case:** Safely generating a destination path for copying or archiving script files.

**Returns:** Adjusted path string guaranteed (at call time) to be unused.

**Notes:**  
- Relies on `xp_cmdshell` / extended stored procedure accessibility.  
- Assumes extension length of 4 (e.g., `.sql`, `.bak`); adapt if variable.

---

### 2. 📝 `dbo.InitCap(@InputString VARCHAR(4000))`
Title-cases each whitespace-delimited token.

**Logic:**  
1. Splits input via `STRING_SPLIT(' ')`.  
2. Uppercases first character of each token.  
3. Reassembles via `STRING_AGG`.

**Returns:** Reconstructed string with capitalized tokens.

**Limitations:**  
- Multiple spaces collapse (due to `STRING_SPLIT`).  
- No locale-sensitive casing.

---

### 3. 🧼 `dbo.NormalizeCompanyDBName(@UnnormalizedName SYSNAME)`
Produces a sanitized alphanumeric identifier suitable for database names.

**Steps:**  
1. Removes non `[0-9A-Za-z ]` characters.  
2. Trims + title-cases via `InitCap`.  
3. Removes spaces.  
4. Applies specific collations (case / accent handling).  
5. Removes stray `?` characters.  
6. If ends with `log`, appends `-99` (collision / reserved word avoidance).

**Returns:** Sanitized stem (no file-system path logic).

**Use Case:** Generating consistent DB names like `Org-<Stem>DB`.

---

## 🛠️ Core Stored Procedures

### 4. 📂 `dbo.usp_execute_external_tsql`
Batch executor for a *set* of external `.sql` files and/or inline commands.

**Key Capabilities:**
- Recursively enumerates files via PowerShell (`Get-ChildItem`).
- Supports pre/post ad‑hoc commands.
- Execution via `sqlcmd` shell invocation (constructed connection string).
- Execution time measurement per script.
- Error aggregation (SQLCMD vs SQL errors).
- Optional post-success file operations:
  - Move / copy / delete (policies 1–4).
  - De-duplication via `dbo.find_nonexistant_name`.
- Debug modes (1 = raw output, 2 = structured failures, 3 = error classification).
- Controlled enabling/disabling of `xp_cmdshell`.

**Important Parameters (subset):**
| Parameter | Purpose |
|-----------|---------|
| @InputFolder / @InputFiles | Source scripts (folder vs explicit list). |
| @PreCommand / @PostCommand | Inline commands executed before/after sequence. |
| @After_Successful_Execution_Policy | Post-processing behavior. |
| @Stop_On_Error | Halts sequence on first failing script. |
| @MoveTo_Folder_Name | Target folder when relocating successfully executed scripts. |
| @DefaultDatabase | Base database for SQLCMD session. |

**Security Considerations:**
- Requires `xp_cmdshell`; restrict to admin context.
- File enumeration via PowerShell: ensure trust boundary on @InputFolder.
- Avoid exposing credentials in plain text where SQL authentication is used.

---

### 5. ♻️ `dbo.sp_complete_restore`
Performs a single-file `RESTORE DATABASE` with optional:
- Tail-of-log backup capture.
- File relocation (`MOVE` clauses).
- Recovery model alteration.
- Read-only finalization.
- Retention of CDC / replication metadata.
- Controlled `DROP DATABASE` (conditional).
- Stats throttling (`STATS = n`).
- Script-only mode (dry-run).

**Workflow Summary:**
1. Resolve target paths (default instance paths if unspecified).
2. If target DB exists:
   - Optionally tail-log backup.
   - Force `SINGLE_USER` and/or drop.
3. Query `RESTORE FILELISTONLY` (for new placement).
4. Build dynamic `MOVE` clauses if relocation needed.
5. Execute restore (`NORECOVERY` optional).
6. Post-restore:
   - Switch recovery model if requested.
   - Multi-user reset.
   - Optional shrink of log when set to SIMPLE.
   - Optional read-only toggle.

**Key Parameters:**
| Parameter | Behavior |
|-----------|----------|
| @Drop_Database_if_Exists | Forces drop prior to restore. |
| @Take_tail_of_log_backup | Captures tail log if full recovery. |
| @Destination_*_Location | Overrides original paths. |
| @Change_Target_RecoveryModel_To | FULL / SIMPLE / BULK_LOGGED / SAME. |
| @Generate_Statements_Only | Build without execution. |

**Cautions:**
- Log shrink logic is aggressive; evaluate policy alignment.
- Tail-log capture skipped for pseudo-simple detection edge cases.

---

### 6. 📀 `dbo.sp_CloneDB`
Creates a full clone of a source database into a new target using backup/restore.

**Steps:**
1. Determines backup path under instance default backup directory.
2. Executes `BACKUP DATABASE` with `COPY_ONLY`, `CHECKSUM`, `COMPRESSION`.
3. Invokes `sp_complete_restore` to materialize target.
4. Optional logical replacement (via inverted @Replace_if_Exists pattern).

**Parameters:**
| Parameter | Notes |
|-----------|-------|
| @SourceDB_Name | Source database name. |
| @TargetDB_Name | New database name (or replacement). |
| @Schema_only | Placeholder (not implemented; always full clone). |
| @Replace_if_Exists | Inverted logic (legacy compatibility). |

---

### 7. 🏗️ `dbo.sp_create_new_OrgDB`
End-to-end tenant provisioning procedure.

**Pipeline:**
1. Normalizes organization name -> database stem (`NormalizeCompanyDBName`).
2. Builds destination DB name: `Org-<Stem>DB`.
3. Clones base template (`Org-TemplateDB`) via `sp_CloneDB`.
4. Registers connection string in central metadata tables.
5. Seeds:
   - Operator baseline (pulls from identity + company tables).
   - Configuration snapshot and mirrors into global tracking table.
6. Executes external authorization script (`orgDB_auth.sql`).
7. Updates tenant status code (e.g., status progression).
8. Seeds calendar subsystem tables (Operators / Calendars / AccessGrants).
9. Seeds notification subsystem (companies + operator parties).
10. Optionally adds DB to an Availability Group (naming pattern check).
11. Sends success email (HTML) to recipient group (conditional).
12. On error: sends failure email, rethrows exception.

**Notable Internal Queries:**
- Dynamic SQL uses QUOTENAME for DB context safety (object names but not all literal values).
- AG integration uses pattern `@@SERVERNAME LIKE 'App-DB%'`.

**Error Handling:**
- TRY/CATCH wraps the entire provisioning section.
- Failure: dispatches error via Database Mail and raises.

**Extensibility Recommendations:**
- Abstract credentials / connection strings to secure vault.
- Parameterize AG name and mail profile.
- Add idempotency checks for re-runs.

---

## 🛡️ Safety / Operational Notes

| Aspect | Recommendation |
|--------|----------------|
| xp_cmdshell | Keep disabled outside controlled execution windows. |
| PowerShell enumeration | Validate path inputs to prevent traversal misuse. |
| Dynamic SQL | Extend QUOTENAME to user-derived literals where applicable. |
| Email notifications | Ensure Database Mail profile hardening (no external relay abuse). |
| AG operations | Add guards for seeding mode & replica state introspection. |
| Recovery model changes | Align with backup strategy (log chain continuity). |

---

## 🚀 Example (Provisioning Flow)

```sql
EXEC dbo.sp_create_new_OrgDB
      @OrgID = 1001
    , @SendSuccessEmail = 1;
```

---

## 🧪 Suggested Enhancements

- Add `@Schema_Only` true branch in `sp_CloneDB` using `DBCC CLONEDATABASE` (if schema-only is needed).
- Replace string splitting capitalization with CLR or JSON aware logic if multilingual.
- Introduce centralized audit logging table for provisioning runs.
- Parameterize email recipients instead of table lookups (support override).
- Harden password handling (remove inline literal in connection string).

---

## 📄 Licensing / Attribution

Anonymous internal toolkit – documentation generated for clarity and maintainability.

---

## ✅ Quick Reference (Cheat Sheet)

| Action | Call |
|--------|------|
| Clone DB | `EXEC dbo.sp_CloneDB @SourceDB_Name='Template', @TargetDB_Name='TenantX';` |
| Restore w/ relocation (script only) | `EXEC dbo.sp_complete_restore @Restore_DBName='TenantX', @Backup_Location='D:\baks\TenantX.bak', @Generate_Statements_Only=1;` |
| Normalize name | `SELECT dbo.NormalizeCompanyDBName('Acme Holdings Intl');` |
| Execute folder scripts | `EXEC dbo.usp_execute_external_tsql @InputFolder='D:\Deploy\', @After_Successful_Execution_Policy=2;` |

---

🌟 End of Document.