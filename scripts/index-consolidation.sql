/* ------------------------------------------------------------------
-- Title				: Index Consolidation (unused, exact-duplicate, superseded and mergeable indexes)
-- Author				: Adrian Sullivan
-- whah?				: adrian@sqldba.org
-- Date					: 2026-11-21
-- Version: 1.3 (2026-11-24)
-- What it does			: Lists every index of ONE database and gives each one verdict: KEEP, UNUSED, EXACT DUPLICATE,
--						  SUPERSEDED (a wider index with the same leading keys does its job), MERGE (same keys, other
--						  includes) or NOT JUDGED (not compared, or a safety check could not run; the reason says why).
--						  For each removable index it writes the script that disables it (step 2) and the one that
--						  drops it (drop_script). A keeper that must take over included columns gets its rebuild
--						  script (step 1, run it first). After you run the scripts, run this again: an index kept
--						  only because it was the keeper of a duplicate can be superseded once the duplicate is gone.
-- Modes (@Mode)		: audit (the default) shows only the indexes it would change, then ONE remediation script, one
--						  line per row, in run order (step 1, step 2, then the drops commented out). all shows every index.
--						  changecontrol lists every index, one row per change (a change id, a risk, the script, the script
--						  that undoes it, and empty approved / approver / approved_date columns), then the indexes with no
--						  change. Run its rollback scripts in REVERSE change_id order.
-- Size filter			: @MinSizeMB turns a drop verdict on an index smaller than it into NOT JUDGED, reason 'below size
--						  filter'. Every other verdict is the same as with 0.
-- Progress			: @Progress = 1 prints one line per step to the Messages tab as it runs (step n of N, seconds so far);
--						  the audit script prints one line before each change it makes. 0 = silent.
-- Never suggested		: removing a primary key, unique constraint, unique index, an index a foreign key relies on,
--						  an index named in a module, plan guide, cached plan, Query Store text or hint or Agent job
--						  step, an index a Query Store forced plan uses, or a full-text key. A cached plan protects an
--						  index only while it is in the cache: ad hoc code that hints an index and is not cached when
--						  this runs cannot be seen. The cached texts are copied first, before anything else is read, but a
--						  server short of memory can still evict a small ad hoc plan before that.
-- Read-only			: It reads catalog views and DMVs and writes only to #temp tables. It changes no setting and runs
--						  none of the scripts it writes: they are text in the result set. Read them, then run them yourself.
-- Permissions			: VIEW SERVER STATE (2022: VIEW SERVER PERFORMANCE STATE) for index usage, the server start time
--						  and the plan cache; VIEW DEFINITION and VIEW DATABASE STATE on the database. Without the first
--						  two, or when index usage or the server start time cannot be read, it stops and says so.
--						  When the database holds an encrypted module, also SELECT on sys.sql_expression_dependencies
--						  (db_owner has it by default); without it every drop verdict is NOT JUDGED, reason
--						  'module dependencies not readable'. msdb job steps are read when the login can read them.
-- SQL Server			: 2012 and later. Tested on 2017 and 2022 only.
-- Credit				: The comparison approach (key string with direction, sorted includes, equal filters, closest
--						  superset) follows Erik Darling's sp_IndexCleanup (DarlingData, MIT). No code is copied.
------------------------------------------------------------------ */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

/*The knobs. Twiddle these, leave the rest alone*/
DECLARE @DatabaseName SYSNAME, @MinUptimeDays INT, @SchemaName SYSNAME, @TableName SYSNAME, @Online BIT, @Mode NVARCHAR(20), @MinSizeMB DECIMAL(18, 2), @Progress BIT
SET @DatabaseName = NULL		/*NULL = the current database. One database per run*/
SET @MinUptimeDays = 30			/*A usage window shorter than this many days marks every UNUSED verdict low confidence (per index: from its last build or statistics update)*/
SET @SchemaName = NULL			/*NULL = every schema, or name just the one*/
SET @TableName = NULL			/*NULL = every table and indexed view, or name just the one*/
SET @Online = 0					/*1 = add ONLINE = ON to the rebuild scripts, only on editions that allow it*/
SET @Mode = N'audit'			/*audit = candidates plus one remediation script; all = every index; changecontrol = an approval list*/
SET @MinSizeMB = 0				/*Drop verdicts on indexes smaller than this (used pages, MB) become NOT JUDGED, reason below size filter. 0 = no filter*/
SET @Progress = 1				/*1 = print progress to the Messages tab as it runs; 0 = silent*/

/*Progress (2026-11-23): each step below starts with a progress point, two lines at column 0 outside every IF and TRY, so
every mode and version prints the same @ptot lines, each at the START of the step it names, then a done line before result
set 1 (a message after a result set would land inside the result set 3 text of sqlcmd output). @ptot is the number of points*/
DECLARE @t0 DATETIME2(7) = SYSDATETIME(), @pn INT = 0, @ptot INT = 15, @pwhat NVARCHAR(400), @pms INT, @psec INT, @pfrac INT
	, @pfmt NVARCHAR(100) = N'index-consolidation: [%d/%d] %s elapsed %d.%03d s';

/*The knobs are checked before anything is read. NOT IN with a NULL is not true, so NULL is tested on its own. Every mode
branch below compares @Mode COLLATE Latin1_General_100_CI_AS after it is lowered, so a case-sensitive database agrees*/
IF @Mode IS NULL OR LOWER(@Mode) COLLATE Latin1_General_100_CI_AS NOT IN (N'audit', N'all', N'changecontrol')
BEGIN
	RAISERROR(N'index-consolidation: @Mode must be audit, all or changecontrol. Nothing was read.', 16, 1);
	RETURN;
END
SET @Mode = LOWER(@Mode);
IF @MinSizeMB IS NULL OR @MinSizeMB < 0
BEGIN
	RAISERROR(N'index-consolidation: @MinSizeMB must be 0 or more. Nothing was read.', 16, 1);
	RETURN;
END

/*Everything below reads, it does not write*/
DECLARE @db SYSNAME = ISNULL(@DatabaseName, DB_NAME());
IF DB_ID(@db) IS NULL
BEGIN
	RAISERROR(N'index-consolidation: database %s was not found. Nothing was read.', 16, 1, @db);
	RETURN;
END
DECLARE @dbid INT = DB_ID(@db);
DECLARE @major INT = CONVERT(INT, PARSENAME(CONVERT(VARCHAR(32), SERVERPROPERTY('ProductVersion')), 4));

/*Safety checks that must run before anything is judged. Without them the tool stops: it never guesses*/
DECLARE @srvperm NVARCHAR(60) = CASE WHEN @major >= 16 THEN N'VIEW SERVER PERFORMANCE STATE' ELSE N'VIEW SERVER STATE' END;
IF ISNULL(HAS_PERMS_BY_NAME(NULL, NULL, @srvperm), 0) = 0
BEGIN
	RAISERROR(N'index-consolidation: needs %s on the server (index usage, the server start time and the plan cache). Nothing was judged.', 16, 1, @srvperm);
	RETURN;
END
IF ISNULL(HAS_PERMS_BY_NAME(@db, N'DATABASE', N'VIEW DEFINITION'), 0) = 0
BEGIN
	RAISERROR(N'index-consolidation: needs VIEW DEFINITION on %s: the catalog is not fully visible. Nothing was judged.', 16, 1, @db);
	RETURN;
END

DECLARE @exec NVARCHAR(400) = QUOTENAME(@db) + N'.sys.sp_executesql';	/*catalog views are per database, so every catalog read runs in the target database*/
DECLARE @exec_msdb NVARCHAR(400) = N'msdb.sys.sp_executesql';			/*Agent job steps, read only when the login can*/
DECLARE @sql NVARCHAR(MAX), @err NVARCHAR(2048), @deps_read BIT = 1;
DECLARE @server_start DATETIME, @create_date DATETIME, @window_start DATETIME, @window_days INT, @ag NVARCHAR(3), @autoclose BIT
	, @qs NVARCHAR(20), @qsd NVARCHAR(60), @pc NVARCHAR(20) = N'not readable', @jobs NVARCHAR(20) = N'not readable', @adhoc INT;
DECLARE @online_ok BIT = CASE WHEN @Online = 1 AND CONVERT(INT, SERVERPROPERTY('EngineEdition')) IN (3, 5, 8) THEN 1 ELSE 0 END;
DECLARE @setline NVARCHAR(400) = N'SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON; SET NUMERIC_ROUNDABORT OFF; ';
DECLARE @use NVARCHAR(400) = N'USE ' + QUOTENAME(@db) + N'; ';
DECLARE @version NVARCHAR(20) = N'1.3 (2026-11-24)';
/*Change-control risk thresholds, in MB (judgement, not measurements: a rebuild or re-create over 10 GB needs a
maintenance window on typical storage; a widen rewrites the whole index). Written once*/
DECLARE @risk_high_mb DECIMAL(19, 2) = 10240, @risk_med_mb DECIMAL(19, 2) = 1024;
DECLARE @inc NVARCHAR(20) = N' INCLUDE (';	/*the generator's include part, written once (widen, rollback, drop rollback)*/

