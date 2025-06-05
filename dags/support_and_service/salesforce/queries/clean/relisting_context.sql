SELECT
    Id AS id_relisting_context,
    OwnerId AS id_owner,
    HouseId__c AS id_house,
    Contract__c AS id_contract,
    Termination__c AS id_termination,
    CAST(ExternalId__c AS INT) AS id_external,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    Name AS name,
    ListingStatus__c AS listing_status,
    CAST(IsDeleted AS BOOLEAN) AS is_deleted,
    CAST(IsEarlyRelistingActive__c AS BOOLEAN) AS is_early_relisting_active,
    CAST(IsRelistingEligible__c AS BOOLEAN) AS is_relisting_eligible,
    CAST(CreatedDate AS TIMESTAMP) AS ts_created,
    CAST(LastModifiedDate AS TIMESTAMP) AS ts_last_modified,
    CAST(SystemModstamp AS TIMESTAMP) AS ts_system_mod,
    CAST(LastViewedDate AS TIMESTAMP) AS ts_last_viewed,
    CAST(LastReferencedDate AS TIMESTAMP) AS ts_last_referenced,
    year,
    month,
    day
FROM
    datalake_salesforce_raw.relisting_context
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
