WITH conversion_kind AS (
    SELECT DISTINCT
      id_prospect,
      CASE
        WHEN business_context = 'SALE' THEN 'true'
      END AS is_sale,
      CASE
        WHEN business_context = 'RENT' THEN 'true'
      END AS is_rent
    FROM
      datalake_wololo_clean.conversion
),
conversions AS (
    SELECT
      id_prospect,
      MAX(is_sale) conversion_sale,
      MAX(is_rent) conversion_rent
    FROM
      conversion_kind
    GROUP BY 1
),
unique_discard_context AS (
    SELECT
      id_prospect,
      MAX(id) AS id,
      business_context
    FROM
      datalake_wololo_clean.context_discard
    WHERE
      is_automatically_discarded = false
    GROUP BY 1, 3
),
discard_kind AS (
    SELECT
      u.id_prospect,
      CASE
        WHEN u.business_context = 'SALE' THEN cd.reason
      END AS is_sale,
      CASE
        WHEN u.business_context = 'RENT' THEN cd.reason
      END AS is_rent
    FROM
      datalake_wololo_clean.context_discard AS cd
    INNER JOIN
        unique_discard_context AS u
          ON u.id = cd.id
          AND u.business_context = cd.business_context
          AND u.id_prospect = cd.id_prospect
),
discards AS (
    SELECT
      id_prospect,
      MAX(is_sale) AS discard_sale,
      MAX(is_rent) AS discard_rent
    FROM
      discard_kind
    GROUP BY 1
),
rene_tasks AS (
    SELECT
      DISTINCT id,
      REGEXP_REPLACE(SPLIT(SPLIT(REGEXP_EXTRACT(acquisition_campaign,'"taskId":[^.]*', 0), ',')[0], ':')[1], '"', '') AS task_id,
      REGEXP_REPLACE(REGEXP_REPLACE(SPLIT(SPLIT(REGEXP_EXTRACT(acquisition_campaign,'"originPhone":[^.]*', 0), ',')[0], ':')[1], '"', ''), '}}', '') AS origin_phone
    FROM
      datalake_rene_descartes_clean.acquisition_misc_data
    WHERE acquisition_campaign LIKE '%taskId%'
), rene_leads as (
    SELECT
      DISTINCT hl.id,
      hl.status,
      rt.task_id,
      rt.origin_phone,
      MAX(CASE WHEN lr.business_context = 'RENT' THEN lr.reason END) AS discard_reason_rent,
      MAX(CASE WHEN lr.business_context = 'SALE' THEN lr.reason END) AS discard_reason_sale
    FROM
      datalake_rene_descartes_clean.house_lead hl
    INNER JOIN
      rene_tasks rt
        ON rt.id = hl.id_acquisition
    LEFT JOIN
      datalake_rene_descartes_clean.lead_rejection lr
        ON hl.id = lr.id_house_lead
    WHERE rt.task_id IS NOT NULL
        AND rt.task_id <> ''
        AND lr.origin != 'PROSPECT'
    GROUP BY 1, 2, 3, 4
),
inbound_leads AS (
    SELECT DISTINCT
      dl.sk_lead,
      COALESCE(p.id_task, rl.task_id) AS inbound_id_task,
      dl.captado_em,
      dl.status,
      COALESCE(p.status, rl.status) AS p_status,
      dl.origem,
      COALESCE(p.origin_phone, rl.origin_phone) AS inbound_origin_phone,
      CASE
        WHEN c.conversion_sale = 'true' THEN true
        ELSE false
      END AS conversion_sale,
      CASE
        WHEN c.conversion_rent = 'true' THEN true
        ELSE false
      END AS conversion_rent,
      d.*
    FROM
      dw_public.dim_lead AS dl
    LEFT JOIN
      datalake_wololo_clean.prospect AS p
        ON CAST(p.id_reference AS string) = dl.sk_lead
    LEFT JOIN
      conversions AS c
        ON c.id_prospect = p.id
    LEFT JOIN
      discards AS d
        ON d.id_prospect = p.id
    LEFT JOIN
      rene_leads rl
        ON rl.id = dl.external_id
),
call_tasks AS (
    SELECT DISTINCT
      fct.sk_call,
      fct.sk_task,
      'call' AS channel,
      dc.to_phone_number,
      dc.direction,
      dca.email,
      dca.location,
      dct.queue_name,
      dct.ts_created + INTERVAL -3 HOURS AS ts_created_local,
      dct.ts_ended + INTERVAL -3 HOURS AS ts_ended_local,
      dct.ts_twilio_created_local,
      fct.seconds_wait_time,
      CASE
        WHEN LEAD(dct.queue_name) OVER (PARTITION BY fct.sk_call ORDER BY dct.ts_created) IS NULL THEN 'task completed'
        WHEN LEAD(dct.queue_name) OVER (PARTITION BY fct.sk_call ORDER BY dct.ts_created) IS NOT NULL THEN 'task transferred'
      END AS outcome,
      LEAD(dct.queue_name) OVER (PARTITION BY fct.sk_call ORDER BY dct.ts_created) AS next_queue,
      LAG(dct.queue_name) OVER (PARTITION BY fct.sk_call ORDER BY dct.ts_created) AS previous_queue,
      ROW_NUMBER() OVER (PARTITION BY fct.sk_call ORDER BY dct.ts_created) AS task_number
    FROM
      dw_call.fact_call_tasks AS fct
    INNER JOIN
      dw_call.dim_call_task AS dct
        ON dct.sk_task = fct.sk_task
    LEFT JOIN
      dw_call.dim_call AS dc
        ON fct.sk_call = dc.sk_call
    LEFT JOIN
      dw_call.dim_call_agent AS dca
        ON dca.sk_call_agent = fct.sk_agent
    WHERE
      fct.is_answered = true
      AND dc.direction = 'inbound'
),
chat_tasks AS (
    SELECT DISTINCT
      ft.sk_chat,
      ft.sk_task,
      'chat' AS channel,
      dc.twilio_phone,
      'inbound' AS direction,
      qa.email,
      qa.location,
      dt.department,
      dt.ts_created_local,
      dt.ts_updated_local,
      dt.ts_twilio_created_local,
      ft.seconds_first_reply,
      completion_reason,
      LEAD(dt.department) OVER (PARTITION BY ft.sk_chat ORDER BY dt.ts_created_local) AS next_queue,
      LAG(dt.department) OVER (PARTITION BY ft.sk_chat ORDER BY dt.ts_created_local) AS previous_queue,
      ROW_NUMBER() OVER (PARTITION BY ft.sk_chat  ORDER BY dt.ts_created_local) AS task_number
    FROM
      dw_quinto_messenger.fact_tasks AS ft
    INNER JOIN
      dw_quinto_messenger.dim_task AS dt
        ON dt.sk_task = ft.sk_task
    LEFT JOIN
      dw_quinto_messenger.dim_chat AS dc
        ON dc.sk_chat = ft.sk_chat
    LEFT JOIN
      dw_quinto_messenger.dim_quinto_messenger_agent AS qa
        ON qa.sk_quinto_messenger_agent = ft.sk_quinto_messenger_agent
),
inbound_tasks_reservations AS (
    SELECT DISTINCT
      il.*,
      e.id_task,
      e.id_reservation,
      ft.sk_task AS sk_call_task
    FROM
      inbound_leads AS il
    INNER JOIN
      datalake_bigfone_twilio.call_flex_events AS e
        ON il.inbound_id_task = e.id_task
    LEFT JOIN
      call_tasks AS ft
        ON ft.sk_task = e.id_reservation
    INNER JOIN
      dw_call.fact_calls AS fc
        ON ft.sk_call = fc.sk_call
        AND ft.task_number = fc.answered_tasks
),
all_tasks AS (
    SELECT
      ct.sk_call,
      ct.sk_task,
      ct.channel,
      ct.to_phone_number,
      ct.direction,
      ct.email,
      ct.location,
      ct.queue_name,
      ct.ts_created_local,
      ct.ts_ended_local,
      ct.ts_twilio_created_local,
      ct.seconds_wait_time,
      ct.outcome,
      ct.next_queue,
      ct.previous_queue,
      ir.sk_lead,
      ir.inbound_id_task,
      ir.captado_em,
      ir.status,
      ir.p_status,
      ir.origem,
      ir.inbound_origin_phone,
      ir.conversion_sale,
      ir.conversion_rent,
      ir.discard_sale,
      ir.discard_rent,
      MIN(ct.task_number) AS task_number
    FROM
      call_tasks AS ct
    LEFT JOIN
      inbound_tasks_reservations AS ir
        ON ir.sk_call_task = ct.sk_task
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26
    UNION
    SELECT
      ct.sk_chat,
      ct.sk_task,
      ct.channel,
      ct.twilio_phone,
      ct.direction,
      ct.email,
      ct.location,
      ct.department,
      ct.ts_created_local,
      ct.ts_updated_local,
      ct.ts_twilio_created_local,
      ct.seconds_first_reply,
      ct.completion_reason,
      ct.next_queue,
      ct.previous_queue,
      ir.sk_lead,
      ir.inbound_id_task,
      ir.captado_em,
      ir.status,
      ir.p_status,
      ir.origem,
      ir.inbound_origin_phone,
      ir.conversion_sale,
      ir.conversion_rent,
      ir.discard_sale,
      ir.discard_rent,
      MIN(ct.task_number) AS task_number
    FROM
      chat_tasks AS ct
    LEFT JOIN
      inbound_leads AS ir
        ON ir.inbound_id_task = ct.sk_task
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26
),
lead_context_dates AS (
    SELECT DISTINCT
      sk_lead,
      CASE
        WHEN origin_table = 'Rent' THEN sk_lead_date
      END AS sk_lead_rent_date,
      CASE
        WHEN origin_table = 'Rent' THEN sk_prospect_date
      END AS sk_prospect_rent_date,
      CASE
        WHEN origin_table = 'Rent' THEN sk_qualified_date
      END AS sk_qualified_rent_date,
      CASE
        WHEN origin_table = 'Rent' THEN sk_opportunity_date
      END AS sk_opportunity_rent_date,
      CASE
        WHEN origin_table = 'Rent' THEN sk_first_listing_date
      END AS sk_first_listing_rent_date,
      CASE
        WHEN origin_table = 'Sale' THEN sk_lead_date
      END AS sk_lead_sale_date,
      CASE
        WHEN origin_table = 'Sale' THEN sk_prospect_date
      END AS sk_prospect_sale_date,
      CASE
        WHEN origin_table = 'Sale' THEN sk_qualified_date
      END AS sk_qualified_sale_date,
      CASE
        WHEN origin_table = 'Sale' THEN sk_opportunity_date
      END AS sk_opportunity_sale_date,
      CASE
        WHEN origin_table = 'Sale' THEN sk_first_listing_date
      END AS sk_first_listing_sale_date,
      CASE
        WHEN origin_table = 'Rent' THEN sales_company
      END AS sales_company_rent,
      CASE
        WHEN origin_table = 'Rent' THEN sourcing_ops
      END AS sourcing_ops_rent,
      CASE
        WHEN origin_table = 'Rent' THEN funnel_drop_reason
      END AS funnel_drop_reason_rent,
      CASE
        WHEN origin_table = 'Rent' THEN mkt_origin
      END AS mkt_origin_rent,
      CASE
        WHEN origin_table = 'Rent' THEN mkt_completion
      END AS mkt_completion_rent,
      CASE
        WHEN origin_table = 'Rent' THEN mkt_source
      END AS mkt_source_rent,
      CASE
        WHEN origin_table = 'Rent' THEN mkt_medium
      END AS mkt_medium_rent,
      CASE
        WHEN origin_table = 'Rent' THEN lead_origin
      END AS lead_origin_rent,
      CASE
        WHEN origin_table = 'Sale' THEN sales_company
      END AS sales_company_sale,
      CASE
        WHEN origin_table = 'Sale' THEN sourcing_ops
      END AS sourcing_ops_sale,
      CASE
        WHEN origin_table = 'Sale' THEN funnel_drop_reason
      END AS funnel_drop_reason_sale,
      CASE
        WHEN origin_table = 'Sale' THEN mkt_origin
      END AS mkt_origin_sale,
      CASE
        WHEN origin_table = 'Sale' THEN mkt_completion
      END AS mkt_completion_sale,
      CASE
        WHEN origin_table = 'Sale' THEN mkt_source
      END AS mkt_source_sale,
      CASE
        WHEN origin_table = 'Sale' THEN mkt_medium
      END AS mkt_medium_sale,
      CASE
        WHEN origin_table = 'Sale' THEN lead_origin
      END AS lead_origin_sale
    FROM
      dw_datamarts.lead_listing_flows
),
lead_unique_table AS (
    SELECT
      sk_lead,
      MAX(sk_lead_rent_date) AS sk_lead_rent_date,
      MAX(sk_lead_sale_date) AS sk_lead_sale_date,
      MAX(sk_prospect_rent_date) AS sk_prospect_rent_date,
      MAX(sk_prospect_sale_date) AS sk_prospect_sale_date,
      MAX(sk_qualified_rent_date) AS sk_qualified_rent_date,
      MAX(sk_qualified_sale_date) AS sk_qualified_sale_date,
      MAX(sk_opportunity_rent_date) AS sk_opportunity_rent_date,
      MAX(sk_opportunity_sale_date) AS sk_opportunity_sale_date,
      MAX(sk_first_listing_rent_date) AS sk_first_listing_rent_date,
      MAX(sk_first_listing_sale_date) AS sk_first_listing_sale_date,
      MAX(sales_company_rent) AS sales_company_rent,
      MAX(sales_company_sale) AS sales_company_sale,
      MAX(sourcing_ops_rent) AS sourcing_ops_rent,
      MAX(sourcing_ops_sale) AS sourcing_ops_sale,
      MAX(funnel_drop_reason_rent) AS funnel_drop_reason_rent,
      MAX(funnel_drop_reason_sale) AS funnel_drop_reason_sale,
      MAX(mkt_origin_rent) AS mkt_origin_rent,
      MAX(mkt_origin_sale) AS mkt_origin_sale,
      MAX(mkt_completion_rent) AS mkt_completion_rent,
      MAX(mkt_completion_sale) AS mkt_completion_sale,
      MAX(mkt_source_rent) AS mkt_source_rent,
      MAX(mkt_source_sale) AS mkt_source_sale,
      MAX(mkt_medium_rent) AS mkt_medium_rent,
      MAX(mkt_medium_sale) AS mkt_medium_sale,
      MAX(lead_origin_rent) AS lead_origin_rent,
      MAX(lead_origin_sale) AS lead_origin_sale
    FROM
      lead_context_dates
    GROUP BY 1
)
SELECT DISTINCT
  at.sk_call AS sk_channel,
  at.sk_task,
  at.sk_lead,
  lt.sk_lead_rent_date,
  lt.sk_lead_sale_date,
  -- filling qualified leads without prospect date
  CASE
    WHEN lt.sk_prospect_rent_date < 0 AND lt.sk_qualified_rent_date > 0 THEN lt.sk_qualified_rent_date
    ELSE lt.sk_prospect_rent_date
  END AS sk_prospect_rent_date,
  CASE
    WHEN lt.sk_prospect_sale_date < 0 AND lt.sk_qualified_sale_date > 0 THEN lt.sk_qualified_sale_date
    ELSE lt.sk_prospect_sale_date
  END AS sk_prospect_sale_date,
  lt.sk_qualified_rent_date,
  lt.sk_qualified_sale_date,
  lt.sk_opportunity_rent_date,
  lt.sk_opportunity_sale_date,
  lt.sk_first_listing_rent_date,
  lt.sk_first_listing_sale_date,
  at.channel,
  at.to_phone_number AS phone_contacted,
  at.inbound_origin_phone,
  at.email AS analyst_email,
  at.location AS analyst_company,
  at.queue_name AS task_department,
  at.next_queue AS next_task_department,
  at.previous_queue AS previous_task_department,
  at.task_number AS task_order,
  at.seconds_wait_time,
  at.outcome AS task_completion_reason,
  at.status AS lead_status,
  at.discard_rent AS lead_discard_reason_rent,
  at.discard_sale AS lead_discard_reason_sale,
  lt.sales_company_rent AS lead_sales_company_rent,
  lt.sales_company_sale AS lead_sales_company_sale,
  lt.sourcing_ops_sale AS lead_sourcing_ops_sale,
  lt.sourcing_ops_rent AS lead_sourcing_ops_rent,
  lt.funnel_drop_reason_rent AS lead_funnel_drop_reason_rent,
  lt.funnel_drop_reason_sale AS lead_funnel_drop_reason_sale,
  lt.mkt_origin_rent,
  lt.mkt_origin_sale,
  lt.mkt_completion_rent,
  lt.mkt_completion_sale,
  lt.mkt_source_rent,
  lt.mkt_source_sale,
  lt.mkt_medium_rent,
  lt.mkt_medium_sale,
  lt.lead_origin_rent,
  lt.lead_origin_sale,
  at.conversion_sale AS is_converted_sale,
  at.conversion_rent AS is_converted_rent,
  at.ts_created_local AS ts_task_created_local,
  at.ts_ended_local AS ts_task_ended_local,
  at.ts_twilio_created_local AS ts_task_received_local,
  at.captado_em AS dt_lead_created_local
FROM
  all_tasks AS at
LEFT JOIN
  lead_unique_table AS lt
    ON lt.sk_lead = at.sk_lead

