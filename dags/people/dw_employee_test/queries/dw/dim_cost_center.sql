WITH
-- Base query: Join all tables and calculate validity dates considering all sources
cost_center_base AS (
  SELECT DISTINCT
    org.id_organization,
    ar.id_person AS bp_person_number,
    t.name AS cost_center_name,
    org.cost_center_code,
    org.business,
    org.product,
    org.brand,
    org.vertical,
    org.structure,
    org.team,
    org.chapter,
    org.line,
    org.name_owner_l1,
    org.name_owner_l2,
    org.name_owner_l3,
    org.headcount_type,
    CASE class.status
      WHEN 'A' THEN TRUE
      WHEN 'I' THEN FALSE
    END AS is_active,
    LEAST(
      TO_DATE(org.dt_effective_started),
      TO_DATE(class.dt_effective_started),
      COALESCE(TO_DATE(t.dt_effective_started), TO_DATE(org.dt_effective_started))
    ) AS dt_valid_from,
    GREATEST(
      COALESCE(TO_DATE(org.dt_effective_ended), DATE('9999-12-31')),
      COALESCE(TO_DATE(class.dt_effective_ended), DATE('9999-12-31')),
      COALESCE(TO_DATE(t.dt_effective_ended), DATE('9999-12-31'))
    ) AS dt_valid_to
  FROM
    datalake_pin_core_clean.all_organization_units AS org
  LEFT JOIN 
    datalake_pin_core_clean.organization_unit_classification AS class
      ON org.id_organization = class.id_organization
      AND org.dt_effective_started = class.dt_effective_started
      AND org.dt_effective_ended = class.dt_effective_ended
  LEFT JOIN 
    datalake_pin_core_clean.organization_unit_translation AS t
      ON t.id_organization = org.id_organization
      AND t.language = 'PTB'
      AND org.dt_effective_started >= t.dt_effective_started
      AND org.dt_effective_started < COALESCE(t.dt_effective_ended, DATE('9999-12-31'))
  LEFT JOIN
    datalake_pin_core_clean.assignment_responsibility AS ar
      ON ar.id_organization = org.id_organization
  WHERE 
    class.classification_code = 'DEPARTMENT'
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY org.id_organization, org.dt_effective_started
      ORDER BY ar.id_person DESC NULLS LAST
    ) = 1
),
-- Detect attribute changes using hash and consolidate consecutive periods with identical attributes
cost_center_with_hash AS (
  SELECT
    *,
    MD5(CONCAT_WS('|',
      CAST(bp_person_number AS STRING),
      CAST(cost_center_name AS STRING),
      CAST(cost_center_code AS STRING),
      CAST(business AS STRING),
      CAST(product AS STRING),
      CAST(brand AS STRING),
      CAST(vertical AS STRING),
      CAST(structure AS STRING),
      CAST(team AS STRING),
      CAST(chapter AS STRING),
      CAST(line AS STRING),
      CAST(name_owner_l1 AS STRING),
      CAST(name_owner_l2 AS STRING),
      CAST(name_owner_l3 AS STRING),
      CAST(headcount_type AS STRING),
      CAST(is_active AS STRING)
    )) AS attributes_hash
  FROM
    cost_center_base
),
-- Group consecutive periods with identical attributes
cost_center_groups AS (
  SELECT
    *,
    SUM(CASE 
      WHEN LAG(attributes_hash) OVER (
        PARTITION BY id_organization
        ORDER BY dt_valid_from
      ) <> attributes_hash
        OR LAG(attributes_hash) OVER (
          PARTITION BY id_organization
          ORDER BY dt_valid_from
        ) IS NULL
      THEN 1
      ELSE 0
    END) OVER (
      PARTITION BY id_organization
      ORDER BY dt_valid_from
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS change_group
  FROM
    cost_center_with_hash
),
-- Consolidate consecutive periods with identical attributes into single SCD Type 2 versions
consolidated_cost_centers AS (
  SELECT
    id_organization,
    bp_person_number,
    cost_center_name,
    cost_center_code,
    business,
    product,
    brand,
    vertical,
    structure,
    team,
    chapter,
    line,
    name_owner_l1,
    name_owner_l2,
    name_owner_l3,
    headcount_type,
    is_active,
    MIN(dt_valid_from) AS dt_valid_from,
    MAX(dt_valid_to) AS dt_valid_to
  FROM
    cost_center_groups
  GROUP BY
    id_organization,
    change_group,
    bp_person_number,
    cost_center_name,
    cost_center_code,
    business,
    product,
    brand,
    vertical,
    structure,
    team,
    chapter,
    line,
    name_owner_l1,
    name_owner_l2,
    name_owner_l3,
    headcount_type,
    is_active
  )

SELECT
  MD5(CONCAT_WS('|', CAST(ccc.id_organization AS STRING), CAST(ccc.dt_valid_from AS STRING))) AS sk_cost_center_version,
  ccc.cost_center_code,
  ccc.cost_center_name,
  ccc.bp_person_number,
  ccc.business,
  ccc.product,
  ccc.brand,
  ccc.vertical,
  ccc.structure,
  ccc.team,
  ccc.chapter,
  ccc.line,
  ccc.name_owner_l1,
  ccc.name_owner_l2,
  ccc.name_owner_l3,
  ccc.headcount_type,
  ccc.is_active,
  ROW_NUMBER() OVER (
    PARTITION BY ccc.id_organization
    ORDER BY ccc.dt_valid_from
  ) AS version,
  ccc.dt_valid_from,
  LEAST(
    COALESCE(
      LEAD(ccc.dt_valid_from) OVER (
        PARTITION BY ccc.id_organization
        ORDER BY ccc.dt_valid_from
      ) - INTERVAL '1 DAY',
      DATE('9999-12-31')
    ),
    COALESCE(ccc.dt_valid_to, DATE('9999-12-31'))
  ) AS dt_valid_to,
  (
    LEAD(ccc.dt_valid_from) OVER (
      PARTITION BY ccc.id_organization
      ORDER BY ccc.dt_valid_from
    ) IS NULL
  ) AS is_current,
  NOW() AS ts_load
FROM
  consolidated_cost_centers AS ccc