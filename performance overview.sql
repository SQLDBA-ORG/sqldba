USE [master]
GO

/****** Object:  Table [dbo].[snapmemory]    Script Date: 4/11/2020 10:24:21 AM ******/
SET ANSI_NULLS ON
GO

/*1 min healthcheck
Created:5-Nov-2020
Author:Rob Wylie   
Code from everywhere including blitzfirst...

Performs the following checks

	Buffer Cache Hit Ratio
	Current Memory<Target Memory
	Excessive Free memory in Buffer Cache
	Checks for Single Use Plans reported in stats
	Checks for CPU where SQL is over 50% or other processes over 20%
	Lists top 10 queries in cache by I/O
	Lists top 10 queries in cache by CPU
	Looks for currently blocking queries
	Blocking History since the last restart
	Looks for waits due to Database_restores,datafilegrowth,logfilegrowth
	CHecks for currently running disk intensive tasks such as DBCC/Backups/Index tasks currently running
	Looks for recent database Growth Events
	Looks for current running queries in a WT min period  
	Checks O/S Memory Pressure

	Add Index Snapshot in a wt period
	---add index snapshot/io snapshot....


		--16-Nov 20-2020   added N'VDI_CLIENT_OTHER' exclusion from wait tasks
		--19-Nov-2020   added filename,ChangeinSize and DurationMS to Growthevents
		--19-Nov 2020  added CF.FileID,SAF.filename  to Stall information
*/

SET QUOTED_IDENTIFIER ON
GO
declare @linefeed char(2)

set @linefeed=char(10)+char(13)

declare @showall int
set @showall=0    --0 is only show pain points,   1- show everything


DECLARE @SNAPSHOTDELAY VARCHAR(12)
SET @SNAPSHOTDELAY='00:01:00';


		IF OBJECT_ID ('tempdb..#checkversion') IS NOT NULL
		DROP TABLE #checkversion;
	CREATE TABLE #checkversion (
		version NVARCHAR(128),
		common_version AS SUBSTRING(version, 1, CHARINDEX('.', version) + 1 ),
		major AS PARSENAME(CONVERT(VARCHAR(32), version), 4),
		minor AS PARSENAME(CONVERT(VARCHAR(32), version), 3),
		build AS PARSENAME(CONVERT(VARCHAR(32), version), 2),
		revision AS PARSENAME(CONVERT(VARCHAR(32), version), 1)
	);

	insert into #checkversion
		SELECT CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128))
	OPTION (RECOMPILE);




declare @snapmemory TABLE(pass int,
	[object_name] [nvarchar](30) NULL,
	[counter_name] [nvarchar](40) NULL,
	[instance_name] [nvarchar](50) NULL,
	[cntr_value] [bigint] NOT NULL)


	
   declare @masterfiles TABLE  (database_id INT, file_id INT, type_desc NVARCHAR(50), name NVARCHAR(255), physical_name NVARCHAR(255), size BIGINT);
    /* Azure SQL Database doesn't have sys.master_files, so we have to build our own. */
    IF ((SERVERPROPERTY('Edition')) = 'SQL Azure' 
         AND (OBJECT_ID('sys.master_files') IS NULL))
    INSERT INTO @MasterFiles (database_id, file_id, type_desc, name, physical_name, size) SELECT DB_ID(), file_id, type_desc, name, physical_name, size FROM sys.database_files;;
    ELSE
     INSERT INTO @MasterFiles (database_id, file_id, type_desc, name, physical_name, size) SELECT database_id, file_id, type_desc, name, physical_name, size FROM sys.master_files;



declare     @FileStats table (
        ID INT IDENTITY(1, 1) PRIMARY KEY CLUSTERED,
        Pass TINYINT NOT NULL,
        SampleTime DATETIMEOFFSET NOT NULL,
        DatabaseID INT NOT NULL,
        FileID INT NOT NULL,
        DatabaseName NVARCHAR(256) ,
        FileLogicalName NVARCHAR(256) ,
        TypeDesc NVARCHAR(60) ,
        SizeOnDiskMB BIGINT ,
        io_stall_read_ms BIGINT ,
        num_of_reads BIGINT ,
        bytes_read BIGINT ,
        io_stall_write_ms BIGINT ,
        num_of_writes BIGINT ,
        bytes_written BIGINT,
        PhysicalName NVARCHAR(520) ,
        avg_stall_read_ms INT ,
        avg_stall_write_ms INT
    );





insert into @snapmemory (pass,object_name,counter_name,instance_name,cntr_value)
SELECT  
    1,SUBSTRING ([object_name], CHARINDEX (':', [object_name]) + 1, 30) AS [object_name], 
    LEFT (counter_name, 40) AS counter_name, LEFT (instance_name, 50) AS instance_name, cntr_value   
  FROM sys.dm_os_performance_counters 
  WHERE 
       ([object_name] LIKE '%:Memory Manager%' COLLATE Latin1_General_BIN    and counter_name in ('Memory Grants Pending','Target Server Memory (KB)','Total Server Memory (KB)','Free Memory (KB)'))
         OR ([object_name] LIKE '%:Buffer Manager%' COLLATE Latin1_General_BIN     AND counter_name COLLATE Latin1_General_BIN IN ('Page lookups/sec', 'Page life expectancy', 'Lazy writes/sec', 'Page reads/sec', 'Page writes/sec', 'Checkpoint pages/sec', 'Free pages', 'Total pages', 'Target pages', 'Stolen pages'))


	--	 select cntr_value/1024,* from sys.dm_os_performance_counters where [object_name] LIKE '%:Memory Manager%'



	--	 select physical_memory_in_use_kb/1024,* from sys.dm_os_process_memory

	 --select * from #snapmemory

declare @memorycommentary table (

	[TargetMb] [bigint] NULL,
	[TotalMb] [bigint] NULL,
	[FreeMb] [bigint] NULL,
	[comment] [varchar](127) NOT NULL)



	insert into @memorycommentary
			 select m1.cntr_value/1024 as TargetMb,m2.cntr_value /1024 as TotalMb,m3.cntr_value /1024 as FreeMb,'Target Memory is not reached, this may mean server is under memory pressure or freshly restarted or over committed for workload' as comment from @snapmemory m1 , @snapmemory m2 ,@snapmemory m3 where  m1.object_name='Memory Manager'  and m1.counter_name='Target Server Memory (KB)'  
			 and m2.object_name='memory manager' and m2.counter_name='Total Server Memory (KB)'  		 and m3.object_name='memory manager' and m3.counter_name='Free Memory (KB)'
				and  ((CAST(m1.cntr_value AS BIGINT)  ) >(CAST(m2.cntr_value AS BIGINT) )    or ((CAST(m1.cntr_value AS BIGINT) * .3 <= CAST(m3.cntr_value AS BIGINT)) or CAST(m3.cntr_value AS BIGINT) > 20480000000))
				and m1.pass=1 and m2.pass=1


				
				
	insert into @memorycommentary
			 select m1.cntr_value/1024 as TargetMb,m2.cntr_value /1024 as TotalMb,m3.cntr_value /1024 as FreeMb,/*m3.cntr_value,*/'Free Memory is large compared to total or over 5Gb.  May mean bad query plan bload, killing data cache' from @snapmemory m1 , @snapmemory m2 ,@snapmemory m3 where  m1.object_name='Memory Manager'  and m1.counter_name='Target Server Memory (KB)'  
			 and m2.object_name='memory manager' and m2.counter_name='Total Server Memory (KB)'  		 and m3.object_name='memory manager' and m3.counter_name='Free Memory (KB)'
				and     ((CAST(m1.cntr_value AS BIGINT) * .3 <= CAST(m3.cntr_value AS BIGINT) or CAST(m3.cntr_value AS BIGINT) >5242880))
					and m1.pass=1 and m2.pass=1 and m3.pass=1

				--if exists  show results

				if exists (select 1 from @memorycommentary)
					begin
						select * from @memorycommentary
					end



						declare @bufferCacheHitRatio decimal (5,2)
		 SELECT  @bufferCacheHitRatio= (a.cntr_value * 1.0 / b.cntr_value) * 100.0 
		FROM (SELECT *, 1 x FROM sys.dm_os_performance_counters   
        WHERE counter_name = 'Buffer cache hit ratio'
          AND object_name like '%Buffer Manager%') a   
     join
     (SELECT *, 1 x FROM sys.dm_os_performance_counters   
        WHERE counter_name = 'Buffer cache hit ratio base'
          and object_name like  '%Buffer Manager%') b      
          on a.x=b.x

		  if @bufferCacheHitRatio<95    or @showall=1
			begin
				select  @bufferCacheHitRatio,'Cache hit Ratio Should be above 95% for OLTP, 90% for OLAP'   
			end


					  --based on code from http://www.sqlskills.com/blogs/kimberly/plan-cache-adhoc-workloads-and-clearing-the-single-use-plan-cache-bloat/
declare @MemoryInUse			decimal(19,3)

SELECT @MemoryInUse = physical_memory_in_use_kb/1024 
FROM sys.dm_os_process_memory

