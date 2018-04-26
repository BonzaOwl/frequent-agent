USE MSDB

GO

IF DB_ID('DBA_Tasks') IS NULL
	
	BEGIN

		CREATE DATABASE DBA_Tasks

	END

	ELSE

	BEGIN

		Print 'DBA_Tasks already exists in your environment'

	END

USE DBA_Tasks

IF SCHEMA_ID('DBA') IS NULL

	BEGIN 

		EXEC ('CREATE SCHEMA [DBA] AUTHORIZATION [DBO]');

	END


IF OBJECT_ID ('DBA.JobHistory_Archive') IS NULL

	BEGIN

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

	END

	ELSE

	BEGIN

		Print 'Great, the table already exists'

	END

IF OBJECT_ID ('DBA.p_Cleanup_Frequent_Job_History') IS NULL

	BEGIN 

		Print 'The stored procedure already exists, we are going to drop it and re-create'
		DROP PROCEDURE [DBA].[p_Cleanup_Frequent_Job_History]

	END

GO	

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [DBA].[p_Cleanup_Frequent_Job_History]

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
					[sJOB].Active = 1 --Make sure that the job is actually active
					AND [sSCH].[schedule_uid] IS NOT NULL --Job is scheduled
					AND [SShed].[freq_subday_type] = 4 --Jobs that run every x minutes
					AND [SShed].[freq_subday_interval] < 60 --Jobs that run less than every 60 minutes

			COMMIT TRANSACTION t1

		END TRY
		BEGIN CATCH 
		
		Print 'Something has gone wrong here'

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

				--Store the history of the data we are going to remove in a table that isn't MSDB
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
		
				--Remove the data from the MSDB jobhistory table, we don't want any of this data keeping so we won't specify a date
				EXEC msdb..sp_purge_jobhistory @job_name = @JobName

			COMMIT TRANSACTION t2

		END TRY
		BEGIN CATCH

		Print 'Something has gone wrong purging the data...rolling back'

		ROLLBACK TRANSACTION t2

		END CATCH

		--Increment that counter and loop if we don't meet the MAX ID condition
		SET @Counter = @Counter +1

	END

	--We are done, drop the temp table
	DROP TABLE #Results

END




