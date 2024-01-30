SELECT
  fct.sk_call,
  dct.sk_task,
  dct.queue_name,
  ROW_NUMBER() OVER (PARTITION BY fct.sk_call ORDER BY dct.ts_created NULLS LAST) AS task_order,
  LAG(dct.queue_name) OVER (PARTITION BY fct.sk_call ORDER BY dct.ts_created NULLS LAST) AS previous_department,
  LEAD(dct.queue_name) OVER (PARTITION BY fct.sk_call ORDER BY dct.ts_created NULLS LAST) AS next_department,
  dca.location AS company,
  LEAD(dca.location) OVER (PARTITION BY fct.sk_call ORDER BY dct.ts_created NULLS LAST) AS next_company,
  dca.email,
  LEAD(dca.email) OVER (PARTITION BY fct.sk_call ORDER BY dct.ts_created NULLS LAST) AS next_email
FROM dw_call.dim_call_task AS dct
INNER JOIN dw_call.fact_call_tasks AS fct
  ON fct.sk_task = dct.sk_task
LEFT JOIN dw_call.dim_call_agent AS dca
  ON fct.sk_agent = dca.sk_call_agent
LEFT JOIN dw_call.fact_calls AS fc
  ON fc.sk_call = fct.sk_call
WHERE
  fct.is_answered = TRUE
ORDER BY
  1 NULLS LAST,
  4 NULLS LAST