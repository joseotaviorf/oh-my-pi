WITH propose_canceled_date AS (
  SELECT
    id_propose,
    MAX(DATE(CAST(ts_updated AS TIMESTAMP))) AS dt_ended
  FROM
    datalake_velo_clean.fiancavelo_proposehistory
  WHERE
    id_text_key = 10 --10 indicates that the propose has ended
    AND id_type_history = 1 -- alteration by the system
  GROUP BY
    1 -- some proposes can have multiple same status
),
propose_started_date AS (
  SELECT
    id_propose,
    MAX(DATE(CAST(ts_updated AS TIMESTAMP))) AS dt_propose_started
  FROM
    datalake_velo_clean.fiancavelo_proposehistory
  WHERE
    id_text_key = 2 --2 indicates that the propose has started
    AND id_type_history = 1 -- alteration by the system
  GROUP BY
    1 -- some proposes can have multiple same status
),
propose_waiting_new_docs_date AS (
  SELECT
    id_propose,
    MAX(DATE(CAST(ts_updated AS TIMESTAMP))) AS dt_waiting_new_docs
  FROM
    datalake_velo_clean.fiancavelo_proposehistory
  WHERE
    id_text_key = 3 -- indicates that the propose is waiting for more docs
    AND id_type_history = 1 -- alteration by the system
  GROUP BY
    1 -- some proposes can have multiple same status
),
propose_evaluation_started_date AS (
  SELECT
    id_propose,
    MAX(DATE(CAST(ts_updated AS TIMESTAMP))) AS dt_evaluation_started
  FROM
    datalake_velo_clean.fiancavelo_proposehistory
  WHERE
    id_text_key = 4 -- indicates that the evaluation has started
    AND id_type_history = 1 -- alteration by the system
  GROUP BY
    1 -- some proposes can have multiple same status
),
propose_rejected_date AS (
  SELECT
    id_propose,
    MAX(DATE(CAST(ts_updated AS TIMESTAMP))) AS dt_rejected
  FROM
    datalake_velo_clean.fiancavelo_proposehistory
  WHERE
    id_text_key = 5 -- indicates that the propose was rejected
    AND id_type_history = 1 -- alteration by the system
  GROUP BY
    1 -- some proposes can have multiple same status
),
propose_sign_started_date AS (
  SELECT
    id_propose,
    MAX(DATE(CAST(ts_updated AS TIMESTAMP))) AS dt_sign_started
  FROM
    datalake_velo_clean.fiancavelo_proposehistory
  WHERE
    id_text_key = 6 -- indicates that the sign has started
    AND id_type_history = 1 -- alteration by the system
  GROUP BY
    1 -- some proposes can have multiple same status
),
propose_paid_date AS (
  SELECT
    id_propose,
    MAX(DATE(CAST(ts_updated AS TIMESTAMP))) AS dt_paid
  FROM
    datalake_velo_clean.fiancavelo_proposehistory
  WHERE
    id_text_key = 7 -- indicates that the propose has been paid
    AND id_type_history = 1 -- alteration by the system
  GROUP BY
    1 -- some proposes can have multiple same status
),
propose_activation_date AS (
  SELECT
    id_propose,
    MAX(DATE(CAST(ts_updated AS TIMESTAMP))) AS dt_activation
  FROM
    datalake_velo_clean.fiancavelo_proposehistory
  WHERE
    id_text_key = 8 -- indicates that the propose is active
    AND id_type_history = 1 -- alteration by the system
  GROUP BY
    1 -- some proposes can have multiple same status
),
propose_secured_date AS (
  SELECT
    id_propose,
    MAX(DATE(CAST(ts_updated AS TIMESTAMP))) AS dt_secured
  FROM
    datalake_velo_clean.fiancavelo_proposehistory
  WHERE
    id_text_key = 9 -- indicates that the propose is secured
    AND id_type_history = 1 -- alteration by the system
  GROUP BY
    1 -- some proposes can have multiple same status
),
propose_activation_analysis_date AS (
  SELECT
    id_propose,
    MAX(DATE(CAST(ts_updated AS TIMESTAMP))) AS dt_activation_analysis
  FROM
    datalake_velo_clean.fiancavelo_proposehistory
  WHERE
    id_text_key = 11 -- indicates that the propose is active but in analysis
    AND id_type_history = 1 -- alteration by the system
  GROUP BY
    1 -- some proposes can have multiple same status
),
propose_secure_pending_date AS (
  SELECT
    id_propose,
    MAX(DATE(CAST(ts_updated AS TIMESTAMP))) AS dt_secure_pending
  FROM
    datalake_velo_clean.fiancavelo_proposehistory
  WHERE
    id_text_key = 12 -- indicates that the propose is waiting to be secured
    AND id_type_history = 1 -- alteration by the system
  GROUP BY
    1 -- some proposes can have multiple same status
),
propose_company AS (
  SELECT
    id_propose,
    id_company,
    ROW_NUMBER() OVER(PARTITION BY id_propose ORDER BY ts_updated DESC) AS rn
  FROM
    datalake_velo_clean.fiancavelo_proposecompany
),
house AS (
  SELECT
    o.id_propose AS id_propose,
    py.id AS id_house,
    ROW_NUMBER() OVER (PARTITION BY o.id_propose ORDER BY o.ts_updated DESC, o.id_property DESC) AS rn -- House update order, there was a bug in product that created a new id for every update. To solve, order by the latest update date.
  FROM
    datalake_velo_clean.fiancavelo_object AS o
  LEFT JOIN
    datalake_velo_clean.fiancavelo_property AS py
      ON py.id = o.id_property
        AND py.is_active
  WHERE
    o.is_active
),
propose_values AS (
  SELECT
    CONCAT(p.id, a.id, pl.id) AS id_propose_values,
    p.id AS id_propose
  FROM
    datalake_velo_clean.fiancavelo_propose AS p
  LEFT JOIN
    datalake_velo_clean.fiancavelo_activator AS a
      ON a.id = p.id_activator
  LEFT JOIN
    datalake_velo_clean.fiancavelo_plans AS pl
      ON pl.id = p.id_plan
),
person_score AS (
  SELECT
    c.id AS id_score_consultation,
    c.id_person,
    c.value AS score_value,
    c.risk,
    r.name AS risk_classification,
    c.id_bureau,
    b.name AS bureau_name,
    vp.value AS score_personal_value,
    vp.declared AS declared_income,
    vp.requested AS requested_income,
    ROW_NUMBER() OVER(PARTITION BY c.id_person ORDER BY c.ts_updated DESC, c.ts_inserted DESC) AS rn
  FROM
    datalake_velo_clean.veloscore_consultations AS c
  LEFT JOIN
    datalake_velo_clean.veloscore_bureau AS b
      ON b.id = c.id_bureau
  LEFT JOIN
    datalake_velo_clean.veloscore_personal AS vp
      ON vp.consultations = c.id
  LEFT JOIN
    datalake_velo_clean.veloscore_risk AS r
      ON r.id = c.risk
),
main_client AS (
  SELECT
      pp.id_propose,
      pp.id_person AS id_primary_person,
      prs.declared_income,
      ROW_NUMBER() OVER(PARTITION BY pp.id_propose ORDER BY pp.ts_updated DESC) AS rn
    FROM
      datalake_velo_clean.fiancavelo_proposeperson AS pp
    LEFT JOIN
        person_score AS prs
        ON prs.id_person = pp.id_person
          AND prs.rn = 1
    WHERE
      pp.is_active
        AND pp.id_type = 1 -- bringing only main IQ
),
persons_metrics AS (
  SELECT
      pp.id_propose,
      MAX(mc.declared_income) / SUM(prs.declared_income) AS percentage_income_from_primary_person,
      COUNT(cp.id) AS count_persons_included,
      AVG(prs.score_value) AS avg_serasa_score,
      AVG(prs.risk) AS avg_risk_score,
      AVG(prs.declared_income) AS avg_declared_income
  FROM
      datalake_velo_clean.fiancavelo_proposeperson AS pp
  LEFT JOIN
      datalake_velo_clean.clientes_person AS cp
      ON cp.id = pp.id_person
  LEFT JOIN
      person_score AS prs
      ON prs.id_person = cp.id
        AND prs.rn = 1
  LEFT JOIN
      main_client AS mc
      ON mc.id_propose = pp.id_propose
      AND mc.rn = 1
  GROUP BY 1
)
SELECT
  p.id AS id_propose,
  pv.id_propose_values AS id_propose_values,
  f.id_realestate AS id_broker,
  h.id_house,
  p.id_realtor AS id_agent,
  f.id AS id_contract,
  pc.id_company AS id_propose_company,
  mc.id_primary_person,
  CASE
    WHEN pc.id_propose IS NOT NULL THEN 1
    ELSE 2
  END AS id_origin, -- be sure to match the junk table
  jk1.id_junk AS id_propose_status,
  jk2.id_junk AS id_guarantee_status,
  jk3.id_junk AS id_propose_type,
  pm.count_persons_included,
  pm.percentage_income_from_primary_person,
  pm.avg_serasa_score,
  pm.avg_risk_score,
  pm.avg_declared_income,
  f.id IS NOT NULL AS is_contract,
  DATE(f.dt_begin) AS dt_contract_started,
  COALESCE(DATE(pcd.dt_ended), f.dt_ended) AS dt_ended,
  sd.dt_propose_started,
  wndd.dt_waiting_new_docs,
  esd.dt_evaluation_started,
  rd.dt_rejected,
  ssd.dt_sign_started,
  pd.dt_paid,
  ad.dt_activation,
  sed.dt_secured,
  aad.dt_activation_analysis,
  spd.dt_secure_pending
