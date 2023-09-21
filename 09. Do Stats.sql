/*-*-*-*-*-*-*-*-* PRINT NCHAR(65021)   *-*-*-*-*-*-*-*-*-*-*-*/
/* ------------------------------------------------------------------
-- Title				: Stats and Heap Update
-- Author				: Adrian Sullivan
-- whah?				: adrian@sqldba.org
-- Date					: 2013-10-14
-- Last Modified Date	: 2022-08-21 /*DETAILED to SAMPLED.. who knew right*/
-- Modified By			: Adrian Sullivan adrian@sqldba.org
------------------------------------------------------------------ */
BEGIN

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @MinChangePercentage MONEY, @DoStatistics MONEY
SET @MinChangePercentage = 0.2
SET @DoStatistics = 6 /*The number of hours to consider when looking at old stats, 6 = 6 hours*/
/*Parameter DECLARES.. like eclairs, but not so sweet and chewy and with a D*/
DECLARE @Database VARCHAR(255), @RecoveryModel INT, @TableName VARCHAR(255), @SchemaName VARCHAR(25), @IndexName VARCHAR(255), @StatsName VARCHAR(255), @CurrentFillFactor INT, @CurrentFragmentation DECIMAL(10,3), @ClusterType VARCHAR(15);
DECLARE @Databasei_Count INT, @Databasei_Max INT, @RebuildLoopi_Count INT, @RebuildLoopi_Max INT
DECLARE @Phase0_SQL NVARCHAR(4000),@NoLogReadsPlease INT, @Phase3_SQL NVARCHAR(4000), @Phase6_SQL NVARCHAR(4000), @Errortext NVARCHAR(4000);
DECLARE @HeapSQL NVARCHAR(4000)
		
									
DECLARE @Databases TABLE
	(
	id INT IDENTITY(1,1)
	, databasename VARCHAR(250)
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
	, DBname VARCHAR(100)
	, TableName VARCHAR(100)
	, StatsID INT
	, StatisticsName VARCHAR(500)
	, SchemaName VARCHAR(100)
	, ModificationCount BIGINT
	, Rows BIGINT
	, ModificationPercentage MONEY
	, LastUpdated DATETIME
);
/*Now populate some of the @temp*/
SET @Phase0_SQL = 'SELECT 
db.name
, db.compatibility_level
, db.user_access
, db.user_access_desc
, db.state
, db.state_desc
, db.recovery_model
, db.recovery_model_desc
FROM 
sys.databases db '

IF (SELECT OBJECT_ID('master.sys.availability_groups')) IS NOT NULL /*You have active AGs*/
SET @Phase0_SQL = @Phase0_SQL + '
LEFT OUTER JOIN(
SELECT top 100 percent
AG.name AS [AvailabilityGroupName],
ISNULL(agstates.primary_replica, NULL) AS [PrimaryReplicaServerName],
ISNULL(arstates.role, 3) AS [LocalReplicaRole],
dbcs.database_name AS [DatabaseName],
ISNULL(dbrs.synchronization_state, 0) AS [SynchronizationState],
ISNULL(dbrs.is_suspended, 0) AS [IsSuspended],
ISNULL(dbcs.is_database_joined, 0) AS [IsJoined]

FROM master.sys.availability_groups AS AG
LEFT OUTER JOIN master.sys.dm_hadr_availability_group_states as agstates
   ON AG.group_id = agstates.group_id
INNER JOIN master.sys.availability_replicas AS AR
   ON AG.group_id = AR.group_id
INNER JOIN master.sys.dm_hadr_availability_replica_states AS arstates
   ON AR.replica_id = arstates.replica_id AND arstates.is_local = 1
INNER JOIN master.sys.dm_hadr_database_replica_cluster_states AS dbcs
   ON arstates.replica_id = dbcs.replica_id
LEFT OUTER JOIN master.sys.dm_hadr_database_replica_states AS dbrs
   ON dbcs.replica_id = dbrs.replica_id AND dbcs.group_database_id = dbrs.group_database_id
WHERE agstates.primary_replica = @@SERVERNAME OR agstates.primary_replica IS NULL
ORDER BY AG.name ASC, dbcs.database_name
) t1 on t1.DatabaseName = db.name'

