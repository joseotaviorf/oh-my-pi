SELECT
    ID_Empresa_Site__c AS id_lead,
    CreatedDate AS creation_date,
    OwnerId AS id_analyst,
     CASE
        WHEN Ha_respondido_el_contacto__c = 'Si' THEN TRUE
        WHEN Ha_respondido_el_contacto__c = 'No' THEN FALSE
        ELSE FALSE
    END AS is_contacted,
    CASE
        WHEN Calificado__c = 'Si' THEN TRUE
        WHEN Calificado__c = 'No' THEN FALSE
        WHEN Calificado__c = 'No Aplica' THEN FALSE
        ELSE FALSE
    END AS is_qualified,
    Phone AS phone,
    Direccion__c AS address,
    Canal__c AS channel,
    Id AS id_salesforce,
    Status AS status,
    LastName AS owner_name,
    RecordTypeId AS record_type_id,
    dt_updated,
    year,
    month,
    day
FROM
    datalake_salesforce_growth_raw.lead
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')