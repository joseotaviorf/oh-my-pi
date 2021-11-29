WITH
  termination_aud
  AS
  (
    SELECT
      id,
      id_contract,
      rev,
      rev_end,
      status,
      dt_termination,
      ts_updated
    FROM datalake_terminator_clean_prod.termination_aud
  ),
  terminations_finished
  AS
  (
    SELECT
      id,
      min(ts_updated) AS ts_termination_finished
    FROM termination_aud ta
    WHERE ta.status = 'DONE'
    GROUP BY 1
  ),
  terminations_modified
  AS
  (
    SELECT
      ta1.id,
    max(ta2.ts_updated)::date as dt_last_updated
    FROM termination_aud ta1
      INNER JOIN termination_aud ta2
      ON ta2.rev = ta1.rev_end
        AND ta2.id = ta1.id
    WHERE ta1.rev_end IS NOT NULL
      AND ta1.dt_termination != ta2.dt_termination
    GROUP BY 1
  ),
  keys
  AS
  (
    SELECT
      id_contract,
      id,
      tenant_keys_location,
      owner_keys_location
    FROM datalake_terminator_clean_prod.termination
  ),
  completed_utility_attachments
  AS
  (
    SELECT
    DISTINCT id_termination,
    listagg(type, ', ') within group (order by id_termination, type) as completed_utility_attachments
    FROM datalake_terminator_clean_prod.utility_bill 
    WHERE status = 'COMPLETED'
    GROUP BY id_termination
  ),
  pending_utility_attachments
  AS
  (
    SELECT
    DISTINCT id_termination,
    listagg(type, ', ') within group (order by id_termination, type) as pending_utility_attachments
    FROM datalake_terminator_clean_prod.utility_bill 
    WHERE status = 'PENDING'
    GROUP BY id_termination
  ),
  utility_in_condominium
  AS
  (
    SELECT
    DISTINCT id_termination,
    listagg(type, ', ') within group (order by id_termination, type) as utility_bill_in_condominium
    FROM datalake_terminator_clean_prod.utility_bill 
    WHERE is_included_condominium is TRUE
    GROUP BY id_termination
  ),
  total_nps
  AS
  (
    SELECT
    DISTINCT t.id,
    100.0*(COUNT(DISTINCT CASE WHEN fnd.score BETWEEN 9 AND 10 THEN fnd.sk_nps_answer END)
    -COUNT(DISTINCT CASE WHEN fnd.score BETWEEN 0 AND 6 THEN fnd.sk_nps_answer END)
    )/NULLIF(COUNT(DISTINCT CASE WHEN fnd.sk_nps_answer > 0 THEN fnd.sk_nps_answer END),0) AS NPS
    FROM datalake_terminator_clean_prod.termination t
      JOIN tracksale.fact_nps_dispatches fnd
      ON fnd.sk_contract = t.id_contract
      LEFT JOIN tracksale.dim_nps_campaign dnc
      ON dnc.sk_nps_campaign = fnd.sk_nps_campaign
    WHERE t.status <> 'CANCELED'
    AND dnc.metric_group IN ('iqoffboarding', 'ppoffboarding', 'offboarding')
    GROUP BY t.id
  ),
  iq_nps
  AS
  (
    SELECT
    DISTINCT t.id,
    (CASE WHEN dnc.customer_type = 'IQ' THEN 100.0*(COUNT(DISTINCT CASE WHEN fnd.score BETWEEN 9 AND 10 THEN fnd.sk_nps_answer END)
    -COUNT(DISTINCT CASE WHEN fnd.score BETWEEN 0 AND 6 THEN fnd.sk_nps_answer END)
    )/NULLIF(COUNT(DISTINCT CASE WHEN fnd.sk_nps_answer > 0 THEN fnd.sk_nps_answer END),0)END) AS IQ_NPS
    FROM datalake_terminator_clean_prod.termination t
      JOIN tracksale.fact_nps_dispatches fnd
      ON fnd.sk_contract = t.id_contract
      LEFT JOIN tracksale.dim_nps_campaign dnc
      ON dnc.sk_nps_campaign = fnd.sk_nps_campaign
    WHERE t.status <> 'CANCELED'
    AND dnc.metric_group IN ('iqoffboarding', 'offboarding')
    AND dnc.customer_type = 'IQ'
    GROUP BY t.id, dnc.customer_type
  ),
  pp_nps
  AS
  (
    SELECT
    DISTINCT t.id,
    (CASE WHEN dnc.customer_type = 'PP' THEN 100.0*(COUNT(DISTINCT CASE WHEN fnd.score BETWEEN 9 AND 10 THEN fnd.sk_nps_answer END)
    -COUNT(DISTINCT CASE WHEN fnd.score BETWEEN 0 AND 6 THEN fnd.sk_nps_answer END)
    )/NULLIF(COUNT(DISTINCT CASE WHEN fnd.sk_nps_answer > 0 THEN fnd.sk_nps_answer END),0)END) AS PP_NPS
    FROM datalake_terminator_clean_prod.termination t
      JOIN tracksale.fact_nps_dispatches fnd
      ON fnd.sk_contract = t.id_contract
      LEFT JOIN tracksale.dim_nps_campaign dnc
      ON dnc.sk_nps_campaign = fnd.sk_nps_campaign
    WHERE t.status <> 'CANCELED'
    AND dnc.metric_group IN ('ppoffboarding', 'offboarding')
    AND dnc.customer_type = 'PP'
    GROUP BY t.id, dnc.customer_type
  ),
  last_inspection_synch
  AS(
    SELECT
    DISTINCT t.id,
    max(fib.sk_inspected_date) AS dt_last_inspection_synch
    FROM datalake_terminator_clean_prod.termination t
    JOIN fact_inspection_bookings fib
        ON t.id_contract = fib.sk_contract
    WHERE t.status <> 'CANCELED'
    AND sk_inspected_date <> -1
    GROUP BY t.id
  ),
  termination_finished_user 
  AS 
  (
  SELECT
    id AS id_termination,
    min(rev) AS min_rev,
    min(ta.ts_updated) AS ts_termination_finished
  FROM datalake_terminator_clean_prod.termination_aud ta  
  WHERE ta.status = 'DONE'
  GROUP BY 1
  ), 
  application_user_info 
  AS 
  (
  SELECT
    id_termination,
    au.id_external,
    au.name,
    au.email
  FROM termination_finished_user tfu 
  JOIN datalake_terminator_clean_prod.rev_info ri
      ON ri.rev = tfu.min_rev
  LEFT JOIN datalake_terminator_clean_prod.application_user au
      ON au.id = ri.id_user
  WHERE id_external IS NOT NULL
  ),
  negotiation_rank 
  AS 
  (
  SELECT
      id_termination_fee,
      id AS id_fee_negotiation,
      discount_percentage,
      discount_value,
      final_amount,
      number_of_installments,
      payment_option,
      status,
      ts_created,
      ts_updated,
      rank() OVER (PARTITION BY id_termination_fee ORDER BY id DESC) AS fee_negotiation_rank
  FROM datalake_terminator_clean_prod.termination_fee_negotiation 
  ),
  last_negotiation
  AS 
  (
  SELECT
      tf.id_termination,
      nr.discount_percentage AS fee_discount_percentage,
      nr.discount_value AS fee_discount_value,
      nr.final_amount AS fee_final_amount,
      nr.number_of_installments AS fee_number_of_installments,
      nr.payment_option AS fee_payment_option,
      nr.status AS fee_negotiation_status,
      nr.ts_created AS ts_fee_negotiation_created,
      nr.ts_updated AS ts_fee_negotiation_updated
  FROM negotiation_rank nr
  LEFT JOIN datalake_terminator_clean_prod.termination_fee tf
      ON nr.id_termination_fee = tf.id 
  WHERE fee_negotiation_rank = 1
  )
