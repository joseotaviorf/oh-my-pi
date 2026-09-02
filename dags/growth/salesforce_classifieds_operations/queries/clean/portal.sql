SELECT
    Id AS id,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    OwnerId AS id_owner,
    CurrencyIsoCode AS currency_iso_code,
    Name AS name,
    Organizaciones_con_ID_Empresa_compartido__c AS organizations_id_company_shared,
    Portal__c AS portal,
    Sitio__c AS site,
    Vertical__c AS vertical,
    Permite_compartir_id_site__c AS allows_share_id_site,
    IsDeleted AS is_deleted,
    LastActivityDate AS dt_last_activity,
    CreatedDate AS ts_created,
    LastModifiedDate AS ts_last_modified,
    LastReferencedDate AS ts_last_referenced,
    LastViewedDate AS ts_last_viewed,
    SystemModstamp AS ts_system_mod,
    CAST(LastModifiedDate AS DATE) AS dt_updated,
    YEAR(LastModifiedDate) AS year,
    MONTH(LastModifiedDate) AS month,
    DAY(LastModifiedDate) AS day
FROM
    datalake_salesforce_classifieds_raw.portal__c
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
