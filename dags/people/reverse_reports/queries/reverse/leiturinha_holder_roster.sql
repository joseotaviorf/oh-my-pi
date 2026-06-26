SELECT
    es.assignment_number AS id_colaborador,
    bu.consolidated_business_unit_name AS empresa,
    es.name AS nome,
    bu.cnpj AS cnpj,
    LOWER(es.work_email) AS email,
    es.address_zip_code AS residencia_cep,
    es.address_street AS residencia_endereco,
    es.address_number AS residencia_numero,
    es.address_complement AS residencia_complemento,
    es.address_district AS residencia_bairro,
    es.address_state AS residencia_uf,
    es.address_city AS residencia_cidade,
    CAST(es.ts_load AS DATE) AS dt_last_update,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.sk_business_unit
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND es.is_active = TRUE
    AND bu.consolidated_business_unit_name IN (
        'QuintoAndar SP',
        'QuintoAndar SC',
        'QuintoAndar MG'
    )
