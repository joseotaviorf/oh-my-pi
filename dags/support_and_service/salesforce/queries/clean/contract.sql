SELECT
    Id AS id_contract,
    OwnerId AS id_owner,
    ExternalId__c AS id_external,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    Name AS contract_name,
    ContractTerm__c AS contract_term,
    IsDeleted AS is_deleted,
    SystemModstamp AS system_mod_stamp,
    StartDate__c AS ts_start,
    LastActivityDate AS ts_last_activity,
    LastViewedDate AS ts_last_viewed,
    LastReferencedDate AS ts_last_referenced,
    CreatedDate AS ts_created,
    LastModifiedDate AS ts_last_modified,
    year,
    month,
    day
FROM
    datalake_salesforce_raw.contract
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
