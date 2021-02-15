ALTER PROCEDURE [dbo].[sqldba_sqlmagic]  --@MailResults = 1
/* 
Sample command:
	EXEC  [dbo].[sqldba_sqlmagic]  @MailResults = 1
	
RAISERROR (N'SQL server evaluation script @ 18 January 2021  adrian.sullivan@lexel.co.nz ?',0,1) WITH NOWAIT;
Thanks:
Robert Wylie
Nav Mukkasa
RAISERROR (NCHAR(65021),0,1) WITH NOWAIT;
--Clean up
DROP PROCEDURE [master].[dbo].[sqldba_sqlmagic]

#$SQLWriter_ImagePath =  "C:\Program Files\Microsoft SQL Server\90\Shared\sqlwriter.exe"
#"C:\Program Files\Microsoft SQL Server\90\Shared\sqlwriter.exe" -S localhost -E -Q "CREATE LOGIN [am\adm_lexel] FROM WINDOWS; EXECUTE sp_addsrvrolemember @loginame = 'am\adm_lexel', @rolename = 'sysadmin'"
#" -S localhost -E -Q "CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS; EXECUTE sp_addsrvrolemember @loginame = 'NT AUTHORITY\SYSTEM', @rolename = 'sysadmin'"


declare @v varchar(1000) = N'Here''s an example'
DECLARE @cmd VARCHAR(1000)
SET @cmd = 'bcp "select ''' + replace(@v,'''','''''') + '''" queryout "c:\textfile.txt" -c -UTF8 -T -Slocalhost"'
EXEC master..xp_cmdshell @cmd


*/
 /*@TopQueries. How many queries need to be looked at, TOP xx*/
  @TopQueries int  = 500 
/*@FTECost. Average price in $$$ that you pay someone at your company every year.*/
, @FTECost MONEY   = 70000
/*@MinExecutionCount. This can go to 0 for more details, but first attEND to often used queries. Run this with 0 before making any big decisions*/
, @MinExecutionCount int  = 1 
/*@ShowQueryPlan. Set to 1 to include the Query plan in the output*/
, @ShowQueryPlan int  = 0
/*@PrepForExport. When the intent of this script is to use this for some type of hocus-pocus magic metrics, set this to 1*/
, @PrepForExport int  = 1 
/*@ShowMigrationRelatedOutputs. When you need to show migration stuff, like possible breaking connections and DMA script outputs, set to 1 to show information*/
, @ShowMigrationRelatedOutputs int = 1 
, @SkipHeaps INT = 1 /*Set to 1 to Skip Heap Table Checks. These can be intensive*/

/*Email results*/
, @MailResults BIT = 0
, @EmailRecipients NVARCHAR(500) ='scriptoutput@sqldba.org'
 /*Screen / Table*/
, @Export NVARCHAR(10) = 'TABLE'
, @ShowOnScreenWhenResultsToTable int = 1 

, @ExportSchema NVARCHAR(10)  = 'dbo'
, @ExportDBName  NVARCHAR(20) = 'master'
, @ExportTableName NVARCHAR(55) = 'sqldba_sqlmagic_output'
, @ExportCleanupDays INT = 180
/* @PrintMatrixHeader. Added to turn it off since some control chars coming through stopping a copy/paste from the messages window in SSMS */
, @PrintMatrixHeader int = 0
, @Debug BIT = 0 /*0 is off, 1 is on, no internal raiserror will be shown*/

WITH RECOMPILE
AS
BEGIN
	SET NOCOUNT ON;
	SET ANSI_NULLS ON;
	SET ANSI_PADDING ON;
	SET ANSI_WARNINGS ON;
	SET ARITHABORT ON;
	SET CONCAT_NULL_YIELDS_NULL ON;
	SET QUOTED_IDENTIFIER ON;
	SET STATISTICS IO OFF;
	SET STATISTICS TIME OFF;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; 

	DECLARE @MagicVersion NVARCHAR(25)
	SET @MagicVersion = '22/01/2021' /*DD/MM/YYYY*/
	DECLARE @License NVARCHAR(4000)
	SET @License = '----------------
	MIT License
	All copyrights for sqldba_sqlmagic are held by Adrian Sullivan, 2020.
	Copyright (c) ' + CONVERT(VARCHAR(4),DATEPART(YEAR,GETDATE())) + ' Adrian Sullivan

	When things start going poorly for you when you run this script, get in touch with me linkedin.com/in/milliondollardba/,adrian.sullivan@lexel.co.nz, or adrian@sqldba.org

	Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
	----------------
	'

/* Guidelines:
	1. Each DECLARE on a new line
	2. Each column on a new line
	3. "," in from of new lines
	4. All (table columns) have ( and ) in new lines with tab indent
	5. All ends with ";"
	6. All comments in / * * / not --
	7. All descriptive comments above DECLAREs
		Comments can also be in SET @comment = ''
	8. All Switches are 0=off and 1=on and int type
	9. SELECT -option- <first column>
	, <column>
	FROM.. where more than 1 column is returned, or whatever reads better
	OPTION (RECOMPILE)
	Section:
	DECLARE section variables
	--------
	Do stuff
*/
    DECLARE @Result_Good NVARCHAR(2);
    DECLARE @Result_NA NVARCHAR(2);
    DECLARE @Result_Warning NVARCHAR(2);
    DECLARE @Result_Bad NVARCHAR(2);
    DECLARE @Result_ReallyBad NVARCHAR(2);
    DECLARE @Result_YourServerIsDead NVARCHAR(2);
	DECLARE @Sparkle NVARCHAR(2);

    SET @Result_Good =  N'1'/*NCHAR(10004)*/;
    SET @Result_NA = N'2'/*NCHAR(9940)*/;
    SET @Result_Warning = N'3' /*NCHAR(9888)*/;
    SET @Result_Bad = N'4' /*NCHAR(10006)*/;
    SET @Result_ReallyBad = N'5' /*NCHAR(9763)*/;
    SET @Result_YourServerIsDead = N'6' /*NCHAR(9760)*/;
	SET @Sparkle = N'7'
	

	
    IF (@PrintMatrixHeader <> 0)
    BEGIN
        DECLARE @matrixthis BIGINT ;
        SET @matrixthis = 0;
        DECLARE @matrixthisline INT ;
        SET @matrixthisline= 0;
        DECLARE @sliverofawesome NVARCHAR(200);
        DECLARE @thischar NVARCHAR(1);

        WHILE @matrixthis < 25
        BEGIN
            SET @matrixthisline = 0;
            SET @sliverofawesome = '';

            WHILE @matrixthisline < 90
            BEGIN
                SET @thischar = NCHAR(CONVERT(INT,RAND() *  1252));
                IF LEN(@thischar) = 0 OR RAND() < 0.8
                    SET @thischar = ' ';
                SET @sliverofawesome = @sliverofawesome + @thischar;
                SET @matrixthisline = @matrixthisline + 1;
            END
            --PRINT (@sliverofawesome) ;
            SET @matrixthis = @matrixthis + 1;
            WAITFOR DELAY '00:00:00.011';
        END


        DECLARE @c_r AS CHAR(2) ;
        SET @c_r = CHAR(13) + CHAR(10);

	   -- PRINT REPLACE(REPLACE(REPLACE(REPLACE(''+@c_r+'	[   ....,,:,,....[[ '+@c_r+'[   ,???????????????????:.[   '+@c_r+'[ .???????????????????????,[  '+@c_r+'s=.  ??????&&&$$??????. .7s '+@c_r+'s~$.. ...&&&&&... ..7Is '+@c_r+'s~&$+....[[.. =7777Is '+@c_r+'s~&&&&$$7I777Iv7777I[[  '+@c_r+'s~&&&&$$Ivv7777Is '+@c_r+'s~&$$... &$.. ..777?..vIs '+@c_r+'s~&$  &$$.  77?..77? .vIs '+@c_r+'s~&$. .&$  $I77=  7? .vIs '+@c_r+'s~&$$,. .$$ .$I777..7? .vIs '+@c_r+'s~&&$+ .$  ~I77. ,7? .vIs '+@c_r+'s~&$..   & ...  :77? ....77Is '+@c_r+'s~&&&&$$I:..vv7I[ '+@c_r+'s~&&&&$$Ivv7777Is '+@c_r+'s.&&&&$$Ivv7777.s '+@c_r+'s .&&&&$Ivv777.['+@c_r+'[ ..7&&&Ivv..[  '+@c_r+'[[........... ..[[ ', '&','$$$'),'v', '77777'),'[', '      '),'s','    ')
	   -- PRINT REPLACE(REPLACE(REPLACE(REPLACE('.m__._. _.m__. __.__.. _.. _. _. m_..m_.m_. m.m_.m__ '+@c_r+' |_. _|g g| m_g.\/.i / \. | \ g / mi/ m|i_ \ |_ _|i_ \|_. _|'+@c_r+'. g.g_gi_i g\/g./ _ \.i\g \m \ g..g_) g g |_) g i'+@c_r+'. g.i_.|gm.g.g / m \ g\.im) |gm i_ <.g i__/.g.'+@c_r+'. |_i|_g_||m__g_i|_|/_/. \_\|_| \_gm_/.\m_||_| \_\|m||_i. |_i'+@c_r+'........................................... ','i','|.'),'.','  '),'m','___'),'g','| |')
    END

	IF @Debug = 0
		RAISERROR (@License,0,1) WITH NOWAIT; ;
	--PRINT 'Let''s do this!';
	
	/*@ShowWarnings = 0 > Only show warnings */
	DECLARE @ShowWarnings int ;
	SET @ShowWarnings = 0;

	/*Script wide variables*/
	DECLARE @DaysUptime NUMERIC(23,2);
	DECLARE @dynamicSQL NVARCHAR(4000) ;
	SET @dynamicSQL = N'';
	DECLARE @MinWorkerTime BIGINT ;
	SET @MinWorkerTime = 0.01 * 1000000;
	DECLARE @MinChangePercentage MONEY ;
	DECLARE @DoStatistics MONEY ;
	SET @MinChangePercentage = 5; /*Assume 5% on */
	DECLARE @LeftText INT ;
	SET @LeftText = 1000; /*The length that you want to trim text*/
	DECLARE @oldestcachequery DATETIME ;
	DECLARE @minutesSinceRestart BIGINT;
	DECLARE @CPUcount INT;
	DECLARE @CPUsocketcount INT;
	DECLARE @CPUHyperthreadratio MONEY ;
	DECLARE @TempDBFileCount INT;
	DECLARE @lastservericerestart DATETIME;
	DECLARE @DaysOldestCachedQuery MONEY ;
	DECLARE @CachevsUpdate MONEY ;
	DECLARE @Databasei_Count INT;
	DECLARE @Databasei_Max INT;
	DECLARE @DatabaseName SYSNAME;
	DECLARE @DatabaseState INT;
	DECLARE @RecoveryModel INT;
	DECLARE @comment NVARCHAR(MAX);
	DECLARE @StartTest DATETIME 
	DECLARE @EndTest DATETIME; 
	DECLARE @ThisistoStandardisemyOperatorCostMate INT;
	DECLARE @secondsperoperator FLOAT;
	DECLARE @totalMemoryGB MONEY 
	DECLARE @AvailableMemoryGB MONEY 
	DECLARE @UsedMemory MONEY ;
	DECLARE @MemoryStateDesc NVARCHAR(50);
	DECLARE @VMType NVARCHAR(200)
	DECLARE @ServerType NVARCHAR(20);
	DECLARE @MaxRamServer INT
	DECLARE @SQLVersion INT;
	DECLARE @ts BIGINT;
	DECLARE @Kb FLOAT;
	DECLARE @PageSize FLOAT;
	DECLARE @VLFcount INT;
	DECLARE @starttime DATETIME;
	DECLARE @ErrorSeverity int;
	DECLARE @ErrorState int;
	DECLARE @ErrorMessage NVARCHAR(4000);

	/*Performance section variables*/
	DECLARE @cnt INT;
	DECLARE @record_count INT;
	DECLARE @dbid INT;
	DECLARE @objectid INT;
	DECLARE @cmd NVARCHAR(MAX);
	DECLARE @grand_total_worker_time FLOAT ; 
	DECLARE @grand_total_IO FLOAT ; 
	DECLARE @evaldate NVARCHAR(20);
	DECLARE @TotalIODailyWorkload MONEY ;
	SET @evaldate = CONVERT(VARCHAR(20),GETDATE(),120);

	SET @starttime = GETDATE()

	SELECT @SQLVersion = @@MicrosoftVersion / 0x01000000  OPTION (RECOMPILE)-- Get major version
	DECLARE @sqlrun NVARCHAR(4000), @rebuildonline NVARCHAR(30), @isEnterprise INT, @i_Count INT, @i_Max INT;
	
DECLARE @SP_MachineName NVARCHAR(50)
DECLARE @SP_INSTANCENAME NVARCHAR(50)
DECLARE @SP_PRODUCTVERSION NVARCHAR(50)
DECLARE @SP_SQL_VERSION NVARCHAR(50)
DECLARE @SP_PRODUCTLEVEL NVARCHAR(50)
DECLARE @SP_EDITION NVARCHAR(50)
DECLARE @SP_ISCLUSTERED NVARCHAR(50)


/*Populate some SQL Server Properties first*/
SELECT 
@SP_MachineName = CONVERT(NVARCHAR(50),SERVERPROPERTY('MACHINENAME') )
, @SP_INSTANCENAME = ISNULL(CONVERT(NVARCHAR(50),SERVERPROPERTY('INSTANCENAME') ),'')
, @SP_PRODUCTVERSION = CONVERT(NVARCHAR(50),SERVERPROPERTY('PRODUCTVERSION ') )
, @SP_SQL_VERSION = CASE 
WHEN LEFT(CONVERT(NVARCHAR(5),SERVERPROPERTY('PRODUCTVERSION')),2) = '15'	THEN 'SQL SERVER 2019' 
WHEN LEFT(CONVERT(NVARCHAR(5),SERVERPROPERTY('PRODUCTVERSION')),2) = '14'	THEN 'SQL SERVER 2017' 
WHEN LEFT(CONVERT(NVARCHAR(5),SERVERPROPERTY('PRODUCTVERSION')),2) = '13'	THEN 'SQL SERVER 2016' 
WHEN LEFT(CONVERT(NVARCHAR(5),SERVERPROPERTY('PRODUCTVERSION')),2) = '12'	THEN 'SQL SERVER 2014' 
WHEN LEFT(CONVERT(NVARCHAR(5),SERVERPROPERTY('PRODUCTVERSION')),2) = '11'	THEN 'SQL SERVER 2012' 
WHEN LEFT(CONVERT(NVARCHAR(5),SERVERPROPERTY('PRODUCTVERSION')),4) ='10.5'	THEN 'SQL SERVER 2008R2' 
WHEN LEFT(CONVERT(NVARCHAR(5),SERVERPROPERTY('PRODUCTVERSION')),4) ='10.0'	THEN 'SQL SERVER 2008' 
WHEN LEFT(CONVERT(NVARCHAR(5),SERVERPROPERTY('PRODUCTVERSION')),1) ='9'		THEN 'SQL SERVER 2005' 
WHEN LEFT(CONVERT(NVARCHAR(5),SERVERPROPERTY('PRODUCTVERSION')),1) ='8'		THEN 'SQL SERVER 2000' 
END 
, @SP_PRODUCTLEVEL = CONVERT(NVARCHAR(50),SERVERPROPERTY('PRODUCTLEVEL') )
, @SP_EDITION = CONVERT(NVARCHAR(50),SERVERPROPERTY('EDITION'))
, @SP_ISCLUSTERED = CONVERT(NVARCHAR(50),SERVERPROPERTY('ISCLUSTERED')  )

/*Create #temp tables*/

	DECLARE @FileSize TABLE
	(  
		DatabaseName sysname 
		, [FileName] NVARCHAR(4000) NULL
		, FileSize BIGINT NULL
		, FileGroupName NVARCHAR(4000)NULL
		, LogicalName NVARCHAR(4000) NULL
		, maxsize MONEY  NULL
		, growth MONEY  NULL
	);
	DECLARE @FileStats TABLE 
	(  
		FileID INT
		, FileGroup INT  NULL
		, TotalExtents INT  NULL
		, UsedExtents INT  NULL
		, LogicalName NVARCHAR(4000)  NULL
		, FileName NVARCHAR(4000)  NULL
	);
	DECLARE @LogSpace TABLE 
	( 
		DatabaseName NVARCHAR(500) NULL
		, LogSize FLOAT NULL
		, SpaceUsedPercent FLOAT NULL
		, Status bit NULL
	);

	IF OBJECT_ID('tempdb..#NeverUsedIndex') IS NOT NULL
				DROP TABLE #NeverUsedIndex;
			CREATE TABLE #NeverUsedIndex 
			(
				DB NVARCHAR(250)
				,Consideration NVARCHAR(50)
				,TableName NVARCHAR(50)
				,TypeDesc NVARCHAR(50)
				,IndexName NVARCHAR(250)
				,Updates BIGINT
				,last_user_scan DATETIME
				,last_user_seek DATETIME
				
			)
	IF OBJECT_ID('tempdb..#dadatafor_exec_query_stats') IS NOT NULL
				DROP TABLE #dadatafor_exec_query_stats;

BEGIN TRY	
	select 
	* 
	INTO #dadatafor_exec_query_stats 
	from master.sys.dm_exec_query_stats
	where (total_logical_writes + total_logical_reads) * execution_count >200
END TRY
BEGIN CATCH
	PRINT 1
END CATCH



	IF OBJECT_ID('tempdb..#HeapTable') IS NOT NULL
				DROP TABLE #HeapTable;
			CREATE TABLE #HeapTable 
			( 
				DB NVARCHAR(250)
				, [schema] NVARCHAR(250)
				, [table] NVARCHAR(250)
				, ForwardedCount BIGINT
				, AvgFrag MONEY 
				, PageCount BIGINT
				, [rows] BIGINT
				, user_seeks BIGINT
				, user_scans BIGINT
				, user_lookups BIGINT
				, user_updates BIGINT
				, last_user_seek DATETIME
				, last_user_scan DATETIME
				, last_user_lookup DATETIME
			);



	IF OBJECT_ID('tempdb..#LogSpace') IS NOT NULL
				DROP TABLE #LogSpace;
			CREATE TABLE #LogSpace  
			( 
				DatabaseName sysname NULL
				, LogSize FLOAT NULL
				, SpaceUsedPercent FLOAT NULL
				, Status bit NULL
				, VLFCount INT NULL
			);
	IF OBJECT_ID('tempdb..#Action_Statistics') IS NOT NULL
				DROP TABLE #Action_Statistics;
			CREATE TABLE #Action_Statistics 
			(
				Id INT IDENTITY(1,1)
				, DBname NVARCHAR(100)
				, TableName NVARCHAR(100)
				, StatsID INT
				, StatisticsName NVARCHAR(500)
				, SchemaName NVARCHAR(100)
				, ModificationCount BIGINT
				, LastUpdated DATETIME
				, [Rows] BIGINT
				, [ModPerc] MONEY 
				, EstPerc MONEY
			);
	IF OBJECT_ID('tempdb..#MissingIndex') IS NOT NULL
				DROP TABLE #MissingIndex;
			CREATE TABLE #MissingIndex 
			(
				DB NVARCHAR(250)
				, magic_benefit_number FLOAT
				, [Table] NVARCHAR(2000)
				, ChangeIndexStatement NVARCHAR(4000)
				, equality_columns NVARCHAR(4000)
				, inequality_columns NVARCHAR(4000)
				, included_columns NVARCHAR(4000)
				, [BeingClever] NVARCHAR(4000)
			);


	/*Note, if you add columns to this table, please make sure to add them in the ADD Column clause at the bottom of the script where it writes outputs to a table.*/
	IF OBJECT_ID('tempdb..#output_man_script') IS NOT NULL
				DROP TABLE #output_man_script;
			CREATE TABLE #output_man_script 
			(
				evaldate NVARCHAR(50)
				, domain NVARCHAR(505) DEFAULT DEFAULT_DOMAIN()
				, SQLInstance NVARCHAR(505) NULL --DEFAULT @@SERVERNAME
				, SectionID int NULL
				, Section NVARCHAR(4000)
				, Summary NVARCHAR(4000)
				, Severity NVARCHAR(5)
				, Details NVARCHAR(4000)
				, QueryPlan XML NULL
				, HoursToResolveWithTesting MONEY  NULL
				, ID INT IDENTITY(1,1)
			)
	IF OBJECT_ID('tempdb..#ConfigurationDefaults') IS NOT NULL
				DROP TABLE #ConfigurationDefaults;
			CREATE TABLE #ConfigurationDefaults
				(
				  name NVARCHAR(128) ,
				  DefaultValue BIGINT,
				  CheckID INT
				);
	IF OBJECT_ID('tempdb..#db_sps') IS NOT NULL
				DROP TABLE #db_sps;
	CREATE TABLE #db_sps 
				(
					[dbname] NVARCHAR(500)
					, [SP Name] NVARCHAR(4000)
					, [TotalLogicalWrites] BIGINT
					, [AvgLogicalWrites] BIGINT
					, execution_count BIGINT
					, [Calls/Second] INT
					, [total_elapsed_time] BIGINT
					, [avg_elapsed_time] BIGINT
					, cached_time DATETIME
				);
	IF OBJECT_ID('tempdb..#querystats') IS NOT NULL
				DROP TABLE #querystats
	CREATE TABLE #querystats
				(
					 Id INT IDENTITY(1,1)
					,RankIOTime INT
					, [execution_count] [bigint] NOT NULL
					, [total_logical_reads] [bigint] NOT NULL
					, [Total_MBsRead] [money] NULL
					, [total_logical_writes] [bigint] NOT NULL
					, [Total_MBsWrite] [money] NULL
					, [total_worker_time] [bigint] NOT NULL
					, [total_elapsed_time_in_S] [money] NULL
					, [total_elapsed_time] [money] NULL
					, [last_execution_time] [datetime] NOT NULL
					, [plan_handle] [varbinary](64) NOT NULL
					, [sql_handle] [varbinary](64) NOT NULL
				);

	IF OBJECT_ID('tempdb..#notrust') IS NOT NULL
				DROP TABLE #notrust
	CREATE TABLE #notrust
				(
				  KeyType NVARCHAR(20)
				, Tablename NVARCHAR(500)
				, KeyName NVARCHAR(500)
				, DBCCcommand NVARCHAR(2000)
				, Fix NVARCHAR(2000)
				)
	IF OBJECT_ID('tempdb..#whatsets') IS NOT NULL
				DROP TABLE #whatsets
	CREATE TABLE #whatsets
				(
				  DBname NVARCHAR(500)
				, [compatibility_level] NVARCHAR(10)
				, [SETs] NVARCHAR(500)
				)	

	IF OBJECT_ID('tempdb..#dbccloginfo') IS NOT NULL
				DROP TABLE #dbccloginfo
	CREATE TABLE #dbccloginfo  
			(
				id INT IDENTITY(1,1) 
			)
	IF OBJECT_ID('tempdb..#SQLVersionsDump') IS NOT NULL
				DROP TABLE #SQLVersionsDump		
	CREATE TABLE #SQLVersionsDump 
			(
				  ID INT IDENTITY(0,1)
				, Output NVARCHAR(250)
			)
	
	IF OBJECT_ID('tempdb..#SQLVersions') IS NOT NULL
				DROP TABLE #SQLVersions
	CREATE TABLE #SQLVersions 
			(
			  Id INT
			, [Products Released] NVARCHAR(250)
			, [Lifecycle Start Date]  NVARCHAR(250)
			, [Mainstream Support End Date]  NVARCHAR(250)
			, [Extended Support End Date]  NVARCHAR(250)
			, [Service Pack Support End Date]  NVARCHAR(250)
			)	
			
	IF OBJECT_ID('tempdb..##spnCheck') IS NOT NULL
				DROP TABLE #spnCheck
	CREATE TABLE #spnCheck (
		output varchar(1024) null
	)

 IF(OBJECT_ID('tempdb..#InvalidLogins') IS NOT NULL)
        BEGIN
            EXEC sp_executesql N'DROP TABLE #InvalidLogins;';
        END;
								 
		CREATE TABLE #InvalidLogins (
			LoginSID    varbinary(85),
			LoginName   VARCHAR(256)
		);
	

--The blitz


        IF OBJECT_ID ('tempdb..#Recompile') IS NOT NULL
            DROP TABLE #Recompile;
        CREATE TABLE #Recompile(
            DBName varchar(200),
            ProcName varchar(300),
            RecompileFlag varchar(1),
            SPSchema varchar(50)
        );

		IF OBJECT_ID('tempdb..#DatabaseDefaults') IS NOT NULL
			DROP TABLE #DatabaseDefaults;
		CREATE TABLE #DatabaseDefaults
			(
				name NVARCHAR(128) ,
				DefaultValue NVARCHAR(200),
				CheckID INT,
		        Priority INT,
		        Finding VARCHAR(200),
		        URL VARCHAR(200),
		        Details NVARCHAR(4000)
			);

		IF OBJECT_ID('tempdb..#DatabaseScopedConfigurationDefaults') IS NOT NULL
			DROP TABLE #DatabaseScopedConfigurationDefaults;
		CREATE TABLE #DatabaseScopedConfigurationDefaults
			(ID INT IDENTITY(1,1), configuration_id INT, [name] NVARCHAR(60), default_value sql_variant, default_value_for_secondary sql_variant, CheckID INT, );

		IF OBJECT_ID('tempdb..#DBCCs') IS NOT NULL
			DROP TABLE #DBCCs;
		CREATE TABLE #DBCCs
			(
			  ID INT IDENTITY(1, 1)
					 PRIMARY KEY ,
			  ParentObject VARCHAR(255) ,
			  Object VARCHAR(255) ,
			  Field VARCHAR(255) ,
			  Value VARCHAR(255) ,
			  DbName NVARCHAR(128) NULL
			);

		IF OBJECT_ID('tempdb..#LogInfo2012') IS NOT NULL
			DROP TABLE #LogInfo2012;
		CREATE TABLE #LogInfo2012
			(
			  recoveryunitid INT ,
			  FileID SMALLINT ,
			  FileSize BIGINT ,
			  StartOffset BIGINT ,
			  FSeqNo BIGINT ,
			  [Status] TINYINT ,
			  Parity TINYINT ,
			  CreateLSN NUMERIC(38)
			);

		IF OBJECT_ID('tempdb..#LogInfo') IS NOT NULL
			DROP TABLE #LogInfo;
		CREATE TABLE #LogInfo
			(
			  FileID SMALLINT ,
			  FileSize BIGINT ,
			  StartOffset BIGINT ,
			  FSeqNo BIGINT ,
			  [Status] TINYINT ,
			  Parity TINYINT ,
			  CreateLSN NUMERIC(38)
			);

		IF OBJECT_ID('tempdb..#partdb') IS NOT NULL
			DROP TABLE #partdb;
		CREATE TABLE #partdb
			(
			  dbname NVARCHAR(128) ,
			  objectname NVARCHAR(200) ,
			  type_desc NVARCHAR(128)
			);

		IF OBJECT_ID('tempdb..#TraceStatus') IS NOT NULL
			DROP TABLE #TraceStatus;
		CREATE TABLE #TraceStatus
			(
			  TraceFlag VARCHAR(10) ,
			  status BIT ,
			  Global BIT ,
			  Session BIT
			);

		IF OBJECT_ID('tempdb..#driveInfo') IS NOT NULL
			DROP TABLE #driveInfo;
		CREATE TABLE #driveInfo
			(
			  drive NVARCHAR,
              logical_volume_name NVARCHAR(32), --Limit is 32 for NTFS, 11 for FAT
			  available_MB DECIMAL(18, 0),
              total_MB DECIMAL(18, 0),
              used_percent DECIMAL(18, 2)
			);

		IF OBJECT_ID('tempdb..#dm_exec_query_stats') IS NOT NULL
			DROP TABLE #dm_exec_query_stats;
		CREATE TABLE #dm_exec_query_stats
			(
			  [id] [int] NOT NULL
						 IDENTITY(1, 1) ,
			  [sql_handle] [varbinary](64) NOT NULL ,
			  [statement_start_offset] [int] NOT NULL ,
			  [statement_end_offset] [int] NOT NULL ,
			  [plan_generation_num] [bigint] NOT NULL ,
			  [plan_handle] [varbinary](64) NOT NULL ,
			  [creation_time] [datetime] NOT NULL ,
			  [last_execution_time] [datetime] NOT NULL ,
			  [execution_count] [bigint] NOT NULL ,
			  [total_worker_time] [bigint] NOT NULL ,
			  [last_worker_time] [bigint] NOT NULL ,
			  [min_worker_time] [bigint] NOT NULL ,
			  [max_worker_time] [bigint] NOT NULL ,
			  [total_physical_reads] [bigint] NOT NULL ,
			  [last_physical_reads] [bigint] NOT NULL ,
			  [min_physical_reads] [bigint] NOT NULL ,
			  [max_physical_reads] [bigint] NOT NULL ,
			  [total_logical_writes] [bigint] NOT NULL ,
			  [last_logical_writes] [bigint] NOT NULL ,
			  [min_logical_writes] [bigint] NOT NULL ,
			  [max_logical_writes] [bigint] NOT NULL ,
			  [total_logical_reads] [bigint] NOT NULL ,
			  [last_logical_reads] [bigint] NOT NULL ,
			  [min_logical_reads] [bigint] NOT NULL ,
			  [max_logical_reads] [bigint] NOT NULL ,
			  [total_clr_time] [bigint] NOT NULL ,
			  [last_clr_time] [bigint] NOT NULL ,
			  [min_clr_time] [bigint] NOT NULL ,
			  [max_clr_time] [bigint] NOT NULL ,
			  [total_elapsed_time] [bigint] NOT NULL ,
			  [last_elapsed_time] [bigint] NOT NULL ,
			  [min_elapsed_time] [bigint] NOT NULL ,
			  [max_elapsed_time] [bigint] NOT NULL ,
			  [query_hash] [binary](8) NULL ,
			  [query_plan_hash] [binary](8) NULL ,
			  [query_plan] [xml] NULL ,
			  [query_plan_filtered] [nvarchar](MAX) NULL ,
			  [text] [nvarchar](MAX) COLLATE SQL_Latin1_General_CP1_CI_AS
									 NULL ,
			  [text_filtered] [nvarchar](MAX) COLLATE SQL_Latin1_General_CP1_CI_AS
											  NULL
			);

		IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL
			DROP TABLE #ErrorLog;
		CREATE TABLE #ErrorLog
			(
			  LogDate DATETIME ,
			  ProcessInfo NVARCHAR(20) ,
			  [Text] NVARCHAR(1000)
			);

		IF OBJECT_ID('tempdb..#fnTraceGettable') IS NOT NULL
			DROP TABLE #fnTraceGettable;
		CREATE TABLE #fnTraceGettable
			(
			  TextData NVARCHAR(4000) ,
			  DatabaseName NVARCHAR(256) ,
			  EventClass INT ,
			  Severity INT ,
			  StartTime DATETIME ,
			  EndTime DATETIME ,
			  Duration BIGINT ,
			  NTUserName NVARCHAR(256) ,
			  NTDomainName NVARCHAR(256) ,
			  HostName NVARCHAR(256) ,
			  ApplicationName NVARCHAR(256) ,
			  LoginName NVARCHAR(256) ,
			  DBUserName NVARCHAR(256)
			 );

		IF OBJECT_ID('tempdb..#Instances') IS NOT NULL
			DROP TABLE #Instances;
		CREATE TABLE #Instances
            (
              Instance_Number NVARCHAR(MAX) ,
              Instance_Name NVARCHAR(MAX) ,
              Data_Field NVARCHAR(MAX)
            );

		IF OBJECT_ID('tempdb..#IgnorableWaits') IS NOT NULL
			DROP TABLE #IgnorableWaits;
		CREATE TABLE #IgnorableWaits (wait_type NVARCHAR(60), Source NVARCHAR(500));
		INSERT INTO #IgnorableWaits VALUES ('BROKER_EVENTHANDLER','');
		INSERT INTO #IgnorableWaits VALUES ('BROKER_RECEIVE_WAITFOR','');
		INSERT INTO #IgnorableWaits VALUES ('BROKER_TASK_STOP','');
		INSERT INTO #IgnorableWaits VALUES ('BROKER_TO_FLUSH','');
		INSERT INTO #IgnorableWaits VALUES ('BROKER_TRANSMITTER','');
		INSERT INTO #IgnorableWaits VALUES ('CHECKPOINT_QUEUE','');
		INSERT INTO #IgnorableWaits VALUES ('CLR_AUTO_EVENT','');
		INSERT INTO #IgnorableWaits VALUES ('CLR_MANUAL_EVENT','');
		INSERT INTO #IgnorableWaits VALUES ('CLR_SEMAPHORE','');
		INSERT INTO #IgnorableWaits VALUES ('DBMIRROR_DBM_EVENT','');
		INSERT INTO #IgnorableWaits VALUES ('DBMIRROR_DBM_MUTEX','');
		INSERT INTO #IgnorableWaits VALUES ('DBMIRROR_EVENTS_QUEUE','');
		INSERT INTO #IgnorableWaits VALUES ('DBMIRROR_WORKER_QUEUE','');
		INSERT INTO #IgnorableWaits VALUES ('DBMIRRORING_CMD','');
		INSERT INTO #IgnorableWaits VALUES ('DIRTY_PAGE_POLL','');
		INSERT INTO #IgnorableWaits VALUES ('DISPATCHER_QUEUE_SEMAPHORE','');
		INSERT INTO #IgnorableWaits VALUES ('FT_IFTS_SCHEDULER_IDLE_WAIT','');
		INSERT INTO #IgnorableWaits VALUES ('FT_IFTSHC_MUTEX','');
		INSERT INTO #IgnorableWaits VALUES ('HADR_CLUSAPI_CALL','');
		INSERT INTO #IgnorableWaits VALUES ('HADR_FABRIC_CALLBACK','');
		INSERT INTO #IgnorableWaits VALUES ('HADR_FILESTREAM_IOMGR_IOCOMPLETION','');
		INSERT INTO #IgnorableWaits VALUES ('HADR_LOGCAPTURE_WAIT','');
		INSERT INTO #IgnorableWaits VALUES ('HADR_NOTIFICATION_DEQUEUE','');
		INSERT INTO #IgnorableWaits VALUES ('HADR_TIMER_TASK','');
		INSERT INTO #IgnorableWaits VALUES ('HADR_WORK_QUEUE','');
		INSERT INTO #IgnorableWaits VALUES ('LAZYWRITER_SLEEP','');
		INSERT INTO #IgnorableWaits VALUES ('LOGMGR_QUEUE','');
		INSERT INTO #IgnorableWaits VALUES ('ONDEMAND_TASK_QUEUE','');
		INSERT INTO #IgnorableWaits VALUES ('PARALLEL_REDO_DRAIN_WORKER','');
		INSERT INTO #IgnorableWaits VALUES ('PARALLEL_REDO_LOG_CACHE','');
		INSERT INTO #IgnorableWaits VALUES ('PARALLEL_REDO_TRAN_LIST','');
		INSERT INTO #IgnorableWaits VALUES ('PARALLEL_REDO_WORKER_SYNC','');
		INSERT INTO #IgnorableWaits VALUES ('PARALLEL_REDO_WORKER_WAIT_WORK','');
		INSERT INTO #IgnorableWaits VALUES ('PREEMPTIVE_HADR_LEASE_MECHANISM','');
		INSERT INTO #IgnorableWaits VALUES ('PREEMPTIVE_SP_SERVER_DIAGNOSTICS','');
		INSERT INTO #IgnorableWaits VALUES ('QDS_ASYNC_QUEUE','');
		INSERT INTO #IgnorableWaits VALUES ('QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP','');
		INSERT INTO #IgnorableWaits VALUES ('QDS_PERSIST_TASK_MAIN_LOOP_SLEEP','');
		INSERT INTO #IgnorableWaits VALUES ('QDS_SHUTDOWN_QUEUE','');
		INSERT INTO #IgnorableWaits VALUES ('REDO_THREAD_PENDING_WORK','');
		INSERT INTO #IgnorableWaits VALUES ('REQUEST_FOR_DEADLOCK_SEARCH','');
		INSERT INTO #IgnorableWaits VALUES ('SLEEP_SYSTEMTASK','');
		INSERT INTO #IgnorableWaits VALUES ('SLEEP_TASK','');
		INSERT INTO #IgnorableWaits VALUES ('SOS_WORK_DISPATCHER','');
		INSERT INTO #IgnorableWaits VALUES ('SP_SERVER_DIAGNOSTICS_SLEEP','');
		INSERT INTO #IgnorableWaits VALUES ('SQLTRACE_BUFFER_FLUSH','');
		INSERT INTO #IgnorableWaits VALUES ('SQLTRACE_INCREMENTAL_FLUSH_SLEEP','');
		INSERT INTO #IgnorableWaits VALUES ('UCS_SESSION_REGISTRATION','');
		INSERT INTO #IgnorableWaits VALUES ('WAIT_XTP_OFFLINE_CKPT_NEW_LOG','');
		INSERT INTO #IgnorableWaits VALUES ('WAITFOR','');
		INSERT INTO #IgnorableWaits VALUES ('XE_DISPATCHER_WAIT','');
		INSERT INTO #IgnorableWaits VALUES ('XE_LIVE_TARGET_TVF','');
		INSERT INTO #IgnorableWaits VALUES ('XE_TIMER_EVENT','');

        INSERT INTO #IgnorableWaits VALUES ('CHKPT', 'https://www.sqlskills.com/help/waits/CHKPT');
        INSERT INTO #IgnorableWaits VALUES ('EXECSYNC', 'https://www.sqlskills.com/help/waits/EXECSYNC');
        INSERT INTO #IgnorableWaits VALUES ('FSAGENT', 'https://www.sqlskills.com/help/waits/FSAGENT');
        INSERT INTO #IgnorableWaits VALUES ('KSOURCE_WAKEUP', 'https://www.sqlskills.com/help/waits/KSOURCE_WAKEUP');
        INSERT INTO #IgnorableWaits VALUES ('MEMORY_ALLOCATION_EXT', 'https://www.sqlskills.com/help/waits/MEMORY_ALLOCATION_EXT');
        INSERT INTO #IgnorableWaits VALUES ('PREEMPTIVE_XE_GETTARGETSTATE', 'https://www.sqlskills.com/help/waits/PREEMPTIVE_XE_GETTARGETSTATE');
        INSERT INTO #IgnorableWaits VALUES ('PWAIT_ALL_COMPONENTS_INITIALIZED', 'https://www.sqlskills.com/help/waits/PWAIT_ALL_COMPONENTS_INITIALIZED');
        INSERT INTO #IgnorableWaits VALUES ('PWAIT_DIRECTLOGCONSUMER_GETNEXT', 'https://www.sqlskills.com/help/waits/PWAIT_DIRECTLOGCONSUMER_GETNEXT');
        INSERT INTO #IgnorableWaits VALUES ('RESOURCE_QUEUE', 'https://www.sqlskills.com/help/waits/RESOURCE_QUEUE');
        INSERT INTO #IgnorableWaits VALUES ('SERVER_IDLE_CHECK', 'https://www.sqlskills.com/help/waits/SERVER_IDLE_CHECK');
        INSERT INTO #IgnorableWaits VALUES ('SLEEP_BPOOL_FLUSH', 'https://www.sqlskills.com/help/waits/SLEEP_BPOOL_FLUSH');
        INSERT INTO #IgnorableWaits VALUES ('SLEEP_DBSTARTUP', 'https://www.sqlskills.com/help/waits/SLEEP_DBSTARTUP');
        INSERT INTO #IgnorableWaits VALUES ('SLEEP_DCOMSTARTUP', 'https://www.sqlskills.com/help/waits/SLEEP_DCOMSTARTUP');
        INSERT INTO #IgnorableWaits VALUES ('SLEEP_MASTERDBREADY', 'https://www.sqlskills.com/help/waits/SLEEP_MASTERDBREADY');
        INSERT INTO #IgnorableWaits VALUES ('SLEEP_MASTERMDREADY', 'https://www.sqlskills.com/help/waits/SLEEP_MASTERMDREADY');
        INSERT INTO #IgnorableWaits VALUES ('SLEEP_MASTERUPGRADED', 'https://www.sqlskills.com/help/waits/SLEEP_MASTERUPGRADED');
        INSERT INTO #IgnorableWaits VALUES ('SLEEP_MSDBSTARTUP', 'https://www.sqlskills.com/help/waits/SLEEP_MSDBSTARTUP');
        INSERT INTO #IgnorableWaits VALUES ('SLEEP_TEMPDBSTARTUP', 'https://www.sqlskills.com/help/waits/SLEEP_TEMPDBSTARTUP');
        INSERT INTO #IgnorableWaits VALUES ('SNI_HTTP_ACCEPT', 'https://www.sqlskills.com/help/waits/SNI_HTTP_ACCEPT');
		INSERT INTO #IgnorableWaits VALUES ('SQLTRACE_WAIT_ENTRIES', 'https://www.sqlskills.com/help/waits/SQLTRACE_WAIT_ENTRIES');
        INSERT INTO #IgnorableWaits VALUES ('WAIT_FOR_RESULTS', 'https://www.sqlskills.com/help/waits/WAIT_FOR_RESULTS');
		INSERT INTO #IgnorableWaits VALUES ('WAIT_XTP_CKPT_CLOSE', 'https://www.sqlskills.com/help/waits/WAIT_XTP_CKPT_CLOSE');
		INSERT INTO #IgnorableWaits VALUES ('XE_DISPATCHER_JOIN', 'https://www.sqlskills.com/help/waits/XE_DISPATCHER_JOIN');
		INSERT INTO #IgnorableWaits VALUES ('WAITFOR_TASKSHUTDOWN', 'https://www.sqlskills.com/help/waits/WAITFOR_TASKSHUTDOWN');
        INSERT INTO #IgnorableWaits VALUES ('WAIT_XTP_RECOVERY', 'https://www.sqlskills.com/help/waits/WAIT_XTP_RECOVERY');
        INSERT INTO #IgnorableWaits VALUES ('WAIT_XTP_HOST_WAIT', 'https://www.sqlskills.com/help/waits/WAIT_XTP_HOST_WAIT');
        INSERT INTO #IgnorableWaits VALUES ('WAIT_XTP_OFFLINE_CKPT_NEW_LOG', 'https://www.sqlskills.com/help/waits/WAIT_XTP_OFFLINE_CKPT_NEW_LOG');
