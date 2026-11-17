/*-*-*-*-*-*-*-*-* PRINT NCHAR(65021)   *-*-*-*-*-*-*-*-*-*-*-*/
/* ------------------------------------------------------------------
-- Title				: Stats and Heap Update
-- Author				: Adrian Sullivan
-- whah?				: adrian@sqldba.org
-- Date					: 2013-10-14
-- Last Modified Date	: 2026-11-18 /*Find the heaps first, THEN go look inside them. Not the other way round*/
-- Modified By			: Adrian Sullivan adrian@sqldba.org
------------------------------------------------------------------ */
BEGIN

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

/*The knobs. Twiddle these, leave the rest alone*/
DECLARE @MinChangePercentage MONEY, @DoStatistics MONEY
DECLARE @UpdateStats BIT, @CheckHeaps BIT, @IncludeColumnStats BIT, @HeapsOnlyIfFetched BIT
DECLARE @MinHeapPages BIGINT, @OnlyThisDatabase SYSNAME, @StatsScan NVARCHAR(60)
SET @MinChangePercentage = 0.2	/*Percent of rows changed before a statistic gets a refresh. 0.2 = 0.2 percent, not 20*/
SET @DoStatistics = 24			/*The number of hours to consider when looking at old stats, 24 = leave anything updated in the last 24 hours*/
SET @UpdateStats = 1			/*0 = just show me what you WOULD do, touch nothing*/
SET @CheckHeaps = 1				/*0 = skip the heap hunt*/
SET @IncludeColumnStats = 1		/*1 = also the _WA_Sys and hand made column statistics, 0 = only statistics that belong to an index*/
SET @HeapsOnlyIfFetched = 0		/*1 = only look inside heaps where something actually FOLLOWED a forwarded record since the last restart. Fast, but a heap nobody has read yet is skipped*/
SET @MinHeapPages = 0			/*Skip heaps smaller than this many pages*/
SET @OnlyThisDatabase = NULL	/*NULL = every user database, or name just the one*/
SET @StatsScan = N'FULLSCAN'	/*or SAMPLE 20 PERCENT, or RESAMPLE*/

/*Parameter DECLARES.. like eclairs, but not so sweet and chewy and with a D*/
DECLARE @Database SYSNAME, @TableName SYSNAME, @SchemaName SYSNAME, @StatsName SYSNAME;
DECLARE @Databasei_Count INT, @Databasei_Max INT, @RebuildLoopi_Count INT, @RebuildLoopi_Max INT
DECLARE @Phase0_SQL NVARCHAR(MAX), @Phase3_SQL NVARCHAR(MAX), @Phase6_SQL NVARCHAR(MAX), @Errortext NVARCHAR(2000);
DECLARE @HeapSQL NVARCHAR(MAX), @StatsBody NVARCHAR(MAX), @HeapBody NVARCHAR(MAX)
DECLARE @OlderThan DATETIME
SET @OlderThan = DATEADD(MINUTE, - CONVERT(INT, @DoStatistics * 60), GETDATE())

DECLARE @Databases TABLE
	(
	id INT IDENTITY(1,1)
	, databasename SYSNAME
	, [compatibility_level] BIGINT
	, user_access BIGINT
	, user_access_desc VARCHAR(50)
	, [state] BIGINT
	, state_desc  VARCHAR(50)
	, recovery_model BIGINT
	, recovery_model_desc  VARCHAR(50)
	);
DECLARE @LovemyHeaps TABLE
	(
		TableName NVARCHAR(500)
		, ForwardedCount BIGINT
		, AvgFrag MONEY
		, PageCount BIGINT
	)
DECLARE @Action_Statistics TABLE
	(
	Id INT IDENTITY(1,1)
	, DBname SYSNAME
	, TableName SYSNAME
	, StatsID INT
	, StatisticsName SYSNAME
	, SchemaName SYSNAME
	, ModificationCount BIGINT
	, Rows BIGINT
	, ModificationPercentage MONEY
	, LastUpdated DATETIME
);
/*Now populate some of the @temp*/
/*Only databases we can actually work in: online, multi user, writable, not a snapshot*/
SET @Phase0_SQL = N'SELECT
db.name
, db.compatibility_level
, db.user_access
, db.user_access_desc
, db.state
, db.state_desc
, db.recovery_model
, db.recovery_model_desc
FROM
sys.databases db
WHERE db.name NOT IN (''master'',''msdb'',''tempdb'',''model'') /*List of excluded Databases*/
AND db.state = 0 AND db.user_access <> 1
AND db.is_read_only = 0
AND db.source_database_id IS NULL
AND (@OnlyThisDatabase IS NULL OR db.name = @OnlyThisDatabase)'

