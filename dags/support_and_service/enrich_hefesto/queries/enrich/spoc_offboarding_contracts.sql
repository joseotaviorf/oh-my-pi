WITH queue_cte AS (
  SELECT DISTINCT 
    id_queue,
    queue_friendly_name
  FROM 
    datalake_hefesto_clean.queue
  )
SELECT 
  wp.id_portfolio,
  INT(COALESCE(wpu.origin_identifier, CAST(wp.id_contract AS string))) AS id_contract,
  INT(COALESCE(CAST(get_json_object(wpu.metadata, '$.termination_id') AS string), wp.id_entity_origin)) AS id_termination,
  wp.id_worker,
  w.id_worker_twilio,
  MD5(a.email) AS id_analyst,
  wp.id_user,
  wpu.user_persona,
  a.email AS worker_email,
  wpu.status AS portfolio_status,
  a.organization AS analyst_organization,
  wp.entity_origin,
  wpu.ts_updated
FROM 
  datalake_hefesto_clean.worker_portfolio_unit wpu
LEFT JOIN
  datalake_hefesto_clean.worker_portfolio AS wp 
    ON wpu.worker_portfolio_id = wp.id_portfolio
LEFT JOIN
  (queue_cte) AS q 
    ON wp.id_queue = q.id_queue
LEFT JOIN
  datalake_hefesto_clean.worker AS w 
    ON wp.id_worker = w.id_worker
LEFT JOIN
  datalake_support_users.analysts AS a 
    ON a.email = w.email
WHERE 
  wp.entity_origin = 'OFFBOARDING'
  AND queue_friendly_name = 'CX Off Manager'