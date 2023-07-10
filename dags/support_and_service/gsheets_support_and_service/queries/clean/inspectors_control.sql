SELECT
    CAST(sk_inspector AS BIGINT) AS id_inspector,
    IF(agenda_type = '', NULL, agenda_type) AS agenda_type,
    IF(beneficiary_document = '', NULL, beneficiary_document) AS beneficiary_document,
    IF(beneficiary_name = '', NULL, beneficiary_name) AS beneficiary_name,
    IF(company = '', NULL, company) AS company,
    IF(employee_contract_type = '', NULL, employee_contract_type) AS employee_contract_type,
    IF(inspector_address = '', NULL, inspector_address) AS inspector_address,
    IF(inspector_cnpj = '', NULL, inspector_cnpj) AS inspector_cnpj,
    IF(inspector_corporate_name = '', NULL, inspector_corporate_name) AS inspector_corporate_name,
    IF(inspector_cpf = '', NULL, inspector_cpf) AS inspector_cpf,
    IF(inspector_name = '', NULL, inspector_name) AS inspector_name,
    IF(inspector_phone = '', NULL, inspector_phone) AS inspector_phone,
    IF(inspector_rg = '', NULL, inspector_rg) AS inspector_rg,
    IF(inspector_secondary_phone = '', NULL, inspector_secondary_phone) AS inspector_secondary_phone,
    IF(insperctor_email = '', NULL, insperctor_email) AS inspector_email,
    IF(main_operating_region = '', NULL, main_operating_region) AS main_operating_region,
    IF(operating_city = '', NULL, operating_city) AS operating_city,
    IF(operating_regions = '', NULL, operating_regions) AS operating_regions,
    IF(registry_type = '', NULL, registry_type) AS registry_type,
    IF(salary = '', NULL, salary) AS salary,
    IF(status = '', NULL, status) AS status,
    IF(transportation_type = '', NULL, transportation_type) AS transportation_type,
    CASE
        WHEN CHAR_LENGTH(dt_start) = 8 THEN to_date(dt_start, 'M/d/yyyy')
        WHEN CHAR_LENGTH(dt_start) = 9
            AND CHAR_LENGTH(SPLIT(dt_start, '/')[0]) = 1
            THEN to_date(dt_start, 'M/dd/yyyy')
        WHEN CHAR_LENGTH(dt_start) = 9
            AND CHAR_LENGTH(SPLIT(dt_start, '/')[0]) = 2
            THEN to_date(dt_start, 'MM/d/yyyy')
        WHEN CHAR_LENGTH(dt_start) = 10 THEN to_date(dt_start, 'MM/dd/yyyy')
    END AS dt_start,
    CASE
        WHEN CHAR_LENGTH(dt_end) = 8 THEN to_date(dt_end, 'M/d/yyyy')
        WHEN CHAR_LENGTH(dt_end) = 9
            AND CHAR_LENGTH(SPLIT(dt_end, '/')[0]) = 1
            THEN to_date(dt_end, 'M/dd/yyyy')
        WHEN CHAR_LENGTH(dt_end) = 9
            AND CHAR_LENGTH(SPLIT(dt_end, '/')[0]) = 2
            THEN to_date(dt_end, 'MM/d/yyyy')
        WHEN CHAR_LENGTH(dt_end) = 10 THEN to_date(dt_end, 'MM/dd/yyyy')
    END AS dt_end,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.inspectors_control
