WITH all_inspection_sync AS (
  SELECT
    id_inspection,
    id_house,
    MIN(ia.ts_last_synced) AS ts_synced
  FROM datalake_ebdb_clean.inspection_aud AS ia
  WHERE
    status = 'Revisada'
    AND NOT ts_last_synced IS NULL
    AND (
      type = 'Saida' OR type = 'Constatação'
    )
  GROUP BY
    1,
    2
), comments AS (
  SELECT
    insp.id_contract, /* insp.type, */
    ii.id_inspection,
    insp.is_owner_approved,
    COUNT(CASE WHEN NOT ii.comment IS NULL THEN id_inspection ELSE NULL END) AS n_comments_vt,
    COUNT(CASE WHEN NOT ii.owner_comment IS NULL THEN id_contract ELSE NULL END) AS n_comments_pp,
    COUNT(CASE WHEN NOT ii.tenant_comment IS NULL THEN id_contract ELSE NULL END) AS n_comments_iq
  FROM datalake_ebdb_clean.inspection_item AS ii
  LEFT JOIN datalake_ebdb_clean.inspection AS insp
    ON ii.id_inspection = insp.id
  WHERE
    (
      insp.type = 'Saida' OR insp.type = 'Constatação'
    )
  GROUP BY
    1,
    2,
    3
), crm_info AS (
  SELECT
    fit.sk_inspection,
    fit.sk_contract,
    fit.action_type,
    TO_TIMESTAMP(SUBSTR(CAST(dit.ts_start AS STRING), 1, 10), 'yyyy-MM-dd') AS dt_start,
    TO_TIMESTAMP(SUBSTR(CAST(dit.ts_completed AS STRING), 1, 10), 'yyyy-MM-dd') AS dt_completed,
    MAX(
      CASE
        WHEN (
          action_type = 'REALIZE' OR action_type = 'RESOLVE'
        )
        THEN action_user_name
        ELSE NULL
      END
    ) AS nome_analista
  FROM dw_crm.fact_inspection_tasks AS fit
  LEFT JOIN dw_crm.dim_inspection_task AS dit
    ON fit.sk_task = dit.sk_task
  WHERE
    dit.type = 'AnaliseVistoriaSaida'
  GROUP BY
    1,
    2,
    3,
    4,
    5
  ORDER BY
    1 DESC
), users AS (
  SELECT DISTINCT
    p.sk_contract,
    p.sk_contract_person,
    p.sk_personal_document,
    p.contract_role,
    p.is_first_contract,
    p.is_last_contract,
    u.email,
    COALESCE(u.sk_user, p.sk_user) AS sk_user
  FROM dw_rent.fact_contract_people AS p
  LEFT JOIN dw_public.dim_user AS u
    ON p.sk_personal_document = u.cpf
  WHERE
    COALESCE(u.sk_user, p.sk_user) > 0 AND NOT COALESCE(u.sk_user, p.sk_user) IS NULL
), nps_onb AS (
  SELECT
    dp.sk_contract,
    dp.sk_user,
    dp.sk_personal_document,
    CASE
      WHEN dp.sk_answered_date < 0 OR dp.sk_answered_date IS NULL
      THEN NULL
      ELSE TO_TIMESTAMP(CAST(dp.sk_answered_date AS STRING), CAST('yyyyMMdd' AS STRING))
    END AS dt_nps_answer,
    dp.sk_answered_date,
    dp.sk_nps_answer,
    dp.sk_nps_campaign,
    dp.sk_answered_date,
    dp.score,
    CASE
      WHEN dp.score >= 9
      THEN 100.0
      WHEN dp.score >= 7
      THEN 0.0
      WHEN dp.score >= 0
      THEN -100.0
      ELSE NULL
    END AS agg_score,
    LAST_VALUE(
      CASE
        WHEN dp.sk_answered_date < 0 OR dp.sk_answered_date IS NULL
        THEN NULL
        ELSE TO_TIMESTAMP(CAST(dp.sk_answered_date AS STRING), CAST('yyyyMMdd' AS STRING))
      END
    ) OVER (PARTITION BY dp.sk_user, c.sk_contract ORDER BY dp.sk_answered_date NULLS LAST, dp.score DESC rows BETWEEN UNBOUNDED preceding AND UNBOUNDED following) AS last_date,
    LAST_VALUE(dp.score) OVER (PARTITION BY dp.sk_user, c.sk_contract ORDER BY dp.sk_answered_date NULLS LAST, dp.score DESC rows BETWEEN UNBOUNDED preceding AND UNBOUNDED following) AS last_score
  FROM dw_tracksale.fact_nps_dispatches AS dp
  LEFT JOIN dw_tracksale.dim_nps_campaign AS camp
    ON dp.sk_nps_campaign = camp.sk_nps_campaign
  LEFT JOIN users AS u
    ON dp.sk_user = u.sk_user
  LEFT JOIN dw_rent.dim_contract AS c
    ON u.sk_contract = c.sk_contract
    AND CASE
      WHEN dp.sk_answered_date < 0 OR dp.sk_answered_date IS NULL
      THEN NULL
      ELSE TO_TIMESTAMP(CAST(dp.sk_answered_date AS STRING), CAST('yyyyMMdd' AS STRING))
    END BETWEEN COALESCE(c.ts_signature, c.dt_start) AND COALESCE(c.dt_annulment, CURRENT_DATE)
  WHERE
    camp.metric_group LIKE '%off%'
)
SELECT
  fib.sk_contract,
  fib.sk_inspection,
  ais.id_house,
  dc.is_b2b,
  du.nome,
  t.dt_termination,
  TO_TIMESTAMP(CAST(CASE
    WHEN fib.sk_booking_inspected_date < 0
    THEN NULL
    ELSE fib.sk_booking_inspected_date
  END AS STRING), 'yyyyMMdd'),
  TO_TIMESTAMP(SUBSTR(CAST(ais.ts_synced AS STRING), 1, 10), 'yyyy-MM-dd') AS dt_synced,
  ci.dt_start,
  ci.dt_completed,
  dt.ts_termination_finished,
  c.n_comments_vt,
  c.n_comments_pp,
  ci.nome_analista,
  c.is_owner_approved,
  dhl.house_total_area AS metragem,
  dhl.is_house_furnished AS mobiliado,
  MAX(nps.last_date) AS dt_nps_answer,
  AVG(CASE WHEN u.contract_role = 'tenant' THEN last_score ELSE NULL END) AS nps_iq,
  AVG(CASE WHEN u.contract_role = 'landlord' THEN last_score ELSE NULL END) AS nps_pp,
  region_info.regional_inspection,
  region_info.city_name,
  ci.action_type
