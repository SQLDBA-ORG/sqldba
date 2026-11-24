/* =====================================================================================================
   nvarchar(max) right-sizing audit                                   SQL Server 2016 or later
   Run in the database you want to check. Read-only unless you run the fix script it prints.
   Run end to end on SQL Server 2017 and 2022 (Developer edition). 2016, 2019, 2025, Standard edition
   and Azure are untested. Needs VIEW DATABASE STATE, VIEW SERVER STATE and SELECT on the tables.

   WHAT YOU GET (result sets, in order)
     1. Overview   one row: recovery model, whether ONLINE is usable, how many columns fall in each verdict.
                   TablesChecked is lower than TablesWithMaxColumns when @TopTables cut the list.
     2. Tables     one row per table: size, how hot it is, and the estimated log cost of each way to fix it.
     3. Columns    one row per nvarchar(max) column: verdict, suggested type, what blocks the change.
     4. FixScript  only when @FixScript is COLUMN or TABLE: copy the Script column into a new query window.
     With @TopQueries set, a TopQueries result comes second: the queries that were read and what they touch.

   HIGH IMPACT ONLY (@TopQueries = N)
     Keeps only the tables that the N heaviest queries of THIS database touch, so the list is the short
     one worth fixing first. It ranks queries by @TopQueriesBy, reads one plan for each, and keeps a table
     when a plan names it. A query whose plan names no user table of this database (monitoring, catalog
     and this audit's own queries) is passed over and does not use up one of the N places.
     The Why column then says which top queries use each column itself (read or write): a table can be
     in a plan through an index that never carries the nvarchar(max) column.
     Where the queries come from (@TopQueriesFrom): Query Store when it is on for this database and holds
     data for the last @TopQueriesDays days, because it survives restarts and memory pressure; otherwise
     the plan cache, which can be nearly
     empty on a server short of memory or just restarted. The TopQueries result names the source that was
     used, and its LastSeen column shows how fresh each query is (a Query Store that went read-only is stale).
     Plan cache: the instance's 5,000 heaviest cached statements are looked at, and of those only the
     ones compiled in this database's context are ranked. Query Store: the last @TopQueriesDays days are
     ranked (default 7; NULL = everything it holds, which is slow on a large Query Store).
     The audit's own table scans are left out by a marker comment.
     A heavy query with no plan to read (a single-use ad hoc query under 'optimize for ad hoc workloads',
     or a plan already evicted) is listed with a blank rank and does not use up a place either.
     Limits, so it stays cheap on a busy server: at most N + 100 plans, read one at a time as plain text
     (no XML is loaded, so the read needs no memory grant), and it stops as soon as N queries are kept.
     Every ranking step runs MAXDOP 1 with its memory grant capped at 1%, because the optimizer
     over-estimates Query Store and asks for far too much: on a server short of query memory an uncapped
     step queued for minutes (RESOURCE_SEMAPHORE, measured 2026-11-24). A plan over 5 million characters
     is skipped and shown as not read. A ranking step can still wait a little if the server has no query
     memory free at all.
     The ranking works in small steps through temp tables: one pass over Query Store's runtime
     statistics, then text and plans for about 100 queries only.
     The Messages tab shows a line with the elapsed time after each step, so a slow step names itself.

   VERDICTS (result set 3)
     SHRINK       every value fits nvarchar(4000) and nothing blocks ALTER COLUMN. A fix is scripted.
     BLOCKED      it fits, but ALTER COLUMN is refused while the named objects exist. No fix is scripted.
     FORCE        only with @ForceBlocked = 1: it fits and is blocked only by objects this script can drop
                  and re-create. A fix is scripted (see FORCING A BLOCKED COLUMN).
     KEEP MAX     at least one row holds more than 4,000 characters.
     NO DATA      table empty, column all NULL, or only empty strings. Ask the application owner.
     NOT SCANNED  table is over @MaxRowsToScan.      SCAN FAILED  the scan raised an error (shown in Why).

   FORCING A BLOCKED COLUMN (@ForceBlocked = 1)
     For a column blocked only by a plain nonclustered index (INCLUDE or filter), user-created statistics
     or a check constraint, the fix script does this in ONE transaction: drop them, ALTER the column,
     re-create them. XACT_ABORT is on, so if any step fails everything rolls back and nothing has changed.
     The table is locked for the whole transaction, so the ALTER runs offline, and each re-created index
     is a full build that is logged at the index's size under FULL recovery.
     What is carried over. Index: unique, key order, INCLUDE list, filter, PAD_INDEX, FILLFACTOR,
     IGNORE_DUP_KEY, STATISTICS_NORECOMPUTE, row and page lock settings, ROW or PAGE compression,
     filegroup. Statistics: columns, filter, NORECOMPUTE, INCREMENTAL. Check constraint: definition,
     trusted or not, disabled or not, NOT FOR REPLICATION.
     What is NOT carried over: a statistics sample rate or FULLSCAN (the re-created one samples by
     default), and a system-generated constraint name becomes an ordinary name.
     Never forced, they stay BLOCKED and the Why column says which: an index that is partitioned,
     disabled, backs a constraint, is used by a foreign key, carries an extended property, or uses
     OPTIMIZE_FOR_SEQUENTIAL_KEY or XML compression; a definition or filter that spans lines; a computed
     column; a schema-bound view or function; full-text; and every table-level blocker.
     One index that covers two forced columns is dropped and rebuilt once for each column.

   LOG ESTIMATES: planning figures, measured 2026-11-14 on SQL Server 2022 CU27 (tables of 76 to 310 MB)
     Offline ALTER COLUMN   rows x 450 bytes + 2 x the column's data (3 x on a heap). Fully logged in EVERY
                            recovery model. Actual was 0.55 to 1.0 times this. The table also grows (1.2x to 2.7x
                            measured) because the old values stay in the pages until a REBUILD.
     REBUILD (offline)      the table's size under FULL recovery (actual 0.6 to 1.0 times: low when pages
                            are part empty); about 1% of it under SIMPLE or BULK_LOGGED.
     ONLINE ALTER COLUMN    PER COLUMN: the table's size + 350 bytes a row under FULL; 25% of the in-row
                            size + 75% of the off-row size under SIMPLE. Actual was 0.7 to 1.0 times these.
                            Leaves no dead space, so no REBUILD after it. An ONLINE REBUILD costs the same
                            as one ONLINE ALTER (measured 132 MB FULL, 18 MB SIMPLE on a 76 MB table).
     Copy-and-swap (new table, bulk insert, rename) was measured too. It is left out on purpose: it is
     several changes in one go.
     BULK_LOGGED is treated like SIMPLE for log FILE growth. Its next log backup is still large.
     A FULL database with no log backup chain yet truncates like SIMPLE and is treated that way.
     Whole fix scripts, estimate against actual: 0.7 to 0.93 on 2022 (five runs), 1.06 on 2017 (one run).

   FACTS THE FIX SCRIPT RELIES ON (each one run on SQL Server 2022, 2026-11-14)
     - ALTER COLUMN without NULL / NOT NULL made a NOT NULL column nullable, and without COLLATE reset the
       column to the database collation. The script always states both.
     - A default constraint blocks the change (Msg 5074). The script drops and re-creates it inside one
       transaction with the ALTER. That ALTER runs offline even when ONLINE is available.
     - An index (INCLUDE too), user-created statistics, a check constraint, a computed column or a
       schema-bound view on the column blocks it. Auto-created statistics do not; they are dropped.
     - If a longer value arrived after the scan, the ALTER fails with Msg 2628 and changes nothing.
     - The scan reads each table once and does not read off-row pages (0 LOB reads measured).
   ===================================================================================================== */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;   -- the scan takes no shared locks

DECLARE
    @TableLike     nvarchar(600) = NULL,        -- NULL = every table, or a LIKE pattern on schema.table, e.g. N'dbo.Order%'
    @TopTables     int           = NULL,        -- NULL = every table, or N = only the N most-read tables that have an nvarchar(max) column
    @TopQueries    int           = NULL,        -- NULL = off, or N (1 to 100) = high impact only: keep the tables the N heaviest queries touch
    @TopQueriesBy  varchar(10)   = 'CPU',       -- what "heaviest" means: CPU | READS | DURATION | GRANT (memory)
    @TopQueriesFrom varchar(10)  = 'AUTO',      -- AUTO (Query Store if it is on and holds data, else the plan cache) | QUERYSTORE | CACHE
    @TopQueriesDays int          = 7,           -- Query Store only: rank the last N days; NULL = everything it holds (slow on a large one)
    @MaxRowsToScan bigint        = 50000000,    -- bigger tables are listed but not scanned; NULL = scan everything
    @ScanMaxDop    int           = 2,           -- MAXDOP for each scan; NULL = server default
    @HeadroomPct   int           = 50,          -- suggested size = longest value + this %, rounded up to a tidy size
    @FixScript     varchar(10)   = 'NONE',      -- NONE | COLUMN (one block per column) | TABLE (one block per table)
    @UseOnline     bit           = 1,           -- use WITH (ONLINE = ON) where the edition and the table allow it
    @ForceBlocked  bit           = 0;           -- 1 = also script a column blocked only by an index, statistics or a check constraint: drop, ALTER, re-create, one transaction

IF @FixScript NOT IN ('NONE', 'COLUMN', 'TABLE')
BEGIN
    RAISERROR('@FixScript must be NONE, COLUMN or TABLE.', 16, 1);
    RETURN;
END;

IF @TopTables < 1
BEGIN
    RAISERROR('@TopTables must be NULL (every table) or 1 or more.', 16, 1);
    RETURN;
END;

IF @TopQueries < 1 OR @TopQueries > 100
   OR @TopQueriesBy IS NULL OR @TopQueriesBy NOT IN ('CPU', 'READS', 'DURATION', 'GRANT')
   OR @TopQueriesFrom IS NULL OR @TopQueriesFrom NOT IN ('AUTO', 'QUERYSTORE', 'CACHE')
   OR @TopQueriesDays < 1
BEGIN
    RAISERROR('@TopQueries must be NULL or 1 to 100; @TopQueriesBy CPU, READS, DURATION or GRANT; @TopQueriesFrom AUTO, QUERYSTORE or CACHE; @TopQueriesDays NULL or 1 or more.', 16, 1);
    RETURN;
END;

-- =====================================================================================================
-- 0. Environment
-- =====================================================================================================
DECLARE @Recovery nvarchar(60), @FullyLogged bit, @OnlineOk bit, @StatsSince datetime, @Msg nvarchar(2048);
DECLARE @T0 datetime2(3) = SYSDATETIME();      -- start of the run, for the elapsed-time lines in Messages (@TopQueries only)

SELECT @Recovery    = d.recovery_model_desc COLLATE DATABASE_DEFAULT,
       @FullyLogged = CASE WHEN d.recovery_model_desc = N'FULL' AND rs.last_log_backup_lsn IS NOT NULL THEN 1 ELSE 0 END
FROM sys.databases AS d
LEFT JOIN sys.database_recovery_status AS rs ON rs.database_id = d.database_id
WHERE d.database_id = DB_ID();

-- ONLINE ALTER COLUMN: Enterprise / Developer / Evaluation (3), Azure SQL Database (5), Managed Instance (8)
SET @OnlineOk    = CASE WHEN @UseOnline = 1 AND CAST(SERVERPROPERTY('EngineEdition') AS int) IN (3, 5, 8) THEN 1 ELSE 0 END;
SET @StatsSince  = (SELECT sqlserver_start_time FROM sys.dm_os_sys_info);

