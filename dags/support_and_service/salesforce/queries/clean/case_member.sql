SELECT
    Id AS id_case_member,
    OwnerId AS id_owner,
    Case__c AS id_case,
    Account__c AS id_account,
    CAST(ExternalId__c AS INT) AS id_external,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    Name AS case_member_name,
    Type__c AS case_member_type,
    CAST(IsDeleted AS BOOLEAN) AS is_deleted,
    CAST(SystemModstamp AS TIMESTAMP) AS ts_system_mod,
    CAST(LastActivityDate AS DATE) AS dt_last_activity,
    CAST(CreatedDate AS TIMESTAMP) AS ts_created,
    CAST(LastModifiedDate AS TIMESTAMP) AS ts_last_modified,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    datalake_salesforce_raw.case_member
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
