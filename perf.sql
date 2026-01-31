
 SET ARITHABORT off


SELECT
	TMP.Category
	, DB_NAME(st.dbid) [DB]
	,TMP.[Total Elapsed Time in S]
,TMP.[Total Execution Count]
,TMP.[Total CPU Time in S]
,TMP.[Avg CPU Time in MS]
,TMP.[Total Logical Reads]
,TMP.[Avg Logical Reads]
,TMP.[Total Logical Writes]
,TMP.[Avg Logical Writes]
,TMP.[Total CLR Time]
,TMP.[Avg CLR Time in MS]
,TMP.[Min CPU Time in MS]
,TMP.[Max CPU Time in MS]
,TMP.[Min Logical Reads]
,TMP.[Max Logical Reads]
,TMP.[Min Logical Writes]
,TMP.[Max Logical Writes]
,TMP.[Min CLR Time in MS]
,TMP.[Max CLR Time in MS]
,TMP.[Number of Statements]
,TMP.[Last Execution Time]
,TMP.[Plan Handle]
,st.text AS [Query]
,qp.query_plan AS [Plan]
	
FROM
	(
SELECT * FROM (
SELECT TOP 10 'worst I/O' [Category],
		CAST(SUM(s.total_elapsed_time) / 1000000.0 AS DECIMAL(20, 2)) AS [Total Elapsed Time in S],
		SUM(s.execution_count) AS [Total Execution Count],
		CAST(SUM(s.total_worker_time) / 1000000.0 AS DECIMAL(20, 2)) AS [Total CPU Time in S],
		CAST(SUM(s.total_worker_time) / SUM(s.execution_count) / 1000.0 AS DECIMAL(20, 2)) AS [Avg CPU Time in MS],
		SUM(s.total_logical_reads) AS [Total Logical Reads],
		CAST(CAST(SUM(s.total_logical_reads) AS FLOAT) / CAST(SUM(s.execution_count) AS FLOAT) AS DECIMAL(20, 2)) AS [Avg Logical Reads],
		SUM(s.total_logical_writes) AS [Total Logical Writes],
		CAST(CAST(SUM(s.total_logical_writes) AS FLOAT) / CAST(SUM(s.execution_count) AS FLOAT) AS DECIMAL(20, 2)) AS [Avg Logical Writes],
		SUM(s.total_clr_time) AS [Total CLR Time],
		CAST(SUM(s.total_clr_time) / SUM(s.execution_count) / 1000.0 AS DECIMAL(20, 2)) AS [Avg CLR Time in MS],
		CAST(SUM(s.min_worker_time) / 1000.0 AS DECIMAL(20, 2)) AS [Min CPU Time in MS],
		CAST(SUM(s.max_worker_time) / 1000.0 AS DECIMAL(20, 2)) AS [Max CPU Time in MS],
		SUM(s.min_logical_reads) AS [Min Logical Reads],
		SUM(s.max_logical_reads) AS [Max Logical Reads],
		SUM(s.min_logical_writes) AS [Min Logical Writes],
		SUM(s.max_logical_writes) AS [Max Logical Writes],
		CAST(SUM(s.min_clr_time) / 1000.0 AS DECIMAL(20, 2)) AS [Min CLR Time in MS],
		CAST(SUM(s.max_clr_time) / 1000.0 AS DECIMAL(20, 2)) AS [Max CLR Time in MS],
		COUNT(1) AS [Number of Statements],
		MAX(s.last_execution_time) AS [Last Execution Time],
		s.plan_handle AS [Plan Handle]
	FROM
		sys.dm_exec_query_stats s
		--where execution_count>0
	-- Most CPU consuming
	--GROUP BY s.plan_handle ORDER BY SUM(s.total_worker_time) DESC
		
	-- Most read+write IO consuming
	GROUP BY s.plan_handle ORDER BY SUM(s.total_logical_reads + s.total_logical_writes) DESC
	)TT	
	-- Most write IO consuming
	--GROUP BY s.plan_handle ORDER BY SUM(s.total_logical_writes) DESC
		
	-- Most CLR consuming
	--WHERE s.total_clr_time > 0 GROUP BY s.plan_handle ORDER BY SUM(s.total_clr_time) DESC
UNION ALL
 SELECT * FROM (
	SELECT TOP 10 'worst CPU' [Category],
		CAST(SUM(s.total_elapsed_time) / 1000000.0 AS DECIMAL(20, 2)) AS [Total Elapsed Time in S],
		SUM(s.execution_count) AS [Total Execution Count],
		CAST(SUM(s.total_worker_time) / 1000000.0 AS DECIMAL(20, 2)) AS [Total CPU Time in S],
		CAST(SUM(s.total_worker_time) / SUM(s.execution_count) / 1000.0 AS DECIMAL(20, 2)) AS [Avg CPU Time in MS],
		SUM(s.total_logical_reads) AS [Total Logical Reads],
		CAST(CAST(SUM(s.total_logical_reads) AS FLOAT) / CAST(SUM(s.execution_count) AS FLOAT) AS DECIMAL(20, 2)) AS [Avg Logical Reads],
		SUM(s.total_logical_writes) AS [Total Logical Writes],
		CAST(CAST(SUM(s.total_logical_writes) AS FLOAT) / CAST(SUM(s.execution_count) AS FLOAT) AS DECIMAL(20, 2)) AS [Avg Logical Writes],
		SUM(s.total_clr_time) AS [Total CLR Time],
		CAST(SUM(s.total_clr_time) / SUM(s.execution_count) / 1000.0 AS DECIMAL(20, 2)) AS [Avg CLR Time in MS],
		CAST(SUM(s.min_worker_time) / 1000.0 AS DECIMAL(20, 2)) AS [Min CPU Time in MS],
		CAST(SUM(s.max_worker_time) / 1000.0 AS DECIMAL(20, 2)) AS [Max CPU Time in MS],
		SUM(s.min_logical_reads) AS [Min Logical Reads],
		SUM(s.max_logical_reads) AS [Max Logical Reads],
		SUM(s.min_logical_writes) AS [Min Logical Writes],
		SUM(s.max_logical_writes) AS [Max Logical Writes],
		CAST(SUM(s.min_clr_time) / 1000.0 AS DECIMAL(20, 2)) AS [Min CLR Time in MS],
		CAST(SUM(s.max_clr_time) / 1000.0 AS DECIMAL(20, 2)) AS [Max CLR Time in MS],
		COUNT(1) AS [Number of Statements],
		MAX(s.last_execution_time) AS [Last Execution Time],
		s.plan_handle AS [Plan Handle]
	FROM
		sys.dm_exec_query_stats s
		
	-- Most CPU consuming
	GROUP BY s.plan_handle ORDER BY SUM(s.total_worker_time) DESC
	) T	
	-- Most read+write IO consuming
	--GROUP BY s.plan_handle ORDER BY SUM(s.total_logical_reads + s.total_logical_writes) DESC
		
	-- Most write IO consuming
	--GROUP BY s.plan_handle ORDER BY SUM(s.total_logical_writes) DESC
		
	-- Most CLR consuming
	--WHERE s.total_clr_time > 0 GROUP BY s.plan_handle ORDER BY SUM(s.total_clr_time) DESC
	)
	TMP
