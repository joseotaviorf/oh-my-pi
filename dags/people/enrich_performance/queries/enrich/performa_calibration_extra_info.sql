WITH pei_latest_ranked AS (
  SELECT
    id_person_extra_info,
    id_person,
    id_meeting,
    id_rating_impact,
    id_rating_behavior,
    id_rating_leadership,
    dt_evaluation,
    ROW_NUMBER() OVER (
      PARTITION BY
        id_person_extra_info
      ORDER BY
        dt_effective_started DESC
    ) AS rn
  FROM
    datalake_pin_core_clean.people_extra_info
  WHERE
    information_type = 'Notas Talent'
    AND information_category = 'Notas Talent'
),
pei_latest AS (
  SELECT
    id_person_extra_info,
    id_person,
    id_meeting,
    id_rating_impact,
    id_rating_behavior,
    id_rating_leadership,
    dt_evaluation
  FROM
    pei_latest_ranked
  WHERE
    rn = 1
),
rating_value_ranked AS (
  SELECT
    r.id_rating_level,
    r.rating_description,
    b.numeric_rating,
    r.ts_updated,
    ROW_NUMBER() OVER (
      PARTITION BY
        b.id_rating_level
      ORDER BY
        b.dt_started DESC
    ) AS rn
  FROM
    datalake_pin_talent_clean.rating_level_translation r
  LEFT JOIN
    datalake_pin_talent_clean.rating_level_base b
      ON (b.id_rating_level = r.id_rating_level)
  WHERE
    r.language = 'US'
    AND b.dt_started <= DATE('{load_start_date}')
),
rating_value AS (
  SELECT
    id_rating_level,
    rating_description,
    numeric_rating,
    ts_updated
  FROM
    rating_value_ranked
  WHERE
    rn = 1
),
meeting_year AS (
  SELECT
    m.id_meeting,
    COALESCE(EXTRACT(YEAR FROM m.ts_meeting), EXTRACT(YEAR FROM m.ts_created)) AS value
  FROM
    datalake_pin_hr_review_clean.meeting m
)
SELECT
  pei.id_person_extra_info,
  im.person_number,
  m.id_meeting,
  meeting_year.value AS meeting_year,
  m.meeting_title,
  m.meeting_status_code,
  ci.rating_description AS impact_description,
  ci.numeric_rating AS impact_numeric,
  cb.rating_description AS behavior_description,
  cb.numeric_rating AS behavior_numeric,
  CASE
    WHEN meeting_year.value < 2026 THEN cl.rating_description
    ELSE NULL
  END AS leadership_description,
  CASE
    WHEN meeting_year < 2026 THEN cl.numeric_rating
    ELSE NULL
    END AS leadership_numeric,
  pei.dt_evaluation
FROM
  datalake_pin_core_clean.all_assignments aa
LEFT JOIN
  datalake_people.identifier_mapping im
    ON (im.id_assignment = aa.id_assignment)
LEFT JOIN
  pei_latest AS pei
    ON (aa.id_person = pei.id_person)
LEFT JOIN
  datalake_pin_hr_review_clean.meeting m
    ON (m.id_meeting = pei.id_meeting)
LEFT JOIN
  meeting_year
    ON meeting_year.id_meeting = m.id_meeting
LEFT JOIN
  datalake_pin_hr_review_clean.dashboard_template_translation dtl
    ON (m.id_dashboard_template = dtl.id_dashboard_template
      AND dtl.language = 'US')
LEFT JOIN
  rating_value ci
    ON (ci.id_rating_level = pei.id_rating_impact)
LEFT JOIN
  rating_value cb
    ON (cb.id_rating_level = pei.id_rating_behavior)
LEFT JOIN
  rating_value cl
    ON (cl.id_rating_level = pei.id_rating_leadership)
WHERE 1=1
  AND aa.assignment_status_type = 'INACTIVE'
  AND aa.is_primary
  AND DATE('{load_start_date}') BETWEEN TO_DATE(aa.dt_effective_started) AND TO_DATE(aa.dt_effective_ended)
  AND dtl.id_dashboard_template IN (300000008237707, 300000145965905)
  AND ci.rating_description IS NOT NULL
  AND cb.rating_description IS NOT NULL
