WITH proponent_document_dates AS (
    SELECT
        p.id_proponent,
        MIN(IF(p.ts_documentation_sent IS NOT NULL, p.ts_documentation_sent, NULL)) AS ts_first_document_sent,
        MAX(IF(p.ts_documentation_sent IS NOT NULL, p.ts_documentation_sent, NULL)) AS ts_last_document_sent,
        MIN(IF(p_aud.tenant_documentation_status = 'AnaliseCredito', ure.ts_revision, NULL)) AS ts_first_sent_to_insurance
    FROM
        datalake_ebdb_clean.proposal AS p
    LEFT JOIN
        datalake_ebdb_clean.proposal_aud AS p_aud
            ON p_aud.id_proposal = p.id
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON ure.id = p_aud.rev
    GROUP BY
          p.id_proponent
),
user_information AS (
    WITH distinct_id_user_from_house AS (
        SELECT
            DISTINCT id_user
        FROM
            datalake_ebdb_clean.house
    ),
    distinct_id_user_from_device AS (
        SELECT
            DISTINCT id_user
        FROM
            datalake_ebdb_clean.device
        WHERE
            mobile_app = 'Inquilinos'
    ),
    distinct_id_user_from_contract AS (
        SELECT
            DISTINCT id_user
        FROM
            datalake_ebdb_clean.contract
    )
    SELECT
        user.id AS id_user,
        (house_ids.id_user IS NOT NULL) AS has_house,
        (device_ids.id_user IS NOT NULL) AS has_tenant_app,
        (contract_ids.id_user IS NOT NULL) AS has_active_contract,
        (
          (
            user.id_affiliates IS NULL
            AND user.id_photographer_data IS NULL
            AND user.id_sales_rep IS NULL
            AND user.id_agent_rep IS NULL
            AND house_ids.id_user IS NULL
          )
          OR contract_ids.id_user IS NOT NULL
        ) AS is_tenant,
        (user.id_photographer_data IS NOT NULL) AS is_photographer,
        SUBSTRING(user.main_phone, 4, 2) AS main_phone_ddd
    FROM
        datalake_ebdb_clean.user user
    LEFT JOIN
        distinct_id_user_from_house AS house_ids
            ON house_ids.id_user = user.id
    LEFT JOIN
        distinct_id_user_from_device AS device_ids
            ON device_ids.id_user = user.id
    LEFT JOIN
        distinct_id_user_from_contract AS contract_ids
            ON contract_ids.id_user = user.id
    GROUP BY
        1, 2, 3, 4, 5, 6, 7
),
user_state AS (
    SELECT
        id AS id_user,
        CASE
            WHEN id_state = 1 THEN 'AC'
            WHEN id_state = 2 THEN 'AL'
            WHEN id_state = 3 THEN 'AM'
            WHEN id_state = 4 THEN 'AP'
            WHEN id_state = 5 THEN 'BA'
            WHEN id_state = 6 THEN 'CE'
            WHEN id_state = 7 THEN 'DF'
            WHEN id_state = 8 THEN 'ES'
            WHEN id_state = 9 THEN 'GO'
            WHEN id_state = 10 THEN 'MA'
            WHEN id_state = 11 THEN 'MG'
            WHEN id_state = 12 THEN 'MS'
            WHEN id_state = 13 THEN 'MT'
            WHEN id_state = 14 THEN 'PA'
            WHEN id_state = 15 THEN 'PB'
            WHEN id_state = 16 THEN 'PE'
            WHEN id_state = 17 THEN 'PI'
            WHEN id_state = 18 THEN 'PR'
            WHEN id_state = 19 THEN 'RJ'
            WHEN id_state = 20 THEN 'RN'
            WHEN id_state = 21 THEN 'RR'
            WHEN id_state = 21 THEN 'RO'
            WHEN id_state = 23 THEN 'RS'
            WHEN id_state = 24 THEN 'SC'
            WHEN id_state = 25 THEN 'SE'
            WHEN id_state = 26 THEN 'SP'
            WHEN id_state = 27 THEN 'TO'
            ELSE NULL
        END AS uf
    FROM
        datalake_ebdb_clean.user 
)
SELECT
    u.id,
    ur.id_country,
    u.uuid_person,
    u.id_facebook,
    u.id_linkedin,
    u.id_google,
    u.id_agent,
    u.id_photographer_data,
    u.id_sales_rep,
    u.id_affiliates,
    u.id_bank,
    u.id_state,
    ur.country_code,
    u.cpf,
    u.rg,
    CASE
        WHEN u.cpf RLIKE '([0-9]{{3}})(.)([0-9]{{3}})(.)([0-9]{{3}})(-)([0-9]{{2}})' THEN 'CPF'
        WHEN u.cpf RLIKE '([0-9]{{2}})(.)([0-9]{{3}})(.)([0-9]{{3}})(\/)([0-9]{{4}})(-)([0-9]{{2}})' THEN 'CNPJ'
    END AS personal_document_type,
    u.gender,
    u.email,
    u.alternative_email,
    u.name,
    u.admin_type,
    u.address,
    u.number,
    u.complement,
    u.neighborhood,
    u.city,
    u.zip_code,
    us.uf,
    u.main_phone,
    ui.main_phone_ddd,
    u.bank_agency,
    u.bank_account,
    u.bank_cpf_cnpj,
    -- TODO [ODS] rename to bank_person_name
    u.bank_name,
    u.bank_another_holder,
    u.bank_account_type,
    u.has_accepted_sms,
    ui.has_house,
    ui.has_tenant_app,
    ui.has_active_contract,
    ui.is_tenant,
    ui.is_photographer,
    u.is_active,
    u.is_blocked,
    CAST(CASE
        WHEN DATE_FORMAT(u.dt_birth, 'y') < 100 THEN u.dt_birth + INTERVAL 1900 YEARS
        WHEN DATE_FORMAT(u.dt_birth, 'y') < 1000 THEN u.dt_birth + INTERVAL 1000 YEARS
        ELSE u.dt_birth
    END AS DATE) AS dt_birth,
    u.ts_click_anuncie,
    pdd.ts_first_document_sent,
    pdd.ts_last_document_sent,
    pdd.ts_first_sent_to_insurance,
    u.ts_created,
    u.ts_updated
FROM
    datalake_ebdb_clean.user AS u
JOIN
    datalake_ebdb_country.user AS ur
        ON u.id = ur.id_user
LEFT JOIN
    proponent_document_dates AS pdd
        ON pdd.id_proponent = u.id
LEFT JOIN
    user_information AS ui
        ON ui.id_user = u.id
LEFT JOIN
    user_state AS us
        ON us.id_user = u.id