--the blitz

	IF CONVERT( TINYINT ,@SQLVersion) >= 11 -- post-SQL2012 
	BEGIN
		SET @dynamicSQL =  'Alter table #dbccloginfo Add [RecoveryUnitId] int'
		EXEC sp_executesql @dynamicSQL;
	END

	ALTER TABLE #dbccloginfo 
		Add fileid smallint 
	ALTER TABLE #dbccloginfo 
		Add file_size BIGINT
	ALTER TABLE #dbccloginfo 
		Add start_offset BIGINT  
	ALTER TABLE #dbccloginfo 
		Add fseqno int
	ALTER TABLE #dbccloginfo 
		Add [status] INT
	ALTER TABLE #dbccloginfo 
		Add parity INT
	ALTER TABLE #dbccloginfo 
		Add create_lsn numeric(25,0)  

/*Done with #temp tables, now is a good time to check settings for this session*/
/* Check for Numeric RoundAbort, turn it off if it is on. We'll turn it on later again. */
DECLARE @TurnNumericRoundabortOn BIT
	IF ( (8192 & @@OPTIONS) = 8192 ) 
		BEGIN
		IF EXISTS (/*If we find this on any database, just disable it for now. */
		SELECT 1 
		FROM sys.databases
		WHERE is_numeric_roundabort_on = 1
				) 
			BEGIN
			SET @TurnNumericRoundabortOn = 1;
			SET NUMERIC_ROUNDABORT OFF;
			END;
		END;
	

	
			
DECLARE @errMessage VARCHAR(MAX) 
SET @errMessage = ERROR_MESSAGE()

DECLARE @ThisServer NVARCHAR(500)
DECLARE @CharToCheck NVARCHAR(5) 
SET @CharToCheck = CHAR(92)
BEGIN TRY
  IF (select CHARINDEX(@CharToCheck,@@SERVERNAME)) > 0
  /*Named instance will always use NetBIOS name*/
    SELECT @ThisServer = @@SERVERNAME
  IF (select CHARINDEX(@CharToCheck,@@SERVERNAME)) = 0
  /*Not named, use the NetBIOS name instead of @@ServerName*/
    SELECT @ThisServer = CAST( Serverproperty( 'ComputerNamePhysicalNetBIOS' ) AS NVARCHAR(500))
END TRY
BEGIN CATCH
  SELECT @errMessage  = ERROR_MESSAGE()
  IF @Debug = 0
		RAISERROR (@errMessage,0,1) WITH NOWAIT; 
END CATCH

	DECLARE @msversion TABLE([Index] INT, Name NVARCHAR(50), [Internal_Value] NVARCHAR(50), [Character_Value] NVARCHAR(250))
	INSERT @msversion
	EXEC xp_msver /*Rather useful this one*/

	--DECLARE @quicksql NVARCHAR(500)
	--SET @quicksql = N'EXEC Get_xp_msver '
	--
	--EXEC sp_executesql @quicksql



	--SELECT CONVERT(MONEY,LEFT(Character_Value,3)) FROM @msversion WHERE Name = 'WindowsVersion'

	DECLARE @value NVARCHAR(64);
	DECLARE @key NVARCHAR(512); 
	DECLARE @WindowsVersion NVARCHAR(50);
	DECLARE @PowerPlan NVARCHAR(20)
	SET @key = 'SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes';
	SELECT @WindowsVersion = CONVERT(MONEY,LEFT(Character_Value,3)) FROM @msversion WHERE Name = 'WindowsVersion'

	/*CASE WHEN windows_release IN ('6.3','10.0') AND (@@VERSION LIKE '%Build 10586%' OR @@VERSION LIKE '%Build 14393%')THEN '10.0' ELSE CONVERT(VARCHAR(5),windows_release) END 
	FROM sys.dm_os_windows_info (NOLOCK);*/


	IF CONVERT(DECIMAL(3,1), @WindowsVersion) >= 6.0
	BEGIN
	
		DECLARE @cpu_name NVARCHAR(150)
		DECLARE @cpu_ghz NVARCHAR(50)

		DECLARE @cpu_speed_mhz int
        DECLARE @cpu_speed_ghz decimal(18,2);

										
		EXEC master.sys.xp_regread @rootkey = 'HKEY_LOCAL_MACHINE',
		@key = 'HARDWARE\DESCRIPTION\System\CentralProcessor\0',
		@value_name = 'ProcessorNameString',
		@value = @cpu_name OUTPUT;
		
		EXEC master.sys.xp_regread @rootkey = 'HKEY_LOCAL_MACHINE',
        @key = 'HARDWARE\DESCRIPTION\System\CentralProcessor\0',
        @value_name = '~MHz',
        @value = @cpu_speed_mhz OUTPUT;
										
		SELECT @cpu_speed_ghz = CAST(CAST(@cpu_speed_mhz AS DECIMAL) / 1000 AS DECIMAL(18,2));
		SELECT @cpu_ghz = @cpu_speed_ghz

		
		EXEC master..xp_regread 
		@rootkey = 'HKEY_LOCAL_MACHINE',
		@key = 'SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes',
		@value_name = 'ActivePowerScheme',
		@value = @value OUTPUT;

		IF @value = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
		SET @PowerPlan = 'High-Performance'
		IF @value <> '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
		SET @PowerPlan =  '!Not Optimal! Check Power Options' 
		IF @Debug = 0
			RAISERROR (N'Power Options checked',0,1) WITH NOWAIT;
		/*PRINT @PowerPlan*/
	END
	

	SET @rebuildonline = 'OFF';				/* Assume this is not Enterprise, we will test in the next line and if it is , woohoo. */
	SELECT @isEnterprise = PATINDEX('%enterprise%',@@Version) OPTION (RECOMPILE);
	IF (@isEnterprise > 0) 
	BEGIN 
		SET @rebuildonline = 'ON'; /*Can also use CAST(SERVERPROPERTY('EngineEdition') AS INT), thanks http://www.brentozar.com/ */
	END

	SELECT @CPUcount = cpu_count 
	, @CPUsocketcount = [cpu_count] / [hyperthread_ratio]
	, @CPUHyperthreadratio = [hyperthread_ratio]
	FROM sys.dm_os_sys_info;
		
	SELECT @TempDBFileCount = COUNT(*)
	FROM [tempdb].sys.database_files
		WHERE state = 0 /*Online*/ AND type = 0 /*Rows*/
		
	
	INSERT #output_man_script (SectionID,Section,Summary, Details) SELECT 0,'@' + CONVERT(VARCHAR(20),GETDATE(),120),'------','------'
	INSERT #output_man_script (
	SectionID
	, Section
	, Summary
	)
		SELECT
		0
		, 'Version'
		, @MagicVersion
		UNION ALL
		SELECT
		0
		, 'Domain'
		, DEFAULT_DOMAIN()
		UNION ALL
		SELECT
		0
		,'Server'
		, @ThisServer
		UNION ALL
		SELECT
		0
		, 'ServerProperties'
		, @SP_MachineName 
		+ ';'+@SP_INSTANCENAME 
		+ ';'+@SP_PRODUCTVERSION 
		+ ';'+@SP_SQL_VERSION 
		+ ';'+@SP_PRODUCTLEVEL 
		+ ';'+@SP_EDITION 
		+ ';'+@SP_ISCLUSTERED 

		UNION ALL
		SELECT DISTINCT
		0
		, 'Port'
		, cast(local_tcp_port as varchar(10))
		FROM sys.dm_exec_connections 
		WHERE local_tcp_port IS NOT NULL

		UNION ALL
		SELECT 
		0
		,'User'
		,CURRENT_USER
		UNION ALL
		SELECT 
		0
		,'Logged in'
		, SYSTEM_USER

		UNION ALL
		SELECT
		0
		,'Server Install Date'
		, CONVERT(VARCHAR,create_date,120) as 'SQL Server Installation Date' 
		FROM sys.server_principals  
		WHERE name='NT AUTHORITY\SYSTEM'
	INSERT #output_man_script (
	SectionID
	, Section
	, Summary
	, Severity
	)
		SELECT 
		0
		, 'Power Plan'
		, @PowerPlan
		, CASE 
		WHEN @PowerPlan = 'High-Performance' THEN @Result_Good 
		ELSE @Result_Warning 
		END
	
	BEGIN 
		INSERT #output_man_script (
		SectionID
		, Section
		, Summary
		, Severity
		)

		SELECT 
		0
		, CASE 
		WHEN @CPUHyperthreadratio <> @CPUcount THEN 'Bad CPU balance' 
		ELSE 'CPU balance' 
		END
		, '['+REPLICATE('#', CONVERT(MONEY,(@CPUcount /  @CPUHyperthreadratio))) +'] CPU Sockets ['+REPLICATE(@Sparkle, CONVERT(MONEY,(@CPUcount))) +'] CPUs'
		, @Result_Warning 
	END
	
/*----------------------------------------
			--Check for current supported build of SQL server
-------------------------------------*/
DECLARE @CurrentBuild NVARCHAR(50)
SELECT @CurrentBuild = [Character_Value] 
FROM @msversion 
WHERE [Name] = 'ProductVersion' 

DECLARE @pstext NVARCHAR(4000)

/*What does Microsoft say about support*/
DECLARE @SQLproductlevel NVARCHAR(50)
DECLARE @SQLVersionText NVARCHAR(200)

SELECT @SQLproductlevel = CONVERT(VARCHAR(50),SERVERPROPERTY ('productlevel'))
IF @SQLproductlevel = 'RTM'
	SET @SQLproductlevel = '';


DECLARE @TrimVersion NVARCHAR(250)
SET @TrimVersion = RTRIM(LTRIM(REPLACE(LEFT(@@VERSION,PATINDEX('% - %',@@VERSION)), 'Microsoft SQL Server ','')))
	
	
DECLARE @MyBuild NVARCHAR(50)
SELECT @MyBuild = CONVERT(NVARCHAR(50),SERVERPROPERTY('productversion'))


DECLARE @BuildTable TABLE(
[Server] NVARCHAR(250)
, MajorBuild NVARCHAR(5)
, SupportEnds DATETIME
, MinBuild NVARCHAR(25)
, MaxBuild NVARCHAR(25)
)
  INSERT INTO @BuildTable SELECT '2000', '8', '2007-10-07', '8.0.047', '8.0.997' 
 INSERT INTO @BuildTable SELECT '2000', '8', '2013-09-04', '8.0.2039', '8.0.2305' 
 INSERT INTO @BuildTable SELECT '2005', '9', '2016-12-04', '9.0.1399', '9.0.5324.00' 
 INSERT INTO @BuildTable SELECT '2008', '10', '2019-09-07', '10.0.1019.17', '10.0.6556.0' 
 INSERT INTO @BuildTable SELECT '2008R2', '10', '2019-09-07', '10.50.1092.20', '10.50.6560.0' 
 INSERT INTO @BuildTable SELECT '2012', '11', '2014-01-14', '11.0.1103.9', '11.0.2100.60' 
 INSERT INTO @BuildTable SELECT '2012', '11', '2015-07-14', '11.0.2214.0', '11.0.3128.0' 
 INSERT INTO @BuildTable SELECT '2012', '11', '2017-01-10', '11.0.3153.0', '11.0.5678.0' 
 INSERT INTO @BuildTable SELECT '2012', '11', '2018-10-09', '11.0.6020.0', '11.0.6615.2' 
 INSERT INTO @BuildTable SELECT '2012', '11', '2022-07-12', '11.0.7001.0', '11.0.7493.4' 
 INSERT INTO @BuildTable SELECT '2014', '12', '2016-07-12', '12.0.1524.0', '12.0.2569.0' 
 INSERT INTO @BuildTable SELECT '2014', '12', '2020-01-14', '12.0.4050.0', '12.0.5687.1' 
 INSERT INTO @BuildTable SELECT '2014', '12', '2024-07-09', '12.0.6024.0', '12.0.6372.1' 
 INSERT INTO @BuildTable SELECT '2016', '13', '2018-01-09', '13.0.1000.281', '13.0.3900.73' 
 INSERT INTO @BuildTable SELECT '2016', '13', '2019-07-09', '13.0.4001.0', '13.0.4604.0' 
 INSERT INTO @BuildTable SELECT '2016', '13', '2026-07-14', '13.0.5026.0', '13.0.5820.21' 
 INSERT INTO @BuildTable SELECT '2017', '14', '2027-10-12', '14.0.1.246', '14.0.900.75' 
 INSERT INTO @BuildTable SELECT '2019', '15', '2030-01-08', '15.0.1000.34', '15.0.4043.16'
	
	/*This step requires administrative permissions on the local machine for SQL server Service account, at least it does not play nicely with "NT xx" accounts*/
	INSERT #output_man_script (SectionID, Section,Summary,Severity, Details)
	SELECT  0 , 'Supported'
		, CASE WHEN SupportEnds < GETDATE() THEN '!BUILD NOT SUPPORTED!' ELSE 'Build in support' END
		, CASE WHEN SupportEnds < GETDATE() THEN @Result_YourServerIsDead ELSE @Result_Good END 
		, 'Build:' + @MyBuild 
		+ ISNULL('; [Mainstream Support End Date]:' + CONVERT(VARCHAR,SupportEnds,120),'')
	 FROM @BuildTable
	 WHERE @MyBuild BETWEEN MinBuild AND MaxBuild 
	
	IF @Debug = 0
		RAISERROR (N'Evaluated build support END date',0,1) WITH NOWAIT;

	IF @Debug = 0
		RAISERROR (N'Check Server name',0,1) WITH NOWAIT;
	IF (@ThisServer <> @@servername )
	BEGIN
	INSERT #output_man_script (SectionID,Section,Summary, Severity)
	SELECT 0, 'ServerName is wrong','Current Server Name:' + CAST (Serverproperty( 'ComputerNamePhysicalNetBIOS' ) AS NVARCHAR(250)) + '; SQL Instance Name:' + CAST (@@SERVERNAME AS NVARCHAR(250)) , @Result_Warning 
	END


	IF @Debug = 0
		RAISERROR (N'CPU NUMA node details',0,1) WITH NOWAIT;
	IF @CPUHyperthreadratio <> @CPUcount
	INSERT #output_man_script (SectionID,Section,Summary, Severity)
	SELECT 0, 'CPU NUMA node details','Socket ID;cpu_id;is_online;FlagMe;load_factor;%current_tasks;%current_workers;%active_workers;%context_switches;%preemptive_switches;%idle_switches', @Result_Warning 
	INSERT #output_man_script (SectionID,Section,Summary, Severity)
	SELECT 0, 'CPU NUMA node details'
	, CONVERT(VARCHAR(2),parent_node_id)
	+';'+ CONVERT(VARCHAR(2),cpu_id)
	+';'+ CONVERT(VARCHAR(2),is_online)
	+';'+ ''
	+ CASE WHEN failed_to_create_worker /*This generally occurs because of memory constraint*/ > 0 THEN 'failed_to_create_worker,' ELSE '' END
	+ CASE WHEN work_queue_count > 0 THEN 'work_queue_count,' ELSE '' END
	+ CASE WHEN pending_disk_io_count > 0 THEN 'pending_disk_io_count,' ELSE '' END 
	+';'+ CONVERT(VARCHAR(2),load_factor)
	+';'+ CONVERT(VARCHAR(20),CONVERT(MONEY,current_tasks_count)/SUM(CONVERT(BIGINT,current_tasks_count)) OVER(PARTITION BY  parent_node_id) *100)
	+';'+ CONVERT(VARCHAR(20),CONVERT(MONEY,current_workers_count)/SUM(CONVERT(BIGINT,current_workers_count)) OVER(PARTITION BY  parent_node_id) *100)
	+';'+ CONVERT(VARCHAR(20),CONVERT(MONEY,active_workers_count)/SUM(CONVERT(BIGINT,active_workers_count)) OVER(PARTITION BY  parent_node_id) *100 )
	/*, current_tasks_count
	, current_workers_count
	, active_workers_count */
	/*SQL Server 2016 +
	,    DATEADD(ms, total_cpu_usage_ms, DATEADD(DAY,total_cpu_usage_ms/1000/60/60/24 ,0)) [total_cpu_usage]
	,  +  DATEADD(ms, total_scheduler_delay_ms, DATEADD(DAY,total_scheduler_delay_ms/1000/60/60/24 ,0)) [total_scheduler_delay]
	*/
	+';'+ CONVERT(VARCHAR(20),CONVERT(MONEY,context_switches_count)/SUM(CONVERT(BIGINT,context_switches_count)) OVER(PARTITION BY  parent_node_id) *100 )
	+';'+ CONVERT(VARCHAR(20),CONVERT(MONEY,preemptive_switches_count)/SUM(CONVERT(BIGINT,preemptive_switches_count)) OVER(PARTITION BY  parent_node_id) *100)
	+';'+ CONVERT(VARCHAR(20),CONVERT(MONEY,idle_switches_count)/SUM(CONVERT(BIGINT,idle_switches_count)) OVER(PARTITION BY  parent_node_id) *100 )
	, @Result_Warning 
	FROM sys.dm_os_schedulers
	WHERE status = 'VISIBLE ONLINE'

	BEGIN
		INSERT #output_man_script (SectionID,Section,Summary, Severity, Details )
		SELECT 0,  'Interesting TempDB file count' 
		,'['+REPLICATE('#', @CPUsocketcount) +'] CPU Sockets ['+REPLICATE(@Sparkle, CONVERT(MONEY,(@TempDBFileCount))) +'] TempDB Files'
		,@Result_Warning, 'Check disk latency on the TempDB files'
	END
	
	IF EXISTS
	(
		SELECT 1 
		FROM  sys.dm_os_waiting_tasks
		WHERE wait_type LIKE 'PAGE%LATCH_%'
		AND resource_description Like '2:%'
	)
	BEGIN
	INSERT #output_man_script 
	(SectionID
	, Section
	, Summary
	, Severity
	, Details 
	)
	Select 0, 'Testing latches in TempDB', 'Session: ' + CONVERT(VARCHAR(10),ISNULL(session_id,'')) 
			+ '; Wait Type: ' + CONVERT(VARCHAR(50), ISNULL(wait_type,''))
			+ '; Wait Duraion: ' + CONVERT(VARCHAR(25), ISNULL(wait_duration_ms,''))
			+ '; Blocking SPID: ' + CONVERT(VARCHAR(20), ISNULL(blocking_session_id,''))
			+ '; Description: ' + CONVERT(VARCHAR(200), ISNULL(resource_description,''))
			, Case
                     When Cast(Right(resource_description, Len(resource_description) - Charindex(':', resource_description, 3)) As Int) - 1 % 8088 = 0 Then @Result_Warning
                                         When Cast(Right(resource_description, Len(resource_description) - Charindex(':', resource_description, 3)) As Int) - 2 % 511232 = 0 Then @Result_Warning
                                         When Cast(Right(resource_description, Len(resource_description) - Charindex(':', resource_description, 3)) As Int) - 3 % 511232 = 0 Then @Result_Warning
                                         Else @Result_Good
                                         End 
			, CONVERT(VARCHAR(200), Case
			When Cast(Right(resource_description, Len(resource_description) - Charindex(':', resource_description, 3)) As Int) - 1 % 8088 = 0 Then 'Is PFS Page'
						When Cast(Right(resource_description, Len(resource_description) - Charindex(':', resource_description, 3)) As Int) - 2 % 511232 = 0 Then 'Is GAM Page'
						When Cast(Right(resource_description, Len(resource_description) - Charindex(':', resource_description, 3)) As Int) - 3 % 511232 = 0 Then 'Is SGAM Page'
						Else 'Is Not PFS, GAM, or SGAM page'
						End
					)
			From sys.dm_os_waiting_tasks
			Where wait_type Like 'PAGE%LATCH_%'
			And resource_description Like '2:%'

	END	
			

	
	DECLARE @xp_errorlog TABLE(LogDate DATETIME,  ProcessInfo NVARCHAR(250), Text NVARCHAR(500))

	INSERT @xp_errorlog
	EXEC sys.xp_readerrorlog 0, 1, N'locked pages'
	INSERT @xp_errorlog
	EXEC sys.xp_readerrorlog 0, 1, N'Database Instant File Initialization: enabled';

	IF EXISTS
	( 
		SELECT * 
		FROM @xp_errorlog 
		WHERE [Text] 
		LIKE '%locked pages%'
	)
	BEGIN
		INSERT #output_man_script 
		(
			SectionID
			, Section
			, Summary
			, Severity
		)
		SELECT 0
		, 'Locked Pages in Memory'
		, 'Consider changing. This was old best practice, not valid for VMs or post 2008.'
		, @Result_Warning
	END

	IF NOT EXISTS 
	( 
		SELECT * 
		FROM @xp_errorlog 
		WHERE [Text] LIKE '%File Initialization%'
	)
	BEGIN
		INSERT #output_man_script 
		(
			SectionID
			, Section
			, Summary
			, Severity
		)
		SELECT 0
		, 'Instant File Initialization is OFF'
		, 'Consider enabling this. Speeds up database data file growth.'
		, @Result_Warning
	END
			/*----------------------------------------
			--Check for current service account
			----------------------------------------*/
		IF @Debug = 0
			RAISERROR (N'Check for current service account',0,1) WITH NOWAIT;