SELECT
  t.id AS sk_termination,
  t.id_contract AS sk_contract,
  t.id_exit_inspection AS sk_exit_inspection,
  fhl.sk_house_listing,
  fhl.sk_region,
  aui.id_external AS sk_application_user,
  tw.id_current_assignee AS sk_workflow_assignee,
  JSON_EXTRACT_PATH_TEXT(t.feedback, 'reason') AS reason,
  t.feedback,
  t.requested_by,
  t.status,
  t.source,
  CASE WHEN (source = 'PWA' and dc.is_b2b= 'true' and t.ts_created < '2020-06-10')
    OR (source = 'PWA' and t.dt_termination < dc.dt_entrance)
    OR (source = 'PWA' and JSON_EXTRACT_PATH_TEXT(feedback, 'reason') = 'JOB_TRANSFER' and t.ts_created >= '2020-03-25' and dateadd(year, 1, dc.dt_entrance) > t.dt_termination)
    OR (source = 'PWA' and JSON_EXTRACT_PATH_TEXT(feedback, 'reason') = 'JOB_TRANSFER' and t.ts_created < '2020-03-25')
    THEN 'Semi-automatic'
    WHEN t.source = 'CRM' then 'Manual'
    ELSE 'Automatic'
    END AS type,
  t.cancellation_info,
  t.rescheduling_history,
  JSON_EXTRACT_PATH_TEXT(JSON_EXTRACT_PATH_TEXT(feedback, 'churnInfo'), 'reason') AS churn_reason,
  JSON_EXTRACT_PATH_TEXT(feedback, 'nextProperty') AS next_property,
  JSON_EXTRACT_PATH_TEXT(feedback, 'propertyIssue') AS property_issue,
  dc.b2b_type,
  dc.b2b_prime_type,
  tw.current_step AS workflow_current_step,
  JSON_EXTRACT_PATH_TEXT(k.tenant_keys_location, 'location') AS tenant_key_location,
  k.tenant_keys_location AS tenant_key_detail,
  k.owner_keys_location AS owner_key_detail,
  n.repair_resolution,
  n.repair_cost,
  t.utility_bill_info,
  c.completed_utility_attachments,
  p.pending_utility_attachments,
  u.utility_bill_in_condominium,
  tn.nps,
  iqn.iq_nps,
  ppn.pp_nps,
  aui.name AS application_user_name,
  aui.email AS application_user_email,
  ln.fee_discount_percentage,
  ln.fee_discount_value,
  ln.fee_final_amount,
  ln.fee_number_of_installments,
  ln.fee_payment_option,
  ln.fee_negotiation_status,
  DATEDIFF('day', t.ts_created, t.dt_termination) AS leadtime_request_to_vacancy,
  CASE WHEN d.ts_termination_finished <= '2020-07-07' THEN DATEDIFF('day', t.dt_termination, n.ts_updated)
    WHEN d.ts_termination_finished > '2020-07-07' THEN DATEDIFF('day', t.dt_termination, d.ts_termination_finished)
    END AS leadtime_vacancy_to_finish,
  dc.is_b2b,
  (t.ts_created < dc.dt_start) AS is_before_contract_start, 
  tw.has_automatically_closed_task,
  t.has_exit_inspection,
  n.has_landlord_comment AS has_repairs,
  n.needs_repair_by_tenant AS is_repair_tenant_duty,
  (trunc(t.dt_termination) < dateadd('month', 1, trunc(t.ts_created))) AS has_prior_notice_fine,
  (trunc(t.dt_termination) < dateadd('month', 12, trunc(dc.dt_start))) AS has_one_year_fine,
  (m.id IS NOT NULL) AS has_been_rescheduled,
  (t.ts_canceled IS NOT NULL) AS is_termination_canceled,
  (tw.id IS NOT NULL) AS is_workflow,
  (occ.sk_contract IS NOT NULL OR (tw.id IS NOT NULL AND tw.ts_created > '2021-05-19 18:00:00')) AS is_carteirizado,
  t.is_relisting,
  t.dt_termination,
  m.dt_last_updated AS dt_last_rescheduled,
  to_date(cast(lis.dt_last_inspection_synch AS text),'YYYYMMDD') AS dt_last_inspection_synched,
  n.ts_updated::date AS dt_negotiation_updated,
  ln.ts_fee_negotiation_created,
  ln.ts_fee_negotiation_updated,
  t.ts_created,
  t.ts_canceled,
  CASE WHEN d.ts_termination_finished <= '2020-07-07' THEN n.ts_updated
    WHEN d.ts_termination_finished > '2020-07-07' THEN d.ts_termination_finished
    END AS ts_termination_finished,
  t.ts_updated,
  current_timestamp as ts_load
