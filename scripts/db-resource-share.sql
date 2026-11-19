/*
  db-resource-share.sql
  Each database's share of CPU, IO and buffer-pool memory on this SQL Server instance.
  Standalone version of sp_triage section 14 ("Database: CPU IO Memory DISK DiskIO Latency"), 2026-11-19.
  Run on SQL Server 2022 (16.0) and SQL Server 2025 (17.0), Developer edition. Other versions are untested.

  Read-only. Creates nothing, writes nothing. Needs VIEW SERVER STATE (VIEW SERVER PERFORMANCE STATE on 2022+).

  What each figure means:
    CPU      sum of total_worker_time in the plan cache, grouped by the plan's dbid attribute.
             Only covers plans still cached, and since each plan was cached (not since startup).
             Ad hoc SQL is credited to the database it ran in; cross-database queries go to the calling database.
    IO       reads + writes from sys.dm_io_virtual_file_stats, since SQL Server started.
    Buffer   pages in the buffer pool now (sys.dm_os_buffer_descriptors). That DMV walks every page,
             so it is only read when the pool is at most @BufferScanMaxGB. Above that, Buffer is NULL.
    Size     allocated size of all files (sys.master_files).
    GB/day   bytes read + written since startup, divided by days up.
    Latency  average io_stall per read / write / overall, since startup.

  Differences from the sp_triage section (deliberate):
    - CPU is shown in milliseconds. total_worker_time is in microseconds; sp_triage labels the raw figure "Ms".
    - GB/day uses the real byte counters. sp_triage multiplies the IO COUNT by 8 KB.
    - CPU reads the whole plan cache. sp_triage keeps only statements with (reads + writes) * executions > 200.
    - Size comes from sys.master_files, so it needs no per-database loop and covers databases sp_triage skips.
    - The result is a table, not text bars.
*/
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @BufferScanMaxGB INT = 64;  /* 0 = never scan the buffer pool */

DECLARE @DaysUptime NUMERIC(23,2);
SELECT @DaysUptime = CAST(DATEDIFF(HOUR, sqlserver_start_time, GETDATE()) / 24. AS NUMERIC(23,2))
FROM sys.dm_os_sys_info;
IF @DaysUptime IS NULL OR @DaysUptime = 0 SET @DaysUptime = 0.1;

/* CPU per database from the plan cache */
IF OBJECT_ID('tempdb..#cpu') IS NOT NULL DROP TABLE #cpu;
SELECT CONVERT(INT, pa.value) AS database_id
     , SUM(qs.total_worker_time) / 1000 AS cpu_ms
INTO #cpu
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
WHERE pa.attribute = N'dbid'
GROUP BY CONVERT(INT, pa.value)
OPTION (RECOMPILE);

/* IO, throughput and latency per database since startup */
IF OBJECT_ID('tempdb..#io') IS NOT NULL DROP TABLE #io;
SELECT vfs.database_id
     , SUM(vfs.num_of_reads)                                   AS reads
     , SUM(vfs.num_of_writes)                                  AS writes
     , SUM(vfs.num_of_reads + vfs.num_of_writes)               AS total_io
     , SUM(vfs.num_of_bytes_read + vfs.num_of_bytes_written)   AS total_bytes
     , SUM(vfs.io_stall_read_ms)                               AS stall_read_ms
     , SUM(vfs.io_stall_write_ms)                              AS stall_write_ms
     , SUM(vfs.io_stall)                                       AS stall_ms
INTO #io
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
GROUP BY vfs.database_id
OPTION (RECOMPILE);

/* Buffer pool pages per database, behind the size gate */
IF OBJECT_ID('tempdb..#buf') IS NOT NULL DROP TABLE #buf;
CREATE TABLE #buf (database_id INT PRIMARY KEY, buffer_pages BIGINT);

DECLARE @BufferPoolMB BIGINT;
SELECT @BufferPoolMB = cntr_value * 8 / 1024
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Database pages'
  AND [object_name] LIKE '%Buffer Manager%';

IF @BufferPoolMB IS NOT NULL
   AND ISNULL(@BufferScanMaxGB, 0) > 0
   AND @BufferPoolMB <= CONVERT(BIGINT, @BufferScanMaxGB) * 1024
BEGIN
    INSERT #buf (database_id, buffer_pages)
    SELECT database_id, COUNT_BIG(*)
    FROM sys.dm_os_buffer_descriptors
    WHERE database_id IS NOT NULL
    GROUP BY database_id
    OPTION (RECOMPILE);
END
ELSE
    RAISERROR(N'Buffer-pool scan skipped (pool larger than @BufferScanMaxGB, size unknown, or scan disabled). Buffer columns are NULL.', 0, 1) WITH NOWAIT;

DECLARE @BufScanned BIT = CASE WHEN EXISTS (SELECT 1 FROM #buf) THEN 1 ELSE 0 END;

/* Allocated size per database */
IF OBJECT_ID('tempdb..#size') IS NOT NULL DROP TABLE #size;
SELECT database_id, SUM(CONVERT(BIGINT, size)) * 8 / 1024 AS size_mb
INTO #size
FROM sys.master_files
GROUP BY database_id;

/* Result */
SELECT
      d.name                                                        AS database_name
    , ISNULL(c.cpu_ms, 0)                                           AS cpu_ms
    , CAST(100.0 * ISNULL(c.cpu_ms, 0)
           / NULLIF(SUM(ISNULL(c.cpu_ms, 0)) OVER (), 0) AS DECIMAL(5,2))      AS cpu_pct
    , i.total_io
    , CAST(100.0 * i.total_io
           / NULLIF(SUM(i.total_io) OVER (), 0) AS DECIMAL(5,2))                AS io_pct
    , i.reads
    , i.writes
    , CASE WHEN @BufScanned = 1 THEN ISNULL(b.buffer_pages, 0) / 128 END       AS buffer_mb
    , CASE WHEN @BufScanned = 1 THEN CAST(100.0 * ISNULL(b.buffer_pages, 0)
           / NULLIF(SUM(ISNULL(b.buffer_pages, 0)) OVER (), 0) AS DECIMAL(5,2)) END AS buffer_pct
    , CAST(s.size_mb / 1024.0 AS DECIMAL(18,2))                     AS size_gb
    , CAST(i.total_bytes / 1073741824.0 / @DaysUptime AS DECIMAL(18,2))       AS io_gb_per_day
    , i.stall_read_ms  / NULLIF(i.reads, 0)                         AS avg_read_latency_ms
    , i.stall_write_ms / NULLIF(i.writes, 0)                        AS avg_write_latency_ms
    , i.stall_ms       / NULLIF(i.total_io, 0)                      AS avg_latency_ms
FROM sys.databases AS d
LEFT JOIN #io   AS i ON i.database_id = d.database_id
LEFT JOIN #cpu  AS c ON c.database_id = d.database_id
LEFT JOIN #buf  AS b ON b.database_id = d.database_id
LEFT JOIN #size AS s ON s.database_id = d.database_id
ORDER BY i.total_io DESC, c.cpu_ms DESC
OPTION (RECOMPILE);

SELECT @DaysUptime AS days_since_sqlserver_start
     , @BufferPoolMB AS buffer_pool_data_mb
     , @BufScanned AS buffer_pool_scanned;

DROP TABLE #cpu; DROP TABLE #io; DROP TABLE #buf; DROP TABLE #size;
