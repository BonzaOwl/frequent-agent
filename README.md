# Frequent Agent

Frequent Agent is a SQL Server Stored Procedure that will check for frequently running SQL Agent Jobs move their Agent History from MSDB to the JobHistory_Archive table which is created inside the DBA_Tasks database and then purge the data from the MSDB database. 

# Requirements

* Database with the name DBA_Tasks
* Schema in the above mentioned database called DBA