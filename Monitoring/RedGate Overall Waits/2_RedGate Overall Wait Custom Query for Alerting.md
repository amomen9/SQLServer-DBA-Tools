# ⏱️ SQL Server Waits Monitoring Script (RedGate Custom Metric)

---

## 1. Overview 📘

This document presents a custom `T-SQL` monitoring script intended for integration with RedGate SQL Monitor (as a Custom Metric / Alert).  
It calculates the average non-signal wait time per second over a 2‑minute interval, excluding a curated set of benign or idle wait types.

---

## 2. Original Script Explanation (Embedded Comments) 📝

The script (see full code below) performs these actions:

1. Captures a baseline of cumulative wait time (`wait_time_ms - signal_wait_time_ms`) across the top 200 wait rows—excluding idle/system waits.
2. Pauses execution for exactly 2 minutes (`WAITFOR DELAY '00:02:00'`).
3. Re-queries the same DMV to obtain a new cumulative wait delta.
4. Computes:  
   Average Non-Signal Wait Seconds per Second = (Delta Non-Signal Wait Seconds) / 120.

This value can be used to trigger alerts when overall waiting behavior increases beyond expected thresholds.

---

## 3. Step-by-Step Logic Breakdown 🔍

### 3.1 Baseline Capture
1. Query `sys.dm_os_wait_stats`.
2. Filter out zero wait rows and a long exclusion list of low-value / idle wait types.
3. Take top 200 wait rows ordered by highest `wait_time_ms`.
4. Sum `wait_time_ms - signal_wait_time_ms` and convert to seconds (`/ 1000.0`).

### 3.2 Interval Wait
1. Sleep for 2 minutes using `WAITFOR DELAY`.

### 3.3 Follow-up Capture
1. Re-run the same filtered TOP 200 wait aggregation.
2. Subtract baseline from new cumulative value.

### 3.4 Final Metric
1. Divide delta seconds by 120 (seconds in 2 minutes) → average per second.
2. Return single scalar row usable by RedGate Custom Metric engine.

---

## 4. Why Exclude Certain Wait Types? 🚫

Excluded waits are mostly:
- Idle background queue waits (`LAZYWRITER_SLEEP`, `BROKER_*`, `XE_*`, etc.).
- Internal housekeeping or diagnostic sleeps.
- Non-actionable waits that inflate totals without indicating performance pressure.

Filtering enhances signal-to-noise ratio for real workload stress indicators (e.g., `LATCH_`, `PAGEIOLATCH_`, `CXPACKET` / related, `WRITELOG`, etc.—assuming they appear in the Top 200 set).

---

## 5. Output 📤

| Column | Description |
|--------|-------------|
| (No alias) | Single numeric value: average non-signal wait seconds per second over the last 2 minutes. |

---

## 6. Integration Notes 🧩

| Aspect | Recommendation |
|--------|---------------|
| Scheduling | Every 2–5 minutes via RedGate Custom Metric poll. |
| Alert Threshold | Baseline using historical collection; set warning/critical above typical idle averages. |
| Permissions | Requires view access to `sys.dm_os_wait_stats`. Typically `VIEW SERVER STATE`. |
| Variability | On very quiet systems value may be near 0. |

---

## 7. Potential Enhancements 🔧

- Parameterize delay duration (e.g., replace hard-coded 2 minutes).
- Add breakdown per wait class (requires extra grouping).
- Capture sample into a logging table for trend analysis.
- Include division safeguards if DMV resets during interval.

---

## 8. Glossary 🔍

| Term | Meaning |
|------|---------|
| `Wait Time` | Time threads spent waiting (resource or queue). |
| `Signal Wait Time` | Portion spent waiting to get CPU after resource was available. |
| `Non-Signal Wait` | Resource acquisition portion: total minus signal. |
| `DMV` | Dynamic Management View (`sys.dm_os_wait_stats`). |
| `RedGate SQL Monitor` | Third-party monitoring suite for SQL Server. |

---

## 9. Full Script Source Code 💻

<details>
<summary>(click to expand) The complete script:</summary>

