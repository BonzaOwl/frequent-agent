IF SCHEMA_ID('DBA') IS NULL

	BEGIN 

		RAISERROR('Attempting to create schema',1,1) WITH NOWAIT

		BEGIN TRY

		EXEC ('CREATE SCHEMA [DBA]');

		END TRY
		BEGIN CATCH
			RAISERROR('Creation of schema failed',1,1) WITH NOWAIT
		END CATCH

	END


IF OBJECT_ID ('DBA.JobHistory_Archive') IS NULL

	BEGIN

		RAISERROR('Required table doesn''t exist, attempting to create it...',1,1) WITH NOWAIT

		CREATE TABLE DBA.JobHistory_Archive 
		(
			ID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
			JobName nvarchar(128),
			Message nvarchar(4000),
			Run_Date INT,
			Run_Time INT,
			Run_Status INT,
			Date_Added DATETIME DEFAULT GETDATE()
		)

		RAISERROR('Required table created sucessfully',1,1) WITH NOWAIT

	END

IF OBJECT_ID ('DBA.Cleanup_Frequent_Job_History') IS NOT NULL

	BEGIN 

		RAISERROR('The stored procedure already exists, we are going to drop it and re-create',1,1) WITH NOWAIT
		DROP PROCEDURE [DBA].[Cleanup_Frequent_Job_History]

	END

IF OBJECT_ID('DBA.p_Cleanup_Frequent_Job_History') IS NULL

BEGIN

	DECLARE @CreateProc nvarchar(max)

	RAISERROR('Attempting to create stored procedure...',1,1) WITH NOWAIT

	SET @CreateProc = 'CREATE PROCEDURE [DBA].[Cleanup_Frequent_Job_History]

	AS

	BEGIN

		SET NOCOUNT ON;
	
		--A couple of variables that we are going to use
		DECLARE @Counter INT
		DECLARE @MaxID INT
		DECLARE @JobName NVARCHAR(128)

		--A temp table to hold some results for us to loop through
		CREATE TABLE #Results
		(
			ID INT IDENTITY(1,1) NOT NULL,
			JobName NVARCHAR(128)
		)

		BEGIN

			BEGIN TRY

				BEGIN TRANSACTION t1
		
					--Get the job name of the jobs we want to purge the data for
					INSERT INTO #Results
					SELECT 
						[sJOB].[name] AS [JobName]
					FROM
						[msdb].[dbo].[sysjobs] AS [sJOB]
  
						LEFT JOIN [msdb].[dbo].[sysjobschedules] AS [sJOBSCH]
							ON [sJOB].[job_id] = [sJOBSCH].[job_id]
    
						LEFT JOIN [msdb].[dbo].[sysschedules] AS [sSCH]
							ON [sJOBSCH].[schedule_id] = [sSCH].[schedule_id]

						LEFT JOIN [msdb].[dbo].[sysschedules] AS [SShed]
							ON SShed.schedule_id = SSch.schedule_id

						WHERE 
						[sJOB].enabled = 1 --Make sure that the job is actually active
						AND [sSCH].[schedule_uid] IS NOT NULL --Job is scheduled
						AND [SShed].[freq_subday_type] = 4 --Jobs that run every x minutes
						AND [SShed].[freq_subday_interval] < 60 --Jobs that run less than every 60 minutes

				COMMIT TRANSACTION t1

			END TRY
			BEGIN CATCH 
		
			RAISERROR(''Something has gone wrong here'',1,1) WITH NOWAIT

			ROLLBACK TRANSACTION t1

			END CATCH

		END

		SET @Counter = 1

		--Set the MAXID from the MAXID of the results table 
		SET @MaxID = (SELECT MAX(ID) FROM #Results)

		--If the counter is less or equal to the max id keep looping
		WHILE @Counter <= @MaxID

		BEGIN

			BEGIN TRY

				BEGIN TRANSACTION t2
		
					--Get the job name from the results data set 
					SET @JobName = (SELECT JobName FROM #Results WHERE ID = @Counter)

					--Store the history of the data we are going to remove in a table that isn''t MSDB
					--that way we can add an index etc.
					INSERT INTO [DBA_Tasks].[DBA].[JobHistory_Archive](JobName,Message,Run_Date,Run_Time,Run_Status)
		
					SELECT 
						j.name,
						jh.message,
						jh.run_date,
						jh.run_time,
						jh.run_status 
		
					FROM 
						msdb..sysjobhistory jh
					LEFT JOIN msdb..sysjobs j ON
						j.job_id = jh.job_id

					WHERE 
					j.name = @JobName
		
					--Remove the data from the MSDB jobhistory table, we don''t want any of this data keeping so we won''t specify a date
					EXEC msdb..sp_purge_jobhistory @job_name = @JobName

				COMMIT TRANSACTION t2

			END TRY
			BEGIN CATCH

				RAISERROR(''Something has gone wrong purging the data...rolling back'',1,1) WITH NOWAIT

			ROLLBACK TRANSACTION t2

			END CATCH

			--Increment that counter and loop if we don''t meet the MAX ID condition
			SET @Counter = @Counter +1

		END

		--We are done, drop the temp table
		DROP TABLE #Results

	END'

	BEGIN TRY

	EXEC(@CreateProc)

	RAISERROR('Stored procedure sucessfully created.',1,1) WITH NOWAIT

	END TRY
	BEGIN CATCH

		RAISERROR('Creation of stored procedure failed....',1,1) WITH NOWAIT

	END CATCH

END

IF NOT EXISTS(SELECT name FROM msdb.dbo.sysjobs where name = 'SQL Agent Log Cleanup')
BEGIN TRY

RAISERROR('Attempting to create SQL Agent Job',0,1) WITH NOWAIT

USE [msdb];

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'SQL Agent Log Cleanup', 
		@enabled=0, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Execute Agent Log Cleanup', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'EXEC [DBA].[Cleanup_Frequent_Job_History]', 
		@database_name=N'DBA_Tasks', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
END TRY
BEGIN CATCH
	RAISERROR('Creation of SQL Agent Job failed',0,1) WITH NOWAIT
END CATCH