--if wastedmb is high, consider turning on 'optimize for ad hoc workloads'
SELECT  'if wastedmb is high, consider turning on optimize for ad hoc workloads', sum(cast((CASE WHEN usecounts = 1 AND objtype IN ('Adhoc', 'Prepared') 
								THEN size_in_bytes ELSE 0 END) AS DECIMAL(12,2)))/1024/1024 as WastedMB
	,  sum(CASE WHEN usecounts = 1 AND objtype IN ('Adhoc', 'Prepared') 
								THEN 1 ELSE 0 END)  as SingleUsePlanCount
	,  sum(cast((CASE WHEN usecounts = 1 AND objtype IN ('Adhoc', 'Prepared') 
								THEN size_in_bytes ELSE 0 END) AS DECIMAL(12,2)))/1024/1024/@MemoryInUse * 100     as 'Wasted Percent'
FROM sys.dm_exec_cached_plans




----check the last hours CPU, and highlight either where SQL>50 or other tasks are above 30...



IF OBJECT_ID('tempdb..#cpuRingBuffer') IS NOT NULL
    DROP TABLE #cpuRingBuffer

CREATE TABLE [dbo].[#cpuRingBuffer](
	[id] int NULL,
	[eventtime] smalldatetime NULL,
	SQLCPU int,
	idleCPU int,
	OtherCpu int) ON [PRIMARY]



				DECLARE @ticks_ms BIGINT
SELECT @ticks_ms = ms_ticks
FROM sys.dm_os_sys_info;

insert into #cpuRingBuffer
SELECT TOP 60 id
    ,dateadd(ms, - 1 * (@ticks_ms - [timestamp]), GetDate()) AS EventTime
    ,ProcessUtilization as 'SQL CPU'
    ,SystemIdle 'Idle CPU'
    ,100 - SystemIdle - ProcessUtilization AS 'Others (100-SQL-Idle)'
FROM (
    SELECT record.value('(./Record/@id)[1]', 'int') AS id
    ,record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') 
                          AS SystemIdle
    ,record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') 
                          AS ProcessUtilization
        ,TIMESTAMP
    FROM (
        SELECT TIMESTAMP
            ,convert(XML, record) AS record
        FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
            AND record LIKE '%SystemHealth%'
        ) AS sub1
    ) AS sub2
ORDER BY id DESC



if exists (select 1 from #cpuRingBuffer where SQLCPU>50 or OtherCpu>20) or @showall=1
begin
	select 'SHow CPU issues in the last hour'
	select *,'CPU Spikes from either SQL or Other tasks' as comments from #cpuRingBuffer where SQLCPU>50 or OtherCpu>20
end

select 'Show Cache Size by database'
SELECT count(*)*8/1024 AS 'Cached Size (MB)' ,CASE database_id WHEN 32767 THEN 'ResourceDb' ELSE db_name(database_id) END AS 'Database' FROM sys.dm_os_buffer_descriptors
GROUP BY db_name(database_id),database_id ORDER BY'Cached Size (MB)'DESC






/********************************************************************************
 Title:			Worst Performing Queries
 Created by:	Mark S. Rasmussen <mark@improve.dk>
 License:		CC BY 3.0

--https://github.com/improvedk/Useful-SQL-Server-Queries/blob/master/Plan%20Cache/Worst%20Performing%20Queries.sql
 
 Usage:
 Returns a list of the most time consuming queries, server wide. Depending on what
 kind of queries you're looking for, you can uncomment the relevant predicates.
 ********************************************************************************/

 select 'worst IO'
 SET ARITHABORT off
;WITH TMP AS
(
	SELECT TOP 10
		CAST(SUM(s.total_elapsed_time) / 1000000.0 AS DECIMAL(10, 2)) AS [Total Elapsed Time in S],
		SUM(s.execution_count) AS [Total Execution Count],
		CAST(SUM(s.total_worker_time) / 1000000.0 AS DECIMAL(10, 2)) AS [Total CPU Time in S],
		CAST(SUM(s.total_worker_time) / SUM(s.execution_count) / 1000.0 AS DECIMAL(10, 2)) AS [Avg CPU Time in MS],
		SUM(s.total_logical_reads) AS [Total Logical Reads],
		CAST(CAST(SUM(s.total_logical_reads) AS FLOAT) / CAST(SUM(s.execution_count) AS FLOAT) AS DECIMAL(20, 2)) AS [Avg Logical Reads],
		SUM(s.total_logical_writes) AS [Total Logical Writes],
	CAST(CAST(SUM(s.total_logical_writes) AS FLOAT) / CAST(SUM(s.execution_count) AS FLOAT) AS DECIMAL(20, 2)) AS [Avg Logical Writes],
		SUM(s.total_clr_time) AS [Total CLR Time],
		CAST(SUM(s.total_clr_time) / SUM(s.execution_count) / 1000.0 AS DECIMAL(20, 2)) AS [Avg CLR Time in MS],
	--	CAST(SUM(s.min_worker_time) / 1000.0 AS DECIMAL(10, 2)) AS [Min CPU Time in MS],
	--	CAST(SUM(s.max_worker_time) / 1000.0 AS DECIMAL(10, 2)) AS [Max CPU Time in MS],
		SUM(s.min_logical_reads) AS [Min Logical Reads],
		SUM(s.max_logical_reads) AS [Max Logical Reads],
		SUM(s.min_logical_writes) AS [Min Logical Writes],
		SUM(s.max_logical_writes) AS [Max Logical Writes],
	--	CAST(SUM(s.min_clr_time) / 1000.0 AS DECIMAL(10, 2)) AS [Min CLR Time in MS],
	---	CAST(SUM(s.max_clr_time) / 1000.0 AS DECIMAL(10, 2)) AS [Max CLR Time in MS],
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
		
	-- Most write IO consuming
	--GROUP BY s.plan_handle ORDER BY SUM(s.total_logical_writes) DESC
		
	-- Most CLR consuming
	--WHERE s.total_clr_time > 0 GROUP BY s.plan_handle ORDER BY SUM(s.total_clr_time) DESC
)
SELECT
	TMP.*,
	st.text AS [Query],
	qp.query_plan AS [Plan],qp.dbid
FROM
	TMP
OUTER APPLY
	sys.dm_exec_query_plan(TMP.[Plan Handle]) AS qp
OUTER APPLY
	sys.dm_exec_sql_text(TMP.[Plan Handle]) AS st


	
 select 'worst CPU'
 
;WITH TMP AS
(
	SELECT TOP 10
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
		
	-- Most read+write IO consuming
	--GROUP BY s.plan_handle ORDER BY SUM(s.total_logical_reads + s.total_logical_writes) DESC
		
	-- Most write IO consuming
	--GROUP BY s.plan_handle ORDER BY SUM(s.total_logical_writes) DESC
		
	-- Most CLR consuming
	--WHERE s.total_clr_time > 0 GROUP BY s.plan_handle ORDER BY SUM(s.total_clr_time) DESC
)
SELECT
	TMP.*,
	st.text AS [Query],
	qp.query_plan AS [Plan],qp.dbid
FROM
	TMP
OUTER APPLY
	sys.dm_exec_query_plan(TMP.[Plan Handle]) AS qp
OUTER APPLY
	sys.dm_exec_sql_text(TMP.[Plan Handle]) AS st

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



	
declare @blockinghistory table (DatabaseName varchar(200),ObjectName varchar(200),LocksCount bigint,BlocksCount bigint,blocksWaitTimeMs bigint,index_id bigint)


DECLARE @command varchar(1000) 
SELECT @command = 'use [?] select db_name(database_id) as DatabaseName
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

if exists(select 1 from @blockinghistory where BlocksCount>10) or @showall=1
begin
	select 'Blocking History'

	select * from @blockinghistory where BlocksCount>10
end

	---bad plan estimates based on sp_blitz code..... not currently in use..
--	declare @majorv int

--	select  @majorv=major from #checkversion

--	if  @majorv>12
--	begin

--	   DECLARE @bad_estimate TABLE 
--                     ( 
--                       session_id INT, 
--                       request_id INT, 
--                       estimate_inaccuracy BIT 
--                     );
                   
--                   INSERT @bad_estimate ( session_id, request_id, estimate_inaccuracy )
--                   SELECT x.session_id, 
--                          x.request_id, 
--                          x.estimate_inaccuracy
--                   FROM (
--                         SELECT deqp.session_id,
--                                deqp.request_id,
--                                CASE WHEN deqp.row_count > ( deqp.estimate_row_count * 10000 )
--                                     THEN 1
--                                     ELSE 0
--                                END AS estimate_inaccuracy
--                         FROM   sys.dm_exec_query_profiles AS deqp
--						 WHERE deqp.session_id <> @@SPID
--                   ) AS x
--                   WHERE x.estimate_inaccuracy = 1
--                   GROUP BY x.session_id, 
--                            x.request_id, 
--                            x.estimate_inaccuracy;
							

--							select * 
--							   FROM @bad_estimate AS b
--                  JOIN sys.dm_exec_requests AS r
--                  ON r.session_id = b.session_id
--                  AND r.request_id = b.request_id
--                  JOIN sys.dm_exec_sessions AS s
--                  ON s.session_id = b.session_id
--                  CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS dest
--				  CROSS APPLY sys.dm_exec_query_plan(r.plan_handle) AS qp ;
--end 


--check for waits for  storage space for a database restore, a data file growth, or a log file growth.    






declare @quickstats table
        (
         sessionid int,
          QueryPlan [XML] NULL,
          --QueryText NVARCHAR(MAX) NULL,
          StartTime DATETIMEOFFSET NULL,
          LoginName NVARCHAR(128) NULL,
          NTUserName NVARCHAR(128) NULL,
          OriginalLoginName NVARCHAR(128) NULL,
          ProgramName NVARCHAR(128) NULL,
          HostName NVARCHAR(128) NULL,
          DatabaseID INT NULL,
          DatabaseName NVARCHAR(128) NULL,
          OpenTransactionCount INT NULL,
		  comments varchar(500),
		  command varchar(500))




insert into @quickstats (sessionid, QueryPlan, StartTime, LoginName, NTUserName, ProgramName, HostName, comments,command)
 


select s.session_id,pl.query_plan AS QueryPlan,        r.start_time AS StartTime,        s.login_name AS LoginName,
        s.nt_user_name AS NTUserName,
        s.[program_name] AS ProgramName,
        s.[host_name] AS HostName, 'waits for  storage space for a database restore, a data file growth, or a log file growth.'  as Comments, r.command
    FROM sys.dm_os_waiting_tasks t
    INNER JOIN sys.dm_exec_connections c ON t.session_id = c.session_id
    INNER JOIN sys.dm_exec_requests r ON t.session_id = r.session_id
    INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
    CROSS APPLY sys.dm_exec_query_plan(r.plan_handle) pl
    WHERE t.wait_type = 'PREEMPTIVE_OS_WRITEFILEGATHER'




insert into @quickstats (sessionid, QueryPlan, StartTime, LoginName, NTUserName, ProgramName, HostName,DatabaseID,DatabaseName, command,comments)

select     c.session_id, pl.query_plan AS QueryPlan,
        r.start_time AS StartTime,
        s.login_name AS LoginName,
        s.nt_user_name AS NTUserName,
        s.[program_name] AS ProgramName,
        s.[host_name] AS HostName,
        db.[resource_database_id] AS DatabaseID,
        DB_NAME(db.resource_database_id) AS DatabaseName,
       
       r.command ,'DBCC/backup/index  tasks Running' as comments   
    FROM sys.dm_exec_requests r
    INNER JOIN sys.dm_exec_connections c ON r.session_id = c.session_id
    INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
    INNER JOIN (SELECT DISTINCT l.request_session_id, l.resource_database_id
    FROM    sys.dm_tran_locks l
    INNER JOIN sys.databases d ON l.resource_database_id = d.database_id
    WHERE l.resource_type = N'DATABASE'
    AND     l.request_mode = N'S'
    AND    l.request_status = N'GRANT'
    AND    l.request_owner_type = N'SHARED_TRANSACTION_WORKSPACE') AS db ON s.session_id = db.request_session_id
    OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) pl
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
    WHERE (r.command LIKE 'DBCC%' or r.command LIKE 'BACKUP%' or r.command LIKE '%index%')
	AND CAST(t.text AS NVARCHAR(4000)) NOT LIKE '%dm_db_index_physical_stats%'
	AND CAST(t.text AS NVARCHAR(4000)) NOT LIKE '%ALTER INDEX%'
	AND CAST(t.text AS NVARCHAR(4000)) NOT LIKE '%fileproperty%'


	--check for existence of a bad operation like indexing, dbcc, backups

	if exists (select 1 from @quickstats)
	begin
		select 'intensive disk actions occuring'
		select command,sessionid,StartTime,LoginName,ntusername,programname,HostName,DatabaseID,databasename from @quickstats
    end
