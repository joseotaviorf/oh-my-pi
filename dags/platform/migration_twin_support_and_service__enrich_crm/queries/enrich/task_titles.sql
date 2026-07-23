SELECT
    GET_JSON_OBJECT(REPLACE(id,'$',''),'$.oid') AS id,
    workgroup_ids,
    description,
    title,
    slug
FROM 
    datalake_crm_clean.task_titles