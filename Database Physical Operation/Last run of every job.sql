
SELECT * FROM 
(
	SELECT 
		ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY run_date DESC, run_time DESC) row,
		(SELECT name FROM msdb..sysjobs WHERE job_id = h.job_id) JobName,
		STUFF(STUFF(h.run_date,5,0,'-'),8,0,'-')+' '+STUFF(STUFF(REPLICATE('0',6-LEN(h.run_time))+CONVERT(VARCHAR(6),h.run_time),3,0,':'),6,0,':') RunDate,
		h.run_status,
		CASE h.run_status WHEN 0 THEN 'Failed' WHEN 1 THEN 'Succeeded' WHEN 2 THEN 'Retry' WHEN 3 THEN 'Canceled' WHEN 4 THEN 'In Progress' END run_status_desc
	FROM msdb..sysjobhistory h
) dt
WHERE row < 3 AND dt.JobName LIKE 'cdc%capture'



--SELECT LEN(CONVERT(INT,1111))
--SELECT REPLICATE('0',0)