--check if default trace is enabled
--select * from sys.configurations where configuration_id = 1568
 



 --look for recent database growth events 
--get the current trace rollover file
--use this path with the log.trc file in the path below.
--this will cause a file rollover to get all the data


declare @tracepath varchar(2000)

declare @mytraceinfo table(traceid int, property int,value sql_variant)

insert into @mytraceinfo 
select * from ::fn_trace_getinfo(0) 


select @tracepath=cast(value as varchar(2000)) from @mytraceinfo where property=2


declare @growthevents table(
	[ntusername] [nvarchar](256) NULL,
	[loginname] [nvarchar](256) NULL,
	[objectname] [nvarchar](256) NULL,
	[category_id] [smallint] NOT NULL,
	[textdata] [ntext] NULL,
	[starttime] [datetime] NULL,
	[spid] [int] NULL,
	[hostname] [nvarchar](256) NULL,
	[eventclass] [int] NULL,
	[databasename] [nvarchar](256) NULL,
	[name] [nvarchar](128) NULL,
	Filename nvarchar(128),
	ChangeInSizeMB int,
	DurationMS int)



 insert into @growthevents
SELECT ntusername,loginname, objectname, e.category_id, textdata, starttime,spid,hostname, eventclass,databasename, e.name ,FileName,  (IntegerData * 8.0 / 1024) AS 'ChangeInSize MB',(duration/1000)AS DurMS
FROM ::fn_trace_gettable(@tracepath,0)
      inner join sys.trace_events e
            on eventclass = trace_event_id
       INNER JOIN sys.trace_categories AS cat
            ON e.category_id = cat.category_id
where
      cat.category_id = 2 and --database category
      e.trace_event_id in (92,93) --db file growth
	  and dateadd(hh,-3,getdate())>starttime


	  if exists (select 1 from @growthevents)
	  begin
			
		select 'Database Growth Events'
		  select * from @growthevents
	  end 


	  declare @logspace table (DatabaseName varchar(30),LogSizeMb   decimal (20,2),LogSpaceUsedPct decimal (5,2))

	  insert into @logspace(DatabaseName ,LogSizeMb,LogSpaceUsedPct)
			SELECT rtrim(pc1.instance_name) AS [Database Name]
 ,      pc1.cntr_value/1024.0  AS [Log Size (MB)]
 ,      cast(pc2.cntr_value*100.0/pc1.cntr_value as dec(5,2))
         as [Log Space Used (%)]
 FROM   sys.dm_os_performance_counters as pc1
 JOIN   sys.dm_os_performance_counters as pc2
 ON     pc1.instance_name = pc2.instance_name
 WHERE  pc1.object_name LIKE '%Databases%'
 AND    pc2.object_name LIKE '%Databases%'
 AND    pc1.counter_name = 'Log File(s) Size (KB)'
 AND    pc2.counter_name = 'Log File(s) Used Size (KB)'
 AND    pc1.instance_name not in ('_Total', 'mssqlsystemresource')
 AND    pc1.cntr_value > 0

 select * from @logspace



 
/*Beginning of the timing section, how long to monitor pain points  or WT*/





 
/*Beginning of the timing section, how long to monitor pain points  or WT*/

--query section on sp_blitz
-- based on sp_blitz --magic on query plans
---queries run in the last 10 secs 
---look for frequent small exections 	

--missing index section based on IndexSnapshot by Rob


declare @rr_indexsnapshot table   
(
	[index_advantage] [float] NULL,
	[group_handle] [int] NOT NULL,
	[index_handle] [int] NOT NULL,
	[unique_compiles] [bigint] NULL,
	[user_seeks] [bigint] NULL,
	[last_user_seek] [datetime] NULL,
	[avg_total_user_cost] [float] NULL,
	[avg_user_impact] [float] NULL,
	[database_id] [smallint] NOT NULL,
	[object_id] [int] NOT NULL,
	[equality_columns] [nvarchar](4000) NULL,
	[inequality_columns] [nvarchar](4000) NULL,
	[included_columns] [nvarchar](4000) NULL,
	[statement] [nvarchar](4000) NULL
) 

--initial snapshot
insert into @rr_indexsnapshot
select index_advantage,group_handle,mig.index_handle,unique_compiles,user_seeks,last_user_seek,avg_total_user_cost,avg_user_impact,database_id,object_id,equality_columns,inequality_columns,included_columns	,statement 
from
(select user_seeks * avg_total_user_cost * (avg_user_impact*0.01) as index_advantage,
migs.* from sys.dm_db_missing_index_group_stats migs) as migs_adv 
inner join sys.dm_db_missing_index_groups as mig on migs_adv.group_handle=
mig.index_group_handle
inner join sys.dm_db_missing_index_details as mid on mig.index_handle=mid.index_handle
order by migs_adv.index_advantage desc;

declare @waitsnap TABLE (
	snapdate smalldatetime,[Pass] [int] NOT NULL,
	[wait_type] [nvarchar](60) NOT NULL,
	[waiting_tasks_count] [bigint] NOT NULL,
	[wait_time_ms] [bigint] NOT NULL,
	[max_wait_time_ms] [bigint] NOT NULL,
	[signal_wait_time_ms] [bigint] NOT NULL
) 


		declare  @cte_my_waitssummary table(
	[wait_type] [nvarchar](60) NOT NULL,
	[wait_time_ms] [bigint] NULL,
	[WaitS] [numeric](26, 6) NULL,
	[ResourceS] [numeric](26, 6) NULL,
	[SignalS] [numeric](26, 6) NULL,
	[WaitCount] [bigint] NULL,
	[Percentage] [numeric](38, 15) NULL,
	[RowNum] [bigint] NULL)

