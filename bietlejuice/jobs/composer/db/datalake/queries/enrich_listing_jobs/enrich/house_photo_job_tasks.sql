SELECT
    COALESCE(house_via_job.id, house_via_task.id) AS id_house,
    MAX((task_status.type = 'AgendarJobDeFotografo')) AS has_job_photo,
    MAX((task_status.type = 'FupFoto')) AS has_fup_photo
FROM datalake_crm_tasks.task_status
LEFT JOIN
    datalake_ebdb_listing_jobs.photo_job AS pj
    ON task_status.id_origin = pj.id
LEFT JOIN
    datalake_ebdb_listing.house AS house_via_job
    ON house_via_job.id = pj.id_house
LEFT JOIN
    datalake_ebdb_listing.house AS house_via_task
    ON house_via_task.id = task_status.id_origin
WHERE
    task_status.type IN ('FupFoto', 'AgendarJobDeFotografo')
    AND COALESCE(house_via_job.id, house_via_task.id) IS NOT NULL
GROUP BY 1