FROM
  datalake_velo_clean.fiancavelo_propose AS p
LEFT JOIN
  datalake_velo_clean.fiancavelo_fianca AS f
    ON f.id_propose = p.id
LEFT JOIN
  propose_canceled_date AS pcd
    ON pcd.id_propose = p.id
LEFT JOIN
  propose_company AS pc
    ON pc.id_propose = p.id
      AND pc.rn = 1
lEFT JOIN
  persons_metrics AS pm
    ON pm.id_propose = p.id
LEFT JOIN
  datalake_velo.junk AS jk1
    ON jk1.id_lvl_1 = p.id_status
      AND jk1.desc_master_type = 'Propose Status'
LEFT JOIN
  datalake_velo.junk AS jk2
    ON jk2.id_lvl_1 = f.id_status
      AND jk2.desc_master_type = 'Guarantee Status'
LEFT JOIN
  datalake_velo.junk AS jk3
    ON jk3.id_lvl_1 = p.id_type
      AND jk3.desc_master_type = 'Propose Type'
LEFT JOIN
  house AS h
    ON h.id_propose = p.id
      AND h.rn = 1 -- Gets only the latest updated id
LEFT JOIN
  propose_values AS pv
    ON pv.id_propose = p.id
LEFT JOIN
  main_client AS mc
    ON mc.id_propose = p.id
LEFT JOIN
  propose_started_date AS sd
    ON sd.id_propose = p.id
LEFT JOIN
  propose_waiting_new_docs_date AS wndd
    ON wndd.id_propose = p.id
LEFT JOIN
  propose_evaluation_started_date AS esd
    ON esd.id_propose = p.id
LEFT JOIN
  propose_rejected_date AS rd
    ON rd.id_propose = p.id
LEFT JOIN
  propose_sign_started_date AS ssd
    ON ssd.id_propose = p.id
LEFT JOIN
  propose_paid_date AS pd
    ON pd.id_propose = p.id
LEFT JOIN
  propose_activation_date AS ad
    ON ad.id_propose = p.id
LEFT JOIN
  propose_secured_date AS sed
    ON sed.id_propose = p.id
LEFT JOIN
  propose_activation_analysis_date AS aad
    ON aad.id_propose = p.id
LEFT JOIN
  propose_secure_pending_date AS spd
    ON spd.id_propose = p.id
WHERE
  p.is_active