FROM dw_public.fact_inspection_bookings AS fib
LEFT JOIN dw_public.dim_inspection AS di
  ON fib.sk_inspection = di.sk_inspection
LEFT JOIN dw_rent.dim_contract AS dc
  ON fib.sk_contract = dc.sk_contract
LEFT JOIN datalake_terminator_clean.termination AS t
  ON t.id_contract = dc.sk_contract
LEFT JOIN datalake_offboarding.contract_termination AS dt
  ON dc.sk_contract = dt.id_contract
LEFT JOIN all_inspection_sync AS ais
  ON ais.id_inspection = fib.sk_inspection
LEFT JOIN comments AS c
  ON fib.sk_inspection = c.id_inspection
LEFT JOIN dw_rent.dim_house_listing AS dhl
  ON ais.id_house = dhl.id_house
LEFT JOIN crm_info AS ci
  ON fib.sk_inspection = ci.sk_inspection
LEFT JOIN users AS u
  ON dc.sk_contract = u.sk_contract
LEFT JOIN (
  SELECT DISTINCT
    sk_user,
    sk_contract,
    last_date,
    last_score
  FROM nps_onb
) AS nps
  ON u.sk_user = nps.sk_user AND u.sk_contract = nps.sk_contract
LEFT JOIN dw_public.dim_user AS du
  ON du.sk_user = fib.sk_inspector
LEFT JOIN dw_rent.fact_house_listings AS fact_house_listings
  ON dhl.sk_house_listing = fact_house_listings.sk_house_listing
LEFT JOIN dw_public.dim_region AS region_info
  ON fact_house_listings.sk_region = CAST(region_info.sk_region AS BIGINT)
WHERE
  NOT ts_synced IS NULL
  AND (
    di.type = 'Saida' OR di.type = 'Constatação'
  )
  AND TO_TIMESTAMP(CAST(CASE
    WHEN fib.sk_booking_inspected_date < 0
    THEN NULL
    ELSE fib.sk_booking_inspected_date
  END AS STRING), 'yyyyMMdd') >= (
    (
      DATE(
        ADD_MONTHS(CAST(DATE_TRUNC('MONTH', DATE_TRUNC('DAY', CURRENT_TIMESTAMP())) AS TIMESTAMP), -3)
      )
    )
  )
GROUP BY
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  21,
  22,
  23
ORDER BY
  6 DESC