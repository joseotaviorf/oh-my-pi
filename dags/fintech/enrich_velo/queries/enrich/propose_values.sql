
WITH prop_values AS (
    WITH cte_values AS (
        SELECT
            id_propose,
            pi.value,
            it.name
        FROM
            datalake_rental_guarantee_platform_clean.propose_item AS pi
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.item_type AS it
                ON pi.id_item_type = it.id
    )

    SELECT
        *
    FROM
        cte_values
    PIVOT(
        SUM(value)
        FOR name IN
        (
            'Aluguel' AS rent_amount,
            'Luz' AS light_amount,
            'Iptu' AS iptu_amount,
            'Condomínio' AS condo_amount,
            'Outros' AS other_amount
        )
    )
),
cte_payment AS (
  SELECT
      id_propose,
      billing_type
  FROM
      datalake_rental_guarantee_platform_clean.payment
  QUALIFY
      ROW_NUMBER() OVER (PARTITION BY id_propose ORDER BY ts_updated DESC) = 1
)

SELECT DISTINCT
    CONCAT(p.id, cp.id, pl.id) AS id_propose_values,
    CASE py.billing_type
      WHEN 'CREDIT_CARD' THEN 'monthly'
      WHEN 'PIX' THEN 'annual'
      WHEN 'ANNUAL_CREDIT_CARD' THEN 'annual'
      ELSE 'no info'
    END AS subscription_type,
    bt.name AS plan_type,
    CAST(NULL AS STRING) AS activator_type,
    pl.plan_name AS plan,
    CAST(NULL AS BIGINT) AS subscription_installments,
    p.activator_value AS activator_amount,
    COALESCE((COALESCE(pv.rent_amount,0) + COALESCE(pv.condo_amount,0) + COALESCE(pv.light_amount,0) + COALESCE(pv.iptu_amount,0) + COALESCE(pv.other_amount,0))*pl.pricing,0) AS monthly_guarantee,
    COALESCE((COALESCE(pv.rent_amount,0) + COALESCE(pv.condo_amount,0) + COALESCE(pv.light_amount,0) + COALESCE(pv.iptu_amount,0) + COALESCE(pv.other_amount,0))*pl.pricing*12,0) AS annual_guarantee,
    pv.rent_amount,
    pv.condo_amount,
    pv.light_amount,
    CAST(NULL AS BIGINT) AS water_amount,
    CAST(NULL AS BIGINT) AS phone_amount,
    pv.iptu_amount,
    pv.other_amount,
    COALESCE(pv.rent_amount,0) + COALESCE(pv.condo_amount,0) + COALESCE(pv.light_amount,0) + COALESCE(pv.iptu_amount,0) + COALESCE(pv.other_amount,0) AS total_package_amount,
    pl.pricing * 100 AS plan_percent,
    pl.coverage AS plan_coverage,
    pl.damage AS plan_damage,
    pl.commission AS plan_commission,
    p.id <= 5000000 AS is_legacy
FROM
    datalake_rental_guarantee_platform_clean.propose AS p
LEFT JOIN
    datalake_rental_guarantee_platform_clean.company_plan AS cp
        ON p.id_company_plan = cp.id
LEFT JOIN
    datalake_rental_guarantee_platform_clean.plan AS pl
        ON cp.id_plan = pl.id
LEFT JOIN
    datalake_rental_guarantee_platform_clean.bussines_type AS bt
        ON pl.id_type = bt.id
LEFT JOIN
    prop_values AS pv
        ON p.id = pv.id_propose
LEFT JOIN
    cte_payment AS py
      ON p.id = py.id_propose

UNION ALL

-- the following query includes propose_values for 2.0 proposes

SELECT DISTINCT
    CONCAT(p.id, cp.id, pl.id) AS id_propose_values,
    CAST(NULL AS STRING) AS subscription_type,
    bt.name AS plan_type,
    CAST(NULL AS STRING) AS activator_type,
    pl.plan_name AS plan,
    CAST(NULL AS BIGINT) AS subscription_installments,
    p.activator_value AS activator_amount,
    CAST(NULL AS DECIMAL(30,6)) AS monthly_guarantee,
    CAST(NULL AS DECIMAL(33,6)) AS annual_guarantee,
    CAST(NULL AS DECIMAL(18,2)) AS rent_amount,
    CAST(NULL AS DECIMAL(18,2)) AS condo_amount,
    CAST(NULL AS DECIMAL(18,2)) AS light_amount,
    CAST(NULL AS BIGINT) AS water_amount,
    CAST(NULL AS BIGINT) AS phone_amount,
    CAST(NULL AS DECIMAL(18,2)) AS iptu_amount,
    CAST(NULL AS DECIMAL(18,2)) AS other_amount,
    CAST(NULL AS DECIMAL(22,2)) AS total_package_amount,
    pl.pricing * 100 AS plan_percent,
    pl.coverage AS plan_coverage,
    pl.damage AS plan_damage,
    pl.commission AS plan_commission,
    True AS is_legacy
FROM
    datalake_rental_guarantee_platform_clean.fiancavelo_propose_legacy AS p
LEFT JOIN
    datalake_rental_guarantee_platform_clean.plan AS pl
        ON p.id_plan = pl.id_legacy
LEFT JOIN
    datalake_rental_guarantee_platform_clean.company_plan AS cp
        ON p.id_quintocred_company = cp.id_company
        AND pl.id = cp.id_plan
LEFT JOIN
    datalake_rental_guarantee_platform_clean.bussines_type AS bt
        ON pl.id_type = bt.id
WHERE
    p.id NOT IN (SELECT id FROM datalake_rental_guarantee_platform_clean.propose)