FROM datalake_terminator_clean_prod.termination t
  LEFT JOIN terminations_finished d
  ON d.id = t.id
    AND t.status = 'DONE'
  LEFT JOIN datalake_terminator_clean_prod.negotiation n
  ON t.id=n.id_termination
  LEFT JOIN keys k
  ON k.id = t.id
  LEFT JOIN terminations_modified m
  ON m.id = t.id
  LEFT JOIN dim_contract dc
  ON dc.sk_contract = t.id_contract 
  LEFT JOIN datalake_terminator_clean_prod.termination_workflow tw
  ON t.id = tw.id_termination
  LEFT JOIN (SELECT distinct cast(nullif(ongoing_contracts,'') AS BIGINT) AS sk_contract FROM datalake_raw.gsheets_offboarding_carteirizacao_contratos
            UNION all
            SELECT distinct cast(nullif(finished_contracts,'') AS BIGINT) AS sk_contract FROM datalake_raw.gsheets_offboarding_carteirizacao_contratos) occ 
  ON t.id_contract = occ.sk_contract 
  LEFT JOIN fact_house_listings fhl
  ON t.id_contract = fhl.sk_contract
  LEFT JOIN completed_utility_attachments c
    ON  c.id_termination = t.id
  LEFT JOIN pending_utility_attachments p
    ON p.id_termination = t.id
  LEFT JOIN utility_in_condominium u
    ON u.id_termination = t.id
  LEFT JOIN total_nps tn
    ON tn.id = t.id
  LEFT JOIN iq_nps iqn
    ON iqn.id = t.id
  LEFT JOIN pp_nps ppn
    ON ppn.id = t.id
  LEFT JOIN last_inspection_synch lis
    ON lis.id = t.id
  LEFT JOIN application_user_info aui
    on t.id = aui.id_termination
  LEFT JOIN last_negotiation ln
    on t.id = ln.id_termination