SET @Phase0_SQL = @Phase0_SQL + '
WHERE db.name NOT IN (''master'',''msdb'',''tempdb'',''model'') /*List of excluded Databases*/
AND db.state <> 6 AND db.user_access <> 1 OPTION (RECOMPILE);'

INSERT INTO @Databases 
EXEC sp_executesql @Phase0_SQL;

SET @Databasei_Max = (SELECT MAX(id) FROM @Databases ); /*We need to determine how many times we need to loop*/
SET @Databasei_Count = 1; /*I learned in school to count from 1, my script, my logic.. mkay*/
WHILE @Databasei_Count <= @Databasei_Max /*We will loop until we find the maximum ID*/
BEGIN  
		SET @Database = (SELECT databasename FROM @Databases WHERE id = @Databasei_Count) ;/*Select the first database in our list*/
		SET @RecoveryModel = (SELECT recovery_model FROM @Databases WHERE id = @Databasei_Count) ;

		/*  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3  3 */
		/*Shows Statistics.. more modification counts mean more need to refresh the stats.. wouldn't you say*/
		/*Thanks to John Huang http://www.sqlnotes.info/2012/03/14/modification-count-of-stats/#more-1864 */

		SET @Phase3_SQL = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
		USE ['+@Database+'];
		SELECT 
			'''+@Database+''' [DbName]
			, ObjectNm
			, StatsID
			, StatsName
			, SchemaName
			, ModificationCount
			, Rows
			, CASE WHEN Rows = 0 THEN 0 ELSE CONVERT(MONEY,ModificationCount*100/Rows)END ModificationPercentage
			, [LastUpdated] 
		FROM (
				SELECT 
					OBJECT_NAME(p.object_id) ObjectNm
						, p.index_id StatsID
						, s.name StatsName
						, MAX(p.rows) Rows
						, sce.name SchemaName' +
						CASE WHEN OBJECT_ID(N'sys.dm_db_stats_properties') IS NOT NULL 
				THEN ', sum(ddsp.modification_counter) ' 
				ELSE ', sum(pc.modified_count) ' END
						+' ModificationCount
						, MAX(
								STATS_DATE(s.object_id, s.stats_id)
							 ) AS [LastUpdated]
				FROM sys.system_internals_partition_columns pc
				INNER JOIN sys.partitions p ON pc.partition_id = p.partition_id
				INNER JOIN sys.stats s ON s.object_id = p.object_id AND s.stats_id = p.index_id
				INNER JOIN sys.stats_columns sc ON sc.object_id = s.object_id AND sc.stats_id = s.stats_id AND sc.stats_column_id = pc.partition_column_id
				INNER JOIN sys.tables t ON t.object_id = s.object_id
				INNER JOIN sys.schemas sce ON sce.schema_id = t.schema_id' + 
				CASE WHEN OBJECT_ID(N'sys.dm_db_stats_properties') IS NOT NULL 
				THEN ' OUTER APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) ddsp WHERE ddsp.modification_counter > 0 GROUP BY p.object_id, p.index_id, s.name,sce.name' 
				ELSE ' GROUP BY p.object_id, p.index_id, s.name,sce.name HAVING sum(pc.modified_count)> 0 ' END
				+'
			) stats
			WHERE ObjectNm NOT LIKE ''sys%'' AND ModificationCount != 0
			AND ObjectNm NOT LIKE ''ifts_comp_fragment%''
			AND ObjectNm NOT LIKE ''fulltext_%''
			AND ObjectNm NOT LIKE ''filestream_%''
			AND ObjectNm NOT LIKE ''queue_messages_%''
			AND Rows > 500
			AND  CASE WHEN Rows = 0 THEN 0 ELSE CONVERT(MONEY,ModificationCount)*100/Rows END >= '+CONVERT(VARCHAR(20),@MinChangePercentage)+ '
			AND LastUpdated < DATEADD(DAY, - 1, GETDATE())
			ORDER BY ObjectNm, StatsName OPTION (RECOMPILE);
		';
		
		SET @HeapSQL = 'USE ['+@Database+'];
		SELECT ''['' + DB_NAME(DB_ID()) + ''].['' + OBJECT_SCHEMA_NAME(IDXPS.object_id) +''].['' +OBJECT_NAME(IDXPS.object_id) + '']'' AS table_name
			, IDXPS.forwarded_record_count
			, IDXPS.avg_fragmentation_in_percent Fragmentation_Percentage
			, IDXPS.page_count

