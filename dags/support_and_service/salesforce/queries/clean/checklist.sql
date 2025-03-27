SELECT
    Id AS id_checklist,
    OwnerId AS id_owner,
    Termination__c AS id_termination,
    CAST(ExternalId__c AS INT) AS id_external,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    Name AS name,
    Type__c AS type,
    CAST(Done__c AS BOOLEAN) AS is_done,
    CAST(Active__c AS BOOLEAN) AS is_active,
    CAST(IsDeleted AS BOOLEAN) AS is_deleted,
    CAST(CreatedDate AS TIMESTAMP) AS ts_created,
    CAST(LastModifiedDate AS TIMESTAMP) AS ts_last_modified,
    CAST(SystemModstamp AS TIMESTAMP) AS ts_system_mod,
    CAST(LastActivityDate AS TIMESTAMP) AS ts_last_activity,
    CAST(LastViewedDate AS TIMESTAMP) AS ts_last_viewed,
    CAST(LastReferencedDate AS TIMESTAMP) AS ts_last_referenced,
    year,
    month,
    day
FROM
    datalake_salesforce_raw.checklist
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
