WITH
filtered_schedule AS (
  SELECT DISTINCT
    id_schedule,
    id_visit
  FROM
    datalake_ebdb_clean.visit_status_log
  WHERE
    DATE(ts_created) >= DATE('2024-11-01')
),
schedule AS (
  SELECT
    vsl.id_visit,
    vsl.id_schedule,
    MAX(
      CASE
        WHEN vsl.event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED') THEN vsl.id_author_user
      END
    ) AS id_user_creator,
    MAX(
      CASE
        WHEN vsl.event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED') THEN vsl.author_user_role
      END
    ) AS user_role_creator,
    MAX(
      CASE
        WHEN vsl.event_type IN ('VISIT_CANCELED', 'VISIT_REQUEST_CANCELED') THEN vsl.id_author_user
      END
    ) AS id_user_cancelation,
    MAX(
      CASE
        WHEN vsl.event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED') THEN vsl.channel
      END
    ) AS channel_creation,
    MAX(
      CASE
        WHEN vsl.on_behalf_of = 'TENANT_LIVING' THEN vsl.ts_created
      END
    ) AS ts_event_tenant,
    MIN(
      CASE
        WHEN vsl.event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED') THEN vsl.ts_created
      END
    ) AS ts_schedule_created,
    MIN(
      CASE
        WHEN vsl.event_type = 'VISIT_REQUESTED' THEN vsl.ts_created
      END
    ) AS ts_schedule_requested,
    MIN(
      CASE
        WHEN vsl.event_type = 'VISIT_RESCHEDULED' THEN vsl.ts_created
      END
    ) AS ts_schedule_rescheduled,
    MIN(
      CASE
        WHEN vsl.event_type = 'VISIT_CONFIRMED' THEN vsl.ts_created
      END
    ) AS ts_schedule_confirmed,
    MIN(
      CASE
        WHEN vsl.event_type = 'VISIT_DONE' THEN vsl.ts_created
      END
    ) AS ts_schedule_completed,
    MIN(
      CASE
        WHEN vsl.event_type = 'VISIT_UNSUCCESSFUL' THEN vsl.ts_created
      END
    ) AS ts_schedule_unsuccessful,
    MAX(
      CASE
        WHEN vsl.event_type IN ('VISIT_REQUEST_CANCELED', 'VISIT_CANCELED') THEN vsl.ts_created
      END
    ) AS ts_schedule_canceled,
    CASE
      WHEN MIN(vsl.ts_created) FILTER (WHERE vsl.event_type = 'VISIT_RESCHEDULED') IS NOT NULL THEN 'RESCHEDULE'
      ELSE 'REQUEST'
    END AS schedule_origin,
    LEAD(vsl.id_schedule) OVER(PARTITION BY vsl.id_visit ORDER BY MIN(vsl.ts_created)) AS id_succeed_schedule,
    MAX_BY(event_type, ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_PENDING', 'ANSWER_REJECTED') AND on_behalf_of = 'SUPPLY') AS last_confirm_answer_supply,
    MAX_BY(event_type, ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_PENDING', 'ANSWER_REJECTED') AND on_behalf_of = 'DEMAND') AS last_confirm_answer_demand,
    MAX_BY(event_type, ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_PENDING', 'ANSWER_REJECTED') AND on_behalf_of = 'AGENT') AS last_confirm_answer_agent,
    MAX_BY(event_type, ts_created) FILTER (WHERE event_type IN ('ANSWER_CONFIRMED', 'ANSWER_PENDING', 'ANSWER_REJECTED') AND on_behalf_of = 'TENANT_LIVING') AS last_confirm_answer_tenant_living,
    MAX_BY(channel, ts_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED' AND on_behalf_of = 'SUPPLY') AS channel_confirmed_supply,
    MAX_BY(channel, ts_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED' AND on_behalf_of = 'DEMAND') AS channel_confirmed_demand,
    MAX_BY(channel, ts_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED' AND on_behalf_of = 'AGENT') AS channel_confirmed_agent,
    MAX_BY(channel, ts_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED' AND on_behalf_of = 'TENANT_LIVING') AS channel_confirmed_tenant_living
  FROM
    datalake_ebdb_clean.visit_status_log AS vsl
  JOIN
    filtered_schedule AS fs
      ON vsl.id_schedule = fs.id_schedule AND vsl.id_visit = fs.id_visit
  GROUP BY 1, 2
),
visit_aud AS (
  SELECT
    va.id_visit,
    va.ts_visit,
    ure.ts_revision AS ts_created
  FROM
    datalake_ebdb_clean.visit_aud AS va
  LEFT JOIN
    datalake_ebdb_user.user_revision_entity AS ure
      ON va.rev = ure.id
),
schedule_enriched AS (
  SELECT
    schedule.id_visit,
    schedule.id_schedule,
    schedule.id_user_creator,
    schedule.user_role_creator,
    schedule.id_user_cancelation,
    schedule.channel_creation,
    schedule.ts_event_tenant,
    schedule.ts_schedule_created,
    schedule.ts_schedule_requested,
    schedule.ts_schedule_rescheduled,
    schedule.ts_schedule_confirmed,
    schedule.ts_schedule_completed,
    schedule.ts_schedule_unsuccessful,
    schedule.ts_schedule_canceled,
    schedule.schedule_origin,
    schedule.id_succeed_schedule,
    schedule.last_confirm_answer_supply,
    schedule.last_confirm_answer_demand,
    schedule.last_confirm_answer_agent,
    schedule.last_confirm_answer_tenant_living,
    schedule.channel_confirmed_supply,
    schedule.channel_confirmed_demand,
    schedule.channel_confirmed_agent,
    schedule.channel_confirmed_tenant_living,
    va.ts_visit AS ts_schedule_visit
  FROM
    schedule
  LEFT JOIN
    visit_aud AS va
      ON va.id_visit = schedule.id_visit
      AND va.ts_created > schedule.ts_schedule_created
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY schedule.id_schedule ORDER BY va.ts_created) = 1
),
visit_model AS (
  SELECT
    id_visit,
    CASE
      WHEN vse.event_type = 'VISIT_FITTED' THEN 'FITTED'
      WHEN vse.event_type = 'VISIT_REGISTERED' THEN 'REGISTERED'
    END AS visit_model
  FROM
    datalake_ebdb_clean.visit_status_log AS vse
  WHERE
    vse.event_type IN ('VISIT_FITTED', 'VISIT_REGISTERED')
),
offer_after_booking AS (
  SELECT
    id_booking AS id_schedule,
    id_offer,
    hours_booking_to_offer,
    hours_visit_to_offer
  FROM
    datalake_offer.sale_offer
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_booking ORDER BY ts_offer_submitted) = 1
),
agent_contract_aud AS (
  SELECT
    adaud.id AS id_agent,
    adaud.rev,
    adaud.id_work_contract,
    CAST(FROM_UNIXTIME(ure.ts_revision / 1000) AS TIMESTAMP) + (ure.ts_revision % 1000) * INTERVAL 1 MILLISECONDS AS ts_revision,
    LAG(adaud.id_work_contract) OVER (
      PARTITION BY adaud.id
      ORDER BY
        adaud.rev
    ) AS previous_id_work_contract
  FROM
    datalake_ebdb_clean.agent_data_aud AS adaud
  LEFT JOIN
    datalake_ebdb_clean.user_revision_entity AS ure
      ON ure.id = adaud.rev
  WHERE
    adaud.id_work_contract IS NOT NULL
),
agent_contract AS (
  SELECT
    id_agent,
    id_work_contract,
    ts_revision AS ts_work_contract_start,
    LEAD(ts_revision) OVER (
      PARTITION BY id_agent
      ORDER BY
        rev
    ) AS ts_work_contract_end
  FROM
    agent_contract_aud
  WHERE
    previous_id_work_contract <> id_work_contract
    OR previous_id_work_contract IS NULL
),
schedule_aux AS (
  SELECT
    s.id_schedule,
    u.id_agent,
    v.business_context,
    v.id_visitor,
    v.id_house,
    v.dt_visit,
    s.ts_schedule_created AS ts_created
  FROM
    schedule_enriched AS s
  INNER JOIN
    datalake_ebdb_clean.visit AS v
      ON s.id_visit = v.id
  LEFT JOIN
    datalake_ebdb_clean.user AS u
      ON u.id = v.id_agent
),
booking_3p_demand_agent AS (
  SELECT
    b.id_schedule,
    wc.id_company_hubspot AS id_company_demand,
    wc.3p_partner AS partner_3p_demand
  FROM
    agent_contract AS ac
  INNER JOIN
    schedule_aux AS b
      ON b.ts_created BETWEEN ac.ts_work_contract_start AND COALESCE(ac.ts_work_contract_end, CURRENT_TIMESTAMP)
      AND ac.id_agent = b.id_agent
  INNER JOIN
    datalake_ebdb_work_contract.work_contract AS wc
      ON wc.id = ac.id_work_contract
  WHERE
    is_3p_contract = TRUE
),
booking_hub_agent AS (
  SELECT
    b.id_schedule,
    wc.contract_name
  FROM
    agent_contract AS ac
  INNER JOIN
    schedule_aux AS b
      ON b.ts_created BETWEEN ac.ts_work_contract_start AND COALESCE(ac.ts_work_contract_end, CURRENT_TIMESTAMP)
      AND ac.id_agent = b.id_agent
  LEFT JOIN
    datalake_ebdb_clean.work_contract AS wc
      ON wc.id = ac.id_work_contract
  WHERE
    wc.contract_name LIKE 'HUB%'
    AND CAST(b.ts_created AS DATE) >= '2021-07-19'
),
booking_in_rented_house AS (
  SELECT
    b.id_schedule,
    BOOL_OR(
      CASE
        WHEN c.status = 'Ativo'
        AND c.dt_started <= b.dt_visit THEN TRUE
        WHEN c.status = 'Finalizado'
        AND b.dt_visit BETWEEN c.dt_started
        AND LEAST(
          TO_DATE(c.ts_analyst_annulment_input),
          c.dt_termination
        ) THEN TRUE
        ELSE FALSE
      END
    ) AS is_house_rented
  FROM
    schedule_aux AS b
  INNER JOIN
    datalake_ebdb_contract.contract AS c
      ON c.id_house = b.id_house
  WHERE
    c.status in ('Ativo', 'Finalizado')
    AND b.dt_visit BETWEEN c.dt_started
    AND CASE
            WHEN c.status = 'Ativo' THEN NOW()
            WHEN c.status = 'Finalizado' THEN LEAST(TO_DATE(c.ts_analyst_annulment_input), c.dt_termination)
        END
  GROUP BY
    b.id_schedule
),
fixed_agent_disabled AS (
  SELECT
    pfa_aud.id,
    MAX(
      CASE
        WHEN pfa_aud.is_enabled = FALSE THEN FROM_UNIXTIME(ure.ts_revision / 1000)
      END
    ) AS ts_fixed_agent_disabled
  FROM
    datalake_ebdb_clean.preferred_fixed_agent_aud AS pfa_aud
  LEFT JOIN
    datalake_ebdb_clean.user_revision_entity AS ure
      ON ure.id = pfa_aud.rev
  WHERE
    pfa_aud.mod_is_enabled = true
  GROUP BY
    pfa_aud.id
),
preferred_fixed_agent AS (
  SELECT
    id,
    id_user_visit_preferences,
    id_agent_data,
    id_region,
    business_context,
    is_enabled,
    ts_created
  FROM
    datalake_ebdb_clean.preferred_fixed_agent
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_user_visit_preferences ORDER BY ts_updated DESC) = 1
),
fixed_agent AS (
  SELECT
    pfa.id_agent_data AS id_fixed_agent,
    b.id_schedule,
    pfa.business_context
  FROM
    datalake_ebdb_clean.user_visit_preferences AS uvp
  INNER JOIN
    preferred_fixed_agent AS pfa
      ON pfa.id_user_visit_preferences = uvp.id
  LEFT JOIN
    fixed_agent_disabled AS fad
      ON fad.id = pfa.id
  INNER JOIN
    schedule_aux AS b
      ON b.id_visitor = uvp.id_user
      AND b.business_context = pfa.business_context
  INNER JOIN
    datalake_ebdb_clean.house AS h
      ON h.id = b.id_house
  INNER JOIN
    datalake_region.region AS r
      ON r.id = h.id_region
  WHERE
    b.ts_created BETWEEN pfa.ts_created
    AND IF(pfa.is_enabled = TRUE, NOW(), fad.ts_fixed_agent_disabled)
    AND r.id_city = pfa.id_region
),
secretariat_on_visit_date AS (
  SELECT
    b.id_schedule,
    bsc.id_external_responsible AS id_user_secretariat_on_visit_date
  FROM
    schedule_aux AS b
  INNER JOIN
    datalake_hub_services.buyer_secretariat_changes AS bsc
      ON b.id_visitor = bsc.id_external_lead
      AND b.dt_visit BETWEEN bsc.ts_assigned AND COALESCE(bsc.ts_unassigned, GREATEST(CURRENT_DATE, b.dt_visit))
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY b.id_schedule ORDER BY bsc.ts_assigned DESC) = 1
),
last_secretariat as (
  SELECT
    b.id_schedule,
    bsc.id_external_responsible AS id_user_last_secretariat
  FROM
    schedule_aux AS b
  INNER JOIN
    datalake_hub_services.buyer_secretariat_changes AS bsc
      ON b.id_visitor = bsc.id_external_lead
      AND bsc.is_last_responsible
),
buyer_review AS (
  SELECT
    id_reviewed,
    id_reviewer,
    dt_creation
  FROM
    datalake_insider_clean.review
  WHERE
    type = 'tenant_visit'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_reviewed, id_reviewer ORDER BY dt_creation ASC) = 1
),
filtered_visit AS (
  SELECT
    v.id,
    v.id_visitor,
    v.id_house,
    v.id_agent,
    v.code,
    v.business_context,
    v.behavior,
    vbm.business_model,
    v.dt_visit,
    v.id_real_estate_agent_rating,
    v.ts_visit,
    v.ts_created
  FROM
    datalake_ebdb_clean.visit AS v
  LEFT JOIN
    datalake_ebdb_listing.house_listing AS hll
      ON v.id_house = hll.id_house
      AND DATE(v.ts_created) >= DATE(hll.ts_listing_version_start)
      AND (DATE(v.ts_created) <= DATE(hll.ts_listing_version_end) OR hll.ts_listing_version_end IS NULL)
  LEFT JOIN
    datalake_ebdb_clean.country AS ct
      ON ct.code = hll.country_code
  LEFT JOIN
    datalake_visit.visit_business_model AS vbm
      ON v.id = vbm.id_visit
)
SELECT DISTINCT
  s.id_schedule,
  s.id_visit,
  v.id_visitor,
  h.id_user AS id_owner,
  v.id_house,
  s.id_user_creator AS id_user_creation,
  s.user_role_creator AS user_role_creation,
  s.id_user_cancelation,
  v.id_agent AS id_user_agent,
  ua.id_agent,
  so.id_offer,
  fa.id_fixed_agent,
  su.id_user_5a AS id_user_sale_attendence_5a,
  sovd.id_user_secretariat_on_visit_date,
  ls.id_user_last_secretariat,
  COALESCE(cs_company.sk_company, cs_hubspot.sk_company, p_3p_supply.sk_company) AS id_company_supply,
  COALESCE(NULLIF(COALESCE(cs_demand.sk_company, p_3p_demand.sk_company), -1), dm.id_company_demand) AS id_company_demand,
  s.id_succeed_schedule,
  CONCAT(v.id_visitor, '_', v.id_house) AS id_sale_flow,
  h.id_region,
  svh.id_business_unit,
  svh.id_user_en,
  v.code AS visit_code,
  v.business_context,
  v.business_model,
  entry_model.key_location AS method,
  entry_model.entry_model_type,
  CASE
    WHEN vm.visit_model IS NULL THEN 'STANDARD'
    ELSE vm.visit_model
  END AS visit_model,
  bb.visit_fup,
  v.behavior,
  s.schedule_origin,
  s.channel_creation,
  bha.contract_name AS hub_agent_region,
  s.last_confirm_answer_supply,
  s.last_confirm_answer_demand,
  s.last_confirm_answer_agent,
  s.last_confirm_answer_tenant_living,
  s.channel_confirmed_supply,
  s.channel_confirmed_demand,
  s.channel_confirmed_agent,
  s.channel_confirmed_tenant_living,
  CASE
    WHEN s.last_confirm_answer_supply = 'ANSWER_CONFIRMED' THEN TRUE
    WHEN s.last_confirm_answer_supply IN ('ANSWER_PENDING', 'ANSWER_REJECTED') THEN FALSE
    ELSE NULL
  END AS is_confirmed_by_supply,
  CASE
    WHEN s.last_confirm_answer_demand = 'ANSWER_CONFIRMED' THEN TRUE
    WHEN s.last_confirm_answer_demand IN ('ANSWER_PENDING', 'ANSWER_REJECTED') THEN FALSE
    ELSE NULL
  END AS is_confirmed_by_demand,
  CASE
    WHEN s.last_confirm_answer_agent = 'ANSWER_CONFIRMED' THEN TRUE
    WHEN s.last_confirm_answer_agent IN ('ANSWER_PENDING', 'ANSWER_REJECTED') THEN FALSE
    ELSE NULL
  END AS is_confirmed_by_agent,
  CASE
    WHEN s.last_confirm_answer_tenant_living = 'ANSWER_CONFIRMED' THEN TRUE
    WHEN s.last_confirm_answer_tenant_living IN ('ANSWER_PENDING', 'ANSWER_REJECTED') THEN FALSE
    ELSE NULL
  END AS is_confirmed_by_tenant_living,
  IF(s.ts_schedule_confirmed IS NOT NULL, TRUE, FALSE) AS is_confirmed,
  IF(s.ts_schedule_completed IS NOT NULL, TRUE, FALSE) AS is_completed,
  IF(s.ts_schedule_unsuccessful IS NOT NULL, TRUE, FALSE) AS is_unsuccessful,
  IF(s.ts_schedule_canceled IS NOT NULL, TRUE, FALSE) AS is_canceled,
  IF(s.ts_schedule_rescheduled IS NOT NULL, TRUE, FALSE) AS is_rescheduled,
  IF(bha.id_schedule IS NOT NULL, TRUE, FALSE) AS is_hub_flow,
  brh.is_house_rented,
  IF(dm.id_schedule IS NOT NULL, TRUE, FALSE) AS is_3p_demand,
  IF(v.behavior IN ('CONFIRMATION_TENANT_LIVING','CONFIRMATION_TENANT_LIVING_ASSURED','CONFIRMATION_TENANT_LIVING_REQUIRED'), TRUE, FALSE) AS has_tenant_living,
  DATEDIFF(v.dt_visit, ts_schedule_canceled) AS days_visit_cancelled_to_visit,
  DATEDIFF(v.dt_visit, ts_schedule_created) AS days_visit_booked_to_visit,
  DATEDIFF(ts_schedule_canceled, ts_schedule_created) AS days_visit_booked_to_cancelled,
  DATEDIFF(ts_schedule_completed, ts_schedule_created) AS days_visit_booked_to_visit_completed,
  so.hours_booking_to_offer,
  so.hours_visit_to_offer,
  v.ts_visit,
  s.ts_schedule_created,
  s.ts_schedule_requested,
  s.ts_schedule_rescheduled,
  s.ts_schedule_confirmed,
  s.ts_schedule_completed,
  s.ts_schedule_unsuccessful,
  s.ts_schedule_canceled,
  s.ts_schedule_visit,
  v_cin.ts_checkin AS ts_visit_checkin,
  br.dt_creation AS ts_buyer_review_rating,
  NOW() AS ts_load
FROM
  schedule_enriched AS s
INNER JOIN
  filtered_visit AS v
    ON s.id_visit = v.id
INNER JOIN
  datalake_ebdb_clean.house AS h
    ON v.id_house = h.id
--Precisamos para as análises a fup da booking, sendo esse o único join, tendo que ser retirado assim que criarem uma nova referência no produto.
INNER JOIN
  datalake_ebdb_clean.booking AS bb
    ON s.id_schedule = bb.id
LEFT JOIN
  datalake_ebdb_listing.house AS hl
    ON v.id_house = hl.id
LEFT JOIN
  datalake_ebdb_clean.user AS ua
    ON v.id_agent = ua.id
LEFT JOIN
  datalake_sale_visit_hubs.sale_visit_hubs AS svh
    ON svh.id_booking = s.id_schedule
LEFT JOIN
  visit_model AS vm
    ON s.id_visit = vm.id_visit
LEFT JOIN
  datalake_hub_services.secretariat_hierarchy AS su
    ON su.id_user_5a = s.id_user_creator
LEFT JOIN
  datalake_ebdb_listing.house_entrance_history AS entry_model
    ON v.id_house = entry_model.id_house
    AND s.ts_schedule_created >= entry_model.ts_entrance_started
    AND s.ts_schedule_created < COALESCE(entry_model.ts_entrance_ended, NOW())
LEFT JOIN
  booking_3p_demand_agent AS dm
    ON s.id_schedule = dm.id_schedule
LEFT JOIN
  fixed_agent AS fa
    ON s.id_schedule = fa.id_schedule
LEFT JOIN
  secretariat_on_visit_date AS sovd
    ON s.id_schedule = sovd.id_schedule
LEFT JOIN
  last_secretariat AS ls
    ON s.id_schedule = ls.id_schedule
LEFT JOIN
  offer_after_booking AS so
    ON s.id_schedule = so.id_schedule
LEFT JOIN
  booking_hub_agent AS bha
    ON bha.id_schedule = s.id_schedule
LEFT JOIN
  booking_in_rented_house AS brh
    ON s.id_schedule = brh.id_schedule
LEFT JOIN
  datalake_ebdb_clean.visit_checkin AS v_cin
    ON v_cin.id_visit = s.id_visit
LEFT JOIN
  buyer_review AS br
    ON v.code = br.id_reviewed
    AND v.id_visitor = br.id_reviewer
LEFT JOIN
  datalake_company.company_sks AS cs_demand
    ON dm.id_company_demand = cs_demand.id_hubspot
LEFT JOIN
  datalake_company.company_sks AS p_3p_demand
    ON dm.partner_3p_demand = p_3p_demand.extracted_3p_tag
LEFT JOIN
  datalake_company.company_sks AS cs_company
    ON hl.uuid_company = cs_company.id_hubspot
LEFT JOIN
  datalake_company.company_sks AS cs_hubspot
    ON hl.id_company_hubspot = cs_hubspot.id_hubspot
LEFT JOIN
  datalake_company.company_sks AS p_3p_supply
    ON hl.partner_3p_supply = p_3p_supply.extracted_3p_tag
WHERE
  s.id_user_creator IS NOT NULL
