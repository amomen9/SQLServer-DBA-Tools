-- =============================================
-- Author:              "a-momen"
-- Contact & Report:    "amomen@gmail.com"
-- Update date:         "2022-08-31"
-- Description:         "last execution status of every job"
-- License:             "Please refer to the license file"
-- =============================================




SELECT 
	*
from
(
	SELECT 
		name, (SELECT run_status FROM msdb..sysjobhistory WHERE instance_id = MAX(h.instance_id)) run_status
	FROM msdb..sysjobs j JOIN msdb..sysjobhistory h
	ON h.job_id = j.job_id
	--WHERE h.run_status = 0
	GROUP BY j.name
) dt
WHERE dt.run_status = 0

