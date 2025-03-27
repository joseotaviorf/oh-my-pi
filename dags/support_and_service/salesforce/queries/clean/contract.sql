SELECT
    Id AS id_contract,
    OwnerId AS id_owner,
    CAST(ExternalId__c AS INT) AS id_external,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    Name AS contract_name,
    ContractTerm__c AS contract_term,
    CAST(IsDeleted AS BOOLEAN) AS is_deleted,
    CAST(SystemModstamp AS TIMESTAMP) AS ts_system_mod,
    CAST(StartDate__c AS TIMESTAMP) AS ts_start,
    CAST(LastActivityDate AS TIMESTAMP) AS ts_last_activity,
    CAST(LastViewedDate AS TIMESTAMP) AS ts_last_viewed,
    CAST(LastReferencedDate AS TIMESTAMP) AS ts_last_referenced,
    CAST(CreatedDate AS TIMESTAMP) AS ts_created,
    CAST(LastModifiedDate AS TIMESTAMP) AS ts_last_modified,
    year,
    month,
    day
FROM
    datalake_salesforce_raw.contract
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
