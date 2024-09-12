WITH customer_conversions AS (
  SELECT
    COALESCE(cc.id_customer,-1) AS id_customer,
    cc.id_dispatch,
    cc.id_dispatch_lot,
    cc.id_answer,
    cc.customer_email,
    cc.customer_phone,
    cc.is_customer_identified,
    d.status,
    d.id_campaign,
    a.nps_answer,
    a.nps_comment,
    ROUND(a.seconds_spent_answering/60.0,2) AS minutes_spent_answering,
    d.ts_created,
    a.ts_answer_sent_local,
    a.ts_dispatch
  FROM
    (SELECT * FROM datalake_tracksale.customer_conversions
    UNION ALL
    SELECT * FROM datalake_casa_mineira_tracksale.customer_conversions) cc
  INNER JOIN
    (SELECT * FROM datalake_tracksale.dispatch
    UNION ALL
    SELECT * FROM datalake_casa_mineira_tracksale.dispatch) d
      ON cc.id_dispatch_lot = d.id
  LEFT JOIN
    (SELECT * FROM datalake_tracksale.answer
    UNION ALL
    SELECT * FROM datalake_casa_mineira_tracksale.answer) a
      ON cc.id_answer = a.id
),
answer_keys AS (
  SELECT
    id_answer,
    MAX(CASE WHEN tag_name = 'User Id' THEN CAST(tag_value AS BIGINT)
      END) AS id_user,
    MAX(CASE WHEN tag_name = 'CPF' THEN tag_value
      END) AS cpf
  FROM
    (SELECT * FROM datalake_tracksale.answer_tags
    UNION ALL
    SELECT * FROM datalake_casa_mineira_tracksale.answer_tags)
  WHERE
    tag_name IN ('User Id','CPF')
  GROUP BY 1
),
ebdb_user AS (
  SELECT
    ak.id_answer,
    ak.id_user
  FROM answer_keys ak
  INNER JOIN datalake_ebdb_clean.user u
    ON ak.id_user = u.id
  GROUP BY
    1,2
),
ebdb_cpf AS (
  SELECT
    ak.id_answer,
    ak.cpf
  FROM
    answer_keys ak
  INNER JOIN
    datalake_ebdb_customer_contact_identification.customer_contact_identification cci
      ON ak.cpf = cci.cpf
  GROUP BY
    1,2
),
customer_keys AS (
  SELECT
    cc.id_customer,
    MAX(COALESCE(eu.id_user,cci_e.id_user, cci_p.id_user)) AS id_user,
    MAX(COALESCE(ec.cpf,cci_e.cpf,cci_p.cpf)) AS cpf
  FROM
    (SELECT * FROM datalake_tracksale.customer_conversions
    UNION ALL
    SELECT * FROM datalake_casa_mineira_tracksale.customer_conversions) cc -- we are merging historical data from Casa Mineira's Tracksale account
  LEFT JOIN
    ebdb_user eu
      ON eu.id_answer = cc.id_answer
  LEFT JOIN
    ebdb_cpf ec
      ON ec.id_answer = cc.id_answer
  LEFT JOIN
    datalake_ebdb_customer_contact_identification.customer_contact_identification cci_p
      ON cci_p.customer_contact = cc.customer_phone
      AND cci_p.channel = 'phone'
  LEFT JOIN
    datalake_ebdb_customer_contact_identification.customer_contact_identification cci_e
      ON cci_e.customer_contact = cc.customer_email
      AND cci_e.channel = 'email'
  WHERE
    cc.id_customer IS NOT NULL
  GROUP BY
    1
),
attributes_union AS (
  SELECT *
  FROM
    datalake_tracksale.dispatch_attributes

    UNION ALL

  SELECT *
  FROM
    datalake_casa_mineira_tracksale.dispatch_attributes
),
customer_last_rent_event AS (
  SELECT
    cc.id_dispatch,
    au.id AS id_dispatch_lot,
    rd.id_tenant_prospect,
    au.dispatch_time AS ts_dispatch_sent,
    MAX(ts_event) FILTER(WHERE ts_event < dispatch_time) AS ts_rent_last_event
  FROM
    customer_conversions AS cc
  LEFT JOIN
    customer_keys AS ck
      ON ck.id_customer = cc.id_customer
  LEFT JOIN
    attributes_union AS au
      ON cc.id_dispatch_lot = au.id
      AND COALESCE(cc.customer_email, cc.customer_phone) = COALESCE(au.email, au.phone)
  LEFT JOIN
    datalake_rent_demand_events.rent_demand_events AS rd
      ON rd.id_tenant_prospect = ck.id_user
      AND rd.ts_event < au.dispatch_time
  GROUP BY
    1, 2, 3, 4
),
customer_event AS (
  SELECT
    cl.id_dispatch,
    cl.id_dispatch_lot,
    cl.id_tenant_prospect,
    MAX(rd.id_event) AS id_event,
    MAX(rd.id_event_type) AS id_event_type,
    cl.ts_dispatch_sent,
    cl.ts_rent_last_event
  FROM
    customer_last_rent_event AS cl
  JOIN
    datalake_rent_demand_events.rent_demand_events AS rd
      ON rd.id_tenant_prospect = cl.id_tenant_prospect
      AND rd.ts_event = cl.ts_rent_last_event
  GROUP BY
    1, 2, 3, 6, 7
)
SELECT
  COALESCE(cc.id_dispatch,-1) AS sk_nps_dispatch,
  COALESCE(cc.id_dispatch_lot,-1) AS sk_nps_dispatch_lot,
  COALESCE(cc.id_campaign,-1) AS sk_nps_campaign,
  COALESCE(cc.id_customer,-1) AS sk_nps_customer,
  COALESCE(ck.id_user,-1) AS sk_user,
  COALESCE(ck.cpf, -1) AS sk_personal_document,
  COALESCE(cc.id_answer, -1) AS sk_nps_answer,
  COALESCE(ad.id_house_listing, -1) AS sk_house_listing,
  COALESCE(ad.id_booking, -1) AS sk_booking,
  COALESCE(ad.id_tta, -1) AS sk_tta,
  COALESCE(ad.id_offer_context, -1) AS sk_offer,
  COALESCE(ad.id_contract, -1) AS sk_contract,
  COALESCE(ce.id_event, -1) AS sk_last_rent_event,
  COALESCE(ce.id_event_type, -1) AS sk_last_rent_event_type,
  COALESCE(CAST(DATE_FORMAT(cc.ts_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_created_date,
  COALESCE(CAST(DATE_FORMAT(COALESCE(at.dispatch_time, cc.ts_dispatch), 'yyyyMMdd') AS BIGINT), -1) AS sk_sent_date,
  COALESCE(CAST(DATE_FORMAT(cc.ts_answer_sent_local, 'yyyyMMdd') AS BIGINT), -1) AS sk_answered_date,
  COALESCE(CAST(DATE_FORMAT(ce.ts_rent_last_event, 'yyyyMMdd') AS BIGINT), -1) AS sk_last_rent_event_date,
  cc.nps_answer AS score,
  minutes_spent_answering AS minutes_response_time,
  CASE
    WHEN COALESCE(at.dispatch_time,cc.ts_dispatch) IS NOT NULL
    THEN 'Finalizado'
    ELSE at.status
  END AS dispatch_status,
  COALESCE(ac.city, 'NÃO INFORMADO') AS city,
  CAST(COALESCE(at.survey_opened, 'false') AS BOOLEAN) AS is_survey_opened,
  CASE
    WHEN
      cc.status <> 'Finalizado'
      AND COALESCE(at.dispatch_time,cc.ts_dispatch) IS NULL
    THEN TRUE
    ELSE False
  END AS is_pending_survey,
  cc.id_answer IS NOT NULL AS is_answered,
  cc.nps_comment IS NOT NULL AS has_comment,
  cc.is_customer_identified,
  CURRENT_TIMESTAMP AS ts_load
FROM
  customer_conversions AS cc
LEFT JOIN
  customer_keys AS ck
    ON ck.id_customer = cc.id_customer
LEFT JOIN
  datalake_nps_answer_drivers.answer_drivers AS ad
    ON cc.id_answer = ad.id_answer
LEFT JOIN
  attributes_union AS at
    ON at.id = cc.id_dispatch_lot
    AND (COALESCE(cc.customer_email, cc.customer_phone) = COALESCE(at.email, at.phone))
LEFT JOIN
  (SELECT *
  FROM
    datalake_tracksale.answer_cities

    UNION ALL

  SELECT *
  FROM
    datalake_casa_mineira_tracksale.answer_cities) AS ac
      ON ac.id_answer = cc.id_answer
LEFT JOIN
  customer_event AS ce
    ON ce.id_dispatch = cc.id_dispatch
    AND ce.id_dispatch_lot = cc.id_dispatch_lot
    AND ce.ts_dispatch_sent = at.dispatch_time
    AND ce.id_tenant_prospect = ck.id_user