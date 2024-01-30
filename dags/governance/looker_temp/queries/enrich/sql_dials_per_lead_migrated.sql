WITH out_base AS (
  SELECT
    id_prospect_reference AS id_lead,
    COUNT(c.id) AS number_of_calls_per_lead
  FROM datalake_wololo_clean.contact AS c
  GROUP BY
    1
), in_base AS (
  SELECT
    CAST(ct2.id_origin AS BIGINT) AS id_lead,
    SUM(cpt.number_of_calls_per_task) AS number_of_calls_per_lead
  FROM (
    SELECT
      id,
      MAX(
        CAST(CONCAT(CAST(year AS STRING), '-', CAST(month AS STRING), '-', CAST(day AS STRING)) AS DATE)
      ) AS max_dt
    FROM datalake_crm_clean.tasks
    GROUP BY
      1
  ) AS ct
  JOIN datalake_crm_clean.tasks AS ct2
    ON ct2.id = ct.id
    AND CAST(CONCAT(CAST(ct2.year AS STRING), '-', CAST(ct2.month AS STRING), '-', CAST(ct2.day AS STRING)) AS DATE) = ct.max_dt
  JOIN calls_per_task AS cpt
    ON cpt.id_task = ct.id
  GROUP BY
    1
), calls_per_task AS (
  SELECT
    id_task,
    COUNT(DISTINCT events.event_date) AS number_of_calls_per_task
  FROM datalake_autodialer_clean.task_reference_inbound_event_histories AS events
  WHERE
    events.task_reference_event_origin = 'WEB_HOOK_BEFORE_NOTIFICATION'
  GROUP BY
    1
)
SELECT
  COALESCE(i.id_lead, o.id_lead) AS id_lead,
  COALESCE(i.number_of_calls_per_lead, 0) AS quintoandar_dials,
  COALESCE(o.number_of_calls_per_lead, 0) AS action_line_dials,
  COALESCE(i.number_of_calls_per_lead, 0) + COALESCE(o.number_of_calls_per_lead, 0) AS total_dials
FROM in_base AS i
FULL OUTER JOIN out_base AS o
  ON o.id_lead = i.id_lead