IF (SELECT OBJECT_ID('master.sys.availability_groups')) IS NOT NULL /*You could have AGs. Only the primary copy can take new statistics*/
SET @Phase0_SQL = @Phase0_SQL + N'
AND NOT EXISTS (
	SELECT 1
	FROM master.sys.dm_hadr_database_replica_states AS dbrs
	INNER JOIN master.sys.dm_hadr_availability_replica_states AS arstates
		ON arstates.replica_id = dbrs.replica_id AND arstates.group_id = dbrs.group_id
	WHERE dbrs.database_id = db.database_id
	AND dbrs.is_local = 1 AND arstates.is_local = 1
	AND ISNULL(arstates.role, 3) <> 1 /*1 = PRIMARY*/
	)'

SET @Phase0_SQL = @Phase0_SQL + N'
ORDER BY db.name OPTION (RECOMPILE);'

INSERT INTO @Databases
EXEC sp_executesql @Phase0_SQL, N'@OnlyThisDatabase SYSNAME', @OnlyThisDatabase = @OnlyThisDatabase;

/*  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3 */
/*Shows Statistics.. more modification counts mean more need to refresh the stats.. wouldn't you say*/
/*One row per statistic, straight from sys.stats, so the column statistics are in here too*/
/*and the modification count is the real one, not multiplied by partitions and columns*/
IF OBJECT_ID(N'sys.dm_db_stats_properties') IS NOT NULL
	SET @StatsBody = N'
	SELECT
		DB_NAME() [DbName]
		, t.name ObjectNm
		, s.stats_id StatsID
		, s.name StatsName
		, sce.name SchemaName
		, ddsp.modification_counter ModificationCount
		, r.Rows
		, CONVERT(MONEY, CONVERT(MONEY,ddsp.modification_counter)*100/NULLIF(r.Rows,0)) ModificationPercentage
		, ddsp.last_updated [LastUpdated]
	FROM sys.stats s
	INNER JOIN sys.tables t ON t.object_id = s.object_id
	INNER JOIN sys.schemas sce ON sce.schema_id = t.schema_id
	CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) ddsp
	/*Rows = what the table holds NOW, all partitions. A table that grew from 10 rows to 10 million must not hide behind its old row count*/
	CROSS APPLY (SELECT SUM(p.rows) Rows FROM sys.partitions p WHERE p.object_id = s.object_id AND p.index_id IN (0,1)) cur
	CROSS APPLY (SELECT CASE WHEN s.has_filter = 1 THEN ddsp.rows ELSE cur.Rows END Rows) r
	WHERE t.is_ms_shipped = 0
	AND ddsp.modification_counter > 0
	AND r.Rows > 500
	AND CONVERT(MONEY,ddsp.modification_counter)*100/NULLIF(r.Rows,0) >= @MinChangePercentage
	AND ddsp.last_updated < @OlderThan
	AND (@IncludeColumnStats = 1 OR EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id = s.object_id AND i.index_id = s.stats_id))
	ORDER BY t.name, s.name OPTION (RECOMPILE);'
ELSE /*Old timer. No sys.dm_db_stats_properties before 2008 R2 SP2 and 2012 SP1, so ask sysindexes*/
	SET @StatsBody = N'
	SELECT
		DB_NAME() [DbName]
		, t.name ObjectNm
		, s.stats_id StatsID
		, s.name StatsName
		, sce.name SchemaName
		, si.rowmodctr ModificationCount
		, r.Rows
		, CONVERT(MONEY, CONVERT(MONEY,si.rowmodctr)*100/NULLIF(r.Rows,0)) ModificationPercentage
		, STATS_DATE(s.object_id, s.stats_id) [LastUpdated]
	FROM sys.stats s
	INNER JOIN sys.tables t ON t.object_id = s.object_id
	INNER JOIN sys.schemas sce ON sce.schema_id = t.schema_id
	INNER JOIN sys.sysindexes si ON si.id = s.object_id AND si.indid = s.stats_id
	CROSS APPLY (SELECT SUM(p.rows) Rows FROM sys.partitions p WHERE p.object_id = s.object_id AND p.index_id IN (0,1)) r
	WHERE t.is_ms_shipped = 0
	AND si.rowmodctr > 0
	AND r.Rows > 500
	AND CONVERT(MONEY,si.rowmodctr)*100/NULLIF(r.Rows,0) >= @MinChangePercentage
	AND STATS_DATE(s.object_id, s.stats_id) < @OlderThan
	AND (@IncludeColumnStats = 1 OR EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id = s.object_id AND i.index_id = s.stats_id))
	ORDER BY t.name, s.name OPTION (RECOMPILE);'

