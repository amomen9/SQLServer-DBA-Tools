# 🔄 What Is `REVERTING` State in SQL Server Always On Availability Groups?

---

## 1. Definition 📘

**What is reverting state?**  
The `REVERTING` state occurs when a newly designated secondary replica must undo (`UNDO`) changes that it had already applied via `REDO` in order to resynchronize with the current primary replica after a failover. This phase aligns the secondary’s log and data pages to a negotiated recovery point so normal `SYNCHRONIZED` replication can resume.

> This process is also called **"Undo of Redo"**.

---

## 2. When Does `REVERTING` Occur? 🕒

1. A failover happens (planned or forced).
2. Previous primary becomes secondary; a new primary takes over.
3. Replicas reestablish connectivity.
4. A common recovery point is negotiated (log position).
5. If the new secondary had applied log records beyond what the new primary has committed (e.g., a large transaction was in-flight), it must revert those changes.
6. Pages are requested from the primary to complete the alignment.

---

## 3. Key Characteristics 🧬

| Aspect | Details |
|--------|---------|
| Trigger | Log divergence during failover |
| Action | Undo previously replayed log records |
| Performance | Potentially slow (large transactions/pages copied) |
| Risk | Sudden data loss on former primary may yield data loss (uncommitted work) |
| Visibility | Primary: `NOT_SYNCHRONIZING`; Secondary: `REVERTING` |

---

## 4. Impact ⚠️

- Read-only and reporting workloads cannot access the secondary database during `REVERTING`.
- Error like `922` may appear: database not available / inaccessible for the workload.
- Monitoring dashboards show a mismatch (`NOT SYNCHRONIZING` vs `REVERTING`).

---

## 5. Visual Indicators 🖥️

**Not Synchronizing**

![Screenshot of the Always On dashboard reporting Not Synchronizing on the primary.]()

![Screenshot of Always On dashboard reporting Reverting on the secondary.]()

**Read-only and reporting workloads fail to access the secondary database**

![Screenshot shows that read-only and reporting workloads fail to access the secondary database with error 922.]()

---

## 6. DMV Visibility 🧪

### 6.1 Primary Replica: Shows `NOT_SYNCHRONIZING`
Use DMVs to inspect synchronization state:

```tsql
SELECT DISTINCT
       ar.replica_server_name,
       drcs.database_name,
       drs.database_id,
       drs.synchronization_state_desc,
       drs.database_state_desc
FROM sys.availability_replicas ar
JOIN sys.dm_hadr_database_replica_states drs
     ON ar.replica_id = drs.replica_id
JOIN sys.dm_hadr_database_replica_cluster_states drcs
     ON drs.group_database_id = drcs.group_database_id;
```

### 6.2 Secondary Replica: Shows `REVERTING`
The same DMV query will return `REVERTING` for `synchronization_state_desc` (or transitional states) on the secondary where undo is occurring.

---

## 7. Performance Considerations 🚦

- Large active transactions at failover time increase revert duration.
- High page re-copy volume between primary and secondary.
- Slow storage or network latency exacerbates revert time.
- Monitoring `AlwaysOn_health` Extended Events can help approximate progress.

---

## 8. Estimating Time in `REVERTING` State ⏳

While SQL Server does not expose an explicit “remaining time” counter for reverting, practitioners:
1. Track decreasing `redo_queue_size` and `log_send_queue_size`.
2. Correlate `last_redone_lsn` vs `last_sent_lsn`.
3. Monitor Extended Events such as `error_reported`, `hadr_db_partner_set_sync_state`, and `hadr_recovery_preempt`.

**Diagnostic Log Reference**

![Screenshot of the AlwaysOn_health extended event diagnostic log.]()

---

## 9. Troubleshooting Checklist 🧰

| Step | Action |
|------|--------|
| 1 | Confirm failover completion (`sys.dm_hadr_database_replica_states`). |
| 2 | Check `synchronization_state_desc` and `database_state_desc`. |
| 3 | Validate network stability (cross-subnet latency if applicable). |
| 4 | Inspect large active transactions before failover (avoid forced failover mid-transaction if possible). |
| 5 | Review Extended Events for recovery progression. |
| 6 | Ensure primary’s data/log are healthy (no corruption). |
| 7 | Avoid unnecessary workload pressure on secondary until revert completes. |

---

## 10. Common Symptoms 🩺

- Dashboard warnings: `NOT SYNCHRONIZING` / `REVERTING`.
- Queries to secondary fail with accessibility errors (e.g., error 922).
- Reporting services timeout against the secondary.

---

## 11. Best Practices ✅

- Prefer planned failovers outside peak transactional bursts.
- Monitor transaction log size growth prior to failover.
- Maintain robust network connectivity; packet loss prolongs revert.
- Implement alerting on prolonged `REVERTING` states.
- Consider `Distributed Availability Groups (DAG)` for cross-geo deployments—reduces complex revert scenarios across distant datacenters.

---

## 12. Glossary 📖

| Term | Definition |
|------|------------|
| `Redo` | Applying logged changes to bring a secondary in sync. |
| `Undo` | Reverting uncommitted changes replayed during redo. |
| `REVERTING` | State indicating ongoing undo after failover. |
| `NOT_SYNCHRONIZING` | State from primary perspective when replica not yet synchronized. |
| `LSN` | Log Sequence Number (ordering in transaction log). |
| `Extended Events` | Lightweight event tracing framework. |

---

## 13. Summary 🧾

The `REVERTING` state is a transitional synchronization phase in Always On Availability Groups where the new secondary aligns its data by undoing previously applied log activity beyond the negotiated recovery point. During this period, workloads targeting that secondary (especially read-only/reporting) will fail until synchronization resumes.

---

**END**