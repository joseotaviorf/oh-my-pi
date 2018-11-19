SELECT
    _id as id,
    cast(contactinfo as varchar) as contactinfo
FROM
    datalake_raw.task_references
WHERE createddate IS NOT NULL