/*Heaps. The old way asked sys.dm_db_index_physical_stats to sample EVERY index in the database and then kept only the heaps.*/
/*Now: list the heaps from the catalog (free), then sample only those, one at a time.*/
/*A partitioned heap comes back as one row, so one REBUILD line, not one per partition*/
SET @HeapBody = N'
SET NOCOUNT ON;
DECLARE @obj INT, @n INT;
CREATE TABLE #Heaps (object_id INT PRIMARY KEY, SchemaName SYSNAME, TableName SYSNAME);
CREATE TABLE #HeapResult (object_id INT, forwarded_record_count BIGINT, avg_fragmentation_in_percent FLOAT, page_count BIGINT);

INSERT #Heaps (object_id, SchemaName, TableName)
SELECT t.object_id, sce.name, t.name
FROM sys.tables t
INNER JOIN sys.schemas sce ON sce.schema_id = t.schema_id
INNER JOIN sys.indexes IDX ON IDX.object_id = t.object_id AND IDX.type = 0
INNER JOIN (
	SELECT ps.object_id, SUM(ps.row_count) row_count, SUM(ps.in_row_data_page_count) page_count
	FROM sys.dm_db_partition_stats ps
	WHERE ps.index_id = 0
	GROUP BY ps.object_id
	) sz ON sz.object_id = t.object_id
WHERE t.is_ms_shipped = 0
AND sz.row_count > 0 /*no rows, no forwarded rows*/
AND sz.page_count >= @MinHeapPages
AND (@HeapsOnlyIfFetched = 0 OR EXISTS (
		SELECT 1 FROM sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) os
		WHERE os.object_id = t.object_id AND os.index_id = 0 AND os.forwarded_fetch_count > 0
	));

SET @n = @@ROWCOUNT;
RAISERROR (N''  ..%d heaps to look inside'' ,0,1, @n) WITH NOWAIT;

SELECT @obj = MIN(object_id) FROM #Heaps;
WHILE @obj IS NOT NULL
BEGIN
	INSERT #HeapResult
	SELECT @obj, IDXPS.forwarded_record_count, IDXPS.avg_fragmentation_in_percent, IDXPS.page_count
	FROM sys.dm_db_index_physical_stats(DB_ID(), @obj, 0, NULL, ''SAMPLED'') IDXPS
	WHERE IDXPS.alloc_unit_type_desc = ''IN_ROW_DATA''
	AND IDXPS.forwarded_record_count > 0;

	SELECT @obj = MIN(object_id) FROM #Heaps WHERE object_id > @obj;
END

SELECT QUOTENAME(DB_NAME()) + N''.'' + QUOTENAME(h.SchemaName) + N''.'' + QUOTENAME(h.TableName) AS table_name
	, SUM(r.forwarded_record_count)
	, MAX(r.avg_fragmentation_in_percent) Fragmentation_Percentage
	, SUM(r.page_count)
FROM #HeapResult r
INNER JOIN #Heaps h ON h.object_id = r.object_id
GROUP BY h.SchemaName, h.TableName;'

SET @Databasei_Max = (SELECT MAX(id) FROM @Databases ); /*We need to determine how many times we need to loop*/
SET @Databasei_Count = 1; /*I learned in school to count from 1, my script, my logic.. mkay*/
WHILE @Databasei_Count <= @Databasei_Max /*We will loop until we find the maximum ID*/
BEGIN
		SET @Database = (SELECT databasename FROM @Databases WHERE id = @Databasei_Count) ;/*Select the first database in our list*/

		SET @Phase3_SQL = N'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
		USE ' + QUOTENAME(@Database) + N';' + @StatsBody;

	RAISERROR (N'%s' ,0,1, @Database) WITH NOWAIT;
	BEGIN TRY
		RAISERROR (N' Getting some Statstics statistics..' ,0,1) WITH NOWAIT;
		INSERT INTO @Action_Statistics
		EXEC sp_executesql @Phase3_SQL
			, N'@MinChangePercentage MONEY, @OlderThan DATETIME, @IncludeColumnStats BIT'
			, @MinChangePercentage = @MinChangePercentage, @OlderThan = @OlderThan, @IncludeColumnStats = @IncludeColumnStats;
	END TRY
	BEGIN CATCH
		SELECT @Database DBName,@Phase3_SQL Query,ERROR_LINE() AS Line, ERROR_NUMBER() AS Error, ERROR_SEVERITY() AS Severity, ERROR_STATE() AS ErrorState, ERROR_MESSAGE() AS Message;
	END CATCH
	SET @Databasei_Count = (@Databasei_Count + 1)

