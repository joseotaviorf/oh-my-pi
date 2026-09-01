SELECT
    Id AS id,
    Cuenta__c AS id_account,
    OwnerId AS id_owner,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    Id_grupo_economico__c AS external_economic_group_id,
    Name AS economic_group_name,
    Envio_email_OS__c AS send_service_order_email_name,
    CurrencyIsoCode AS currency_iso_code,
    IsDeleted AS is_deleted,
    LastActivityDate AS dt_last_activity,
    CreatedDate AS ts_created,
    LastModifiedDate AS ts_last_modified,
    SystemModstamp AS ts_system_mod,
    LastViewedDate AS ts_last_viewed,
    LastReferencedDate AS ts_last_referenced,
    CAST(LastModifiedDate AS DATE) AS dt_updated,
    YEAR(LastModifiedDate) AS year,
    MONTH(LastModifiedDate) AS month,
    DAY(LastModifiedDate) AS day
FROM
    datalake_salesforce_classifieds_raw.grupo_economico__c
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