IF OBJECT_ID('tempdb..#QueryStats') IS NOT NULL
        DROP TABLE #QueryStats;
    CREATE TABLE #QueryStats (
        ID INT IDENTITY(1, 1) PRIMARY KEY CLUSTERED,
        Pass INT NOT NULL,
        SampleTime DATETIMEOFFSET NOT NULL,
        [sql_handle] VARBINARY(64),
        statement_start_offset INT,
        statement_end_offset INT,
        plan_generation_num BIGINT,
        plan_handle VARBINARY(64),
        execution_count BIGINT,
        total_worker_time BIGINT,
        total_physical_reads BIGINT,
        total_logical_writes BIGINT,
        total_logical_reads BIGINT,
        total_clr_time BIGINT,
        total_elapsed_time BIGINT,
        creation_time DATETIMEOFFSET,
        query_hash BINARY(8),
        query_plan_hash BINARY(8),
        Points TINYINT
    );


	insert into @waitsnap(snapdate,Pass,wait_type,waiting_tasks_count,wait_time_ms,max_wait_time_ms,signal_wait_time_ms)
	select getdate(),1 as Pass, wait_type,waiting_tasks_count,wait_time_ms,max_wait_time_ms,signal_wait_time_ms    from sys.dm_os_wait_stats

	    WHERE [wait_type] NOT IN (
        -- These wait types are almost 100% never a problem and so they are
        -- filtered out to avoid them skewing the results. Click on the URL
        -- for more information.
		N'VDI_CLIENT_OTHER',
        N'BROKER_EVENTHANDLER', -- https://www.sqlskills.com/help/waits/BROKER_EVENTHANDLER
        N'BROKER_RECEIVE_WAITFOR', -- https://www.sqlskills.com/help/waits/BROKER_RECEIVE_WAITFOR
        N'BROKER_TASK_STOP', -- https://www.sqlskills.com/help/waits/BROKER_TASK_STOP
        N'BROKER_TO_FLUSH', -- https://www.sqlskills.com/help/waits/BROKER_TO_FLUSH
        N'BROKER_TRANSMITTER', -- https://www.sqlskills.com/help/waits/BROKER_TRANSMITTER
        N'CHECKPOINT_QUEUE', -- https://www.sqlskills.com/help/waits/CHECKPOINT_QUEUE
        N'CHKPT', -- https://www.sqlskills.com/help/waits/CHKPT
        N'CLR_AUTO_EVENT', -- https://www.sqlskills.com/help/waits/CLR_AUTO_EVENT
        N'CLR_MANUAL_EVENT', -- https://www.sqlskills.com/help/waits/CLR_MANUAL_EVENT
        N'CLR_SEMAPHORE', -- https://www.sqlskills.com/help/waits/CLR_SEMAPHORE
        N'CXCONSUMER', -- https://www.sqlskills.com/help/waits/CXCONSUMER
 
        -- Maybe comment these four out if you have mirroring issues
        N'DBMIRROR_DBM_EVENT', -- https://www.sqlskills.com/help/waits/DBMIRROR_DBM_EVENT
        N'DBMIRROR_EVENTS_QUEUE', -- https://www.sqlskills.com/help/waits/DBMIRROR_EVENTS_QUEUE
        N'DBMIRROR_WORKER_QUEUE', -- https://www.sqlskills.com/help/waits/DBMIRROR_WORKER_QUEUE
        N'DBMIRRORING_CMD', -- https://www.sqlskills.com/help/waits/DBMIRRORING_CMD
 
        N'DIRTY_PAGE_POLL', -- https://www.sqlskills.com/help/waits/DIRTY_PAGE_POLL
        N'DISPATCHER_QUEUE_SEMAPHORE', -- https://www.sqlskills.com/help/waits/DISPATCHER_QUEUE_SEMAPHORE
        N'EXECSYNC', -- https://www.sqlskills.com/help/waits/EXECSYNC
        N'FSAGENT', -- https://www.sqlskills.com/help/waits/FSAGENT
        N'FT_IFTS_SCHEDULER_IDLE_WAIT', -- https://www.sqlskills.com/help/waits/FT_IFTS_SCHEDULER_IDLE_WAIT
        N'FT_IFTSHC_MUTEX', -- https://www.sqlskills.com/help/waits/FT_IFTSHC_MUTEX
 
        -- Maybe comment these six out if you have AG issues
        N'HADR_CLUSAPI_CALL', -- https://www.sqlskills.com/help/waits/HADR_CLUSAPI_CALL
        N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', -- https://www.sqlskills.com/help/waits/HADR_FILESTREAM_IOMGR_IOCOMPLETION
        N'HADR_LOGCAPTURE_WAIT', -- https://www.sqlskills.com/help/waits/HADR_LOGCAPTURE_WAIT
        N'HADR_NOTIFICATION_DEQUEUE', -- https://www.sqlskills.com/help/waits/HADR_NOTIFICATION_DEQUEUE
        N'HADR_TIMER_TASK', -- https://www.sqlskills.com/help/waits/HADR_TIMER_TASK
        N'HADR_WORK_QUEUE', -- https://www.sqlskills.com/help/waits/HADR_WORK_QUEUE
 
        N'KSOURCE_WAKEUP', -- https://www.sqlskills.com/help/waits/KSOURCE_WAKEUP
        N'LAZYWRITER_SLEEP', -- https://www.sqlskills.com/help/waits/LAZYWRITER_SLEEP
        N'LOGMGR_QUEUE', -- https://www.sqlskills.com/help/waits/LOGMGR_QUEUE
        N'MEMORY_ALLOCATION_EXT', -- https://www.sqlskills.com/help/waits/MEMORY_ALLOCATION_EXT
        N'ONDEMAND_TASK_QUEUE', -- https://www.sqlskills.com/help/waits/ONDEMAND_TASK_QUEUE
        N'PARALLEL_REDO_DRAIN_WORKER', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_DRAIN_WORKER
        N'PARALLEL_REDO_LOG_CACHE', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_LOG_CACHE
        N'PARALLEL_REDO_TRAN_LIST', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_TRAN_LIST
        N'PARALLEL_REDO_WORKER_SYNC', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_WORKER_SYNC
        N'PARALLEL_REDO_WORKER_WAIT_WORK', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_WORKER_WAIT_WORK
        N'PREEMPTIVE_XE_GETTARGETSTATE', -- https://www.sqlskills.com/help/waits/PREEMPTIVE_XE_GETTARGETSTATE
        N'PWAIT_ALL_COMPONENTS_INITIALIZED', -- https://www.sqlskills.com/help/waits/PWAIT_ALL_COMPONENTS_INITIALIZED
        N'PWAIT_DIRECTLOGCONSUMER_GETNEXT', -- https://www.sqlskills.com/help/waits/PWAIT_DIRECTLOGCONSUMER_GETNEXT
        N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', -- https://www.sqlskills.com/help/waits/QDS_PERSIST_TASK_MAIN_LOOP_SLEEP
        N'QDS_ASYNC_QUEUE', -- https://www.sqlskills.com/help/waits/QDS_ASYNC_QUEUE
        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
            -- https://www.sqlskills.com/help/waits/QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP
        N'QDS_SHUTDOWN_QUEUE', -- https://www.sqlskills.com/help/waits/QDS_SHUTDOWN_QUEUE
        N'REDO_THREAD_PENDING_WORK', -- https://www.sqlskills.com/help/waits/REDO_THREAD_PENDING_WORK
        N'REQUEST_FOR_DEADLOCK_SEARCH', -- https://www.sqlskills.com/help/waits/REQUEST_FOR_DEADLOCK_SEARCH
        N'RESOURCE_QUEUE', -- https://www.sqlskills.com/help/waits/RESOURCE_QUEUE
        N'SERVER_IDLE_CHECK', -- https://www.sqlskills.com/help/waits/SERVER_IDLE_CHECK
        N'SLEEP_BPOOL_FLUSH', -- https://www.sqlskills.com/help/waits/SLEEP_BPOOL_FLUSH
        N'SLEEP_DBSTARTUP', -- https://www.sqlskills.com/help/waits/SLEEP_DBSTARTUP
        N'SLEEP_DCOMSTARTUP', -- https://www.sqlskills.com/help/waits/SLEEP_DCOMSTARTUP
        N'SLEEP_MASTERDBREADY', -- https://www.sqlskills.com/help/waits/SLEEP_MASTERDBREADY
        N'SLEEP_MASTERMDREADY', -- https://www.sqlskills.com/help/waits/SLEEP_MASTERMDREADY
        N'SLEEP_MASTERUPGRADED', -- https://www.sqlskills.com/help/waits/SLEEP_MASTERUPGRADED
        N'SLEEP_MSDBSTARTUP', -- https://www.sqlskills.com/help/waits/SLEEP_MSDBSTARTUP
        N'SLEEP_SYSTEMTASK', -- https://www.sqlskills.com/help/waits/SLEEP_SYSTEMTASK
        N'SLEEP_TASK', -- https://www.sqlskills.com/help/waits/SLEEP_TASK
        N'SLEEP_TEMPDBSTARTUP', -- https://www.sqlskills.com/help/waits/SLEEP_TEMPDBSTARTUP
        N'SNI_HTTP_ACCEPT', -- https://www.sqlskills.com/help/waits/SNI_HTTP_ACCEPT
        N'SP_SERVER_DIAGNOSTICS_SLEEP', -- https://www.sqlskills.com/help/waits/SP_SERVER_DIAGNOSTICS_SLEEP
        N'SQLTRACE_BUFFER_FLUSH', -- https://www.sqlskills.com/help/waits/SQLTRACE_BUFFER_FLUSH
        N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', -- https://www.sqlskills.com/help/waits/SQLTRACE_INCREMENTAL_FLUSH_SLEEP
        N'SQLTRACE_WAIT_ENTRIES', -- https://www.sqlskills.com/help/waits/SQLTRACE_WAIT_ENTRIES
        N'WAIT_FOR_RESULTS', -- https://www.sqlskills.com/help/waits/WAIT_FOR_RESULTS
        N'WAITFOR', -- https://www.sqlskills.com/help/waits/WAITFOR
        N'WAITFOR_TASKSHUTDOWN', -- https://www.sqlskills.com/help/waits/WAITFOR_TASKSHUTDOWN
        N'WAIT_XTP_RECOVERY', -- https://www.sqlskills.com/help/waits/WAIT_XTP_RECOVERY
        N'WAIT_XTP_HOST_WAIT', -- https://www.sqlskills.com/help/waits/WAIT_XTP_HOST_WAIT
        N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', -- https://www.sqlskills.com/help/waits/WAIT_XTP_OFFLINE_CKPT_NEW_LOG
        N'WAIT_XTP_CKPT_CLOSE', -- https://www.sqlskills.com/help/waits/WAIT_XTP_CKPT_CLOSE
        N'XE_DISPATCHER_JOIN', -- https://www.sqlskills.com/help/waits/XE_DISPATCHER_JOIN
        N'XE_DISPATCHER_WAIT', -- https://www.sqlskills.com/help/waits/XE_DISPATCHER_WAIT
        N'XE_TIMER_EVENT' -- https://www.sqlskills.com/help/waits/XE_TIMER_EVENT
        )
    AND [waiting_tasks_count] > 0



	insert into #QueryStats ([sql_handle],Pass, SampleTime, statement_start_offset, statement_end_offset, plan_generation_num, plan_handle,execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time,query_hash, query_plan_hash,Points)