END

/*Statistics rebuild loop will start from here*/
IF @UpdateStats = 1
BEGIN
	RAISERROR (N'Starting to make them Statistics purdy..' ,0,1) WITH NOWAIT;
	SET @RebuildLoopi_Max = (SELECT MAX(Id) FROM @Action_Statistics ); /*We need to determine how many times we need to loop*/
	SET @RebuildLoopi_Count = 1; /*I learned in school to count from 1, my script, my logic.. mkay*/
	WHILE @RebuildLoopi_Count <= @RebuildLoopi_Max /*We will loop until we find the maximum ID*/
	BEGIN
		SELECT
			@Database					= A1.DBname
			, @TableName				= A1.TableName
			, @StatsName				= A1.StatisticsName
			, @SchemaName				= A1.SchemaName
		FROM @Action_Statistics A1 WHERE A1.Id = @RebuildLoopi_Count ;

		SET @Phase6_SQL = N'USE ' + QUOTENAME(@Database) + N';
			UPDATE STATISTICS ' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName) + N' ' + QUOTENAME(@StatsName) + N' WITH ' + @StatsScan
		BEGIN TRY
			SET @Errortext = N'Doing Statistics:  '+CONVERT(NVARCHAR(10),@RebuildLoopi_Count)+ N' of ' + CONVERT(NVARCHAR(10),@RebuildLoopi_Max) + N'.  '+QUOTENAME(@StatsName)+N' ON '+QUOTENAME(@Database)+N'.'+QUOTENAME(@SchemaName)+N'.'+QUOTENAME(@TableName)+N'  ';
			RAISERROR(N'%s', 0, 1, @Errortext) WITH NOWAIT;
			EXEC sp_executesql @Phase6_SQL;
		END TRY
		BEGIN CATCH
			PRINT @Phase6_SQL;
			SELECT @Database DBName,@Phase6_SQL Query,ERROR_LINE() AS Line, ERROR_NUMBER() AS Error, ERROR_SEVERITY() AS Severity, ERROR_STATE() AS ErrorState, ERROR_MESSAGE() AS Message;
		END CATCH
		SET @RebuildLoopi_Count = @RebuildLoopi_Count + 1
	END;
END
ELSE
	RAISERROR (N'@UpdateStats = 0, so this is the list of what I would have done. Nothing was touched.' ,0,1) WITH NOWAIT;

SELECT * FROM @Action_Statistics ORDER BY Id

/*Heaps go LAST, on purpose. Looking inside a damaged table can kill the whole session (seen it: severity 22, on a corrupt test database)*/
/*By now the statistics are done and listed, so the worst a bad heap can cost you is the heap list*/
IF @CheckHeaps = 1
BEGIN
	SET @Databasei_Count = 1;
	WHILE @Databasei_Count <= @Databasei_Max
	BEGIN
		SET @Database = (SELECT databasename FROM @Databases WHERE id = @Databasei_Count) ;
		SET @HeapSQL = N'USE ' + QUOTENAME(@Database) + N';' + @HeapBody;
		BEGIN TRY
			RAISERROR (N'%s: Getting some Heaps info..' ,0,1, @Database) WITH NOWAIT;
			INSERT @LovemyHeaps
			EXEC sp_executesql @HeapSQL
				, N'@MinHeapPages BIGINT, @HeapsOnlyIfFetched BIT'
				, @MinHeapPages = @MinHeapPages, @HeapsOnlyIfFetched = @HeapsOnlyIfFetched;
		END TRY
		BEGIN CATCH
			SELECT @Database DBName,@HeapSQL Query,ERROR_LINE() AS Line, ERROR_NUMBER() AS Error, ERROR_SEVERITY() AS Severity, ERROR_STATE() AS ErrorState, ERROR_MESSAGE() AS Message;
		END CATCH
		SET @Databasei_Count = (@Databasei_Count + 1)
	END
END

END


/*Copy the first column into a new window. Mind: rebuilding a heap rebuilds every nonclustered index on it too*/
SELECT 'RAISERROR(N''Rebuilding ' + REPLACE(H.TableName,'''','''''') + ''', 0, 1) WITH NOWAIT; ALTER TABLE ' + H.TableName + ' REBUILD' AS RebuildCommand
	, H.TableName
	, H.ForwardedCount
	, H.PageCount
	, H.AvgFrag
FROM @LovemyHeaps H
ORDER BY H.ForwardedCount DESC, H.TableName
