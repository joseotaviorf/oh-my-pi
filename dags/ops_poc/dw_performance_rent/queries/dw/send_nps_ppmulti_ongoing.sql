WITH params AS (
    SELECT
        current_date() AS run_dt,
        date_trunc('month', current_date()) AS month_start,
        add_months(date_trunc('month', current_date()), 1) AS month_end,
        CAST(current_date() - INTERVAL 7 DAYS AS DATE) as run_dt_7
),

house_number AS (
    SELECT
        ppm.id_owner,
        ppm.ongoing_houses,
        -- No Spark, use make_date para criar data a partir de colunas ano/mes/dia
        make_date(CAST(ppm.year AS INT), CAST(ppm.month AS INT), CAST(ppm.day AS INT)) AS dt_houses_owned,
        row_number() OVER (
            PARTITION BY ppm.id_owner
            ORDER BY make_date(CAST(ppm.year AS INT), CAST(ppm.month AS INT), CAST(ppm.day AS INT)) DESC
        ) AS rk
    FROM datalake_pp_multi.pp_multi_classification_history ppm
),

deep_dive AS (
    SELECT DISTINCT
        A.*,
        B.pp_multi_classification AS last_pro_owner_status,
        hn.ongoing_houses,
        hn.dt_houses_owned,
        du.country_code
    FROM (
        SELECT 
            ppm.id_owner,
            max(hn.dt_houses_owned) AS last_ts_pro_owner_started
        FROM datalake_pp_multi.pp_multi_classification_history ppm
        LEFT JOIN house_number hn
            ON hn.id_owner = ppm.id_owner
        WHERE ppm.pp_multi_classification = 'ACTIVE'
        GROUP BY 1
    ) AS A
    INNER JOIN (
        SELECT 
            ppm.id_owner,
            ppm.pp_multi_classification,
            row_number() OVER (PARTITION BY ppm.id_owner ORDER BY hn.dt_houses_owned DESC) AS rw
        FROM datalake_pp_multi.pp_multi_classification_history ppm
        LEFT JOIN house_number hn
            ON hn.id_owner = ppm.id_owner
    ) AS B
        ON B.id_owner = A.id_owner AND B.rw = 1
    LEFT JOIN house_number hn
        ON hn.id_owner = A.id_owner AND hn.rk = 1
    LEFT JOIN dw_public.dim_user du
        ON du.sk_user = A.id_owner
),

active_pp AS (
    SELECT
        CAST(doq.id_owner AS INTEGER) AS id_owner,
        doq.ongoing_houses,
        CASE WHEN doq.pp_multi_classification = 'ACTIVE' THEN true ELSE false END AS is_pp_multi_active,
        make_date(CAST(doq.year AS INT), CAST(doq.month AS INT), CAST(doq.day AS INT)) AS dt_houses_owned,
        date_trunc('month', make_date(CAST(doq.year AS INT), CAST(doq.month AS INT), CAST(doq.day AS INT))) AS dt_month_cluster_pp_mult,
        CAST(base_pp.last_ts_pro_owner_started AS DATE) AS dt_last_pro_owner_started,
        ROW_NUMBER() OVER (
            PARTITION BY doq.id_owner, doq.month
            ORDER BY make_date(CAST(doq.year AS INT), CAST(doq.month AS INT), CAST(doq.day AS INT)) DESC
        ) AS rk
    FROM datalake_pp_multi.pp_multi_classification_history doq
    LEFT JOIN deep_dive base_pp
        ON base_pp.id_owner = doq.id_owner
    WHERE
        (doq.ongoing_houses >= 5 OR doq.pp_multi_classification = 'ACTIVE')
),

termination_contracts as (
    SELECT cp3.id_user, cp3.email
    FROM datalake_offboarding.contract_termination ct
    INNER JOIN dw_rent.dim_contract dc3
        ON dc3.sk_contract = ct.id_contract
    INNER JOIN datalake_ebdb_clean.contract_person cp3
        ON dc3.sk_contract = cp3.id_contract
       AND cp3.type = 'Proprietario'
    CROSS JOIN params p
    WHERE
        (CAST(ct.dt_termination AS DATE) >= least(p.month_start, run_dt_7) AND CAST(ct.dt_termination AS DATE) < p.month_end)
        OR
        (CAST(ct.ts_termination_finished AS DATE) >= least(p.month_start, run_dt_7) AND CAST(ct.ts_termination_finished AS DATE) < p.month_end)
),

eligible_contract_users AS (
    SELECT DISTINCT
        cp.id_user AS id_owner,
        dc.sk_contract -- Adicionado aqui para não quebrar o SELECT final
    FROM dw_rent.dim_contract dc
    INNER JOIN dw_rent.fact_listing_rent_flows rf
        ON dc.sk_contract = rf.sk_contract
       AND rf.sk_contract_signed_date > 0
    INNER JOIN dw_rent.dim_house_listing dhl
        ON dhl.sk_house_listing = rf.sk_house_listing
    INNER JOIN datalake_ebdb_clean.contract_person cp
        ON dc.sk_contract = cp.id_contract
       AND cp.type = 'Proprietario'
    CROSS JOIN params p
    WHERE
        dc.status = 'Ativo'
        AND dhl.is_b2b = false
        AND dhl.country_code = 'BR'
        AND dhl.rental_administrator = 'QUINTOANDAR'
        -- No Spark, use add_months para subtrair meses
        AND CAST(dc.dt_start AS DATE) <= add_months(p.month_start, -6)
        AND NOT EXISTS (
            SELECT 1
            FROM dw_rent.dim_contract dc2
            INNER JOIN datalake_ebdb_clean.contract_person cp2
                ON dc2.sk_contract = cp2.id_contract
               AND cp2.type = 'Proprietario'
            WHERE
                cp2.id_user = cp.id_user
                AND CAST(dc2.dt_start AS DATE) >= p.month_start
                AND CAST(dc2.dt_start AS DATE) < p.month_end
        )
)

SELECT
    du.nome AS customer_name,
    du.email AS customer_email,
    du.telefone_principal AS customer_phone,
    'ongppm' AS campaign_step,
    'Proprietário' AS customer_type,
    du.cpf AS customer_CPF,
    po.id_owner AS id_user,
    'ppm' AS campaign_type,
    'contract' AS driver_type,
    ecu.sk_contract as id_driver,
    -- No Spark use concat e date_format
    concat(
        du.email, ' ',
        date_format(CAST(date_trunc('month', current_date()) AS TIMESTAMP), 'yyyy-MM')
    ) AS chave,
    NOW() AS ts_load
FROM active_pp po
INNER JOIN eligible_contract_users ecu
    ON ecu.id_owner = po.id_owner
LEFT JOIN dw_public.dim_user du
    ON du.sk_user = po.id_owner
LEFT JOIN termination_contracts tc1
    ON po.id_owner = tc1.id_user
LEFT JOIN termination_contracts tc2
    ON du.email = tc2.email
CROSS JOIN params p
WHERE
    po.rk = 1
    AND tc1.id_user IS NULL 
    AND tc2.email IS NULL 
    AND po.is_pp_multi_active = TRUE
    AND po.ongoing_houses > 4
    AND po.dt_month_cluster_pp_mult = p.month_start;