```sql
-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2023-12-20"
-- Description:         "2_RedGate Overall Wait Custom Query for Alerting"
-- License:             "Please refer to the license file"
-- =============================================
-- This script can be used to create a custom metric & alert in RedGate SQL Monitor
-- It calculates the average wait time per second over a 2-minute period, excluding certain wait types.
-- The script first captures the total wait time and signal wait time, then calculates the average wait time per second
-- by subtracting the signal wait time from the total wait time, dividing by 1000.0 to convert milliseconds to seconds,
-- and finally dividing by 120 to get the average over the 2-minute period.

SET NOCOUNT ON;

DECLARE @wait INT;

SELECT @wait = (SUM(wait_time_ms) - SUM(signal_wait_time_ms)) / 1000.0
FROM (
    SELECT TOP 200
           wait_type,
           waiting_tasks_count,
           wait_time_ms,
           signal_wait_time_ms,
           0 AS affected_queries_zero
    FROM sys.dm_os_wait_stats
    WHERE wait_time_ms > 0
      AND [wait_type] NOT IN (N'BROKER_EVENTHANDLER', N'BROKER_INIT', N'BROKER_MASTERSTART',
                              N'BROKER_RECEIVE_WAITFOR', N'BROKER_REGISTERALLENDPOINTS', N'BROKER_SERVICE',
                              N'BROKER_SHUTDOWN', N'BROKER_TASK_STOP', N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER',
                              N'CHECKPOINT_QUEUE', N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE',
                              N'DBMIRROR_DBM_MUTEX', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL',
                              N'DISPATCHER_QUEUE_SEMAPHORE', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
                              N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP',
                              N'LOGMGR_QUEUE', N'MISCELLANEOUS', N'OGMGR_QUEUE', N'ONDEMAND_TASK_QUEUE',
                              N'PARALLEL_BACKUP_QUEUE', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
                              N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', N'REQUEST_DISPENSER_PAUSE',
                              N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE', N'SLEEP_BPOOL_FLUSH',
                              N'SLEEP_DBSTARTUP', N'SLEEP_DCOMSTARTUP', N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK',
                              N'SLEEP_TASK', N'SLEEP_TEMPDBSTARTUP', N'SP_SERVER_DIAGNOSTICS_SLEEP',
                              N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'TRACEWRITE',
                              N'WAITFOR', N'XE_DISPATCHER_JOI', N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT',
                              N'HADR_WORK_QUEUE', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'LOGMGR_QUEUE',
                              N'HADR_TIMER_TASK', N'HADR_CLUSAPI_CALL', N'HADR_LOGCAPTURE_WAIT',
                              N'QDS_SHUTDOWN_QUEUE', N'HADR_NOTIFICATION_DEQUEUE', N'CXCONSUMER',
                              N'PARALLEL_REDO_WORKER_WAIT_WORK', N'PARALLEL_REDO_DRAIN_WORKER',
                              N'PARALLEL_REDO_LOG_CACHE', N'PARALLEL_REDO_TRAN_LIST', N'PARALLEL_REDO_WORKER_SYNC',
                              N'SOS_WORK_DISPATCHER', N'QDS_ASYNC_QUEUE', N'VDI_CLIENT_OTHER',
                              N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'RESOURCE_GOVERNOR_IDLE', N'PVS_PREALLOCATE',
                              N'HADR_FABRIC_CALLBACK', N'PWAIT_EXTENSIBILITY_CLEANUP_TASK', N'WAIT_XTP_HOST_WAIT')
    ORDER BY wait_time_ms DESC, signal_wait_time_ms DESC
) dt;

WAITFOR DELAY '00:02:00';

SELECT ((SUM(wait_time_ms) - SUM(signal_wait_time_ms)) / 1000.0 - @wait) / 120
FROM (
    SELECT TOP 200
           wait_type,
           waiting_tasks_count,
           wait_time_ms,
           signal_wait_time_ms,
           0 AS affected_queries_zero
    FROM sys.dm_os_wait_stats
    WHERE wait_time_ms > 0
      AND [wait_type] NOT IN (N'BROKER_EVENTHANDLER', N'BROKER_INIT', N'BROKER_MASTERSTART',
                              N'BROKER_RECEIVE_WAITFOR', N'BROKER_REGISTERALLENDPOINTS', N'BROKER_SERVICE',
                              N'BROKER_SHUTDOWN', N'BROKER_TASK_STOP', N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER',
                              N'CHECKPOINT_QUEUE', N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE',
                              N'DBMIRROR_DBM_MUTEX', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL',
                              N'DISPATCHER_QUEUE_SEMAPHORE', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
                              N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP',
                              N'LOGMGR_QUEUE', N'MISCELLANEOUS', N'OGMGR_QUEUE', N'ONDEMAND_TASK_QUEUE',
                              N'PARALLEL_BACKUP_QUEUE', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
                              N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', N'REQUEST_DISPENSER_PAUSE',
                              N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE', N'SLEEP_BPOOL_FLUSH',
                              N'SLEEP_DBSTARTUP', N'SLEEP_DCOMSTARTUP', N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK',
                              N'SLEEP_TASK', N'SLEEP_TEMPDBSTARTUP', N'SP_SERVER_DIAGNOSTICS_SLEEP',
                              N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'TRACEWRITE',
                              N'WAITFOR', N'XE_DISPATCHER_JOI', N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT',
                              N'HADR_WORK_QUEUE', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'LOGMGR_QUEUE',
                              N'HADR_TIMER_TASK', N'HADR_CLUSAPI_CALL', N'HADR_LOGCAPTURE_WAIT',
                              N'QDS_SHUTDOWN_QUEUE', N'HADR_NOTIFICATION_DEQUEUE', N'CXCONSUMER',
                              N'PARALLEL_REDO_WORKER_WAIT_WORK', N'PARALLEL_REDO_DRAIN_WORKER',
                              N'PARALLEL_REDO_LOG_CACHE', N'PARALLEL_REDO_TRAN_LIST', N'PARALLEL_REDO_WORKER_SYNC',
                              N'SOS_WORK_DISPATCHER', N'QDS_ASYNC_QUEUE', N'VDI_CLIENT_OTHER',
                              N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'RESOURCE_GOVERNOR_IDLE', N'PVS_PREALLOCATE',
                              N'HADR_FABRIC_CALLBACK', N'PWAIT_EXTENSIBILITY_CLEANUP_TASK', N'WAIT_XTP_HOST_WAIT')
    ORDER BY wait_time_ms DESC, signal_wait_time_ms DESC
) dt;
```

</details>

---

## 10. Validation ✅

| Check | Purpose | Expected |
|-------|---------|----------|
| DMV accessible | Ensures permission | Succeeds |
| Single row return | Metric shape | 1 value |
| Runtime ≈ 2 min | Interval length | Yes |
| No divide-by-zero | DMV cumulative | Safe |

---

## 11. Final Notes 🧾

- Suitable for trend-based alerting.
- Consider pairing with a breakdown dashboard (per wait category).
- Reset events (e.g., server restart) may yield transient low values immediately post-start.

---

**END** ✨
