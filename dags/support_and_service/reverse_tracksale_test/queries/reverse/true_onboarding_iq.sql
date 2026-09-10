-- The cohort day is 10 days after the contract start date.
-- Anchoring on it (instead of CURRENT_DATE) keeps the result reproducible on backfills.
WITH new_contracts AS (
    SELECT
        dc.sk_contract,
        dc.dt_start,
        DATE_ADD(dc.dt_start, 10) AS dt_cohort,
        'Onboarding' AS step
    FROM
        dw_rent.dim_contract AS dc
    INNER JOIN
        dw_rent.fact_listing_rent_flows AS rf
            ON dc.sk_contract = rf.sk_contract
            AND rf.sk_contract_signed_date > 0
    INNER JOIN
        dw_rent.dim_house_listing AS dhl
            ON dhl.sk_house_listing = rf.sk_house_listing
    LEFT JOIN
        datalake_offboarding.contract_termination AS ct
            ON dc.sk_contract = ct.id_contract
    WHERE
        dc.status = 'Ativo'
        AND (
            (ct.dt_termination > dc.dt_start)
            OR (ct.dt_termination IS NULL)
        )
        AND dhl.country_code = 'BR'
        AND dhl.rental_administrator = 'QUINTOANDAR'
    GROUP BY
        1,
        2,
        3,
        4
),
crisis_users AS (
    SELECT DISTINCT
        ft.sk_contract
    FROM
        dw_customer_support.fact_tickets AS ft
    INNER JOIN
        dw_customer_support.dim_ticket AS dt
            ON dt.sk_ticket = ft.sk_ticket
    INNER JOIN
        dw_customer_support.dim_department AS dd
            ON dd.department = dt.group_name
    WHERE
        (
            dt.group_name IN (
                'Notificação Extrajudicial [CE] [POS] [BACK]',
                'Dados Bancários [CE] [POS] [BACK]',
                'CX ReclameAqui Adquiridas [CE] [POS] [BACK]'
            )
            OR dd.team IN ('Casos Especiais', 'Ouvidoria', 'ReclameAqui', 'Evictions')
        )
        AND ft.sk_user <> -1
        AND ft.ts_solved IS NULL
),
onboarding_contracts AS (
    SELECT
        c.sk_contract,
        c.dt_start,
        c.dt_cohort,
        c.step
    FROM
        new_contracts AS c
    LEFT JOIN
        crisis_users AS uc
            ON uc.sk_contract = c.sk_contract
    WHERE
        uc.sk_contract IS NULL
    GROUP BY
        1,
        2,
        3,
        4
),
tenants_dwellers AS (
    SELECT
        cp.cpf,
        cp.id_user,
        cp.name,
        cp.email,
        cp.phone_number,
        ac.sk_contract,
        ac.step,
        ac.dt_cohort,
        DENSE_RANK() OVER (
            PARTITION BY
                cp.id_contract,
                cp.email
            ORDER BY
                cp.id
        ) AS order_diff_email
    FROM
        onboarding_contracts AS ac
    INNER JOIN
        datalake_ebdb_clean.contract_person AS cp
            ON ac.sk_contract = cp.id_contract
            AND cp.type IN ('Inquilino', 'Morador')
            AND cp.email IS NOT NULL
),
customers AS (
    SELECT
        name AS customer_name,
        email AS customer_email,
        phone_number AS customer_phone,
        step AS campaign_step,
        'Inquilino' AS customer_type,
        cpf AS customer_cpf,
        id_user,
        'true' AS campaign_type,
        'contract' AS driver_type,
        sk_contract AS id_driver,
        dt_cohort
    FROM
        tenants_dwellers
    WHERE
        order_diff_email = 1
        AND dt_cohort BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION ALL
    SELECT
        'Teste Disparos' AS customer_name,
        'testes.disparos.5a@gmail.com' AS customer_email,
        '+5511123456789' AS customer_phone,
        'Onboarding' AS campaign_step,
        'Inquilino' AS customer_type,
        '1234' AS customer_cpf,
        '1234' AS id_user,
        'true' AS campaign_type,
        'contract' AS driver_type,
        '1234' AS id_driver,
        DATE('{load_start_date}') AS dt_cohort
),
previous_dispatches AS (
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        reverse_tracksale_test.true_onboarding_iq
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
    UNION
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        datalake_tracksale_reverse.true_onboarding_iq
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
)
SELECT
    customers.customer_name,
    customers.customer_email,
    customers.customer_phone,
    customers.campaign_step,
    customers.customer_type,
    customers.customer_cpf,
    customers.id_user,
    customers.campaign_type,
    customers.driver_type,
    customers.id_driver,
    CASE
        WHEN pd.customer_email IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_dispatched,
    CASE
        WHEN pd.customer_email IS NOT NULL THEN CAST(DATE('{load_start_date}') AS TIMESTAMP)
        ELSE CAST(NULL AS TIMESTAMP)
    END AS ts_dispatched,
    customers.dt_cohort,
    YEAR(customers.dt_cohort) AS year,
    MONTH(customers.dt_cohort) AS month,
    DAY(customers.dt_cohort) AS day
FROM
    customers
LEFT JOIN
    previous_dispatches AS pd
        ON customers.customer_email = pd.customer_email
        AND pd.dt_partition BETWEEN DATE_SUB(customers.dt_cohort, 90) AND customers.dt_cohort
