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
  pl.commission AS plan_commission
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