SELECT @pn += 1, @pwhat = N'copy the plan cache and Query Store texts', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*The texts the engine may compile come FIRST, before any other read: a cached plan protects an index (P6) only while it is in
the cache, and the reads below could push a small ad hoc plan out of a cache that is short of memory*/
IF OBJECT_ID(N'tempdb..#text') IS NOT NULL DROP TABLE #text;
IF OBJECT_ID(N'tempdb..#forced') IS NOT NULL DROP TABLE #forced;
CREATE TABLE #text (src_order TINYINT NOT NULL, label NVARCHAR(400) NULL, txt NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS NULL, fast BIT NULL, utxt NVARCHAR(MAX) COLLATE Latin1_General_100_BIN2 NULL);
CREATE TABLE #forced (plan_id BIGINT NOT NULL, query_id BIGINT NOT NULL, query_plan NVARCHAR(MAX) NULL);
/*The plan cache: every cached text, stubs included, with no database filter (ad hoc text has no dbid, and a query in another
database can hint an index here)*/
BEGIN TRY
	INSERT #text (src_order, label, txt)
	SELECT 3, N'P6 plan cache: ' + LEFT(REPLACE(REPLACE(REPLACE(t.text, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' '), 80), t.text
	FROM (SELECT DISTINCT st.text FROM sys.dm_exec_cached_plans cp CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
		WHERE st.text IS NOT NULL) t;
	SET @pc = N'read';
END TRY
BEGIN CATCH
	SET @pc = N'not readable';
END CATCH

/*Query Store state, read only when it exists (2016+). OFF or READ_ONLY is not a block: its texts and forced plans are still read*/
IF @major < 13
	SET @qs = N'not applicable';
ELSE
BEGIN
	BEGIN TRY
		SET @sql = N'SELECT @s = actual_state_desc FROM sys.database_query_store_options;';
		EXEC @exec @sql, N'@s NVARCHAR(60) OUTPUT', @s = @qsd OUTPUT;
		SET @qs = CASE ISNULL(@qsd, N'OFF') WHEN N'OFF' THEN N'off' WHEN N'READ_WRITE' THEN N'read_write' WHEN N'READ_ONLY' THEN N'read_only' ELSE N'not readable' END;
	END TRY
	BEGIN CATCH
		SET @qs = N'not readable';
	END CATCH
END
/*Query Store texts, hints (2022+) and forced plans (P7), whatever its state, when it exists*/
IF @major >= 13 AND @qs <> N'not readable'
BEGIN
	BEGIN TRY
		SET @sql = N'SELECT 4, N''P6 Query Store query_id '' + CONVERT(NVARCHAR(20), q.query_id), qt.query_sql_text
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id
WHERE qt.query_sql_text IS NOT NULL;';
		INSERT #text (src_order, label, txt)
		EXEC @exec @sql;
		IF @major >= 16
		BEGIN
			SET @sql = N'SELECT 5, N''P6 Query Store hint query_id '' + CONVERT(NVARCHAR(20), h.query_id), h.query_hint_text FROM sys.query_store_query_hints h;';
			INSERT #text (src_order, label, txt)
			EXEC @exec @sql;
		END
		SET @sql = N'SELECT p.plan_id, p.query_id, CONVERT(NVARCHAR(MAX), p.query_plan) FROM sys.query_store_plan p WHERE p.is_forced_plan = 1;';
		INSERT #forced (plan_id, query_id, query_plan)
		EXEC @exec @sql;
	END TRY
	BEGIN CATCH
		SET @qs = N'not readable';
	END CATCH
END

SELECT @pn += 1, @pwhat = N'read the server start time' + N' (' + REPLACE(CONVERT(NVARCHAR(30), CONVERT(MONEY, (SELECT COUNT(*) FROM #text)), 1), N'.00', N'') + N' texts so far)', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*The usage window: the later of the server start and the database's create date (a restore or attach resets the counters).
A server start time that cannot be read stops the tool: every UNUSED verdict is measured over this window (I6)*/
BEGIN TRY
	SELECT @server_start = sqlserver_start_time FROM sys.dm_os_sys_info;
	IF @server_start IS NULL RAISERROR(N'sys.dm_os_sys_info returned no start time', 16, 1);
END TRY
BEGIN CATCH
	SET @err = ERROR_MESSAGE();
	RAISERROR(N'index-consolidation: the server start time could not be read (%s). Nothing was judged.', 16, 1, @err);
	RETURN;
END CATCH
SELECT @create_date = create_date, @ag = CASE WHEN replica_id IS NULL THEN N'no' ELSE N'yes' END, @autoclose = is_auto_close_on
FROM sys.databases WHERE database_id = @dbid;
SET @window_start = CASE WHEN @create_date > @server_start THEN @create_date ELSE @server_start END;
SET @window_days = DATEDIFF(SECOND, @window_start, GETDATE()) / 86400;
SELECT @adhoc = CONVERT(INT, value_in_use) FROM sys.configurations WHERE name = N'optimize for ad hoc workloads';

SELECT @pn += 1, @pwhat = N'read the catalog: indexes, columns, partitions, foreign keys, full-text keys', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
IF OBJECT_ID(N'tempdb..#ix') IS NOT NULL DROP TABLE #ix;
IF OBJECT_ID(N'tempdb..#ic') IS NOT NULL DROP TABLE #ic;
IF OBJECT_ID(N'tempdb..#part') IS NOT NULL DROP TABLE #part;
IF OBJECT_ID(N'tempdb..#fk') IS NOT NULL DROP TABLE #fk;
IF OBJECT_ID(N'tempdb..#fkc') IS NOT NULL DROP TABLE #fkc;
IF OBJECT_ID(N'tempdb..#ft') IS NOT NULL DROP TABLE #ft;
IF OBJECT_ID(N'tempdb..#enc') IS NOT NULL DROP TABLE #enc;
IF OBJECT_ID(N'tempdb..#encdep') IS NOT NULL DROP TABLE #encdep;
IF OBJECT_ID(N'tempdb..#blk') IS NOT NULL DROP TABLE #blk;
IF OBJECT_ID(N'tempdb..#g') IS NOT NULL DROP TABLE #g;
IF OBJECT_ID(N'tempdb..#m') IS NOT NULL DROP TABLE #m;
IF OBJECT_ID(N'tempdb..#pfx') IS NOT NULL DROP TABLE #pfx;
IF OBJECT_ID(N'tempdb..#s5') IS NOT NULL DROP TABLE #s5;
IF OBJECT_ID(N'tempdb..#need') IS NOT NULL DROP TABLE #need;
IF OBJECT_ID(N'tempdb..#rs3') IS NOT NULL DROP TABLE #rs3;

CREATE TABLE #ix
	(
	object_id INT NOT NULL
	, index_id INT NOT NULL
	, schema_name SYSNAME NOT NULL
	, table_name SYSNAME NOT NULL
	, index_name SYSNAME NULL
	, type TINYINT NOT NULL
	, type_desc NVARCHAR(60) NULL
	, obj_type CHAR(2) NULL
	, is_unique BIT NOT NULL
	, is_primary_key BIT NOT NULL
	, is_unique_constraint BIT NOT NULL
	, is_disabled BIT NOT NULL
	, is_hypothetical BIT NOT NULL
	, is_memopt BIT NOT NULL
	, filter NVARCHAR(MAX) COLLATE Latin1_General_BIN2 NULL
	, fill_factor TINYINT NULL
	, is_padded BIT NULL
	, ignore_dup_key BIT NULL
	, no_recompute BIT NULL
	, allow_row_locks BIT NULL
	, allow_page_locks BIT NULL
	, ofsk BIT NULL
	, stats_incremental BIT NULL
	, data_space_name SYSNAME NULL
	, data_space_type CHAR(2) NULL
	, kstr NVARCHAR(MAX) COLLATE Latin1_General_BIN2 NULL
	, names_plain NVARCHAR(MAX) COLLATE Latin1_General_BIN2 NULL
	, nkeys INT NULL
	, istr NVARCHAR(MAX) COLLATE Latin1_General_BIN2 NULL
	, part_col SYSNAME NULL
	, reads BIGINT NOT NULL DEFAULT 0
	, writes BIGINT NOT NULL DEFAULT 0
	, stats_date DATETIME NULL	/*STATS_DATE: the index's last build or statistics update (rule 6's per-index window)*/
	, size_mb DECIMAL(19, 2) NULL
	, in_play BIT NOT NULL DEFAULT 0
	, fk_ref BIT NOT NULL DEFAULT 0
	, ft_key BIT NOT NULL DEFAULT 0
	, p6 NVARCHAR(400) NULL
	, p7 NVARCHAR(400) NULL
	, prot_rank INT NOT NULL DEFAULT 9
	, protected_by NVARCHAR(MAX) NULL
	, is_keeper BIT NOT NULL DEFAULT 0
	, verdict NVARCHAR(20) NULL
	, target_id INT NULL
	, confidence NVARCHAR(10) NULL
	, reason NVARCHAR(MAX) NULL
	, fdiff SYSNAME NULL
	, block_which NVARCHAR(400) NULL
	, would_keep NVARCHAR(MAX) NULL
	, step TINYINT NULL
	, new_istr NVARCHAR(MAX) NULL
	, script NVARCHAR(MAX) NULL
	, drop_script NVARCHAR(MAX) NULL
	, cr_head NVARCHAR(MAX) NULL	/*the generator: CREATE [UNIQUE ]NONCLUSTERED INDEX ... ON [db].[s].[t] (keys)*/
	, cr_where NVARCHAR(MAX) NULL	/*' WHERE <filter>', or empty*/
	, cr_opts NVARCHAR(MAX) NULL	/*every stored option, from PAD_INDEX on, without DROP_EXISTING, OPTIMIZE_FOR_SEQUENTIAL_KEY or ONLINE*/
	, cr_ofsk NVARCHAR(MAX) NULL	/*', OPTIMIZE_FOR_SEQUENTIAL_KEY = ON' or empty: CREATE only, a REBUILD refuses it (Msg 155)*/
	, cr_on NVARCHAR(MAX) NULL		/*the data space, with the partitioning column for a scheme*/
	, stmt NVARCHAR(MAX) NULL		/*the bare statement (no USE or SET prefix): step-1 widen or step-2 DISABLE*/
	, drop_stmt NVARCHAR(MAX) NULL	/*the bare DROP INDEX of a step-2 row*/
	, rb_stmt NVARCHAR(MAX) NULL	/*the bare rollback of stmt: the widen with the ORIGINAL includes, or a REBUILD of a disable*/
	, drop_rb_stmt NVARCHAR(MAX) NULL	/*the bare rollback of drop_stmt: the original definition as a plain CREATE*/
	, rb_script NVARCHAR(MAX) NULL	/*rb_stmt with the USE and SET prefix*/
	, drop_rb_script NVARCHAR(MAX) NULL	/*drop_rb_stmt with the USE and SET prefix*/
	, size_kept_for NVARCHAR(MAX) NULL	/*a keeper's members that the size filter turned NOT JUDGED*/
	, skip_why NVARCHAR(100) NULL	/*set when a bare statement holds CR, LF or TAB, or its keeper's does*/
	, prog_line NVARCHAR(MAX) NULL	/*the audit script's progress line before this row's statement (P2), set only for a statement that runs*/
	, PRIMARY KEY (object_id, index_id)
	);
CREATE TABLE #ic
	(
	object_id INT NOT NULL
	, index_id INT NOT NULL
	, column_name SYSNAME COLLATE Latin1_General_BIN2 NOT NULL
	, key_ordinal INT NOT NULL
	, is_desc BIT NOT NULL
	, is_included BIT NOT NULL
	, partition_ordinal INT NOT NULL
	);
CREATE TABLE #part
	(
	object_id INT NOT NULL
	, index_id INT NOT NULL
	, partition_number INT NOT NULL
	, comp NVARCHAR(60) NULL
	, used_pages BIGINT NULL
	);
CREATE TABLE #fk (fk_id INT NOT NULL, fk_name SYSNAME NOT NULL, parent_object_id INT NOT NULL, ref_object_id INT NOT NULL, key_index_id INT NULL, ncols INT NOT NULL);
CREATE TABLE #fkc (fk_id INT NOT NULL, column_name SYSNAME COLLATE Latin1_General_BIN2 NOT NULL);
CREATE TABLE #ft (object_id INT NOT NULL, unique_index_id INT NOT NULL);
CREATE TABLE #enc (object_id INT NOT NULL, label NVARCHAR(400) NOT NULL);
CREATE TABLE #encdep (module_id INT NOT NULL, referenced_id INT NULL);
CREATE TABLE #blk (object_id INT NULL, which NVARCHAR(400) NOT NULL);
CREATE TABLE #rs3 (seq INT IDENTITY(1, 1) PRIMARY KEY, line NVARCHAR(MAX) NOT NULL);

/*Every index of a user table or indexed view. Columns that do not exist on older versions are read only after the version test*/
SET @sql = N'SELECT i.object_id, i.index_id, s.name, o.name, i.name, i.type, i.type_desc, o.type, i.is_unique, i.is_primary_key
	, i.is_unique_constraint, i.is_disabled, i.is_hypothetical, '
	+ CASE WHEN @major >= 12 THEN N'ISNULL(t.is_memory_optimized, 0)' ELSE N'CONVERT(BIT, 0)' END + N'
	, CASE WHEN i.has_filter = 1 THEN i.filter_definition END, i.fill_factor, i.is_padded, i.ignore_dup_key, ISNULL(st.no_recompute, 0)
	, i.allow_row_locks, i.allow_page_locks, '
	+ CASE WHEN @major >= 15 THEN N'i.optimize_for_sequential_key' ELSE N'CONVERT(BIT, 0)' END + N', '
	+ CASE WHEN @major >= 12 THEN N'ISNULL(st.is_incremental, 0)' ELSE N'CONVERT(BIT, 0)' END + N', ds.name, ds.type, STATS_DATE(i.object_id, i.index_id)
FROM sys.indexes i
JOIN sys.objects o ON o.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
LEFT JOIN sys.tables t ON t.object_id = i.object_id
LEFT JOIN sys.stats st ON st.object_id = i.object_id AND st.stats_id = i.index_id
LEFT JOIN sys.data_spaces ds ON ds.data_space_id = i.data_space_id
WHERE i.index_id > 0
AND o.type IN (''U'', ''V'') AND o.is_ms_shipped = 0
AND (@schema IS NULL OR s.name = @schema)
AND (@table IS NULL OR o.name = @table);';
INSERT #ix (object_id, index_id, schema_name, table_name, index_name, type, type_desc, obj_type, is_unique, is_primary_key
	, is_unique_constraint, is_disabled, is_hypothetical, is_memopt, filter, fill_factor, is_padded, ignore_dup_key, no_recompute
	, allow_row_locks, allow_page_locks, ofsk, stats_incremental, data_space_name, data_space_type, stats_date)
EXEC @exec @sql, N'@schema SYSNAME, @table SYSNAME', @schema = @SchemaName, @table = @TableName;

SET @sql = N'SELECT ic.object_id, ic.index_id, c.name, ic.key_ordinal, ic.is_descending_key, ic.is_included_column, ic.partition_ordinal
FROM sys.index_columns ic
JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE EXISTS (SELECT 1 FROM #ix x WHERE x.object_id = ic.object_id AND x.index_id = ic.index_id);';
INSERT #ic (object_id, index_id, column_name, key_ordinal, is_desc, is_included, partition_ordinal)
EXEC @exec @sql;

SET @sql = N'SELECT p.object_id, p.index_id, p.partition_number, p.data_compression_desc, ps.used_page_count
FROM sys.partitions p
LEFT JOIN sys.dm_db_partition_stats ps ON ps.partition_id = p.partition_id
WHERE EXISTS (SELECT 1 FROM #ix x WHERE x.object_id = p.object_id AND x.index_id = p.index_id);';
INSERT #part (object_id, index_id, partition_number, comp, used_pages)
EXEC @exec @sql;

/*Foreign keys (P4 on the referenced side, P5 on the referencing side) and full-text keys (P8)*/
SET @sql = N'SELECT f.object_id, f.name, f.parent_object_id, f.referenced_object_id, f.key_index_id
	, (SELECT COUNT(*) FROM sys.foreign_key_columns fc WHERE fc.constraint_object_id = f.object_id)
FROM sys.foreign_keys f;';
INSERT #fk (fk_id, fk_name, parent_object_id, ref_object_id, key_index_id, ncols)
EXEC @exec @sql;
SET @sql = N'SELECT fc.constraint_object_id, c.name
FROM sys.foreign_key_columns fc
JOIN sys.columns c ON c.object_id = fc.parent_object_id AND c.column_id = fc.parent_column_id;';
INSERT #fkc (fk_id, column_name)
EXEC @exec @sql;
SET @sql = N'SELECT fi.object_id, fi.unique_index_id FROM sys.fulltext_indexes fi;';
INSERT #ft (object_id, unique_index_id)
EXEC @exec @sql;

SELECT @pn += 1, @pwhat = N'read index usage' + N' (' + REPLACE(CONVERT(NVARCHAR(30), CONVERT(MONEY, (SELECT COUNT(*) FROM #ix)), 1), N'.00', N'') + N' indexes)', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*Usage since the window start. No row = 0. A usage read that fails stops the tool: carrying on would read every index as 0
reads and offer to drop indexes that are in use (I6)*/
BEGIN TRY
	UPDATE x SET
		reads = ISNULL(u.user_seeks + u.user_scans + u.user_lookups, 0)
		, writes = ISNULL(u.user_updates, 0)
	FROM #ix x
	LEFT JOIN sys.dm_db_index_usage_stats u ON u.database_id = @dbid AND u.object_id = x.object_id AND u.index_id = x.index_id;
END TRY
BEGIN CATCH
	SET @err = ERROR_MESSAGE();
	RAISERROR(N'index-consolidation: index usage could not be read (%s). Nothing was judged.', 16, 1, @err);
	RETURN;
END CATCH

SELECT @pn += 1, @pwhat = N'build the key and include lists' + N' (' + REPLACE(CONVERT(NVARCHAR(30), CONVERT(MONEY, (SELECT COUNT(*) FROM #ic)), 1), N'.00', N'') + N' index columns)', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*K = key columns in key order with direction. I = included columns as a sorted set. The partitioning column SQL adds to an
aligned index (key_ordinal 0, not included) is in neither*/
UPDATE x SET
	kstr = ISNULL(STUFF((SELECT N', ' + QUOTENAME(c.column_name) + CASE WHEN c.is_desc = 1 THEN N' DESC' ELSE N' ASC' END
		FROM #ic c WHERE c.object_id = x.object_id AND c.index_id = x.index_id AND c.key_ordinal > 0
		ORDER BY c.key_ordinal FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N''), N'')
	, names_plain = ISNULL(STUFF((SELECT N',' + c.column_name
		FROM #ic c WHERE c.object_id = x.object_id AND c.index_id = x.index_id AND c.key_ordinal > 0
		ORDER BY c.key_ordinal FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''), N'')
	, nkeys = (SELECT COUNT(*) FROM #ic c WHERE c.object_id = x.object_id AND c.index_id = x.index_id AND c.key_ordinal > 0)
	, istr = ISNULL(STUFF((SELECT N', ' + QUOTENAME(c.column_name)
		FROM #ic c WHERE c.object_id = x.object_id AND c.index_id = x.index_id AND c.is_included = 1
		ORDER BY c.column_name FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N''), N'')
	, part_col = (SELECT TOP (1) c.column_name FROM #ic c WHERE c.object_id = x.object_id AND c.index_id = x.index_id AND c.partition_ordinal = 1)
	, size_mb = (SELECT CONVERT(DECIMAL(19, 2), SUM(p.used_pages) / 128.0) FROM #part p WHERE p.object_id = x.object_id AND p.index_id = x.index_id)
FROM #ix x;

SELECT @pn += 1, @pwhat = N'rule 1: not judged' + N' (' + REPLACE(CONVERT(NVARCHAR(30), CONVERT(MONEY, (SELECT COUNT(*) FROM #ix)), 1), N'.00', N'') + N' indexes)', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*Rule 1: NOT JUDGED. Only enabled, real, nonclustered rowstore indexes on disk-based tables are compared*/
UPDATE #ix SET
	verdict = N'NOT JUDGED'
	, step = 3
	, reason = CASE
		WHEN type = 1 THEN N'clustered index'
		WHEN type = 3 THEN N'XML index'
		WHEN type = 4 THEN N'spatial index'
		WHEN type = 5 THEN N'clustered columnstore index'
		WHEN type = 6 THEN N'nonclustered columnstore index'
		WHEN type = 7 THEN N'hash index'
		WHEN type <> 2 THEN N'index type ' + ISNULL(type_desc, N'?')
		WHEN is_memopt = 1 THEN N'memory-optimized table'
		WHEN is_hypothetical = 1 THEN N'hypothetical'
		WHEN is_disabled = 1 THEN N'disabled'
		END
WHERE (type <> 2 OR is_hypothetical = 1 OR is_disabled = 1 OR is_memopt = 1);
UPDATE #ix SET in_play = 1 WHERE verdict IS NULL;

SELECT @pn += 1, @pwhat = N'protection P1-P4, P8' + N' (' + REPLACE(CONVERT(NVARCHAR(30), CONVERT(MONEY, (SELECT COUNT(*) FROM #ix WHERE in_play = 1)), 1), N'.00', N'') + N' indexes in play)', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*Protection, BEFORE any verdict, because the keeper choice and the survivor test read it.
P1 primary key > P2 unique constraint > P3 unique index > the others (P4 foreign key target, P8 full-text key, then P6 text and
P7 forced plan). P9 (a keeper) is set as each step names one. P5 runs after rule 6*/
UPDATE x SET
	fk_ref = CASE WHEN EXISTS (SELECT 1 FROM #fk f WHERE f.ref_object_id = x.object_id AND f.key_index_id = x.index_id) THEN 1 ELSE 0 END
	, ft_key = CASE WHEN EXISTS (SELECT 1 FROM #ft f WHERE f.object_id = x.object_id AND f.unique_index_id = x.index_id) THEN 1 ELSE 0 END
FROM #ix x
WHERE x.in_play = 1;
UPDATE x SET
	prot_rank = CASE WHEN x.is_primary_key = 1 THEN 1 WHEN x.is_unique_constraint = 1 THEN 2 WHEN x.is_unique = 1 THEN 3
		WHEN x.fk_ref = 1 OR x.ft_key = 1 THEN 4 ELSE 9 END
	, protected_by = NULLIF(STUFF(
		CASE WHEN x.is_primary_key = 1 THEN N'; P1 primary key' ELSE N'' END
		+ CASE WHEN x.is_unique_constraint = 1 THEN N'; P2 unique constraint' ELSE N'' END
		+ CASE WHEN x.is_unique = 1 THEN N'; P3 unique index' ELSE N'' END
		+ CASE WHEN x.fk_ref = 1 THEN N'; P4 referenced by FK ' + STUFF((SELECT N', ' + f.fk_name FROM #fk f
			WHERE f.ref_object_id = x.object_id AND f.key_index_id = x.index_id ORDER BY f.fk_name FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N'')
			ELSE N'' END
		+ CASE WHEN x.ft_key = 1 THEN N'; P8 full-text key' ELSE N'' END, 1, 2, N''), N'')
FROM #ix x
WHERE x.in_play = 1;

SELECT @pn += 1, @pwhat = N'copy the module, plan guide and Agent job texts', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*P6: the texts the engine may compile. Every source is copied once into #text; a source that cannot be read blocks (I6)*/
SET @sql = N'SELECT 1, N''P6 module '' + ISNULL(s.name + N''.'' + o.name, N''object_id '' + CONVERT(NVARCHAR(20), m.object_id)), m.definition
FROM sys.sql_modules m
LEFT JOIN sys.objects o ON o.object_id = m.object_id
LEFT JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE m.definition IS NOT NULL;';
INSERT #text (src_order, label, txt)
EXEC @exec @sql;
/*An encrypted module cannot be read: the tables it references are a check not run (I6)*/
SET @sql = N'SELECT m.object_id, ISNULL(s.name + N''.'' + o.name, N''object_id '' + CONVERT(NVARCHAR(20), m.object_id))
FROM sys.sql_modules m
LEFT JOIN sys.objects o ON o.object_id = m.object_id
LEFT JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE m.definition IS NULL;';
INSERT #enc (object_id, label)
EXEC @exec @sql;
/*Its tables come from sys.sql_expression_dependencies, which only db_owner can read by default. It is read only when an
encrypted module exists; when it cannot be read, the whole database is blocked with that cause (I6)*/
IF EXISTS (SELECT 1 FROM #enc)
BEGIN
	BEGIN TRY
		SET @sql = N'SELECT d.referencing_id, d.referenced_id
FROM sys.sql_expression_dependencies d
WHERE d.referencing_id IN (SELECT m.object_id FROM sys.sql_modules m WHERE m.definition IS NULL);';
		INSERT #encdep (module_id, referenced_id)
		EXEC @exec @sql;
	END TRY
	BEGIN CATCH
		SET @deps_read = 0;
		INSERT #blk (object_id, which) VALUES (NULL, N'module dependencies not readable');
	END CATCH
END
BEGIN TRY
	SET @sql = N'SELECT 2, N''P6 plan guide '' + g.name, ISNULL(g.query_text, N'''') + N'' '' + ISNULL(g.hints, N'''') FROM sys.plan_guides g;';
	INSERT #text (src_order, label, txt)
	EXEC @exec @sql;
END TRY
BEGIN CATCH
	INSERT #blk (object_id, which) VALUES (NULL, N'plan guides not readable');
END CATCH
/*The plan cache and Query Store texts were copied at the top. Agent job steps: read when the login can; not a block when it cannot*/
BEGIN TRY
	SET @sql = N'SELECT 6, N''P6 agent job '' + j.name + N'' step '' + CONVERT(NVARCHAR(10), s.step_id), s.command
FROM dbo.sysjobsteps s JOIN dbo.sysjobs j ON j.job_id = s.job_id WHERE s.command IS NOT NULL;';
	INSERT #text (src_order, label, txt)
	EXEC @exec_msdb @sql;
	SET @jobs = N'read';
END TRY
BEGIN CATCH
	SET @jobs = N'not readable';
END CATCH

SELECT @pn += 1, @pwhat = N'P6/P7 name match' + N' (' + REPLACE(CONVERT(NVARCHAR(30), CONVERT(MONEY, (SELECT COUNT(*) FROM #ix WHERE in_play = 1 AND prot_rank = 9)), 1), N'.00', N'') + N' indexes x ' + REPLACE(CONVERT(NVARCHAR(30), CONVERT(MONEY, (SELECT COUNT(*) FROM #text)), 1), N'.00', N'') + N' texts)', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*P6 and P7 for every in-play index not already protected by P1-P4 or P8. The name is matched as text (case-insensitive) in
four forms: as written, with ] doubled (a bracketed hint: INDEX([a]]b])), with ' doubled (a hint inside a string literal or
dynamic SQL), and both. Each form has [, %, _ and the escape character escaped. Deliberately over-broad: a false match only KEEPs.
A pair whose name and text hold only codes 1..127 is matched under BIN2 on the uppercased text (fast, utxt); every other pair
runs the CI LIKE unchanged. The two give the same answer only in that range (tested for every character 0..127; NCHAR(0) differs
and stays on the CI path)*/
UPDATE #text SET fast = CASE WHEN txt IS NULL THEN 0
		WHEN txt COLLATE Latin1_General_100_BIN2 LIKE N'%[^' + NCHAR(1) + N'-' + NCHAR(127) + N']%' THEN 0 ELSE 1 END;
UPDATE #text SET utxt = UPPER(txt COLLATE Latin1_General_100_BIN2) WHERE fast = 1;
UPDATE x SET
	p6 = (SELECT TOP (1) t.label
		FROM (SELECT DISTINCT v.form FROM (VALUES (UPPER(x.index_name))
			, (REPLACE(UPPER(x.index_name), N']', N']]'))
			, (REPLACE(UPPER(x.index_name), N'''', N''''''))
			, (REPLACE(REPLACE(UPPER(x.index_name), N']', N']]'), N'''', N''''''))) v(form)) f
		CROSS APPLY (SELECT CASE WHEN UPPER(x.index_name) COLLATE Latin1_General_100_BIN2 LIKE N'%[^' + NCHAR(1) + N'-' + NCHAR(127) + N']%' THEN 0 ELSE 1 END AS nfast) n
		CROSS APPLY (SELECT REPLACE(REPLACE(REPLACE(REPLACE(f.form, N'~', N'~~'), N'[', N'~['), N'%', N'~%'), N'_', N'~_') AS pat) e
		JOIN #text t ON 1 = CASE WHEN n.nfast = 1 AND t.fast = 1
			THEN CASE WHEN t.utxt LIKE (N'%' + e.pat + N'%') COLLATE Latin1_General_100_BIN2 ESCAPE N'~' THEN 1 ELSE 0 END
			ELSE CASE WHEN UPPER(t.txt) COLLATE Latin1_General_100_CI_AS LIKE N'%' + e.pat + N'%' ESCAPE N'~' THEN 1 ELSE 0 END END
		ORDER BY t.src_order, t.label)
	, p7 = (SELECT TOP (1) N'P7 forced plan plan_id ' + CONVERT(NVARCHAR(20), f.plan_id) + N' (query_id ' + CONVERT(NVARCHAR(20), f.query_id) + N')'
		FROM #forced f
		WHERE CHARINDEX(N'Index="' + QUOTENAME(x.index_name) + N'"', f.query_plan) > 0
		AND CHARINDEX(N'Table="' + QUOTENAME(x.table_name) + N'"', f.query_plan) > 0
		ORDER BY f.plan_id)
FROM #ix x
WHERE x.in_play = 1 AND x.prot_rank = 9;
UPDATE #ix SET
	prot_rank = CASE WHEN p6 IS NOT NULL OR p7 IS NOT NULL THEN 4 ELSE prot_rank END
	, protected_by = NULLIF(STUFF(ISNULL(N'; ' + p6, N'') + ISNULL(N'; ' + p7, N''), 1, 2, N''), N'')
WHERE in_play = 1 AND prot_rank = 9;

SELECT @pn += 1, @pwhat = N'rules 2-6: duplicates, merges, prefixes, filters, unused', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*Rule 2: EXACT DUPLICATE. Same table, same K, same I, same F. Keeper: protected first, then most reads, then lowest index_id*/
SELECT object_id, index_id, kstr, istr, ISNULL(filter, N'') AS f
	, ROW_NUMBER() OVER (PARTITION BY object_id, kstr, istr, ISNULL(filter, N'') ORDER BY prot_rank, reads DESC, index_id) AS rn
INTO #g
FROM #ix
WHERE in_play = 1;

UPDATE x SET
	verdict = CASE WHEN pm.keep_member = 1 THEN N'KEEP' ELSE N'EXACT DUPLICATE' END
	, target_id = CASE WHEN pm.keep_member = 1 THEN NULL ELSE k.index_id END
	, step = CASE WHEN pm.keep_member = 1 THEN 3 ELSE 2 END
	, reason = CASE WHEN pm.keep_member = 1
		THEN N'exact duplicate of ' + k.index_name + N'; protected by ' + x.protected_by + N'; review by hand'
		ELSE N'same keys, includes and filter as ' + k.index_name END
FROM #ix x
JOIN #g gx ON gx.object_id = x.object_id AND gx.index_id = x.index_id
JOIN #g gk ON gk.object_id = gx.object_id AND gk.kstr = gx.kstr AND gk.istr = gx.istr AND gk.f = gx.f AND gk.rn = 1
JOIN #ix k ON k.object_id = gk.object_id AND k.index_id = gk.index_id
CROSS APPLY (SELECT CASE WHEN x.prot_rank < 9 THEN 1 ELSE 0 END AS keep_member) pm
WHERE gx.rn > 1;

UPDATE k SET is_keeper = 1
FROM #ix k
WHERE EXISTS (SELECT 1 FROM #ix m WHERE m.object_id = k.object_id AND m.target_id = k.index_id);

/*Rule 3: MERGE. Among the indexes still in play with no verdict yet (a rule-2 keeper counts; a protected duplicate member is
represented by its keeper), same table, same K and same F, other I. Keeper: protected first, then a keeper from step 2, then
most reads, then lowest index_id. A protected member, or a keeper from step 2, is never merged away. A constraint (P1/P2), a
foreign key target (P4) or a full-text key (P8) is not widened by policy (the engine widens an FK-referenced unique index with
DROP_EXISTING; only P1/P2 refuse, Msg 1907), so a member with includes it lacks stays, for review by hand*/
SELECT object_id, index_id, kstr, ISNULL(filter, N'') AS f
	, ROW_NUMBER() OVER (PARTITION BY object_id, kstr, ISNULL(filter, N'') ORDER BY prot_rank, is_keeper DESC, reads DESC, index_id) AS rn
INTO #m
FROM #ix
WHERE in_play = 1 AND verdict IS NULL;

UPDATE x SET
	verdict = CASE WHEN b.code = 0 THEN N'MERGE' ELSE N'KEEP' END
	, target_id = CASE WHEN b.code = 0 THEN k.index_id END
	, step = CASE WHEN b.code = 0 THEN 2 ELSE 3 END
	, reason = CASE b.code
		WHEN 0 THEN N'same keys and filter as ' + k.index_name + N'; its includes move there'
		WHEN 1 THEN N'same keys as ' + k.index_name + N'; protected by ' + ISNULL(x.protected_by, N'P9 keeper') + N'; review by hand'
		WHEN 2 THEN N'same keys as constraint ' + k.index_name + N', which cannot take INCLUDE columns'
		ELSE N'keeper ' + k.index_name + N' is ' + CASE WHEN k.fk_ref = 1 THEN N'FK-referenced' ELSE N'a full-text key' END + N'; not widened by policy, review by hand' END
FROM #ix x
JOIN #m mx ON mx.object_id = x.object_id AND mx.index_id = x.index_id
JOIN #m mk ON mk.object_id = mx.object_id AND mk.kstr = mx.kstr AND mk.f = mx.f AND mk.rn = 1
JOIN #ix k ON k.object_id = mk.object_id AND k.index_id = mk.index_id
CROSS APPLY (SELECT CASE WHEN EXISTS (SELECT 1 FROM #ic c WHERE c.object_id = x.object_id AND c.index_id = x.index_id AND c.is_included = 1
		AND NOT EXISTS (SELECT 1 FROM #ic kc WHERE kc.object_id = k.object_id AND kc.index_id = k.index_id AND kc.column_name = c.column_name
			AND (kc.key_ordinal > 0 OR kc.is_included = 1))) THEN 1 ELSE 0 END AS needs) w
CROSS APPLY (SELECT CASE
		WHEN x.prot_rank < 9 OR x.is_keeper = 1 THEN 1
		WHEN w.needs = 1 AND (k.is_primary_key = 1 OR k.is_unique_constraint = 1) THEN 2
		WHEN w.needs = 1 AND (k.fk_ref = 1 OR k.ft_key = 1) THEN 3
		ELSE 0 END AS code) b
WHERE mx.rn > 1;

UPDATE k SET is_keeper = 1
FROM #ix k
WHERE EXISTS (SELECT 1 FROM #ix m WHERE m.object_id = k.object_id AND m.target_id = k.index_id);

/*Rule 4: SUPERSEDED. Pairs (A, B) on the same table with the same F where K(A) is a strict left prefix of K(B), compared
entry by entry (name AND direction), among indexes that are not being dropped. A row with a drop verdict is never a keeper*/
SELECT a.object_id, a.index_id AS a_id, b.index_id AS b_id
INTO #pfx
FROM #ix a
JOIN #ix b ON b.object_id = a.object_id AND b.index_id <> a.index_id
WHERE a.in_play = 1 AND b.in_play = 1
AND ISNULL(a.verdict, N'KEEP') = N'KEEP'
AND ISNULL(b.verdict, N'KEEP') = N'KEEP'
AND ISNULL(a.filter, N'') = ISNULL(b.filter, N'')
AND b.nkeys > a.nkeys
AND a.nkeys = (SELECT COUNT(*) FROM #ic ca
	JOIN #ic cb ON cb.object_id = ca.object_id AND cb.index_id = b.index_id AND cb.key_ordinal = ca.key_ordinal
		AND cb.column_name = ca.column_name AND cb.is_desc = ca.is_desc
	WHERE ca.object_id = a.object_id AND ca.index_id = a.index_id AND ca.key_ordinal > 0);

/*A: unprotected, no verdict yet, not a keeper (P9). B: a SURVIVOR (protected or a keeper, or not itself a strict prefix of
another index here). Of several B, the closest superset: fewest keys, then most reads, then lowest index_id.
When B is a constraint (P1/P2), a foreign key target (P4) or a full-text key (P8) and A has includes B lacks, B is not
widened (P1/P2: the engine refuses; P4/P8: by policy): A stays (no search for another survivor)*/
WITH c AS
	(
	SELECT p.object_id, p.a_id, p.b_id
		, ROW_NUMBER() OVER (PARTITION BY p.object_id, p.a_id ORDER BY b.nkeys, b.reads DESC, b.index_id) AS rn
	FROM #pfx p
	JOIN #ix a ON a.object_id = p.object_id AND a.index_id = p.a_id
	JOIN #ix b ON b.object_id = p.object_id AND b.index_id = p.b_id
	WHERE a.verdict IS NULL AND a.prot_rank = 9 AND a.is_keeper = 0
	AND (b.prot_rank < 9 OR b.is_keeper = 1
		OR NOT EXISTS (SELECT 1 FROM #pfx p2 WHERE p2.object_id = b.object_id AND p2.a_id = b.index_id))
	)
UPDATE a SET
	verdict = CASE WHEN e.code = 0 THEN N'SUPERSEDED' ELSE N'KEEP' END
	, target_id = CASE WHEN e.code = 0 THEN c.b_id END
	, step = CASE WHEN e.code = 0 THEN 2 ELSE 3 END
	, reason = CASE e.code
		WHEN 0 THEN N'keys are a left prefix of ' + b.index_name
		WHEN 2 THEN N'keys are a left prefix of constraint ' + b.index_name + N', which cannot take INCLUDE columns'
		ELSE N'keys are a left prefix of ' + b.index_name + N'; keeper ' + b.index_name + N' is '
			+ CASE WHEN b.fk_ref = 1 THEN N'FK-referenced' ELSE N'a full-text key' END + N'; not widened by policy, review by hand' END
FROM #ix a
JOIN c ON c.object_id = a.object_id AND c.a_id = a.index_id
JOIN #ix b ON b.object_id = c.object_id AND b.index_id = c.b_id
CROSS APPLY (SELECT CASE WHEN EXISTS (SELECT 1 FROM #ic ac WHERE ac.object_id = a.object_id AND ac.index_id = a.index_id AND ac.is_included = 1
		AND NOT EXISTS (SELECT 1 FROM #ic bc WHERE bc.object_id = b.object_id AND bc.index_id = b.index_id AND bc.column_name = ac.column_name
			AND (bc.key_ordinal > 0 OR bc.is_included = 1))) THEN 1 ELSE 0 END AS needs) w
CROSS APPLY (SELECT CASE
		WHEN w.needs = 1 AND (b.is_primary_key = 1 OR b.is_unique_constraint = 1) THEN 2
		WHEN w.needs = 1 AND (b.fk_ref = 1 OR b.ft_key = 1) THEN 3
		ELSE 0 END AS code) e
WHERE c.rn = 1;

UPDATE k SET is_keeper = 1
FROM #ix k
WHERE EXISTS (SELECT 1 FROM #ix m WHERE m.object_id = k.object_id AND m.target_id = k.index_id);

/*Rule 5: filter mismatch. An index still to be judged, with the same K as another index still in play but a different F, is
named here; with reads it is KEEP ('review by hand'), a keeper adds the note, with 0 reads rule 6 applies*/
UPDATE x SET
	fdiff = (SELECT TOP (1) y.index_name FROM #ix y
		WHERE y.object_id = x.object_id AND y.index_id <> x.index_id AND y.in_play = 1
		AND ISNULL(y.verdict, N'KEEP') NOT IN (N'UNUSED', N'EXACT DUPLICATE', N'SUPERSEDED', N'MERGE')
		AND y.kstr = x.kstr AND ISNULL(y.filter, N'') <> ISNULL(x.filter, N'')
		ORDER BY y.index_id)
FROM #ix x
WHERE x.in_play = 1 AND x.verdict IS NULL;

/*Rule 6: UNUSED. No reads since the window start, not protected, not a keeper. The usage window is per index:
it starts at the later of the database window start and STATS_DATE, the index's last build or statistics update, because an
index created or rebuilt later has been watched for less time (a rebuild restarts its usage counters). A statistics update also
moves STATS_DATE, so the window errs short, toward low confidence. NULL STATS_DATE = the database window start.*/
UPDATE x SET
	verdict = N'UNUSED'
	, step = 2
	, confidence = CASE WHEN @window_days < @MinUptimeDays OR DATEDIFF(SECOND, w.idx_start, GETDATE()) / 86400 < @MinUptimeDays
			OR @ag = N'yes' OR @autoclose = 1 OR @major IN (11, 12)
		THEN N'low' ELSE N'normal' END
	, reason = N'0 reads, ' + CONVERT(NVARCHAR(20), writes) + N' writes since ' + CONVERT(NVARCHAR(19), @window_start, 120)
		+ CASE WHEN w.idx_start > @window_start THEN N'; usage counted only since ' + CONVERT(NVARCHAR(16), w.idx_start, 120)
			+ N' (index created, rebuilt or statistics updated)' ELSE N'' END
		+ CASE WHEN @window_days < @MinUptimeDays THEN N'; usage window ' + CONVERT(NVARCHAR(10), @window_days) + N' days, under '
			+ CONVERT(NVARCHAR(10), @MinUptimeDays) ELSE N'' END
		+ CASE WHEN @ag = N'yes' THEN N'; reads on secondary replicas are not counted' ELSE N'' END
		+ CASE WHEN @autoclose = 1 THEN N'; counters reset when the database closes' ELSE N'' END
		+ CASE WHEN @major IN (11, 12) THEN N'; index rebuilds reset usage on this version' ELSE N'' END
FROM #ix x
CROSS APPLY (SELECT CASE WHEN x.stats_date > @window_start THEN x.stats_date ELSE @window_start END AS idx_start) w
WHERE in_play = 1 AND verdict IS NULL AND reads = 0 AND prot_rank = 9 AND is_keeper = 0;

SELECT @pn += 1, @pwhat = N'P5: foreign key support', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*P5, after rule 6 (it only turns UNUSED into KEEP): for each foreign key, S = the enabled, real, unfiltered clustered or
nonclustered indexes whose first n keys are the FK's n columns as a set. When no member of S is a keeper and every member has
a drop verdict, the nonclustered member with most reads, then lowest index_id, is kept, so one index always supports the FK*/
SELECT f.fk_id, f.fk_name, x.object_id, x.index_id
INTO #s5
FROM #fk f
JOIN #ix x ON x.object_id = f.parent_object_id
WHERE x.type IN (1, 2) AND x.is_disabled = 0 AND x.is_hypothetical = 0 AND x.filter IS NULL
AND x.nkeys >= f.ncols
AND f.ncols = (SELECT COUNT(*) FROM #fkc fc
	JOIN #ic c ON c.object_id = x.object_id AND c.index_id = x.index_id AND c.key_ordinal BETWEEN 1 AND f.ncols AND c.column_name = fc.column_name
	WHERE fc.fk_id = f.fk_id);

WITH r AS
	(
	SELECT s.fk_id, s.fk_name, s.object_id, s.index_id
		, ROW_NUMBER() OVER (PARTITION BY s.fk_id ORDER BY x.reads DESC, x.index_id) AS rn
	FROM #s5 s
	JOIN #ix x ON x.object_id = s.object_id AND x.index_id = s.index_id
	WHERE x.type = 2
	AND NOT EXISTS (SELECT 1 FROM #s5 s2 JOIN #ix y ON y.object_id = s2.object_id AND y.index_id = s2.index_id
		WHERE s2.fk_id = s.fk_id AND (y.is_keeper = 1 OR ISNULL(y.verdict, N'KEEP') NOT IN (N'UNUSED', N'EXACT DUPLICATE', N'SUPERSEDED', N'MERGE')))
	)
UPDATE x SET
	verdict = NULL
	, step = NULL
	, confidence = NULL
	, reason = NULL
	, prot_rank = 4
	, protected_by = ISNULL(x.protected_by + N'; ', N'') + N'P5 supports FK ' + r.fk_name
FROM #ix x
JOIN r ON r.object_id = x.object_id AND r.index_id = x.index_id
WHERE r.rn = 1 AND x.verdict = N'UNUSED';

SELECT @pn += 1, @pwhat = N'I6: safety checks that could not run', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*I6, last: a safety check that could not run blocks every drop verdict in its scope (a table for an encrypted module, the
whole database for an unreadable source). Nothing in scope is dropped, so no keeper there is rebuilt either*/
INSERT #blk (object_id, which)
SELECT DISTINCT d.referenced_id, N'module ' + e.label + N' is encrypted'
FROM #enc e JOIN #encdep d ON d.module_id = e.object_id
WHERE d.referenced_id IS NOT NULL;
INSERT #blk (object_id, which)
SELECT NULL, N'module ' + e.label + N' is encrypted (its tables are not known)'
FROM #enc e
WHERE @deps_read = 1	/*when the dependencies could not be read, the block above already names that cause*/
AND (NOT EXISTS (SELECT 1 FROM #encdep d WHERE d.module_id = e.object_id AND d.referenced_id IS NOT NULL)
OR EXISTS (SELECT 1 FROM #encdep d WHERE d.module_id = e.object_id AND d.referenced_id IS NULL));
IF @pc = N'not readable' INSERT #blk (object_id, which) VALUES (NULL, N'plan cache not readable');
IF @qs IN (N'not readable') INSERT #blk (object_id, which) VALUES (NULL, N'Query Store not readable');

UPDATE x SET
	block_which = (SELECT TOP (1) b.which FROM #blk b WHERE b.object_id IS NULL OR b.object_id = x.object_id ORDER BY b.which)
FROM #ix x
WHERE x.in_play = 1;
UPDATE k SET
	would_keep = STUFF((SELECT N', ' + m.index_name FROM #ix m WHERE m.object_id = k.object_id AND m.target_id = k.index_id
		ORDER BY m.index_id FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N'')
FROM #ix k
WHERE k.block_which IS NOT NULL AND k.is_keeper = 1;
UPDATE #ix SET
	verdict = N'NOT JUDGED'
	, target_id = NULL
	, step = 3
	, confidence = NULL
	, reason = N'safety check not run: ' + block_which
WHERE block_which IS NOT NULL AND verdict IN (N'UNUSED', N'EXACT DUPLICATE', N'SUPERSEDED', N'MERGE');

SELECT @pn += 1, @pwhat = N'size filter', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*Size filter, LAST among the verdicts, after I6: every verdict, keeper, protection and P5 rescue above is
computed exactly as with @MinSizeMB = 0, and the filter only turns a drop verdict below the size into NOT JUDGED. A row
I6 blocked keeps the I6 reason, because I6 ran first. size_mb NULL occurs only on rule-1 rows; never filtered (an unknown size
is not smaller). Include widening below reads only rows that still have a drop verdict, so a keeper loses the widening its
filtered members needed and keeps the widening the others need.*/
UPDATE k SET size_kept_for = STUFF((SELECT N', ' + m.index_name FROM #ix m WHERE m.object_id = k.object_id AND m.target_id = k.index_id
		AND m.in_play = 1 AND m.size_mb < @MinSizeMB AND m.verdict IN (N'EXACT DUPLICATE', N'SUPERSEDED', N'MERGE')
		ORDER BY m.index_id FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N'')
FROM #ix k
WHERE k.is_keeper = 1;
UPDATE #ix SET
	verdict = N'NOT JUDGED'
	, target_id = NULL
	, step = 3
	, confidence = NULL
	, reason = N'below size filter (' + CONVERT(NVARCHAR(30), size_mb) + N' MB < ' + CONVERT(NVARCHAR(30), @MinSizeMB) + N' MB)'
WHERE in_play = 1 AND size_mb < @MinSizeMB AND verdict IN (N'UNUSED', N'EXACT DUPLICATE', N'SUPERSEDED', N'MERGE');

SELECT @pn += 1, @pwhat = N'include widening and the script generator', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*Include widening: each keeper gets AT MOST ONE step-1 script. Its INCLUDE list = its own I UNION the I of EVERY row that
targets it, minus its key columns, sorted by name*/
SELECT DISTINCT m.object_id, m.target_id AS keeper_id, c.column_name
INTO #need
FROM #ix m
JOIN #ic c ON c.object_id = m.object_id AND c.index_id = m.index_id AND c.is_included = 1
WHERE m.target_id IS NOT NULL
AND m.verdict IN (N'EXACT DUPLICATE', N'SUPERSEDED', N'MERGE')
AND NOT EXISTS (SELECT 1 FROM #ic k WHERE k.object_id = m.object_id AND k.index_id = m.target_id AND k.column_name = c.column_name
	AND (k.key_ordinal > 0 OR k.is_included = 1));

UPDATE k SET
	new_istr = STUFF((SELECT N', ' + QUOTENAME(u.column_name)
		FROM (SELECT c.column_name FROM #ic c WHERE c.object_id = k.object_id AND c.index_id = k.index_id AND c.is_included = 1
			UNION SELECT n.column_name FROM #need n WHERE n.object_id = k.object_id AND n.keeper_id = k.index_id) u
		ORDER BY u.column_name FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N'')
FROM #ix k
WHERE EXISTS (SELECT 1 FROM #need n WHERE n.object_id = k.object_id AND n.keeper_id = k.index_id);

/*The generator: ONE place builds the pieces of an index's CREATE text, for every row that may need one (a step-1
keeper, every drop verdict). A statement is cr_head + its include part + cr_where + ' WITH (' + [DROP_EXISTING = ON, ] + cr_opts
+ cr_ofsk + @cr_online + ') ON ' + cr_on + ';'. OPTIMIZE_FOR_SEQUENTIAL_KEY is its own column (cr_ofsk) because ALTER INDEX ...
REBUILD refuses it (Msg 155); ONLINE stays last. Never a second hand-edited copy.
Keeps each keeper's own options, its own compression and its own data space*/
DECLARE @cr_online NVARCHAR(20) = CASE WHEN @online_ok = 1 THEN N', ONLINE = ON' ELSE N'' END;
UPDATE k SET
	cr_head = N'CREATE ' + CASE WHEN k.is_unique = 1 THEN N'UNIQUE ' ELSE N'' END + N'NONCLUSTERED INDEX ' + QUOTENAME(k.index_name)
		+ N' ON ' + QUOTENAME(@db) + N'.' + QUOTENAME(k.schema_name) + N'.' + QUOTENAME(k.table_name) + N' (' + k.kstr + N')'
	, cr_where = CASE WHEN k.filter IS NOT NULL THEN N' WHERE ' + k.filter ELSE N'' END
	, cr_opts = CONVERT(NVARCHAR(MAX), N'PAD_INDEX = ') + CASE WHEN k.is_padded = 1 THEN N'ON' ELSE N'OFF' END
		+ CASE WHEN k.fill_factor > 0 THEN N', FILLFACTOR = ' + CONVERT(NVARCHAR(3), k.fill_factor) ELSE N'' END
		+ CASE WHEN k.ignore_dup_key = 1 THEN N', IGNORE_DUP_KEY = ON' ELSE N'' END
		+ N', STATISTICS_NORECOMPUTE = ' + CASE WHEN k.no_recompute = 1 THEN N'ON' ELSE N'OFF' END
		+ N', ALLOW_ROW_LOCKS = ' + CASE WHEN k.allow_row_locks = 1 THEN N'ON' ELSE N'OFF' END
		+ N', ALLOW_PAGE_LOCKS = ' + CASE WHEN k.allow_page_locks = 1 THEN N'ON' ELSE N'OFF' END
		+ CASE WHEN (SELECT COUNT(DISTINCT p.comp) FROM #part p WHERE p.object_id = k.object_id AND p.index_id = k.index_id) <= 1
			THEN ISNULL((SELECT TOP (1) N', DATA_COMPRESSION = ' + p.comp FROM #part p WHERE p.object_id = k.object_id AND p.index_id = k.index_id), N'')
			ELSE (SELECT N', DATA_COMPRESSION = ' + v.comp + N' ON PARTITIONS ('
					+ STUFF((SELECT N', ' + CONVERT(NVARCHAR(10), p2.partition_number) FROM #part p2
						WHERE p2.object_id = k.object_id AND p2.index_id = k.index_id AND p2.comp = v.comp
						ORDER BY p2.partition_number FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N'') + N')'
				FROM (SELECT DISTINCT p.comp FROM #part p WHERE p.object_id = k.object_id AND p.index_id = k.index_id) v
				ORDER BY v.comp FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)') END
		+ CASE WHEN k.stats_incremental = 1 THEN N', STATISTICS_INCREMENTAL = ON' ELSE N'' END
	, cr_ofsk = CASE WHEN k.ofsk = 1 THEN N', OPTIMIZE_FOR_SEQUENTIAL_KEY = ON' ELSE N'' END
	, cr_on = CASE WHEN k.data_space_type = 'PS' THEN QUOTENAME(k.data_space_name) + N'(' + QUOTENAME(k.part_col) + N')'
			ELSE QUOTENAME(k.data_space_name) END
FROM #ix k
WHERE k.new_istr IS NOT NULL OR k.verdict IN (N'UNUSED', N'EXACT DUPLICATE', N'SUPERSEDED', N'MERGE');

/*Step 1, bare: rebuild the keeper in place with the widened include list (from the generator)*/
UPDATE k SET
	step = 1
	, stmt = k.cr_head + CASE WHEN k.new_istr <> N'' THEN @inc + k.new_istr + N')' ELSE N'' END + k.cr_where
		+ N' WITH (DROP_EXISTING = ON, ' + k.cr_opts + k.cr_ofsk + @cr_online + N') ON ' + k.cr_on + N';'
FROM #ix k
WHERE k.new_istr IS NOT NULL;

/*Step 2, bare: disable first (undo: ALTER INDEX ... REBUILD WITH the index's own options; a bare REBUILD loses its data
compression; @Mode = 'changecontrol' prints each rollback); the drop is in its own column*/
UPDATE #ix SET
	stmt = N'ALTER INDEX ' + QUOTENAME(index_name) + N' ON ' + QUOTENAME(@db) + N'.'
		+ QUOTENAME(schema_name) + N'.' + QUOTENAME(table_name) + N' DISABLE;'
	, drop_stmt = N'DROP INDEX ' + QUOTENAME(index_name) + N' ON ' + QUOTENAME(@db) + N'.'
		+ QUOTENAME(schema_name) + N'.' + QUOTENAME(table_name) + N';'
WHERE verdict IN (N'UNUSED', N'EXACT DUPLICATE', N'SUPERSEDED', N'MERGE');

/*The rollbacks, bare, from the same generator columns: a widen's rollback is the same CREATE ...
DROP_EXISTING with the index's ORIGINAL includes; a disable's rollback is a REBUILD with every stored option (cr_opts), because
a bare REBUILD of a disabled index drops its compression, but WITHOUT cr_ofsk: a REBUILD
refuses OPTIMIZE_FOR_SEQUENTIAL_KEY (Msg 155) and keeps the stored value without it; a drop's rollback is the original
definition as a plain CREATE. Constraint-backed indexes never get a drop verdict (P1/P2), so no ALTER TABLE ADD CONSTRAINT is
needed*/
UPDATE k SET
	rb_stmt = CASE WHEN k.step = 1 THEN k.cr_head + CASE WHEN k.istr <> N'' THEN @inc + k.istr + N')' ELSE N'' END + k.cr_where
			+ N' WITH (DROP_EXISTING = ON, ' + k.cr_opts + k.cr_ofsk + @cr_online + N') ON ' + k.cr_on + N';'
		ELSE N'ALTER INDEX ' + QUOTENAME(k.index_name) + N' ON ' + QUOTENAME(@db) + N'.' + QUOTENAME(k.schema_name) + N'.' + QUOTENAME(k.table_name)
			+ N' REBUILD WITH (' + k.cr_opts + @cr_online + N');' END
	, drop_rb_stmt = CASE WHEN k.drop_stmt IS NOT NULL THEN k.cr_head + CASE WHEN k.istr <> N'' THEN @inc + k.istr + N')' ELSE N'' END
			+ k.cr_where + N' WITH (' + k.cr_opts + k.cr_ofsk + @cr_online + N') ON ' + k.cr_on + N';' END
FROM #ix k
WHERE k.stmt IS NOT NULL;

SELECT @pn += 1, @pwhat = N'per-row scripts and KEEP reasons', @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
IF @Progress = 1 BEGIN SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(@pfmt, 0, 1, @pn, @ptot, @pwhat, @psec, @pfrac) WITH NOWAIT; END
/*No printed statement holds CR, LF or TAB: such a statement could not be one line of result set 3. The test is on
the bare statement, not the names, because a column name in an include list counts too. A row targeting a skipped keeper is
skipped with it: disabling it before its keeper is widened would lose coverage. The rollbacks are tested last, so a member of a
skipped keeper keeps the reason 'its keeper cannot be scripted'; a keeper's rollback holds nothing its widen does not*/
UPDATE #ix SET skip_why = N'its definition holds a line break or tab'
WHERE (stmt LIKE N'%[' + NCHAR(13) + NCHAR(10) + NCHAR(9) + N']%' OR drop_stmt LIKE N'%[' + NCHAR(13) + NCHAR(10) + NCHAR(9) + N']%');
UPDATE m SET skip_why = N'its keeper cannot be scripted'
FROM #ix m
JOIN #ix k ON k.object_id = m.object_id AND k.index_id = m.target_id
WHERE m.skip_why IS NULL AND m.stmt IS NOT NULL AND k.skip_why IS NOT NULL;
UPDATE #ix SET skip_why = N'its definition holds a line break or tab'
WHERE skip_why IS NULL
AND (rb_stmt LIKE N'%[' + NCHAR(13) + NCHAR(10) + NCHAR(9) + N']%' OR drop_rb_stmt LIKE N'%[' + NCHAR(13) + NCHAR(10) + NCHAR(9) + N']%');

/*The printed per-row scripts: ONE place adds the USE and SET prefix to each bare statement*/
UPDATE #ix SET
	script = CASE WHEN skip_why IS NOT NULL THEN N'SKIPPED (line break or tab)' ELSE CONVERT(NVARCHAR(MAX), @use) + @setline + stmt END
	, drop_script = CASE WHEN drop_stmt IS NULL THEN NULL WHEN skip_why IS NOT NULL THEN N'SKIPPED (line break or tab)'
		ELSE CONVERT(NVARCHAR(MAX), @use) + @setline + drop_stmt END
	, rb_script = CASE WHEN skip_why IS NOT NULL THEN N'SKIPPED (line break or tab)' ELSE CONVERT(NVARCHAR(MAX), @use) + @setline + rb_stmt END
	, drop_rb_script = CASE WHEN drop_rb_stmt IS NULL THEN NULL WHEN skip_why IS NOT NULL THEN N'SKIPPED (line break or tab)'
		ELSE CONVERT(NVARCHAR(MAX), @use) + @setline + drop_rb_stmt END
WHERE stmt IS NOT NULL;

/*Everything else: KEEP, with the protection first, then what it keeps for, then the filter note, then its use*/
UPDATE k SET
	verdict = N'KEEP'
	, step = ISNULL(k.step, 3)
	, reason = STUFF(
		ISNULL(N'; ' + k.protected_by, N'')
		+ CASE WHEN k.would_keep IS NOT NULL THEN N'; would keep for: ' + k.would_keep + N'; safety check not run: ' + k.block_which ELSE N'' END
		+ ISNULL(N'; keeper for: ' + STUFF((SELECT N', ' + m.index_name FROM #ix m WHERE m.object_id = k.object_id AND m.target_id = k.index_id
			ORDER BY m.index_id FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N''), N'')
		+ ISNULL(N'; kept for: ' + k.size_kept_for + N' (below size filter)', N'')
		+ CASE WHEN k.fdiff IS NOT NULL AND k.is_keeper = 0 THEN N'; filter differs from ' + k.fdiff + N'; review by hand' ELSE N'' END
		+ CASE WHEN k.fdiff IS NOT NULL AND k.is_keeper = 1 THEN N'; filter differs from ' + k.fdiff ELSE N'' END
		+ CASE WHEN k.reads > 0 THEN N'; used: ' + CONVERT(NVARCHAR(20), k.reads) + N' reads' ELSE N'; 0 reads' END, 1, 2, N'')
FROM #ix k
WHERE k.verdict IS NULL;

IF @Progress = 1 BEGIN SELECT @pms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME()); SELECT @psec = @pms / 1000, @pfrac = @pms % 1000; RAISERROR(N'index-consolidation: done in %d.%03d s', 0, 1, @psec, @pfrac) WITH NOWAIT; END

/*Result set 1: the header, with the usage window the figures cover*/
SELECT
	@@SERVERNAME AS server
	, CONVERT(NVARCHAR(128), SERVERPROPERTY('ProductVersion')) AS version
	, CONVERT(NVARCHAR(128), SERVERPROPERTY('Edition')) AS edition
	, @db AS [database]
	, @server_start AS server_start
	, @window_start AS window_start
	, @window_days AS window_days
	, N'UNUSED is low confidence under ' + CONVERT(NVARCHAR(10), @MinUptimeDays) + N' days' AS confidence_rule
	, @qs AS query_store
	, @pc + N' (optimize for ad hoc: ' + CASE WHEN @adhoc = 1 THEN N'on' ELSE N'off' END + N')' AS plan_cache
	, @jobs AS agent_jobs
	, @ag AS ag
	, (SELECT COUNT(*) FROM #ix WHERE verdict = N'KEEP') AS keep_count
	, (SELECT COUNT(*) FROM #ix WHERE verdict = N'UNUSED') AS unused_count
	, (SELECT COUNT(*) FROM #ix WHERE verdict = N'EXACT DUPLICATE') AS exact_duplicate_count
	, (SELECT COUNT(*) FROM #ix WHERE verdict = N'SUPERSEDED') AS superseded_count
	, (SELECT COUNT(*) FROM #ix WHERE verdict = N'MERGE') AS merge_count
	, (SELECT COUNT(*) FROM #ix WHERE verdict = N'NOT JUDGED') AS not_judged_count
	, @Mode AS mode
	, @MinSizeMB AS size_filter_mb
	, (SELECT COUNT(*) FROM #ix WHERE reason LIKE N'below size filter (%') AS below_size_filter_count
	, N'high: confidence low or over 10,240 MB; medium: DISABLE, or WIDEN over 1,024 MB; else low' AS risk_rule;

/*Mode audit: result set 3, ONE remediation script, one row per line, in run order. Built after the KEEP verdicts, because the
step-1 comment lines read reason. Step 1 widens keepers, step 2 disables, both inside ONE TRY block with XACT_ABORT on. Most DDL
errors end the batch by themselves; the TRY/CATCH stops it on any other error (a severity-16 RAISERROR, for one), so no index is
disabled after a failed widen (XACT_ABORT alone does not stop a severity-16 error and TRY/CATCH alone does; XACT_ABORT stays
in the script). The TRY block is written only when at
least one statement line is not commented out, because T-SQL needs a statement inside it. Step 3, the drops, is
commented out. A low-confidence row's DISABLE and DROP are commented out too. No line holds CR, LF or TAB*/
IF @Mode COLLATE Latin1_General_100_CI_AS = N'audit'
BEGIN
	DECLARE @n1 INT, @n2 INT, @nlow INT, @run INT, @wrap BIT;
	SELECT @n1 = COUNT(CASE WHEN step = 1 AND stmt IS NOT NULL THEN 1 END)
		, @n2 = COUNT(CASE WHEN verdict IN (N'UNUSED', N'EXACT DUPLICATE', N'SUPERSEDED', N'MERGE') THEN 1 END)
		, @nlow = COUNT(CASE WHEN verdict IN (N'UNUSED', N'EXACT DUPLICATE', N'SUPERSEDED', N'MERGE') AND confidence = N'low' THEN 1 END)
		, @run = COUNT(CASE WHEN stmt IS NOT NULL AND skip_why IS NULL AND (step = 1 OR ISNULL(confidence, N'') <> N'low') THEN 1 END)
	FROM #ix;
	SET @wrap = CASE WHEN @run > 0 THEN 1 ELSE 0 END;
	/*The script's progress lines (P2): written only in a wrapped script and only when @Progress = 1 (NULL = 0). Before each
	statement that runs: SET @ic_s, then RAISERROR 'step s, n of N: widen|disable schema.table.index'; n runs 1..N (= @run) over
	the running statements in script order. The name is a %s argument, so only ' is doubled; a name with CR, LF or TAB is SKIPPED
	above and so has no line. The DECLARE is outside the TRY: a variable is batch-scoped. This numbering and the three result set 3
	INSERTs below order by schema_name, table_name, object_id, index_id: object_id breaks the tie between tables whose names differ
	only by case (a case-sensitive database; #ix compares in tempdb's collation), so each statement keeps its own lines*/
	DECLARE @prog BIT = CASE WHEN @wrap = 1 AND ISNULL(@Progress, 0) = 1 THEN 1 ELSE 0 END
		, @icset NVARCHAR(100) = N'SET @ic_s = DATEDIFF(SECOND, @ic_t0, SYSDATETIME());';
	UPDATE x SET prog_line = N'RAISERROR(N''step %d, %d of %d: %s %s, elapsed %d s'', 0, 1, ' + CASE WHEN x.step = 1 THEN N'1' ELSE N'2' END
		+ N', ' + CONVERT(NVARCHAR(10), r.n) + N', ' + CONVERT(NVARCHAR(10), @run) + N', N''' + CASE WHEN x.step = 1 THEN N'widen' ELSE N'disable' END
		+ N''', N''' + REPLACE(x.schema_name + N'.' + x.table_name + N'.' + x.index_name, N'''', N'''''') + N''', @ic_s) WITH NOWAIT;'
	FROM #ix x
	JOIN (SELECT object_id, index_id, ROW_NUMBER() OVER (ORDER BY CASE WHEN step = 1 THEN 1 ELSE 2 END, schema_name, table_name, object_id, index_id) AS n
		FROM #ix WHERE stmt IS NOT NULL AND skip_why IS NULL AND (step = 1 OR ISNULL(confidence, N'') <> N'low')) r
		ON r.object_id = x.object_id AND r.index_id = x.index_id
	WHERE @prog = 1;
	INSERT #rs3 (line) SELECT REPLACE(REPLACE(REPLACE(N'-- Index consolidation remediation for ' + QUOTENAME(@db) + N' on ' + ISNULL(@@SERVERNAME, CONVERT(NVARCHAR(128), SERVERPROPERTY('ServerName')))
		+ N', generated ' + CONVERT(NVARCHAR(16), GETDATE(), 120) + N' server local time by index-consolidation.sql v' + @version + N'.'
		, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' ');
	INSERT #rs3 (line) VALUES (N'-- Read every statement first. Run in this order. Step 1 widens keepers; step 2 disables; the DROP section is commented out.');
	IF @db LIKE N'%[' + NCHAR(13) + NCHAR(10) + NCHAR(9) + N']%'
		INSERT #rs3 (line) VALUES (N'-- SKIPPED: the database name holds a line break or tab; script it by hand.');
	ELSE
	BEGIN
		INSERT #rs3 (line) VALUES (N'USE ' + QUOTENAME(@db) + N';');
		INSERT #rs3 (line) VALUES (RTRIM(@setline));
		IF @n1 + @n2 = 0
			INSERT #rs3 (line) VALUES (N'-- Nothing to change.');
		ELSE
		BEGIN
			IF @wrap = 1
			BEGIN
				IF @prog = 1 INSERT #rs3 (line) VALUES (N'DECLARE @ic_t0 DATETIME2(7) = SYSDATETIME(), @ic_s INT;');
				INSERT #rs3 (line) VALUES (N'-- Most DDL errors end the batch by themselves; the TRY/CATCH below stops it on any other error, so no index is disabled after a failed widen.');
				INSERT #rs3 (line) VALUES (N'SET XACT_ABORT ON;');
				INSERT #rs3 (line) VALUES (N'BEGIN TRY');
			END
			IF @n1 = 0 AND @nlow = @n2
				INSERT #rs3 (line) VALUES (N'-- Nothing runs: every change below is LOW CONFIDENCE and commented out.');
			IF @n1 > 0
			BEGIN
				INSERT #rs3 (line) VALUES (N'-- Step 1: widen keepers');
				INSERT #rs3 (line)
				SELECT v.line
				FROM #ix x
				CROSS APPLY (VALUES (1, REPLACE(REPLACE(REPLACE(N'-- ' + x.schema_name + N'.' + x.table_name + N'.' + x.index_name + N': ' + ISNULL(x.reason, N'')
						, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' '))
					, (2, CASE WHEN @prog = 1 AND x.prog_line IS NOT NULL THEN @icset END)
					, (3, CASE WHEN @prog = 1 THEN x.prog_line END)
					, (4, CASE WHEN x.skip_why IS NOT NULL
						THEN REPLACE(REPLACE(REPLACE(N'-- SKIPPED ' + x.schema_name + N'.' + x.table_name + N'.' + x.index_name + N' (flattened): '
							+ x.skip_why + N'; script it by hand', NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' ')
						ELSE x.stmt END)) v(sub, line)
				WHERE x.step = 1 AND x.stmt IS NOT NULL AND v.line IS NOT NULL
				ORDER BY x.schema_name, x.table_name, x.object_id, x.index_id, v.sub;
			END
			IF @n2 > 0
			BEGIN
				INSERT #rs3 (line) VALUES (N'-- Step 2: disable (undo: ALTER INDEX ... REBUILD WITH the index''s own options; a bare REBUILD loses its data compression; @Mode = ''changecontrol'' prints each rollback)');
				INSERT #rs3 (line)
				SELECT v.line
				FROM #ix x
				LEFT JOIN #ix t ON t.object_id = x.object_id AND t.index_id = x.target_id
				CROSS APPLY (VALUES (1, REPLACE(REPLACE(REPLACE(N'-- ' + x.verdict + ISNULL(N' of ' + t.index_name, N'') + ISNULL(N', confidence ' + x.confidence, N'')
						+ N': ' + x.schema_name + N'.' + x.table_name + N'.' + x.index_name, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' '))
					, (2, CASE WHEN @prog = 1 AND x.prog_line IS NOT NULL THEN @icset END)
					, (3, CASE WHEN @prog = 1 THEN x.prog_line END)
					, (4, CASE WHEN x.skip_why IS NOT NULL
						THEN REPLACE(REPLACE(REPLACE(N'-- SKIPPED ' + x.schema_name + N'.' + x.table_name + N'.' + x.index_name + N' (flattened): '
							+ x.skip_why + N'; script it by hand', NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' ')
						WHEN x.confidence = N'low' THEN N'-- LOW CONFIDENCE: ' + x.stmt
						ELSE x.stmt END)) v(sub, line)
				WHERE x.verdict IN (N'UNUSED', N'EXACT DUPLICATE', N'SUPERSEDED', N'MERGE') AND v.line IS NOT NULL
				ORDER BY x.schema_name, x.table_name, x.object_id, x.index_id, v.sub;
			END
			IF @wrap = 1
			BEGIN
				IF @prog = 1
				BEGIN
					INSERT #rs3 (line) VALUES (@icset);
					INSERT #rs3 (line) VALUES (N'RAISERROR(N''remediation done in %d s'', 0, 1, @ic_s) WITH NOWAIT;');
				END
				INSERT #rs3 (line) VALUES (N'END TRY');
				INSERT #rs3 (line) VALUES (N'BEGIN CATCH');
				INSERT #rs3 (line) VALUES (N'THROW;');
				INSERT #rs3 (line) VALUES (N'END CATCH;');
			END
			IF @n2 > 0
			BEGIN
				INSERT #rs3 (line) VALUES (N'-- Step 3: after a soak period, drop (uncomment to run)');
				INSERT #rs3 (line)
				SELECT CASE WHEN x.skip_why IS NOT NULL
						THEN REPLACE(REPLACE(REPLACE(N'-- SKIPPED ' + x.schema_name + N'.' + x.table_name + N'.' + x.index_name + N' (flattened): '
							+ x.skip_why + N'; script it by hand', NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' ')
					WHEN x.confidence = N'low' THEN N'-- -- LOW CONFIDENCE: ' + x.drop_stmt
					ELSE N'-- ' + x.drop_stmt END
				FROM #ix x
				WHERE x.verdict IN (N'UNUSED', N'EXACT DUPLICATE', N'SUPERSEDED', N'MERGE')
				ORDER BY x.schema_name, x.table_name, x.object_id, x.index_id;
			END
		END
	END
	
END

/*Result set 2 (modes all and audit): one row per index; audit shows only the rows with a script and the rows a safety check
blocked. Text columns are one line (CR, LF and TAB become a space; | in a reason becomes /)*/
IF @Mode COLLATE Latin1_General_100_CI_AS IN (N'all', N'audit')
SELECT
	x.step
	, x.schema_name
	, x.table_name
	, x.index_name
	, x.index_id
	, x.type_desc
	, x.kstr AS key_columns
	, x.istr AS include_columns
	, REPLACE(REPLACE(REPLACE(x.filter, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' ') AS filter
	, x.is_unique
	, REPLACE(REPLACE(REPLACE(REPLACE(x.protected_by, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' '), N'|', N'/') AS protected_by
	, x.reads
	, x.writes
	, x.size_mb
	, x.verdict
	, t.index_name AS target_index
	, x.confidence
	, REPLACE(REPLACE(REPLACE(REPLACE(x.reason, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' '), N'|', N'/') AS reason
	, REPLACE(REPLACE(REPLACE(x.script, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' ') AS script
	, REPLACE(REPLACE(REPLACE(x.drop_script, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' ') AS drop_script
FROM #ix x
LEFT JOIN #ix t ON t.object_id = x.object_id AND t.index_id = x.target_id
WHERE @Mode COLLATE Latin1_General_100_CI_AS = N'all' OR x.script IS NOT NULL
	OR (x.verdict = N'NOT JUDGED' AND x.reason LIKE N'safety check not run%')
ORDER BY x.step, x.schema_name, x.table_name, x.index_id;

/*Result set 3 (mode audit): line_no, line*/
IF @Mode COLLATE Latin1_General_100_CI_AS = N'audit'
SELECT ROW_NUMBER() OVER (ORDER BY seq) AS line_no, line
FROM #rs3
ORDER BY seq;

/*Mode changecontrol, result set 2: one row per CHANGE, then one row per index with no change. A change is a step-1
widen (WIDEN INCLUDES) or a step-2 disable (DISABLE); its change_id runs CC-001.. in run order (step 1, then step 2, each by
schema, table, index_id). Each change has its implement script, its rollback, and for a disable the later drop and the drop's
rollback; run the rollbacks in REVERSE change_id order. risk: high when confidence
is low or the index is over @risk_high_mb; medium for a DISABLE, or a WIDEN over @risk_med_mb; else low; empty on a NONE row.
script_sha256 is the SHA-256 of implement_script as printed (UTF-16LE), so an approval names the exact text; empty
on 2012/2014 for a script over 8,000 bytes (HASHBYTES' limit there). Text columns are one line, like result set 2*/
IF @Mode COLLATE Latin1_General_100_CI_AS = N'changecontrol'
BEGIN

SELECT
	CASE WHEN c.act <> N'NONE' THEN N'CC-' + CASE WHEN c.n < 1000 THEN RIGHT(N'00' + CONVERT(NVARCHAR(10), c.n), 3) ELSE CONVERT(NVARCHAR(10), c.n) END END AS change_id
	, c.step
	, c.schema_name
	, c.table_name
	, c.index_name
	, c.act AS action
	, c.verdict
	, t.index_name AS target_index
	, c.confidence
	, REPLACE(REPLACE(REPLACE(REPLACE(c.reason, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' '), N'|', N'/') AS reason
	, c.size_mb
	, c.reads
	, c.writes
	, CASE WHEN c.act = N'NONE' THEN N''
		WHEN c.confidence = N'low' OR c.size_mb > @risk_high_mb THEN N'high'
		WHEN c.act = N'DISABLE' OR (c.act = N'WIDEN INCLUDES' AND c.size_mb > @risk_med_mb) THEN N'medium'
		ELSE N'low' END AS risk
	, p.impl AS implement_script
	, REPLACE(REPLACE(REPLACE(c.rb_script, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' ') AS rollback_script
	, REPLACE(REPLACE(REPLACE(c.drop_script, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' ') AS drop_script
	, REPLACE(REPLACE(REPLACE(c.drop_rb_script, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' ') AS drop_rollback_script
	, N'' AS approved
	, N'' AS approver
	, N'' AS approved_date
	, CASE WHEN @major >= 13 OR DATALENGTH(p.impl) <= 8000 THEN CONVERT(CHAR(64), HASHBYTES('SHA2_256', p.impl), 2) ELSE '' END AS script_sha256
FROM
	(
	SELECT x.*, a.act
		, ROW_NUMBER() OVER (ORDER BY CASE a.act WHEN N'WIDEN INCLUDES' THEN 1 WHEN N'DISABLE' THEN 2 ELSE 3 END
			, CASE WHEN a.act = N'NONE' THEN x.step END, x.schema_name, x.table_name, x.index_id) AS n
	FROM #ix x
	CROSS APPLY (SELECT CASE WHEN x.step = 1 AND x.stmt IS NOT NULL THEN N'WIDEN INCLUDES'
			WHEN x.verdict IN (N'UNUSED', N'EXACT DUPLICATE', N'SUPERSEDED', N'MERGE') THEN N'DISABLE'
			ELSE N'NONE' END AS act) a
	) c
LEFT JOIN #ix t ON t.object_id = c.object_id AND t.index_id = c.target_id
CROSS APPLY (SELECT REPLACE(REPLACE(REPLACE(c.script, NCHAR(13), N' '), NCHAR(10), N' '), NCHAR(9), N' ') AS impl) p
ORDER BY c.n;
END
