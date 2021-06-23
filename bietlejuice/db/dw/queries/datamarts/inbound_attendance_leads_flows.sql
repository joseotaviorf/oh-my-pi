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
      datalake_wololo_clean_prod.conversion
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
      datalake_wololo_clean_prod.context_discard
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
      datalake_wololo_clean_prod.context_discard AS cd
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
inbound_leads AS (
    SELECT DISTINCT
      dl.sk_lead,
      p.id_task AS inbound_id_task,
      dl.captado_em,
      dl.status,
      p.status AS p_status,
      dl.origem,
      p.origin_phone AS inbound_origin_phone,
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
      dim_lead AS dl
    LEFT JOIN
      datalake_wololo_clean_prod.prospect AS p
        ON cast(p.id_reference AS varchar) = dl.sk_lead
    LEFT JOIN
      conversions AS c
        ON c.id_prospect = p.id
    LEFT JOIN
      discards AS d
        ON d.id_prospect = p.id
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
      date_add('hour', -3, dct.ts_created) AS ts_created_local,
      date_add('hour', -3, dct.ts_ended) AS ts_ended_local,
      dct.ts_twilio_created_local,
      fct.seconds_wait_time,
      LEAD(dct.queue_name) OVER (PARTITION BY fct.sk_call ORDER BY dct.ts_created) AS next_queue,
      LAG(dct.queue_name) OVER (PARTITION BY fct.sk_call ORDER BY dct.ts_created) AS previous_queue,
      ROW_NUMBER() OVER (PARTITION BY fct.sk_call ORDER BY dct.ts_created) AS task_number,
      CASE
        WHEN next_queue IS NULL THEN 'task completed'
        WHEN next_queue IS NOT NULL THEN 'task transferred'
      END AS outcome
    FROM
      call.fact_call_tasks AS fct
    INNER JOIN
      call.dim_call_task AS dct
        ON dct.sk_task = fct.sk_task
    LEFT JOIN
      call.dim_call AS dc
        ON fct.sk_call = dc.sk_call
    LEFT JOIN
      call.dim_call_agent AS dca
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
      LEAD(dt.department) OVER (PARTITION BY ft.sk_chat ORDER BY dt.ts_created_local) AS next_queue,
      LAG(dt.department) OVER (PARTITION BY ft.sk_chat ORDER BY dt.ts_created_local) AS previous_queue,
      ROW_NUMBER() OVER (PARTITION BY ft.sk_chat  ORDER BY dt.ts_created_local) AS task_number,
      completion_reason
    FROM
      quinto_messenger.fact_tasks AS ft
    INNER JOIN
      quinto_messenger.dim_task AS dt
        ON dt.sk_task = ft.sk_task
    LEFT JOIN
      quinto_messenger.dim_chat AS dc
        ON dc.sk_chat = ft.sk_chat
    LEFT JOIN
      quinto_messenger.dim_quinto_messenger_agent AS qa
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
      datalake_bigfone_twilio_prod.call_flex_events AS e
        ON il.inbound_id_task = e.id_task
    LEFT JOIN
      call_tasks AS ft
        ON ft.sk_task = e.id_reservation
    INNER JOIN
      call.fact_calls AS fc
        ON ft.sk_call = fc.sk_call
        AND ft.task_number = fc.answered_tasks
),
all_tasks AS (
    SELECT DISTINCT
      ct.*,
      sk_lead,
      inbound_id_task,
      captado_em,
      status,
      p_status,
      origem,
      inbound_origin_phone,
      conversion_sale,
      conversion_rent,
      discard_sale,
      discard_rent
    FROM
      call_tasks AS ct
    LEFT JOIN
      inbound_tasks_reservations AS ir
        ON ir.sk_call_task = ct.sk_task
    UNION
    SELECT DISTINCT
      ct.*,
      sk_lead,
      inbound_id_task,
      captado_em,
      status,
      p_status,
      origem,
      inbound_origin_phone,
      conversion_sale,
      conversion_rent,
      discard_sale,
      discard_rent
    FROM
      chat_tasks AS ct
    LEFT JOIN
      inbound_leads AS ir
        ON ir.inbound_id_task = ct.sk_task
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
      datamarts.lead_listing_flows
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
  lt.sk_prospect_rent_date,
  lt.sk_prospect_sale_date,
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
  at.locatiON AS analyst_company,
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