SELECT [sql_handle], 1 AS Pass, SYSDATETIMEOFFSET(), statement_start_offset, statement_end_offset, plan_generation_num, plan_handle, execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time, query_hash, query_plan_hash, 0
											FROM sys.dm_exec_query_stats qs
											WHERE qs.last_execution_time >= (DATEADD(ss, -10, SYSDATETIMEOFFSET()));




--now get the plan counts as far back as possible
		INSERT INTO #QueryStats (Pass, SampleTime, execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time)
		SELECT 0 AS Pass, SYSDATETIMEOFFSET(), SUM(execution_count), SUM(total_worker_time), SUM(total_physical_reads), SUM(total_logical_writes), SUM(total_logical_reads), SUM(total_clr_time), SUM(total_elapsed_time), MIN(creation_time)
			FROM sys.dm_exec_query_stats qs;

---collecting file stats for sample
			insert into @FileStats (   Pass , 
			SampleTime , 
			DatabaseID ,  
			FileID ,
        DatabaseName ,
        FileLogicalName  ,
     
        SizeOnDiskMB ,
        io_stall_read_ms  ,
        num_of_reads,
        bytes_read ,
        io_stall_write_ms  ,
        num_of_writes  ,
        bytes_written ,
        PhysicalName  
       )
	     SELECT
        1 AS Pass,
        SYSDATETIMEOFFSET()  AS SampleTime,
        mf.[database_id],
        mf.[file_id],
        DB_NAME(vfs.database_id) AS [db_name],
        mf.name + N' [' + mf.type_desc COLLATE SQL_Latin1_General_CP1_CI_AS + N']' AS file_logical_name ,
        CAST(( ( vfs.size_on_disk_bytes / 1024.0 ) / 1024.0 ) AS INT) AS size_on_disk_mb ,
        vfs.io_stall_read_ms  ,
		vfs.num_of_reads  ,
        vfs.[num_of_bytes_read] ,
        vfs.io_stall_write_ms  ,
       vfs.num_of_writes  ,
       vfs.[num_of_bytes_written]  ,
        mf.physical_name
    FROM sys.dm_io_virtual_file_stats (NULL, NULL) AS vfs
    INNER JOIN @MasterFiles AS mf ON vfs.file_id = mf.file_id
        AND vfs.database_id = mf.database_id
    WHERE vfs.num_of_reads > 0
        OR vfs.num_of_writes > 0;

			--WT timer
			---delay before second query snapshot is taken  and second index section
			 WAITFOR DELAY  @SNAPSHOTDELAY

				----  now vs snapshot

				
				select 'Indexing Snapshot';
				
				with indexnow  as (select index_advantage,group_handle,mig.index_handle,unique_compiles,user_seeks,last_user_seek,avg_total_user_cost,avg_user_impact,database_id,object_id,equality_columns,inequality_columns,included_columns	,statement
				from
				(select user_seeks * avg_total_user_cost * (avg_user_impact*0.01) as index_advantage,
				migs.* from sys.dm_db_missing_index_group_stats migs) as migs_adv 
				inner join sys.dm_db_missing_index_groups as mig on migs_adv.group_handle=
				mig.index_group_handle
				inner join sys.dm_db_missing_index_details as mid on mig.index_handle=mid.index_handle

				)


				select ind_now.index_advantage,snap.user_seeks as snapseeks,ind_now.user_seeks as now_seeks,ind_now.avg_user_impact,ind_now.avg_total_user_cost, ind_now.last_user_seek,ind_now.database_id,snap.database_id,
				snap.object_id,snap.equality_columns,snap.inequality_columns,snap.included_columns,snap.statement
				from indexnow  ind_now    join @rr_indexsnapshot  snap on ind_now.index_handle=snap.index_handle
				where ind_now.last_user_seek>snap.last_user_seek    and (ind_now.index_advantage>5000 or @showall=1)
				


				--select user_seeks * avg_total_user_cost * (avg_user_impact*0.01) as index_advantage,
				--migs.* from sys.dm_db_missing_index_group_stats migs) as migs_adv 
				--inner join sys.dm_db_missing_index_groups as mig on migs_adv.group_handle=
				--mig.index_group_handle
				--inner join sys.dm_db_missing_index_details as mid on mig.index_handle=mid.index_handle
				--order by ind_now.index_advantage   desc


				
	insert into @waitsnap(snapdate,Pass,wait_type,waiting_tasks_count,wait_time_ms,max_wait_time_ms,signal_wait_time_ms)
	select getdate(),2 as Pass, wait_type,waiting_tasks_count,wait_time_ms,max_wait_time_ms,signal_wait_time_ms    from sys.dm_os_wait_stats
		    WHERE [wait_type] NOT IN (
        -- These wait types are almost 100% never a problem and so they are
        -- filtered out to avoid them skewing the results. Click on the URL
        -- for more information.
        N'BROKER_EVENTHANDLER', -- https://www.sqlskills.com/help/waits/BROKER_EVENTHANDLER
        N'BROKER_RECEIVE_WAITFOR', -- https://www.sqlskills.com/help/waits/BROKER_RECEIVE_WAITFOR
        N'BROKER_TASK_STOP', -- https://www.sqlskills.com/help/waits/BROKER_TASK_STOP
        N'BROKER_TO_FLUSH', -- https://www.sqlskills.com/help/waits/BROKER_TO_FLUSH
        N'BROKER_TRANSMITTER', -- https://www.sqlskills.com/help/waits/BROKER_TRANSMITTER
        N'CHECKPOINT_QUEUE', -- https://www.sqlskills.com/help/waits/CHECKPOINT_QUEUE
        N'CHKPT', -- https://www.sqlskills.com/help/waits/CHKPT
        N'CLR_AUTO_EVENT', -- https://www.sqlskills.com/help/waits/CLR_AUTO_EVENT
        N'CLR_MANUAL_EVENT', -- https://www.sqlskills.com/help/waits/CLR_MANUAL_EVENT
        N'CLR_SEMAPHORE', -- https://www.sqlskills.com/help/waits/CLR_SEMAPHORE
        N'CXCONSUMER', -- https://www.sqlskills.com/help/waits/CXCONSUMER
 
        -- Maybe comment these four out if you have mirroring issues
        N'DBMIRROR_DBM_EVENT', -- https://www.sqlskills.com/help/waits/DBMIRROR_DBM_EVENT
        N'DBMIRROR_EVENTS_QUEUE', -- https://www.sqlskills.com/help/waits/DBMIRROR_EVENTS_QUEUE
        N'DBMIRROR_WORKER_QUEUE', -- https://www.sqlskills.com/help/waits/DBMIRROR_WORKER_QUEUE
        N'DBMIRRORING_CMD', -- https://www.sqlskills.com/help/waits/DBMIRRORING_CMD
 
        N'DIRTY_PAGE_POLL', -- https://www.sqlskills.com/help/waits/DIRTY_PAGE_POLL
        N'DISPATCHER_QUEUE_SEMAPHORE', -- https://www.sqlskills.com/help/waits/DISPATCHER_QUEUE_SEMAPHORE
        N'EXECSYNC', -- https://www.sqlskills.com/help/waits/EXECSYNC
        N'FSAGENT', -- https://www.sqlskills.com/help/waits/FSAGENT
        N'FT_IFTS_SCHEDULER_IDLE_WAIT', -- https://www.sqlskills.com/help/waits/FT_IFTS_SCHEDULER_IDLE_WAIT
        N'FT_IFTSHC_MUTEX', -- https://www.sqlskills.com/help/waits/FT_IFTSHC_MUTEX
 
        -- Maybe comment these six out if you have AG issues
        N'HADR_CLUSAPI_CALL', -- https://www.sqlskills.com/help/waits/HADR_CLUSAPI_CALL
        N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', -- https://www.sqlskills.com/help/waits/HADR_FILESTREAM_IOMGR_IOCOMPLETION
        N'HADR_LOGCAPTURE_WAIT', -- https://www.sqlskills.com/help/waits/HADR_LOGCAPTURE_WAIT
        N'HADR_NOTIFICATION_DEQUEUE', -- https://www.sqlskills.com/help/waits/HADR_NOTIFICATION_DEQUEUE
        N'HADR_TIMER_TASK', -- https://www.sqlskills.com/help/waits/HADR_TIMER_TASK
        N'HADR_WORK_QUEUE', -- https://www.sqlskills.com/help/waits/HADR_WORK_QUEUE
 
        N'KSOURCE_WAKEUP', -- https://www.sqlskills.com/help/waits/KSOURCE_WAKEUP
        N'LAZYWRITER_SLEEP', -- https://www.sqlskills.com/help/waits/LAZYWRITER_SLEEP
        N'LOGMGR_QUEUE', -- https://www.sqlskills.com/help/waits/LOGMGR_QUEUE
        N'MEMORY_ALLOCATION_EXT', -- https://www.sqlskills.com/help/waits/MEMORY_ALLOCATION_EXT
        N'ONDEMAND_TASK_QUEUE', -- https://www.sqlskills.com/help/waits/ONDEMAND_TASK_QUEUE
        N'PARALLEL_REDO_DRAIN_WORKER', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_DRAIN_WORKER
        N'PARALLEL_REDO_LOG_CACHE', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_LOG_CACHE
        N'PARALLEL_REDO_TRAN_LIST', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_TRAN_LIST
        N'PARALLEL_REDO_WORKER_SYNC', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_WORKER_SYNC
        N'PARALLEL_REDO_WORKER_WAIT_WORK', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_WORKER_WAIT_WORK
        N'PREEMPTIVE_XE_GETTARGETSTATE', -- https://www.sqlskills.com/help/waits/PREEMPTIVE_XE_GETTARGETSTATE
        N'PWAIT_ALL_COMPONENTS_INITIALIZED', -- https://www.sqlskills.com/help/waits/PWAIT_ALL_COMPONENTS_INITIALIZED
        N'PWAIT_DIRECTLOGCONSUMER_GETNEXT', -- https://www.sqlskills.com/help/waits/PWAIT_DIRECTLOGCONSUMER_GETNEXT
        N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', -- https://www.sqlskills.com/help/waits/QDS_PERSIST_TASK_MAIN_LOOP_SLEEP
        N'QDS_ASYNC_QUEUE', -- https://www.sqlskills.com/help/waits/QDS_ASYNC_QUEUE
        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
            -- https://www.sqlskills.com/help/waits/QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP
        N'QDS_SHUTDOWN_QUEUE', -- https://www.sqlskills.com/help/waits/QDS_SHUTDOWN_QUEUE
        N'REDO_THREAD_PENDING_WORK', -- https://www.sqlskills.com/help/waits/REDO_THREAD_PENDING_WORK
        N'REQUEST_FOR_DEADLOCK_SEARCH', -- https://www.sqlskills.com/help/waits/REQUEST_FOR_DEADLOCK_SEARCH
        N'RESOURCE_QUEUE', -- https://www.sqlskills.com/help/waits/RESOURCE_QUEUE
        N'SERVER_IDLE_CHECK', -- https://www.sqlskills.com/help/waits/SERVER_IDLE_CHECK
        N'SLEEP_BPOOL_FLUSH', -- https://www.sqlskills.com/help/waits/SLEEP_BPOOL_FLUSH
        N'SLEEP_DBSTARTUP', -- https://www.sqlskills.com/help/waits/SLEEP_DBSTARTUP
        N'SLEEP_DCOMSTARTUP', -- https://www.sqlskills.com/help/waits/SLEEP_DCOMSTARTUP
        N'SLEEP_MASTERDBREADY', -- https://www.sqlskills.com/help/waits/SLEEP_MASTERDBREADY
        N'SLEEP_MASTERMDREADY', -- https://www.sqlskills.com/help/waits/SLEEP_MASTERMDREADY
        N'SLEEP_MASTERUPGRADED', -- https://www.sqlskills.com/help/waits/SLEEP_MASTERUPGRADED
        N'SLEEP_MSDBSTARTUP', -- https://www.sqlskills.com/help/waits/SLEEP_MSDBSTARTUP
        N'SLEEP_SYSTEMTASK', -- https://www.sqlskills.com/help/waits/SLEEP_SYSTEMTASK
        N'SLEEP_TASK', -- https://www.sqlskills.com/help/waits/SLEEP_TASK
        N'SLEEP_TEMPDBSTARTUP', -- https://www.sqlskills.com/help/waits/SLEEP_TEMPDBSTARTUP
        N'SNI_HTTP_ACCEPT', -- https://www.sqlskills.com/help/waits/SNI_HTTP_ACCEPT
        N'SP_SERVER_DIAGNOSTICS_SLEEP', -- https://www.sqlskills.com/help/waits/SP_SERVER_DIAGNOSTICS_SLEEP
        N'SQLTRACE_BUFFER_FLUSH', -- https://www.sqlskills.com/help/waits/SQLTRACE_BUFFER_FLUSH
        N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', -- https://www.sqlskills.com/help/waits/SQLTRACE_INCREMENTAL_FLUSH_SLEEP
        N'SQLTRACE_WAIT_ENTRIES', -- https://www.sqlskills.com/help/waits/SQLTRACE_WAIT_ENTRIES
        N'WAIT_FOR_RESULTS', -- https://www.sqlskills.com/help/waits/WAIT_FOR_RESULTS
        N'WAITFOR', -- https://www.sqlskills.com/help/waits/WAITFOR
        N'WAITFOR_TASKSHUTDOWN', -- https://www.sqlskills.com/help/waits/WAITFOR_TASKSHUTDOWN
        N'WAIT_XTP_RECOVERY', -- https://www.sqlskills.com/help/waits/WAIT_XTP_RECOVERY
        N'WAIT_XTP_HOST_WAIT', -- https://www.sqlskills.com/help/waits/WAIT_XTP_HOST_WAIT
        N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', -- https://www.sqlskills.com/help/waits/WAIT_XTP_OFFLINE_CKPT_NEW_LOG
        N'WAIT_XTP_CKPT_CLOSE', -- https://www.sqlskills.com/help/waits/WAIT_XTP_CKPT_CLOSE
        N'XE_DISPATCHER_JOIN', -- https://www.sqlskills.com/help/waits/XE_DISPATCHER_JOIN
        N'XE_DISPATCHER_WAIT', -- https://www.sqlskills.com/help/waits/XE_DISPATCHER_WAIT
        N'XE_TIMER_EVENT' -- https://www.sqlskills.com/help/waits/XE_TIMER_EVENT
        )
    AND [waiting_tasks_count] > 0


	;WITH CTE_TOPWAIT AS (
	select w2.wait_type,w2.waiting_tasks_count-w1.waiting_tasks_count as waiting_tasks_count,w2.wait_time_ms-w1.wait_time_ms as wait_time_ms,w2.signal_wait_time_ms-w1.signal_wait_time_ms as signal_wait_time_ms
	 FROM @waitsnap w1
          INNER JOIN @waitsnap  w2 on w1.pass=1 and w2.pass=2 and w1.wait_type=w2.wait_type and w2.waiting_tasks_count>w1.waiting_tasks_count)
		  ,cte_waitssummary as (		  select wait_type, wait_time_ms,wait_time_ms/ 1000.0 AS [WaitS],([wait_time_ms] - [signal_wait_time_ms]) / 1000.0 AS [ResourceS],
		  [signal_wait_time_ms] / 1000.0 AS [SignalS],
     [waiting_tasks_count] AS [WaitCount],
        100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() AS [Percentage],
        ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
		from CTE_TOPWAIT)
		--select * from cte_waitssummary

		--select * into cte_my_waitssummary from cte_waitssummary


		insert into @cte_my_waitssummary
		select * from cte_waitssummary



	--	select * from @waitsnap w1 where w1.pass=1

		select 'Waits over time'
		;WITH [Waits] AS
    (SELECT
        [wait_type],
        [wait_time_ms] / 1000.0 AS [WaitS],
        ([wait_time_ms] - [signal_wait_time_ms]) / 1000.0 AS [ResourceS],
        [signal_wait_time_ms] / 1000.0 AS [SignalS],
        [waiting_tasks_count] AS [WaitCount],
       100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() AS [Percentage],
        ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
    FROM @waitsnap w1 where w1.pass=1
   
    )
