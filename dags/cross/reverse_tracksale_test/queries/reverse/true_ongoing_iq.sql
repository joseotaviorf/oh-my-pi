-- The cohort day is the 6-month contract anniversary, or 15 days after it (recap).
-- Anchoring on DATE('{load_start_date}') (instead of CURRENT_DATE) keeps the result reproducible on backfills.
WITH contracts AS (
    SELECT
        dc.sk_contract,
        dc.dt_start,
        DATE('{load_start_date}') - INTERVAL '15' DAY AS dt_recap,
        INT(MONTHS_BETWEEN(DATE('{load_start_date}'), dc.dt_start)) AS age,
        INT(MONTHS_BETWEEN(DATE('{load_start_date}') - INTERVAL '15' DAY, dc.dt_start)) AS age_recap,
        CASE
            WHEN DAY(dt_start) = DAY(DATE('{load_start_date}'))
                AND INT(MONTHS_BETWEEN(DATE('{load_start_date}'), dc.dt_start)) % 6 = 0 THEN 'birthday'
            WHEN DAY(dt_start) = DAY(DATE('{load_start_date}') - INTERVAL '15' DAY)
                AND INT(MONTHS_BETWEEN(DATE('{load_start_date}') - INTERVAL '15' DAY, dc.dt_start)) % 6 = 0 THEN 'recap_birthday'
            ELSE NULL
        END AS birth_type
    FROM
        dw_rent.dim_contract AS dc
    LEFT JOIN
        datalake_offboarding.contract_termination AS ct
            ON dc.sk_contract = ct.id_contract
            AND ct.status != 'CANCELED'
    WHERE
        dc.country_code = 'BR'
        AND dc.status = 'Ativo'
        AND ct.id_contract IS NULL
        AND dc.rental_administrator = 'QUINTOANDAR'
        AND INT(MONTHS_BETWEEN(DATE('{load_start_date}'), dc.dt_start)) > 5
),
stock_contracts AS (
    SELECT DISTINCT
        op.id_contract
    FROM
        datalake_collections_quintoandar.overdue_portfolio_timeline AS op
    WHERE
        op.debtor_type = 'Stock'
        AND op.dt_reference BETWEEN (DATE('{load_start_date}') - INTERVAL '180' DAY) AND DATE('{load_start_date}')
),
status_send AS (
    SELECT
        c.sk_contract,
        c.age,
        c.age_recap,
        c.birth_type,
        ft.front_or_back,
        dp.team,
        c.dt_start,
        c.dt_recap,
        ft.ts_created AS ts_started,
        ft.ts_solved,
        CASE
            WHEN c.birth_type = 'birthday'
                AND ft.sk_ticket IS NOT NULL
                AND ft.ts_solved IS NULL
                AND (ft.front_or_back = 'back' OR dp.team IS NOT NULL) THEN 1
            ELSE 0
        END AS flg_not_send,
        CASE
            WHEN c.birth_type = 'recap_birthday'
                AND ft.sk_ticket IS NOT NULL
                AND ft.ts_created < c.dt_recap
                AND (ft.ts_solved >= c.dt_recap OR ft.ts_solved IS NULL)
                AND (ft.front_or_back = 'back' OR dp.team IS NOT NULL) THEN 1
            ELSE 0
        END AS flg_recap_send
    FROM
        contracts AS c
    LEFT JOIN
        dw_customer_support.dim_ticket AS dt
            ON c.sk_contract = dt.sk_contract
            AND dt.sk_contract IS NOT NULL
    LEFT JOIN
        dw_customer_support.fact_tickets AS ft
            ON dt.sk_ticket = ft.sk_ticket
    LEFT JOIN
        dw_customer_support.dim_department AS dp
            ON ft.sk_main_department = dp.sk_department
            AND (
                dp.department IN (
                    'Notificação Extrajudicial [CE] [POS] [BACK]',
                    'Dados Bancários [CE] [POS] [BACK]',
                    'CX ReclameAqui Adquiridas [CE] [POS] [BACK]'
                )
                OR dp.team IN ('Casos Especiais', 'Ouvidoria', 'ReclameAqui', 'Evictions')
            )
    WHERE
        c.birth_type IS NOT NULL
        AND c.sk_contract NOT IN (
            SELECT
                id_contract
            FROM
                stock_contracts
        )
),
contracts_to_send AS (
    SELECT
        ss.sk_contract,
        ss.age,
        ss.age_recap,
        MAX(ss.birth_type) AS birth_type,
        MAX(ss.flg_not_send) AS flg_not_send,
        MAX(ss.flg_recap_send) AS flg_recap_send
    FROM
        status_send AS ss
    GROUP BY
        1,
        2,
        3
    HAVING
        (MAX(ss.birth_type) = 'birthday' AND MAX(ss.flg_not_send) = 0)
        OR (MAX(ss.birth_type) = 'recap_birthday' AND MAX(ss.flg_recap_send) = 1)
),
people_to_send AS (
    SELECT
        cp.name AS customer_name,
        cp.email AS customer_email,
        cp.phone_number AS customer_phone,
        CASE
            WHEN cs.birth_type = 'birthday' THEN STRING(cs.age) || ' meses'
            ELSE STRING(cs.age_recap) || ' meses'
        END AS campaign_step,
        'Inquilino' AS customer_type,
        cp.cpf AS customer_cpf,
        cp.id_user,
        'true' AS campaign_type,
        'id_contract' AS driver_type,
        cp.id_contract AS id_driver,
        DATE('{load_start_date}') AS dt_cohort
    FROM
        datalake_ebdb_clean.contract_person AS cp
    INNER JOIN
        contracts_to_send AS cs
            ON cp.id_contract = cs.sk_contract
    WHERE
        cp.type IN ('Inquilino', 'Morador')
        AND cp.email IS NOT NULL
),
customers AS (
    SELECT
        customer_name,
        customer_email,
        customer_phone,
        campaign_step,
        customer_type,
        customer_cpf,
        id_user,
        campaign_type,
        driver_type,
        id_driver,
        dt_cohort
    FROM
        people_to_send
    WHERE
        dt_cohort BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION ALL
    SELECT
        'Teste Disparo' AS customer_name,
        'testes.disparos.5a@gmail.com' AS customer_email,
        '+5511123456789' AS customer_phone,
        '12 meses' AS campaign_step,
        'Inquilino' AS customer_type,
        '1234' AS customer_cpf,
        '1234' AS id_user,
        'true' AS campaign_type,
        'id_contract' AS driver_type,
        '1234' AS id_driver,
        DATE('{load_start_date}') AS dt_cohort
),
previous_dispatches AS (
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        reverse_tracksale_test.true_ongoing_iq
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
    UNION
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        datalake_tracksale_reverse.true_ongoing_iq
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
