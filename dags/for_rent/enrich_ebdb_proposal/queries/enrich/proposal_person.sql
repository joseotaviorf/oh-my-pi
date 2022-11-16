WITH person_cpf AS (
	SELECT
		id,
		cpf,
		cpf RLIKE '^([0-9]{{3}})(\\.)?([0-9]{{3}})(\\.)?([0-9]{{3}})(.)?([0-9]{{2}})$' AS is_cpf_format,
		cpf RLIKE '^([0-9]{{2}})?(\\.)?([0-9]{{3}})(\\.)?([0-9]{{3}})(\\/)([0-9]{{4}})(.)?([0-9]{{2}})$' AS is_cnpj_format
	FROM 
        datalake_ebdb_clean.proponent_proposal
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
            WHEN is_cpf_format = true THEN SUBSTRING(CAST(REGEXP_REPLACE(cpf, '\\D+', '') AS STRING),1,9)
			WHEN is_cnpj_format = true THEN SUBSTRING(CAST(REGEXP_REPLACE(cpf, '\\D+', '') AS STRING),1,12)
        END AS first_digits
	FROM 
        person_cpf
	WHERE 
        is_cpf_format = true
		OR is_cnpj_format = true
),
unnested_digits AS (
	SELECT
		id,
		cpf,
		'cpf' AS doc_type,
        first_digits,
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
		CAST(0 AS INTEGER) AS col12,
        is_cpf_format,
		is_cnpj_format
	FROM 
        validation_string
	WHERE 
        is_cpf_format = true
		AND LENGTH(first_digits) = 9
	UNION ALL
	SELECT
		id,
		cpf,
		'cnpj' AS doc_type,
        first_digits,
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
		CAST(SUBSTR(first_digits, 12, 1) AS INTEGER),
        is_cpf_format,
		is_cnpj_format
	FROM 
        validation_string
	WHERE 
        is_cnpj_format = true
		AND LENGTH(first_digits) = 12
),
first_linear_combination AS (
    SELECT
        id,
        doc_type,
        CASE 
            WHEN doc_type = 'cpf' THEN (10 * col1 + 9 * col2 + 8 * col3 + 7 * col4 + 6 * col5 + 5 * col6 + 4 * col7 + 3 * col8 + 2 * col9)
            WHEN doc_type = 'cnpj' THEN (5 * col1 + 4 * col2 + 3 * col3 + 2 * col4 + 9 * col5 + 8 * col6 + 7 * col7 + 6 * col8 + 5 * col9 + 4 * col10 + 3 * col11 + 2 * col12)
        END aux1
    FROM 
        unnested_digits
),
calculate_first_digit AS (
	SELECT
		id,
		CAST(CASE 
                WHEN (aux1 % 11) < 2 THEN 0 
                ELSE 11 - (aux1 % 11) 
            END AS INTEGER) AS dig1
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
        unnested_digits ud
	INNER JOIN 
        calculate_first_digit cfd
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
		ud.is_cpf_format,
		ud.is_cnpj_format,
		ud.first_digits,
		REGEXP_REPLACE(ud.cpf, '\\D+', '') AS cpf_digits,
		CONCAT(ud.first_digits,CONCAT(CAST(cfd.dig1 AS STRING),CAST(csd.dig2 AS STRING))) AS valid_cpf,
		REGEXP_REPLACE(ud.cpf, '\\D+', '') RLIKE '\\b(\\d)\\1+\\b' AS is_repeated_numbers
	FROM 
        unnested_digits ud
	INNER JOIN 
        calculate_first_digit cfd
		    ON cfd.id = ud.id
	INNER JOIN 
        calculate_second_digit csd
		    ON csd.id = ud.id
),
cpf_validator AS (
	SELECT
		id,
		cpf,
		cpf_digits,
		valid_cpf,
        is_cpf_format,
		is_cnpj_format
	FROM 
        validate_cpfs
	WHERE 
        is_repeated_numbers = false
),
cpf_agg_proposals AS (
	SELECT
		cpf,
		MIN(id_proposal) AS id_first_proposal,
		MAX(id_proposal) AS id_last_proposal
	FROM 
        datalake_ebdb_clean.proponent_proposal
	GROUP BY 1
)
SELECT
	pp.id AS id_proposal_person,
	pp.cpf AS id_personal_document,
	pp.id_proposal AS id_proposal,
	COALESCE(u.country_code, 'Undefined') AS country_code,
    CASE 
        WHEN current_situation = 'Familiares' THEN 'family'
        WHEN current_situation = 'Alugado' THEN 'rented'
        WHEN current_situation = 'Proprio' THEN 'own'
        ELSE current_situation
    END AS current_house_situation,
    pp.email,
    CASE 
        WHEN emp_link = 'CLT' THEN 'CLT'
        WHEN emp_link = 'Empresario' THEN 'businessman'
        WHEN emp_link = 'FuncionarioPublico' THEN 'government employee'
        WHEN emp_link = 'ProfissionalLiberal' THEN 'liberal professional'
        WHEN emp_link = 'Autonomo' THEN 'self-employment'
        WHEN emp_link = 'EstudanteBolsista' THEN 'scholarship holder'
        WHEN emp_link = 'RendaAlugueis' THEN 'rental income'
        WHEN emp_link = 'DiretorEmpresa' THEN 'company director'
        ELSE emp_link 
    END AS employment_bond,
	CASE 
        WHEN pp.type = 'Proprietario' THEN 'landlord'
		WHEN pp.type = 'Inquilino' THEN 'tenant'
		WHEN pp.type = 'Fiador' THEN 'sponsor'
		ELSE pp.type
    END AS expected_contract_role,
    pp.name AS full_name,
    REPLACE(LOWER(pp.gender), 'o', 'e') AS gender,
    pp.marital_status,
    pp.cpf AS personal_document,
    CASE 
        WHEN pp.cpf RLIKE '([0-9]{{3}})(\\.)?([0-9]{{3}})(\\.)?([0-9]{{3}})(-)([0-9]{{2}})' THEN 'CPF'
        WHEN pp.cpf RLIKE '([0-9]{{2}})(\\.)?([0-9]{{3}})(\\.)?([0-9]{{3}})(\\/)([0-9]{{4}})(-)([0-9]{{2}})' THEN 'CNPJ' 
        ELSE NULL 
    END AS personal_document_type,
    pp.phone_number,
	CASE 
        WHEN pp.rental_motive = 'ProximidadeAOTrabalho' THEN 'work proximity'
		WHEN pp.rental_motive = 'ParaFamiliares' THEN 'for relatives'
		WHEN pp.rental_motive = 'RealocacaoEmpresa' THEN 'company realocation'
		WHEN pp.rental_motive = 'ReducaoCustos' THEN 'cost reduction'
		WHEN pp.rental_motive = 'Casamento' THEN 'marriage'
		WHEN pp.rental_motive = 'Separacao' THEN 'divorce'
		WHEN pp.rental_motive = 'ProximidadeAFamiliares' THEN 'family proximity'
		WHEN pp.rental_motive = 'Independencia' THEN 'independence'
		WHEN pp.rental_motive = 'VendaImovelProprio' THEN 'selling own house'
		WHEN pp.rental_motive = 'ProximidadeAEscola' THEN 'school proximity'
		WHEN pp.rental_motive = 'ParaTerceiros' THEN 'for third party'
		ELSE pp.rental_motive
    END AS rental_motive,
    pp.id_estado AS state_code,
    pp.number_of_dependents,
    COALESCE(pp.monthly_salary,0) + COALESCE(pp.additional_income,0) AS brl_total_income,
	pp.will_live AS is_going_to_live,
	(pp.id_proposal = cag.id_first_proposal) AS is_first_proposal,
	(pp.id_proposal = cag.id_last_proposal) AS is_last_proposal,
    (cv.is_cpf_format = true AND cv.valid_cpf = CAST(REGEXP_REPLACE(pp.cpf,'(\\D+)','') AS STRING)) AS is_valid_cpf,
	(cv.is_cnpj_format = true AND cv.valid_cpf = CAST(REGEXP_REPLACE(pp.cpf,('\\D+'),'') AS STRING)) AS is_valid_cnpj,
    has_contributed_to_current_house,
    pp.dt_birth,
    pp.ts_created,
    pp.ts_updated
FROM 
    datalake_ebdb_clean.proponent_proposal pp
LEFT JOIN 
    cpf_agg_proposals cag
	    ON cag.cpf = pp.cpf
LEFT JOIN 
    cpf_validator cv
	    ON cv.id = pp.id
LEFT JOIN
	datalake_ebdb_country.user AS u
		ON u.id_user = pp.id