OUTER APPLY
	sys.dm_exec_query_plan(TMP.[Plan Handle]) AS qp
OUTER APPLY
	sys.dm_exec_sql_text(TMP.[Plan Handle]) AS st
ORDER BY Category, [Total Logical Reads] DESC
	--blocked tasks

	select 'current blocks'
	select t1.resource_type							as lock_type
	,db_name(resource_database_id)				as database_id
	,t1.resource_associated_entity_id			as blk_object
	,t1.request_mode							as lock_req	 -- lock requested
	,t1.request_session_id						as wait_sid  -- spid of waiter
	,t2.wait_duration_ms						as wait_time
	,t2.wait_type								as wait_type		
	,(select text from sys.dm_exec_requests	r  --- get sql for waiter
		cross apply sys.dm_exec_sql_text(r.sql_handle) 
		where r.session_id = t1.request_session_id) as wait_batch
	,(select substring(qt.text,r.statement_start_offset/2, 
			(case when r.statement_end_offset = -1 
			then len(convert(nvarchar(max), qt.text)) * 2 
			else r.statement_end_offset end - r.statement_start_offset)/2) 
		from sys.dm_exec_requests r
		cross apply sys.dm_exec_sql_text(r.sql_handle) qt
		where r.session_id = t1.request_session_id) as wait_stmt    --- this is the statement executing right now
	,(select text from sys.sysprocesses p		--- get sql for blocker
		cross apply sys.dm_exec_sql_text(p.sql_handle) 
		where p.spid = t2.blocking_session_id) as block_stmt
	,t2.blocking_session_id as blocker_sid -- spid of blocker
from 
	sys.dm_tran_locks t1, 
	sys.dm_os_waiting_tasks t2
where 
	t1.lock_owner_address = t2.resource_address



	
declare @blockinghistory table (databasename varchar(200),ObjectName varchar(200),LocksCount bigint,BlocksCount bigint,blocksWaitTimeMs bigint,index_id bigint)


DECLARE @command varchar(1000) 
SELECT @command = 'use [?] select db_name(database_id) as databasename
,object_name(object_id) as ObjectName
,row_lock_count + page_lock_count as LocksCount
,row_lock_wait_count + page_lock_wait_count as BlocksCount
,row_lock_wait_in_ms + page_lock_wait_in_ms as BlocksWaitTimeMs	
,index_id
from sys.dm_db_index_operational_stats(NULL,NULL,NULL,NULL)
where db_name(database_id) = DB_NAME()
--order by BlocksWaitTime desc' 

insert into @blockinghistory
EXEC sp_MSforeachdb @command 

if exists(select 1 from @blockinghistory where BlocksCount>10) 
begin
	select 'Blocking History'

	select * from @blockinghistory where BlocksCount>10
end