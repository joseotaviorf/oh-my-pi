WITH cte_union AS (
(
    WITH pack_values AS (
    SELECT
      pk.id_propose AS id_propose,
      COALESCE( SUM( CASE WHEN pk.id_pack_type = 1 THEN COALESCE(pk.value,0) END ) , 0) AS rent_amount,
      COALESCE( SUM( CASE WHEN pk.id_pack_type = 2 THEN COALESCE(pk.value,0) END ) , 0) AS condo_amount,
      COALESCE( SUM( CASE WHEN pk.id_pack_type = 3 THEN COALESCE(pk.value,0) END ) , 0) AS light_amount,
      COALESCE( SUM( CASE WHEN pk.id_pack_type = 4 THEN COALESCE(pk.value,0) END ) , 0) AS water_amount,
      COALESCE( SUM( CASE WHEN pk.id_pack_type = 5 THEN COALESCE(pk.value,0) END ) , 0) AS phone_amount,
      COALESCE( SUM( CASE WHEN pk.id_pack_type = 6 THEN COALESCE(pk.value,0) END ) , 0) AS iptu_amount,
      COALESCE( SUM( CASE WHEN pk.id_pack_type NOT IN (1,2,3,4,5,6) THEN COALESCE(pk.value,0) END ) , 0) AS other_amount,
      SUM(COALESCE(pk.value,0)) AS total_package_amount
    FROM
      datalake_velo_clean.fiancavelo_packvalues AS pk
    WHERE
      pk.is_active
    GROUP BY
      1
  ),
  payments AS (
    SELECT
      NULLIF(p.id_propose,0) AS id_propose,
      p.value,
      RANK() OVER(PARTITION BY NULLIF(p.id_propose,0) ORDER BY p.dt_created) AS rk
    FROM
      datalake_velo_clean.fiancavelo_payment AS p
  ),
  first_payment AS (
    SELECT
      id_propose,
      SUM(value) AS first_payment_amount
    FROM
      payments
    WHERE
      rk = 1
    GROUP BY
      1
  )
  SELECT
    CONCAT(p.id, a.id, pl.id) AS id_propose_values,
    CASE
      WHEN (COALESCE(pk.total_package_amount*pl.percent*0.01*12.0,0) + COALESCE(a.value,0)) > fp.first_payment_amount THEN 'monthly'
      WHEN (COALESCE(pk.total_package_amount*pl.percent*0.01*12.0,0) + COALESCE(a.value,0)) <= fp.first_payment_amount THEN 'annual'
      ELSE 'no info'
    END AS subscription_type,
    plt.name AS plan_type,
    a.name AS activator_type,
    pl.name AS plan,
    CASE
      WHEN (COALESCE(pk.total_package_amount*pl.percent*0.01*12.0,0) + COALESCE(a.value,0)) > fp.first_payment_amount THEN 1
      ELSE 12
    END AS subscription_installments,
    a.value AS activator_amount,
    COALESCE(pk.total_package_amount*pl.percent*0.01,0) AS monthly_guarantee,
    COALESCE(pk.total_package_amount*pl.percent*0.01*12.0,0) AS annual_guarantee,
    pk.rent_amount,
    pk.condo_amount,
    pk.light_amount,
    pk.water_amount,
    pk.phone_amount,
    pk.iptu_amount,
    pk.other_amount,
    pk.total_package_amount,
    pl.percent AS plan_percent,
    pl.coverage AS plan_coverage,
    pl.damage AS plan_damage,
    pl.commission AS plan_commission,
    TRUE AS is_legacy
  FROM
    datalake_velo_clean.fiancavelo_propose AS p
  LEFT JOIN
    datalake_velo_clean.fiancavelo_activator AS a
      ON a.id = p.id_activator
  LEFT JOIN
    datalake_velo_clean.fiancavelo_plans AS pl
      ON pl.id = p.id_plan
  LEFT JOIN
    datalake_velo_clean.fiancavelo_plantype AS plt
      ON plt.id = pl.id_type
      AND plt.is_active
  LEFT JOIN
    pack_values AS pk
      ON pk.id_propose = p.id
  LEFT JOIN
    first_payment AS fp
      ON fp.id_propose = p.id

)
UNION ALL
(
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

  SELECT
      CONCAT(p.id, cp.id, pl.id) AS id_propose_values,
      CASE py.billing_type
        WHEN 'CREDIT_CARD' THEN 'monthly'
        WHEN 'PIX' THEN 'annual'
        WHEN 'ANNUAL_CREDIT_CARD' THEN 'annual'
        ELSE 'no info'
      END AS subscription_type,
      bt.name AS plan_type,
      NULL AS activator_type,
      pl.plan_name AS plan,
      NULL AS subscription_installments,
      p.activator_value AS activator_amount,
      COALESCE((COALESCE(pv.rent_amount,0) + COALESCE(pv.condo_amount,0) + COALESCE(pv.light_amount,0) + COALESCE(pv.iptu_amount,0) + COALESCE(pv.other_amount,0))*pl.pricing,0) AS monthly_guarantee,
      COALESCE((COALESCE(pv.rent_amount,0) + COALESCE(pv.condo_amount,0) + COALESCE(pv.light_amount,0) + COALESCE(pv.iptu_amount,0) + COALESCE(pv.other_amount,0))*pl.pricing*12,0) AS annual_guarantee,
      pv.rent_amount,
      pv.condo_amount,
      pv.light_amount,
      NULL AS water_amount,
      NULL AS phone_amount,
      pv.iptu_amount,
      pv.other_amount,
      COALESCE(pv.rent_amount,0) + COALESCE(pv.condo_amount,0) + COALESCE(pv.light_amount,0) + COALESCE(pv.iptu_amount,0) + COALESCE(pv.other_amount,0) AS total_package_amount,
      pl.pricing plan_percent,
      pl.coverage AS plan_coverage,
      pl.damage AS plan_damage,
      pl.commission AS plan_commission,
      FALSE AS is_legacy
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
  WHERE
      p.id >= 5000000
)
ORDER BY 1
)
SELECT
    id_propose_values,
    subscription_type,
    plan_type,
    activator_type,
    plan,
    subscription_installments,
    activator_amount,
    monthly_guarantee,
    annual_guarantee,
    rent_amount,
    condo_amount,
    light_amount,
    water_amount,
    phone_amount,
    iptu_amount,
    other_amount,
    total_package_amount,
    plan_percent,
    plan_coverage,
    plan_damage,
    plan_commission,
    is_legacy
FROM
    cte_union
