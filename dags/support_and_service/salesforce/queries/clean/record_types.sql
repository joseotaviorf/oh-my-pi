SELECT
    Id AS id_record_type,
    BusinessProcessId AS id_business_process,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    Name AS record_type_name,
    DeveloperName AS developer_name,
    NamespacePrefix AS namespace_prefix,
    Description AS record_type_description,
    SobjectType AS sobject_type,
    CAST(IsActive AS BOOLEAN) AS is_active,
    CAST(IsPersonType AS BOOLEAN) AS is_person_type,
    CAST(SystemModstamp AS TIMESTAMP) AS ts_system_mod,
    CAST(CreatedDate AS TIMESTAMP) AS ts_created,
    CAST(LastModifiedDate AS TIMESTAMP) AS ts_last_modified,
    year,
    month,
    day
FROM
    datalake_salesforce_raw.record_types
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