SELECT
    MAX ([W1].[wait_type]) AS [WaitType],
    CAST (MAX ([W1].[WaitS]) AS DECIMAL (16,2)) AS [Wait_S],
    CAST (MAX ([W1].[ResourceS]) AS DECIMAL (16,2)) AS [Resource_S],
    CAST (MAX ([W1].[SignalS]) AS DECIMAL (16,2)) AS [Signal_S],
    MAX ([W1].[WaitCount]) AS [WaitCount],
    CAST (MAX ([W1].[Percentage]) AS DECIMAL (5,2)) AS [Percentage],
    CAST ((MAX ([W1].[WaitS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgWait_S],
    CAST ((MAX ([W1].[ResourceS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgRes_S],
    CAST ((MAX ([W1].[SignalS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgSig_S],
    CAST ('https://www.sqlskills.com/help/waits/' + MAX ([W1].[wait_type]) as XML) AS [Help/Info URL]
FROM [Waits] AS [W1]
INNER JOIN [Waits] AS [W2]
    ON [W2].[RowNum] <= [W1].[RowNum]
GROUP BY [W1].[RowNum]
HAVING SUM ([W2].[Percentage]) - MAX( [W1].[Percentage] ) < 95; -- percentage threshold







select 'Monitoring Window Wait Pressure'		
SELECT
    MAX ([W1].[wait_type]) AS [WaitType],
    CAST (MAX ([W1].[WaitS]) AS DECIMAL (16,2)) AS [Wait_S],
    CAST (MAX ([W1].[ResourceS]) AS DECIMAL (16,2)) AS [Resource_S],
    CAST (MAX ([W1].[SignalS]) AS DECIMAL (16,2)) AS [Signal_S],
    MAX ([W1].[WaitCount]) AS [WaitCount],
    CAST (MAX ([W1].[Percentage]) AS DECIMAL (5,2)) AS [Percentage],
    CAST ((MAX ([W1].[WaitS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgWait_S],
    CAST ((MAX ([W1].[ResourceS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgRes_S],
    CAST ((MAX ([W1].[SignalS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgSig_S],
    CAST ('https://www.sqlskills.com/help/waits/' + MAX ([W1].[wait_type]) as XML) AS [Help/Info URL]
FROM @cte_my_waitssummary AS [W1]
INNER JOIN @cte_my_waitssummary AS [W2] ON [W2].[RowNum] <= [W1].[RowNum]
GROUP BY [W1].[RowNum]
HAVING SUM ([W2].[Percentage]) - MAX( [W1].[Percentage] ) < 95; -- percentage threshold

--select *  from @cte_my_waitssummary



			
	insert into #QueryStats ([sql_handle],Pass, SampleTime, statement_start_offset, statement_end_offset, plan_generation_num, plan_handle,execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time,query_hash, query_plan_hash,Points)
SELECT [sql_handle], 2 AS Pass, SYSDATETIMEOFFSET(), statement_start_offset, statement_end_offset, plan_generation_num, plan_handle, execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time, query_hash, query_plan_hash, 0
											FROM sys.dm_exec_query_stats qs
											WHERE qs.last_execution_time >= (DATEADD(MINUTE, -1, SYSDATETIMEOFFSET()));



---collecting file stats for second sample
---collecting file stats for sample
			insert into @FileStats (   Pass , 
			SampleTime , 
			DatabaseID ,  
			FileID ,
        DatabaseName ,
        FileLogicalName  ,
     
        SizeOnDiskMB ,
        io_stall_read_ms  ,
        num_of_reads,
        bytes_read ,
        io_stall_write_ms  ,
        num_of_writes  ,
        bytes_written ,
        PhysicalName  
       )
	     SELECT
        2 AS Pass,
        SYSDATETIMEOFFSET()  AS SampleTime,
        mf.[database_id],
        mf.[file_id],
        DB_NAME(vfs.database_id) AS [db_name],
        mf.name + N' [' + mf.type_desc COLLATE SQL_Latin1_General_CP1_CI_AS + N']' AS file_logical_name ,
        CAST(( ( vfs.size_on_disk_bytes / 1024.0 ) / 1024.0 ) AS INT) AS size_on_disk_mb ,
        vfs.io_stall_read_ms  ,
		vfs.num_of_reads  ,
        vfs.[num_of_bytes_read] ,
        vfs.io_stall_write_ms  ,
       vfs.num_of_writes  ,
       vfs.[num_of_bytes_written]  ,
        mf.physical_name
    FROM sys.dm_io_virtual_file_stats (NULL, NULL) AS vfs
    INNER JOIN @MasterFiles AS mf ON vfs.file_id = mf.file_id
        AND vfs.database_id = mf.database_id
    WHERE vfs.num_of_reads > 0
        OR vfs.num_of_writes > 0;


/*
        Pick the most resource-intensive queries to review. Update the Points field
        in #QueryStats - if a query is in the top 10 for logical reads, CPU time,
        duration, or execution, add 1 to its points.
        */
        WITH qsTop AS (
        SELECT TOP 10 qsNow.ID
        FROM #QueryStats qsNow
          INNER JOIN #QueryStats qsFirst ON qsNow.[sql_handle] = qsFirst.[sql_handle] AND qsNow.statement_start_offset = qsFirst.statement_start_offset AND qsNow.statement_end_offset = qsFirst.statement_end_offset AND qsNow.plan_generation_num = qsFirst.plan_generation_num AND qsNow.plan_handle = qsFirst.plan_handle AND qsFirst.Pass = 1
        WHERE qsNow.total_elapsed_time > qsFirst.total_elapsed_time
            AND qsNow.Pass = 2
            AND qsNow.total_elapsed_time - qsFirst.total_elapsed_time > 1000000 /* Only queries with over 1 second of runtime */
        ORDER BY (qsNow.total_elapsed_time - COALESCE(qsFirst.total_elapsed_time, 0)) DESC)
        UPDATE #QueryStats
            SET Points = Points + 1
            FROM #QueryStats qs
            INNER JOIN qsTop ON qs.ID = qsTop.ID;

			--reads
			WITH qsTop AS (
        SELECT TOP 10 qsNow.ID
        FROM #QueryStats qsNow
          INNER JOIN #QueryStats qsFirst ON qsNow.[sql_handle] = qsFirst.[sql_handle] AND qsNow.statement_start_offset = qsFirst.statement_start_offset AND qsNow.statement_end_offset = qsFirst.statement_end_offset AND qsNow.plan_generation_num = qsFirst.plan_generation_num AND qsNow.plan_handle = qsFirst.plan_handle AND qsFirst.Pass = 1
        WHERE qsNow.total_logical_reads > qsFirst.total_logical_reads
            AND qsNow.Pass = 2
            AND qsNow.total_logical_reads - qsFirst.total_logical_reads > 1000 /* Only queries with over 1000 reads */
        ORDER BY (qsNow.total_logical_reads - COALESCE(qsFirst.total_logical_reads, 0)) DESC)
        UPDATE #QueryStats
            SET Points = Points + 1
            FROM #QueryStats qs
            INNER JOIN qsTop ON qs.ID = qsTop.ID;

			--workertime
        WITH qsTop AS (
        SELECT TOP 10 qsNow.ID
        FROM #QueryStats qsNow
          INNER JOIN #QueryStats qsFirst ON qsNow.[sql_handle] = qsFirst.[sql_handle] AND qsNow.statement_start_offset = qsFirst.statement_start_offset AND qsNow.statement_end_offset = qsFirst.statement_end_offset AND qsNow.plan_generation_num = qsFirst.plan_generation_num AND qsNow.plan_handle = qsFirst.plan_handle AND qsFirst.Pass = 1
        WHERE qsNow.total_worker_time > qsFirst.total_worker_time
            AND qsNow.Pass = 2
            AND qsNow.total_worker_time - qsFirst.total_worker_time > 1000000 /* Only queries with over 1 second of worker time */
        ORDER BY (qsNow.total_worker_time - COALESCE(qsFirst.total_worker_time, 0)) DESC)
        UPDATE #QueryStats
            SET Points = Points + 1
            FROM #QueryStats qs
            INNER JOIN qsTop ON qs.ID = qsTop.ID;

        WITH qsTop AS (
        SELECT TOP 10 qsNow.ID
        FROM #QueryStats qsNow
          INNER JOIN #QueryStats qsFirst ON qsNow.[sql_handle] = qsFirst.[sql_handle] AND qsNow.statement_start_offset = qsFirst.statement_start_offset AND qsNow.statement_end_offset = qsFirst.statement_end_offset AND qsNow.plan_generation_num = qsFirst.plan_generation_num AND qsNow.plan_handle = qsFirst.plan_handle AND qsFirst.Pass = 1
        WHERE qsNow.execution_count > qsFirst.execution_count
            AND qsNow.Pass = 2
            AND (qsNow.total_elapsed_time - qsFirst.total_elapsed_time > 1000000 /* Only queries with over 1 second of runtime */
                OR qsNow.total_logical_reads - qsFirst.total_logical_reads > 1000 /* Only queries with over 1000 reads */
                OR qsNow.total_worker_time - qsFirst.total_worker_time > 1000000 /* Only queries with over 1 second of worker time */)
        ORDER BY (qsNow.execution_count - COALESCE(qsFirst.execution_count, 0)) DESC)
        UPDATE #QueryStats
            SET Points = Points + 1
            FROM #QueryStats qs
            INNER JOIN qsTop ON qs.ID = qsTop.ID;








		--	select * from #QueryStats
		if exists (select 1 from #QueryStats where Points>0)
		begin
			

			 SELECT  'Query Stats', 'Most Resource-Intensive Queries', 
            'Query stats during the sample:' + @LineFeed +
            'Executions: ' + CAST(qsNow.execution_count - (COALESCE(qsFirst.execution_count, 0)) AS NVARCHAR(100)) + @LineFeed +
            'Elapsed Time: ' + CAST(qsNow.total_elapsed_time - (COALESCE(qsFirst.total_elapsed_time, 0)) AS NVARCHAR(100)) + @LineFeed +
            'CPU Time: ' + CAST(qsNow.total_worker_time - (COALESCE(qsFirst.total_worker_time, 0)) AS NVARCHAR(100)) + @LineFeed +
            'Logical Reads: ' + CAST(qsNow.total_logical_reads - (COALESCE(qsFirst.total_logical_reads, 0)) AS NVARCHAR(100)) + @LineFeed +
            'Logical Writes: ' + CAST(qsNow.total_logical_writes - (COALESCE(qsFirst.total_logical_writes, 0)) AS NVARCHAR(100)) + @LineFeed +
            'CLR Time: ' + CAST(qsNow.total_clr_time - (COALESCE(qsFirst.total_clr_time, 0)) AS NVARCHAR(100)) + @LineFeed +
            @LineFeed + @LineFeed + 'Query stats since ' + CONVERT(NVARCHAR(100), qsNow.creation_time ,121) + @LineFeed +
            'Executions: ' + CAST(qsNow.execution_count AS NVARCHAR(100)) +
                    CASE qsTotal.execution_count WHEN 0 THEN '' ELSE (' - Percent of Server Total: ' + CAST(CAST(100.0 * qsNow.execution_count / qsTotal.execution_count AS DECIMAL(6,2)) AS NVARCHAR(100)) + '%') END + @LineFeed +
            'Elapsed Time: ' + CAST(qsNow.total_elapsed_time AS NVARCHAR(100)) +
                    CASE qsTotal.total_elapsed_time WHEN 0 THEN '' ELSE (' - Percent of Server Total: ' + CAST(CAST(100.0 * qsNow.total_elapsed_time / qsTotal.total_elapsed_time AS DECIMAL(6,2)) AS NVARCHAR(100)) + '%') END + @LineFeed +
            'CPU Time: ' + CAST(qsNow.total_worker_time AS NVARCHAR(100)) +
                    CASE qsTotal.total_worker_time WHEN 0 THEN '' ELSE (' - Percent of Server Total: ' + CAST(CAST(100.0 * qsNow.total_worker_time / qsTotal.total_worker_time AS DECIMAL(6,2)) AS NVARCHAR(100)) + '%') END + @LineFeed +
            'Logical Reads: ' + CAST(qsNow.total_logical_reads AS NVARCHAR(100)) +
                    CASE qsTotal.total_logical_reads WHEN 0 THEN '' ELSE (' - Percent of Server Total: ' + CAST(CAST(100.0 * qsNow.total_logical_reads / qsTotal.total_logical_reads AS DECIMAL(6,2)) AS NVARCHAR(100)) + '%') END + @LineFeed +
            'Logical Writes: ' + CAST(qsNow.total_logical_writes AS NVARCHAR(100)) +
                    CASE qsTotal.total_logical_writes WHEN 0 THEN '' ELSE (' - Percent of Server Total: ' + CAST(CAST(100.0 * qsNow.total_logical_writes / qsTotal.total_logical_writes AS DECIMAL(6,2)) AS NVARCHAR(100)) + '%') END + @LineFeed +
            'CLR Time: ' + CAST(qsNow.total_clr_time AS NVARCHAR(100)) +
                    CASE qsTotal.total_clr_time WHEN 0 THEN '' ELSE (' - Percent of Server Total: ' + CAST(CAST(100.0 * qsNow.total_clr_time / qsTotal.total_clr_time AS DECIMAL(6,2)) AS NVARCHAR(100)) + '%') END + @LineFeed +
            --@LineFeed + @LineFeed + 'Query hash: ' + CAST(qsNow.query_hash AS NVARCHAR(100)) + @LineFeed +
            --@LineFeed + @LineFeed + 'Query plan hash: ' + CAST(qsNow.query_plan_hash AS NVARCHAR(100)) +
            char(10)+char(12) AS Details,
          --  'See the URL for tuning tips on why this query may be consuming resources.' AS HowToStopIt,
            qp.query_plan,
            QueryText = SUBSTRING(st.text,
                 (qsNow.statement_start_offset / 2) + 1,
                 ((CASE qsNow.statement_end_offset
                   WHEN -1 THEN DATALENGTH(st.text)
                   ELSE qsNow.statement_end_offset
                   END - qsNow.statement_start_offset) / 2) + 1),
            qsNow.ID AS QueryStatsNowID,
            qsFirst.ID AS QueryStatsFirstID,
            qsNow.plan_handle AS PlanHandle,
            qsNow.query_hash
			    FROM #QueryStats qsNow
                INNER JOIN #QueryStats qsTotal ON qsTotal.Pass = 0
                LEFT OUTER JOIN #QueryStats qsFirst ON qsNow.[sql_handle] = qsFirst.[sql_handle] AND qsNow.statement_start_offset = qsFirst.statement_start_offset AND qsNow.statement_end_offset = qsFirst.statement_end_offset AND qsNow.plan_generation_num = qsFirst.plan_generation_num AND qsNow.plan_handle = qsFirst.plan_handle AND qsFirst.Pass = 1
                CROSS APPLY sys.dm_exec_sql_text(qsNow.sql_handle) AS st
                CROSS APPLY sys.dm_exec_query_plan(qsNow.plan_handle) AS qp
            WHERE qsNow.Points > 0 AND st.text IS NOT NULL AND qp.query_plan IS NOT NULL;
		end



		---grab a secondset of memory stats....  this should allow Page Life Expectancy to be calculated

		insert into @snapmemory (pass,object_name,counter_name,instance_name,cntr_value)
SELECT  
    2,SUBSTRING ([object_name], CHARINDEX (':', [object_name]) + 1, 30) AS [object_name], 
    LEFT (counter_name, 40) AS counter_name, LEFT (instance_name, 50) AS instance_name, cntr_value   
  FROM sys.dm_os_performance_counters 
  WHERE 
       ([object_name] LIKE '%:Memory Manager%' COLLATE Latin1_General_BIN    and counter_name in ('Memory Grants Pending','Target Server Memory (KB)','Total Server Memory (KB)','Free Memory (KB)'))
         OR ([object_name] LIKE '%:Buffer Manager%' COLLATE Latin1_General_BIN     AND counter_name COLLATE Latin1_General_BIN IN ('Page lookups/sec', 'Page life expectancy', 'Lazy writes/sec', 'Page reads/sec', 'Page writes/sec', 'Checkpoint pages/sec', 'Free pages', 'Total pages', 'Target pages', 'Stolen pages'))

		 
		 
		 


		 SELECT physical_memory_in_use_kb / 1024 AS [Physical Memory In Use (MB)]

,locked_page_allocations_kb / 1024 AS [Locked Page In Memory Allocations (MB)]

,memory_utilization_percentage AS [Memory Utilization Percentage]

,available_commit_limit_kb / 1024 AS [Available Commit Limit (MB)]

,CASE WHEN process_physical_memory_low = 0 THEN 'No Memory Pressure Detected' ELSE 'Memory Low' END AS 'Process Physical Memory'

,CASE WHEN process_virtual_memory_low = 0 THEN 'No Memory Pressure Detected' ELSE 'Memory Low' END AS 'Process Virtual Memory'
,CURRENT_TIMESTAMP AS [Current Date Time]

FROM sys.dm_os_process_memory

OPTION (RECOMPILE);


;with cte_filestats as
(
select fs1.DatabaseName,fs1.SampleTime,fs1.DatabaseID,fs1.fileid,fs1.SizeOnDiskMB,fs2.SizeOnDiskMB as finalsize,fs2.SizeOnDiskMB-fs1.SizeOnDiskMB as SizeDiff,fs2.num_of_reads-fs1.num_of_reads as NumReads,fs2.num_of_writes-fs1.num_of_writes as numwrites,
(fs2.io_stall_read_ms+fs2.io_stall_write_ms)-(fs1.io_stall_read_ms+fs1.io_stall_write_ms) as IO_stall_Diff,fs2.bytes_read-fs1.bytes_read as BytesRead,fs2.bytes_written-fs1.bytes_written as byteswritten

from @FileStats fs1 join @FileStats fs2 on fs1.FileID=fs2.FileID and fs1.DatabaseID=fs2.DatabaseID and fs1.Pass=1 and fs2.pass=2     where (fs2.bytes_written-fs1.bytes_written)>0 or (fs2.bytes_read-fs1.bytes_read )>0
		 --select * from @snapmemory where pass=2
)
select CF.DatabaseID,CF.SampleTime,CF.DatabaseID,CF.FileID,SAF.filename,CF.SizeOnDiskMB,CF.finalsize,CF.SizeDiff,CF.NumReads,CF.numwrites,CF.IO_stall_Diff,CF.BytesRead,CF.byteswritten,convert(decimal(10,2),(convert(float,IO_stall_Diff))/convert(float,(NumReads)+(numwrites))) as avgStallMS from cte_filestats cf JOIN SYS.sysaltfiles SAF ON CF.DatabaseID=SAF.dbid AND CF.FileID=SAF.fileid
		 
		-- 439

		--select * from sys.sysaltfiles
