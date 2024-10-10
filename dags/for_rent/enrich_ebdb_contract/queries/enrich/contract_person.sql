WITH person_cpf AS (
    SELECT
        id,
        cpf,
        cpf RLIKE '^([0-9]{{3}})(\\.)?([0-9]{{3}})(\\.)?([0-9]{{3}})(\.)?([0-9]{{2}})$' AS is_cpf_format,
        cpf RLIKE '^([0-9]{{2}})(\\.)?([0-9]{{3}})(\\.)?([0-9]{{3}})(\/)?([0-9]{{4}})(\.)?([0-9]{{2}})$' AS is_cnpj_format
    FROM
        datalake_ebdb_clean.contract_person
    WHERE
        cpf IS NOT NULL
),
validation_string AS (
    SELECT
        id,
        cpf,
        is_cpf_format,
        is_cnpj_format,
        CASE
            WHEN is_cpf_format = TRUE THEN SUBSTRING(CAST(REGEXP_REPLACE(cpf, '\\D+', '') AS STRING), 1, 9)
            when is_cnpj_format = TRUE THEN SUBSTRING(CAST(REGEXP_REPLACE(cpf, '\\D+', '') AS STRING), 1, 12)
        END AS first_digits
    FROM
        person_cpf
    WHERE
        is_cpf_format = TRUE
        OR is_cnpj_format = TRUE
),
unnested_digits AS (
    SELECT
        id,
        cpf,
        is_cpf_format,
        is_cnpj_format,
        first_digits,
        'cpf' AS doc_type,
        CAST(SUBSTR(first_digits, 1, 1) AS INTEGER) AS col1,
        CAST(SUBSTR(first_digits, 2, 1) AS INTEGER) AS col2,
        CAST(SUBSTR(first_digits, 3, 1) AS INTEGER) AS col3,
        CAST(SUBSTR(first_digits, 4, 1) AS INTEGER) AS col4,
        CAST(SUBSTR(first_digits, 5, 1) AS INTEGER) AS col5,
        CAST(SUBSTR(first_digits, 6, 1) AS INTEGER) AS col6,
        CAST(SUBSTR(first_digits, 7, 1) AS INTEGER) AS col7,
        CAST(SUBSTR(first_digits, 8, 1) AS INTEGER) AS col8,
        CAST(SUBSTR(first_digits, 9, 1) AS INTEGER) AS col9,
        CAST(0 AS INTEGER) AS col10,
        CAST(0 AS INTEGER) AS col11,
        CAST(0 AS INTEGER) AS col12
    FROM
        validation_string
    WHERE
        is_cpf_format = TRUE
        AND LENGTH(first_digits) = 9
    UNION ALL
    SELECT
        id,
        cpf,
        is_cpf_format,
        is_cnpj_format,
        first_digits,
        'cnpj' AS doc_type,
        CAST(SUBSTR(first_digits, 1, 1) AS INTEGER),
        CAST(SUBSTR(first_digits, 2, 1) AS INTEGER),
        CAST(SUBSTR(first_digits, 3, 1) AS INTEGER),
        CAST(SUBSTR(first_digits, 4, 1) AS INTEGER),
        CAST(SUBSTR(first_digits, 5, 1) AS INTEGER),
        CAST(SUBSTR(first_digits, 6, 1) AS INTEGER),
        CAST(SUBSTR(first_digits, 7, 1) AS INTEGER),
        CAST(SUBSTR(first_digits, 8, 1) AS INTEGER),
        CAST(SUBSTR(first_digits, 9, 1) AS INTEGER),
        CAST(SUBSTR(first_digits, 10, 1) AS INTEGER),
        CAST(SUBSTR(first_digits, 11, 1) AS INTEGER),
        CAST(SUBSTR(first_digits, 12, 1) AS INTEGER)
    FROM
        validation_string
    WHERE
        is_cnpj_format = TRUE
        AND LENGTH(first_digits) = 12
),
first_linear_combination AS (
    SELECT
        id,
        doc_type,
        CASE
            WHEN doc_type = 'cpf' THEN (10 * col1 + 9 * col2 + 8 * col3 + 7 * col4 + 6 * col5 + 5 * col6 + 4 * col7 + 3 * col8 + 2 * col9)
            WHEN doc_type = 'cnpj' THEN (5 * col1 + 4 * col2 + 3 * col3 + 2 * col4 + 9 * col5 + 8 * col6 + 7 * col7 + 6 * col8 + 5 * col9 + 4 * col10 + 3 * col11 + 2 * col12)
        END AS aux1
    FROM
        unnested_digits
),
calculate_first_digit AS (
    SELECT
        id,
        CAST(
            CASE
                WHEN (aux1 % 11) < 2 THEN 0
                ELSE 11 - (aux1 % 11)
            END AS INTEGER
        ) AS dig1
    FROM
        first_linear_combination
),
second_linear_combination AS (
    SELECT
        ud.id,
        ud.doc_type,
        CASE
            WHEN doc_type = 'cpf' THEN (11 * col1 + 10 * col2 + 9 * col3 + 8 * col4 + 7 * col5 + 6 * col6 + 5 * col7 + 4 * col8 + 3 * col9 + 2 * dig1)
            WHEN doc_type = 'cnpj' THEN (6 * col1 + 5 * col2 + 4 * col3 + 3 * col4 + 2 * col5 + 9 * col6 + 8 * col7 + 7 * col8 + 6 * col9 + 5 * col10 + 4 * col11 + 3 * col12 + 2 * dig1)
        END AS aux2
    FROM
        unnested_digits AS ud
        INNER JOIN
            calculate_first_digit AS cfd
                ON ud.id = cfd.id
),
calculate_second_digit AS (
    SELECT
        id,
        CASE
            WHEN (aux2 % 11) < 2 THEN 0
            ELSE 11 - (aux2 % 11)
        END AS dig2
    FROM
        second_linear_combination
),
validate_cpfs AS (
    SELECT
        ud.id,
        ud.cpf,
        ud.doc_type,
        ud.is_cpf_format,
        ud.is_cnpj_format,
        ud.first_digits,
        REGEXP_REPLACE(ud.cpf, '\\D+', '') AS cpf_digits,
        CONCAT(
            ud.first_digits,
            CONCAT(
                CAST(cfd.dig1 AS STRING), CAST(csd.dig2 AS STRING)
            )
        ) AS valid_cpf,
        REGEXP_REPLACE(ud.cpf, '\\D+', '') RLIKE '\b(\d)\1+\b' AS is_repeated_numbers
    FROM
        unnested_digits AS ud
        INNER JOIN
            calculate_first_digit AS cfd
                ON cfd.id = ud.id
        INNER JOIN
            calculate_second_digit csd
                ON csd.id = ud.id
),
cpf_validator AS (
    SELECT
        id,
        cpf,
        doc_type,
        is_cpf_format,
        is_cnpj_format,
        cpf_digits,
        valid_cpf
    FROM
        validate_cpfs
    WHERE
        is_repeated_numbers = FALSE
),
contract_users AS (
    SELECT
        c.id AS id_contract,
        c.id_user AS id_user_tenant,
        h.id_user AS id_user_owner
    FROM
        datalake_ebdb_clean.contract AS c
        INNER JOIN datalake_ebdb_clean.house AS h
            ON h.id = c.id_house
),
user_agg_contracts AS (
    SELECT
        id_user,
        MAX(id) AS id_max,
        MIN(id_contract) AS id_first_contract,
        MAX(id_contract) AS id_last_contract
    FROM
        datalake_ebdb_clean.contract_person
    GROUP BY 1
),
cpf_agg_contracts AS (
    SELECT
        cpf,
        MAX(id) AS id_max,
        MIN(id_contract) AS id_first_contract,
        MAX(id_contract) AS id_last_contract
    FROM
        datalake_ebdb_clean.contract_person
    GROUP BY 1
),
get_previous_user AS (
    SELECT DISTINCT
        cp.id_contract,
        cp.id AS id_contract_person,
        cp.id_user AS id_user_contract_person,
        LAG(cp.id_user) OVER (PARTITION BY cp.id_contract, cp.type, cp.will_live ORDER BY FROM_UNIXTIME(ure.ts_revision/1000) ASC) AS id_previous_user_contract_person,
        cp.mod_id_user,
        FROM_UNIXTIME(ure.ts_revision/1000) AS ts_revision
    FROM
        datalake_ebdb_clean.contract_person_aud AS cp
    LEFT JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON ure.id = cp.REV
    WHERE
        cp.id_user IS NOT NULL
),
ownership_swap AS (
    SELECT
        id_contract,
        id_contract_person,
        id_user_contract_person,
        id_previous_user_contract_person,
        ts_revision
    FROM
        get_previous_user
    WHERE
        mod_id_user
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_contract, id_user_contract_person ORDER BY ts_revision DESC) = 1
)
SELECT
    cp.id AS id_contract_person,
    cp.id_user AS id_user_contract_person,
    os.id_previous_user_contract_person,
    cp.id_contract,
    u.id AS id_user,
    COALESCE(ch.country_code, 'Undefined') AS country_code,
    cp.name AS full_name,
    cp.phone_number,
    cp.email,
    UPPER(cv.doc_type) AS personal_document_type,
    cp.cpf AS personal_document,
    REPLACE(LOWER(cp.gender), 'o', 'e') AS gender,
    CASE
        WHEN cp.marital_status = 'Amasiado' THEN 'common-law marriage'
	    WHEN cp.marital_status = 'Casado' THEN 'married'
	    WHEN cp.marital_status = 'Desquitado' THEN 'separated'
	    WHEN cp.marital_status = 'Divorciado' THEN 'divorced'
	    WHEN cp.marital_status = 'Separado' THEN 'separated'
	    WHEN cp.marital_status = 'Solteiro' THEN 'single'
	    WHEN cp.marital_status = 'Viuvo' THEN 'widower'
    END AS marital_status,
    cp.state_id AS state_code,
    CASE
        WHEN cp.type = 'Fiador' THEN 'sponsor'
        WHEN cp.type = 'Inquilino' THEN 'tenant'
        WHEN cp.type = 'Morador' THEN 'dweller'
        WHEN cp.type = 'Partner' THEN 'partner'
        WHEN cp.type = 'Proprietario' THEN 'landlord'
    END AS contract_role,
    cp.will_live AS is_living,
    (cv.is_cpf_format = TRUE AND cv.valid_cpf = CAST(REGEXP_REPLACE(cp.cpf, '\\D+', '') AS STRING)) AS is_valid_cpf,
    (cv.is_cnpj_format = TRUE AND cv.valid_cpf = CAST(REGEXP_REPLACE(cp.cpf, '\\D+', '') AS STRING)) AS is_valid_cnpj,
    u.id IS NOT NULL AS is_user,
    COALESCE(
        (cp.type = 'Inquilino' AND cp.id_user = cusr.id_user_tenant)
        OR (cp.type = 'Proprietario' AND cp.id_user = cusr.id_user_owner),
    FALSE) AS is_contract_user,
    (cp.id_contract = COALESCE(uag.id_first_contract, cag.id_first_contract)) AS is_first_contract,
    (cp.id_contract = COALESCE(uag.id_last_contract, cag.id_last_contract)) AS is_last_contract,
    cp.dt_birth,
    cp.ts_created,
    cp.ts_updated
FROM
    datalake_ebdb_clean.contract_person AS cp
LEFT JOIN
    ownership_swap AS os
        ON os.id_contract = cp.id_contract
        AND os.id_contract_person = cp.id
        AND os.id_user_contract_person = cp.id_user
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON u.id = cp.id_user
        AND cp.id_user IS NOT NULL
LEFT JOIN
    datalake_ebdb_country.user AS ch
        ON ch.id_user = cp.id_user
        AND cp.id_user IS NOT NULL
LEFT JOIN
    contract_users AS cusr
        ON cusr.id_contract = cp.id_contract
LEFT JOIN
    user_agg_contracts AS uag
        ON uag.id_user = cp.id_user
        AND uag.id_max = cp.id -- prevent duplicated contract and contract person in various ids
LEFT JOIN
    cpf_agg_contracts AS cag
        ON cag.cpf = cp.cpf
        AND cag.id_max = cp.id -- prevent duplicated contract and contract person in various ids
LEFT JOIN
    cpf_validator AS cv
        ON cp.id = cv.id
