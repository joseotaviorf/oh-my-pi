SELECT DISTINCT
    COALESCE(id_inspector, -1) AS sk_inspector,
    IF(inspector_name = '', NULL, inspector_name) AS inspector_name,
    IF(insperctor_email = '', NULL, insperctor_email) AS inspector_email,
    IF(inspector_corporate_name = '', NULL, inspector_corporate_name) AS inspector_corporate_name,
    IF(beneficiary_name = '', NULL, beneficiary_name) AS beneficiary_name,
    IF(employee_contract_type = '', NULL, employee_contract_type) AS employee_contract_type,
    IF(company = '', NULL, company) AS company,
    IF(status = '', NULL, status) AS status,
    IF(operating_city = '', NULL, operating_city) AS operating_city,
    IF(operating_regions = '', NULL, operating_regions) AS operating_regions,
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
    datalake_gsheets_clean.inspectors_control