SELECT
    Id AS id,
    Pais__c AS id_country,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    ID_Lista_de_Precios_SAP__c AS external_sap_price_list_id,
    Name AS pricebook_name,
    Description AS description,
    CurrencyIsoCode AS currency_iso_code,
    Organizacion_de_venta__c AS sales_organization_name,
    IsActive AS is_active,
    IsDeleted AS is_deleted,
    IsStandard AS is_standard,
    IsArchived AS is_archived,
    Es_regional__c AS is_regional,
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
    datalake_salesforce_classifieds_raw.pricebook2
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