IF OBJECT_ID('tempdb..#Tab')  IS NOT NULL DROP TABLE #Tab;
IF OBJECT_ID('tempdb..#Col')  IS NOT NULL DROP TABLE #Col;
IF OBJECT_ID('tempdb..#Scan') IS NOT NULL DROP TABLE #Scan;
IF OBJECT_ID('tempdb..#Blk')  IS NOT NULL DROP TABLE #Blk;
IF OBJECT_ID('tempdb..#Fix')  IS NOT NULL DROP TABLE #Fix;
IF OBJECT_ID('tempdb..#TopQ') IS NOT NULL DROP TABLE #TopQ;
IF OBJECT_ID('tempdb..#Cand') IS NOT NULL DROP TABLE #Cand;
IF OBJECT_ID('tempdb..#PlanRef') IS NOT NULL DROP TABLE #PlanRef;
IF OBJECT_ID('tempdb..#QsPlan') IS NOT NULL DROP TABLE #QsPlan;
IF OBJECT_ID('tempdb..#QsTop')  IS NOT NULL DROP TABLE #QsTop;
IF OBJECT_ID('tempdb..#QsRows') IS NOT NULL DROP TABLE #QsRows;
IF OBJECT_ID('tempdb..#QsDb')   IS NOT NULL DROP TABLE #QsDb;
IF OBJECT_ID('tempdb..#BlkObj') IS NOT NULL DROP TABLE #BlkObj;
IF OBJECT_ID('tempdb..#IdxNew') IS NOT NULL DROP TABLE #IdxNew;

-- =====================================================================================================
-- 1. Find the tables and columns (catalog only)
-- =====================================================================================================
CREATE TABLE #Tab (
    ObjectId     int            NOT NULL PRIMARY KEY,
    SchemaName   sysname        COLLATE DATABASE_DEFAULT NOT NULL,
    TableName    sysname        COLLATE DATABASE_DEFAULT NOT NULL,
    FullName     nvarchar(520)  COLLATE DATABASE_DEFAULT NOT NULL,      -- [schema].[table]
    IsHeap       bit            NOT NULL,
    ApproxRows   bigint         NOT NULL,
    BaseMB       decimal(18, 2) NOT NULL,      -- heap or clustered index, off-row pages included
    OffRowMB     decimal(18, 2) NOT NULL,      -- LOB + row-overflow pages of the heap or clustered index
    NcIndexMB    decimal(18, 2) NOT NULL,
    TableBlocker nvarchar(400)  COLLATE DATABASE_DEFAULT NULL,          -- no fix is scripted for any column of this table
    OnlineBar    nvarchar(200)  COLLATE DATABASE_DEFAULT NULL,          -- ONLINE cannot be used on this table
    ScanStatus   varchar(10)    COLLATE DATABASE_DEFAULT NOT NULL,      -- PENDING, SCANNED, SKIPPED, FAILED
    ScanError    nvarchar(2048) COLLATE DATABASE_DEFAULT NULL,
    BaseReads    bigint         NOT NULL DEFAULT 0,
    BaseWrites   bigint         NOT NULL DEFAULT 0,
    LobFetches   bigint         NOT NULL DEFAULT 0,
    TableRank    int            NULL
);

INSERT INTO #Tab (ObjectId, SchemaName, TableName, FullName, IsHeap, ApproxRows, BaseMB, OffRowMB, NcIndexMB,
                  TableBlocker, OnlineBar, ScanStatus)
SELECT
    t.object_id,
    SCHEMA_NAME(t.schema_id),
    t.name,
    QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name),
    CASE WHEN EXISTS (SELECT 1 FROM sys.indexes AS i WHERE i.object_id = t.object_id AND i.index_id = 0) THEN 1 ELSE 0 END,
    ISNULL(ps.ApproxRows, 0),
    ISNULL(ps.BasePages, 0)   * 8 / 1024.0,
    ISNULL(ps.OffRowPages, 0) * 8 / 1024.0,
    ISNULL(ps.NcPages, 0)     * 8 / 1024.0,
    STUFF(
        CASE WHEN t.is_memory_optimized = 1 THEN N'; memory-optimized table' ELSE N'' END
      + CASE t.temporal_type WHEN 2 THEN N'; system-versioned (temporal) table' WHEN 1 THEN N'; temporal history table' ELSE N'' END
      + CASE WHEN t.is_replicated = 1 OR t.is_published = 1 OR t.is_merge_published = 1 THEN N'; replicated table' ELSE N'' END
      + CASE WHEN t.is_tracked_by_cdc = 1 THEN N'; tracked by change data capture' ELSE N'' END
      + CASE WHEN t.is_filetable = 1 THEN N'; FileTable' ELSE N'' END
      + CASE WHEN t.is_external = 1 THEN N'; external table' ELSE N'' END
      + CASE WHEN EXISTS (SELECT 1 FROM sys.indexes AS i WHERE i.object_id = t.object_id AND i.type IN (5, 6))
             THEN N'; has a columnstore index' ELSE N'' END
      , 1, 2, N''),
    CASE WHEN EXISTS (SELECT 1 FROM sys.change_tracking_tables AS ct WHERE ct.object_id = t.object_id)
         THEN N'change tracking is on' END,
    'PENDING'
FROM sys.tables AS t
OUTER APPLY (
    SELECT SUM(CASE WHEN p.index_id IN (0, 1) THEN p.row_count ELSE 0 END)                                      AS ApproxRows,
           SUM(CASE WHEN p.index_id IN (0, 1) THEN p.used_page_count ELSE 0 END)                                AS BasePages,
           SUM(CASE WHEN p.index_id IN (0, 1) THEN p.lob_used_page_count + p.row_overflow_used_page_count ELSE 0 END) AS OffRowPages,
           SUM(CASE WHEN p.index_id > 1       THEN p.used_page_count ELSE 0 END)                            AS NcPages
    FROM sys.dm_db_partition_stats AS p
    WHERE p.object_id = t.object_id
) AS ps
WHERE t.is_ms_shipped = 0
  AND (@TableLike IS NULL OR SCHEMA_NAME(t.schema_id) + N'.' + t.name LIKE @TableLike)
  AND EXISTS (SELECT 1 FROM sys.columns AS c
              WHERE c.object_id = t.object_id AND c.system_type_id = 231 AND c.max_length = -1 AND c.is_computed = 0);

-- How hot is each table. Reads and Writes are for the heap or clustered index only: a nonclustered index
-- cannot carry these columns unless it INCLUDEs them. LobFetches is how often SQL Server fetched a max or
-- overflow value (in-row values count too). Counters reset at instance start; LobFetches also resets when
-- the table's metadata leaves the cache, so read it as "at least".
UPDATE t
SET BaseReads = u.Reads, BaseWrites = u.Writes
FROM #Tab AS t
INNER JOIN (SELECT object_id,
                   SUM(user_seeks + user_scans + user_lookups) AS Reads,
                   SUM(user_updates)                           AS Writes
            FROM sys.dm_db_index_usage_stats
            WHERE database_id = DB_ID() AND index_id IN (0, 1)
            GROUP BY object_id) AS u ON u.object_id = t.ObjectId;

DECLARE @DbBaseReads bigint =
    (SELECT SUM(u.user_seeks + u.user_scans + u.user_lookups)
     FROM sys.dm_db_index_usage_stats AS u
     WHERE u.database_id = DB_ID() AND u.index_id IN (0, 1) AND OBJECTPROPERTY(u.object_id, 'IsUserTable') = 1);

DECLARE @TablesFound int = (SELECT COUNT(*) FROM #Tab);

-- @TopQueries: high impact only. Rank this database's queries, read one plan each, and keep only the
-- tables those plans name. Done here, before the scan, so the tables left out cost nothing.
CREATE TABLE #TopQ (
    QueryRank   int            NOT NULL PRIMARY KEY,   -- rank among the candidates
    KeepRank    int            NULL,                   -- rank among the queries kept (1 to @TopQueries): the number shown
    Measure     bigint         NOT NULL,
    Executions  bigint         NOT NULL,
    LastSeen    datetime       NULL,          -- plan cache: when the plan was compiled; Query Store: last execution
    QueryText   nvarchar(400)  COLLATE DATABASE_DEFAULT NULL,
    PlanHandle  varbinary(64)  NULL,
    StartOffset int            NULL,
    EndOffset   int            NULL,
    PlanText    nvarchar(max)  COLLATE DATABASE_DEFAULT NULL,
    PlanRead    nvarchar(200)  COLLATE DATABASE_DEFAULT NULL
);
-- one row per table (ColumnName NULL) or column that a top query's plan names; names as the plan writes them
CREATE TABLE #PlanRef (
    QueryRank  int           NOT NULL,
    SchemaQ    nvarchar(260) COLLATE DATABASE_DEFAULT NOT NULL,   -- [schema]
    TableQ     nvarchar(260) COLLATE DATABASE_DEFAULT NOT NULL,   -- [table]
    ColumnName nvarchar(260) COLLATE DATABASE_DEFAULT NULL
);

DECLARE @QSource varchar(10) = NULL;

