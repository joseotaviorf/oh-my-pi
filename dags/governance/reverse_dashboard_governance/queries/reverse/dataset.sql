SELECT
    ARRAY('datahub') AS vendor,
    CAST(id AS STRING) AS id_dataset,
    dataset_type,
    platform,
    if(dataset_type = 'virtual', 'virtual', schema) AS schema_name,
    table_name,
    if(dataset_type = 'virtual', company_line, 'physical') AS dataset_path,
    COALESCE(description,"") AS description,
    sql_code AS query,
    from_json(to_json(columns, map('ignoreNullFields','false')), 'array<map<string,string>>') AS columns,
    from_json(to_json(metrics, map('ignoreNullFields','false')), 'array<map<string,string>>') AS metrics,
    tags,
    business_owners,
    technical_owner AS created_by,
    last_owner AS changed_by,
    certified_by,
    date_format(ts_created, 'yyyy-MM-dd hh:mm:ss') AS created_on,
    date_format(ts_changed, 'yyyy-MM-dd hh:mm:ss') AS changed_on,
    company_line AS domain
FROM
    datalake_superset.tables
WHERE
    DATE_DIFF(DAY, ts_changed, CURRENT_TIMESTAMP) = 1
