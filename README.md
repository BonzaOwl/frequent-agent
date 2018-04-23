# Frequent Agent

Frequent Agent is a SQL Server Stored Procedure that will check for frequently running SQL Agent Jobs move their Agent History from MSDB to the JobHistory_Archive table which is created inside the DBA_Tasks database and then purges the data from the MSDB database. 

In our enviroment we found that we had some jobs that were running daily every 30 seconds or so which was bulking out the sysjobhistory table in MSDB and when the [default purge settings](https://blog.sqlauthority.com/2014/02/27/sql-server-dude-where-is-the-sql-agent-job-history-notes-from-the-field-017/) were enabled this was causing other job history to be cleared out, so investigating why a backup had failed for example was becoming problomatic.

# Requirements

* Ability to create stored procedures
* Ability to create tables
* Ability to drop stored procedures
* A database with the name DBA_Tasks
* Schema in the above mentioned database called DBA
* SQL Server 2008+

When running this script if the an object exists in the DBA_Tasks database under the schema DBA with the name p_Cleanup_Frequent_Job_History it will be dropped and this stored procedure created in it's place.

#Further Reading 

This stored procedure makes use of [purge_jobhistory](https://docs.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-purge-jobhistory-transact-sql?view=sql-server-2017) we only specify the job name, no date range is specified for the high frquency jobs as in our instance we didn't want to keep any of this data in MSDB at all.