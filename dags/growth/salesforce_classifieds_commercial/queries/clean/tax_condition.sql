SELECT
    Id AS id,
    OwnerId AS id_owner,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    Id_Clase__c AS id_class,
    Pais__c AS id_country,
    Name AS tax_condition_name,
    Tipo_de_documento__c AS document_type,
    CurrencyIsoCode AS currency_iso_code,
    IsDeleted AS is_deleted,
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
    datalake_salesforce_classifieds_raw.condicion_fiscal__c
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
