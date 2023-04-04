WITH propose_canceled_date AS (
  SELECT
    id_propose,
    MAX(CAST(ts_updated AS TIMESTAMP)) AS ts_ended
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
    MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_propose_started
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
    MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_waiting_new_docs
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
    MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_evaluation_started
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
    MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_rejected
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
    MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_sign_started
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
    MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_paid
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
    MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_activation
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
    MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_secured
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
    MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_activation_analysis
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
    MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_secure_pending
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
pack_values AS (
  SELECT
    pk.id_propose AS id_propose,
    SUM(COALESCE(pk.value,0)) AS total_package_amount
  FROM
    datalake_velo_clean.fiancavelo_packvalues AS pk
  WHERE
    pk.is_active
  GROUP BY
    1
),
propose_values AS (
  SELECT
    CONCAT(p.id, a.id, pl.id) AS id_propose_values,
    p.id AS id_propose,
    plt.name AS plan_type,
    COALESCE(pk.total_package_amount*pl.percent*0.01,0) AS monthly_guarantee
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
      AVG(prs.declared_income) AS avg_declared_income,
      SUM(prs.declared_income) AS total_declared_income
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
),
payments_metrics AS (
  SELECT
    id_propose,
    SUM(IF(dt_paid IS NOT NULL, due_amount, 0)) AS total_paid_amount,
    SUM(due_amount) AS total_expected_amount,
    SUM(IF(dt_paid IS NULL, due_amount, 0)) AS total_due_amount,
    -- CAST(NULL AS DOUBLE) AS lmi,
    COUNT(id_payment) AS total_payments,
    COUNT(IF(dt_paid IS NOT NULL, 1, 0)) AS total_payments_paid,
    COUNT(IF(dt_paid IS NULL AND dt_due < current_date(), 1, 0)) AS total_payments_expired,
    MAX(dt_paid) AS dt_last_payment
  FROM
    datalake_velo.payment
  GROUP BY 1
),
occurrence_metrics AS (
  SELECT
    id_propose,
    SUM(IF(paid_amount IS NOT NULL, paid_amount, 0)) AS total_occurrences_paid_amount,
    SUM(due_amount) AS total_occurrences_due_amount,
    COUNT(id_occurrence) AS total_occurrences,
    COUNT(ts_paid) AS occurrences_solved
  FROM
    datalake_velo.occurrence AS o
  GROUP BY 1
)
SELECT
  p.id AS id_propose,
  pv.id_propose_values AS id_propose_values,
  COALESCE(f.id_realestate, c.id_realestate) AS id_broker,
  h.id_house,
  p.id_realtor AS id_agent,
  f.id AS id_contract,
  pc.id_company AS id_propose_company,
  mc.id_primary_person,
  jk4.id_junk AS id_origin,
  jk1.id_junk AS id_propose_status,
  jk2.id_junk AS id_guarantee_status,
  jk3.id_junk AS id_propose_type,
  pm.count_persons_included,
  pm.percentage_income_from_primary_person,
  pm.avg_serasa_score,
  pm.avg_risk_score,
  pm.avg_declared_income,
  pm.total_declared_income,
  CAST(pv.monthly_guarantee / pm.total_declared_income AS DECIMAL(32,2)) AS dti,
  pym.total_paid_amount,
  pym.total_expected_amount,
  pym.total_due_amount,
  -- pym.lmi,
  om.total_occurrences_due_amount,
  om.total_occurrences_paid_amount,
  pym.total_payments,
  pym.total_payments_paid,
  pym.total_payments_expired,
  om.total_occurrences,
  om.occurrences_solved,
  f.id IS NOT NULL AS is_contract,
  IFNULL(DATEDIFF(COALESCE(DATE(pcd.ts_ended), f.dt_ended), DATE(f.dt_begin)) <= 10, False) AS is_grace_period_cancelled,
  pym.dt_last_payment,
  DATE(f.dt_begin) AS dt_contract_started,
  COALESCE(DATE(pcd.ts_ended), f.dt_ended) AS dt_ended,
  sd.ts_propose_started,
  wndd.ts_waiting_new_docs,
  esd.ts_evaluation_started,
  rd.ts_rejected,
  ssd.ts_sign_started,
  pd.ts_paid,
  ad.ts_activation,
  sed.ts_secured,
  aad.ts_activation_analysis,
  spd.ts_secure_pending
FROM
  datalake_velo_clean.fiancavelo_propose AS p
LEFT JOIN
  datalake_velo_clean.fiancavelo_fianca AS f
    ON f.id_propose = p.id
LEFT JOIN
  datalake_velo_clean.fiancavelo_colaborador AS c
    ON c.id_user = p.id_realtor
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
lEFT JOIN
  payments_metrics AS pym
    ON pym.id_propose = p.id
lEFT JOIN
  occurrence_metrics AS om
    ON om.id_propose = p.id
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
  datalake_velo.junk AS jk4
    ON jk4.id_lvl_1 = IF(pc.id_propose IS NOT NULL, 1, 2)
      AND jk4.desc_master_type = 'Origin'
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
      AND mc.rn = 1 -- Gets only the latest updated id
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