IF @TopQueries IS NOT NULL
BEGIN
    SET @Msg = FORMAT(DATEDIFF(MILLISECOND, @T0, SYSDATETIME()) / 1000.0, 'N1') + N' s: ' + CAST(@TablesFound AS nvarchar(10)) + N' tables have an nvarchar(max) column. Choosing where to rank the top queries.';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    -- Query Store window: the first interval that ends inside the last @TopQueriesDays days (NULL days = no lower bound)
    DECLARE @MinInterval bigint = NULL, @QsUsable bit = 0;

    IF EXISTS (SELECT 1 FROM sys.database_query_store_options WHERE actual_state IN (1, 2))
    BEGIN
        IF @TopQueriesDays IS NOT NULL
            SELECT @MinInterval = MIN(i.runtime_stats_interval_id)
            FROM sys.query_store_runtime_stats_interval AS i
            WHERE i.end_time >= DATEADD(DAY, -@TopQueriesDays, SYSDATETIMEOFFSET());

        IF @TopQueriesDays IS NULL OR @MinInterval IS NOT NULL
            IF EXISTS (SELECT 1 FROM sys.query_store_runtime_stats AS rs
                       WHERE rs.runtime_stats_interval_id >= ISNULL(@MinInterval, 0))
                SET @QsUsable = 1;
    END;

    SET @QSource = CASE WHEN @TopQueriesFrom <> 'AUTO' THEN @TopQueriesFrom
                        WHEN @QsUsable = 1 THEN 'QUERYSTORE'
                        ELSE 'CACHE' END;

    SET @Msg = FORMAT(DATEDIFF(MILLISECOND, @T0, SYSDATETIME()) / 1000.0, 'N1') + N' s: ranking queries by ' + @TopQueriesBy + N' from '
             + CASE @QSource WHEN 'QUERYSTORE' THEN N'Query Store' + ISNULL(N', last ' + CAST(@TopQueriesDays AS nvarchar(10)) + N' days', N', all it holds')
                             ELSE N'the plan cache' END + N'.';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    IF @QSource = 'QUERYSTORE'
    BEGIN
        -- Step 1: one pass over the runtime statistics, nothing joined, summed per plan.
        SELECT rs.plan_id,
               SUM(CASE @TopQueriesBy WHEN 'CPU'      THEN rs.avg_cpu_time * rs.count_executions / 1000
                                      WHEN 'READS'    THEN rs.avg_logical_io_reads * rs.count_executions
                                      WHEN 'DURATION' THEN rs.avg_duration * rs.count_executions / 1000
                                      ELSE                 rs.avg_query_max_used_memory * rs.count_executions * 8 END) AS Measure,
               SUM(rs.count_executions)    AS Executions,
               MAX(rs.last_execution_time) AS LastSeen
        INTO #QsPlan
        FROM sys.query_store_runtime_stats AS rs
        WHERE rs.runtime_stats_interval_id >= ISNULL(@MinInterval, 0)
        GROUP BY rs.plan_id
        OPTION (RECOMPILE, MAXDOP 1, MAX_GRANT_PERCENT = 1);

        -- Step 2: plans to queries in one join that carries no text and no plan. Keep the heaviest N + 100 queries
        -- (spare: a query that names no user table is passed over), each with the plan it used last in the window.
        SELECT TOP (@TopQueries + 100)
               x.query_id, x.plan_id, x.Measure, x.Executions, x.LastSeen
        INTO #QsTop
        FROM (SELECT p.query_id, p.plan_id,
                     CAST(SUM(a.Measure) OVER (PARTITION BY p.query_id) AS bigint) AS Measure,
                     SUM(a.Executions)   OVER (PARTITION BY p.query_id)            AS Executions,
                     MAX(a.LastSeen)     OVER (PARTITION BY p.query_id)            AS LastSeen,
                     ROW_NUMBER()        OVER (PARTITION BY p.query_id ORDER BY a.LastSeen DESC, p.plan_id DESC) AS rn
              FROM #QsPlan AS a
              INNER JOIN sys.query_store_plan AS p ON p.plan_id = a.plan_id) AS x
        WHERE x.rn = 1
        ORDER BY x.Measure DESC, x.query_id
        OPTION (MAXDOP 1, MAX_GRANT_PERCENT = 1);

        -- Step 3: text and plan for those queries only, each found by its key.
        INSERT INTO #TopQ (QueryRank, Measure, Executions, LastSeen, QueryText, PlanText)
        SELECT ROW_NUMBER() OVER (ORDER BY g.Measure DESC, g.query_id),
               g.Measure, g.Executions,
               CAST(SWITCHOFFSET(g.LastSeen, DATENAME(TZOFFSET, SYSDATETIMEOFFSET())) AS datetime),
               LEFT(REPLACE(REPLACE(REPLACE(qt.query_sql_text, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' '), 400),
               p.query_plan
        FROM #QsTop AS g
        INNER JOIN sys.query_store_query AS q ON q.query_id = g.query_id
        INNER JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
        INNER JOIN sys.query_store_plan AS p ON p.plan_id = g.plan_id
        WHERE q.is_internal_query = 0
        OPTION (MAXDOP 1, MAX_GRANT_PERCENT = 1);

        -- the audit's own scans, by their marker (it sits in the first 400 characters of the statement)
        DELETE FROM #TopQ WHERE QueryText LIKE N'%nvarchar(max) right-sizing audit%';
    END;
    ELSE
    BEGIN
        -- Plan cache. The same query cached many times (different literals) is one query: grouped by query_hash.
        SELECT TOP (5000)
               qs.plan_handle, qs.sql_handle, qs.statement_start_offset, qs.statement_end_offset, qs.creation_time, qs.execution_count, qs.query_hash,
               CAST(CASE @TopQueriesBy WHEN 'CPU'      THEN qs.total_worker_time / 1000
                                       WHEN 'READS'    THEN qs.total_logical_reads
                                       WHEN 'DURATION' THEN qs.total_elapsed_time / 1000
                                       ELSE                 ISNULL(qs.total_grant_kb, 0) END AS bigint) AS Measure
        INTO #QsRows
        FROM sys.dm_exec_query_stats AS qs
        ORDER BY Measure DESC
        OPTION (MAXDOP 1, MAX_GRANT_PERCENT = 1);

        -- which of their plans were compiled in this database's context
        SELECT h.plan_handle
        INTO #QsDb
        FROM (SELECT DISTINCT plan_handle FROM #QsRows) AS h
        CROSS APPLY sys.dm_exec_plan_attributes(h.plan_handle) AS pa
        WHERE pa.attribute = N'dbid' AND CAST(pa.value AS int) = DB_ID()
        OPTION (MAXDOP 1, MAX_GRANT_PERCENT = 1);

        WITH s AS (
            SELECT qs.plan_handle, qs.sql_handle, qs.statement_start_offset, qs.statement_end_offset, qs.creation_time, qs.execution_count,
                   qs.Measure,
                   CASE WHEN qs.query_hash = 0x0000000000000000
                        THEN CAST(qs.plan_handle AS varbinary(72)) + CAST(qs.statement_start_offset AS binary(4))
                        ELSE CAST(qs.query_hash AS varbinary(72)) END AS GroupKey
            FROM #QsRows AS qs
            INNER JOIN #QsDb AS d ON d.plan_handle = qs.plan_handle
        ), g AS (
            SELECT s.*,
                   SUM(s.Measure)         OVER (PARTITION BY s.GroupKey) AS GroupMeasure,
                   SUM(s.execution_count) OVER (PARTITION BY s.GroupKey) AS GroupExecs,
                   ROW_NUMBER()           OVER (PARTITION BY s.GroupKey ORDER BY s.Measure DESC, s.creation_time DESC) AS rn
            FROM s
        )
        SELECT TOP (@TopQueries + 300)       -- spare rows, because the audit's own statements are dropped next
               g.plan_handle, g.sql_handle, g.statement_start_offset, g.statement_end_offset, g.creation_time,
               g.GroupMeasure, g.GroupExecs, g.GroupKey
        INTO #Cand
        FROM g
        WHERE g.rn = 1
        ORDER BY g.GroupMeasure DESC, g.GroupKey
        OPTION (MAXDOP 1, MAX_GRANT_PERCENT = 1);

        INSERT INTO #TopQ (QueryRank, Measure, Executions, LastSeen, QueryText, PlanHandle, StartOffset, EndOffset)
        SELECT TOP (@TopQueries + 100)
               ROW_NUMBER() OVER (ORDER BY c.GroupMeasure DESC, c.GroupKey),
               c.GroupMeasure, c.GroupExecs, c.creation_time,
               LEFT(REPLACE(REPLACE(REPLACE(
                    SUBSTRING(st.text, c.statement_start_offset / 2 + 1,
                              (CASE WHEN c.statement_end_offset = -1 THEN DATALENGTH(st.text) ELSE c.statement_end_offset END
                               - c.statement_start_offset) / 2 + 1),
                    NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' '), 400),
               c.plan_handle, c.statement_start_offset, c.statement_end_offset
        FROM #Cand AS c
        OUTER APPLY sys.dm_exec_sql_text(c.sql_handle) AS st
        WHERE ISNULL(st.text, N'') NOT LIKE N'%nvarchar(max) right-sizing audit%'
        ORDER BY c.GroupMeasure DESC, c.GroupKey
        OPTION (MAXDOP 1, MAX_GRANT_PERCENT = 1);

        -- plan text for the candidates only
        UPDATE q
        SET PlanText = tp.query_plan
        FROM #TopQ AS q
        OUTER APPLY sys.dm_exec_text_query_plan(q.PlanHandle, q.StartOffset, q.EndOffset) AS tp;
    END;

    SET @Msg = FORMAT(DATEDIFF(MILLISECOND, @T0, SYSDATETIME()) / 1000.0, 'N1') + N' s: ' + CAST((SELECT COUNT(*) FROM #TopQ) AS nvarchar(10)) + N' candidate queries ranked. Reading their plans.';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    -- Read the plans one at a time, as TEXT. A plan names what it touches as
    --     Database="[db]" Schema="[schema]" Table="[table]" [Alias="[a]"] Column="column"
    -- (Column only on a column reference; names XML-escaped). One pass over the text finds every such
    -- reference. Nothing here sorts, hashes or loads XML, so it needs no memory grant: reading the same
    -- plan through XML queued 11 to 70 seconds for memory on a server short of it (measured 2026-11-24).
    -- A candidate is kept when its plan names a user table of this database. One with no plan at all is
    -- listed but takes no place. One whose plan names no user table is dropped. The read stops at
    -- @TopQueries kept.
    DECLARE @Rank int, @PlanText nvarchar(max), @PlanRead nvarchar(200), @Kept int = 0, @PlansRead int = 0,
            @DbPfx nvarchar(600), @Pos bigint, @Q1 bigint, @Q2 bigint, @Cur bigint, @Refs int,
            @Sch nvarchar(1000), @Tbl nvarchar(1000), @ColName nvarchar(1000),
            @LastSch nvarchar(1000), @LastTbl nvarchar(1000), @LastCol nvarchar(1000);

    -- the database name as the plan writes it: bracketed, then XML-escaped
    SET @DbPfx = N'Database="' + REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(QUOTENAME(DB_NAME()), N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;'), N'"', N'&quot;'), N'''', N'&apos;')
               + N'" Schema="';

    DECLARE PlanCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT QueryRank, PlanText FROM #TopQ ORDER BY QueryRank;

    OPEN PlanCursor;
    FETCH NEXT FROM PlanCursor INTO @Rank, @PlanText;

    WHILE @@FETCH_STATUS = 0 AND @Kept < @TopQueries
    BEGIN
        SET @PlansRead += 1;

        IF @PlanText IS NULL
            SET @PlanRead = CASE WHEN @QSource = 'CACHE' THEN N'No: no plan in the cache (single-use ad hoc query, or evicted). Not counted.'
                                 ELSE N'No: Query Store holds no plan. Not counted.' END;
        ELSE IF DATALENGTH(@PlanText) > 10000000
            SET @PlanRead = N'No: plan is over 5 million characters';
        ELSE
        BEGIN
            SELECT @Refs = 0, @LastSch = NULL, @LastTbl = NULL, @LastCol = NULL;
            SET @Pos = CHARINDEX(@DbPfx COLLATE Latin1_General_100_BIN2, @PlanText COLLATE Latin1_General_100_BIN2);

            WHILE @Pos > 0 AND @Refs < 200000
            BEGIN
                SET @Refs += 1;
                SET @Cur = @Pos + LEN(@DbPfx);                                                      -- first character of the schema value
                SET @Q1  = CHARINDEX(N'"', @PlanText COLLATE Latin1_General_100_BIN2, @Cur);        -- its closing quote
                SELECT @Sch = SUBSTRING(@PlanText, @Cur, @Q1 - @Cur), @Tbl = NULL, @ColName = NULL;

                IF @Q1 > 0 AND SUBSTRING(@PlanText, @Q1, 9) COLLATE Latin1_General_100_BIN2 = N'" Table="'
                BEGIN
                    SET @Cur = @Q1 + 9;
                    SET @Q2  = CHARINDEX(N'"', @PlanText COLLATE Latin1_General_100_BIN2, @Cur);
                    SET @Tbl = SUBSTRING(@PlanText, @Cur, @Q2 - @Cur);
                    SET @Cur = @Q2;

                    IF SUBSTRING(@PlanText, @Cur, 9) COLLATE Latin1_General_100_BIN2 = N'" Alias="'
                        SET @Cur = CHARINDEX(N'"', @PlanText COLLATE Latin1_General_100_BIN2, @Cur + 9);   -- step over the alias

                    IF SUBSTRING(@PlanText, @Cur, 10) COLLATE Latin1_General_100_BIN2 = N'" Column="'
                    BEGIN
                        SET @Q2 = CHARINDEX(N'"', @PlanText COLLATE Latin1_General_100_BIN2, @Cur + 10);
                        SET @ColName = SUBSTRING(@PlanText, @Cur + 10, @Q2 - @Cur - 10);
                    END;

                    -- a plan repeats the same reference many times in a row: store a change only
                    IF @LastSch IS NULL OR @Sch <> @LastSch COLLATE Latin1_General_100_BIN2 OR @Tbl <> @LastTbl COLLATE Latin1_General_100_BIN2
                       OR ISNULL(@ColName, N'"') <> ISNULL(@LastCol, N'"') COLLATE Latin1_General_100_BIN2
                    BEGIN
                        SELECT @LastSch = @Sch, @LastTbl = @Tbl, @LastCol = @ColName;
                        -- back from XML text to the real name (&amp; last)
                        SELECT @Sch     = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@Sch,     N'&lt;', N'<'), N'&gt;', N'>'), N'&quot;', N'"'), N'&apos;', N''''), N'&amp;', N'&'),
                               @Tbl     = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@Tbl,     N'&lt;', N'<'), N'&gt;', N'>'), N'&quot;', N'"'), N'&apos;', N''''), N'&amp;', N'&'),
                               @ColName = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@ColName, N'&lt;', N'<'), N'&gt;', N'>'), N'&quot;', N'"'), N'&apos;', N''''), N'&amp;', N'&');

                        IF LEN(@Sch) <= 260 AND LEN(@Tbl) <= 260 AND ISNULL(LEN(@ColName), 0) <= 260
                           AND NOT EXISTS (SELECT 1 FROM #PlanRef AS r
                                           WHERE r.QueryRank = @Rank AND r.SchemaQ = @Sch AND r.TableQ = @Tbl
                                             AND (r.ColumnName = @ColName OR (r.ColumnName IS NULL AND @ColName IS NULL)))
                            INSERT INTO #PlanRef (QueryRank, SchemaQ, TableQ, ColumnName) VALUES (@Rank, @Sch, @Tbl, @ColName);
                    END;
                END;

                SET @Pos = CHARINDEX(@DbPfx COLLATE Latin1_General_100_BIN2, @PlanText COLLATE Latin1_General_100_BIN2, @Pos + LEN(@DbPfx));
            END;

            SET @PlanRead = CASE WHEN @Refs < 200000 THEN N'Yes' ELSE N'Yes: first 200,000 references only' END;
        END;

        IF @PlanText IS NULL
            UPDATE #TopQ SET PlanRead = @PlanRead WHERE QueryRank = @Rank;
        ELSE IF @PlanRead NOT LIKE N'Yes%' OR EXISTS (SELECT 1 FROM #PlanRef WHERE QueryRank = @Rank AND SchemaQ <> N'[sys]')
        BEGIN
            SET @Kept += 1;
            UPDATE #TopQ SET PlanRead = @PlanRead, KeepRank = @Kept WHERE QueryRank = @Rank;
        END;

        FETCH NEXT FROM PlanCursor INTO @Rank, @PlanText;
    END;

    CLOSE PlanCursor;
    DEALLOCATE PlanCursor;

    DELETE FROM #TopQ WHERE PlanRead IS NULL;      -- never reached, or its plan named no user table
    DELETE r FROM #PlanRef AS r WHERE NOT EXISTS (SELECT 1 FROM #TopQ AS q WHERE q.QueryRank = r.QueryRank);

    IF NOT EXISTS (SELECT 1 FROM #TopQ WHERE KeepRank IS NOT NULL)
        RAISERROR('@TopQueries: no query that names a user table was found in the %s for this database, so no table passes the filter.', 0, 1, @QSource) WITH NOWAIT;

    DELETE t
    FROM #Tab AS t
    WHERE NOT EXISTS (SELECT 1 FROM #PlanRef AS r
                      WHERE r.SchemaQ = QUOTENAME(t.SchemaName) AND r.TableQ = QUOTENAME(t.TableName));

    SET @Msg = FORMAT(DATEDIFF(MILLISECOND, @T0, SYSDATETIME()) / 1000.0, 'N1') + N' s: ' + CAST(@PlansRead AS nvarchar(10)) + N' plans read, ' + CAST(@Kept AS nvarchar(10)) + N' top queries kept, '
             + CAST((SELECT COUNT(*) FROM #Tab) AS nvarchar(10)) + N' tables pass the filter. Scanning those next.';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END;

-- @TopTables: keep only the N most-read tables. Done here, before the scan, so the others cost nothing.
-- Ties (tables with no reads since the restart, mostly) go to the most-written, then the largest.
IF @TopTables IS NOT NULL
    DELETE t
    FROM #Tab AS t
    INNER JOIN (SELECT ObjectId,
                       ROW_NUMBER() OVER (ORDER BY BaseReads DESC, BaseWrites DESC, BaseMB DESC, SchemaName, TableName) AS UsageRank
                FROM #Tab) AS r ON r.ObjectId = t.ObjectId
    WHERE r.UsageRank > @TopTables;

-- LobFetches, read after the cuts: per table when few are left, in one pass over the database otherwise
IF (SELECT COUNT(*) FROM #Tab) <= 200
    UPDATE t
    SET LobFetches = ISNULL(o.Pages, 0)
    FROM #Tab AS t
    CROSS APPLY (SELECT SUM(os.lob_fetch_in_pages + os.row_overflow_fetch_in_pages) AS Pages
                 FROM sys.dm_db_index_operational_stats(DB_ID(), t.ObjectId, NULL, NULL) AS os) AS o;
ELSE
    UPDATE t
    SET LobFetches = o.Pages
    FROM #Tab AS t
    INNER JOIN (SELECT object_id, SUM(lob_fetch_in_pages + row_overflow_fetch_in_pages) AS Pages
                FROM sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL)
                GROUP BY object_id) AS o ON o.object_id = t.ObjectId;

CREATE TABLE #Col (
    ObjectId      int            NOT NULL,
    ColumnId      int            NOT NULL,
    ColumnName    sysname        COLLATE DATABASE_DEFAULT NOT NULL,
    IsNullable    bit            NOT NULL,
    CollationName sysname        COLLATE DATABASE_DEFAULT NULL,
    DefaultName   sysname        COLLATE DATABASE_DEFAULT NULL,
    DefaultDef    nvarchar(max)  COLLATE DATABASE_DEFAULT NULL,
    Blockers      nvarchar(max)  COLLATE DATABASE_DEFAULT NULL,
    TopQueryRefs  nvarchar(400)  COLLATE DATABASE_DEFAULT NULL,          -- ranks of the top queries whose plan names this column
    ForceOk       bit            NOT NULL DEFAULT 0,                     -- @ForceBlocked: every blocker of this column can be dropped and re-created
    ForceNote     nvarchar(max)  COLLATE DATABASE_DEFAULT NULL,          -- @ForceBlocked: why it cannot
    -- filled by the scan
    RowCnt        bigint         NULL,
    NonNullRows   bigint         NULL,
    MaxChars      bigint         NULL,
    TotalBytes    bigint         NULL,
    RowsOver4000  bigint         NULL,
    -- derived
    NewLen        int            NULL,
    Verdict       varchar(12)    COLLATE DATABASE_DEFAULT NULL,
    GoesOnline    bit            NULL,
    AlterLogMB    decimal(18, 1) NULL,      -- log for the ALTER as it will be scripted
    OfflineLogMB  decimal(18, 1) NULL,      -- log for an offline ALTER
    PRIMARY KEY (ObjectId, ColumnId)
);

INSERT INTO #Col (ObjectId, ColumnId, ColumnName, IsNullable, CollationName, DefaultName, DefaultDef)
SELECT c.object_id, c.column_id, c.name, c.is_nullable, c.collation_name, dc.name, dc.definition
FROM sys.columns AS c
INNER JOIN #Tab AS t ON t.ObjectId = c.object_id
LEFT JOIN sys.default_constraints AS dc ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
WHERE c.system_type_id = 231 AND c.max_length = -1 AND c.is_computed = 0;

IF @TopQueries IS NOT NULL
    UPDATE c
    SET TopQueryRefs = STUFF((SELECT N', ' + CAST(d.KeepRank AS nvarchar(10))
                              FROM (SELECT DISTINCT q.KeepRank
                                    FROM #PlanRef AS r
                                    INNER JOIN #TopQ AS q ON q.QueryRank = r.QueryRank
                                    WHERE r.SchemaQ = QUOTENAME(t.SchemaName) AND r.TableQ = QUOTENAME(t.TableName)
                                      AND r.ColumnName = c.ColumnName) AS d
                              ORDER BY d.KeepRank
                              FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'')
    FROM #Col AS c
    INNER JOIN #Tab AS t ON t.ObjectId = c.ObjectId;

-- Everything that makes SQL Server refuse ALTER COLUMN, or that the ALTER would silently lose
-- Kind and RefId say what the blocker is, for @ForceBlocked: INDEX (index_id), STATS (stats_id), CHECK (object_id), OTHER.
CREATE TABLE #Blk (ObjectId int NOT NULL, ColumnId int NOT NULL, Reason nvarchar(400) COLLATE DATABASE_DEFAULT NOT NULL,
                   Kind varchar(10) COLLATE DATABASE_DEFAULT NOT NULL, RefId int NULL);

INSERT INTO #Blk (ObjectId, ColumnId, Reason, Kind, RefId)
SELECT c.ObjectId, c.ColumnId, N'index ' + QUOTENAME(i.name), 'INDEX', i.index_id
FROM #Col AS c
INNER JOIN sys.index_columns AS ic ON ic.object_id = c.ObjectId AND ic.column_id = c.ColumnId
INNER JOIN sys.indexes AS i ON i.object_id = ic.object_id AND i.index_id = ic.index_id
UNION ALL
SELECT c.ObjectId, c.ColumnId, N'statistics ' + QUOTENAME(s.name), 'STATS', s.stats_id
FROM #Col AS c
INNER JOIN sys.stats_columns AS sc ON sc.object_id = c.ObjectId AND sc.column_id = c.ColumnId
INNER JOIN sys.stats AS s ON s.object_id = sc.object_id AND s.stats_id = sc.stats_id
WHERE s.user_created = 1
UNION ALL
SELECT DISTINCT c.ObjectId, c.ColumnId,
       CASE WHEN d.referencing_class = 1 AND d.referencing_minor_id > 0
                 THEN N'computed column ' + QUOTENAME(COL_NAME(d.referencing_id, d.referencing_minor_id))
            WHEN d.referencing_class = 1
                 THEN LOWER(REPLACE(o.type_desc COLLATE DATABASE_DEFAULT, N'_', N' ')) + N' ' + QUOTENAME(o.name)
            WHEN d.referencing_class = 7
                 THEN N'filtered index ' + ISNULL(QUOTENAME(fi.name), N'')
            ELSE LOWER(REPLACE(d.referencing_class_desc COLLATE DATABASE_DEFAULT, N'_', N' ')) + N' (schema-bound)' END,
       CASE WHEN d.referencing_class = 1 AND d.referencing_minor_id = 0 AND o.type = 'C' THEN 'CHECK'
            WHEN d.referencing_class = 7 THEN 'INDEX'
            ELSE 'OTHER' END,
       CASE WHEN d.referencing_class = 1 AND d.referencing_minor_id = 0 AND o.type = 'C' THEN o.object_id
            WHEN d.referencing_class = 7 THEN d.referencing_minor_id END
FROM #Col AS c
INNER JOIN sys.sql_expression_dependencies AS d
        ON d.referenced_id = c.ObjectId AND d.referenced_minor_id = c.ColumnId AND d.is_schema_bound_reference = 1
LEFT JOIN sys.objects AS o  ON o.object_id = d.referencing_id AND d.referencing_class = 1
LEFT JOIN sys.indexes AS fi ON fi.object_id = d.referencing_id AND fi.index_id = d.referencing_minor_id AND d.referencing_class = 7
UNION ALL
SELECT c.ObjectId, c.ColumnId, N'full-text index', 'OTHER', NULL
FROM #Col AS c
INNER JOIN sys.fulltext_index_columns AS fc ON fc.object_id = c.ObjectId AND fc.column_id = c.ColumnId
UNION ALL
SELECT c.ObjectId, c.ColumnId, x.Reason, 'OTHER', NULL
FROM #Col AS c
INNER JOIN sys.columns AS sc ON sc.object_id = c.ObjectId AND sc.column_id = c.ColumnId
CROSS APPLY (VALUES
    (CASE WHEN sc.user_type_id <> sc.system_type_id THEN N'alias type ' + QUOTENAME(TYPE_NAME(sc.user_type_id)) END),
    (CASE WHEN sc.is_sparse = 1 THEN N'SPARSE column' END),
    (CASE WHEN sc.is_masked = 1 THEN N'dynamic data mask' END),
    (CASE WHEN sc.encryption_type IS NOT NULL THEN N'Always Encrypted column' END),
    (CASE WHEN sc.rule_object_id <> 0 THEN N'bound rule (sp_bindrule)' END),
    (CASE WHEN sc.default_object_id <> 0 AND c.DefaultName IS NULL THEN N'bound default (sp_bindefault)' END),
    (CASE WHEN c.DefaultDef LIKE N'%[' + NCHAR(10) + NCHAR(13) + N']%' THEN N'default ' + QUOTENAME(c.DefaultName) + N' spans lines' END)
) AS x (Reason)
WHERE x.Reason IS NOT NULL;

UPDATE c
SET Blockers = STUFF((SELECT N', ' + b.Reason
                      FROM #Blk AS b
                      WHERE b.ObjectId = c.ObjectId AND b.ColumnId = c.ColumnId
                      ORDER BY b.Reason
                      FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'')
FROM #Col AS c
WHERE EXISTS (SELECT 1 FROM #Blk AS b WHERE b.ObjectId = c.ObjectId AND b.ColumnId = c.ColumnId);

-- @ForceBlocked: for each blocking index, statistics object and check constraint, write the statement that
-- drops it and the one that re-creates it exactly, or say why this script will not (NoForce).
CREATE TABLE #BlkObj (
    ObjectId  int            NOT NULL,
    Kind      varchar(10)    COLLATE DATABASE_DEFAULT NOT NULL,
    RefId     int            NOT NULL,
    Label     nvarchar(300)  COLLATE DATABASE_DEFAULT NULL,
    NoForce   nvarchar(300)  COLLATE DATABASE_DEFAULT NULL,      -- NULL = it can be dropped and re-created
    DropSql   nvarchar(max)  COLLATE DATABASE_DEFAULT NULL,
    CreateSql nvarchar(max)  COLLATE DATABASE_DEFAULT NULL,
    PostSql   nvarchar(max)  COLLATE DATABASE_DEFAULT NULL,      -- a disabled check constraint is disabled again
    ExtraMB   decimal(18, 2) NOT NULL DEFAULT 0,                 -- size of an index that has to be rebuilt
    PRIMARY KEY (ObjectId, Kind, RefId)
);
-- indexes that use an option newer than SQL Server 2017, found without naming the new catalog columns here
CREATE TABLE #IdxNew (ObjectId int NOT NULL, IndexId int NOT NULL);

IF @ForceBlocked = 1
BEGIN
    INSERT INTO #BlkObj (ObjectId, Kind, RefId)
    SELECT DISTINCT b.ObjectId, b.Kind, b.RefId
    FROM #Blk AS b
    WHERE b.Kind IN ('INDEX', 'STATS', 'CHECK') AND b.RefId IS NOT NULL;

    IF COL_LENGTH('sys.indexes', 'optimize_for_sequential_key') IS NOT NULL
        INSERT INTO #IdxNew (ObjectId, IndexId)
        EXEC (N'SELECT object_id, index_id FROM sys.indexes WHERE optimize_for_sequential_key = 1');

    IF COL_LENGTH('sys.partitions', 'xml_compression') IS NOT NULL
        INSERT INTO #IdxNew (ObjectId, IndexId)
        EXEC (N'SELECT DISTINCT object_id, index_id FROM sys.partitions WHERE xml_compression = 1');

    -- statistics
    UPDATE bo
    SET Label     = N'statistics ' + QUOTENAME(s.name),
        NoForce   = CASE WHEN s.filter_definition LIKE N'%[' + NCHAR(10) + NCHAR(13) + N']%' THEN N'its filter spans lines' END,
        DropSql   = N'DROP STATISTICS ' + t.FullName + N'.' + QUOTENAME(s.name) + N';',
        CreateSql = N'CREATE STATISTICS ' + QUOTENAME(s.name) + N' ON ' + t.FullName + N' (' + sc.Cols + N')'
                  + ISNULL(N' WHERE ' + s.filter_definition, N'')
                  + ISNULL(N' WITH ' + STUFF(CASE WHEN s.no_recompute = 1 THEN N', NORECOMPUTE' ELSE N'' END
                                           + CASE WHEN s.is_incremental = 1 THEN N', INCREMENTAL = ON' ELSE N'' END, 1, 2, N''), N'')
                  + N';'
    FROM #BlkObj AS bo
    INNER JOIN #Tab AS t ON t.ObjectId = bo.ObjectId
    INNER JOIN sys.stats AS s ON s.object_id = bo.ObjectId AND s.stats_id = bo.RefId
    CROSS APPLY (SELECT STUFF((SELECT N', ' + QUOTENAME(col.name)
                               FROM sys.stats_columns AS x
                               INNER JOIN sys.columns AS col ON col.object_id = x.object_id AND col.column_id = x.column_id
                               WHERE x.object_id = s.object_id AND x.stats_id = s.stats_id
                               ORDER BY x.stats_column_id
                               FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'') AS Cols) AS sc
    WHERE bo.Kind = 'STATS';

    -- check constraints
    UPDATE bo
    SET Label     = N'check constraint ' + QUOTENAME(cc.name),
        NoForce   = CASE WHEN cc.definition LIKE N'%[' + NCHAR(10) + NCHAR(13) + N']%' THEN N'its definition spans lines'
                         WHEN EXISTS (SELECT 1 FROM sys.extended_properties AS ep WHERE ep.class = 1 AND ep.major_id = cc.object_id AND ep.minor_id = 0)
                              THEN N'it carries an extended property' END,
        DropSql   = N'ALTER TABLE ' + t.FullName + N' DROP CONSTRAINT ' + QUOTENAME(cc.name) + N';',
        CreateSql = N'ALTER TABLE ' + t.FullName + CASE WHEN cc.is_not_trusted = 1 THEN N' WITH NOCHECK' ELSE N' WITH CHECK' END
                  + N' ADD CONSTRAINT ' + QUOTENAME(cc.name) + N' CHECK ' + CASE WHEN cc.is_not_for_replication = 1 THEN N'NOT FOR REPLICATION ' ELSE N'' END
                  + cc.definition + N';',
        PostSql   = CASE WHEN cc.is_disabled = 1 THEN N'ALTER TABLE ' + t.FullName + N' NOCHECK CONSTRAINT ' + QUOTENAME(cc.name) + N';' END
    FROM #BlkObj AS bo
    INNER JOIN #Tab AS t ON t.ObjectId = bo.ObjectId
    INNER JOIN sys.check_constraints AS cc ON cc.object_id = bo.RefId AND cc.parent_object_id = bo.ObjectId
    WHERE bo.Kind = 'CHECK';

    -- indexes
    UPDATE bo
    SET Label     = N'index ' + QUOTENAME(i.name),
        NoForce   = CASE WHEN i.type <> 2 THEN N'it is not a plain nonclustered index'
                         WHEN i.is_primary_key = 1 OR i.is_unique_constraint = 1 THEN N'it backs a constraint'
                         WHEN i.is_disabled = 1 THEN N'it is disabled'
                         WHEN i.is_hypothetical = 1 THEN N'it is hypothetical'
                         WHEN ds.type <> 'FG' OR pc.Parts <> 1 THEN N'it is partitioned'
                         WHEN i.filter_definition LIKE N'%[' + NCHAR(10) + NCHAR(13) + N']%' THEN N'its filter spans lines'
                         WHEN EXISTS (SELECT 1 FROM sys.foreign_keys AS fk WHERE fk.referenced_object_id = i.object_id AND fk.key_index_id = i.index_id)
                              THEN N'a foreign key uses it'
                         WHEN EXISTS (SELECT 1 FROM sys.extended_properties AS ep WHERE ep.class = 7 AND ep.major_id = i.object_id AND ep.minor_id = i.index_id)
                              THEN N'it carries an extended property'
                         WHEN EXISTS (SELECT 1 FROM #IdxNew AS n WHERE n.ObjectId = i.object_id AND n.IndexId = i.index_id)
                              THEN N'it uses OPTIMIZE_FOR_SEQUENTIAL_KEY or XML compression' END,
        DropSql   = N'DROP INDEX ' + QUOTENAME(i.name) + N' ON ' + t.FullName + N';',
        CreateSql = N'CREATE ' + CASE WHEN i.is_unique = 1 THEN N'UNIQUE ' ELSE N'' END + N'NONCLUSTERED INDEX ' + QUOTENAME(i.name) + N' ON ' + t.FullName
                  + N' (' + k.Cols + N')' + ISNULL(N' INCLUDE (' + inc.Cols + N')', N'') + ISNULL(N' WHERE ' + i.filter_definition, N'')
                  + N' WITH (PAD_INDEX = ' + CASE WHEN i.is_padded = 1 THEN N'ON' ELSE N'OFF' END
                  + CASE WHEN i.fill_factor BETWEEN 1 AND 100 THEN N', FILLFACTOR = ' + CAST(i.fill_factor AS nvarchar(3)) ELSE N'' END
                  + CASE WHEN i.is_unique = 1 THEN N', IGNORE_DUP_KEY = ' + CASE WHEN i.ignore_dup_key = 1 THEN N'ON' ELSE N'OFF' END ELSE N'' END
                  + N', STATISTICS_NORECOMPUTE = ' + CASE WHEN ISNULL(st.no_recompute, 0) = 1 THEN N'ON' ELSE N'OFF' END
                  + N', ALLOW_ROW_LOCKS = '  + CASE WHEN i.allow_row_locks = 1  THEN N'ON' ELSE N'OFF' END
                  + N', ALLOW_PAGE_LOCKS = ' + CASE WHEN i.allow_page_locks = 1 THEN N'ON' ELSE N'OFF' END
                  + CASE WHEN pc.Compression IN (N'ROW', N'PAGE') THEN N', DATA_COMPRESSION = ' + pc.Compression ELSE N'' END
                  + N') ON ' + QUOTENAME(ds.name) + N';',
        ExtraMB   = ISNULL(sz.UsedMB, 0)
    FROM #BlkObj AS bo
    INNER JOIN #Tab AS t ON t.ObjectId = bo.ObjectId
    INNER JOIN sys.indexes AS i ON i.object_id = bo.ObjectId AND i.index_id = bo.RefId
    INNER JOIN sys.data_spaces AS ds ON ds.data_space_id = i.data_space_id
    LEFT JOIN sys.stats AS st ON st.object_id = i.object_id AND st.stats_id = i.index_id
    CROSS APPLY (SELECT COUNT(*) AS Parts, MAX(p.data_compression_desc COLLATE DATABASE_DEFAULT) AS Compression
                 FROM sys.partitions AS p WHERE p.object_id = i.object_id AND p.index_id = i.index_id) AS pc
    CROSS APPLY (SELECT SUM(ps.used_page_count) * 8 / 1024.0 AS UsedMB
                 FROM sys.dm_db_partition_stats AS ps WHERE ps.object_id = i.object_id AND ps.index_id = i.index_id) AS sz
    CROSS APPLY (SELECT STUFF((SELECT N', ' + QUOTENAME(col.name) + CASE WHEN x.is_descending_key = 1 THEN N' DESC' ELSE N'' END
                               FROM sys.index_columns AS x
                               INNER JOIN sys.columns AS col ON col.object_id = x.object_id AND col.column_id = x.column_id
                               WHERE x.object_id = i.object_id AND x.index_id = i.index_id AND x.key_ordinal > 0
                               ORDER BY x.key_ordinal
                               FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'') AS Cols) AS k
    CROSS APPLY (SELECT STUFF((SELECT N', ' + QUOTENAME(col.name)
                               FROM sys.index_columns AS x
                               INNER JOIN sys.columns AS col ON col.object_id = x.object_id AND col.column_id = x.column_id
                               WHERE x.object_id = i.object_id AND x.index_id = i.index_id AND x.is_included_column = 1
                               ORDER BY x.index_column_id
                               FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'') AS Cols) AS inc
    WHERE bo.Kind = 'INDEX';

    -- a row this script could not describe is never forced
    UPDATE #BlkObj SET NoForce = N'its definition could not be read' WHERE NoForce IS NULL AND (DropSql IS NULL OR CreateSql IS NULL);

    -- per column: why it cannot be forced, or nothing
    UPDATE c
    SET ForceNote = STUFF((SELECT N'; ' + x.Note
                           FROM (SELECT DISTINCT CASE WHEN b.Kind = 'OTHER' OR bo.ObjectId IS NULL
                                                      THEN b.Reason + N' is not a kind this script re-creates'
                                                      ELSE bo.Label + N': ' + bo.NoForce END AS Note
                                 FROM #Blk AS b
                                 LEFT JOIN #BlkObj AS bo ON bo.ObjectId = b.ObjectId AND bo.Kind = b.Kind AND bo.RefId = b.RefId
                                 WHERE b.ObjectId = c.ObjectId AND b.ColumnId = c.ColumnId
                                   AND (b.Kind = 'OTHER' OR bo.ObjectId IS NULL OR bo.NoForce IS NOT NULL)) AS x
                           ORDER BY x.Note
                           FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'')
    FROM #Col AS c
    WHERE c.Blockers IS NOT NULL;

    UPDATE c
    SET ForceOk = 1
    FROM #Col AS c
    INNER JOIN #Tab AS t ON t.ObjectId = c.ObjectId
    WHERE c.Blockers IS NOT NULL AND c.ForceNote IS NULL AND t.TableBlocker IS NULL;
END;

-- =====================================================================================================
-- 2. Scan: one pass per table, all of its nvarchar(max) columns at once
-- =====================================================================================================
CREATE TABLE #Scan (
    ObjectId int NOT NULL, ColumnId int NOT NULL, RowCnt bigint NOT NULL,
    NonNullRows bigint NULL, MaxChars bigint NULL, TotalBytes bigint NULL, RowsOver4000 bigint NULL
);

DECLARE @ObjectId int, @FullName nvarchar(520), @ApproxRows bigint, @Aggs nvarchar(max), @Vals nvarchar(max), @Sql nvarchar(max);

DECLARE TableCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT ObjectId, FullName, ApproxRows FROM #Tab ORDER BY ApproxRows;

OPEN TableCursor;
FETCH NEXT FROM TableCursor INTO @ObjectId, @FullName, @ApproxRows;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF @MaxRowsToScan IS NOT NULL AND @ApproxRows > @MaxRowsToScan
        UPDATE #Tab SET ScanStatus = 'SKIPPED' WHERE ObjectId = @ObjectId;
    ELSE
    BEGIN
        -- written so that no NULL reaches an aggregate: no "Null value is eliminated" warnings
        SELECT
            @Aggs = (SELECT N', SUM(CASE WHEN ' + q.n + N' IS NULL THEN CAST(0 AS bigint) ELSE 1 END) AS N' + q.id
                          + N', NULLIF(MAX(ISNULL(DATALENGTH(' + q.n + N'), -1)), -1) / 2 AS M' + q.id
                          + N', SUM(ISNULL(DATALENGTH(' + q.n + N'), 0)) AS B' + q.id
                          + N', SUM(CASE WHEN DATALENGTH(' + q.n + N') > 8000 THEN CAST(1 AS bigint) ELSE 0 END) AS O' + q.id
                     FROM (SELECT QUOTENAME(c.ColumnName) AS n, CAST(c.ColumnId AS nvarchar(10)) AS id, c.ColumnId
                           FROM #Col AS c WHERE c.ObjectId = @ObjectId) AS q
                     ORDER BY q.ColumnId
                     FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'),
            @Vals = STUFF((SELECT N', (' + q.id + N', s.N' + q.id + N', s.M' + q.id + N', s.B' + q.id + N', s.O' + q.id + N')'
                           FROM (SELECT CAST(c.ColumnId AS nvarchar(10)) AS id, c.ColumnId
                                 FROM #Col AS c WHERE c.ObjectId = @ObjectId) AS q
                           ORDER BY q.ColumnId
                           FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'');

        SET @Sql = N'INSERT INTO #Scan (ObjectId, ColumnId, RowCnt, NonNullRows, MaxChars, TotalBytes, RowsOver4000)
SELECT /* nvarchar(max) right-sizing audit */ @oid, u.ColumnId, s.RowCnt, u.NonNullRows, u.MaxChars, u.TotalBytes, u.RowsOver4000
FROM (SELECT COUNT_BIG(*) AS RowCnt' + @Aggs + N' FROM ' + @FullName + N') AS s
CROSS APPLY (VALUES ' + @Vals + N') AS u (ColumnId, NonNullRows, MaxChars, TotalBytes, RowsOver4000)'
            + ISNULL(N' OPTION (MAXDOP ' + CAST(@ScanMaxDop AS nvarchar(10)) + N')', N'') + N';';

        SET @Msg = N'Scanning ' + @FullName + N' (about ' + FORMAT(@ApproxRows, 'N0') + N' rows)';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

        BEGIN TRY
            EXEC sys.sp_executesql @Sql, N'@oid int', @oid = @ObjectId;
            UPDATE #Tab SET ScanStatus = 'SCANNED' WHERE ObjectId = @ObjectId;
        END TRY
        BEGIN CATCH
            UPDATE #Tab SET ScanStatus = 'FAILED', ScanError = N'Msg ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N': ' + ERROR_MESSAGE()
            WHERE ObjectId = @ObjectId;
        END CATCH;
    END;

    FETCH NEXT FROM TableCursor INTO @ObjectId, @FullName, @ApproxRows;
END;

CLOSE TableCursor;
DEALLOCATE TableCursor;

UPDATE c
SET RowCnt = s.RowCnt, NonNullRows = s.NonNullRows, MaxChars = s.MaxChars, TotalBytes = s.TotalBytes, RowsOver4000 = s.RowsOver4000
FROM #Col AS c
INNER JOIN #Scan AS s ON s.ObjectId = c.ObjectId AND s.ColumnId = c.ColumnId;

-- =====================================================================================================
-- 3. Verdict, suggested size and log estimate per column
-- =====================================================================================================
UPDATE c
SET NewLen = CASE WHEN c.MaxChars > 0 AND c.RowsOver4000 = 0
                  THEN ISNULL((SELECT MIN(l.Len) FROM (VALUES (10), (20), (30), (50), (100), (150), (200), (255), (300), (400), (500),
                                                              (750), (1000), (1500), (2000), (3000), (4000)) AS l (Len)
                               WHERE l.Len >= CEILING(c.MaxChars * (100 + @HeadroomPct) / 100.0)), 4000) END,
    Verdict = CASE WHEN t.ScanStatus = 'SKIPPED'      THEN 'NOT SCANNED'
                   WHEN t.ScanStatus <> 'SCANNED'     THEN 'SCAN FAILED'
                   WHEN c.RowsOver4000 > 0            THEN 'KEEP MAX'
                   WHEN ISNULL(c.MaxChars, 0) = 0     THEN 'NO DATA'
                   WHEN c.ForceOk = 1                 THEN 'FORCE'
                   WHEN t.TableBlocker IS NOT NULL OR c.Blockers IS NOT NULL THEN 'BLOCKED'
                   ELSE 'SHRINK' END
FROM #Col AS c
INNER JOIN #Tab AS t ON t.ObjectId = c.ObjectId;

UPDATE c
SET GoesOnline   = CASE WHEN c.Verdict = 'SHRINK' AND @OnlineOk = 1 AND t.OnlineBar IS NULL AND c.DefaultName IS NULL THEN 1 ELSE 0 END,
    OfflineLogMB = (c.RowCnt * 450.0 + CASE WHEN t.IsHeap = 1 THEN 3.0 ELSE 2.0 END * c.TotalBytes) / 1048576
                 -- a forced column also rebuilds its blocking indexes
                 + CASE WHEN c.Verdict = 'FORCE'
                        THEN ISNULL((SELECT SUM(bo.ExtraMB)
                                     FROM #BlkObj AS bo
                                     WHERE EXISTS (SELECT 1 FROM #Blk AS b
                                                   WHERE b.ObjectId = c.ObjectId AND b.ColumnId = c.ColumnId
                                                     AND b.Kind = bo.Kind AND b.RefId = bo.RefId AND bo.ObjectId = b.ObjectId)), 0)
                             * CASE WHEN @FullyLogged = 1 THEN 1.0 ELSE 0.01 END
                        ELSE 0 END
FROM #Col AS c
INNER JOIN #Tab AS t ON t.ObjectId = c.ObjectId
WHERE c.Verdict IN ('SHRINK', 'FORCE');

UPDATE c
SET AlterLogMB = CASE WHEN c.GoesOnline = 0 THEN c.OfflineLogMB
                      WHEN @FullyLogged = 1 THEN t.BaseMB + c.RowCnt * 350.0 / 1048576
                      ELSE 0.25 * (t.BaseMB - t.OffRowMB) + 0.75 * t.OffRowMB END
FROM #Col AS c
INNER JOIN #Tab AS t ON t.ObjectId = c.ObjectId
WHERE c.Verdict IN ('SHRINK', 'FORCE');

-- =====================================================================================================
-- 4. Roll up per table
-- =====================================================================================================
IF OBJECT_ID('tempdb..#TabOut') IS NOT NULL DROP TABLE #TabOut;

SELECT
    t.ObjectId,
    COUNT(*)                                                  AS MaxColumns,
    SUM(CASE WHEN c.Verdict IN ('SHRINK', 'FORCE') THEN 1 ELSE 0 END) AS CanShrink,
    SUM(CASE WHEN c.Verdict = 'BLOCKED'  THEN 1 ELSE 0 END)   AS Blocked,
    SUM(CASE WHEN c.Verdict = 'KEEP MAX' THEN 1 ELSE 0 END)   AS KeepMax,
    SUM(CASE WHEN c.Verdict IN ('NO DATA', 'NOT SCANNED', 'SCAN FAILED') THEN 1 ELSE 0 END) AS Unknown,
    NULLIF(MAX(ISNULL(c.RowCnt, -1)), -1)                     AS RowCnt,
    SUM(ISNULL(c.OfflineLogMB, 0))                            AS SumOfflineMB,
    SUM(ISNULL(c.AlterLogMB, 0))                              AS SumScriptedMB,
    MAX(ISNULL(c.AlterLogMB, 0))                              AS MaxScriptedMB,
    SUM(CASE WHEN c.Verdict IN ('SHRINK', 'FORCE') AND c.GoesOnline = 0 THEN 1 ELSE 0 END) AS OfflineAlters,
    SUM(CASE WHEN c.Verdict IN ('SHRINK', 'FORCE') AND c.GoesOnline = 1 THEN 1 ELSE 0 END) AS OnlineAlters,
    -- REBUILD after offline ALTERs: ONLINE when the edition allows it. On a heap it rebuilds the nonclustered indexes too.
    MAX(CASE WHEN @OnlineOk = 1 AND @FullyLogged = 1 THEN t.BaseMB + t.ApproxRows * 350.0 / 1048576 + CASE WHEN t.IsHeap = 1 THEN t.NcIndexMB ELSE 0 END
             WHEN @OnlineOk = 1 THEN 0.25 * (t.BaseMB - t.OffRowMB + CASE WHEN t.IsHeap = 1 THEN t.NcIndexMB ELSE 0 END) + 0.75 * t.OffRowMB
             ELSE (t.BaseMB + CASE WHEN t.IsHeap = 1 THEN t.NcIndexMB ELSE 0 END) * CASE WHEN @FullyLogged = 1 THEN 1.0 ELSE 0.01 END END) AS RebuildMB,
    MAX((t.BaseMB + CASE WHEN t.IsHeap = 1 THEN t.NcIndexMB ELSE 0 END) * CASE WHEN @FullyLogged = 1 THEN 1.0 ELSE 0.01 END)             AS OfflineRebuildMB
INTO #TabOut
FROM #Tab AS t
INNER JOIN #Col AS c ON c.ObjectId = t.ObjectId
GROUP BY t.ObjectId;

UPDATE t
SET TableRank = r.Rnk
FROM #Tab AS t
INNER JOIN (SELECT t2.ObjectId,
                   ROW_NUMBER() OVER (ORDER BY CASE WHEN o.CanShrink > 0 THEN 0 ELSE 1 END,
                                               t2.BaseReads DESC, t2.BaseMB DESC, t2.SchemaName, t2.TableName) AS Rnk
            FROM #Tab AS t2
            INNER JOIN #TabOut AS o ON o.ObjectId = t2.ObjectId) AS r ON r.ObjectId = t.ObjectId;

-- =====================================================================================================
-- RESULT SET 1: overview
-- =====================================================================================================
SELECT
    DB_NAME()                                                           AS DatabaseName,
    @Recovery + CASE WHEN @Recovery = N'FULL' AND @FullyLogged = 0
                     THEN N' (no log backup chain yet: logs like SIMPLE)' ELSE N'' END AS RecoveryModel,
    CASE WHEN @OnlineOk = 1 THEN 'Yes'
         WHEN @UseOnline = 0 THEN 'No (@UseOnline = 0)'
         ELSE 'No (edition)' END                                        AS OnlineAlterUsable,
    @StatsSince                                                         AS UsageCountersSince,
    @TablesFound                                                        AS TablesWithMaxColumns,
    (SELECT COUNT(*) FROM #Tab)                                         AS TablesChecked,
    COUNT(*)                                                            AS MaxColumns,
    SUM(CASE WHEN Verdict IN ('SHRINK', 'FORCE') THEN 1 ELSE 0 END)     AS Shrink,
    SUM(CASE WHEN Verdict = 'BLOCKED'     THEN 1 ELSE 0 END)            AS Blocked,
    SUM(CASE WHEN Verdict = 'KEEP MAX'    THEN 1 ELSE 0 END)            AS KeepMax,
    SUM(CASE WHEN Verdict = 'NO DATA'     THEN 1 ELSE 0 END)            AS NoData,
    SUM(CASE WHEN Verdict = 'NOT SCANNED' THEN 1 ELSE 0 END)            AS NotScanned,
    SUM(CASE WHEN Verdict = 'SCAN FAILED' THEN 1 ELSE 0 END)            AS ScanFailed
FROM #Col;

-- =====================================================================================================
-- RESULT SET (only with @TopQueries): the queries that were ranked and read, heaviest first.
--   QueryRank         blank for a query that had no plan to read: it is shown, but takes none of the N places
--   MaxTablesTouched  tables in the Tables result that this query's plan names
--   MaxColumnsUsed    nvarchar(max) columns that this query's plan names (read or written)
-- =====================================================================================================
IF @TopQueries IS NOT NULL
    SELECT
        q.KeepRank AS QueryRank,
        CASE @QSource WHEN 'QUERYSTORE' THEN 'Query Store' ELSE 'Plan cache' END AS Source,
        CASE @TopQueriesBy WHEN 'CPU' THEN 'CPU ms' WHEN 'READS' THEN 'logical reads' WHEN 'DURATION' THEN 'duration ms' ELSE 'memory KB' END AS RankedBy,
        q.Measure,
        q.Executions,
        q.LastSeen,
        q.PlanRead,
        STUFF((SELECT N', ' + t.FullName
               FROM #Tab AS t
               WHERE EXISTS (SELECT 1 FROM #PlanRef AS r
                             WHERE r.QueryRank = q.QueryRank AND r.SchemaQ = QUOTENAME(t.SchemaName) AND r.TableQ = QUOTENAME(t.TableName))
               ORDER BY t.FullName
               FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'') AS MaxTablesTouched,
        STUFF((SELECT N', ' + t.FullName + N'.' + QUOTENAME(c.ColumnName)
               FROM #Col AS c
               INNER JOIN #Tab AS t ON t.ObjectId = c.ObjectId
               WHERE EXISTS (SELECT 1 FROM #PlanRef AS r
                             WHERE r.QueryRank = q.QueryRank AND r.SchemaQ = QUOTENAME(t.SchemaName) AND r.TableQ = QUOTENAME(t.TableName)
                               AND r.ColumnName = c.ColumnName)
               ORDER BY t.FullName, c.ColumnId
               FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'') AS MaxColumnsUsed,
        q.QueryText
    FROM #TopQ AS q
    ORDER BY q.QueryRank;

-- =====================================================================================================
-- RESULT SET 2: tables. Fixable tables first, busiest first.
--   LogMB_Scripted     what the scripted fix writes to the log in total (ALTERs, plus the REBUILD if any ran offline)
--   BiggestTxnMB      its largest single transaction: the log must hold at least this much at once
--   LogMB_AllOffline  the same job with every ALTER offline, plus the REBUILD
-- =====================================================================================================
SELECT
    t.SchemaName,
    t.TableName,
    ISNULL(o.RowCnt, t.ApproxRows)                                       AS [Rows],
    t.BaseMB                                                             AS TableMB,
    t.OffRowMB,
    o.MaxColumns,
    o.CanShrink,
    o.Blocked,
    o.KeepMax,
    o.Unknown,
    t.BaseReads                                                          AS Reads,
    CAST(100.0 * t.BaseReads / NULLIF(@DbBaseReads, 0) AS decimal(6, 2)) AS PctOfDbReads,
    t.BaseWrites                                                         AS Writes,
    t.LobFetches,
    CASE WHEN o.CanShrink = 0 THEN NULL
         WHEN o.OfflineAlters = 0 THEN 'ONLINE ALTER'
         WHEN o.OnlineAlters = 0  THEN 'OFFLINE ALTER + REBUILD'
         ELSE 'MIXED + REBUILD' END                                      AS FixMethod,
    CAST(x.InPlaceMB AS decimal(18, 1))                                  AS LogMB_Scripted,
    CAST(x.BiggestTxnMB AS decimal(18, 1))                               AS BiggestTxnMB,
    CAST(CASE WHEN o.CanShrink > 0 THEN o.SumOfflineMB + o.OfflineRebuildMB END AS decimal(18, 1)) AS LogMB_AllOffline,
    CASE WHEN o.CanShrink = 0 AND t.ScanStatus = 'SKIPPED' THEN 'Not scanned: over @MaxRowsToScan.'
         WHEN o.CanShrink = 0 AND t.ScanStatus = 'FAILED'  THEN 'Scan failed: ' + t.ScanError
         WHEN o.CanShrink = 0 AND t.TableBlocker IS NOT NULL AND o.Blocked > 0 THEN 'Needs a hand-written change because of: ' + t.TableBlocker + '.'
         WHEN o.CanShrink = 0 THEN 'Nothing to script. See the Columns result.'
         WHEN x.InPlaceMB < 1024 THEN 'Small job. Run the script as it is.'
         ELSE 'Big job: about ' + FORMAT(x.InPlaceMB, 'N0') + ' MB of log, ' + FORMAT(x.BiggestTxnMB, 'N0')
              + ' MB of it in one transaction. Check log space first and take log backups between steps.' END AS Suggestion
FROM #Tab AS t
INNER JOIN #TabOut AS o ON o.ObjectId = t.ObjectId
CROSS APPLY (SELECT CASE WHEN o.CanShrink > 0 THEN o.SumScriptedMB + CASE WHEN o.OfflineAlters > 0 THEN o.RebuildMB ELSE 0 END END AS InPlaceMB,
                    CASE WHEN o.CanShrink > 0 THEN CASE WHEN o.OfflineAlters > 0 AND o.RebuildMB > o.MaxScriptedMB
                                                         THEN o.RebuildMB ELSE o.MaxScriptedMB END END                         AS BiggestTxnMB) AS x
ORDER BY t.TableRank;

-- =====================================================================================================
-- RESULT SET 3: columns, in the same table order
-- =====================================================================================================
SELECT
    t.SchemaName,
    t.TableName,
    c.ColumnName,
    c.Verdict,
    N'nvarchar(max) ' + CASE WHEN c.IsNullable = 1 THEN N'NULL' ELSE N'NOT NULL' END              AS CurrentType,
    N'nvarchar(' + CAST(c.NewLen AS nvarchar(10)) + N') ' + CASE WHEN c.IsNullable = 1 THEN N'NULL' ELSE N'NOT NULL' END AS SuggestedType,
    c.MaxChars                                                                                    AS LongestChars,
    CAST(c.TotalBytes / 2.0 / NULLIF(c.NonNullRows, 0) AS decimal(18, 1))                         AS AvgChars,
    c.RowCnt                                                                                      AS [Rows],
    c.NonNullRows,
    c.RowsOver4000,
    CAST(c.TotalBytes / 1048576.0 AS decimal(18, 1))                                              AS ColumnMB,
    CASE WHEN c.Verdict IN ('SHRINK', 'FORCE') THEN CASE WHEN c.GoesOnline = 1 THEN 'ONLINE' ELSE 'OFFLINE' END END AS AlterRuns,
    c.AlterLogMB                                                                                  AS LogMB_Alter,
    CASE c.Verdict
        WHEN 'NOT SCANNED' THEN N'About ' + FORMAT(t.ApproxRows, 'N0') + N' rows, over @MaxRowsToScan. Raise the limit and run off-hours.'
        WHEN 'SCAN FAILED' THEN t.ScanError
        WHEN 'KEEP MAX'    THEN N'Rows over 4,000 characters: ' + FORMAT(c.RowsOver4000, 'N0') + N' (longest ' + FORMAT(c.MaxChars, 'N0') + N').'
        WHEN 'NO DATA'     THEN CASE WHEN c.RowCnt = 0 THEN N'The table is empty.'
                                     WHEN c.NonNullRows = 0 THEN N'Every row is NULL.'
                                     ELSE N'Only empty strings.' END + N' Ask the application owner before sizing.'
        WHEN 'BLOCKED'     THEN N'Fits nvarchar(' + CAST(c.NewLen AS nvarchar(10)) + N'), but needs a hand-written change because of: '
                                + ISNULL(t.TableBlocker, N'') + CASE WHEN t.TableBlocker IS NOT NULL AND c.Blockers IS NOT NULL THEN N'; ' ELSE N'' END
                                + ISNULL(c.Blockers, N'') + N'.'
                                + CASE WHEN @ForceBlocked = 1 THEN N' Not forced: ' + ISNULL(c.ForceNote, N'the table itself blocks it') + N'.' ELSE N'' END
        WHEN 'FORCE'       THEN N'Headroom ' + FORMAT(100.0 * (c.NewLen - c.MaxChars) / c.MaxChars, 'N0') + N'% over the longest value. Forced: '
                                + c.Blockers + N' dropped and re-created around the ALTER in one transaction, so it runs offline.'
                                + CASE WHEN c.DefaultName IS NOT NULL THEN N' Default ' + QUOTENAME(c.DefaultName) + N' too.' ELSE N'' END
        WHEN 'SHRINK'      THEN N'Headroom ' + FORMAT(100.0 * (c.NewLen - c.MaxChars) / c.MaxChars, 'N0') + N'% over the longest value.'
                                + CASE WHEN c.DefaultName IS NOT NULL THEN N' Default ' + QUOTENAME(c.DefaultName) + N' is dropped and re-created around the ALTER, so it runs offline.' ELSE N'' END
                                + CASE WHEN c.DefaultName IS NULL AND @OnlineOk = 1 AND t.OnlineBar IS NOT NULL THEN N' Offline because ' + t.OnlineBar + N'.' ELSE N'' END
    END
    + CASE WHEN @TopQueries IS NULL THEN N''
           WHEN c.TopQueryRefs IS NOT NULL THEN N' Used by top query ' + c.TopQueryRefs + N'.'
           ELSE N' No top query uses this column itself.' END                                    AS Why
FROM #Col AS c
INNER JOIN #Tab AS t ON t.ObjectId = c.ObjectId
ORDER BY t.TableRank, c.ColumnId;

-- =====================================================================================================
-- RESULT SET 4: the fix script. One statement per row, so it survives a copy out of the grid.
--   COLUMN  each column is its own block: run any one of them alone. The REBUILD is left commented out.
--   TABLE   each table is one block: all of its columns, then one REBUILD if any ALTER ran offline.
-- =====================================================================================================
IF @FixScript <> 'NONE'
BEGIN
    CREATE TABLE #Fix (TableRank int NOT NULL, ColumnId int NOT NULL, Part int NOT NULL, Script nvarchar(max) COLLATE DATABASE_DEFAULT NOT NULL);

    -- top of the script
    INSERT INTO #Fix (TableRank, ColumnId, Part, Script)
    VALUES
        (0, 0, 1, N'-- nvarchar(max) right-sizing for database ' + QUOTENAME(DB_NAME()) + N', generated ' + CONVERT(nvarchar(16), SYSDATETIME(), 120)
                  + N'. Mode: ' + @FixScript + N'. Recovery model: ' + @Recovery + N'.'
                  + CASE WHEN @TopQueries IS NOT NULL
                         THEN N' High impact only: tables touched by the top ' + CAST(@TopQueries AS nvarchar(10)) + N' queries by ' + @TopQueriesBy + N'.'
                         ELSE N'' END),
        (0, 0, 2, N'-- Review it and run it in a maintenance window. An offline ALTER locks its table until it ends; an ONLINE one locks it briefly at the start and the end.'),
        (0, 0, 3, N'-- Log figures are estimates. Each ALTER fails with Msg 2628 and changes nothing if a longer value has arrived since the scan.'),
        (0, 0, 4, N'USE ' + QUOTENAME(DB_NAME()) + N';'),
        (0, 0, 5, N'GO'),
        (0, 0, 6, N'SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON; SET NUMERIC_ROUNDABORT OFF;'),
        (0, 0, 7, N'SET XACT_ABORT ON; SET LOCK_TIMEOUT 10000;   -- give up after 10 seconds rather than queue behind a long transaction and block everyone else'),
        (0, 0, 8, N'GO');

    IF @ForceBlocked = 1
        INSERT INTO #Fix (TableRank, ColumnId, Part, Script)
        VALUES (0, 0, 3, N'-- A forced column drops its blocking index, statistics or check constraint, changes the column and re-creates them in ONE transaction. If a step fails, all of it rolls back.');

    -- TABLE mode: a header line per table
    IF @FixScript = 'TABLE'
        INSERT INTO #Fix (TableRank, ColumnId, Part, Script)
        SELECT t.TableRank, 0, 1,
               N'-- ===== ' + t.FullName + N': ' + CAST(o.CanShrink AS nvarchar(10)) + N' column(s), ' + FORMAT(ISNULL(o.RowCnt, 0), 'N0') + N' rows, '
               + FORMAT(t.BaseMB, 'N0') + N' MB. Estimated log: ' + FORMAT(o.SumScriptedMB + CASE WHEN o.OfflineAlters > 0 THEN o.RebuildMB ELSE 0 END, 'N0')
               + N' MB in total, ' + FORMAT(CASE WHEN o.OfflineAlters > 0 AND o.RebuildMB > o.MaxScriptedMB THEN o.RebuildMB ELSE o.MaxScriptedMB END, 'N0')
               + N' MB in the largest single transaction. ====='
        FROM #Tab AS t
        INNER JOIN #TabOut AS o ON o.ObjectId = t.ObjectId
        WHERE o.CanShrink > 0;

    -- one block per column
    INSERT INTO #Fix (TableRank, ColumnId, Part, Script)
    SELECT t.TableRank, c.ColumnId, p.Part, p.Script
    FROM #Col AS c
    INNER JOIN #Tab AS t ON t.ObjectId = c.ObjectId
    CROSS APPLY (SELECT N'nvarchar(' + CAST(c.NewLen AS nvarchar(10)) + N')' + ISNULL(N' COLLATE ' + c.CollationName, N'')
                        + CASE WHEN c.IsNullable = 1 THEN N' NULL' ELSE N' NOT NULL' END AS NewType) AS n
    CROSS APPLY (VALUES
        (10, N'-- ' + t.FullName + N'.' + QUOTENAME(c.ColumnName) + N': nvarchar(max) -> nvarchar(' + CAST(c.NewLen AS nvarchar(10)) + N'). Longest value '
            + FORMAT(c.MaxChars, 'N0') + N' characters in ' + FORMAT(c.RowCnt, 'N0') + N' rows. Estimated log ' + FORMAT(c.AlterLogMB, 'N0') + N' MB, '
            + CASE WHEN c.GoesOnline = 1 THEN N'online.' ELSE N'offline.' END
            + CASE WHEN c.Verdict = 'FORCE' THEN N' Forced: drops and re-creates ' + c.Blockers + N'.' ELSE N'' END),
        (20, CASE WHEN c.DefaultName IS NOT NULL OR c.Verdict = 'FORCE' THEN N'BEGIN TRANSACTION;' END),
        (30, CASE WHEN c.DefaultName IS NOT NULL THEN N'ALTER TABLE ' + t.FullName + N' DROP CONSTRAINT ' + QUOTENAME(c.DefaultName) + N';' END),
        (500, N'ALTER TABLE ' + t.FullName + N' ALTER COLUMN ' + QUOTENAME(c.ColumnName) + N' ' + n.NewType
            + CASE WHEN c.GoesOnline = 1 THEN N' WITH (ONLINE = ON);' ELSE N';' END),
        (800, CASE WHEN c.DefaultName IS NOT NULL THEN N'ALTER TABLE ' + t.FullName + N' ADD CONSTRAINT ' + QUOTENAME(c.DefaultName) + N' DEFAULT ' + c.DefaultDef
                                                     + N' FOR ' + QUOTENAME(c.ColumnName) + N';' END),
        (900, CASE WHEN c.DefaultName IS NOT NULL OR c.Verdict = 'FORCE' THEN N'COMMIT TRANSACTION;' END),
        (990, N'GO')
    ) AS p (Part, Script)
    WHERE c.Verdict IN ('SHRINK', 'FORCE') AND p.Script IS NOT NULL;

    -- a forced column: its blockers go before the ALTER (part 100) and come back after it (600, then 601)
    INSERT INTO #Fix (TableRank, ColumnId, Part, Script)
    SELECT t.TableRank, c.ColumnId, p.Part, p.Script
    FROM #Col AS c
    INNER JOIN #Tab AS t ON t.ObjectId = c.ObjectId
    INNER JOIN #BlkObj AS bo ON bo.ObjectId = c.ObjectId
    CROSS APPLY (VALUES (100, bo.DropSql), (600, bo.CreateSql), (601, bo.PostSql)) AS p (Part, Script)
    WHERE c.Verdict = 'FORCE' AND p.Script IS NOT NULL
      AND EXISTS (SELECT 1 FROM #Blk AS b
                  WHERE b.ObjectId = c.ObjectId AND b.ColumnId = c.ColumnId AND b.Kind = bo.Kind AND b.RefId = bo.RefId);

    -- after the last column of a table: give back the space the old values still hold (offline ALTERs only)
    INSERT INTO #Fix (TableRank, ColumnId, Part, Script)
    SELECT t.TableRank, 2147483647, p.Part, p.Script
    FROM #Tab AS t
    INNER JOIN #TabOut AS o ON o.ObjectId = t.ObjectId
    CROSS APPLY (SELECT N'ALTER TABLE ' + t.FullName + N' REBUILD'
                        + CASE WHEN @OnlineOk = 1 THEN N' WITH (ONLINE = ON);' ELSE N';' END AS Stmt,
                        N' Estimated log ' + FORMAT(o.RebuildMB, 'N0') + N' MB.' AS Cost) AS r
    CROSS APPLY (VALUES
        (1, CASE WHEN @FixScript = 'COLUMN'
                 THEN N'-- Optional, once ' + t.FullName + N' has had its last offline ALTER: the old values still fill the pages until a rebuild.' + r.Cost
                 ELSE N'-- Rebuild ' + t.FullName + N': the offline ALTERs left the old values in the pages.' + r.Cost END),
        (2, CASE WHEN @FixScript = 'COLUMN' THEN N'-- ' ELSE N'' END + r.Stmt),
        (3, N'GO')
    ) AS p (Part, Script)
    WHERE o.OfflineAlters > 0;

    SELECT f.Script
    FROM #Fix AS f
    ORDER BY f.TableRank, f.ColumnId, f.Part, f.Script;
END;
