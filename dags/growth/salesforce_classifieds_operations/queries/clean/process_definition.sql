SELECT
    Id AS id,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    Description AS description,
    DeveloperName AS developer_name,
    LockType AS lock_type_name,
    Name AS name,
    State AS state_name,
    TableEnumOrId AS target_object_name,
    Type AS type_name,
    CreatedDate AS ts_created,
    LastModifiedDate AS ts_last_modified,
    SystemModstamp AS ts_system_mod,
    CAST(LastModifiedDate AS DATE) AS dt_updated,
    YEAR(LastModifiedDate) AS year,
    MONTH(LastModifiedDate) AS month,
    DAY(LastModifiedDate) AS day
FROM
    datalake_salesforce_classifieds_raw.processdefinition
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