/*, forwarded_record_count, record_count, page_count*/

FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''SAMPLED'') IDXPS 
INNER JOIN sys.indexes IDX  ON IDX.object_id = IDXPS.object_id 
AND IDX.index_id = IDXPS.index_id 
AND  IDX.type = 0 
AND  forwarded_record_count > 0
ORDER BY Fragmentation_Percentage DESC
			'
	

		
	BEGIN TRY
	PRINT @Database
		INSERT INTO @Action_Statistics
		EXEC sp_executesql @Phase3_SQL;
		/*UPDATE STATISTICS dbo.tblPDAForward PK_tblPDAForward*/
		RAISERROR (N'Getting some Statstics statistics..' ,0,1) WITH NOWAIT;
		
		
		INSERT @LovemyHeaps
		EXEC sp_executesql @HeapSQL;
		RAISERROR (N'Getting some Heaps info..' ,0,1) WITH NOWAIT;
		
	END TRY
	BEGIN CATCH 
		PRINT @HeapSQL;
		SELECT @Database DBName,@Phase3_SQL Query,ERROR_LINE() AS Line, ERROR_NUMBER() AS Error, ERROR_SEVERITY() AS Severity, ERROR_STATE() AS ErrorState, ERROR_MESSAGE() AS Message;
	END CATCH
	SET @Databasei_Count = (@Databasei_Count + 1)
 
END

/*Statistics rebuild loop will start from here*/
	PRINT 'Starting to make them Statistics purdy..';
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

		SET @Phase6_SQL = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
			USE ['+@Database+'];
			UPDATE STATISTICS ['+@SchemaName+'].['+@TableName+'] ['+@StatsName+'] WITH FULLSCAN'
		BEGIN TRY
			SET @Errortext = 'Doing Statistics:  '+CONVERT(VARCHAR(10),@RebuildLoopi_Count)+ ' of ' + CONVERT(VARCHAR(10),@RebuildLoopi_Max) +'.  ['+@StatsName+'] ON ['+@Database+'].['+@SchemaName+'].['+@TableName+']  ';
			RAISERROR(@Errortext, 0, 1) WITH NOWAIT;
			EXEC sp_executesql @Phase6_SQL;
		END TRY
		BEGIN CATCH 
			PRINT @Phase6_SQL;
			SELECT @Database DBName,@Phase6_SQL Query,ERROR_LINE() AS Line, ERROR_NUMBER() AS Error, ERROR_SEVERITY() AS Severity, ERROR_STATE() AS ErrorState, ERROR_MESSAGE() AS Message;
		END CATCH
		SET @RebuildLoopi_Count = @RebuildLoopi_Count + 1
	END;
	
END


SELECT * FROM @Action_Statistics

SELECT 'RAISERROR(N''Rebuilding ' + H.TableName + ''', 0, 1) WITH NOWAIT; ALTER TABLE ' + H.TableName + ' REBUILD'
FROM @LovemyHeaps H





