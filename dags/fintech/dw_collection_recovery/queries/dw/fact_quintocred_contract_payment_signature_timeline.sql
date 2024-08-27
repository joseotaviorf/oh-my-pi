WITH propose_features AS (
    WITH base_executivos_comerciais AS (
        SELECT
            person.id AS id_person,
            person.person_name,
            company_executive.ts_updated,
            company.id AS sk_broker,
            ROW_NUMBER() OVER (PARTITION BY company.id ORDER BY company_executive.ts_updated DESC) AS rn
        FROM
            datalake_rental_guarantee_platform_clean.company_executive
        LEFT JOIN
            datalake_person_clean.person
            ON company_executive.uuid_person = person.uuid_person
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.company
            ON company_executive.uuid_company = company.uuid_company
        WHERE
            company_executive.is_active
    ),
    base_executivos_comerciais_dedupli AS (
        SELECT
            *
        FROM
            base_executivos_comerciais
        WHERE rn = 1
    )
    SELECT
        m.sk_propose,
        CAST(m.ts_sign_started AS date) AS ts_signed,
        CAST(m.dt_contract_started AS date) AS dt_contract_started,
        CAST(m.dt_ended AS date) AS dt_ended,
        CAST(m.dt_analyst_annulment_input AS date) AS dt_ended_input,
        m.dt_next_renewal,
        m.is_contract,
        COALESCE(f1.subscription_type, 'UNDEFINED') AS subscription_type,
        f1.subscription_installments,
        CAST(f1.monthly_guarantee AS FLOAT) AS monthly_guarantee,
        CAST(f1.annual_guarantee AS FLOAT) AS annual_guarantee,
        f1.activator_amount,
        CAST(COALESCE(f1.rent_amount, 0) + COALESCE(f1.condo_amount, 0) AS FLOAT) AS package_amount,
        j2.desc_lvl_1 AS propose_status,
        COALESCE(j1.desc_lvl_1, 'UNDEFINED') AS guarantee_status,
        j3.desc_lvl_1 AS propose_origin,
        m.is_legacy,
        CASE
            WHEN m.sk_propose < 5000000 THEN 'is_born_2.0'
            ELSE 'is_born_3.0'
        END AS birth_origin,
        m.sk_broker,
        j4.name,
        j4.document,
        j4.phone,
        j4.email,
        h.street,
        h.number,
        h.neighborhood,
        h.state,
        CONCAT(h.street, ', ', h.number, ' - ', h.neighborhood, ' - ', h.state) AS full_adress,
        h.zipcode,
        COALESCE(exec_com.person_name, 'UNFOUND') AS comercial_executive_name
    FROM
        dw_velo.fact_velo_propose AS m
    LEFT JOIN
        dw_velo.dim_velo_propose_values AS f1
        ON f1.sk_propose_values = m.sk_propose_values
    LEFT JOIN
        dw_velo.dim_velo_junk AS j1
        ON j1.sk_junk = m.sk_guarantee_status
    LEFT JOIN
        dw_velo.dim_velo_junk AS j2
        ON j2.sk_junk = m.sk_propose_status
    LEFT JOIN
        dw_velo.dim_velo_junk AS j3
        ON j3.sk_junk = m.sk_origin
    LEFT JOIN
        dw_velo.dim_velo_propose_person AS j4
        ON m.sk_primary_person = j4.sk_person
    LEFT JOIN
        dw_velo.dim_velo_house AS h
        ON h.sk_house = m.sk_house
    LEFT JOIN
        base_executivos_comerciais_dedupli AS exec_com
        ON exec_com.sk_broker = m.sk_broker
    WHERE
        m.is_contract
    ORDER BY m.sk_propose
),
first_propose_features AS (
    SELECT
        sk_propose,
        birth_origin,
        CAST(monthly_guarantee AS FLOAT) AS monthly_guarantee,
        CAST(annual_guarantee AS FLOAT) AS annual_guarantee,
        activator_amount,
        package_amount,
        guarantee_status,
        propose_status,
        sk_broker,
        CAST(dt_contract_started AS DATE) AS dt_contract_started,
        CAST(dt_ended AS DATE) AS dt_ended
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY sk_propose ORDER BY sk_propose) AS row_num
        FROM
            propose_features
    ) subquery
    WHERE
        row_num = 1
),
reference_months AS (
    SELECT
        DATE_TRUNC('month', DATE_ADD(dt_contract_started, -day(dt_contract_started) + 1)) AS earliest_start_date,
        DATE_TRUNC('month', CURRENT_DATE()) AS current_date
    FROM
        first_propose_features
    LIMIT 1
),
all_months AS (
    SELECT
        SEQUENCE(earliest_start_date, current_date, INTERVAL 1 MONTH) AS ref_months
    FROM
        reference_months
),
expanded_propose_features AS (
    SELECT
        pfc.*,
        am.ref_month
    FROM
        first_propose_features pfc
    CROSS JOIN
        (SELECT explode(ref_months) AS ref_month FROM all_months) am
),
filtered_propose_features AS (
    SELECT
        epf.*,
        DATE_TRUNC('month', epf.dt_contract_started) AS ref_mob_start,
        DATE_TRUNC('month', epf.dt_ended) AS ref_mob_end
    FROM
        expanded_propose_features epf
    WHERE
        epf.ref_month >= DATE_TRUNC('month', epf.dt_contract_started)
        AND (epf.dt_ended IS NULL OR epf.ref_month <= DATE_TRUNC('month', epf.dt_ended))
),
mob_calculation AS (
    SELECT
        *,
        (YEAR(ref_month) - YEAR(dt_contract_started)) * 12 + (MONTH(ref_month) - MONTH(dt_contract_started)) AS mob
    FROM
        filtered_propose_features
),
base_mob AS (
    SELECT
        sk_propose,
        birth_origin,
        CASE
            WHEN ref_mob_end IS NULL OR ref_mob_end > ref_month THEN 'Ativo'
            ELSE 'Finalizado'
        END AS status_at_ref,
        monthly_guarantee,
        annual_guarantee,
        activator_amount,
        package_amount,
        guarantee_status,
        propose_status,
        sk_broker,
        dt_contract_started,
        ref_mob_start,
        ref_mob_end,
        dt_ended,
        ref_month,
        mob
    FROM
        mob_calculation
    ORDER BY
        sk_propose, ref_month
),
step_0 AS (
    SELECT
        dd.month_start,
        p.sk_propose,
        p.dt_contract_started,
        p.dt_ended,
        rev.ts_created AS ts_started,
        DATE(rev.ts_created) AS start_date,
        pa.billing_model,
        pa.monthly_value
   FROM
        dw_velo.fact_velo_propose p
   LEFT JOIN
        datalake_rental_guarantee_platform_clean.propose pr
        ON pr.id = p.sk_propose
   LEFT JOIN
        datalake_rental_guarantee_platform_clean.propose_aud pa
        ON p.sk_propose = pa.id
   LEFT JOIN
        datalake_rental_guarantee_platform_clean.rev_info rev
        ON pa.rev = rev.rev
   LEFT JOIN
        dw_public.dim_date dd
        ON dd.month_start BETWEEN date_trunc('month', p.dt_contract_started) AND date_trunc('month', coalesce(p.dt_ended, CURRENT_DATE))
        AND IF(date_trunc('month', CURRENT_DATE) = dd.month_start, dd.date = CURRENT_DATE, dd.date = dd.month_start)
   WHERE
        (billing_model_mod = TRUE OR monthly_value_mod = TRUE)
        AND p.dt_contract_started IS NOT NULL and p.is_contract
   ORDER BY 1
),
step_mid0 AS (
    SELECT
        sk_propose,
        MIN(ts_started) AS first_reference_of_aud
    FROM
        step_0
    GROUP BY 1
),
step_mid0_mid0 AS (
   SELECT
        p.sk_propose,
        pa.billing_model AS first_billing_model,
        pa.monthly_value AS first_monthly_value
   FROM
        dw_velo.fact_velo_propose p
   LEFT JOIN
        datalake_rental_guarantee_platform_clean.propose pr
        ON pr.id = p.sk_propose
   LEFT JOIN
        datalake_rental_guarantee_platform_clean.propose_aud pa
        ON p.sk_propose = pa.id
   LEFT JOIN
        datalake_rental_guarantee_platform_clean.rev_info rev
        ON pa.rev = rev.rev
   LEFT JOIN
        step_mid0 AS sm0 ON sm0.sk_propose = p.sk_propose

   WHERE 1=1
     AND p.dt_contract_started IS NOT NULL
     AND rev.ts_created = first_reference_of_aud
   ORDER BY 1
),
step_mid0_mid1 AS (
   SELECT
        m.*,
        f.first_billing_model,
        f.first_monthly_value
    FROM
        step_0 AS m
   LEFT JOIN
        step_mid0_mid0 AS f
        ON f.sk_propose = m.sk_propose
),
step_1 AS (
    SELECT
        *,
        CASE
            WHEN month_start = date_trunc('month', start_date) THEN start_date
            ELSE NULL
        END AS property_dt_mod,
        CASE
            WHEN month_start = date_trunc('month', start_date) THEN billing_model
            ELSE NULL
        END AS billing_model_mod,
        CASE
            WHEN month_start = date_trunc('month', start_date) THEN monthly_value
            ELSE NULL
        END AS monthly_value_mod
   FROM
        step_mid0_mid1
),
step_2 AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY sk_propose, month_start ORDER BY property_dt_mod DESC) AS rn
    FROM
        step_1
),
step_3 AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY sk_propose ORDER BY month_start ASC) AS rn_c
    FROM
        step_2
    WHERE
        rn = 1
    ORDER BY month_start
),
step_4 AS (
    SELECT
        *,
        CASE
            WHEN rn_c = 1 THEN coalesce(billing_model_mod, first_billing_model)
            ELSE billing_model_mod
        END AS billing_mode_classification,
        CASE
            WHEN rn_c = 1 THEN coalesce(monthly_value_mod, first_monthly_value)
            ELSE monthly_value_mod
        END AS monthly_value_classification
FROM step_3
),
propose_property_timeline AS (
SELECT
    CAST(month_start AS DATE) AS ref_month,
    CAST(sk_propose AS INT) AS sk_propose,
    dt_contract_started,
    dt_ended,
    property_dt_mod,
    billing_model_mod,
    monthly_value_mod,
    CASE
        WHEN billing_model_mod IS NOT NULL THEN 1
        ELSE 0
    END AS flag_dm_mod,
    COALESCE(billing_mode_classification, LAG(billing_mode_classification, 1) IGNORE NULLS OVER (PARTITION BY sk_propose ORDER BY month_start)) AS billing_mode_at_ref,
    ROUND(COALESCE(monthly_value_classification, LAG(monthly_value_classification, 1) IGNORE NULLS OVER (PARTITION BY sk_propose ORDER BY month_start)),2) AS monthly_value
FROM
    step_4
ORDER BY 2,1
),
mob_expansion_df AS (
    SELECT
        a.sk_propose,
        a.birth_origin,
        a.status_at_ref,
        a.monthly_guarantee AS monthly_guarantee_online,
        a.annual_guarantee AS annual_guarantee_original,
        a.activator_amount,
        a.package_amount,
        a.guarantee_status,
        a.propose_status,
        a.sk_broker,
        a.dt_contract_started,
        a.ref_mob_start,
        a.ref_mob_end,
        a.dt_ended,
        a.ref_month,
        a.mob,
        b.property_dt_mod,
        b.billing_model_mod,
        b.monthly_value_mod,
        b.flag_dm_mod,
        b.billing_mode_at_ref,
        b.monthly_value AS monthly_guarantee,
        b.monthly_value * 12 AS annual_guarantee
    FROM
        base_mob a
    LEFT JOIN
        propose_property_timeline b
    ON
        a.sk_propose = b.sk_propose
        AND a.ref_month = b.ref_month
),
check_mob_payment_progression AS (
    SELECT
        mob.*,
        pay.*,
       CASE
           WHEN origin_table IS NULL THEN 1
           ELSE 0
       END AS flag_missing_payment
    FROM
        mob_expansion_df AS mob
    LEFT JOIN
        datalake_velo.payment_contracts AS pay
        ON mob.sk_propose = pay.id_propose
        AND mob.ref_month = pay.dt_month_ref_due
),
df_transaction_w_values AS (
    SELECT
        *,
        CASE
            WHEN value IS NULL OR value = 0 OR monthly_guarantee = 0 THEN NULL
            WHEN value / (12 * monthly_guarantee + activator_amount) <= 1.1 AND value / (12 * monthly_guarantee + activator_amount) >= 0.90 THEN 'ANNUAL+ACTIVATION'
            WHEN value / (12 * monthly_guarantee) <= 1.1 AND value / (12 * monthly_guarantee) >= 0.90 THEN 'ANNUAL'
            WHEN value / (monthly_guarantee) <= 1.1 AND value / (monthly_guarantee) >= 0.90 THEN 'SINGLE MONTHLY PAYMENT'
            ELSE 'UNDEFINED'
        END AS flag_annual_payment,
        CASE
            WHEN value IS NULL OR value = 0 OR monthly_guarantee = 0 THEN NULL
            WHEN value / (12 * monthly_guarantee + activator_amount) <= 1.1 AND value / (12 * monthly_guarantee + activator_amount) >= 0.90 THEN ref_month
            WHEN value / (12 * monthly_guarantee) <= 1.1 AND value / (12 * monthly_guarantee) >= 0.90 THEN ref_month
            WHEN value / (monthly_guarantee) <= 1.1 AND value / (monthly_guarantee) >= 0.90 THEN NULL
            ELSE NULL
        END AS flag_annual_payment_month,
        CASE
            WHEN value IS NULL OR value = 0 OR monthly_guarantee = 0 THEN NULL
            WHEN value / (12 * monthly_guarantee + activator_amount) <= 1.1 AND value / (12 * monthly_guarantee + activator_amount) >= 0.90 AND status IN ('SUCCESS', 'PROCESSING', 'RECEIVED', 'PAID', 'IN PAYMENT', 'RECEIVED_IN_CASH', 'PAID_AFTER_DUE_DATE', NULL) THEN 'ANNUAL+ACTIVATION'
            WHEN value / (12 * monthly_guarantee) <= 1.1 AND value / (12 * monthly_guarantee) >= 0.90 AND status IN ('SUCCESS', 'PROCESSING', 'RECEIVED', 'PAID', 'IN PAYMENT', 'RECEIVED_IN_CASH', 'PAID_AFTER_DUE_DATE', NULL) THEN 'ANNUAL'
            WHEN value / (monthly_guarantee) <= 1.1 AND value / (monthly_guarantee) >= 0.90 THEN 'SINGLE MONTHLY PAYMENT'
            ELSE 'UNDEFINED'
        END AS flag_annual_payment_valid,
        CASE
            WHEN value IS NULL OR value = 0 OR monthly_guarantee = 0 THEN NULL
            WHEN value / (12 * monthly_guarantee + activator_amount) <= 1.1 AND value / (12 * monthly_guarantee + activator_amount) >= 0.90 AND status IN ('SUCCESS', 'PROCESSING', 'RECEIVED', 'PAID', 'IN PAYMENT', 'RECEIVED_IN_CASH', 'PAID_AFTER_DUE_DATE', NULL) THEN ref_month
            WHEN value / (12 * monthly_guarantee) <= 1.1 AND value / (12 * monthly_guarantee) >= 0.90 AND status IN ('SUCCESS', 'PROCESSING', 'RECEIVED', 'PAID', 'IN PAYMENT', 'RECEIVED_IN_CASH', 'PAID_AFTER_DUE_DATE', NULL) THEN ref_month
            WHEN value / (monthly_guarantee) <= 1.1 AND value / (monthly_guarantee) >= 0.90 THEN NULL
            ELSE NULL
        END AS flag_annual_payment_month_valid
    FROM
        check_mob_payment_progression
),
flags AS (
    SELECT
        *,
        CASE
            WHEN flag_annual_payment_month IS NULL THEN NULL
            ELSE ADD_MONTHS(flag_annual_payment_month, 12)
        END AS flag_annual_payment_month_limit,
        CASE
            WHEN flag_annual_payment_month_valid IS NULL THEN NULL
            ELSE ADD_MONTHS(flag_annual_payment_month_valid, 12)
        END AS flag_annual_payment_month_valid_limit
    FROM
        df_transaction_w_values
),
memory_annual_limit AS (
    SELECT
        *,
        LAST_VALUE(flag_annual_payment_month_limit) IGNORE NULLS OVER (
            PARTITION BY sk_propose
            ORDER BY ref_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS memory_annual_limit
    FROM
        flags
),
memory_annual_valid_limit AS (
    SELECT
        *,
        LAST_VALUE(flag_annual_payment_month_valid_limit) IGNORE NULLS OVER (
            PARTITION BY sk_propose
            ORDER BY ref_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS memory_annual_valid_limit
    FROM
        memory_annual_limit
)
SELECT
    sk_propose,
    sk_broker,
    id,
    origin_table,
    status,
    gateway,
    COALESCE(LAST_VALUE(gateway) IGNORE NULLS OVER (PARTITION BY sk_propose ORDER BY ref_month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 'UNDEFINED') AS gateway_memory_transaction,
    billing_type,
    category,
    birth_origin,
    status_at_ref,
    monthly_guarantee_online,
    annual_guarantee_original,
    activator_amount,
    package_amount,
    guarantee_status,
    propose_status,
    ref_mob_start,
    ref_mob_end,
    ref_month,
    mob,
    property_dt_mod,
    billing_model_mod,
    monthly_value_mod,
    billing_mode_at_ref,
    monthly_guarantee,
    annual_guarantee,
    value,
    memory_annual_limit,
    memory_annual_valid_limit,
    flag_dm_mod,
    flag_missing_payment,
    flag_annual_payment,
    flag_annual_payment_month,
    flag_annual_payment_valid,
    flag_annual_payment_month_valid,
    flag_annual_payment_month_limit,
    flag_annual_payment_month_valid_limit,
    dt_contract_started,
    dt_ended,
    dt_created,
    dt_month_ref_creation,
    dt_due,
    dt_month_ref_due,
    dt_paid

FROM
    memory_annual_valid_limit
