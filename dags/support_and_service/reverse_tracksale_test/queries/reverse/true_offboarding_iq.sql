-- The cohort day is the partition day of the offboarding IQ dispatches table.
-- Anchoring on it (instead of CURRENT_DATE) keeps the result reproducible on backfills.
WITH people_to_send AS (
    SELECT
        toid.customer_name,
        toid.customer_email,
        toid.customer_phone,
        toid.campaign_step,
        toid.customer_type,
        toid.customer_cpf,
        toid.id_user,
        toid.campaign_type,
        toid.driver_type,
        toid.id_driver,
        MAKE_DATE(toid.year, toid.month, toid.day) AS dt_cohort
    FROM
        datalake_tracksale_dispatches.true_offboarding_iq_dispatches AS toid
    LEFT JOIN
        datalake_tracksale_dispatches.true_offboarding_iq_dispatches AS hist
            ON MAKE_DATE(hist.year, hist.month, hist.day) BETWEEN DATE_SUB(DATE('{load_start_date}'), 90) AND DATE_SUB(DATE('{load_start_date}'), 1)
            AND toid.id_driver = hist.id_driver
            AND toid.customer_email = hist.customer_email
            AND toid.customer_name = hist.customer_name
    WHERE
        MAKE_DATE(toid.year, toid.month, toid.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND hist.customer_email IS NULL
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
    UNION ALL
    SELECT
        'Teste Disparo' AS customer_name,
        'testes.disparos.5a@gmail.com' AS customer_email,
        '+5511123456789' AS customer_phone,
        'Rescisão' AS campaign_step,
        'Inquilino' AS customer_type,
        '12345' AS customer_cpf,
        '12345' AS id_user,
        'true' AS campaign_type,
        'contract' AS driver_type,
        '12345' AS id_driver,
        DATE('{load_start_date}') AS dt_cohort
),
previous_dispatches AS (
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        reverse_tracksale_test.true_offboarding_iq
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
    UNION
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        datalake_tracksale_reverse.true_offboarding_iq
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
