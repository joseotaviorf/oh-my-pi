WITH old_duplicated_company_plan AS (
    SELECT
        pl.id AS id_plan,
        cp.id_company,
        COUNT(*) AS count_company_plan
    FROM
        datalake_rental_guarantee_platform_clean.plan AS pl
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.company_plan AS cp
            ON pl.id = cp.id_plan
    GROUP BY 1, 2
),

pack_values AS (
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

    SELECT DISTINCT
        CONCAT(p.id, COALESCE(cp.id, ''), pl.id) * -1 AS id_propose_values,
        CASE
        WHEN (COALESCE(pk.total_package_amount * (pl.pricing * 100) * 0.01 * 12.0,0) + COALESCE(a.value,0)) > fp.first_payment_amount THEN 'monthly'
        WHEN (COALESCE(pk.total_package_amount * (pl.pricing * 100) * 0.01 * 12.0,0) + COALESCE(a.value,0)) <= fp.first_payment_amount THEN 'annual'
        ELSE 'no info'
        END AS subscription_type,
        bt.name AS plan_type,
        a.name AS activator_type,
        pl.plan_name AS plan,
        CASE
        WHEN (COALESCE(pk.total_package_amount * (pl.pricing * 100) * 0.01 * 12.0,0) + COALESCE(a.value,0)) > fp.first_payment_amount THEN 1
        ELSE 12
        END AS subscription_installments,
        p.activator_value AS activator_amount,
        COALESCE(pk.total_package_amount * (pl.pricing * 100) * 0.01,0) AS monthly_guarantee,
        COALESCE(pk.total_package_amount * (pl.pricing * 100) * 0.01 * 12.0,0) AS annual_guarantee,
        pk.rent_amount,
        pk.condo_amount,
        pk.light_amount,
        pk.water_amount,
        pk.phone_amount,
        pk.iptu_amount,
        pk.other_amount,
        pk.total_package_amount,
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
        old_duplicated_company_plan AS odcp
            ON pl.id = odcp.id_plan
            AND p.id_quintocred_company = odcp.id_company
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.company_plan AS cp
            ON p.id_quintocred_company = cp.id_company
            AND pl.id = cp.id_plan
            AND odcp.count_company_plan = 1
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.bussines_type AS bt
            ON pl.id_type = bt.id
    LEFT JOIN
        datalake_velo_clean.fiancavelo_activator AS a
            ON a.id = p.activator_value
    LEFT JOIN
        pack_values AS pk
        ON pk.id_propose = p.id
    LEFT JOIN
        first_payment AS fp
        ON fp.id_propose = p.id
    WHERE
        p.id NOT IN (SELECT id FROM datalake_rental_guarantee_platform_clean.propose)
