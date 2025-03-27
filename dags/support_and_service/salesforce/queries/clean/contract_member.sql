SELECT
    Id AS id_contract_member,
    OwnerId AS id_owner,
    Contract__c AS id_contract,
    Account__c AS id_account,
    CAST(ExternalId__c AS INT) AS id_external,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    Name AS contract_member_name,
    Type__c AS contract_member_type,
    CAST(IsDeleted AS BOOLEAN) AS is_deleted,
    CAST(SystemModstamp AS TIMESTAMP) AS ts_system_mod,
    CAST(CreatedDate AS TIMESTAMP) AS ts_created,
    CAST(LastModifiedDate AS TIMESTAMP) AS ts_last_modified,
    year,
    month,
    day
FROM
    datalake_salesforce_raw.contract_member
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