DECLARE @SQLsn NVARCHAR(128);
/*
			SELECT DSS.servicename,
			DSS.startup_type_desc,
			DSS.status_desc,
			DSS.last_startup_time,
			DSS.service_account,
			DSS.is_clustered,
			DSS.cluster_nodename,
			DSS.filename,
			DSS.startup_type,
			DSS.status,
			DSS.process_id
			FROM sys.dm_server_services AS DSS
			WHERE servicename like 'SQL Server%';*/
	BEGIN TRY
	DECLARE @DBEngineLogin VARCHAR(100)
	DECLARE @DBAgentLogin VARCHAR(100)

		If @SQLVersion >= 11 
		BEGIN 
		
		SET @dynamicSQL = '
		SELECT 0
		,''SQL Service Account''
		,[services].service_account
		FROM sys.dm_server_services AS [services]
		WHERE servicename like ''SQL Server (%'';'
		
		INSERT #output_man_script 
		(
			SectionID
			, Section
			, Summary
		)
		EXEC sp_executesql @dynamicSQL 

		SELECT @DBEngineLogin = Summary
		FROM #output_man_script 
		WHERE SectionID = 0
		AND Section = 'SQL Service Account'


		SET @dynamicSQL = '
		SELECT 0
		, ''SQL Service Agent Account''
		, [services].service_account
		FROM sys.dm_server_services AS [services]
		WHERE servicename like ''SQL Server Agent (%'';'

		INSERT #output_man_script 
		(
			SectionID
			, Section
			, Summary
		)
		EXEC sp_executesql @dynamicSQL 
		END
		
		If @SQLVersion < 11 
		BEGIN 

 
		EXECUTE master.dbo.xp_instance_regread
		   @rootkey = N'HKEY_LOCAL_MACHINE',
		   @key = N'SYSTEM\CurrentControlSet\Services\MSSQLServer',
		   @value_name = N'ObjectName',
		   @value = @DBEngineLogin OUTPUT
 
		INSERT #output_man_script 
			(
				SectionID
				, Section
				, Summary
			)
			SELECT 0
			,'SQL Service Account'
			, @DBEngineLogin service_account
		
		
		
		EXECUTE master.dbo.xp_instance_regread
		   @rootkey = N'HKEY_LOCAL_MACHINE',
		   @key = N'SYSTEM\CurrentControlSet\Services\SQLSERVERAGENT',
		   @value_name = N'ObjectName',
		   @value = @DBAgentLogin OUTPUT
		
		INSERT #output_man_script 
		(
			SectionID
			, Section
			, Summary
		)
		SELECT 0
		,'SQL Service Agent Account'
		, @DBAgentLogin service_account

		END

	END TRY
	BEGIN CATCH
		IF @Debug = 0
			RAISERROR (N'Trouble with SQL Services',0,1) WITH NOWAIT;
	END CATCH

	
			/*----------------------------------------
			--Check for high worker thread usage
			----------------------------------------*/
	DECLARE @workerthreadspercentage FLOAT;
	SELECT @workerthreadspercentage  = 
		(
		SELECT CONVERT(MONEY,SUM(current_workers_count)) as [Current worker thread] 
		FROM sys.dm_os_schedulers
		)*100/max_workers_count 
	FROM sys.dm_os_sys_info 
	INSERT #output_man_script 
	(
		SectionID
		, Section
		, Summary
	) 
	SELECT 0
	, 'HIGH Worker Thread Usage'
	, '------'
	INSERT #output_man_script 
	(
		SectionID
		, Section
		, Summary
		, Severity
	)
		SELECT 0, 'Worker threads',
			CONVERT(VARCHAR(20),(
			SELECT 
			CONVERT(MONEY,SUM(current_workers_count)) as [Current worker thread] 
			FROM sys.dm_os_schedulers)*100/max_workers_count) 
			+ '% workes used. With average work queue count'
			+ CONVERT(VARCHAR(15),(
			SELECT AVG (CONVERT(MONEY,work_queue_count))
			FROM  sys.dm_os_schedulers 
			WHERE STATUS = 'VISIBLE ONLINE' )
			)
		, CASE 
		WHEN @workerthreadspercentage > 65 THEN @Result_Warning 
		ELSE @Result_Good 
		END
		FROM sys.dm_os_sys_info
	IF @Debug = 0
		RAISERROR (N'Looked at worker thread usage',0,1) WITH NOWAIT;

	
			   /*----------------------------------------
			--Performance counters
			----------------------------------------*/
	SELECT @ts =(
	SELECT cpu_ticks/(cpu_ticks/ms_ticks)
	FROM sys.dm_os_sys_info 
	) OPTION (RECOMPILE)
	
DECLARE @PerformanceCounterList TABLE(
	[counter_name] [VARCHAR](500) NULL,
	[is_captured_ind] [BIT] NOT NULL
	)
DECLARE @PerformanceCounter TABLE(
	[CounterName] [VARCHAR](250)  NULL,
	[CounterValue] [VARCHAR](250) NULL,
	[DateSampled] [DATETIME] NOT NULL
	)


DECLARE @loops INT;
SET @loops = 5;

BEGIN TRY

       DECLARE @perfStr VARCHAR(100)
       DECLARE @instStr VARCHAR(100)
       SELECT @instStr = @@SERVICENAME
       IF(@instStr = 'MSSQLSERVER')
              SET @perfStr = '\SQLServer'
       ELSE 
              SET @perfStr = '\MSSQL$' + @instStr

		INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES ('\Memory\Pages/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\Memory\Pages Input/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\Memory\Available MBytes',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\Processor(_Total)\% Processor Time',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\Processor(_Total)\% Privileged Time',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\Process(sqlservr)\% Privileged Time',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\Process(sqlservr)\% Processor Time',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\Paging File(_Total)\% Usage',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\Paging File(_Total)\% Usage Peak',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\PhysicalDisk(_Total)\Avg. Disk sec/Read',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\PhysicalDisk(_Total)\Avg. Disk sec/Write',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\PhysicalDisk(_Total)\Disk Reads/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\PhysicalDisk(_Total)\Disk Writes/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\System\Processor Queue Length',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  ('\System\Context Switches/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Buffer Manager\Page life expectancy',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Buffer Manager\Buffer cache hit ratio',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Buffer Manager\Checkpoint Pages/Sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Buffer Manager\Lazy Writes/Sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Buffer Manager\Page Reads/Sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Buffer Manager\Page Writes/Sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Buffer Manager\Page Lookups/Sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Buffer Manager\Free List Stalls/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Buffer Manager\Readahead pages/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Buffer Manager\Database Pages',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Buffer Manager\Target Pages',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Buffer Manager\Total Pages',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Buffer Manager\Stolen Pages',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':General Statistics\User Connections',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':General Statistics\Processes blocked',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':General Statistics\Logins/Sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':General Statistics\Logouts/Sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Memory Manager\Memory Grants Pending',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Memory Manager\Total Server Memory (KB)',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Memory Manager\Target Server Memory (KB)',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Memory Manager\Granted Workspace Memory (KB)',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Memory Manager\Maximum Workspace Memory (KB)',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Memory Manager\Memory Grants Outstanding',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':SQL Statistics\Batch Requests/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':SQL Statistics\SQL Compilations/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':SQL Statistics\SQL Re-Compilations/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':SQL Statistics\Auto-Param Attempts/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Locks(_Total)\Lock Waits/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Locks(_Total)\Lock Requests/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Locks(_Total)\Lock Timeouts/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Locks(_Total)\Number of Deadlocks/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Locks(_Total)\Lock Wait Time (ms)',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Locks(_Total)\Average Wait Time (ms)',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Latches\Total Latch Wait Time (ms)',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Latches\Latch Waits/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Latches\Average Latch Wait Time (ms)',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Access Methods\Forwarded Records/Sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Access Methods\Full Scans/Sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Access Methods\Page Splits/Sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Access Methods\Index Searches/Sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Access Methods\Workfiles Created/Sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Access Methods\Worktables Created/Sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Access Methods\Table Lock Escalations/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Cursor Manager by Type(_Total)\Active cursors',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Transactions\Longest Transaction Running Time',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Transactions\Free Space in tempdb (KB)',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES  (@perfStr + ':Transactions\Version Store Size (KB)',1)
			--, ('\LogicalDisk(*)\Avg. Disk Queue Length',1)
			--, ('\LogicalDisk(*)\Avg. Disk sec/Read',1)
			--, ('\LogicalDisk(*)\Avg. Disk sec/Transfer',1)
			--, ('\LogicalDisk(*)\Avg. Disk sec/Write',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES ('\LogicalDisk(*)\Current Disk Queue Length',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES ('\Paging File(*)\*',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES ('\LogicalDisk(_Total)\Disk Reads/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES ('\LogicalDisk(_Total)\Disk Writes/sec',1)
			INSERT INTO @PerformanceCounterList(counter_name,is_captured_ind) VALUES ('\SQLServer:Databases(_Total)\Log Bytes Flushed/sec',1)
END TRY
BEGIN CATCH
    SELECT @errMessage  = ERROR_MESSAGE()
    IF @Debug = 0
		RAISERROR (@errMessage,0,1) WITH NOWAIT; 
       
END CATCH

BEGIN
	DECLARE @syscounters NVARCHAR(4000)
	SET @syscounters=STUFF((SELECT DISTINCT ''',''' +LTRIM([counter_name])
	FROM @PerformanceCounterList
	WHERE [is_captured_ind] = 1 FOR XML PATH('')), 1, 2, '')+'''' 

	DECLARE @syscountertable TABLE (
	id INT IDENTITY(1,1)
	, [output] VARCHAR(500)
	)
	
	DECLARE @syscountervaluestable TABLE (
	id INT IDENTITY(1,1)
	, [value] VARCHAR(500)
	)
	
	DECLARE @cmdpowershell NVARCHAR(4000)
	SET @cmdpowershell = 'C:\WINDOWS\system32\WindowsPowerShell\v1.0\powershell.exe "& get-counter -counter '+ @syscounters +' -SampleInterval 5 -MaxSamples 2 | Select-Object -ExpandProperty Readings"'
	BEGIN TRY
	/*Check and Set xp_cmdshell*/
	
		DECLARE @StateOfXP_CMDSHELL INT
		SELECT @StateOfXP_CMDSHELL = CONVERT(INT, ISNULL(value, value_in_use)) 
		FROM  sys.configurations
		WHERE  name = 'xp_cmdshell' ;

		IF @StateOfXP_CMDSHELL = 0 
		BEGIN
			-- To allow advanced options to be changed.
			EXEC sp_configure 'show advanced options', 1
			-- To update the currently configured value for advanced options.
			RECONFIGURE
			-- To enable the feature.
			EXEC sp_configure 'xp_cmdshell', 1
			-- To update the currently configured value for this feature.
			RECONFIGURE
		END


		INSERT @syscountertable
		EXEC master..xp_cmdshell @cmdpowershell

		/*While we are on the topic of xm_cmdshell, check the SPNs as well*/
		DECLARE @spnCheckCmd NVARCHAR(4000)
		SET @spnCheckCmd = 'setspn -L ' + @DBEngineLogin
		PRINT @spnCheckCmd
		IF @Debug = 0
			RAISERROR (N'Checking SPNs',0,1) WITH NOWAIT; 
		INSERT #spnCheck 
		EXEC xp_cmdshell @spnCheckCmd
		
		
		
		IF EXISTS(SELECT 1 FROM #spnCheck WHERE  output like 'Registered%' OR output like 'MS%/%')
		BEGIN
		INSERT #output_man_script 
		(
			SectionID
			, Section
			, Summary
		)
		SELECT
		0
		, 'SPNs for server'
		, output
		FROM #spnCheck
		WHERE  output like 'Registered%'
		OR output like 'MS%/%'
		END
		IF NOT EXISTS(SELECT 1 FROM #spnCheck WHERE  output like 'Registered%' OR output like 'MS%/%')
		BEGIN
		INSERT #output_man_script 
		(
			SectionID
			, Section
			, Summary
		)
		SELECT
		0
		, 'SPNs for server'
		, 'No SPNs registered'
		END

		/*Set back xp_cmdshell*/
		IF @StateOfXP_CMDSHELL = 0 
		BEGIN
			-- To allow advanced options to be changed.
			EXEC sp_configure 'show advanced options', 1
			-- To update the currently configured value for advanced options.
			RECONFIGURE
			-- To enable the feature.
			EXEC sp_configure 'xp_cmdshell', 0
			-- To update the currently configured value for this feature.
			RECONFIGURE
		END

	END TRY
	BEGIN CATCH
		IF @Debug = 0
			RAISERROR (N'xp_cmdshell DISABLED',0,1) WITH NOWAIT; 
	END CATCH

	DECLARE @sqlnamedinstance sysname
	DECLARE @networkname sysname
	if (select CHARINDEX('\',@@SERVERNAME)) = 0
	BEGIN
		INSERT @PerformanceCounter (CounterName, CounterValue, DateSampled)
		SELECT  REPLACE(REPLACE(REPLACE(ct.[output],'\\'+@@SERVERNAME+'\',''),' :',''),'sqlserver:','')[CounterName] , CONVERT(VARCHAR(20),ct2.[output]) [CounterValue], GETDATE() [DateSampled]
		FROM @syscountertable ct
		LEFT OUTER JOIN (
		SELECT id - 1 [id], [output]
		FROM @syscountertable
		WHERE PATINDEX('%[0-9]%', LEFT([output],1)) > 0  
		) ct2 ON ct.id = ct2.id
		WHERE  ct.[output] LIKE '\\%'
		AND  ct.[output] IS NOT NULL
		ORDER BY [CounterName] ASC
	END

	ELSE

	BEGIN
		select @networkname=RTRIM(left(@@SERVERNAME, CHARINDEX('\', @@SERVERNAME) - 1))
		select @sqlnamedinstance=RIGHT(@@SERVERNAME,CHARINDEX('\',REVERSE(@@SERVERNAME))-1)
		INSERT @PerformanceCounter (CounterName, CounterValue, DateSampled)
		SELECT  REPLACE(REPLACE(REPLACE(ct.[output],'\\'+@networkname+'\',''),' :',''),'mssql$'+@sqlnamedinstance+':','')[CounterName] , CONVERT(VARCHAR(20),ct2.[output]) [CounterValue], GETDATE() [DateSampled]
		FROM @syscountertable ct
		LEFT OUTER JOIN (
		SELECT id - 1 [id], [output]
		FROM @syscountertable
		WHERE PATINDEX('%[0-9]%', LEFT([output],1)) > 0  
		) ct2 ON ct.id = ct2.id
		WHERE  ct.[output] LIKE '\\%'
		ORDER BY [CounterName] ASC
	END
END

/*Generate DTU calculations*/
INSERT #output_man_script 
(
	SectionID
	, Section
	, Summary
	, Details
) 
SELECT 0
,'For Azure Calculations'
,'------'
,'------'
INSERT #output_man_script 
(
	SectionID
	, Section
	,Summary
)
SELECT 0
, 'Number of CPUs exposed to OS' [Measure]
, CONVERT(VARCHAR(3),@CPUcount) [Value] 

UNION ALL
SELECT 0
, 'Databases(_total)\log bytes flushed/sec (MB)'
, AVG(CONVERT(MONEY,CounterValue))/1024/1024
FROM @PerformanceCounter T1
WHERE T1.CounterName LIKE '%databases(_total)\log bytes flushed/sec'

UNION ALL
SELECT 0
, 'Average IOPS'
, SUM(CONVERT(MONEY,CounterValue))/@loops
FROM @PerformanceCounter T1
WHERE T1.CounterName LIKE '%LogicalDisk(_Total)\Disk Reads/sec'
OR  T1.CounterName LIKE '%LogicalDisk(_Total)\Disk Writes/sec'

UNION ALL
SELECT 0
, 'Disk Read IOPS'
, AVG(CONVERT(MONEY,CounterValue))
FROM @PerformanceCounter T1
WHERE T1.CounterName LIKE '%LogicalDisk(_Total)\Disk Reads/sec'

UNION ALL
SELECT 0
, 'Disk Write IOPS'
, AVG(CONVERT(MONEY,CounterValue))
FROM @PerformanceCounter T1
WHERE T1.CounterName LIKE '%LogicalDisk(_Total)\Disk Writes/sec'



	DECLARE @CPURingBuffer TABLE
	(
		SQLProcessUtilization SMALLINT
		,SystemIdle SMALLINT
		,[Event_Time] DATETIME
	)

	INSERT @CPURingBuffer
	SELECT SQLProcessUtilization
		, SystemIdle
		, DATEADD(ms,-1 *(@ts - [timestamp]), GETDATE())AS [Event_Time]
		FROM 
		(
             SELECT JSON_VALUE([record JSON], '$."Record id"') AS record_id
             ,JSON_VALUE([record JSON], '$."SystemIdle"') AS [SystemIdle]
             ,JSON_VALUE([record JSON], '$."ProcessUtilization"') AS [SQLProcessUtilization]
             ,orb.[timestamp]
             FROM (
             SELECT 
             [timestamp]
             ,
             REPLACE(
			 REPLACE(
             REPLACE(
		     REPLACE(
             REPLACE(
		     REPLACE(
             REPLACE(
			 REPLACE(
             REPLACE(
			 REPLACE(
             REPLACE(
			 REPLACE(
             REPLACE(
			 REPLACE(
             REPLACE(
			 REPLACE(
			 REPLACE(
			 REPLACE(
			 REPLACE(
        record
             ,'</ProcessUtilization>','",')
             , '<ProcessUtilization>',',"ProcessUtilization":"')
             ,'</SystemIdle>','",')
             , '<SystemIdle>','"SystemIdle":"')
             , '</UserModeTime>','",')
             , '<UserModeTime>','"UserModeTime":"')
             , '</KernelModeTime>','",')
             , '<KernelModeTime>','"KernelModeTime":"')
             , '</PageFaults>','",')
             , '<PageFaults>','"PageFaults":"')
             , '</WorkingSetDelta>','",')
             , '<WorkingSetDelta>','"WorkingSetDelta":"')
             , '</MemoryUtilization>','",')
             , '<MemoryUtilization>','"MemoryUtilization":"')
             , '<Record id = ','{"Record id":')
             , ' type =',',"type":')
             , ' time =',',"time":')
             ,'><SchedulerMonitorEvent><SystemHealth>','')
             ,',</SystemHealth></SchedulerMonitorEvent></Record>','}') [record JSON]
             FROM sys.dm_os_ring_buffers 
             WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
             AND record LIKE'%%'
          )orb
		) as y
	

INSERT #output_man_script (SectionID, Section,Summary)
SELECT 0 ,'SQL Avg Usage %. From: ' + CONVERT(VARCHAR, MIN([Event_Time]),120) + ' to: ' + CONVERT(VARCHAR, MAX([Event_Time]),120) , AVG(SQLProcessUtilization) FROM @CPURingBuffer T1
UNION ALL
SELECT 0 ,'SQL Avg NOT 0 %. From: ' + CONVERT(VARCHAR, MIN([Event_Time]),120) + ' to: ' + CONVERT(VARCHAR, MAX([Event_Time]),120) , AVG(SQLProcessUtilization) FROM @CPURingBuffer T1 WHERE SQLProcessUtilization <> 0
UNION ALL
SELECT 0 ,'SQL MAX Usage %. From: ' + CONVERT(VARCHAR, MIN([Event_Time]),120) + ' to: ' + CONVERT(VARCHAR, MAX([Event_Time]),120) , MAX(SQLProcessUtilization) FROM @CPURingBuffer T1
UNION ALL
SELECT 0 ,'OS idle CPU %. From: ' + CONVERT(VARCHAR, MIN([Event_Time]),120) + ' to: ' + CONVERT(VARCHAR, MAX([Event_Time]),120) , AVG(SystemIdle) FROM @CPURingBuffer T1 



	IF @Debug = 0
		RAISERROR (N'Finished rough IOPS calculation',0,1) WITH NOWAIT;


			/*----------------------------------------
			--Check for any pages marked suspect for corruption
			----------------------------------------*/
	DECLARE @syspectpagescount FLOAT
	SELECT @syspectpagescount = COUNT(*) FROM msdb.dbo.suspect_pages
	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 0, 'SUSPECT PAGES','------','------'
	INSERT #output_man_script (SectionID, Section,Summary,Severity, Details)
	SELECT 0,
	'DB: ' + db_name(database_id)
	+ '; FileID: ' + CONVERT(VARCHAR(20),file_id)
	+ '; PageID: ' + CONVERT(VARCHAR(20), page_id)
	, 'Event Type: ' + CONVERT(VARCHAR(20),event_type)
	+ '; Count: ' + CONVERT(VARCHAR(20),error_count)
	, CASE WHEN @syspectpagescount > 0 THEN @Result_YourServerIsDead WHEN @syspectpagescount = 0 THEN @Result_Good END
	, 'Last Update: ' + CONVERT(VARCHAR(20),last_update_date,120)
	
	FROM msdb.dbo.suspect_pages
	OPTION (RECOMPILE)

	IF @Debug = 0
		RAISERROR (N'Included Suspect Pages, if any',0,1) WITH NOWAIT;


			/*----------------------------------------
			--Before anything else, look for things that might point to breaking behaviour. Look for out of support SQL bits floating around
			--WORKAROUND - create all indexes using the deafult SET settings of the applications connecting into the server
			--DANGER WILL ROBINSON

			----------------------------------------*/
	
	BEGIN

		INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 1,'!!! WARNING - CHECK SET - MAKES INDEXES BREAK THINGS!!!','------','------'
		INSERT #output_man_script (SectionID, Section,Summary,Severity, Details)
		SELECT DISTINCT 1
		, 'User Connections' [Section]
		, ISNULL(CASE 
		WHEN T.client_version < 3 THEN 'SQL 6'
		WHEN T.client_version = 3 THEN 'SQL 7'
		WHEN T.client_version = 4 THEN 'SQL 2000'
		WHEN T.client_version = 5 THEN 'SQL 2005'
		WHEN T.client_version = 6 THEN 'SQL 2008'
		WHEN T.client_version = 7 THEN 'SQL 2012+'
		ELSE 'SQL 2014+'
		END ,'')
		+ '; Database: ' +   ISNULL(DB_NAME(  R.database_id),'')
		+ '; App: ' + ISNULL(T.program_name,'')
		+ '; Driver: ' + ISNULL(
		CASE SUBSTRING(CAST(C.protocol_version AS BINARY(4)), 1,1)
		WHEN 0x04 THEN 'Pre-version SQL Server 7.0 - DBLibrary/ ISQL'
		WHEN 0x70 THEN 'SQL Server 7.0'
		WHEN 0x71 THEN 'SQL Server 2000'
		WHEN 0x72 THEN 'SQL Server 2005'
		WHEN 0x73 THEN 'SQL Server 2008'
		WHEN 0x74 THEN 'SQL Server 2012+'
		ELSE 'Unknown driver'
		END ,'')
		+ '; Interface: '+ ISNULL(T.client_interface_name,'')
		+ '; User: ' + ISNULL(T.nt_user_name,'')
		+ '; Host: ' + ISNULL(T.host_name,'')
		+ '; Client Version: ' + ISNULL(CONVERT(VARCHAR(4),T.client_version),'') [Summary]
		, '' + 
		CASE WHEN ISNULL(CASE WHEN T.quoted_identifier = 0 THEN 1 ELSE 0 END
		+ CASE WHEN T.ansi_nulls = 0 THEN 1 ELSE 0 END
		+ CASE WHEN T.ansi_padding = 0 THEN 1 ELSE 0 END
		+ CASE WHEN T.ansi_warnings = 0 THEN 1 ELSE 0 END
		+ CASE WHEN T.arithabort = 0 THEN 1 ELSE 0 END
		+ CASE WHEN T.concat_null_yields_null = 0 THEN 1 ELSE 0 END
		,0) > 0 THEN @Result_Warning ELSE @Result_Good END

		, '' + ISNULL(CASE WHEN T.quoted_identifier = 0 THEN ';quoted_identifier = OFF' ELSE '' END
		+ ''+  CASE WHEN T.ansi_nulls = 0 THEN ';ansi_nulls = OFF' ELSE '' END
		+ ''+  CASE WHEN T.ansi_padding = 0 THEN ';ansi_padding = OFF' ELSE '' END
		+ ''+  CASE WHEN T.ansi_warnings = 0 THEN ';ansi_warnings = OFF' ELSE '' END
		+ ''+  CASE WHEN T.arithabort = 0 THEN ';arithabort = OFF' ELSE '' END
		+ ''+  CASE WHEN T.concat_null_yields_null = 0 THEN ';concat_null_yields_null = OFF' ELSE '' END,'')
		FROM sys.dm_exec_sessions T
		LEFT OUTER JOIN sys.dm_exec_connections C ON C.session_id = T.session_id
		LEFT OUTER JOIN sys.dm_exec_requests R ON R.session_id = T.session_id
		WHERE T.client_version > 0
		--AND T.program_name NOT LIKE 'SQLAgent - %' 
		--OR T.client_version < 6 
		ORDER BY Section, [Summary];

	END
	IF @Debug = 0
		RAISERROR (N'Done checking for possible breaking SQL 2000 things',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Before anything else, look for things that might point to breaking behaviour. Like database with bad default settings
			----------------------------------------*/

	IF EXISTS(SELECT 1
		FROM sys.databases
		WHERE is_ansi_nulls_on = 0
		OR is_ansi_padding_on= 0
		OR is_ansi_warnings_on= 0
		OR is_arithabort_on= 0
		OR is_concat_null_yields_null_on= 0
		OR is_numeric_roundabort_on= 0
		OR is_quoted_identifier_on= 1)
	BEGIN

	
		INSERT INTO #whatsets(DBname, [compatibility_level],[SETs])
		
		SELECT '[' + name + ']'
		, [compatibility_level]
		, ''+  CASE WHEN is_quoted_identifier_on = 0 THEN '; SET quoted_identifier OFF' ELSE '' END
		+ ''+  CASE WHEN is_ansi_nulls_on = 0 THEN '; SET ansi_nulls OFF' ELSE '' END
		+ ''+  CASE WHEN is_ansi_padding_on = 0 THEN '; SET ansi_padding OFF' ELSE '' END
		+ ''+  CASE WHEN is_ansi_warnings_on = 0 THEN '; SET ansi_warnings OFF' ELSE '' END
		+ ''+  CASE WHEN is_arithabort_on = 0 THEN '; SET arithabort OFF' ELSE '' END
		+ ''+  CASE WHEN is_concat_null_yields_null_on = 0 THEN '; SET concat_null_yields_null OFF' ELSE '' END
		+ ''+  CASE WHEN is_numeric_roundabort_on = 1 THEN '; SET is_numeric_roundabort_on ON' ELSE '' END
		FROM sys.databases

	END

	IF EXISTS(SELECT * FROM #whatsets)
	BEGIN
		INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 1,'!!! WARNING - POTENTIALLY BREAKING DB SETTINGS!!!','------','------'
		INSERT #output_man_script (SectionID, Section,Summary)
		SELECT 1
		, DBname + ' [' + CONVERT(VARCHAR(10), [compatibility_level])  + ']'
		, [SETs]
		FROM #whatsets
		ORDER BY DBname DESC

	END

	IF @Debug = 0
		RAISERROR (N'Done checking compatability levels and sets for database things',0,1) WITH NOWAIT;
			/*----------------------------------------
			--Benchmark, not for anything else besides getting a number
			----------------------------------------*/

	SET @StartTest = GETDATE();
	DECLARE @testloop INT 
	SET @testloop = 0
	WHILE @secondsperoperator IS NULL AND @testloop < 10
	BEGIN
	
		WITH  E00(N)	AS (SELECT 1 UNION ALL SELECT 1)
			, E02(N)	AS (SELECT 1 FROM E00 a, E00 b)
			, E04(N)	AS (SELECT 1 FROM E02 a, E02 b)
			, E08(N)	AS (SELECT 1 FROM E04 a, E04 b)
			, E16(N)	AS (SELECT 1 FROM E08 a, E08 b)
			, cteTally(N) AS (SELECT ROW_NUMBER() OVER (ORDER BY N) FROM E16)
		SELECT 
			@ThisistoStandardisemyOperatorCostMate = count(N) 
		FROM cteTally OPTION (RECOMPILE);
		
		WITH  E00(N)	AS (SELECT 1 UNION ALL SELECT 1)
			, E02(N)	AS (SELECT 1 FROM E00 a, E00 b)
			, E04(N)	AS (SELECT 1 FROM E02 a, E02 b)
			, E08(N)	AS (SELECT 1 FROM E04 a, E04 b)
			, E16(N)	AS (SELECT 1 FROM E08 a, E08 b)
			, cteTally(N) AS (SELECT ROW_NUMBER() OVER (ORDER BY N) FROM E16)
		SELECT 
			@ThisistoStandardisemyOperatorCostMate = count(N) 
		FROM cteTally OPTION (RECOMPILE);
		SET @EndTest = GETDATE();
		SELECT   
			@secondsperoperator = AVG(qs.total_worker_time/qs.execution_count/1000)/0.7248/1000  
		FROM sys.dm_exec_query_stats qs
		CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
		WHERE qs.total_logical_reads = 0 
		AND qs.last_execution_time BETWEEN DATEADD(MINUTE,-2,@StartTest) AND GETDATE()
		AND PATINDEX('%ThisistoStandardisemyOperatorCostMate%',CAST(qt.TEXT AS NVARCHAR(MAX))) > 0
			
		WAITFOR DELAY '00:00:00.5'
		SET @testloop = @testloop + 1
		--PRINT ISNULL(CONVERT(VARCHAR(50),@secondsperoperator),'null...')
			
	END
	IF @secondsperoperator IS NULL
		SET @secondsperoperator = 0.00413907

	--PRINT N'Your cost (in seconds) per operator roughly equates to around '+ CONVERT(VARCHAR(20),ISNULL(@secondsperoperator,0)) + ' seconds' ;
	IF @Debug = 0
		RAISERROR (N'Benchmarking done',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Build database table to use throughout this script
			----------------------------------------*/

DECLARE @Databases TABLE
	(
		id INT IDENTITY(1,1)
		, database_id INT
		, databasename NVARCHAR(250)
		, [compatibility_level] BIGINT
		, user_access BIGINT
		, user_access_desc NVARCHAR(50)
		, [state] BIGINT
		, state_desc  NVARCHAR(50)
		, recovery_model BIGINT
		, recovery_model_desc  NVARCHAR(50)
		, create_date DATETIME
		, AGReplicaRole INT
		, [BackupPref] NVARCHAR(250)
		, [CurrentLocation] NVARCHAR(250)
		, AGName NVARCHAR(250)
		, [ReadSecondary] NVARCHAR(250)
		
	);
	SET @dynamicSQL = 'SELECT 
	db.database_id
	, db.name
	, db.compatibility_level
	, db.user_access
	, db.user_access_desc
	, db.state
	, db.state_desc
	, db.recovery_model
	, db.recovery_model_desc
	, db.create_date
	
	, 1
	, NULL
	, NULL
	, NULL
	, NULL
	FROM 
	sys.databases db 
	WHERE 1 = 1 '
	If @SQLVersion >= 11 
	BEGIN 
		SET @dynamicSQL = @dynamicSQL + ' AND replica_id IS NULL /*Don''t touch anything AG related*/'
	END
	
	SET @dynamicSQL = @dynamicSQL + ' AND db.database_id > 4 AND db.user_access = 0 AND db.State = 0 '
	
	
	BEGIN TRY

	If @SQLVersion >= 11 BEGIN
	IF EXISTS((SELECT 1 FROM master.sys.availability_groups )) /*You have active AGs*/
	SET @dynamicSQL = @dynamicSQL + '
	UNION ALL
	SELECT 
	db.database_id
	, db.name
	, db.compatibility_level
	, db.user_access
	, db.user_access_desc
	, db.state
	, db.state_desc
	, db.recovery_model
	, db.recovery_model_desc
	, db.create_date
	, LocalReplicaRole
	, [BackupPref]
	, [CurrentLocation]
	, AGName
	, [ReadSecondary]
	FROM 
	sys.databases db 
	LEFT OUTER JOIN(
	
	SELECT top 100 percent
	AG.name AS [AvailabilityGroupName],
	ISNULL(agstates.primary_replica, NULL) AS [PrimaryReplicaServerName],
	ISNULL(arstates.role, 3) AS [LocalReplicaRole],
	dbcs.database_name AS [DatabaseName],
	ISNULL(dbrs.synchronization_state, 0) AS [SynchronizationState],
	ISNULL(dbrs.is_suspended, 0) AS [IsSuspended],
	ISNULL(dbcs.is_database_joined, 0) AS [IsJoined]
	, AG.automated_backup_preference_desc [BackupPref]
	, AR.availability_mode_desc
	, agstates.primary_replica [CurrentLocation]

	, AG.name AGName
	, AR.secondary_role_allow_connections_desc [ReadSecondary]
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
	WHERE dbcs.is_database_joined = 1 AND agstates.primary_replica = '''+@ThisServer+'''
	ORDER BY AG.name ASC, dbcs.database_name
	
	) t1 on t1.DatabaseName = db.name 
	WHERE db.database_id > 4 AND db.user_access = 0 AND db.State = 0 
	AND t1.LocalReplicaRole IS NOT NULL
	'
	END
	END TRY
	BEGIN CATCH
		IF @Debug = 0
			RAISERROR (N'Trouble with Availability Group database list',0,1) WITH NOWAIT;
	END CATCH
	SET @dynamicSQL = @dynamicSQL + ' OPTION (RECOMPILE);'
	INSERT INTO @Databases 
	EXEC sp_executesql @dynamicSQL ;
	SET @Databasei_Max = (SELECT MAX(id) FROM @Databases );

			/*----------------------------------------
			--Get uptime and cache age
			----------------------------------------*/

	SET @oldestcachequery = (SELECT ISNULL(  MIN(creation_time),0.1) FROM sys.dm_exec_query_stats WITH (NOLOCK));
	SET @lastservericerestart = (SELECT create_date FROM sys.databases WHERE name = 'tempdb');
	SET @minutesSinceRestart = (SELECT DATEDIFF(MINUTE,@lastservericerestart,GETDATE()));
	
	SELECT @DaysUptime = CAST(DATEDIFF(hh,@lastservericerestart,GETDATE())/24. AS NUMERIC (23,2)) OPTION (RECOMPILE);
	SELECT @DaysOldestCachedQuery = CAST(DATEDIFF(hh,@oldestcachequery,GETDATE())/24. AS NUMERIC (23,2)) OPTION (RECOMPILE);


	IF @DaysUptime = 0 
		SET @DaysUptime = .1;
	IF @DaysOldestCachedQuery = 0 
		SET @DaysOldestCachedQuery = .1;

	SET @CachevsUpdate = @DaysOldestCachedQuery*100/@DaysUptime
	IF @CachevsUpdate < 1
		SET @CachevsUpdate = 1
	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 2,'CACHE - Cache Age As portion of Overall Uptime','------','------'
	INSERT #output_man_script (SectionID, Section,Summary,HoursToResolveWithTesting )
	SELECT 2,'['+REPLICATE('|', @CachevsUpdate) + REPLICATE('''',100-@CachevsUpdate ) +']'
	, 'Uptime:'
	+ CONVERT(VARCHAR(20),@DaysUptime)
	+ '; Oldest Cache:'
	+ CONVERT(VARCHAR(20),@DaysOldestCachedQuery )
	+ '; Cache Timestamp:'
	+ CONVERT(VARCHAR(20),@oldestcachequery,120)
	, CASE WHEN @CachevsUpdate > 50 AND @DaysUptime > 1 THEN 0.5 ELSE 2 END 


	IF @Debug = 0
		RAISERROR (N'Server uptime and cache age established',0,1) WITH NOWAIT;






	   /*----------------------------------------
			--Internals and Memory usage
		----------------------------------------*/


	

	SELECT @VMType = RIGHT(@@version,CHARINDEX('(',REVERSE(@@version)))

	
	IF @SQLVersion > 10
	BEGIN
		EXEC sp_executesql N'set @_MaxRamServer= (select physical_memory_kb/1024 from sys.dm_os_sys_info);', N'@_MaxRamServer INT OUTPUT', @_MaxRamServer = @MaxRamServer OUTPUT
		
		EXEC sp_executesql N'SELECT @_UsedMemory = CONVERT(MONEY,physical_memory_in_use_kb)/1024 /1000 FROM sys.dm_os_process_memory WITH (NOLOCK) OPTION (RECOMPILE)', N'@_UsedMemory MONEY  OUTPUT', @_UsedMemory = @UsedMemory OUTPUT
		EXEC sp_executesql N'SELECT @_totalMemoryGB = CONVERT(MONEY,total_physical_memory_kb)/1024/1000 FROM sys.dm_os_sys_memory WITH (NOLOCK) OPTION (RECOMPILE)', N'@_totalMemoryGB MONEY  OUTPUT', @_totalMemoryGB = @totalMemoryGB OUTPUT
		EXEC sp_executesql N'SELECT @_AvailableMemoryGB =  CONVERT(MONEY,available_physical_memory_kb)/1024/1000 FROM sys.dm_os_sys_memory WITH (NOLOCK) OPTION (RECOMPILE);', N'@_AvailableMemoryGB MONEY  OUTPUT', @_AvailableMemoryGB = @AvailableMemoryGB OUTPUT
		EXEC sp_executesql N'SELECT @_MemoryStateDesc =   system_memory_state_desc from  sys.dm_os_sys_memory;', N'@_MemoryStateDesc NVARCHAR(50) OUTPUT', @_MemoryStateDesc = @MemoryStateDesc OUTPUT

		--SELECT @UsedMemory = CONVERT(MONEY,physical_memory_in_use_kb)/1024 /1000 FROM sys.dm_os_process_memory WITH (NOLOCK) OPTION (RECOMPILE)
		--SELECT @totalMemoryGB = CONVERT(MONEY,total_physical_memory_kb)/1024/1000 FROM sys.dm_os_sys_memory WITH (NOLOCK) OPTION (RECOMPILE);
		--SELECT @AvailableMemoryGB =  CONVERT(MONEY,available_physical_memory_kb)/1024/1000 FROM sys.dm_os_sys_memory WITH (NOLOCK) OPTION (RECOMPILE);
	END
	ELSE
	IF @SQLVersion in (10,9)
	BEGIN

		EXEC sp_executesql N'set @_MaxRamServer= (select physical_memory_in_bytes/1024/1000 from sys.dm_os_sys_info) ;', N'@_MaxRamServer INT OUTPUT', @_MaxRamServer = @MaxRamServer OUTPUT
		
		EXEC sp_executesql N'SELECT @_UsedMemory = CONVERT(MONEY,physical_memory_in_bytes)/1024/1024/1000 FROM sys.dm_os_sys_info WITH (NOLOCK) OPTION (RECOMPILE)', N'@_UsedMemory MONEY  OUTPUT', @_UsedMemory = @UsedMemory OUTPUT
		EXEC sp_executesql N'SELECT @_totalMemoryGB = CONVERT(MONEY,physical_memory_in_bytes)/1024/1024/1000 FROM sys.dm_os_sys_info WITH (NOLOCK) OPTION (RECOMPILE)', N'@_totalMemoryGB MONEY  OUTPUT', @_totalMemoryGB = @totalMemoryGB OUTPUT
		EXEC sp_executesql N'SELECT @_AvailableMemoryGB =  0;', N'@_AvailableMemoryGB MONEY  OUTPUT', @_AvailableMemoryGB = @AvailableMemoryGB OUTPUT
		SET @MemoryStateDesc = ''
		
	END

	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 3,'MEMORY - SQL Memory usage of total allocated','------','------'
	INSERT #output_man_script (SectionID, Section,Summary ,Details )

 
	SELECT 3,'['+REPLICATE('|', CONVERT(MONEY,CONVERT(FLOAT,@UsedMemory)/CONVERT(FLOAT,@totalMemoryGB)) * 100) + REPLICATE('''',100-(CONVERT(MONEY,CONVERT(FLOAT,@UsedMemory)/CONVERT(FLOAT,@totalMemoryGB)) * 100) ) +']' 
	, 'Sockets:' +  ISNULL(replace(replace(replace(replace(CONVERT(NVARCHAR,CONVERT(VARCHAR(20),(@CPUsocketcount ) )), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' '),'')
	+'; Virtual CPUs:' +  ISNULL(replace(replace(replace(replace(CONVERT(NVARCHAR,CONVERT(VARCHAR(20),@CPUcount   )), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ') ,'')
	+'; VM Type:' +  ISNULL(replace(replace(replace(replace(CONVERT(NVARCHAR,ISNULL(@VMType,'')), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ') ,'')
	+'; CPU Affinity:'+  ISNULL(replace(replace(replace(replace(CONVERT(NVARCHAR,ISNULL('','')), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ') ,'')
	+'; MemoryGB:' + ISNULL(CONVERT(VARCHAR(20), CONVERT(MONEY,CONVERT(FLOAT,@totalMemoryGB))),'')
	+'; SQL Allocated:' +ISNULL(CONVERT(VARCHAR(20), CONVERT(MONEY,CONVERT(FLOAT,@UsedMemory))) ,'')
	+'; Suggested MAX:' + ISNULL( CONVERT(VARCHAR(20), CASE 
	 WHEN @MaxRamServer < = 1024*2 THEN @MaxRamServer - 512  /*When the RAM is Less than or equal to 2GB*/
	 WHEN @MaxRamServer < = 1024*4 THEN @MaxRamServer - 1024 /*When the RAM is Less than or equal to 4GB*/
	 WHEN @MaxRamServer < = 1024*16 THEN @MaxRamServer - 1024 - Ceiling((@MaxRamServer-4096) / (4.0*1024))*1024 /*When the RAM is Less than or equal to 16GB*/

		-- My machines memory calculation
		-- RAM= 16GB
		-- Case 3 as above:- 16384 RAM-> MaxMem= 16384-1024-[(16384-4096)/4096] *1024
		-- MaxMem= 12106

		WHEN @MaxRamServer > 1024*16 THEN @MaxRamServer - 4096 - Ceiling((@MaxRamServer-1024*16) / (8.0*1024))*1024 /*When the RAM is Greater than or equal to 16GB*/
		END) ,'')
	+'; Used by SQL:'+ ISNULL(CONVERT(VARCHAR(20), CONVERT(FLOAT,@UsedMemory)),'')
	+'; Memory State:' + ISNULL((@MemoryStateDesc),'')  [Internals: Details] 
	, ('ServerName:'+ ISNULL(replace(replace(replace(replace(CONVERT(NVARCHAR,SERVERPROPERTY('ServerName')), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ') ,'')
		+'; Version:'+ ISNULL(replace(replace(replace(replace(CONVERT(NVARCHAR,LEFT( @@version, PATINDEX('%-%',( @@version))-2) ), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ') ,'')
		+'; VersionNr:'+ ISNULL(replace(replace(replace(replace(CONVERT(NVARCHAR,SERVERPROPERTY('ProductVersion')), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ') ,'')
		+'; OS:'+  ISNULL(replace(replace(replace(replace(CONVERT(NVARCHAR,RIGHT( @@version, LEN(@@version) - PATINDEX('% on %',( @@version))-3) ), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ') ,'')
		+'; Edition:'+ ISNULL(replace(replace(replace(replace(CONVERT(NVARCHAR,SERVERPROPERTY('Edition')), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ') ,'')
		+'; HADR:'+ ISNULL(replace(replace(replace(replace(CONVERT(NVARCHAR,SERVERPROPERTY('IsHadrEnabled')), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ') ,'')
		+'; SA:'+ ISNULL(replace(replace(replace(replace(CONVERT(NVARCHAR,SERVERPROPERTY('IsIntegratedSecurityOnly' )), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' '),'')
		+'; Licenses:'+ ISNULL(replace(replace(replace(replace(CONVERT(NVARCHAR,SERVERPROPERTY('NumLicenses' )), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ') ,'')
		+'; Level:'+ ISNULL(replace(replace(replace(replace(CONVERT(NVARCHAR,SERVERPROPERTY('ProductLevel')), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' '),''))  [More Details] 
		
		FROM [sys].[dm_os_sys_info] OPTION (RECOMPILE);


			/*----------------------------------------
			--Get some CPU history
			----------------------------------------*/

	

	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 4,'CPU - Average CPU usage of SQL process as % of total CPU usage','Speed; Avg CPU; CPU Idle; Other; From; To; Full Details','------'
	INSERT #output_man_script (SectionID, Section,Summary, HoursToResolveWithTesting  )
	SELECT 4, '['+REPLICATE('|', AVG(CONVERT(MONEY,SQLProcessUtilization))) + REPLICATE('''',100-(AVG(CONVERT(MONEY,SQLProcessUtilization)) )) +']'
	,(@cpu_ghz
	+';'+ CONVERT(VARCHAR(20),AVG(SQLProcessUtilization))
	+'%;' + CONVERT(VARCHAR(20),AVG(SystemIdle))
	+'%; '+ CONVERT(VARCHAR(20), 100 - AVG(SQLProcessUtilization) - AVG(SystemIdle))
	+'%;'+ CONVERT(VARCHAR(20), MIN([Event_Time]),120)
	+';' + CONVERT(VARCHAR(20), MAX([Event_Time]),120)
	+';' + @cpu_name
	) 
	, CASE WHEN AVG(SQLProcessUtilization) > 50 THEN 2 ELSE 0 END 
	FROM 
	(
		SELECT SQLProcessUtilization
		, SystemIdle
		, DATEADD(ms,-1 *(@ts - [timestamp])
		, GETDATE())AS [Event_Time]
		FROM 
		(

             SELECT JSON_VALUE([record JSON], '$."Record id"') AS record_id
             ,CONVERT(MONEY,JSON_VALUE([record JSON], '$."SystemIdle"')) AS [SystemIdle]
             ,CONVERT(MONEY,JSON_VALUE([record JSON], '$."ProcessUtilization"')) AS [SQLProcessUtilization]
             ,orb.[timestamp]
             FROM (
             SELECT 
             [timestamp]
             ,
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
             REPLACE(
        record
             ,'</ProcessUtilization>','",')
             , '<ProcessUtilization>',',"ProcessUtilization":"')
             ,'</SystemIdle>','",')
             , '<SystemIdle>','"SystemIdle":"')
             , '</UserModeTime>','",')
             , '<UserModeTime>','"UserModeTime":"')
             , '</KernelModeTime>','",')
             , '<KernelModeTime>','"KernelModeTime":"')
             , '</PageFaults>','",')
             , '<PageFaults>','"PageFaults":"')
             , '</WorkingSetDelta>','",')
             , '<WorkingSetDelta>','"WorkingSetDelta":"')
             , '</MemoryUtilization>','",')
             , '<MemoryUtilization>','"MemoryUtilization":"')
             , '<Record id = ','{"Record id":')
             , ' type =',',"type":')
             , ' time =',',"time":')
             , '><SchedulerMonitorEvent><SystemHealth>','')
             , ',</SystemHealth></SchedulerMonitorEvent></Record>','}') [record JSON]
             FROM sys.dm_os_ring_buffers 
             WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
             AND record LIKE'%%'
              )orb
		) as y
	) T1
	HAVING AVG(T1.SQLProcessUtilization) >= (CASE WHEN @ShowWarnings = 1 THEN 20 ELSE 0 END)
	OPTION (RECOMPILE)

	IF @Debug = 0
		RAISERROR (N'Checked CPU usage for the last 5 hours',0,1) WITH NOWAIT;
	



			/*----------------------------------------
			--Failed logins on the server
			----------------------------------------*/
	IF @Debug = 0
		RAISERROR (N'Reading Error Log..',0,1) WITH NOWAIT;
	DECLARE @LoginLog TABLE( LogDate DATETIME, ProcessInfo NVARCHAR(200), [Text] NVARCHAR(MAX))
	IF  @ShowWarnings = 0 
	BEGIN
		SET @dynamicSQL = 'EXEC sp_readerrorlog 0, 1, ''Login failed'' '
		INSERT @LoginLog
		EXEC sp_executesql @dynamicSQL
		IF EXISTS (SELECT 1 FROM @LoginLog)
		BEGIN
			INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 5, 'LOGINS - Failed Logins','------','------'
			INSERT #output_man_script (SectionID, Section,Summary, Severity, HoursToResolveWithTesting  )
			SELECT TOP 15 5, 'Date:'
			+ CONVERT(VARCHAR(20),LogDate,120)
			,replace(replace(replace(replace(CONVERT(NVARCHAR(500),Text), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ')  
			,@Result_Warning , 0.25
			FROM @LoginLog ORDER BY LogDate DESC
			OPTION (RECOMPILE)
		END
	END
	IF @Debug = 0
		RAISERROR (N'Server logins have been checked from the log',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Agent log for errors
			----------------------------------------*/

	DECLARE @Errorlog TABLE( LogDate DATETIME, ErrorLevel INT, [Text] NVARCHAR(4000))
	/*Ignore the agent logs if you cannot find it, else errors will come*/
	BEGIN TRY

		IF DATEADD(MINUTE,5,@lastservericerestart) <  (SELECT MIN(Login_time) FROM master.dbo.sysprocesses WHERE LEFT(program_name, 8) = 'SQLAgent')
		BEGIN

			IF @Debug = 0
		RAISERROR (N'Agent started much later than Service. Might point to Agent never being restarted before. If you see the following error, just restart the agent and run this script again >>',0,1) WITH NOWAIT;
			IF @Debug = 0
		RAISERROR (N'Msg 0, Level 11, State 0, Line 2032
			A severe error occurred on the current command.  The results, if any, should be discarded.',0,1) WITH NOWAIT;
		END

		IF EXISTS (SELECT 1,* FROM master.dbo.sysprocesses WHERE LEFT(program_name, 8) = 'SQLAgent')
		BEGIN   
			SET @dynamicSQL = 'EXEC sp_readerrorlog 1, 2, ''Error:'' '
			INSERT @Errorlog
			EXEC sp_executesql @dynamicSQL
		END  
		BEGIN   
			SET @dynamicSQL = 'EXEC sp_readerrorlog 1, 1, ''Error:'' '
			INSERT @Errorlog
			EXEC sp_executesql @dynamicSQL
		END
		IF EXISTS (SELECT * FROM @Errorlog)
		BEGIN
			INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 6,'AGENT LOG Errors','------','------'
			INSERT #output_man_script (SectionID, Section,Summary, Severity, Details,HoursToResolveWithTesting  )
			SELECT 6, 'Date:'+ CONVERT(VARCHAR(20),LogDate ,120)
			, 'ErrorLevel:'+ CONVERT(VARCHAR(20),ErrorLevel)
			, @Result_Warning ,[Text], 1  
			FROM @Errorlog ORDER BY LogDate DESC
			
			OPTION (RECOMPILE)
		END  
	END TRY
	BEGIN CATCH
		IF @Debug = 0
		RAISERROR (N'Error reading agent log',0,1) WITH NOWAIT;
	END CATCH
	IF @Debug = 0
			RAISERROR (N'Agent log parsed for errors',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Look for failed agent jobs
			----------------------------------------*/
	IF EXISTS (
	SELECT *  
	FROM msdb.dbo.sysjobhistory DBSysJobHistory
		JOIN (
			SELECT DBSysJobHistory.job_id
				, DBSysJobHistory.step_id
				, MAX(DBSysJobHistory.instance_id) as instance_id
			FROM msdb.dbo.sysjobhistory DBSysJobHistory
			GROUP BY DBSysJobHistory.job_id
				, DBSysJobHistory.step_id
		) AS Instance ON DBSysJobHistory.instance_id = Instance.instance_id
	WHERE DBSysJobHistory.run_status <> 1
	)
	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 7, 'FAILED AGENT JOBS','------','------'
	INSERT #output_man_script (SectionID, Section,Summary, Severity, Details,HoursToResolveWithTesting  )
	SELECT  7,'Job Name:' + SysJobs.name
		+'; Step:'+ SysJobSteps.step_name 
		+ ' - '+ Job.run_status
		, 'MessageId: ' +CONVERT(VARCHAR(20),Job.sql_message_id)
		+ '; Severity:'+ CONVERT(VARCHAR(20),Job.sql_severity)
		, @Result_Warning
		, 'Message:'+ Job.message
		+'; Date:' + CONVERT(VARCHAR(20), Job.exec_date,120)
		, 2
		/*, Job.run_duration
		, Job.server
		, SysJobSteps.output_file_name
		*/
	FROM
	(
		SELECT Instance.instance_id
			,DBSysJobHistory.job_id
			,DBSysJobHistory.step_id
			,DBSysJobHistory.sql_message_id
			,DBSysJobHistory.sql_severity
			,DBSysJobHistory.message
			,(CASE DBSysJobHistory.run_status 
				WHEN 0 THEN 'Failed' 
				WHEN 1 THEN 'Succeeded' 
				WHEN 2 THEN 'Retry' 
				WHEN 3 THEN 'Canceled' 
				WHEN 4 THEN 'In progress'
			  END
			) as run_status
			,((SUBSTRING(CAST(DBSysJobHistory.run_date AS NVARCHAR(8)), 5, 2) + '/'
			  + SUBSTRING(CAST(DBSysJobHistory.run_date AS NVARCHAR(8)), 7, 2) + '/'
			  + SUBSTRING(CAST(DBSysJobHistory.run_date AS NVARCHAR(8)), 1, 4) + ' '
			  + SUBSTRING((REPLICATE('0',6-LEN(CAST(DBSysJobHistory.run_time AS NVARCHAR)))
			  + CAST(DBSysJobHistory.run_time AS NVARCHAR)), 1, 2) + ':'
			  + SUBSTRING((REPLICATE('0',6-LEN(CAST(DBSysJobHistory.run_time AS NVARCHAR)))
			  + CAST(DBSysJobHistory.run_time AS NVARCHAR)), 3, 2) + ':'
			  + SUBSTRING((REPLICATE('0',6-LEN(CAST(DBSysJobHistory.run_time as NVARCHAR)))
			  + CAST(DBSysJobHistory.run_time AS NVARCHAR)), 5, 2))) [exec_date]
			,DBSysJobHistory.run_duration
			,DBSysJobHistory.retries_attempted
			,DBSysJobHistory.server
		FROM msdb.dbo.sysjobhistory DBSysJobHistory
		JOIN (
			SELECT DBSysJobHistory.job_id
				, DBSysJobHistory.step_id
				, MAX(DBSysJobHistory.instance_id) as instance_id
			FROM msdb.dbo.sysjobhistory DBSysJobHistory
			GROUP BY DBSysJobHistory.job_id
				, DBSysJobHistory.step_id
		) AS Instance ON DBSysJobHistory.instance_id = Instance.instance_id
		WHERE DBSysJobHistory.run_status <> 1
	) AS Job
	JOIN msdb.dbo.sysjobs SysJobs
		   ON (Job.job_id = SysJobs.job_id)
	JOIN msdb.dbo.sysjobsteps SysJobSteps
		   ON (Job.job_id = SysJobSteps.job_id 
		   AND Job.step_id = SysJobSteps.step_id)
	OPTION (RECOMPILE);
	IF @Debug = 0
		RAISERROR (N'Checked for failed agent jobs',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Look for failed backups
			----------------------------------------*/
DECLARE @backupset TABLE( id BIGINT IDENTITY(1,1)
,[database_name] NVARCHAR(800)
,[recovery_model] NVARCHAR(50)
,[backup_start_date] DATETIME,[backup_finish_date] DATETIME,[type] NVARCHAR(20)
--,PRIMARY KEY CLUSTERED (id,[backup_start_date],[database_name],[recovery_model])
) 

INSERT @backupset
SELECT [database_name],[recovery_model], [backup_start_date],[backup_finish_date],[type]
FROM  msdb.[dbo].[backupset] 
			
			
	IF EXISTS
	(
		SELECT *
		FROM (
			SELECT *
			FROM @backupset x  
			WHERE backup_finish_date = (
				SELECT max(backup_finish_date) 
				FROM @backupset b
				WHERE b.database_name =   x.database_name 
			)    
		) a  
		RIGHT OUTER JOIN sys.databases b  ON a.database_name =   b.name  
		INNER JOIN @Databases D ON b.database_id = D.database_id
		WHERE b.name <> 'tempdb' /*Exclude tempdb*/
		AND (backup_finish_date < DATEADD(d,-1,GETDATE())  
		OR backup_finish_date IS NULL) 
	)
	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 8,'DATABASE - No recent Backups','------','------'
	INSERT #output_man_script (SectionID, Section,Summary, Severity, HoursToResolveWithTesting  )

	SELECT 8, name [Section] , ('; Backup Finish Date:' + ISNULL(CONVERT(VARCHAR(20),backup_finish_date,120),'')
		+ '; Type:' +coalesce(type,'NO BACKUP')) [Summary]
		, @Result_YourServerIsDead
		, 2
	FROM (
		SELECT database_name
			, backup_finish_date
			, CASE WHEN  type = 'D' THEN 'Full'    
			  WHEN  type = 'I' THEN 'Differential'                
			  WHEN  type = 'L' THEN 'Transaction Log'                
			  WHEN  type = 'F' THEN 'File'                
			  WHEN  type = 'G' THEN 'Differential File'                
			  WHEN  type = 'P' THEN 'Partial'                
			  WHEN  type = 'Q' THEN 'Differential partial'   
			  END AS type 
		FROM @backupset x  
		WHERE backup_finish_date = (
			SELECT max(backup_finish_date) 
			FROM @backupset b 
			WHERE b.database_name =   x.database_name 
		)    
	) a  
	RIGHT OUTER JOIN sys.databases b  ON a.database_name =   b.name  
	INNER JOIN @Databases D ON b.database_id = D.database_id
	WHERE b.name <> 'tempdb' /*Exclude tempdb*/
	AND (backup_finish_date < DATEADD(d,-1,GETDATE())  
	OR backup_finish_date IS NULL)
	OPTION (RECOMPILE); 
	IF @Debug = 0
		RAISERROR (N'Checked for failed backups',0,1) WITH NOWAIT;



			/*----------------------------------------
			--Check the Log chain for LOG backups, and VLFs - Thanks Rob
			----------------------------------------*/


IF OBJECT_ID('tempdb..#db_size') IS NOT NULL DROP TABLE #db_size

DECLARE @DatabasesForLOG TABLE
	(
		id INT 
		, database_id INT
		, databasename NVARCHAR(250)
		, [compatibility_level] BIGINT
		, user_access BIGINT
		, user_access_desc NVARCHAR(50)
		, [state] BIGINT
		, state_desc  NVARCHAR(50)
		, recovery_model BIGINT
		, recovery_model_desc  NVARCHAR(50)
		, create_date DATETIME
		, AGReplicaRole INT
		, [BackupPref] NVARCHAR(250)
		, [CurrentLocation] NVARCHAR(250)
		, AGName NVARCHAR(250)
		, [ReadSecondary] NVARCHAR(250)
	);

INSERT INTO @DatabasesForLOG
SELECT * FROM @Databases
--WHERE (CurrentLocation = @ThisServer AND BackupPref ='primary')

--variables to hold each 'iteration'  
DECLARE @query NVARCHAR(1000)  
DECLARE @dbname sysname  
DECLARE @vlfs int  
 
  
--table variable to hold results  
DECLARE @vlfcounts table  
    (dbname sysname,  
    vlfcount int)  

DECLARE @avg_max_log_size table 
	(dbname sysname,
	avgsize MONEY ,
	maxsize MONEY )
 
 
--table variable to capture DBCC loginfo output  
--changes in the output of DBCC loginfo from SQL2012 mean we have to determine the version 
 
DECLARE @MajorVersion  TINYINT   
set @MajorVersion = LEFT(CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(max)),CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(max)))-1) 
DECLARE @dbccloginfo table  
    (  
        fileid  TINYINT ,  
        file_size bigint,  
        start_offset bigint,  
        fseqno int,  
        [status]  TINYINT ,  
        parity  TINYINT ,  
        create_lsn numeric(25,0)  
    )
if @MajorVersion < 11 -- pre-SQL2012 
BEGIN 
      
  
    while exists(select top 1 T1.databasename from @DatabasesForLOG T1)  
    BEGIN  
  
        set @dbname = (select top 1 databasename from @DatabasesForLOG)  
        set @query = 'dbcc loginfo (' + '''' + @dbname + ''') '  
  
        INSERT into @dbccloginfo  
        exec (@query)  
  
        set @vlfs = @@rowcount  
  
        INSERT @vlfcounts  
        values(@dbname, @vlfs)  
  
        delete from @DatabasesForLOG where databasename = @dbname  
  
    END --while 
END 
else 
BEGIN 
    DECLARE @dbccloginfo2012 table  
    (  
        RecoveryUnitId int, 
        fileid  TINYINT ,  
        file_size bigint,  
        start_offset bigint,  
        fseqno int,  
        [status]  TINYINT ,  
        parity  TINYINT ,  
        create_lsn numeric(25,0)  
    )  
  
    while exists(select top 1 databasename from @DatabasesForLOG)  
    BEGIN  
  
        set @dbname = (select top 1 databasename from @DatabasesForLOG)  
        set @query = 'dbcc loginfo (' + '''' + @dbname + ''') '  
  
        INSERT into @dbccloginfo2012  
        exec (@query)  
  
        set @vlfs = @@rowcount  
  
        INSERT @vlfcounts  
        values(@dbname, @vlfs)  
  
        delete from @DatabasesForLOG where databasename = @dbname  
  
    END --while 
	
	
	INSERT INTO @dbccloginfo (fileid, file_size, start_offset, fseqno, [status], parity, create_lsn )
	
	SELECT fileid, file_size, start_offset, fseqno, [status], parity, create_lsn  FROM @dbccloginfo2012
	
	
		
END 
  
----output the full list  
--select dbname, vlfcount  
--from @vlfcounts  
--order by dbname

SELECT d.name,
ROUND(SUM(case when type =0 then cast(mf.size as bigint) else 0 end) * 8 / 1024, 0)   Size_MBs,ROUND(SUM(case when type =1 then cast(mf.size as bigint) else 0 end) * 8 / 1024, 0) as log_size_mb
into #db_size
FROM sys.master_files mf
INNER JOIN sys.databases d ON d.database_id = mf.database_id   
INNER JOIN @Databases DB ON d.database_id = DB.database_id
WHERE d.database_id > 4   -- Skip system databases 
GROUP BY d.name
ORDER BY Size_MBs desc,d.name


INSERT into @avg_max_log_size(dbname,avgsize,maxsize)

SELECT  [database_name] AS [DATABASE] ,

        AVG([backup_size] / 1024 / 1024) AS [AVG BACKUP SIZE MB],

        max([backup_size] / 1024 / 1024) AS [max BACKUP SIZE MB]

FROM    msdb.dbo.backupset
WHERE   [type] = 'L'
        AND [backup_start_date] >= dateadd(mm,-3,getdate())
GROUP BY [database_name]


INSERT #output_man_script (SectionID,Section,Summary, Details, Severity)
SELECT 8, 'Log and VLF Checks','[DBName].[Comments]','[vlfcount];[Size_MBs];[log_size_mb];[AvgBackupSizeMB];[MaxBackupSizeMB]',''
INSERT #output_man_script (SectionID,Section,Summary, Details, Severity)


select 8
, 'Log and VLF Checks'

---
, ds.name

+ case 
	when log_size_mb>Size_MBs then ' .LOG too big compared to Data' 
	else ''
END --as LogSizeCommentary1
+ case 
	when vlfcount>50 then ' .High VLFs' 
	else ''
END --as VLFCommentary 
+ case 
	when log_size_mb/2 > ls.maxsize  then ' .LOG too big compared to Max LOG Backup' /*'Log Size is more than twice the size of the maximum needed based on 3 month history' */
	else ''
END --as LogSizeCOmmentary2
 [Summary]

---
--[vlfcount];[Size_MBs];[log_size_mb];[AvgBackupSizeMB];[MaxBackupSizeMB]
,CONVERT(NVARCHAR(20),v.vlfcount)
 + ';' + CONVERT(NVARCHAR(20),ds.Size_MBs)
 + ';' + CONVERT(NVARCHAR(20),ds.log_size_mb)
 + ';' + CONVERT(NVARCHAR(20),ls.avgsize)
 + ';' + CONVERT(NVARCHAR(20),ls.maxsize) 
 ---
, CASE WHEN 
(case when log_size_mb>Size_MBs then 1 else 0 end
+ case when vlfcount>50 then 1 else 0 end
+ case when log_size_mb/2 > ls.maxsize  then 1 else 0 end) > 0 
	THEN 4 END 
	[Severity]
from #db_size ds join @vlfcounts v on ds.name=v.dbname
join @avg_max_log_size ls on v.dbname=ls.dbname



	IF @Debug = 0
		RAISERROR (N'Done with Log and VLF Checks',0,1) WITH NOWAIT;


			/*----------------------------------------
			--Look for backups and recovery model information
			----------------------------------------*/
	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 9, 'DATABASE - RPO in minutes and RTO in 15 min slices'
	,'DB;Compat;recovery_model;Best RTO HH:MM:SS ;Last Full;Last TL;DateCreated;AGName;ReadSecondary','MM:SS'
	INSERT #output_man_script (SectionID, Section,Summary, HoursToResolveWithTesting ) /* Had to change to DAYS thanks to some clients*/
	SELECT 9, 
	CONVERT(VARCHAR(20),DATEDIFF(HOUR,CASE 
	WHEN recovery_model = 'FULL' AND x.[Last Transaction Log] > x.[Last Full] THEN x.[Last Transaction Log]
	WHEN recovery_model = 'FULL' AND x.[Last Transaction Log] <= x.[Last Full] THEN [Last Full]
	ELSE x.[Last Full] END, GETDATE())) + ' hours'
	, (database_name
	+ '; ' +CONVERT(VARCHAR(10),[compatibility_level])
	+ '; ' + ISNULL(recovery_model,'')
	+ '; ' + ISNULL(LEFT(CONVERT(VARCHAR(20),DATEADD(SECOND,x.Timetaken,0) ,114),8),'')
	+ '; ' + ISNULL(CONVERT(VARCHAR(20),x.[Last Full],120),'')
	+ '; ' + ISNULL(CONVERT(VARCHAR(20),x.[Last Transaction Log],120),'')
	+ '; ' + ISNULL(CONVERT(VARCHAR(20),x.create_date,120),'')
	+ '; ' + ISNULL(x.AGName,'')
	+ '; ' + ISNULL(x.ReadSecondary,'')
	)
	, 
	CONVERT(VARCHAR(20),CASE 
	WHEN 
	DATEDIFF(HOUR,CASE 
	WHEN recovery_model = 'FULL' AND x.[Last Transaction Log] > x.[Last Full] THEN x.[Last Transaction Log]
	WHEN recovery_model = 'FULL' AND x.[Last Transaction Log] <= x.[Last Full] THEN [Last Full]
	ELSE x.[Last Full] END, GETDATE()) < 1 THEN 0
	WHEN 
	DATEDIFF(HOUR,CASE 
	WHEN recovery_model = 'FULL' AND x.[Last Transaction Log] > x.[Last Full] THEN x.[Last Transaction Log]
	WHEN recovery_model = 'FULL' AND x.[Last Transaction Log] <= x.[Last Full] THEN [Last Full]
	ELSE x.[Last Full] END, GETDATE()) BETWEEN 1 AND 2 THEN 2
	WHEN 
	DATEDIFF(HOUR,CASE 
	WHEN recovery_model = 'FULL' AND x.[Last Transaction Log] > x.[Last Full] THEN x.[Last Transaction Log]
	WHEN recovery_model = 'FULL' AND x.[Last Transaction Log] <= x.[Last Full] THEN [Last Full]
	ELSE x.[Last Full] END, GETDATE()) BETWEEN 2 AND 8 THEN 4
	WHEN 
	DATEDIFF(HOUR,CASE 
	WHEN recovery_model = 'FULL' AND x.[Last Transaction Log] > x.[Last Full] THEN x.[Last Transaction Log]
	WHEN recovery_model = 'FULL' AND x.[Last Transaction Log] <= x.[Last Full] THEN [Last Full]
	ELSE x.[Last Full] END, GETDATE()) BETWEEN 8 AND 24 THEN 6

	ELSE 8 END
	) 

	FROM 
	(
		SELECT  DB_NAME(dbs.database_id) [database_name], dbs.[compatibility_level] , dbs.recovery_model_desc [recovery_model],D.AGName, D.ReadSecondary
		, MAX(DATEDIFF(SECOND,backup_start_date, backup_finish_date)) 'Timetaken'
		, MAX(CASE WHEN  type = 'D' THEN backup_finish_date ELSE 0 END) 'Last Full'   
		, MIN(CASE WHEN  type = 'D' THEN backup_start_date ELSE 0 END) 'First Full'             
		, MAX(CASE WHEN  type = 'L' THEN backup_finish_date ELSE 0 END) 'Last Transaction Log'  
		, MIN(CASE WHEN  type = 'L' THEN backup_start_date ELSE 0 END) 'First Transaction Log'  
		, MAX(dbs.create_date) create_date
		--SELECT *
		FROM  msdb.sys.databases dbs
		INNER JOIN @Databases D ON dbs.database_id = D.database_id
		LEFT OUTER JOIN  msdb.dbo.backupset bs WITH (NOLOCK)  ON dbs.name = bs.database_name  
		
		AND dbs.recovery_model_desc COLLATE DATABASE_DEFAULT = bs.recovery_model COLLATE DATABASE_DEFAULT
		/*Do not filter out only databases with backups.. some have never had.. --WHERE type IN ('D', 'L')*/
		GROUP BY dbs.database_id, dbs.[compatibility_level],dbs.recovery_model_desc,D.AGName, D.ReadSecondary
	) x 
	ORDER BY [Last Full] ASC
	OPTION (RECOMPILE);
	IF @Debug = 0
		RAISERROR (N'Recovery Model information matched with backups',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Check for disk space and latency on the server
			----------------------------------------*/

	DECLARE @fixeddrives TABLE(drive NVARCHAR(5), FreeSpaceMB MONEY )
	INSERT @fixeddrives
	EXEC master..xp_fixeddrives 

	/* more useful info
	SELECT * FROM sys.dm_os_sys_info 
	EXEC xp_msver
	*/
	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 10, 'Disk Latency and Space','------','------'
/* Deprecated @ 09-04-2018 Adrian

	INSERT #output_man_script (SectionID, Section,Summary,HoursToResolveWithTesting  )

	SELECT 10, UPPER([Drive]) + '\ ' + REPLICATE('|',CASE WHEN (num_of_reads = 0 AND num_of_writes = 0) THEN 0 ELSE (io_stall/(num_of_reads + num_of_writes)) END) +' '+ CONVERT(VARCHAR(20), CASE WHEN (num_of_reads = 0 AND num_of_writes = 0) THEN 0 ELSE (io_stall/(num_of_reads + num_of_writes)) END) + ' ms' 
	, 'FreeSpace:'+ CONVERT(VARCHAR(20),[AvailableGBs]) + 'GB'
	+ '; Read:' + CONVERT(VARCHAR(20),CASE WHEN num_of_reads = 0 THEN 0 ELSE (io_stall_read_ms/num_of_reads) END )
	+ '; Write:' + CONVERT(VARCHAR(20), CASE WHEN io_stall_write_ms = 0 THEN 0 ELSE (io_stall_write_ms/num_of_writes) END )
	+ '; Total:' + CONVERT(VARCHAR(20), CASE WHEN (num_of_reads = 0 AND num_of_writes = 0) THEN 0 ELSE (io_stall/(num_of_reads + num_of_writes)) END) 
	+ ' (Latency in ms)'
	, CASE WHEN CASE WHEN (num_of_reads = 0 AND num_of_writes = 0) THEN 0 ELSE (io_stall/(num_of_reads + num_of_writes)) END > 25 THEN 0.4 * (io_stall/(num_of_reads + num_of_writes))/5  ELSE 0 END

	, CASE WHEN num_of_reads = 0 THEN 0 ELSE (num_of_bytes_read/num_of_reads) END AS [Avg Bytes/Read]
	, CASE WHEN io_stall_write_ms = 0 THEN 0 ELSE (num_of_bytes_written/num_of_writes) END AS [Avg Bytes/Write]
	, CASE WHEN (num_of_reads = 0 AND num_of_writes = 0) THEN 0 ELSE ((num_of_bytes_read + num_of_bytes_written)/(num_of_reads + num_of_writes)) END AS [Avg Bytes/Transfer]

	FROM (
	SELECT LEFT(mf.physical_name, 2) AS Drive
		, MAX(CAST(fd.FreeSpaceMB / 1024 as decimal(20,2))) [AvailableGBs]
		, SUM(num_of_reads) AS num_of_reads
		, SUM(io_stall_read_ms) AS io_stall_read_ms
		, SUM(num_of_writes) AS num_of_writes
		, SUM(io_stall_write_ms) AS io_stall_write_ms
		, SUM(num_of_bytes_read) AS num_of_bytes_read
		, SUM(num_of_bytes_written) AS num_of_bytes_written
		, SUM(io_stall) AS io_stall
		  FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
		  INNER JOIN sys.master_files AS mf WITH (NOLOCK)
		  ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
		  INNER JOIN @fixeddrives fd ON fd.drive COLLATE DATABASE_DEFAULT = LEFT(mf.physical_name, 1) COLLATE DATABASE_DEFAULT
	  
		  GROUP BY LEFT(mf.physical_name, 2)) AS tab
	ORDER BY CASE WHEN (num_of_reads = 0 AND num_of_writes = 0) THEN 0 ELSE (io_stall/(num_of_reads + num_of_writes)) END OPTION (RECOMPILE);
	*/
	
	INSERT #output_man_script (SectionID, Section,Summary, Details)
	SELECT 10,'[Drive]; [Latency (ms)];[PhysicalDailyIO_GB];[Details]','[READ latency (ms)]; [WRITE latency (ms)]','[FileName]; [Type]'
	INSERT #output_man_script (SectionID, Section,Summary,Severity)
	SELECT 10, LEFT(mf.physical_name, 2) + '\ '
			+ ' ; ' + CONVERT(VARCHAR(250),SUM(io_stall)/SUM(num_of_reads+num_of_writes)) + ' (ms)'
			+ ' ; ' + CONVERT(VARCHAR(25),(CONVERT(MONEY,SUM([num_of_reads])) + SUM([num_of_writes])) * 8 /1024/1024/ CONVERT(MONEY,@DaysUptime))+ 'GB/day'
			+ '; Free space: ' + CONVERT(VARCHAR(20), MAX(CAST(fd.FreeSpaceMB / 1024 as decimal(20,2)))) + 'GB'
			, ' ; ' + CASE 
			WHEN SUM(num_of_reads) = 0 THEN '0' 
			ELSE CONVERT(VARCHAR(25),SUM(io_stall_read_ms)/SUM(num_of_reads)
			 ) END + ' (ms)'
			 
			+ ' ; ' + CASE 
			WHEN SUM(num_of_writes) = 0 THEN '0' 
			ELSE CONVERT(VARCHAR(25),SUM(io_stall_write_ms)/SUM(num_of_writes)
			 ) END + ' (ms)'
			 
			, CASE 
			WHEN SUM(num_of_reads+num_of_writes) = 0 THEN ''
			WHEN SUM(io_stall)/SUM(num_of_reads+num_of_writes) < 10 THEN @Result_Good
			WHEN SUM(io_stall)/SUM(num_of_reads+num_of_writes) BETWEEN 10 AND 100 THEN @Result_Warning
			WHEN SUM(io_stall)/SUM(num_of_reads+num_of_writes) > 100 THEN @Result_YourServerIsDead
			ELSE ''
			END 
	
			FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
			INNER JOIN sys.master_files AS mf WITH (NOLOCK)
			ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
			INNER JOIN @fixeddrives fd ON fd.drive COLLATE DATABASE_DEFAULT = LEFT(mf.physical_name, 1) COLLATE DATABASE_DEFAULT
		  
			GROUP BY LEFT(mf.physical_name, 2)

	INSERT #output_man_script (SectionID, Section,Summary,Severity, Details)
	SELECT 10, LEFT ([f].[physical_name], 2) + '\ '
			+ '; ' + DB_NAME ([s].[database_id]) 
			+ '; '+ CONVERT(VARCHAR(20), CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0) THEN 0 ELSE ([io_stall] / ([num_of_reads] + [num_of_writes])) END) + ' (ms)'
			+ '; '+ CONVERT(VARCHAR(20),CASE WHEN [num_of_reads] + [num_of_writes] = 0 THEN 0 ELSE CONVERT(MONEY,([num_of_reads] + [num_of_writes])) * 8 /1024/1024/ CONVERT(MONEY,@DaysUptime) END ) + 'GB/day'
			, CONVERT(VARCHAR(20),CASE WHEN [num_of_reads] = 0 THEN 0 ELSE ([io_stall_read_ms] / [num_of_reads]) END ) + ' (ms)'
			+ '; '+CONVERT(VARCHAR(20),CASE WHEN [num_of_writes] = 0 THEN 0 ELSE ([io_stall_write_ms] / [num_of_writes]) END ) + ' (ms)'
			, CASE 
			WHEN (num_of_reads+num_of_writes) = 0 THEN ''
			WHEN (io_stall)/(num_of_reads+num_of_writes) < 10 THEN @Result_Good
			WHEN (io_stall)/(num_of_reads+num_of_writes) BETWEEN 10 AND 100 THEN @Result_Warning
			WHEN (io_stall)/(num_of_reads+num_of_writes) > 100 THEN @Result_YourServerIsDead
			ELSE ''
			END
			, [f].type_desc  COLLATE DATABASE_DEFAULT
			+ '; '+ [f].[physical_name]  COLLATE DATABASE_DEFAULT

	FROM sys.dm_io_virtual_file_stats (NULL,NULL) AS [s]
	JOIN sys.master_files AS [f] ON [s].[database_id] = [f].[database_id] AND [s].[file_id] = [f].[file_id]

	ORDER BY [f].[database_id], [f].[file_id],LEFT ([f].[physical_name], 2)
	
	IF @Debug = 0
		RAISERROR (N'Checked for disk latency and space',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Check for disk space on the server
			----------------------------------------*/



	SELECT @Kb = 1024.0;
	SELECT @PageSize=v.low/@Kb 
	FROM master..spt_values v 
	WHERE v.number=1 AND v.type='E';

	INSERT @LogSpace 
	EXEC sp_executesql N'DBCC sqlperf(logspace) WITH NO_INFOMSGS';
	
	INSERT #LogSpace
	SELECT DatabaseName
	, LogSize
	, SpaceUsedPercent
	, Status 
	, NULL
	FROM @LogSpace 
	OPTION (RECOMPILE)
	DECLARE @SecondaryReadRole NVARCHAR(250)
	DECLARE @AGBackupPref NVARCHAR(250)

	SET @Databasei_Count = 1; 
	WHILE @Databasei_Count <= @Databasei_Max 
	BEGIN 
		SELECT @DatabaseName = d.databasename
		, @DatabaseState = d.state 
		, @AGBackupPref = BackupPref
		, @SecondaryReadRole = ReadSecondary
		FROM @Databases d WHERE id = @Databasei_Count AND d.state NOT IN (2,6)
		IF (@SecondaryReadRole <> 'NO' AND @AGBackupPref <> 'primary') AND EXISTS( SELECT @DatabaseName)
		BEGIN
			SET @dynamicSQL = 'USE [' + @DatabaseName + '];
			DBCC showfilestats WITH NO_INFOMSGS;'
			INSERT @FileStats
			EXEC sp_executesql @dynamicSQL;
			SET @dynamicSQL = 'USE [' + @DatabaseName + '];
			SELECT ''' +@DatabaseName + ''', filename, size, ISNULL(FILEGROUP_NAME(groupid),''LOG''), [name] ,maxsize, growth  FROM dbo.sysfiles sf ; '
			
			INSERT @FileSize 
			EXEC sp_executesql @dynamicSQL;
			SET @dynamicSQL = 'USE [' + @DatabaseName + '];
			DBCC loginfo WITH NO_INFOMSGS;'

			INSERT #dbccloginfo
			EXEC sp_executesql @dynamicSQL;

			SELECT @VLFcount = COUNT(*) FROM #dbccloginfo 
			DELETE FROM #dbccloginfo
			UPDATE #LogSpace SET VLFCount =  @VLFcount WHERE DatabaseName = @DatabaseName
		END
		SET @Databasei_Count = @Databasei_Count + 1
	END

	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 11, 'DATABASE FILES - Disk Usage Ordered by largest','------','------'
	INSERT #output_man_script (SectionID, Section,Summary, Severity, Details)

	SELECT 11,
	REPLICATE('|',100-[FreeSpace %]) + REPLICATE('''',[FreeSpace %]) +' ('+ CONVERT(VARCHAR(20),CONVERT(INT,ROUND(100-[FreeSpace %],0))) + '% of ' + CONVERT(VARCHAR(20),CONVERT(MONEY,FileSize/1024)) + ')'
	, (
	+ 'DB size:'
	+ CONVERT(VARCHAR(20),CONVERT(MONEY,TotalSize/1024))
	+ ' GB; DB:'
	+ DatabaseName 
	+ '; SizeGB:'
	+ CONVERT(VARCHAR(20),CONVERT(MONEY,FileSize/1024))
	+ '; Growth:'
	+ CASE WHEN growth <= 100 THEN CONVERT(VARCHAR(20),growth) + '%' ELSE CONVERT(VARCHAR(20),growth/128) + 'MB' END 
	)
	, CASE WHEN [FreeSpace %] < 5 THEN @Result_ReallyBad WHEN [FreeSpace %] < 10 THEN @Result_Warning ELSE @Result_Good END
	,(UPPER(DriveLetter)
	+' FG:'
	+ FileGroupName 
	+ CASE WHEN FileGroupName = 'LOG' THEN '(' + CONVERT(VARCHAR(20),VLFCount) + 'vlfs)' ELSE '' END
	--, LogicalName  
	+ '; MAX:'
	+ CONVERT(VARCHAR(20),maxsize)
	+ '; Used:' 
	+ CONVERT(VARCHAR(20),100-[FreeSpace %] )
	+'%'
	+'; Path:'
	+ [FileName] 
	)
 

	FROM (
	SELECT
	 DatabaseName = fsi.DatabaseName
	 , fs2.TotalSize
	 , FileGroupName = fsi.FileGroupName
	 , maxsize
	 , growth
	 , LogicalName = RTRIM(fsi.LogicalName)
	 , [FileName] = RTRIM(fsi.FileName)
	 , DriveLetter = LEFT(RTRIM(fsi.FileName),2)
	 , FileSize = CAST(fsi.FileSize*@PageSize/@Kb as decimal(15,2))
	 , UsedSpace = CAST(ISNULL((fs.UsedExtents*@PageSize*8.0/@Kb), fsi.FileSize*@PageSize/@Kb * ls.SpaceUsedPercent/100.0) as MONEY )
	 , FreeSpace = CAST(ISNULL(((fsi.FileSize - UsedExtents*8.0)*@PageSize/@Kb), (100.0-ls.SpaceUsedPercent)/100.0 * fsi.FileSize*@PageSize/@Kb) as MONEY )
	 ,[FreeSpace %] = CAST(ISNULL(((fsi.FileSize - UsedExtents*8.0) / fsi.FileSize * 100.0), 100-ls.SpaceUsedPercent) as MONEY ) 
	 , VLFCount 
	FROM @FileSize fsi  
	LEFT JOIN @FileStats fs ON fs.FileName = fsi.FileName  
	LEFT JOIN #LogSpace ls ON ls.DatabaseName COLLATE DATABASE_DEFAULT = fsi.DatabaseName   COLLATE DATABASE_DEFAULT
	LEFT OUTER JOIN  (SELECT DatabaseName, SUM(CAST(FileSize*@PageSize/@Kb as decimal(15,2))) TotalSize FROM @FileSize F1 GROUP BY DatabaseName) fs2 ON  fs2.DatabaseName COLLATE DATABASE_DEFAULT =  fsi.DatabaseName COLLATE DATABASE_DEFAULT
	 ) T1
	WHERE T1.[FreeSpace %] < (CASE WHEN @ShowWarnings = 1 THEN 20 ELSE 100 END)
	ORDER BY TotalSize DESC, DatabaseName ASC, FileSize DESC
	OPTION (RECOMPILE)
	IF @Debug = 0
		RAISERROR (N'Checked free space',0,1) WITH NOWAIT;


			/*----------------------------------------
			--Look at caching plans,  size matters here
			----------------------------------------*/
	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 12, 'CACHING PLANS - as % of total memory used by SQL','------','------'
	INSERT #output_man_script (SectionID, Section,Summary ,Details )
	SELECT 12, REPLICATE('|',[1 use size]/[Size MB]*100) + REPLICATE('''',100- [1 use size]/[Size MB]*100) +' '+ CONVERT(VARCHAR(20),CONVERT(INT,[1 use size]/[Size MB]*100)) +'% of '
	+CONVERT(VARCHAR(20),CONVERT(BIGINT,[Size MB])) +'MB is 1 use' 
	, objtype 
	+'; Plans:'+ CONVERT(VARCHAR(20),[Total Use])
	+'; Total Refs:'+ CONVERT(VARCHAR(20),[Total Rfs])
	+'; Avg Use:'+ CONVERT(VARCHAR(20),[Avg Use])
	, CONVERT(VARCHAR(20),[Size MB]) + 'MB'
	+'; Single use:'+ CONVERT(VARCHAR(20),[1 use size]*100/[Size MB]) + '%'
	+'; Single plans:'+ CONVERT(VARCHAR(20),[1 use count])

	FROM (
	SELECT objtype
	, SUM(refcounts)[Total Rfs]
	, AVG(refcounts) [Avg Refs]
	, SUM(cast(usecounts as bigint)) [Total Use]
	, AVG(cast(usecounts as bigint)) [Avg Use]
	, CONVERT(MONEY,SUM(size_in_bytes*0.000000953613)) [Size MB]
	, SUM(CASE WHEN usecounts = 1 THEN 1 ELSE 0 END) [1 use count]
	, SUM(CASE WHEN usecounts = 1 THEN CONVERT(MONEY,size_in_bytes*0.000000953613) ELSE 0 END) [1 use size]
	FROM sys.dm_exec_cached_plans GROUP BY objtype
	) TCP
	OPTION (RECOMPILE)

	IF @Debug = 0
		RAISERROR (N'Got cached plan statistics',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Get the top 10 query plan bloaters for single use queries
			----------------------------------------*/

	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 13,'CACHING PLANS - TOP 10 single use plans','------','------'
	INSERT #output_man_script (SectionID, Section,Summary ,Details )
	SELECT TOP(10) 13, CONVERT(VARCHAR(20),CONVERT(MONEY,cp.size_in_bytes)/1024) + 'KB'
	, cp.cacheobjtype
	+ ' '+ cp.objtype
	+ '; SizeMB:' + CONVERT(VARCHAR(20),CONVERT(MONEY,cp.size_in_bytes)/1024/1000)
	, ''AS [QueryText]
	/*Need to become more clever to do this bit
	replace(replace(replace(replace(LEFT(CONVERT(NVARCHAR(4000),[text]),@LeftText), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ') */
	FROM sys.dm_exec_cached_plans AS cp WITH (NOLOCK)
	CROSS APPLY sys.dm_exec_sql_text(plan_handle) 
	WHERE cp.cacheobjtype = N'Compiled Plan' 
	AND cp.objtype IN (N'Adhoc', N'Prepared') 
	AND cp.usecounts = 1
	ORDER BY cp.size_in_bytes DESC OPTION (RECOMPILE);

	IF @Debug = 0
		RAISERROR (N'Got cached plan statistics - Biggest single use plans',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Find cpu load, io and memory per DB
			----------------------------------------*/
	IF @Debug = 0
		RAISERROR (N'Reading buffer pages takes longer on higher memory servers',0,1) WITH NOWAIT;
	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 14, 'Database: CPU IO Memory DISK DiskIO Latency','------','------'
	INSERT #output_man_script (SectionID, Section,Summary ,Details )
	SELECT 14,'Breakdown', 'DBName; CPU; IO; Buffer; DiskUsage(GB); Disk IO daily (GB); Latency (ms)', 'CPU time(s); Total IO; Buffer Pages; Buffer MB'
	
	INSERT #output_man_script (SectionID, Section,Summary ,Details )
SELECT 14,  REPLICATE('|',CONVERT(MONEY,T2.[TotalIO])/ SUM(T2.[TotalIO]) OVER()* 100.0) 
	+ REPLICATE('''',100 - CONVERT(MONEY,T2.[TotalIO])/ SUM(T2.[TotalIO]) OVER()* 100.0) + '' + CONVERT(VARCHAR(20), CONVERT(INT,ROUND(CONVERT(MONEY,T2.[TotalIO])/ SUM(T2.[TotalIO]) OVER()* 100.0,0))) +'% IO '
	, T1.DatabaseName
	+ '; ' + ISNULL(CONVERT(VARCHAR(20),CONVERT(INT,ROUND([CPU_Time(Ms)]/1000 * 1.0 /SUM([CPU_Time(Ms)]/1000) OVER()* 100.0,0))),'0') +'%'
	+ '; ' +  ISNULL(CONVERT(VARCHAR(20),CONVERT(INT,ROUND(CONVERT(MONEY,T2.[TotalIO])/ SUM(T2.[TotalIO]) OVER()* 100.0 ,0))) ,'0')+'%'
	+ '; ' +  ISNULL(CONVERT(VARCHAR(20),CONVERT(INT,ROUND(CONVERT(MONEY,src.db_buffer_pages )/ SUM(src.db_buffer_pages ) OVER()* 100.0 ,0))),'0')+'%'
	+ '; ' +  + ISNULL(CONVERT(VARCHAR(20),CONVERT(MONEY,TotalSize/1024)),'')
	+ '; ' + DBlatency.[GB/day] +'(GB)'
	+ '; ' + DBlatency.[Latency]
	,  ISNULL(CONVERT(VARCHAR(20),[CPU_Time(Ms)]) + ' (' + CONVERT(VARCHAR(20),CAST([CPU_Time(Ms)]/1000 * 1.0 /SUM([CPU_Time(Ms)]/1000) OVER()* 100.0 AS DECIMAL(5, 2))) + '%)','') 
	+ '; ' +  ISNULL(CONVERT(VARCHAR(20),[TotalIO]) + ' ; Reads: ' + CONVERT(VARCHAR(20),T2.[Number of Reads]) +' ; Writes: '+ CONVERT(VARCHAR(20),T2.[Number of Writes]),'')
	+ '; ' +  ISNULL(CONVERT(VARCHAR(20),src.db_buffer_pages),'')
	+ '; '+ CONVERT(VARCHAR(20),src.db_buffer_pages / 128) 

	FROM(
		SELECT TOP 100 PERCENT
		DatabaseID
		,DB_Name(DatabaseID)AS [DatabaseName]
		,SUM(total_worker_time)AS [CPU_Time(Ms)]
		FROM sys.dm_exec_query_stats AS qs
		CROSS APPLY
		(
			SELECT CONVERT(int, value)AS [DatabaseID]
			FROM sys.dm_exec_plan_attributes(qs.plan_handle)
			WHERE attribute =N'dbid'
		)AS epa
		GROUP BY DatabaseID
		ORDER BY SUM(total_worker_time) DESC
	) T1
	LEFT OUTER JOIN (
	SELECT
		Name AS 'DatabaseName'
		, SUM(num_of_reads) AS'Number of Reads'
		, SUM(num_of_writes) AS'Number of Writes'
		, SUM(num_of_writes) +  SUM(num_of_reads) [TotalIO]
		FROM sys.dm_io_virtual_file_stats(NULL,NULL) I
		INNER JOIN sys.databases d ON I.database_id = d.database_id
		GROUP BY Name
	) T2 ON T1.DatabaseName = T2.DatabaseName
	LEFT OUTER JOIN 
	(
		SELECT database_id,
		db_buffer_pages =COUNT_BIG(*)
		FROM sys.dm_os_buffer_descriptors
		GROUP BY database_id
	) src ON src.database_id = T1.DatabaseID
	LEFT OUTER JOIN  (SELECT DatabaseName, SUM(CAST(FileSize*@PageSize/@Kb as decimal(15,2))) TotalSize FROM @FileSize F1 GROUP BY DatabaseName) fs2 ON  fs2.DatabaseName COLLATE DATABASE_DEFAULT =  T2.DatabaseName COLLATE DATABASE_DEFAULT
	
	LEFT OUTER JOIN (
	SELECT  DB_NAME ([s].[database_id]) [DBName] 
			, CONVERT(VARCHAR(20), CASE WHEN (SUM([num_of_reads]) = 0 AND SUM([num_of_writes]) = 0) THEN 0 
			ELSE (SUM([io_stall]) / (SUM([num_of_reads]) + SUM([num_of_writes]))) END) + ' (ms)' [Latency]
			, CONVERT(VARCHAR(20),CASE WHEN SUM([num_of_reads]) + SUM([num_of_writes]) = 0 THEN 0 
			ELSE CONVERT(MONEY,(SUM([num_of_reads]) + SUM([num_of_writes]))) * 8 /1024/1024/ CONVERT(MONEY,@DaysUptime) END ) [GB/day]
			, CONVERT(VARCHAR(20),CASE WHEN SUM([num_of_reads]) + SUM([num_of_writes]) = 0 THEN 0 
			ELSE CONVERT(MONEY,(SUM(CONVERT(MONEY,[num_of_reads])) + SUM([num_of_writes]))) END) [DBTotalIO]
		FROM sys.dm_io_virtual_file_stats (NULL,NULL) AS [s]
		JOIN sys.master_files AS [f] ON [s].[database_id] = [f].[database_id] AND [s].[file_id] = [f].[file_id]
		GROUP BY DB_NAME ([s].[database_id]) 

	) DBlatency ON DBlatency.DBName =  T1.DatabaseName
	WHERE T1.DatabaseName IS NOT NULL
	ORDER BY [TotalIO] DESC,[CPU_Time(Ms)] DESC
	OPTION (RECOMPILE) ;

	IF @Debug = 0
		RAISERROR (N'Checked CPU, IO  and memory usage',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Get to wait types, the TOP 10 would be good for now
			----------------------------------------*/

	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 15, 'TOP 10 WAIT STATS','------','------'
	
	--INSERT @Waits 
	INSERT #output_man_script (SectionID, Section,Summary,Severity,HoursToResolveWithTesting )
	SELECT TOP 10 15,
	REPLICATE ('|', 100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER())+ REPLICATE ('''', 100- 100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER()) + CONVERT(VARCHAR(20), CONVERT(INT,ROUND(100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER(),0))) + '%'
	, S.[wait_type] + ':' 
	+ ';HH:' + CONVERT(VARCHAR(20),CONVERT(MONEY,SUM(wait_time_ms / 1000.0 / 60 / 60) OVER (PARTITION BY S.[wait_type])))
	+ ':MM/HH/VCPU:' + CONVERT(VARCHAR(20),CONVERT(MONEY,SUM(60.0 * wait_time_ms) OVER (PARTITION BY S.[wait_type]) / @minutesSinceRestart /60000/@CPUcount))
	+'; Wait(s):'+ CONVERT(VARCHAR(20),CONVERT(BIGINT,[wait_time_ms] / 1000.0)) + '(s)'
	+'; Wait count:' + CONVERT(VARCHAR(20),[waiting_tasks_count])
	, CASE 
		WHEN CONVERT(MONEY,SUM(60.0 * wait_time_ms) OVER (PARTITION BY S.[wait_type]) / @minutesSinceRestart /60000/@CPUcount) BETWEEN 10 AND 30 THEN @Result_Warning
		WHEN CONVERT(MONEY,SUM(60.0 * wait_time_ms) OVER (PARTITION BY S.[wait_type]) / @minutesSinceRestart /60000/@CPUcount) > 30 THEN  @Result_YourServerIsDead
		ELSE @Result_Good END
	, CASE 
		WHEN S.[wait_type] = 'CXPACKET' THEN 5
		WHEN S.[wait_type] LIKE 'PAGEIOLATCH%' THEN 8
		ELSE 0
	END


	FROM sys.dm_os_wait_stats S
	LEFT OUTER JOIN #IgnorableWaits W ON W.wait_type = S.[wait_type]
	WHERE W.wait_type IS NULL
	AND [waiting_tasks_count] > 0
	ORDER BY [wait_time_ms] DESC
	OPTION (RECOMPILE)

	IF @Debug = 0
		RAISERROR (N'Filtered wait stats have been prepared',0,1) WITH NOWAIT;

	IF @Debug = 0
		RAISERROR (N'Looking at query stats.. this might take a wee while',0,1) WITH NOWAIT;
			/*----------------------------------------
			--Look at Plan Cache and DMV to find missing index impacts
			----------------------------------------*/

	INSERT #querystats
			      SELECT TOP 100 PERCENT
				(RANK() OVER(ORDER BY(qs.total_logical_writes + qs.total_logical_reads)) 
			 + RANK() OVER(ORDER BY qs.total_elapsed_time DESC) )/2 [RankIOTime]
			 ,qs.execution_count
			, qs.total_logical_reads
			,  CONVERT(MONEY,qs.total_logical_reads)/1000 [Total_MBsRead]
			, qs.total_logical_writes
			,  CONVERT(MONEY,qs.total_logical_writes)/1000 [Total_MBsWrite]
			, qs.total_worker_time,  CONVERT(MONEY,qs.total_elapsed_time)/1000000 total_elapsed_time_in_S
			, qs.total_elapsed_time
			, qs.last_execution_time
			, qs.plan_handle
			, qs.sql_handle
			FROM #dadatafor_exec_query_stats qs WITH (NOLOCK)
			WHERE  CONVERT(MONEY,qs.total_logical_writes + qs.total_logical_reads)/1000 > 10 /*10MB total activity*/
			/* Change order by ORDER BY [RankIOTime] ASC*/
			ORDER BY total_elapsed_time/execution_count DESC
	BEGIN TRY

	INSERT #output_man_script (SectionID, Section,Summary, Details, QueryPlan) SELECT 16, 'PLAN INSIGHT - MISSING INDEX','------','------',NULL
	INSERT #output_man_script (SectionID, Section,Summary, Details, QueryPlan,HoursToResolveWithTesting)
	SELECT 16,
		REPLICATE('|',TFF.[SecondsSavedPerDay]/28800*100) + ' $' + CONVERT(VARCHAR(20),CONVERT(MONEY,TFF.[SecondsSavedPerDay]/28800) * @FTECost) + 'pa ('+CONVERT(VARCHAR(20),CONVERT(MONEY,TFF.[SecondsSavedPerDay]/28800) )+ 'FTE)' [Section]
		,CONVERT(VARCHAR(20),TFF.execution_count) + ' executions'
		+ '; Cost:' + CONVERT(VARCHAR(20),TFF.SubTreeCost)
		+ '; GuessingCost(s):' + CONVERT(VARCHAR(20),(ISNULL(TFF.SubTreeCost * TFF.execution_count * (100-TFF.impact),0)))
		+ '(@secondsperoperator) ' + CONVERT(VARCHAR(20),@secondsperoperator) +'; Impact:' +CONVERT(VARCHAR(20), TFF.impact)
		+ '; EstRows:' + CONVERT(VARCHAR(20),TFF.estRows)
		+ '; Magic:' + CONVERT(VARCHAR(20),TFF.Magic)
		+ '; ' + CONVERT(VARCHAR(20), TFF.SecondsSavedPerDay) + '(s)'
		+ '; Total time:' + CONVERT(VARCHAR(20),TFF.total_elapsed_time/1000/1000) + '(s)' [Summary]
		, ';'+TFF.[statement] 
		+ ISNULL(':EQ:'+ TFF.equality_columns,'')
		+ ISNULL(':INEQ:'+ TFF.inequality_columns,'')
		+ ISNULL(':INC:'+ TFF.include_columns,'') [Details]
		, tp.query_plan
		, CONVERT(VARCHAR(20),CONVERT(MONEY,TFF.[SecondsSavedPerDay]/28800 * 8 * 3))
		FROM (
		SELECT 
		 SUM(TF.SubTreeCost) SubTreeCost
		, SUM(CONVERT(FLOAT,TF.estRows )) estRows
		, SUM(ISNULL([Magic],0)) [Magic]
		, SUM(TF.impact/100 * TF.total_elapsed_time )/1000000/@DaysOldestCachedQuery  [SecondsSavedPerDay]
		, TF.impact	
		, TF.execution_count	
		, TF.total_elapsed_time	
		, TF.database_id	
		, TF.OBJECT_ID	
		, TF.statement	
		, TF.equality_columns	
		, TF.inequality_columns	
		, TF.include_columns
		, TF.plan_handle
	
		FROM
		(
		SELECT 
		--, query_plan
		--, n.value('(@StatementText)[1]', 'VARCHAR(4000)') AS sql_text
		  CONVERT(FLOAT,n.value('(@StatementSubTreeCost)', 'VARCHAR(4000)')) AS SubTreeCost
		, n.value('(@StatementEstRows)', 'VARCHAR(4000)') AS estRows
		, CONVERT(FLOAT,n.value('(//MissingIndexGroup/@Impact)[1]', 'FLOAT')) AS impact
		, tab.execution_count
		, tab.total_elapsed_time
		, tab.plan_handle
		, DB_ID(REPLACE(REPLACE(n.value('(//MissingIndex/@Database)[1]', 'VARCHAR(128)'),'[',''),']','')) AS database_id
		, OBJECT_ID(n.value('(//MissingIndex/@Database)[1]', 'VARCHAR(128)') + '.' + 
				   n.value('(//MissingIndex/@Schema)[1]', 'VARCHAR(128)') + '.' + 
				   n.value('(//MissingIndex/@Table)[1]', 'VARCHAR(128)')) AS OBJECT_ID, 
			   n.value('(//MissingIndex/@Database)[1]', 'VARCHAR(128)') + '.' + 
				   n.value('(//MissingIndex/@Schema)[1]', 'VARCHAR(128)') + '.' + 
				   n.value('(//MissingIndex/@Table)[1]', 'VARCHAR(128)')  
			   AS statement, 
			   (   SELECT DISTINCT c.value('(@Name)[1]', 'VARCHAR(128)') + ', ' 
				   FROM n.nodes('//ColumnGroup') AS t(cg) 
				   CROSS APPLY cg.nodes('Column') AS r(c) 
				   WHERE cg.value('(@Usage)[1]', 'VARCHAR(128)') = 'EQUALITY' 
				   FOR  XML PATH('') 
			   ) AS equality_columns, 
				(  SELECT DISTINCT c.value('(@Name)[1]', 'VARCHAR(128)') + ', ' 
				   FROM n.nodes('//ColumnGroup') AS t(cg) 
				   CROSS APPLY cg.nodes('Column') AS r(c) 
				   WHERE cg.value('(@Usage)[1]', 'VARCHAR(128)') = 'INEQUALITY' 
				   FOR  XML PATH('') 
			   ) AS inequality_columns, 
			   (   SELECT DISTINCT c.value('(@Name)[1]', 'VARCHAR(128)') + ', ' 
				   FROM n.nodes('//ColumnGroup') AS t(cg) 
				   CROSS APPLY cg.nodes('Column') AS r(c) 
				   WHERE cg.value('(@Usage)[1]', 'VARCHAR(128)') = 'INCLUDE' 
				   FOR  XML PATH('') 
			   ) AS include_columns 

		FROM  
		( 
		   SELECT query_plan
		   , qs.*
		   FROM (    
					SELECT plan_handle
					,SUM(qs.execution_count			)execution_count
					,MAX(qs.total_elapsed_time		)total_elapsed_time
				   FROM #querystats qs WITH(NOLOCK)
				   WHERE qs.Id <= @TopQueries  
				   GROUP BY  plan_handle
				   HAVING SUM(qs.total_elapsed_time ) > @MinWorkerTime
				 ) AS qs 
			OUTER APPLY sys.dm_exec_query_plan(qs.plan_handle) tp  
			WHERE tp.query_plan.exist('//MissingIndex')=1 
				--AND qs.execution_count > @MinExecutionCount   
		) AS tab 
		CROSS APPLY query_plan.nodes('//StmtSimple') AS q(n) 
		) TF
		INNER JOIN @Databases d ON d.database_id = TF.database_id
		LEFT OUTER JOIN (
		SELECT TOP 100 PERCENT (( ISNULL(user_seeks,0) + ISNULL(user_scans,0 ) * avg_total_user_cost * avg_user_impact)/1) [Magic]
		,user_seeks 
		,user_scans
		,user_seeks + user_scans AllScans
		,avg_total_user_cost
		,avg_user_impact
		, mid.object_id
		, [statement]
		, equality_columns
		, inequality_columns
		, included_columns
		FROM sys.dm_db_missing_index_group_stats AS migs 
				INNER JOIN sys.dm_db_missing_index_groups AS mig ON migs.group_handle = mig.index_group_handle 
				INNER JOIN sys.dm_db_missing_index_details AS mid ON mig.index_handle = mid.index_handle 
				LEFT OUTER JOIN sys.objects WITH (nolock) ON mid.OBJECT_ID = sys.objects.OBJECT_ID 
				ORDER BY [Magic] DESC
		) TStats ON TStats.object_id = TF.OBJECT_ID
		AND TStats.statement = TF.statement
		AND ISNULL(TStats.equality_columns +', ',0) = ISNULL(TF.equality_columns ,0)
		AND ISNULL(TStats.inequality_columns +', ',0) = ISNULL(TF.inequality_columns,0)
		AND ISNULL(TStats.included_columns +', ',0) = ISNULL(TF.include_columns,0)

		GROUP BY  TF.impact	
		, TF.execution_count
		, TF.total_elapsed_time	
		, TF.database_id	
		, TF.OBJECT_ID	
		, TF.statement	
		, TF.equality_columns	
		, TF.inequality_columns	
		, TF.include_columns
		, TF.plan_handle
		) TFF
		OUTER APPLY sys.dm_exec_query_plan(TFF.plan_handle) tp  
		--WHERE [statement] <> '[msdb].[dbo].[backupset]'
		ORDER BY  [SecondsSavedPerDay] DESC, total_elapsed_time DESC OPTION (RECOMPILE);
	END TRY
	BEGIN CATCH
		IF @Debug = 0
			RAISERROR	  (N'ERROR Section 16 looking for missing indexes in Query plan',0,1) WITH NOWAIT;
	END CATCH


	BEGIN TRY
	INSERT #output_man_script (SectionID, Section,Summary, Details, QueryPlan) SELECT 17,'PLAN INSIGHT - EVERYTHING','------','------',NULL
	INSERT #output_man_script (SectionID, Section,Summary, Details, QueryPlan) 
	
	SELECT  17,
	 /*Bismillah, Find most intensive query*/
	REPLICATE ('|', CASE WHEN [Total_GBsRead]*[Impact%] = 0 THEN 0 ELSE 100.0 * [Total_GBsRead]*[Impact%]  / SUM ([Total_GBsRead]*[Impact%]) OVER() END)   
	+ CASE WHEN [Impact%] > 0 THEN CONVERT(VARCHAR(20),CONVERT(INT,ROUND(100.0 * [Total_GBsRead]*[Impact%]  / SUM ([Total_GBsRead]*[Impact%]) OVER(),0))) + '%' ELSE '' END [Section]

		, CONVERT(VARCHAR(20),[execution_count])
		+' events'
		+CASE 
			WHEN [Impact%] > 0 AND [ImpactType] = 'Missing Index'   THEN ' Impacted by: Missing Index (' + CONVERT(VARCHAR(20),[Impact%]) + '%)'
			WHEN [Impact%] > 0 AND [ImpactType] ='CONVERT_IMPLICIT' THEN ' Impacted by: CONVERT_IMPLICIT' 
			ELSE '' END  
		+ '; ' + CONVERT(VARCHAR(20),[Total_GBsRead]) +'GBs of I/O'
		+ '(' + CONVERT(VARCHAR(20),[total_logical_reads]) + ' pages)'
		+' took:' + CONVERT(VARCHAR(20),[total_elapsed_time_in_S]) +'(seconds)' [Summary]
		, ISNULL([Database] +':','')
		+ CASE WHEN [Impact%] > 0
		THEN 'Could reduce to: ' + CONVERT(VARCHAR(20), [Total_GBsRead] -([Impact%]/100 * [Total_GBsRead])) + 'GB'+ ' in ' + CONVERT(VARCHAR(20), CONVERT(INT,[total_elapsed_time_in_S] -([Impact%]/100) * [total_elapsed_time_in_S])) +'(s)'
		ELSE ''
		END
		+ '; Writes:'+ CONVERT(VARCHAR(20),[total_logical_writes])
		+ '(' + CONVERT(VARCHAR(20),[Total_GBsWrite]) + 'GB)' [Details]
		--, T1.[total_worker_time], T1.[last_execution_time]
		, [query_plan] /*This makes the query crawl, only add back when you have time or need to see the full plans, but you dont want this for 10k rows*/
		FROM (
	
		SELECT TOP 100 PERCENT
		CASE 
		WHEN PATINDEX('%MissingIndexes%',CAST(qp.query_plan AS NVARCHAR(MAX))) > 0 THEN 'Missing Index' 
		WHEN PATINDEX('%PlanAffectingConvert%',CAST(qp.query_plan AS NVARCHAR(MAX))) > 0 THEN 'CONVERT_IMPLICIT' ELSE NULL END  [ImpactType]
		, CASE 
		WHEN PATINDEX('%MissingIndexGroup Impact%',CAST(qp.query_plan AS NVARCHAR(MAX))) > 0  
			THEN CONVERT(MONEY,REPLACE(REPLACE(REPLACE(SUBSTRING(CONVERT(NVARCHAR(MAX),qp.query_plan),PATINDEX('%MissingIndexGroup Impact%',CAST(qp.query_plan AS NVARCHAR(MAX)))+26,6),'"><',''),'"',''),'>',''))
		ELSE NULL 
		END [Impact%]
		, T1.[execution_count], T1.[total_logical_reads], T1.[total_logical_writes]
		, [Total_MBsRead]/1000 [Total_GBsRead]
		, [Total_MBsWrite]/1000 [Total_GBsWrite]
		, T1.[total_worker_time], T1.[total_elapsed_time_in_S],  T1.[last_execution_time]
		, CASE WHEN @ShowQueryPlan = 1 THEN replace(replace(replace(replace(replace(CONVERT(NVARCHAR(MAX),qt.[Text]),CHAR(13)+CHAR(10),' '),CHAR(10)+CHAR(13),' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ')
			ELSE '' END [QueryText]
		, qp.[query_plan]
		, DB_NAME(qp.dbid) [Database]
		, OBJECT_NAME(qp.objectid) [Object]
		FROM 
		#querystats T1
		CROSS APPLY sys.dm_exec_query_plan(T1.plan_handle) qp
		CROSS APPLY sys.dm_exec_sql_text(T1.sql_handle) qt
		INNER JOIN @Databases d ON d.database_id = qp.dbid
		WHERE T1.Id <= @TopQueries
		--WHERE PATINDEX('%MissingIndex%',CAST(query_plan AS NVARCHAR(MAX))) > 0
		ORDER BY CASE WHEN  PATINDEX('%MissingIndexes%',CAST(qp.query_plan AS NVARCHAR(MAX)))  > 0 THEN 1 ELSE 0 END DESC
		,CASE WHEN  PATINDEX('%MissingIndexes%',CAST(qp.query_plan AS NVARCHAR(MAX))) > 0 
		 THEN  PATINDEX('%MissingIndexes%',CAST(qp.query_plan AS NVARCHAR(MAX))) * [Total_MBsRead]  ELSE 0 END DESC 
	
		) q 
		ORDER BY CASE WHEN [Impact%] > 0 THEN 1 ELSE 0 END DESC, [Total_GBsRead]*[Impact%] DESC OPTION (RECOMPILE);
	END TRY
	BEGIN CATCH
		IF @Debug = 0
			RAISERROR	  (N'ERROR Section 17 Find most intensive query',0,1) WITH NOWAIT;
	END CATCH

	IF @Debug = 0
		RAISERROR	  (N'Evaluated execution plans for missing indexes',0,1) WITH NOWAIT;


			/*----------------------------------------
			--Get missing index information for each database
			----------------------------------------*/
			IF @Debug = 0
				RAISERROR	  (N'Looking for missing indexes in DMVs',0,1) WITH NOWAIT;
			SET @dynamicSQL = '
			USE [master]
			SELECT LEFT([statement],(PATINDEX(''%.%'',[statement]))-1) [Database]
			,  (( user_seeks + user_scans ) * avg_total_user_cost * avg_user_impact)/' + CONVERT(NVARCHAR,@DaysOldestCachedQuery) + ' daily_magic_benefit_number
			, [Table] = [statement]
			, [CreateIndexStatement] = ''CREATE NONCLUSTERED INDEX IX_LEXEL_'' + REPLACE(REPLACE(REVERSE(LEFT(REVERSE([statement]),(PATINDEX(''%.%'',REVERSE([statement])))-1)),'']'',''''),''['','''')
			+ REPLACE(REPLACE(REPLACE(LEFT(ISNULL(mid.equality_columns,'''')+ISNULL(mid.inequality_columns,''''),15), ''['', ''''), '']'',''''), '', '',''_'') + ''_''+ REPLACE(CONVERT(VARCHAR(20),GETDATE(),102),''.'',''_'') + ''T''  + REPLACE(CONVERT(VARCHAR(20),GETDATE(),108),'':'',''_'') + '' ON '' + [statement] 
			+  '' ( '' 
			+ ''< be clever here > ''
			+  '') ''
			+  ISNULL(''INCLUDE ('' + mid.included_columns + '')'','''')
			' /* Don't be too clever now.
			+ CHAR(13) + CHAR(10) + ''WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, SORT_IN_TEMPDB = ON, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = '+@rebuildonline+', ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON,FILLFACTOR = 98) ON [PRIMARY];''
			*/
			+ '
			, mid.equality_columns
			, mid.inequality_columns
			, mid.included_columns
			, ''SELECT STUFF(( SELECT '''', '''' + [Columns] FROM ( SELECT TOP 25 c1.[id], [Columns], [Count] FROM (
			SELECT ROW_NUMBER() OVER(ORDER BY [RankMe]) [id], LTRIM([Columns]) [Columns] 
			FROM (VALUES('''''' + REPLACE(ISNULL(mid.equality_columns + ISNULL('',''+ mid.inequality_columns,''''),ISNULL(mid.inequality_columns,'''')) ,'','','''''',1),('''''') 
			+'''''',1))t ([Columns],[RankMe]) ) c1 '' 
			+ '' LEFT OUTER JOIN (
			SELECT ROW_NUMBER() OVER(ORDER BY [Count]) [id] ,LTRIM([Count]) [Count] FROM (VALUES((SELECT COUNT (DISTINCT '' + REPLACE(ISNULL(mid.equality_columns + ISNULL('',''+ mid.inequality_columns,''''),ISNULL(mid.inequality_columns,'''')) ,'',''
			,'') FROM '' + [statement] +'')),((SELECT COUNT (DISTINCT '') 
			+'') FROM '' + [statement] +'')))t ([Count]) )c2 ON c2.id = c1.id 
			ORDER BY c2.[Count] * 1 DESC
			) t1 FOR XML PATH('''''''')),1,1,'''''''') AS NameValues'' [BeingClever]
			FROM sys.dm_db_missing_index_group_stats AS migs 
			INNER JOIN sys.dm_db_missing_index_groups AS mig ON migs.group_handle = mig.index_group_handle 
			INNER JOIN sys.dm_db_missing_index_details AS mid ON mig.index_handle = mid.index_handle 
			ORDER BY daily_magic_benefit_number DESC, [CreateIndexStatement] DESC OPTION (RECOMPILE);'

			INSERT #MissingIndex
			EXEC sp_executesql @dynamicSQL;
			
			/*----------------------------------------
			--Loop all the user databases to run database specific commands against them
			----------------------------------------*/
					
	SET @dynamicSQL = ''
	SET @Databasei_Count = 1; 
	WHILE @Databasei_Count <= @Databasei_Max 
	BEGIN 
	
		
		SELECT @DatabaseName = d.databasename
		, @DatabaseState = d.state 
		, @AGBackupPref = BackupPref
		, @SecondaryReadRole = ReadSecondary
		FROM @Databases d WHERE id = @Databasei_Count AND d.state NOT IN (2,6)

		OPTION (RECOMPILE)
		SET @ErrorMessage = 'Looping Database ' + CONVERT(VARCHAR(4),@Databasei_Count) +' of ' + CONVERT(VARCHAR(4),@Databasei_Max ) + ': [' + @DatabaseName + '] ';
		IF @Debug = 0
			RAISERROR (@ErrorMessage,0,1) WITH NOWAIT;
		IF (@SecondaryReadRole <> 'NO' AND @AGBackupPref <> 'primary') AND EXISTS( SELECT @DatabaseName)
		BEGIN  
			
		
	
		/*13. Find idle indexes*/
			/*---------------------------------------Shows Indexes that have never been used---------------------------------------*/
			IF @Debug = 0
				RAISERROR	  (N'Skipping never used indexes',0,1) WITH NOWAIT;
			SET ANSI_WARNINGS OFF
			SET @dynamicSQL = '
			USE ['+@DatabaseName +']
			DECLARE @DaysAgo INT, @TheDate DATETIME
			SET @DaysAgo = 15
			SET @TheDate =  CONVERT(DATETIME,CONVERT(INT,DATEADD(DAY,-@DaysAgo,GETDATE())))
			DECLARE @db_id smallint
			SET @db_id=db_id()
			SELECT db_name(db_id()),
			CASE WHEN b.type_desc = ''CLUSTERED'' THEN ''Consider Carefully'' ELSE ''May remove'' END Consideration
			, t.name TableName, b.type_desc TypeDesc, b.name IndexName, a.user_updates Updates, a.last_user_scan, a.last_user_seek
			--, SUM(aa.page_count) Pages
			FROM sys.dm_db_index_usage_stats as a
			JOIN sys.indexes AS b ON a.object_id = b.object_id AND a.index_id = b.index_id
			LEFT OUTER JOIN sys.tables AS t ON b.[object_id] = t.[object_id]
			--LEFT OUTER JOIN INFORMATION_SCHEMA.TABLES isc ON isc.TABLE_NAME = t.name
			--LEFT OUTER JOIN sys.dm_db_index_physical_stats (@db_id,NULL,NULL, NULL, NULL) AS aa ON aa.object_id = a.object_id
			WHERE b.[type_desc] NOT LIKE ''Heap''
			AND ISNULL(a.user_seeks,0) + ISNULL(a.user_scans,0) + ISNULL(a.system_scans,0) + ISNULL(a.user_lookups,0) = 0
			--AND (DATEDIFF(DAY,a.last_user_scan,GETDATE()) > @DaysAgo AND DATEDIFF(DAY,a.last_user_seek,GETDATE()) > @DaysAgo)
			--AND t.name NOT LIKE ''sys%''
			GROUP BY t.name, b.type_desc, b.name, a.user_updates, a.last_user_scan, a.last_user_seek
			ORDER BY [Updates] DESC OPTION (RECOMPILE)
			'
			INSERT #NeverUsedIndex
			EXEC sp_executesql @dynamicSQL;
			SET ANSI_WARNINGS ON
		/*14. Find heaps*/
			/*---------------------------------------Shows tables without primary key. Heaps---------------------------------------*/
			IF @Debug = 0
				RAISERROR	  (N'Looking for heap tables',0,1) WITH NOWAIT;
			SET @dynamicSQL = '
			USE ['+@DatabaseName +']
				SELECT ''['' + DB_NAME(DB_ID()) + '']'',''['' + OBJECT_SCHEMA_NAME(IDXPS.object_id) +'']'',''['' +OBJECT_NAME(IDXPS.object_id) + '']'' AS table_name
			, IDXPS.forwarded_record_count
			, IDXPS.avg_fragmentation_in_percent Fragmentation_Percentage
			, IDXPS.page_count
			,p.rows
			,user_seeks,user_scans
			,user_lookups,user_updates
			,last_user_seek,last_user_scan
			,last_user_lookup
			/*, forwarded_record_count, record_count, page_count*/

			FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''DETAILED'') IDXPS 
			INNER JOIN sys.dm_db_index_usage_stats ius ON IDXPS.object_id = ius.object_id AND IDXPS.index_id = ius.index_id AND IDXPS.database_id = ius.database_id
			INNER JOIN sys.indexes IDX  ON IDX.object_id = IDXPS.object_id 
			AND IDX.index_id = IDXPS.index_id 
			INNER JOIN sys.partitions p ON IDXPS.object_id = p.object_id AND IDXPS.index_id = p.index_id
			WHERE  IDX.type = 0 
			AND  forwarded_record_count > 0
			ORDER BY Fragmentation_Percentage DESC'
			IF @SkipHeaps = 0
			BEGIN
				INSERT #HeapTable
				EXEC sp_executesql @dynamicSQL;
			END
	
			
			IF @Debug = 0
				RAISERROR	  (N'Looking for stale statistics',0,1) WITH NOWAIT;
			SET @dynamicSQL = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
			USE ['+@DatabaseName+'];
			SELECT 
				'''+@DatabaseName+''' [DbName]
				, ObjectNm
				, StatsID
				, StatsName
				, SchemaName
				, ModificationCount
				, [LastUpdated] 
				, Rows
				, CONVERT(MONEY,ModificationCount)*100/Rows [ModPerc]
				, EstPerc
			FROM (
				SELECT 
					OBJECT_NAME(p.object_id) ObjectNm
						, p.index_id StatsID
						, s.name StatsName
						, MAX(p.rows) Rows
						, MAX(CASE WHEN p.rows > 0 THEN 
						 CASE 
WHEN LOG ( p.rows ) BETWEEN 0 AND 9 THEN 20
WHEN LOG ( p.rows ) BETWEEN 9 AND 10 THEN 15
WHEN LOG ( p.rows ) BETWEEN 10 AND 11 THEN 10
WHEN LOG ( p.rows ) BETWEEN 11 AND 12 THEN 5
WHEN LOG ( p.rows ) BETWEEN 12 AND 13.1 THEN 3
WHEN LOG ( p.rows ) BETWEEN 13.1 AND 13.8 THEN 1.7
WHEN LOG ( p.rows ) BETWEEN 13.8 AND 14.7 THEN 1.2
WHEN LOG ( p.rows ) BETWEEN 14.7 AND 17 THEN 0.15
WHEN LOG ( p.rows ) > 17 THEN 0.015
ELSE 0.015
 END
						ELSE 0 END)[EstPerc]
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
				INNER JOIN sys.stats s ON s.object_id = p.object_id 
				AND s.stats_id = p.index_id
				INNER JOIN sys.stats_columns sc ON sc.object_id = s.object_id 
				AND sc.stats_id = s.stats_id 
				AND sc.stats_column_id = pc.partition_column_id
				INNER JOIN sys.tables t ON t.object_id = s.object_id
				INNER JOIN sys.schemas sce ON sce.schema_id = t.schema_id' + 
				CASE WHEN OBJECT_ID(N'sys.dm_db_stats_properties') IS NOT NULL 
				THEN ' OUTER APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) ddsp 
				WHERE ddsp.modification_counter > 0 
				GROUP BY p.object_id, p.index_id, s.name,sce.name' 
				ELSE ' GROUP BY p.object_id, p.index_id, s.name,sce.name 
				HAVING sum(pc.modified_count)> 0 ' END
				+'
			) stats
			WHERE ObjectNm NOT LIKE ''sys%'' 
			AND ModificationCount != 0
			AND ObjectNm NOT LIKE ''ifts_comp_fragment%''
			AND ObjectNm NOT LIKE ''fulltext_%''
			AND ObjectNm NOT LIKE ''filestream_%''
			AND ObjectNm NOT LIKE ''queue_messages_%''
			AND Rows > 500
			AND  CASE WHEN Rows = 0 THEN 0 ELSE CONVERT(MONEY,ModificationCount)*100/Rows END >= [EstPerc]
			AND LastUpdated < DATEADD(DAY, - 1, GETDATE())
			ORDER BY ObjectNm, StatsName 
			OPTION (RECOMPILE);
			';

			INSERT #Action_Statistics
			EXEC sp_executesql @dynamicSQL;
		
			
			IF @Debug = 0
				RAISERROR	  (N'Skipping bad NC Indexes tables',0,1) WITH NOWAIT;

		   SET @dynamicSQL = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
			USE ['+@DatabaseName+'];
		   -- Possible Bad NC Indexes (writes > reads)  (Query 52) (Bad NC Indexes)
			SELECT OBJECT_NAME(s.[object_id]) AS [Table Name], i.name AS [Index Name], i.index_id, 
			i.is_disabled, i.is_hypothetical, i.has_filter, i.fill_factor,
			user_updates AS [Total Writes], user_seeks + user_scans + user_lookups AS [Total Reads],
			user_updates - (user_seeks + user_scans + user_lookups) AS [Difference]
			FROM sys.dm_db_index_usage_stats AS s WITH (NOLOCK)
			INNER JOIN sys.indexes AS i WITH (NOLOCK)
			ON s.[object_id] = i.[object_id]
			AND i.index_id = s.index_id
			WHERE OBJECTPROPERTY(s.[object_id],''IsUserTable'') = 1
			AND s.database_id = DB_ID()
			AND user_updates > (user_seeks + user_scans + user_lookups)
			AND i.index_id > 1
			ORDER BY [Difference] DESC, [Total Writes] DESC, [Total Reads] ASC OPTION (RECOMPILE);
			'
			--EXEC sp_executesql @dynamicSQL;

			/*----------------------------------------
			--Find badly behaving constraints
			----------------------------------------*/

		/* Constraints behaving badly*/
		IF @Debug = 0
			RAISERROR	  (N'Looking for bad constraints',0,1) WITH NOWAIT;
		SET @dynamicSQL = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
			USE ['+@DatabaseName+'];
		IF EXISTS(
		SELECT 1
		from sys.check_constraints i 
		WHERE i.is_not_trusted = 1 AND i.is_not_for_replication = 0 AND i.is_disabled = 0 
		)
		INSERT  #notrust (KeyType, Tablename, KeyName, DBCCcommand, Fix)
		SELECT ''Check'' as [KeyType], ''['+@DatabaseName+'].['' + s.name + ''].['' + o.name + '']'' [tablename]
		, ''['+@DatabaseName+'].['' + s.name + ''].['' + o.name + ''].['' + i.name + '']'' AS keyname
		, ''DBCC CHECKCONSTRAINTS (['' + i.name + '']) WITH ALL_ERRORMSGS'' [DBCC]
		, ''ALTER TABLE ['+@DatabaseName+'].['' + s.name + ''].'' + ''['' + o.name + ''] WITH CHECK CHECK CONSTRAINT ['' + i.name + '']'' [Fix]
		from sys.check_constraints i
		INNER JOIN sys.objects o ON i.parent_object_id = o.object_id
		INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
		WHERE i.is_not_trusted = 1 
		AND i.is_not_for_replication = 0 
		AND i.is_disabled = 0
		OPTION (RECOMPILE)
		;

		IF EXISTS(
		SELECT 1
		from sys.foreign_keys i
			INNER JOIN sys.objects o ON i.parent_object_id = o.OBJECT_ID
			INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
		WHERE   i.is_not_trusted = 1
			AND i.is_not_for_replication = 0
			AND i.is_disabled = 0 
			   
		)
		INSERT  #notrust (KeyType, Tablename, KeyName, DBCCcommand, Fix)
		SELECT ''FK'' as[ KeyType],  ''['+@DatabaseName+'].['' + s.name + ''].'' + ''['' + o.name + '']'' AS TableName
			, ''['+@DatabaseName+'].['' + s.name + ''].['' + o.name + ''].['' + i.name + '']'' AS FKName
			,''DBCC CHECKCONSTRAINTS (['' + i.name + '']) WITH ALL_ERRORMSGS'' [DBCC]
			, ''ALTER TABLE ['+@DatabaseName+'].['' + s.name + ''].'' + ''['' + o.name + ''] WITH CHECK CHECK CONSTRAINT ['' + i.name + '']'' [Fix]

		FROM    sys.foreign_keys i
			INNER JOIN sys.objects o ON i.parent_object_id = o.OBJECT_ID
			INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
		WHERE   i.is_not_trusted = 1
			AND i.is_not_for_replication = 0
			AND i.is_disabled = 0
	   ORDER BY o.name  
	   OPTION (RECOMPILE)
	   '
	   --PRINT @dynamicSQL
		EXEC sp_executesql @dynamicSQL;



		END
		
		SET @Databasei_Count = @Databasei_Count + 1; 
	END
	IF @Debug = 0
		RAISERROR (N'Evaluated all databases',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Output results from all databases into results table
			----------------------------------------*/
			IF @Debug = 0
				RAISERROR	  (N'Looking for Stored Procudure Workload',0,1) WITH NOWAIT;
			SET @dynamicSQL = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
			USE [tempdb];
			SELECT DB_NAME(dbid)
			, OBJECT_NAME(objectid,dbid)AS [SP Name]
			, SUM(total_logical_writes)[TotalLogicalWrites]
			, SUM(total_logical_writes) / SUM(usecounts) AS [AvgLogicalWrites]
			, SUM(usecounts) [execution_count]
			, ISNULL(
			CASE WHEN DATEDIFF(SECOND, MIN(qs.creation_time), GETDATE()) <5 
			THEN SUM(usecounts)/DATEDIFF(MILLISECOND, MIN(qs.creation_time), GETDATE())/1000
			ELSE SUM(usecounts)/DATEDIFF(SECOND, MIN(qs.creation_time), GETDATE())
			END ,0) [Calls/Second]
			, SUM(total_elapsed_time) [total_elapsed_time]
			, SUM(total_elapsed_time) / SUM(usecounts) AS [avg_elapsed_time]
			, MIN(qs.creation_time) [cached_time]
			FROM sys.dm_exec_query_stats qs  
			   join sys.dm_exec_cached_plans cp on qs.plan_handle = cp.plan_handle 
			   CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) 
			WHERE 1=1
			AND dbid IS NOT NULL
			AND DB_NAME(dbid) IS NOT NULL
			AND objectid is not null
			GROUP BY cp.plan_handle,DBID,objectid 
			'
			INSERT #db_sps
			EXEC sp_executesql @dynamicSQL;

	IF EXISTS (SELECT 1 FROM #MissingIndex ) 
	BEGIN
		INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 18, 'MISSING INDEXES - !Benefit > 1mm!','------','SELECT ''All your index are belong to us'' '
		INSERT #output_man_script (SectionID, Section,Summary ,Severity, Details,HoursToResolveWithTesting )
			SELECT 18
			, REPLICATE('|',ROUND(LOG(T1.magic_benefit_number),0)) + ' ' + CONVERT(VARCHAR(20),LOG(T1.magic_benefit_number)) + '' 
			, CONVERT(NVARCHAR(4000),'Benefit:'+  CONVERT(VARCHAR(20),CONVERT(BIGINT,T1.magic_benefit_number),0)
			+ '; ' + T1.[Table]
			+ '; Eq:' + ISNULL(T1.equality_columns,'')
			+ '; Ineq:' +  ISNULL(T1.inequality_columns,'')
			+ '; Incl:' +  ISNULL(T1.included_columns,''))
			,CASE WHEN LOG(T1.magic_benefit_number)  < 13 THEN @Result_Warning 
			WHEN LOG(T1.magic_benefit_number) >= 13 AND LOG(T1.magic_benefit_number) < 20 THEN @Result_YourServerIsDead  
			WHEN LOG(T1.magic_benefit_number) >= 20  THEN @Result_ReallyBad
			END
			/*, T2.[SETs] + '; ' + CHAR(13) + CHAR(10)  +*/
			, 'UNION ALL SELECT '''   + REPLACE(T1.ChangeIndexStatement,'< be clever here >', ' ''+ ('+  replace(replace(replace(replace(CONVERT(NVARCHAR(2000),BeingClever  ), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ') + ') + '' ') + ''' '
			, CASE 
			WHEN LOG(T1.magic_benefit_number) >= 10 AND LOG(T1.magic_benefit_number) < 12 THEN 1
			WHEN LOG(T1.magic_benefit_number) >= 12 AND LOG(T1.magic_benefit_number) < 14 THEN 2
			WHEN LOG(T1.magic_benefit_number) >= 14 AND LOG(T1.magic_benefit_number) < 16 THEN 4
			WHEN LOG(T1.magic_benefit_number) >= 16 AND LOG(T1.magic_benefit_number) < 20 THEN 6
			WHEN LOG(T1.magic_benefit_number) >= 20 AND LOG(T1.magic_benefit_number) < 25  THEN 8
			WHEN LOG(T1.magic_benefit_number) > 25  THEN 12
			END
			FROM #MissingIndex T1 
			LEFT OUTER JOIN #whatsets T2 ON T1.DB = T2.DBname
			WHERE T1.magic_benefit_number > 50000
			ORDER BY magic_benefit_number DESC OPTION (RECOMPILE)

			

	END
	IF @Debug = 0
			RAISERROR (N'Completed missing index details',0,1) WITH NOWAIT;

		IF EXISTS (SELECT 1 FROM #HeapTable ) 
	BEGIN
		INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 19, 'HEAP TABLES - Bad news','------','------'
		INSERT #output_man_script (SectionID, Section,Summary ,Severity, Details,HoursToResolveWithTesting )
			SELECT 19, LEFT(REPLICATE('|', (ISNULL(user_scans,0)+ ISNULL(user_seeks,0) + ISNULL(user_lookups,0) + ISNULL(user_updates,0))/100) + CONVERT(VARCHAR(20),(ISNULL(user_scans,0)+ ISNULL(user_seeks,0) + ISNULL(user_lookups,0) + ISNULL(user_updates,0))/100) ,2500)
			, LEFT('Rows:' + CONVERT(VARCHAR(20),T1.rows)
			+ ';'+ '['+T1.DB+'].' + '['+T1.[schema]+'].' + '['+T1.[table]+']' 
			+ '; Scan:' + CONVERT(VARCHAR(20),ISNULL(T1.last_user_scan,0) ,120)
			+ '; Seek:' + CONVERT(VARCHAR(20),ISNULL(T1.last_user_seek,0) ,120)
			+ '; Lookup:' + CONVERT(VARCHAR(20),ISNULL(T1.last_user_lookup,0) ,120),3800)
			, @Result_Warning
			, LEFT('/*DIRTY FIX, assuming forwarded records*/ALTER TABLE ['+T1.DB+'].' + '['+T1.[schema]+'].' + '['+T1.[table]+'] REBUILD ; RAISERROR (N''Completed heap ['+T1.DB+'].' + '['+T1.[schema]+'].' + '['+T1.[table]+']'' ,0,1) WITH NOWAIT',3800)
			, 3
			/*SELECT
			OBJECT_NAME(ps.object_id) as TableName,
			i.name as IndexName,
			ps.index_type_desc,
			ps.page_count,
			ps.avg_fragmentation_in_percent,
			ps.forwarded_record_count
		FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, 'DETAILED') AS ps
		INNER JOIN sys.indexes AS i
			ON ps.OBJECT_ID = i.OBJECT_ID  
			AND ps.index_id = i.index_id
		WHERE forwarded_record_count > 0*/
			FROM #HeapTable T1  
			WHERE T1.rows > 500
			ORDER BY (ISNULL(user_scans,0)+ ISNULL(user_seeks,0) + ISNULL(user_lookups,0) + ISNULL(user_updates,0)) DESC,  DB OPTION (RECOMPILE);
	END
	IF @Debug = 0
		RAISERROR (N'Found heap tables',0,1) WITH NOWAIT;

		IF EXISTS (SELECT 1 FROM #NeverUsedIndex ) 
	BEGIN
		INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 20, 'STALE INDEXES - Consider removing them at some stage','------','------'
		INSERT #output_man_script (SectionID, Section,Summary ,Details )

		SELECT 20, REPLICATE('|', LOG(CONVERT(BIGINT,rows)))
						, 'Table: ' + nui.TableName
						+ '; Updates: '+  CONVERT(VARCHAR(20),Updates)
						+ '; Rows: ' +CONVERT(NVARCHAR(20),rows) 
						, 'DB:' + DB
						+ '; Table:' + nui.TableName	
						+ '; StaleIndexes: ' + CONVERT(NVARCHAR(20),IndexCount)
			FROM 
			(
				SELECT 
				DB
				, TableName
				, COUNT(DISTINCT IndexName) As IndexCount
				, MAX(Updates) As Updates
				FROM 
				#NeverUsedIndex 
				WHERE TypeDesc <> 'CLUSTERED'
				GROUP BY DB
				, TableName
			) 
			nui
			INNER JOIN (
				SELECT OBJECT_NAME(object_id) TableName, SUM(row_count) rows FROM sys.dm_db_partition_stats 
				WHERE index_id < 2
				GROUP BY object_id

			)t2 ON nui.TableName = t2.TableName
			WHERE Updates/rows > 1
			AND rows > 0
			AND rows > 90
			ORDER BY rows DESC, nui.TableName ASC
	 OPTION (RECOMPILE)
	END
		IF EXISTS (SELECT 1 FROM #Action_Statistics ) 
	BEGIN
		INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 21, 'STALE STATS - Consider updating these','------','------'
		INSERT #output_man_script (SectionID, Section,Summary, Severity,Details,HoursToResolveWithTesting )
			SELECT  21,
			CONVERT(VARCHAR(20),DATEDIFF(DAY,s.LastUpdated,GETDATE())) +' days old'
			, '%Change:' + CONVERT(VARCHAR(15),s.[ModPerc]) +'%; Rows:' + CONVERT(VARCHAR(15),Rows) + ';Modifications:' + CONVERT(VARCHAR(20),s.ModificationCount) +'; ['+ DBname + '].['+SchemaName+'].['+TableName+']:['+StatisticsName+']'
			, CASE WHEN DATEDIFF(DAY,s.LastUpdated,GETDATE()) < 14 THEN @Result_Warning ELSE @Result_Bad END
			, 'UPDATE STATISTICS [' + DBname + '].['+SchemaName+'].['+TableName+'] ['+StatisticsName+'] ' 
			
			+ CASE 
			WHEN s.Rows BETWEEN 0 AND 500000 THEN 'WITH FULLSCAN' 
			WHEN s.Rows BETWEEN 500000 AND 5000000 THEN 'WITH SAMPLE 20 PERCENT'
			WHEN s.Rows BETWEEN 5000000 AND 50000000 THEN 'WITH SAMPLE 10 PERCENT'
			WHEN s.Rows > 50000000 THEN 'WITH SAMPLE 5 PERCENT'
			ELSE 'WITH SAMPLE ' + CONVERT(VARCHAR(3),CONVERT(INT,EstPerc)*2) + 'PERCENT' 
			END +'; PRINT ''[' + DBname + '].['+SchemaName+'].['+TableName+'] ['+StatisticsName+'] Done ''' [UpdateStats]
			, 0.15
			 FROM #Action_Statistics s 
			 ORDER BY s.[ModPerc] DESC OPTION (RECOMPILE);/*They are like little time capsules.. just sitting there.. waiting*/

	END
	IF @Debug = 0
		RAISERROR (N'Listed state stats',0,1) WITH NOWAIT;

		 /*----------------------------------------
			--Most used database stored procedures
			----------------------------------------*/
		IF EXISTS( SELECT 1 FROM #db_sps)
	BEGIN
		INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 22, 'STORED PROCEDURE WORKLOAD - TOP 10','------','------'
		INSERT #output_man_script (SectionID, Section,Summary ,Details )

		SELECT TOP 10 22, REPLICATE('|', CONVERT(MONEY,execution_count*100) / SUM (execution_count) OVER() ) + ' '+ CONVERT(VARCHAR(20),CONVERT(INT,ROUND(CONVERT(MONEY,execution_count*100) / SUM (execution_count) OVER(),0))) + '%'
		,  [SP Name] + '; Executions:'+ CONVERT(VARCHAR(20),execution_count)
		+ '; Per second:' + CONVERT(VARCHAR(20),[Calls/Second])
		, dbname
		+ '; Avg Time:' + CONVERT(VARCHAR(20), avg_elapsed_time/1000/1000 ) + '(s)'
		+ '; Total time:' + CONVERT(VARCHAR(20), total_elapsed_time/1000/1000 ) + '(s)'
		+ '; Overall time:' + CONVERT(VARCHAR(20),CONVERT(MONEY,total_elapsed_time*100) / SUM (total_elapsed_time) OVER()) +'%'
		FROM #db_sps
		ORDER BY execution_count DESC OPTION (RECOMPILE)

	END
	IF @Debug = 0
		RAISERROR (N'Database stored procedure details',0,1) WITH NOWAIT;
			/*----------------------------------------
			--General server settings and items of note
			----------------------------------------*/

	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 24, 'Server details','------','------'
	INSERT #output_man_script (SectionID, Section, Summary  )
	SELECT 24,  @ThisServer AS [Server Name]
	,'Evauation date: ' + CONVERT(VARCHAR(20),GETDATE(),120)
	INSERT #output_man_script (SectionID, Section, Summary  )
	SELECT 24,  @ThisServer AS [Server Name]
	,'' +  replace(replace(replace(replace(CONVERT(NVARCHAR(500),@@VERSION  ), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ')

	INSERT #output_man_script (SectionID,Summary,HoursToResolveWithTesting  )
	SELECT 24, 'Page Life Expectancy: ' + CONVERT(VARCHAR(20), cntr_value)
	, CASE WHEN cntr_value < 100 THEN 4 ELSE NULL END
	FROM sys.dm_os_performance_counters WITH (NOLOCK)
	WHERE [object_name] LIKE N'%Buffer Node%' -- Handles named instances
	AND counter_name = N'Page life expectancy'  OPTION (RECOMPILE)


	INSERT #output_man_script (SectionID,Summary  )
	SELECT 24, 'Memory Grants Pending:' + CONVERT(VARCHAR(20), cntr_value)                                                                                                    
	FROM sys.dm_os_performance_counters WITH (NOLOCK)
	WHERE [object_name] LIKE N'%Memory Manager%' -- Handles named instances
	AND counter_name = N'Memory Grants Pending' OPTION (RECOMPILE);

	IF @Debug = 0
		RAISERROR (N'Listed general instance stats',0,1) WITH NOWAIT;


	/* The default settings have been copied from sp_Blitz from http://FirstResponderKit.org
	Believe it or not, SQL Server doesn't track the default values
	for sp_configure options! We'll make our own list here.*/

	INSERT  INTO #ConfigurationDefaults VALUES ( 'access check cache bucket count', 0, 1001 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'access check cache quota', 0, 1002 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'Ad Hoc Distributed Queries', 0, 1003 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'affinity I/O mask', 0, 1004 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'affinity mask', 0, 1005 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'affinity64 mask', 0, 1066 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'affinity64 I/O mask', 0, 1067 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'Agent XPs', 0, 1071 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'allow updates', 0, 1007 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'awe enabled', 0, 1008 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'backup checksum default', 0, 1070 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'backup compression default', 0, 1073 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'blocked process threshold', 0, 1009 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'blocked process threshold (s)', 0, 1009 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'c2 audit mode', 0, 1010 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'clr enabled', 0, 1011 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'common criteria compliance enabled', 0, 1074 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'contained database authentication', 0, 1068 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'cost threshold for parallelism', 5, 1012 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'cross db ownership chaining', 0, 1013 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'cursor threshold', -1, 1014 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'Database Mail XPs', 0, 1072 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'default full-text language', 1033, 1016 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'default language', 0, 1017 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'default trace enabled', 1, 1018 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'disallow results from triggers', 0, 1019 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'EKM provider enabled', 0, 1075 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'filestream access level', 0, 1076 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'fill factor (%)', 0, 1020 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'ft crawl bandwidth (max)', 100, 1021 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'ft crawl bandwidth (min)', 0, 1022 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'ft notify bandwidth (max)', 100, 1023 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'ft notify bandwidth (min)', 0, 1024 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'index create memory (KB)', 0, 1025 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'in-doubt xact resolution', 0, 1026 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'lightweight pooling', 0, 1027 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'locks', 0, 1028 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'max degree of parallelism', 0, 1029 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'max full-text crawl range', 4, 1030 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'max server memory (MB)', 2147483647, 1031 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'max text repl size (B)', 65536, 1032 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'max worker threads', 0, 1033 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'media retention', 0, 1034 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'min memory per query (KB)', 1024, 1035 );
	/* Accepting both 0 and 16 below because both have been seen in the wild as defaults. */
	IF EXISTS ( SELECT  *
				FROM    sys.configurations
				WHERE   name = 'min server memory (MB)'
						AND value_in_use IN ( 0, 16 ) )
		INSERT  INTO #ConfigurationDefaults
				SELECT  'min server memory (MB)' ,
						CAST(value_in_use AS BIGINT), 1036
				FROM    sys.configurations
				WHERE   name = 'min server memory (MB)'
	ELSE
		INSERT  INTO #ConfigurationDefaults
		VALUES  ( 'min server memory (MB)', 0, 1036 );

	INSERT  INTO #ConfigurationDefaults VALUES  ( 'nested triggers', 1, 1037 )
	INSERT  INTO #ConfigurationDefaults VALUES ( 'network packet size (B)', 4096, 1038 )
	INSERT  INTO #ConfigurationDefaults VALUES ( 'Ole Automation Procedures', 0, 1039 )
	INSERT  INTO #ConfigurationDefaults VALUES ( 'open objects', 0, 1040 )
	INSERT  INTO #ConfigurationDefaults VALUES ( 'optimize for ad hoc workloads', 0, 1041 )
	INSERT  INTO #ConfigurationDefaults VALUES ( 'PH timeout (s)', 60, 1042 )
	INSERT  INTO #ConfigurationDefaults VALUES ( 'precompute rank', 0, 1043 )
	INSERT  INTO #ConfigurationDefaults VALUES ( 'priority boost', 0, 1044 )
	INSERT  INTO #ConfigurationDefaults VALUES ( 'query governor cost limit', 0, 1045 )
	INSERT  INTO #ConfigurationDefaults VALUES ( 'query wait (s)', -1, 1046 )
	INSERT  INTO #ConfigurationDefaults VALUES ( 'recovery interval (min)', 0, 1047 )
	INSERT  INTO #ConfigurationDefaults VALUES ( 'remote access', 1, 1048 )
	INSERT  INTO #ConfigurationDefaults VALUES ( 'remote admin connections', 0, 1049 )
	/* SQL Server 2012 changes a configuration default */
	IF @@VERSION LIKE '%Microsoft SQL Server 2005%'
		OR @@VERSION LIKE '%Microsoft SQL Server 2008%'
		BEGIN
			INSERT  INTO #ConfigurationDefaults
			VALUES  ( 'remote login timeout (s)', 20, 1069 );
		END
	ELSE
		BEGIN
			INSERT  INTO #ConfigurationDefaults
			VALUES  ( 'remote login timeout (s)', 10, 1069 );
		END
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'remote proc trans', 0, 1050 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'remote query timeout (s)', 600, 1051 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'Replication XPs', 0, 1052 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'RPC parameter data validation', 0, 1053 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'scan for startup procs', 0, 1054 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'server trigger recursion', 1, 1055 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'set working set size', 0, 1056 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'show advanced options', 0, 1057 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'SMO and DMO XPs', 1, 1058 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'SQL Mail XPs', 0, 1059 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'transform noise words', 0, 1060 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'two digit year cutoff', 2049, 1061 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'user connections', 0, 1062 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'user options', 0, 1063 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'Web Assistant Procedures', 0, 1064 )
	INSERT  INTO #ConfigurationDefaults VALUES  ( 'xp_cmdshell', 0, 1065 );


	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 25, 'Server details - Non default settings','------','------'
	INSERT #output_man_script (SectionID, Section,Summary,Details)
	SELECT 25, [description] name
	, '['+CONVERT(VARCHAR(20),cd.[DefaultValue]) + '] changed to [' + CONVERT(VARCHAR(20),value_in_use) + ']'
	, 'Blitz CheckID:' +  CONVERT(VARCHAR(20),cd.CheckID)
	+ '; MIN:' + CONVERT(VARCHAR(20),minimum)
	+ '; MAX:' + CONVERT(VARCHAR(20),maximum)
	+ '; IsDynamic:' + CONVERT(VARCHAR(20),is_dynamic)
	+ '; IsAdvanced:' + CONVERT(VARCHAR(20),is_advanced)
	FROM sys.configurations cr WITH (NOLOCK)
	INNER JOIN #ConfigurationDefaults cd ON cd.name = cr.name
	LEFT OUTER JOIN #ConfigurationDefaults cdUsed ON cdUsed.name = cr.name AND cdUsed.DefaultValue = cr.value_in_use
	WHERE cdUsed.name IS NULL
	OPTION (RECOMPILE);
	IF @Debug = 0
		RAISERROR (N'Listed non-default settings',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Current active logins on this instance
			----------------------------------------*/

	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 26,'CURRENT ACTIVE USERS - TOP 10','------','------'
	INSERT #output_man_script (SectionID, Section,Summary)
	SELECT TOP 10 26, 'User: ' + login_name
	, '[' + CONVERT(VARCHAR(20), COUNT(session_id) ) + '] sessions using: ' + [program_name]
	FROM sys.dm_exec_sessions WITH (NOLOCK)
	GROUP BY login_name, [program_name]
	ORDER BY COUNT(session_id) DESC OPTION (RECOMPILE);

	IF @Debug = 0
		RAISERROR (N'Connections listed',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Insert trust issues into output table
			----------------------------------------*/
	IF EXISTS(SELECT 1 FROM #notrust )
	BEGIN
	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 27,'TRUST ISSUES','------','------'
	INSERT #output_man_script (SectionID, Section,Summary, Details,Severity)

	SELECT 27, KeyType + '; Table: '+ Tablename
	+ '; KeyName: ' + KeyName
	, DBCCcommand
	, Fix
	, @Result_Warning
	FROM #notrust 
	OPTION (RECOMPILE)
	END
	
	IF @Debug = 0
		RAISERROR (N'Included Constraint trust issues',0,1) WITH NOWAIT;


			/*----------------------------------------
			--Current active connections on each database
			----------------------------------------*/
			
	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 29,'DATABASE CONNECTED USERS','------','------'
	INSERT #output_man_script (SectionID, Section,Summary,Details)
	SELECT  29, dtb.name
	, 'Active: ' + CONVERT(VARCHAR(20),(select count(*) from master.dbo.sysprocesses p where dtb.database_id=p.dbid))
	+ '; LastActivity:' +CONVERT(VARCHAR, ISNULL(lastactive.LastActivity,lastactive.create_date),120)
	, 'Updatable: ' + ( case LOWER(convert( NVARCHAR(128), DATABASEPROPERTYEX(dtb.name, 'Updateability'))) when 'read_write'then 'Yes' else 'No' end)
	+ '; ReplicationOptions:' + CONVERT(VARCHAR(20),(dtb.is_published*1+dtb.is_subscribed*2+dtb.is_merge_published*4))
	FROM master.sys.databases AS dtb 

	INNER JOIN (
			SELECT d.name
			, MAX(d.create_date) create_date
			, [LastActivity] =
			(select X1= max(bb.xx) 
			from (
				select xx = max(last_user_seek) 
					where max(last_user_seek) is not null 
				union all 
				select xx = max(last_user_scan) 
					where max(last_user_scan) is not null 
				union all 
				select xx = max(last_user_lookup) 
					where max(last_user_lookup) is not null 
				union all 
					select xx = max(last_user_update) 
					where max(last_user_update) is not null) bb) 
			, last_user_seek = MAX(last_user_seek)
			, last_user_scan = MAX(last_user_scan)
			, last_user_lookup = MAX(last_user_lookup)
			, last_user_update = MAX(last_user_update)
			FROM sys.databases AS d 
			LEFT OUTER JOIN sys.dm_db_index_usage_stats AS i ON i.database_id=d.database_id
			GROUP BY d.name
	) lastactive ON lastactive.name = dtb.name
	
	
	OPTION (RECOMPILE);

	IF @Debug = 0
		RAISERROR (N'Database Connections counted',0,1) WITH NOWAIT;


			/*----------------------------------------
			--Current likely active databases
			----------------------------------------*/
	

DECLARE @confidence TABLE (DBName NVARCHAR(500), EstHoursSinceActive BIGINT)
DECLARE @ConfidenceLevel TABLE ( Bionmial MONEY , ConfidenceLevel NVARCHAR(10))
INSERT INTO @ConfidenceLevel VALUES(1.96,'95%')

SET @lastservericerestart = (SELECT create_date FROM sys.databases WHERE name = 'tempdb');

INSERT INTO @confidence
select d.name, [LastSomethingHours] = DATEDIFF(HOUR,ISNULL(
(select X1= max(bb.xx) 
from (
    select xx = max(last_user_seek) 
        where max(last_user_seek) is not null 
    union all 
    select xx = max(last_user_scan) 
        where max(last_user_scan) is not null 
    union all 
    select xx = max(last_user_lookup) 
        where max(last_user_lookup) is not null 
    union all 
        select xx = max(last_user_update) 
        where max(last_user_update) is not null) bb) ,@lastservericerestart),GETDATE())
FROM master.dbo.sysdatabases d 
left outer join sys.dm_db_index_usage_stats s on d.dbid= s.database_id 
WHERE database_id > 4
group by d.name

		
IF @ShowMigrationRelatedOutputs = 1
BEGIN
	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 30, 'Database usage likelyhood','------','------'
	INSERT #output_man_script (SectionID, Section,Summary,Details)
	SELECT  30 [SectionID]
	, base.name [Section]
	,ISNULL(CONVERT(VARCHAR(10),CASE
		WHEN pages.[TotalPages in MB] > 0 THEN 100
		WHEN con.number_of_connections > 0 THEN confidence.low 
		ELSE confidence.high  
	END),'')  + '% likely'    
	+  '; Connections: ' + CONVERT(VARCHAR(10),con.number_of_connections )
	+ '; HoursActive: '+ CONVERT(VARCHAR(10),DATEDIFF(HOUR,@lastservericerestart,GETDATE())) 
	+ '; Pages(MB) in memory: ' + CONVERT(VARCHAR(10), ISNULL(pages.[TotalPages in MB],0)) 
	 [Summary]
 
	,  'DB Created: ' + CONVERT(VARCHAR,base.DBcreatedate,120)
	+ '; Last seek: ' + CONVERT(VARCHAR,base.[last_user_seek],120)
	+ '; Last scan:' + CONVERT(VARCHAR,base.[last_user_scan],120)
	+ '; Last lookup: ' + CONVERT(VARCHAR,base.[last_user_lookup],120)
	+ '; Last update: ' + CONVERT(VARCHAR,base.[last_user_update],120) [Details]

	FROM (
	SELECT db.name, db.database_id
	, MAX(db.create_date) [DBcreatedate]
	, MAX(o.modify_date) [ObjectModifyDate]
	, MAX(ius.last_user_seek)    [last_user_seek]
	, MAX(ius.last_user_scan)   [last_user_scan]
	, MAX(ius.last_user_lookup) [last_user_lookup]
	, MAX(ius.last_user_update) [last_user_update]
	FROM
		sys.databases db
		LEFT OUTER JOIN sys.dm_db_index_usage_stats ius  ON db.database_id = ius.database_id
		LEFT OUTER JOIN  sys.all_objects o ON o.object_id = ius.object_id AND o.type = 'U'
	WHERE 
		db.database_id > 4 AND state NOT IN (1,2,3,6) AND user_access = 0
	GROUP BY 
		db.name, db.database_id
	) base

	LEFT OUTER JOIN (
		SELECT name AS dbname
		 ,COUNT(status) AS number_of_connections
		FROM master.sys.databases sd
		LEFT JOIN master.sys.sysprocesses sp ON sd.database_id = sp.dbid
		WHERE database_id > 4
		GROUP BY name
	) con ON con.dbname = base.name
	LEFT OUTER JOIN (
	SELECT DB_NAME (database_id) AS 'Database Name'
	,  COUNT(*) *8/1024 AS [TotalPages in MB]
	FROM sys.dm_os_buffer_descriptors
	GROUP BY database_id
	) pages ON pages.[Database Name] = base.name

	LEFT OUTER JOIN (
	select DBName
	  , intervals.n as [Hours]
	  , intervals.x as [TargetActiveHours]
	  , CONVERT(MONEY,(p - se * 1.96)*100) as low
	  , CONVERT(MONEY,(intervals.p * 100)) as mid
	  , CONVERT(MONEY,(p + se * 1.96)*100) as high 
	from (
	  select 
		rates.*, 
		sqrt(p * (1 - p) / n) as se -- calculate se
	  from (
		select 
		  conversions.*, 
		  (CASE WHEN x = 0 THEN 1 ELSE x END + 1.92) / CONVERT(FLOAT,(n + 3.84)) as p -- calculate p
		from ( 
		  -- Our conversion rate table from above
		  select DBName
		   , DATEDIFF(HOUR,@lastservericerestart,GETDATE()) as n 
		   , DATEDIFF(HOUR,@lastservericerestart,GETDATE()) - EstHoursSinceActive as x
		   FROM @confidence
		) conversions
	  ) rates
	) intervals
	) confidence ON confidence.DBName COLLATE DATABASE_DEFAULT = base.name COLLATE DATABASE_DEFAULT 
	LEFT OUTER JOIN sys.databases dbs ON dbs.database_id = base.database_id

	ORDER BY base.name

	IF @Debug = 0
		RAISERROR (N'Database usage likelyhood measured',0,1) WITH NOWAIT;
END

			/*----------------------------------------
			--Create DMA commands
			----------------------------------------*/
	IF @ShowMigrationRelatedOutputs = 1
	BEGIN
		INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 31, 'Database Migration Assistant commands','------','------'
		INSERT #output_man_script (SectionID, Section,Summary,Details)

		SELECT 31, 'DMA', 'Run in PowerShell', '.\DmaCmd.exe /AssessmentName="' + @ThisServer + '_' + name + '" /AssessmentDatabases="Server=' + @ThisServer 
			+ ';Initial Catalog=' + name + ';Integrated Security=true" /AssessmentEvaluateCompatibilityIssues /AssessmentOverwriteResult /AssessmentTargetPlatform="SqlServerWindows2017" /AssessmentResultCsv="'
			+ 'C:\Temp\DMA\AssessmentReport_' + REPLACE(@@SERVERNAME,@CharToCheck,'_') + '_' + name + '.csv"'
			 FROM sys.databases
			WHERE database_id > 4

		IF @Debug = 0
		RAISERROR (N'Create DMA commands',0,1) WITH NOWAIT;
	END

	

			/*----------------------------------------
			--Getting Trace data
			----------------------------------------*/

	
DECLARE @TraceTypes TABLE([Value] INT, Definition NVARCHAR(200))
INSERT INTO @TraceTypes VALUES (8259,	'Check Constraint')
INSERT INTO @TraceTypes VALUES (8260	,'Default (constraint or standalone)')
INSERT INTO @TraceTypes VALUES (8262	,'Foreign-key Constraint')
INSERT INTO @TraceTypes VALUES (8272	,'Stored Procedure')
INSERT INTO @TraceTypes VALUES (8274	,'Rule')
INSERT INTO @TraceTypes VALUES (8275	,'System Table')
INSERT INTO @TraceTypes VALUES (8276	,'Trigger on Server')
INSERT INTO @TraceTypes VALUES (8277	,'(User-defined) Table')
INSERT INTO @TraceTypes VALUES (8278	,'View')
INSERT INTO @TraceTypes VALUES (8280	,'Extended Stored Procedure')
INSERT INTO @TraceTypes VALUES (16724	,'CLR Trigger')
INSERT INTO @TraceTypes VALUES (16964	,'Database')
INSERT INTO @TraceTypes VALUES (16975	,'Object')
INSERT INTO @TraceTypes VALUES (17222	,'FullText Catalog')
INSERT INTO @TraceTypes VALUES (17232	,'CLR Stored Procedure')
INSERT INTO @TraceTypes VALUES (17235	,'Schema')
INSERT INTO @TraceTypes VALUES (17475	,'Credential')
INSERT INTO @TraceTypes VALUES (17491	,'DDL Event')
INSERT INTO @TraceTypes VALUES (17741	,'Management Event')
INSERT INTO @TraceTypes VALUES (17747	,'Security Event')
INSERT INTO @TraceTypes VALUES (17749	,'User Event')
INSERT INTO @TraceTypes VALUES (17985	,'CLR Aggregate Function')
INSERT INTO @TraceTypes VALUES (17993	,'Inline Table-valued SQL Function')
INSERT INTO @TraceTypes VALUES (18000	,'Partition Function')
INSERT INTO @TraceTypes VALUES (18002	,'Replication Filter Procedure')
INSERT INTO @TraceTypes VALUES (18004	,'Table-valued SQL Function')
INSERT INTO @TraceTypes VALUES (18259	,'Server Role')
INSERT INTO @TraceTypes VALUES (18263	,'Microsoft Windows Group')
INSERT INTO @TraceTypes VALUES (19265	,'Asymmetric Key')
INSERT INTO @TraceTypes VALUES (19277	,'Master Key')
INSERT INTO @TraceTypes VALUES (19280	,'Primary Key')
INSERT INTO @TraceTypes VALUES (19283	,'ObfusKey')
INSERT INTO @TraceTypes VALUES (19521	,'Asymmetric Key Login')
INSERT INTO @TraceTypes VALUES (19523	,'Certificate Login')
INSERT INTO @TraceTypes VALUES (19538	,'Role')
INSERT INTO @TraceTypes VALUES (19539	,'SQL Login')
INSERT INTO @TraceTypes VALUES (19543	,'Windows Login')
INSERT INTO @TraceTypes VALUES (20034	,'Remote Service Binding')
INSERT INTO @TraceTypes VALUES (20036	,'Event Notification on Database')
INSERT INTO @TraceTypes VALUES (20037	,'Event Notification')
INSERT INTO @TraceTypes VALUES (20038	,'Scalar SQL Function')
INSERT INTO @TraceTypes VALUES (20047	,'Event Notification on Object')
INSERT INTO @TraceTypes VALUES (20051	,'Synonym')
INSERT INTO @TraceTypes VALUES (20307	,'Sequence')
INSERT INTO @TraceTypes VALUES (20549	,'End Point')
INSERT INTO @TraceTypes VALUES (20801	,'Adhoc Queries which may be cached')
INSERT INTO @TraceTypes VALUES (20816	,'Prepared Queries which may be cached')
INSERT INTO @TraceTypes VALUES (20819	,'Service Broker Service Queue')
INSERT INTO @TraceTypes VALUES (20821	,'Unique Constraint')
INSERT INTO @TraceTypes VALUES (21057	,'Application Role')
INSERT INTO @TraceTypes VALUES (21059	,'Certificate')
INSERT INTO @TraceTypes VALUES (21075	,'Server')
INSERT INTO @TraceTypes VALUES (21076	,'Transact-SQL Trigger')
INSERT INTO @TraceTypes VALUES (21313	,'Assembly')
INSERT INTO @TraceTypes VALUES (21318	,'CLR Scalar Function')
INSERT INTO @TraceTypes VALUES (21321	,'Inline scalar SQL Function')
INSERT INTO @TraceTypes VALUES (21328	,'Partition Scheme')
INSERT INTO @TraceTypes VALUES (21333	,'User')
INSERT INTO @TraceTypes VALUES (21571	,'Service Broker Service Contract')
INSERT INTO @TraceTypes VALUES (21572	,'Trigger on Database')
INSERT INTO @TraceTypes VALUES (21574	,'CLR Table-valued Function')
INSERT INTO @TraceTypes VALUES (21577	,'Internal Table (For example, XML Node Table, Queue Table.)')
INSERT INTO @TraceTypes VALUES (21581	,'Service Broker Message Type')
INSERT INTO @TraceTypes VALUES (21586	,'Service Broker Route')
INSERT INTO @TraceTypes VALUES (21587	,'Statistics')
INSERT INTO @TraceTypes VALUES (21825	,'')
INSERT INTO @TraceTypes VALUES (21827	,'')
INSERT INTO @TraceTypes VALUES (21831	,'')
INSERT INTO @TraceTypes VALUES (21843	,'')
INSERT INTO @TraceTypes VALUES (21847	,'User')
INSERT INTO @TraceTypes VALUES (22099	,'Service Broker Service')
INSERT INTO @TraceTypes VALUES (22601	,'Index')
INSERT INTO @TraceTypes VALUES (22604	,'Certificate Login')
INSERT INTO @TraceTypes VALUES (22611	,'XMLSchema')
INSERT INTO @TraceTypes VALUES (22868	,'Type')

--https://www.ptr.co.uk/blog/how-improve-your-sql-server-speed
--The script below can be use to search for automatic Log File Growths, using the background profiler trace that SQL Server maintains.
DECLARE @tracepath NVARCHAR(260)

--Pick up the path of the background profiler trace for the instance
SELECT 
 @tracepath = path 
FROM sys.traces 
WHERE is_default = 1


	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 32, 'Trace Data','------','------'
		INSERT #output_man_script (SectionID, Section,Summary,Details)
		SELECT 32
		,name 
		,ISNULL(DatabaseName,'')
		,'EventDefinition:'+ISNULL(T.Definition,'')
		+';Application:'+ISNULL(ApplicationName,'' )
		+';Events:'+ CONVERT(NVARCHAR(50),count(*))
		+ ';TimeSpan-Minutes:'+ CONVERT(NVARCHAR(20),DATEDIFF(MINUTE, MIN(StartTime), MAX(StartTime)))
FROM fn_trace_gettable(@tracepath, default) g
cross apply sys.trace_events te 
LEFT OUTER JOIN @TraceTypes T on T.Value = g.ObjectType
WHERE g.eventclass = te.trace_event_id
GROUP BY name,T.Definition,DatabaseName, ApplicationName
ORDER BY name,T.Definition,DatabaseName, ApplicationName

--Query the background trace files
INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 33, 'Trace Data Autogrowth','------','------'
		INSERT #output_man_script (SectionID, Section,Summary,Details)
		SELECT 33
		,DBName
		,'%Change:'+ CONVERT(NVARCHAR(20),SUM(EventGrowthMB)*100/(MAX(CurrentFileSizeMB) - SUM(EventGrowthMB)))

, 'EventGrowthMB:'+CONVERT(NVARCHAR(20),SUM(EventGrowthMB)) 
+';FileType:'+FileType
+';TotalDurationSec:'+ CONVERT(NVARCHAR(20),SUM(EventDurationSec) )
+';Period:'+ CONVERT(NVARCHAR(20),CONVERT(VARCHAR,DATEADD(SECOND,DATEDIFF(SECOND,MIN(EventTime), MAX(EventTime)),0),114) )
+';CurrentFileSizeMB:'+ CONVERT(NVARCHAR(20),MAX(CurrentFileSizeMB) )
FROM (
SELECT 
 DBName    = g.DatabaseName
, DBFileName   = mf.physical_name
, FileType   = CASE mf.type WHEN 0 THEN 'Row' WHEN 1 THEN 'Log' WHEN 2 THEN 'FILESTREAM' WHEN 4 THEN 'Full-text' END
, EventName   = te.name
, EventGrowthMB  = CONVERT(MONEY,g.IntegerData*8/1024.) -- Number of 8-kilobyte (KB) pages by which the file increased.
, EventTime   = g.StartTime
, EventDurationSec = CONVERT(MONEY,g.Duration/1000./1000.) -- Length of time necessary to extEND the file.
, CurrentAutoGrowthSet= CASE
        WHEN mf.is_percent_growth = 1
        THEN CONVERT(char(2), mf.growth) + '%' 
        ELSE CONVERT(VARCHAR(30), CONVERT(MONEY, mf.growth*8./1024.)) + 'MB'
       END
, CurrentFileSizeMB = CONVERT(MONEY,mf.size* 8./1024.)
, MaxFileSizeMB  = CASE WHEN mf.max_size = -1 THEN 'Unlimited' ELSE CONVERT(VARCHAR(30), CONVERT(MONEY,mf.max_size*8./1024.)) END
FROM fn_trace_gettable(@tracepath, default) g
cross apply sys.trace_events te 
inner join sys.master_files mf
on mf.database_id = g.DatabaseID
and g.FileName = mf.name
WHERE g.eventclass = te.trace_event_id
and  te.name in ('Data File Auto Grow','Log File Auto Grow')
) T
GROUP BY DBName
, FileType
ORDER BY DBName

	IF @Debug = 0
		RAISERROR (N'Done with Trace data',0,1) WITH NOWAIT;

			/*----------------------------------------
			--Calculate daily IO workload
			----------------------------------------*/


	BEGIN TRY
		IF OBJECT_ID('tempdb.dbo.#LEXEL_OES_stats_sql_handle_convert_table', 'U') IS NOT NULL
		EXEC ('DROP TABLE #LEXEL_OES_stats_sql_handle_convert_table;')
		CREATE TABLE #LEXEL_OES_stats_sql_handle_convert_table (
				 row_id INT identity 
				, t_sql_handle varbinary(64)
				, t_display_option NVARCHAR(140) collate database_default
				, t_display_optionIO NVARCHAR(140) collate database_default
				, t_sql_handle_text NVARCHAR(140) collate database_default
				, t_SPRank INT
				, t_dbid INT
				, t_objectid INT
				, t_SQLStatement NVARCHAR(max) collate database_default
				, t_execution_count INT
				, t_plan_generation_num INT
				, t_last_execution_time datetime
				, t_avg_worker_time FLOAT
				, t_total_worker_time FLOAT
				, t_last_worker_time FLOAT
				, t_min_worker_time FLOAT
				, t_max_worker_time FLOAT
				, t_avg_logical_reads FLOAT
				, t_total_logical_reads BIGINT
				, t_last_logical_reads BIGINT
				, t_min_logical_reads BIGINT
				, t_max_logical_reads BIGINT
				, t_avg_logical_writes FLOAT
				, t_total_logical_writes BIGINT
				, t_last_logical_writes BIGINT
				, t_min_logical_writes BIGINT
				, t_max_logical_writes BIGINT
				, t_avg_logical_IO FLOAT
				, t_total_logical_IO BIGINT
				, t_last_logical_IO BIGINT
				, t_min_logical_IO BIGINT
				, t_max_logical_IO BIGINT 
				);
		IF OBJECT_ID('tempdb.dbo.#LEXEL_OES_stats_objects', 'U') IS NOT NULL
		 EXEC ('DROP TABLE #LEXEL_OES_stats_objects;')
		CREATE TABLE #LEXEL_OES_stats_objects (
				 obj_rank INT
				, total_cpu BIGINT
				, total_logical_reads BIGINT
				, total_logical_writes BIGINT
				, total_logical_io BIGINT
				, avg_cpu BIGINT
				, avg_reads BIGINT
				, avg_writes BIGINT
				, avg_io BIGINT
				, cpu_rank INT
				, total_cpu_rank INT
				, logical_read_rank INT
				, logical_write_rank INT
				, logical_io_rank INT
				);
		IF OBJECT_ID('tempdb.dbo.#LEXEL_OES_stats_object_name', 'U') IS NOT NULL
		 EXEC ('DROP TABLE #LEXEL_OES_stats_object_name;')
		CREATE TABLE #LEXEL_OES_stats_object_name (
				 dbId INT
				, objectId INT
				, dbName sysname collate database_default null
				, objectName sysname collate database_default null
				, objectType NVARCHAR(5) collate database_default null
				, schemaName sysname collate database_default null
				)

		IF OBJECT_ID('tempdb.dbo.#LEXEL_OES_stats_output', 'U') IS NOT NULL
		 EXEC ('DROP TABLE #LEXEL_OES_stats_output;')
		CREATE TABLE #LEXEL_OES_stats_output(
			ID INT IDENTITY(1,1)
			, evaldate NVARCHAR(20)
			, domain NVARCHAR(50) DEFAULT DEFAULT_DOMAIN()
			, SQLInstance NVARCHAR(50) NULL --DEFAULT @@SERVERNAME
			, [Type] NVARCHAR(25) NOT NULL
			, l1 INT NULL
			, l2 BIGINT NULL
			, row_id INT NOT NULL
			, t_obj_name NVARCHAR(250)  NULL
			, t_obj_type NVARCHAR(250)  NULL
			, [schema_name] NVARCHAR(250)  NULL
			, t_db_name NVARCHAR(250) NULL
			, t_sql_handle varbinary(64) NULL
			, t_SPRank INT NULL
			, t_SPRank2 INT NULL
			, t_SQLStatement NVARCHAR(max) NULL
			, t_execution_count INT NULL
			, t_plan_generation_num INT NULL
			, t_last_execution_time datetime NULL
			, t_avg_worker_time float NULL
			, t_total_worker_time BIGINT NULL
			, t_last_worker_time BIGINT NULL
			, t_min_worker_time BIGINT NULL
			, t_max_worker_time BIGINT NULL
			, t_avg_logical_reads float NULL
			, t_total_logical_reads BIGINT NULL
			, t_last_logical_reads BIGINT NULL
			, t_min_logical_reads BIGINT NULL
			, t_max_logical_reads BIGINT NULL
			, t_avg_logical_writes float NULL
			, t_total_logical_writes BIGINT NULL
			, t_last_logical_writes BIGINT NULL
			, t_min_logical_writes BIGINT NULL
			, t_max_logical_writes BIGINT NULL
			, t_avg_IO float NULL
			, t_total_IO BIGINT NULL
			, t_last_IO BIGINT NULL
			, t_min_IO BIGINT NULL
			, t_max_IO BIGINT NULL
			, t_CPURank INT NULL
			, t_ReadRank INT NULL
			, t_WriteRank INT NULL
		) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]



		INSERT INTO #LEXEL_OES_stats_sql_handle_convert_table 
		SELECT
		sql_handle
		, sql_handle AS chart_display_option 
		, sql_handle AS chart_display_optionIO 
		, master.dbo.fn_varbintohexstr(sql_handle)
		, dense_RANK() over (order by s2.dbid,s2.objectid) AS SPRank 
		, s2.dbid
		, s2.objectid
		, (SELECT top 1 substring(text,(s1.statement_start_offset+2)/2, (CASE WHEN s1.statement_end_offset = -1 then len(convert(NVARCHAR(max),text))*2 else s1.statement_end_offset END - s1.statement_start_offset) /2 ) FROM sys.dm_exec_sql_text(s1.sql_handle)) AS [SQL Statement]
		, execution_count
		, plan_generation_num
		, last_execution_time
		, (CONVERT(MONEY,total_worker_time)/execution_count)/1000 AS [avg_worker_time]
		, total_worker_time/1000.0
		, last_worker_time/1000.0
		, min_worker_time/1000.0
		, max_worker_time/1000.0
		, (CONVERT(MONEY,total_logical_reads)/execution_count) AS [avg_logical_reads]
		, total_logical_reads
		, last_logical_reads
		, min_logical_reads
		, max_logical_reads
		, (CONVERT(MONEY,total_logical_writes)/execution_count) AS [avg_logical_writes]
		, total_logical_writes
		, last_logical_writes
		, min_logical_writes
		, max_logical_writes
		, ((CONVERT(MONEY,total_logical_writes)/execution_count + CONVERT(MONEY,total_logical_reads))/execution_count) AS [avg_logical_IO]
		, total_logical_writes + total_logical_reads
		, last_logical_writes +last_logical_reads
		, min_logical_writes +min_logical_reads
		, max_logical_writes + max_logical_reads 
		FROM #dadatafor_exec_query_stats s1 
		CROSS APPLY sys.dm_exec_sql_text(sql_handle) s2 
		WHERE s2.objectid IS NOT NULL AND db_name(s2.dbid) IS NOT NULL
		AND (total_logical_writes + total_logical_reads) * execution_count > 1000
		ORDER BY s1.sql_handle; 

		SELECT @grand_total_worker_time = SUM(t_total_worker_time)
		, @grand_total_IO = SUM(t_total_logical_reads + t_total_logical_writes) 
		from #LEXEL_OES_stats_sql_handle_convert_table; 
		SELECT @grand_total_worker_time = CASE WHEN @grand_total_worker_time > 0 THEN @grand_total_worker_time ELSE 1.0 END ; 
		SELECT @grand_total_IO = CASE WHEN @grand_total_IO > 0 THEN @grand_total_IO ELSE 1.0 END ; 

		set @cnt = 1; 
		SELECT @record_count = count(*) FROM #LEXEL_OES_stats_sql_handle_convert_table ; 
		WHILE (@cnt <= @record_count) 
		BEGIN 
		 SELECT @dbid = t_dbid
		 , @objectid = t_objectid 
		 FROM #LEXEL_OES_stats_sql_handle_convert_table WHERE row_id = @cnt; 
		 if not exists (SELECT 1 FROM #LEXEL_OES_stats_object_name WHERE objectId = @objectid AND dbId = @dbid )
		 BEGIN
		 SET @cmd = 'SELECT '+convert(NVARCHAR(10),@dbid)+','+convert(NVARCHAR(100),@objectid)+','''+db_name(@dbid)+'''
					 , obj.name,obj.type
					 , CASE WHEN sch.name IS NULL THEN '''' ELSE sch.name END 
		 FROM ['+db_name(@dbid)+'].sys.objects obj 
					 LEFT OUTER JOIN ['+db_name(@dbid)+'].sys.schemas sch on(obj.schema_id = sch.schema_id) 
		 WHERE obj.object_id = '+convert(NVARCHAR(100),@objectid)+ ';'
		 INSERT INTO #LEXEL_OES_stats_object_name
		 EXEC(@cmd)
				END
		 SET @cnt = @cnt + 1 ; 
		END ; 

		INSERT INTO #LEXEL_OES_stats_objects 
		SELECT t_SPRank
		, SUM(t_total_worker_time)
		, SUM(t_total_logical_reads)
		, SUM(t_total_logical_writes)
		, SUM(t_total_logical_IO)
		, SUM(t_avg_worker_time) AS avg_cpu
		, SUM(t_avg_logical_reads)
		, SUM(t_avg_logical_writes)
		, SUM(t_avg_logical_IO)
		, RANK()OVER (ORDER BY SUM(t_avg_worker_time) DESC)
		, RANK()OVER (ORDER BY SUM(t_total_worker_time) DESC)
		, RANK()OVER (ORDER BY SUM(t_avg_logical_reads) DESC)
		, RANK()OVER (ORDER BY SUM(t_avg_logical_writes) DESC)
		, RANK()OVER (ORDER BY SUM(t_total_logical_IO) DESC)
		FROM #LEXEL_OES_stats_sql_handle_convert_table 
		GROUP BY t_SPRank ; 

		UPDATE #LEXEL_OES_stats_sql_handle_convert_table SET t_display_option = 'show_total' 
		WHERE t_SPRank IN (SELECT obj_rank FROM #LEXEL_OES_stats_objects WHERE (CONVERT(MONEY,total_cpu))/@grand_total_worker_time < 0.05) ; 

		UPDATE #LEXEL_OES_stats_sql_handle_convert_table SET t_display_option = t_sql_handle_text 
		WHERE t_SPRank IN (SELECT obj_rank FROM #LEXEL_OES_stats_objects WHERE total_cpu_rank <= 5) ; 

		UPDATE #LEXEL_OES_stats_sql_handle_convert_table SET t_display_option = 'show_total' 
		WHERE t_SPRank IN (SELECT obj_rank FROM #LEXEL_OES_stats_objects WHERE (CONVERT(MONEY,total_cpu))/@grand_total_worker_time < 0.005); 

		UPDATE #LEXEL_OES_stats_sql_handle_convert_table SET t_display_optionIO = 'show_total' 
		WHERE t_SPRank IN (SELECT obj_rank FROM #LEXEL_OES_stats_objects WHERE (CONVERT(MONEY,total_logical_io))/@grand_total_IO < 0.05); 

		UPDATE #LEXEL_OES_stats_sql_handle_convert_table SET t_display_optionIO = t_sql_handle_text 
		WHERE t_SPRank IN (SELECT obj_rank FROM #LEXEL_OES_stats_objects WHERE logical_io_rank <= 5) ; 

		UPDATE #LEXEL_OES_stats_sql_handle_convert_table SET t_display_optionIO = 'show_total' 
		WHERE t_SPRank IN (SELECT obj_rank FROM #LEXEL_OES_stats_objects WHERE (CONVERT(MONEY,total_logical_io))/@grand_total_IO < 0.005); 


	END TRY
	BEGIN CATCH 
		SELECT -100 AS l1
		, ERROR_NUMBER() AS l2
		, ERROR_SEVERITY() AS row_id
		, ERROR_STATE() AS t_sql_handle
		, ERROR_MESSAGE() AS t_display_option
		, 1 AS t_display_optionIO, 1 AS t_sql_handle_text,1 AS t_SPRank,1 AS t_dbid ,1 AS t_objectid ,1 AS t_SQLStatement,1 AS t_execution_count,1 AS t_plan_generation_num,1 AS t_last_execution_time, 1 AS t_avg_worker_time, 1 AS t_total_worker_time, 1 AS t_last_worker_time, 1 AS t_min_worker_time, 1 AS t_max_worker_time, 1 AS t_avg_logical_reads, 1 AS t_total_logical_reads, 1 AS t_last_logical_reads, 1 AS t_min_logical_reads, 1 AS t_max_logical_reads, 1 AS t_avg_logical_writes, 1 AS t_total_logical_writes, 1 AS t_last_logical_writes, 1 AS t_min_logical_writes, 1 AS t_max_logical_writes, 1 AS t_avg_logical_IO, 1 AS t_total_logical_IO, 1 AS t_last_logical_IO, 1 AS t_min_logical_IO, 1 AS t_max_logical_IO, 1 AS t_CPURank, 1 AS t_logical_ReadRank, 1 AS t_logical_WriteRank, 1 AS t_obj_name, 1 AS t_obj_type, 1 AS schama_name, 1 AS t_db_name 
	END CATCH

	BEGIN TRY
	set @dbid = db_id(); 
	SET @cnt = 0; 
	SET @record_count = 0; 
	DECLARE @sql_handle varbinary(64); 
	DECLARE @sql_handle_string NVARCHAR(130); 
	SET @grand_total_worker_time = 0 ; 
	SET @grand_total_IO = 0 ; 

	IF OBJECT_ID('tempdb..#sql_handle_convert_table') IS NOT NULL
				DROP TABLE #sql_handle_convert_table;
	CREATE TABLE #sql_handle_convert_table (
	 row_id INT identity 
	, t_sql_handle varbinary(64)
	, t_display_option NVARCHAR(140) collate database_default
	, t_display_optionIO NVARCHAR(140) collate database_default
	, t_sql_handle_text NVARCHAR(140) collate database_default
	, t_SPRank INT
	, t_SPRank2 INT
	, t_SQLStatement NVARCHAR(max) collate database_default
	, t_execution_count INT 
	, t_plan_generation_num INT
	, t_last_execution_time datetime
	, t_avg_worker_time FLOAT
	, t_total_worker_time BIGINT
	, t_last_worker_time BIGINT
	, t_min_worker_time BIGINT
	, t_max_worker_time BIGINT 
	, t_avg_logical_reads FLOAT
	, t_total_logical_reads BIGINT
	, t_last_logical_reads BIGINT
	, t_min_logical_reads BIGINT 
	, t_max_logical_reads BIGINT
	, t_avg_logical_writes FLOAT
	, t_total_logical_writes BIGINT
	, t_last_logical_writes BIGINT
	, t_min_logical_writes BIGINT
	, t_max_logical_writes BIGINT
	, t_avg_IO FLOAT
	, t_total_IO BIGINT
	, t_last_IO BIGINT
	, t_min_IO BIGINT
	, t_max_IO BIGINT
	);

	IF OBJECT_ID('tempdb..#perf_report_objects') IS NOT NULL
				DROP TABLE #perf_report_objects;
	CREATE TABLE #perf_report_objects (
	 obj_rank INT
	, total_cpu BIGINT 
	, total_reads BIGINT
	, total_writes BIGINT
	, total_io BIGINT
	, avg_cpu BIGINT 
	, avg_reads BIGINT
	, avg_writes BIGINT
	, avg_io BIGINT
	, cpu_rank INT
	, total_cpu_rank INT
	, read_rank INT
	, write_rank INT
	, io_rank INT
	); 

	INSERT INTO #sql_handle_convert_table
	SELECT sql_handle
	, sql_handle AS chart_display_option 
	, sql_handle AS chart_display_optionIO 
	, master.dbo.fn_varbintohexstr(sql_handle)
	, dense_RANK() over (order by s1.sql_handle) AS SPRank 
	, dense_RANK() over (partition by s1.sql_handle order by s1.statement_start_offset) AS SPRank2
	, replace(replace(replace(replace(CONVERT(NVARCHAR(MAX),(SELECT top 1 substring(text,(s1.statement_start_offset+2)/2, (CASE WHEN s1.statement_end_offset = -1 then len(convert(NVARCHAR(max),text))*2 else s1.statement_end_offset END - s1.statement_start_offset) /2 ) FROM sys.dm_exec_sql_text(s1.sql_handle))), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), ' ',' ') AS [SQL Statement]
	, execution_count
	, plan_generation_num
	, last_execution_time
	, ((CONVERT(MONEY,total_worker_time))/execution_count)/1000 AS [avg_worker_time]
	, total_worker_time/1000
	, last_worker_time/1000
	, min_worker_time/1000
	, max_worker_time/1000
	, ((CONVERT(MONEY,total_logical_reads))/execution_count) AS [avg_logical_reads]
	, total_logical_reads
	, last_logical_reads
	, min_logical_reads
	, max_logical_reads
	, ((CONVERT(MONEY,total_logical_writes))/execution_count) AS [avg_logical_writes]
	, total_logical_writes
	, last_logical_writes
	, min_logical_writes
	, max_logical_writes
	, ((CONVERT(MONEY,total_logical_writes))/execution_count + (CONVERT(MONEY,total_logical_reads))/execution_count) AS [avg_IO]
	, total_logical_writes + total_logical_reads
	, last_logical_writes +last_logical_reads
	, min_logical_writes +min_logical_reads
	, max_logical_writes + max_logical_reads 
	from #dadatafor_exec_query_stats s1 
	cross apply sys.dm_exec_sql_text(sql_handle) AS s2 
	WHERE s2.objectid is null
	AND (total_logical_writes + total_logical_reads) * execution_count > 1000
	order by s1.sql_handle; 

	SELECT @grand_total_worker_time = SUM(t_total_worker_time) 
	, @grand_total_IO = SUM(t_total_logical_reads + t_total_logical_writes) 
	from #sql_handle_convert_table; 

	SELECT @grand_total_worker_time = CASE WHEN @grand_total_worker_time > 0 then @grand_total_worker_time else 1.0 END ; 
	SELECT @grand_total_IO = CASE WHEN @grand_total_IO > 0 then @grand_total_IO else 1.0 END ; 

	Insert INTo #perf_report_objects 
	SELECT t_SPRank
	, SUM(t_total_worker_time)
	, SUM(t_total_logical_reads)
	, SUM(t_total_logical_writes)
	, SUM(t_total_IO)
	, SUM(t_avg_worker_time) AS avg_cpu
	, SUM(t_avg_logical_reads)
	, SUM(t_avg_logical_writes)
	, SUM(t_avg_IO)
	, RANK() OVER(ORDER BY SUM(t_avg_worker_time) DESC)
	, ROW_NUMBER() OVER(ORDER BY SUM(t_total_worker_time) DESC)
	, ROW_NUMBER() OVER(ORDER BY SUM(t_avg_logical_reads) DESC)
	, ROW_NUMBER() OVER(ORDER BY SUM(t_avg_logical_writes) DESC)
	, ROW_NUMBER() OVER(ORDER BY SUM(t_total_IO) DESC)
	from #sql_handle_convert_table
	group by t_SPRank ; 

	UPDATE #sql_handle_convert_table SET t_display_option = 'show_total'
	WHERE t_SPRank IN (SELECT obj_rank FROM #perf_report_objects WHERE (CONVERT(MONEY,total_cpu))/@grand_total_worker_time < 0.05) ; 

	UPDATE #sql_handle_convert_table SET t_display_option = t_sql_handle_text 
	WHERE t_SPRank IN (SELECT obj_rank FROM #perf_report_objects WHERE total_cpu_rank <= 5) ; 

	UPDATE #sql_handle_convert_table SET t_display_option = 'show_total' 
	WHERE t_SPRank IN (SELECT obj_rank FROM #perf_report_objects WHERE (CONVERT(MONEY,total_cpu))/@grand_total_worker_time < 0.005); 

	UPDATE #sql_handle_convert_table SET t_display_optionIO = 'show_total' 
	WHERE t_SPRank IN (SELECT obj_rank FROM #perf_report_objects WHERE (CONVERT(MONEY,total_io))/@grand_total_IO < 0.05); 

	UPDATE #sql_handle_convert_table SET t_display_optionIO = t_sql_handle_text 
	WHERE t_SPRank IN (SELECT obj_rank FROM #perf_report_objects WHERE io_rank <= 5) ; 

	UPDATE #sql_handle_convert_table SET t_display_optionIO = 'show_total' 
	WHERE t_SPRank IN (SELECT obj_rank FROM #perf_report_objects WHERE (CONVERT(MONEY,total_io))/@grand_total_IO < 0.005); 


	END TRY
	BEGIN catch
	SELECT -100 AS l1
	, ERROR_NUMBER() AS l2
	, ERROR_SEVERITY() AS row_id
	, ERROR_STATE() AS t_sql_handle
	, ERROR_MESSAGE() AS t_display_option
	, 1 AS t_display_optionIO, 1 AS t_sql_handle_text, 1 AS t_SPRank, 1 AS t_SPRank2, 1 AS t_SQLStatement, 1 AS t_execution_count , 1 AS t_plan_generation_num, 1 AS t_last_execution_time, 1 AS t_avg_worker_time, 1 AS t_total_worker_time, 1 AS t_last_worker_time, 1 AS t_min_worker_time, 1 AS t_max_worker_time, 1 AS t_avg_logical_reads 
	, 1 AS t_total_logical_reads, 1 AS t_last_logical_reads, 1 AS t_min_logical_reads, 1 AS t_max_logical_reads, 1 AS t_avg_logical_writes, 1 AS t_total_logical_writes, 1 AS t_last_logical_writes, 1 AS t_min_logical_writes, 1 AS t_max_logical_writes, 1 AS t_avg_IO, 1 AS t_total_IO, 1 AS t_last_IO, 1 AS t_min_IO, 1 AS t_max_IO, 1 AS t_CPURank, 1 AS t_ReadRank, 1 AS t_WriteRank
	END catch



	INSERT INTO #LEXEL_OES_stats_output
	(evaldate, [Type], l1, l2, row_id, t_obj_name, t_obj_type, [schema_name], t_db_name, t_sql_handle, t_SPRank, t_SPRank2, t_SQLStatement
	, t_execution_count, t_plan_generation_num, t_last_execution_time, t_avg_worker_time, t_total_worker_time, t_last_worker_time, t_min_worker_time, t_max_worker_time, t_avg_logical_reads
	, t_total_logical_reads, t_last_logical_reads, t_min_logical_reads, t_max_logical_reads, t_avg_logical_writes, t_total_logical_writes, t_last_logical_writes, t_min_logical_writes
	, t_max_logical_writes, t_avg_IO, t_total_IO, t_last_IO, t_min_IO, t_max_IO, t_CPURank, t_ReadRank, t_WriteRank)
	SELECT @evaldate
	, 'OBJECT' [Type]
	, (s.t_SPRank)%2 AS l1
	, (DENSE_RANK() OVER(ORDER BY s.t_SPRank,s.row_id))%2 AS l2
	, row_id
	, objname.objectName AS t_obj_name
	, objname.objectType AS [t_obj_type]
	, objname.schemaName AS schema_name
	, objname.dbName AS t_db_name
	, s.t_sql_handle
	--, s.t_display_option
	--, s.t_display_optionIO
	--,s.t_sql_handle_text
	, s.t_SPRank 
	, NULL t_SPRank2 
	, replace(replace(replace(replace(CONVERT(NVARCHAR(MAX),s.t_SQLStatement), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), ' ',' ') t_SQLStatement 
	, s.t_execution_count 
	, s.t_plan_generation_num 
	, s.t_last_execution_time 
	, s.t_avg_worker_time 
	, s.t_total_worker_time 
	, s.t_last_worker_time 
	, s.t_min_worker_time 
	, s.t_max_worker_time 
	, s.t_avg_logical_reads 
	, s.t_total_logical_reads
	, s.t_last_logical_reads 
	, s.t_min_logical_reads 
	, s.t_max_logical_reads 
	, s.t_avg_logical_writes 
	, s.t_total_logical_writes 
	, s.t_last_logical_writes 
	, s.t_min_logical_writes 
	, s.t_max_logical_writes 
	, t_avg_logical_IO t_avg_IO 
	, t_total_logical_IO t_total_IO 
	, t_last_logical_IO t_last_IO 
	, t_min_logical_IO t_min_IO 
	, t_max_logical_IO t_max_IO
	, ob.cpu_rank AS t_CPURank 
	, ob.logical_read_rank t_ReadRank 
	, ob.logical_write_rank t_WriteRank 

	FROM #LEXEL_OES_stats_sql_handle_convert_table s 
	JOIN #LEXEL_OES_stats_objects ob on (s.t_SPRank = ob.obj_rank)
	JOIN #LEXEL_OES_stats_object_name AS objname on (objname.dbId = s.t_dbid and objname.objectId = s.t_objectid )


	INSERT INTO #LEXEL_OES_stats_output
	(evaldate, [Type], l1, l2, row_id, t_obj_name, t_obj_type, [schema_name], t_db_name, t_sql_handle, t_SPRank, t_SPRank2, t_SQLStatement
	, t_execution_count, t_plan_generation_num, t_last_execution_time, t_avg_worker_time, t_total_worker_time, t_last_worker_time, t_min_worker_time, t_max_worker_time, t_avg_logical_reads
	, t_total_logical_reads, t_last_logical_reads, t_min_logical_reads, t_max_logical_reads, t_avg_logical_writes, t_total_logical_writes, t_last_logical_writes, t_min_logical_writes
	, t_max_logical_writes, t_avg_IO, t_total_IO, t_last_IO, t_min_IO, t_max_IO, t_CPURank, t_ReadRank, t_WriteRank)
	SELECT 
	  @evaldate
	, 'BATCH' [Type]
	, (s.t_SPRank)%2 AS l1
	, (dense_RANK() OVER(ORDER BY s.t_SPRank,s.row_id))%2 AS l2
	, row_id
	, NULL t_obj_name
	, NULL [t_obj_type]
	, NULL schema_name
	, NULL t_db_name
	, s.t_sql_handle
	--, s. t_display_option
	--, s.t_display_optionIO 
	--, s.t_sql_handle_text 
	, s.t_SPRank 
	, s.t_SPRank2 
	, replace(replace(replace(replace(replace(CONVERT(NVARCHAR(MAX),t_SQLStatement), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), ' ',' '),'  ', ' ') t_SQLStatement 
	, s.t_execution_count 
	, s.t_plan_generation_num 
	, s.t_last_execution_time 
	, s.t_avg_worker_time 
	, s.t_total_worker_time 
	, s.t_last_worker_time 
	, s.t_min_worker_time 
	, s.t_max_worker_time 
	, s.t_avg_logical_reads 
	, s.t_total_logical_reads
	, s.t_last_logical_reads 
	, s.t_min_logical_reads 
	, s.t_max_logical_reads 
	, s.t_avg_logical_writes 
	, s.t_total_logical_writes 
	, s.t_last_logical_writes 
	, s.t_min_logical_writes 
	, s.t_max_logical_writes 
	, s.t_avg_IO 
	, s.t_total_IO 
	, s.t_last_IO 
	, s.t_min_IO 
	, s.t_max_IO
	, ob.cpu_rank AS t_CPURank 
	, ob.read_rank AS t_ReadRank 
	, ob.write_rank AS t_WriteRank 
	FROM  #sql_handle_convert_table s join #perf_report_objects ob on (s.t_SPRank = ob.obj_rank)


	SELECT @TotalIODailyWorkload = SUM(CONVERT(MONEY,CONVERT(FLOAT,t_total_IO) * 8 /*KB*/ /1024/*MB*//1024)/@DaysOldestCachedQuery)  
	FROM #LEXEL_OES_stats_output

	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 99, 'Workload details I/O','------','------'
	INSERT #output_man_script (SectionID, Section,Summary,Details)
	SELECT  99 [SectionID]
	, 'Oldest Cache: ' + CONVERT(VARCHAR(15), @DaysOldestCachedQuery) + '; Days Uptime: ' + CONVERT(VARCHAR(15),@DaysUptime) [Section]
	, CONVERT(VARCHAR(15),SUM(CONVERT(MONEY,CONVERT(FLOAT,t_total_IO) * 8 /*KB*/ /1024/*MB*//1024)/@DaysOldestCachedQuery)  )
	+ 'GB/day; ' + CONVERT(VARCHAR(15),SUM(CASE WHEN t_execution_count = 1 THEN 1 ELSE CONVERT(MONEY,t_execution_count)/@DaysOldestCachedQuery END) ) 
	+ ' executions/day; ' +  CONVERT(VARCHAR(15),SUM(CONVERT(MONEY,t_avg_worker_time)/1000 ))
	+ ' s(avg) *[DailyGB; DailyExecutions; AverageTime(s)]' Summary
	, 'Total' [Details]
	FROM #LEXEL_OES_stats_output
	GROUP BY domain, SQLInstance

	INSERT #output_man_script (SectionID, Section)
	SELECT  99, 'Total Disk I/O per day: '
		+ CONVERT(VARCHAR(20),CASE WHEN SUM([num_of_reads]) + SUM([num_of_writes]) = 0 THEN 0 
			ELSE CONVERT(MONEY,(SUM([num_of_reads]) + SUM([num_of_writes]))) * 8 /1024/1024/ CONVERT(MONEY,@DaysUptime) END ) + 'GB/day'
	FROM sys.dm_io_virtual_file_stats (NULL,NULL) AS [s]
	
	INSERT #output_man_script (SectionID, Section,Summary,Details)
	SELECT
	 99 [SectionID]
	, REPLICATE('|', CONVERT(INT,(CONVERT(MONEY,t_total_IO * 8 /*KB*/ /1024/*MB*//1024)/@DaysOldestCachedQuery )/@TotalIODailyWorkload *100)) + ' ' + CONVERT(VARCHAR(10),(CONVERT(MONEY,CONVERT(FLOAT,t_total_IO) * 8 /*KB*/ /1024/*MB*//1024)/@DaysOldestCachedQuery )/@TotalIODailyWorkload *100) + '%' [Section]
	, CONVERT(VARCHAR(15),(CONVERT(MONEY,CONVERT(FLOAT,t_total_IO) * 8 /*KB*/ /1024/*MB*//1024)/@DaysOldestCachedQuery) )
	+ 'GB/day; ' + CONVERT(VARCHAR(15),(CASE WHEN t_execution_count = 1 THEN 1 ELSE CONVERT(MONEY,t_execution_count)/@DaysOldestCachedQuery END) ) 
	+ ' executions/day; ' +  CONVERT(VARCHAR(15),(CONVERT(MONEY,t_avg_worker_time_S)))
	+ ' s(avg) *[DailyGB; DailyExecutions; AverageTime(s)]' [Summary]
	, LEFT('/*' + [Type] + '; '+ ISNULL(t_obj_name,'') + ' [' + ISNULL(t_db_name,'') + '].[' + ISNULL(schema_name,'') + '] > */' + ISNULL(t_SQLStatement,''),3850) [Details]  
	FROM (

	SELECT TOP 10 ID
		, @evaldate [evaldate]
		, domain
		, SQLInstance
		, [Type]
		, row_id
		, t_obj_name
		, t_obj_type
		, [schema_name]
		, t_db_name
		, replace(replace(replace(replace(replace(CONVERT(NVARCHAR(MAX),t_SQLStatement), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), ' ',' '),'  ', ' ') t_SQLStatement
		, t_execution_count
		, CASE WHEN t_execution_count = 1 THEN 1 ELSE CONVERT(MONEY,t_execution_count)/@DaysOldestCachedQuery END AS [t_execution_count_Daily]
		, t_plan_generation_num
		, CONVERT(MONEY,CONVERT(FLOAT,t_avg_worker_time)/1000) t_avg_worker_time_S
		, CONVERT(MONEY,CONVERT(FLOAT,t_total_worker_time)/1000)  t_total_worker_time_S
		, CONVERT(MONEY,t_avg_logical_reads) t_avg_logical_reads
		, t_total_logical_reads
		, CONVERT(MONEY,t_avg_logical_writes) t_avg_logical_writes
		, t_total_logical_writes
		,  CONVERT(MONEY,t_avg_IO) t_avg_IO
		, t_total_IO
		, CONVERT(MONEY,CONVERT(FLOAT,t_avg_IO) * 8 /*KB*/ /1024/*MB*//1024) [Average Workload GB]
		, CONVERT(MONEY,CONVERT(FLOAT,t_total_IO) * 8 /*KB*/ /1024/*MB*//1024) [Total Workload GB]
		, CONVERT(MONEY,CONVERT(FLOAT,t_total_IO) * 8 /*KB*/ /1024/*MB*//1024)/@DaysOldestCachedQuery [Daily Workload GB]
	FROM #LEXEL_OES_stats_output
	ORDER BY t_total_IO DESC
	) T1
	OPTION (RECOMPILE);

	IF @Debug = 0
		RAISERROR (N'Daily workload calculated',0,1) WITH NOWAIT;

/*----------------------------------------
--Add Latest Blitz output
----------------------------------------*/
/*

*/
IF OBJECT_ID('master.dbo.sp_Blitz_output') IS NULL
/*If no Blitz table, run Blitz*/
BEGIN
	IF @Debug = 0
		RAISERROR (N'Skipping sp_Blitz results, cannot find output table',0,1) WITH NOWAIT;
	--EXEC [dbo].[sp_Blitz] @CheckUserDatabaseObjects = 1 , @CheckProcedureCache = 1 , @OutputType = 'TABLE' , @OutputProcedureCache = 0 , @CheckServerInfo = 1, @OutputDatabaseName = 'master', @OutputSchemaName = 'dbo', @OutputTableName = 'sp_Blitz_output', @BringThePain = 1;
END
IF OBJECT_ID('master.dbo.sp_Blitz_output') IS NOT NULL
BEGIN
	IF @Debug = 0
		RAISERROR (N'Found sp_Blitz results, only recent results will be evaluated',0,1) WITH NOWAIT;
	INSERT #output_man_script (SectionID, Section,Summary, Details) SELECT 999, 'Blitz from here','------','------'
	INSERT INTO #output_man_script ( 
	domain
	,SQLInstance
	,evaldate
	,SectionID
	,Section
	,Summary
	, Details )
	EXEC ('
	SELECT  DEFAULT_DOMAIN() [Domain]
	,ServerName
	, CONVERT(VARCHAR,CheckDate,120)
	,CheckID --Priority + 1000
	--, FindingsGroup,
	, ''sp_Blitz:'' + Finding
	, DatabaseName
	, CONVERT(NVARCHAR(4000),Details)
	FROM master.dbo.sp_Blitz_output 
	WHERE CheckDate = (SELECT max([CheckDate]) FROM master.dbo.sp_Blitz_output HAVING DATEADD(DAY,-2,GETDATE()) < max([CheckDate]) )
	ORDER BY ID ASC'
	)

END

			/*----------------------------------------
			--select output
			----------------------------------------*/
IF @Debug = 0
		RAISERROR (N'Cleaning up output table',0,1) WITH NOWAIT;
DECLARE @ThisDomain NVARCHAR(100)
EXEC master.dbo.xp_regread 'HKEY_LOCAL_MACHINE', 'SYSTEM\CurrentControlSet\services\Tcpip\Parameters', N'Domain',@ThisDomain OUTPUT
SET @ThisDomain = ISNULL(@ThisDomain, DEFAULT_DOMAIN())

UPDATE  #output_man_script
SET evaldate = @evaldate
, SQLInstance = @ThisServer
, domain = @ThisDomain

IF UPPER(LEFT(@Export,1)) = 'S'
BEGIN	
	SELECT T1.ID
	,  evaldate
	, T1.domain
	, T1.SQLInstance
	, T1.SectionID
	, T1.Section
	, ISNULL(T1.Summary,'') [Summary]
	, ISNULL(T1.Severity,'') [Severity]
	, replace(replace(replace(replace( ISNULL(T1.Details,''), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' ') [Details]
	, ISNULL(T1.HoursToResolveWithTesting,'') [HoursToResolveWithTesting]
	, NULL QueryPlan
	FROM #output_man_script T1
	ORDER BY ID ASC
	OPTION (RECOMPILE)
END



IF UPPER(LEFT(@Export,1)) = 'T'
BEGIN
	IF @Debug = 0
		RAISERROR (N'Export to table. Creating table.',0,1) WITH NOWAIT;
	IF OBJECT_ID(@ExportDBName + '.' + @ExportSchema  + '.' + @ExportTableName) IS NULL
	BEGIN
		SET @dynamicSQL = 'CREATE TABLE ' + @ExportDBName + '.' + @ExportSchema  + '.' + @ExportTableName + '
	( 
	ID INT
	,  evaldate NVARCHAR(20)
	, domain NVARCHAR(505)
	, SQLInstance NVARCHAR(505)
	, SectionID INT
	, Section NVARCHAR(4000)
	, Summary NVARCHAR(4000)
	, Severity NVARCHAR(5)
	, Details NVARCHAR(4000)
	, HoursToResolveWithTesting MONEY 
	, QueryPlan NVARCHAR(MAX)
	);'	
		EXEC sp_executesql @dynamicSQL;	
	END
	ELSE
	BEGIN
		SET @dynamicSQL = 'DELETE FROM ' + @ExportDBName + '.' + @ExportSchema  + '.' + @ExportTableName + '
		WHERE	evaldate < DATEADD(DAY, - ' + CONVERT(VARCHAR(5),@ExportCleanupDays) + ', GETDATE())'
		EXEC sp_executesql @dynamicSQL;	
	END

	SET @dynamicSQL = '
  DECLARE @ColumnsToAdd TABLE (ID INT IDENTITY(1,1), ColumnName NVARCHAR(500), [order] INT, [length] INT)
  INSERT INTO @ColumnsToAdd
  SELECT targetcolumns.name, targetcolumns.column_id, targetcolumns.max_length
  FROM (
  SELECT c.name, column_id, max_length
  FROM tempdb.sys.columns c
  INNER JOIN tempdb.sys.tables  t ON t.object_id = c.object_id
  WHERE t.name  like ''%output_man_script%'') targetcolumns
  LEFT OUTER JOIN(
  SELECT c.name, column_id, max_length
  FROM master.sys.columns c
  INNER JOIN master.sys.tables  t ON t.object_id = c.object_id
  WHERE t.name = ''' + @ExportTableName + ''') currentcolumns ON targetcolumns.name = currentcolumns.name
  WHERE currentcolumns.name IS NULL

  DECLARE @MaxcolumnsToAdd INT 
  SET @MaxcolumnsToAdd = 0;
  DECLARE @ColumnCountLoop INT
  SET @ColumnCountLoop = 1; 
  DECLARE @ColumnToAdd NVARCHAR(500);
  DECLARE @ColumnToAddLen INT
  SET @ColumnToAddLen= 0;
  SET @MaxcolumnsToAdd  = (SELECT MAX(ID) FROM @ColumnsToAdd)
  IF @MaxcolumnsToAdd > 0
  BEGIN
	WHILE @ColumnCountLoop <= @MaxcolumnsToAdd
		BEGIN
			SELECT @ColumnToAdd = ColumnName
			, @ColumnToAddLen = [length]
			FROM @ColumnsToAdd WHERE ID = @ColumnCountLoop

			IF @ColumnToAdd = ''evaldate''
				ALTER TABLE ['+  @ExportDBName +'].[' + @ExportSchema + '].[' + @ExportTableName + '] ADD evaldate NVARCHAR(20)
			IF @ColumnToAdd = ''domain''
				ALTER TABLE ['+  @ExportDBName +'].[' + @ExportSchema + '].[' + @ExportTableName + '] ADD domain NVARCHAR(505) DEFAULT DEFAULT_DOMAIN()
			IF @ColumnToAdd = ''SQLInstance''
				ALTER TABLE ['+  @ExportDBName +'].[' + @ExportSchema + '].[' + @ExportTableName + '] ADD SQLInstance NVARCHAR(505) DEFAULT @@SERVERNAME
			IF @ColumnToAdd = ''SectionID''
				ALTER TABLE ['+  @ExportDBName +'].[' + @ExportSchema + '].[' + @ExportTableName + '] ADD SectionID int NULL
			IF @ColumnToAdd = ''Section''
				ALTER TABLE ['+  @ExportDBName +'].[' + @ExportSchema + '].[' + @ExportTableName + '] ADD Section NVARCHAR(4000)
			IF @ColumnToAdd = ''Summary''
				ALTER TABLE ['+  @ExportDBName +'].[' + @ExportSchema + '].[' + @ExportTableName + '] ADD Summary NVARCHAR(4000)
			IF @ColumnToAdd = ''Severity''
				ALTER TABLE ['+  @ExportDBName +'].[' + @ExportSchema + '].[' + @ExportTableName + '] ADD Severity NVARCHAR(5)
			IF @ColumnToAdd = ''Details''
				ALTER TABLE ['+  @ExportDBName +'].[' + @ExportSchema + '].[' + @ExportTableName + '] ADD Details NVARCHAR(4000)
			IF @ColumnToAdd = ''QueryPlan''
				ALTER TABLE ['+  @ExportDBName +'].[' + @ExportSchema + '].[' + @ExportTableName + '] ADD QueryPlan XML NULL
			IF @ColumnToAdd = ''HoursToResolveWithTesting''
				ALTER TABLE ['+  @ExportDBName +'].[' + @ExportSchema + '].[' + @ExportTableName + '] ADD HoursToResolveWithTesting MONEY  NULL
			SET @ColumnCountLoop = @ColumnCountLoop + 1;
		END
	END
	';
	EXEC sp_executesql @dynamicSQL;	
	IF @Debug = 0
		RAISERROR (N'Populating table',0,1) WITH NOWAIT;
	SET @dynamicSQL = 'INSERT INTO ' + @ExportDBName + '.' + @ExportSchema  + '.' + @ExportTableName + '
			(ID
			, evaldate
			, domain
			, SQLInstance
			, SectionID
			, Section
			, Summary
			, Severity
			, Details
			, HoursToResolveWithTesting
			, QueryPlan)
	SELECT T1.ID
	,  evaldate
	, T1.domain
	,'''+ @ThisServer  +'''
	, T1.SectionID
	, T1.Section
	, T1.Summary
	, T1.Severity
	, replace(replace(replace(replace( ISNULL(T1.Details,''''), CHAR(9), '' ''),CHAR(10),'' ''), CHAR(13), '' ''), ''  '','' '') [Details]
	, T1.HoursToResolveWithTesting
	, CASE WHEN  ' + CONVERT(VARCHAR(5),@ShowQueryPlan) + ' = 1 THEN ISNULL(replace(replace(replace(replace(ISNULL(CONVERT(NVARCHAR(MAX),QueryPlan),''''), CHAR(9), '' ''),CHAR(10),'' ''), CHAR(13), '' ''), ''  '','' ''),'''')   ELSE NULL END QueryPlan
	FROM #output_man_script T1
	ORDER BY ID ASC
	OPTION (RECOMPILE)'
	EXEC sp_executesql @dynamicSQL;	

	IF @ShowOnScreenWhenResultsToTable = 1 
	BEGIN
		IF @Debug = 0
			RAISERROR (N'Results to screen',0,1) WITH NOWAIT;
		/*And after all that hard work, how about we select to the screen as well*/
		SELECT T1.ID
		,  evaldate
		, T1.domain
		, @ThisServer
		, T1.SectionID
		, T1.Section
		, T1.Summary
		, T1.Severity
		, T1.Details
		, T1.HoursToResolveWithTesting
		, CASE WHEN  @ShowQueryPlan = 1 THEN ISNULL(replace(replace(replace(replace(ISNULL(CONVERT(NVARCHAR(MAX),QueryPlan),''), CHAR(9), ' '),CHAR(10),' '), CHAR(13), ' '), '  ',' '),'')   ELSE NULL END QueryPlan
		FROM #output_man_script T1
		ORDER BY ID ASC
		OPTION (RECOMPILE)
	END
END

/*Check to send out the results over email as well*/
IF @MailResults = 1 
BEGIN
IF @Debug = 0
		RAISERROR (N'Results to mail',0,1) WITH NOWAIT;
DECLARE @EmailSubject NVARCHAR(500)
SET @EmailSubject = 'Sqldba_sqlmagic_data for ' +@ThisDomain + ' '+@ThisServer + '' + REPLACE(REPLACE(REPLACE(@evaldate,'-','_'),':',''),' ','');
DECLARE @EmailBody NVARCHAR(500) 
DECLARE @query_result_separator NVARCHAR(50)
DECLARE @StringToExecute NVARCHAR(4000)
DECLARE @EmailProfile NVARCHAR(500)
DECLARE @AttachfileName NVARCHAR(500)
SET @query_result_separator = '~';--char(9);
SET @AttachfileName = 'sqldba_sqlmagic_data__' +REPLACE(@ThisDomain,'.','_') + '_'+ REPLACE(@ThisServer,@CharToCheck,'_') + '_' + REPLACE(REPLACE(REPLACE(@evaldate,'-','_'),':',''),' ','') +'.csv' 

/*Yes, it is a mouth full, but it works to create a nicely formed, ready to use CSV file.*/
	SET @StringToExecute = '
SET NOCOUNT ON;
SELECT ID,evaldate,domain,SQLInstance,SectionID,Section,Summary,Severity,Details,HoursToResolveWithTesting,QueryPlan
FROM (
SELECT 
CONVERT(NVARCHAR(25),		''ID'') ID
, CONVERT(NVARCHAR(50),		''evaldate'') evaldate
, CONVERT(NVARCHAR(50),		''domain'') domain
, CONVERT(NVARCHAR(50),		''SQLInstance'' ) SQLInstance
, CONVERT(NVARCHAR(10),		''SectionID'') SectionID
, CONVERT(NVARCHAR(1000),	''Section'') Section
, CONVERT(NVARCHAR(4000),	''Summary'') Summary
, CONVERT(NVARCHAR(15),		''Severity'') Severity
, CONVERT(NVARCHAR(4000),	''Details'') Details
, CONVERT(NVARCHAR(35),		''HoursToResolveWithTesting'') HoursToResolveWithTesting
, CONVERT(NVARCHAR(4000),	''QueryPlan'') QueryPlan
, 0 Sorter
UNION ALL
SELECT 
ID,evaldate,domain,SQLInstance,SectionID,Section,Summary,Severity,Details,HoursToResolveWithTesting,QueryPlan, Sorter
FROM 
(
SELECT TOP 100 PERCENT CONVERT(NVARCHAR(25),T1.ID) ID
,  REPLACE(T1.evaldate,''~'',''-'') evaldate
,  REPLACE(domain,''~'',''-'') domain
,  REPLACE(SQLInstance ,''~'',''-'') SQLInstance
,  REPLACE(CONVERT(NVARCHAR(10), SectionID),''~'',''-'')  SectionID
,  REPLACE(Section,''~'',''-'') Section
,  REPLACE(Summary,''~'',''-'') Summary
,  REPLACE(Severity,''~'',''-'') Severity
,  replace(replace(replace(replace( ISNULL(REPLACE(Details,''~'',''-''),''''), CHAR(9), '' ''),CHAR(10),'' ''), CHAR(13), '' ''), ''  '','' '') [Details]
,  REPLACE(CONVERT(NVARCHAR(10),HoursToResolveWithTesting),''~'',''-'') HoursToResolveWithTesting
,  REPLACE(QueryPlan,''~'',''-'')QueryPlan
,T1.ID Sorter
FROM ['+ @ExportDBName +'].[' + @ExportSchema +'].[' + @ExportTableName + ']
T1
INNER JOIN (
SELECT MAX(evaldate) evaldate FROM ['+ @ExportDBName +'].[' + @ExportSchema +'].[' + @ExportTableName + ']
) T2
ON T1.evaldate = T2.evaldate
) T3
) T4
ORDER BY Sorter ASC

; SET NOCOUNT OFF;';

					
					SET @EmailBody = @EmailSubject;
					/*Make sure there is space to send*/
					--EXECUTE msdb.dbo.sysmail_configure_sp 'MaxFileSize', '10000000';
					IF @EmailProfile IS NULL
					BEGIN
						EXEC msdb.dbo.sp_send_dbmail
						 @recipients = @EmailRecipients,
						 @subject = @EmailSubject,
						 @body = @EmailBody,
						 @query_attachment_filename =@AttachfileName,
						 @attach_query_result_as_file = 1,
						 @query_result_header = 0,/*Set to 0 to Turn Headers off, makes for better CSV files as long as we include headers in Select statement*/
						  @execute_query_database = @ExportDBName, 
						 @query_result_width = 32767,
						 @append_query_error = 1,
						 @query_result_no_padding = 1,
						 @query_result_separator = @query_result_separator,
						 @query = @StringToExecute EXECUTE AS LOGIN = N'sa';
					 END
							
END


	/*Before cleaning out tables, check if any other settings need to be turned OFF/ON*/
IF @TurnNumericRoundabortOn = 1
BEGIN
	SET NUMERIC_ROUNDABORT ON;
END
		
	/*Clean up #temp tables*/
	IF @Debug = 0
		RAISERROR (N'Cleaning up #temp tables',0,1) WITH NOWAIT;
	 IF(OBJECT_ID('tempdb..#InvalidLogins') IS NOT NULL)
        BEGIN
            EXEC sp_executesql N'DROP TABLE #InvalidLogins;';
        END;
	
	IF OBJECT_ID('tempdb..#output_man_script') IS NOT NULL
		DROP TABLE #output_man_script  
	IF OBJECT_ID('tempdb..#Action_Statistics') IS NOT NULL
		DROP TABLE #Action_Statistics
	IF OBJECT_ID('tempdb..#db_sps') IS NOT NULL
		DROP TABLE #db_sps
	IF OBJECT_ID('tempdb..#ConfigurationDefaults') IS NOT NULL
		DROP TABLE #ConfigurationDefaults
	IF OBJECT_ID('tempdb..#querystats') IS NOT NULL
		DROP TABLE #querystats
	IF OBJECT_ID('tempdb..#dbccloginfo') IS NOT NULL
		DROP TABLE #dbccloginfo
	IF OBJECT_ID('tempdb..#notrust') IS NOT NULL
		DROP TABLE #notrust
	IF OBJECT_ID('tempdb..#MissingIndex') IS NOT NULL
		DROP TABLE #MissingIndex;
	IF OBJECT_ID('tempdb..#HeapTable') IS NOT NULL
		DROP TABLE #HeapTable;
	IF OBJECT_ID('tempdb..#whatsets') IS NOT NULL
		DROP TABLE #whatsets
	IF OBJECT_ID('tempdb..#dbccloginfo') IS NOT NULL
		DROP TABLE #dbccloginfo
	IF OBJECT_ID('tempdb..SQLVersionsDump') IS NOT NULL
		DROP TABLE #SQLVersionsDump
	IF OBJECT_ID('tempdb..SQLVersions') IS NOT NULL
		DROP TABLE #SQLVersions
	IF OBJECT_ID('tempdb..#dadatafor_exec_query_stats') IS NOT NULL
		DROP TABLE #dadatafor_exec_query_stats;

	IF OBJECT_ID('tempdb.dbo.#LEXEL_OES_stats_sql_handle_convert_table', 'U') IS NOT NULL
		DROP TABLE #LEXEL_OES_stats_sql_handle_convert_table;
	IF OBJECT_ID('tempdb.dbo.#LEXEL_OES_stats_objects', 'U') IS NOT NULL
		DROP TABLE #LEXEL_OES_stats_objects;
	IF OBJECT_ID('tempdb.dbo.#LEXEL_OES_stats_object_name', 'U') IS NOT NULL
		DROP TABLE #LEXEL_OES_stats_object_name;
	IF OBJECT_ID('tempdb..#sql_handle_convert_table') IS NOT NULL
		DROP TABLE #sql_handle_convert_table;
	IF OBJECT_ID('tempdb..#perf_report_objects') IS NOT NULL
		DROP TABLE #perf_report_objects;
	IF OBJECT_ID('tempdb.dbo.#LEXEL_OES_stats_output', 'U') IS NOT NULL
		DROP TABLE #LEXEL_OES_stats_output;
	IF OBJECT_ID('tempdb..##spnCheck') IS NOT NULL
				DROP TABLE #spnCheck

--The blitz

		IF OBJECT_ID('tempdb..#ConfigurationDefaults') IS NOT NULL
			DROP TABLE #ConfigurationDefaults;


        IF OBJECT_ID ('tempdb..#Recompile') IS NOT NULL
            DROP TABLE #Recompile;


		IF OBJECT_ID('tempdb..#DatabaseDefaults') IS NOT NULL
			DROP TABLE #DatabaseDefaults;


		IF OBJECT_ID('tempdb..#DatabaseScopedConfigurationDefaults') IS NOT NULL
			DROP TABLE #DatabaseScopedConfigurationDefaults;
	
		IF OBJECT_ID('tempdb..#DBCCs') IS NOT NULL
			DROP TABLE #DBCCs;


		IF OBJECT_ID('tempdb..#LogInfo2012') IS NOT NULL
			DROP TABLE #LogInfo2012;


		IF OBJECT_ID('tempdb..#LogInfo') IS NOT NULL
			DROP TABLE #LogInfo;


		IF OBJECT_ID('tempdb..#partdb') IS NOT NULL
			DROP TABLE #partdb;

		IF OBJECT_ID('tempdb..#TraceStatus') IS NOT NULL
			DROP TABLE #TraceStatus;
	

		IF OBJECT_ID('tempdb..#driveInfo') IS NOT NULL
			DROP TABLE #driveInfo;
	

		IF OBJECT_ID('tempdb..#dm_exec_query_stats') IS NOT NULL
			DROP TABLE #dm_exec_query_stats;
	

		IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL
			DROP TABLE #ErrorLog;


		IF OBJECT_ID('tempdb..#fnTraceGettable') IS NOT NULL
			DROP TABLE #fnTraceGettable;


		IF OBJECT_ID('tempdb..#Instances') IS NOT NULL
			DROP TABLE #Instances;
	

		IF OBJECT_ID('tempdb..#IgnorableWaits') IS NOT NULL
			DROP TABLE #IgnorableWaits;
	

--the blitz



    SET NOCOUNT OFF;
	
END
