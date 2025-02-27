SELECT
    Id AS id_checklist,
    OwnerId AS id_owner,
    Termination__c AS id_termination,
    ExternalId__c AS id_external,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    Name AS name,
    Type__c AS type,
    Done__c AS is_done,
    Active__c AS is_active,
    IsDeleted AS is_deleted,
    CreatedDate AS ts_created,
    LastModifiedDate AS ts_last_modified,
    SystemModstamp AS system_mod_stamp,
    LastActivityDate AS ts_last_activity,
    LastViewedDate AS ts_last_viewed,
    LastReferencedDate AS ts_last_referenced,
    year,
    month,
    day
FROM
    datalake_salesforce_raw.checklist
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
