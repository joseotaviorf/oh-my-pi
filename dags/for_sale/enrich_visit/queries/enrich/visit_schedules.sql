WITH
ranking AS (
  SELECT
    id_visit,
    id_schedule,
    event_type,
    ROW_NUMBER() OVER(PARTITION BY id_visit ORDER BY ts_created ASC) AS ranking,
    ts_created AS ts_event_created
  FROM
    datalake_ebdb_clean.visit_status_log
),
reschedules AS (
  SELECT
    ev1.id_schedule AS id_schedule,
    ev2.id_schedule AS id_succeed_schedule
  FROM
    ranking AS ev1
  INNER JOIN ranking AS ev2
    ON ev1.id_visit = ev2.id_visit
    AND ev1.ranking = (ev2.ranking -1)
    AND ev2.event_type = 'VISIT_RESCHEDULED'
  GROUP BY ALL
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
  GROUP BY ALL
),
schedule_creator AS (
  SELECT
    id_schedule,
    id_author_user AS id_user_creator
  FROM
    datalake_ebdb_clean.visit_status_log
  WHERE
    event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED')
),
schedule_cancelation AS (
  SELECT
    id_schedule,
    id_author_user AS id_user_cancelation
  FROM
    datalake_ebdb_clean.visit_status_log
  WHERE
    event_type IN ('VISIT_CANCELED', 'VISIT_REQUEST_CANCELED')
),
entrance_method AS (
  SELECT
    heh.id_house AS sk_house,
    DATE(heh.ts_entrance_started) AS date_start,
    DATE(COALESCE(heh.ts_entrance_ended, NOW())) AS date_end,
    MAX(heh.key_location) AS method,
    MAX(heh.key_type) AS key_type
  FROM
    datalake_ebdb_listing.house_entrance_history heh
  WHERE
    heh.is_last_status_of_day
    AND heh.ts_entrance_started < NOW()
    AND COALESCE(heh.ts_entrance_ended, NOW()) >= DATE_SUB(NOW(), 400)
  GROUP BY
    ALL
),
entrance_method_treatment(
  SELECT
    l.id AS id_house,
    DATE(COALESCE(em.date_start, l.dt_creation)) AS start_date,
    DATE(COALESCE(em.date_end, l.ts_updated)) AS end_date,
    TRIM(LOWER(MAX(COALESCE(em.method, l.key_location)))) AS method
  FROM
    datalake_ebdb_listing.house AS l
  LEFT JOIN entrance_method AS em
    ON l.id = em.sk_house
  GROUP BY
    ALL
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
  LEFT JOIN datalake_ebdb_clean.user_revision_entity AS ure
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
    vse.id_schedule,
    u.id_agent,
    v.business_context,
    v.id_visitor,
    v.id_house,
    v.dt_visit,
    MIN(vse.ts_created) AS ts_created
  FROM
    datalake_ebdb_clean.visit_status_log AS vse
  INNER JOIN datalake_ebdb_clean.visit AS v
    ON vse.id_visit = v.id
  LEFT JOIN datalake_ebdb_clean.user AS u
    ON u.id = v.id_agent
  WHERE
    event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED')
  GROUP BY
    1,2,3,4,5,6
),
booking_3p_demand_agent AS (
  SELECT
    b.id_schedule,
    wc.id_company_hubspot AS id_company_demand,
    wc.3p_partner AS partner_3p_demand
  FROM
    agent_contract AS ac
  INNER JOIN schedule_aux AS b
    ON b.ts_created BETWEEN ac.ts_work_contract_start
    AND COALESCE(ac.ts_work_contract_end, CURRENT_TIMESTAMP)
    AND ac.id_agent = b.id_agent
  INNER JOIN datalake_ebdb_work_contract.work_contract AS wc
    ON wc.id = ac.id_work_contract
  WHERE
    is_3p_contract
),
booking_hub_agent AS (
  SELECT
    b.id_schedule,
    wc.contract_name
  FROM
    agent_contract AS ac
  INNER JOIN schedule_aux AS b
    ON b.ts_created BETWEEN ac.ts_work_contract_start
    AND COALESCE(ac.ts_work_contract_end, CURRENT_DATE)
    AND ac.id_agent = b.id_agent
  LEFT JOIN datalake_ebdb_clean.work_contract AS wc
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
  INNER JOIN datalake_ebdb_contract.contract AS c
    ON c.id_house = b.id_house
  WHERE
    c.status in ('Ativo', 'Finalizado')
    AND b.dt_visit BETWEEN c.dt_started
    AND CASE
      WHEN c.status = 'Ativo' THEN NOW()
      WHEN c.status = 'Finalizado' THEN LEAST(
        TO_DATE(c.ts_analyst_annulment_input),
        c.dt_termination
      )
    END
    AND b.business_context = 'SALE'
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
  LEFT JOIN datalake_ebdb_clean.user_revision_entity AS ure
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
  INNER JOIN preferred_fixed_agent AS pfa
    ON pfa.id_user_visit_preferences = uvp.id
  LEFT JOIN fixed_agent_disabled AS fad
    ON fad.id = pfa.id
  INNER JOIN schedule_aux AS b
    ON b.id_visitor = uvp.id_user
    AND b.business_context = pfa.business_context
  INNER JOIN datalake_ebdb_clean.house AS h
    ON h.id = b.id_house
  INNER JOIN datalake_region.region AS r
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
  INNER JOIN datalake_hub_services.buyer_secretariat_changes AS bsc
    ON b.id_visitor = bsc.id_external_lead
    AND b.dt_visit BETWEEN bsc.ts_assigned
    AND COALESCE(bsc.ts_unassigned, GREATEST(NOW(), b.dt_visit))
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY b.id_schedule ORDER BY bsc.ts_assigned DESC) = 1
),
last_secretariat as (
  SELECT
    b.id_schedule,
    bsc.id_external_responsible AS id_user_last_secretariat
  FROM
    schedule_aux AS b
  INNER JOIN datalake_hub_services.buyer_secretariat_changes AS bsc
    ON b.id_visitor = bsc.id_external_lead
    AND bsc.is_last_responsible
),
event_date AS (
  SELECT
    id_schedule,
    MIN(vse.ts_created) FILTER (WHERE event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED')) AS ts_schedule_created,
    MIN(vse.ts_created) FILTER (WHERE event_type = 'VISIT_REQUESTED') AS ts_schedule_requested,
    MIN(vse.ts_created) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') AS ts_schedule_rescheduled,
    MIN(vse.ts_created) FILTER (WHERE event_type = 'VISIT_CONFIRMED') AS ts_schedule_confirmed,
    MIN(vse.ts_created) FILTER (WHERE event_type = 'VISIT_DONE') AS ts_schedule_completed,
    MIN(vse.ts_created) FILTER (WHERE event_type = 'VISIT_UNSUCCESSFUL') AS ts_schedule_unsuccessful,
    MAX(vse.ts_created) FILTER (WHERE event_type IN ('VISIT_REQUEST_CANCELED', 'VISIT_CANCELED')) AS ts_schedule_canceled
  FROM
    datalake_ebdb_clean.visit_status_log AS vse
  GROUP BY
    1
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
)
SELECT
  vse.id_schedule,
  vse.id_visit,
  v.id_visitor,
  h.id_user AS id_owner,
  v.id_house,
  sc.id_user_creator AS id_user_creation,
  scl.id_user_cancelation,
  v.id_agent AS id_user_agent,
  ua.id_agent,
  so.id_offer,
  ar.id AS id_agent_schedule_review,
  fa.id_fixed_agent,
  su.id_user_5a AS id_user_sale_attendence_5a,
  sovd.id_user_secretariat_on_visit_date,
  ls.id_user_last_secretariat,
  cs_supply.sk_company AS id_company_supply,
  COALESCE(NULLIF(cs_demand.sk_company, -1), dm.id_company_demand) AS id_company_demand,
  reschedules.id_succeed_schedule,
  CONCAT(v.id_visitor, '_', v.id_house) AS id_sale_flow,
  h.id_region,
  svh.id_business_unit,
  svh.id_user_en,
  v.code AS visit_code,
  v.business_context,
  CASE
    emt.method
    WHEN 'frontdoor' THEN 'Front Door'
    WHEN 'keyswithagent' THEN 'Keys with Agent'
    WHEN 'lockbox' THEN 'Lockbox'
    WHEN 'password' THEN 'Password'
    WHEN 'keyslocker' THEN 'Keys Locker'
    ELSE 'Owner Present'
  END AS method,
  CASE
    WHEN vm.visit_model IS NULL THEN 'STANDARD'
    ELSE vm.visit_model
  END AS visit_model,
  v.behavior,
  CASE
    WHEN MIN(vse.ts_created) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') IS NOT NULL THEN 'RESCHEDULE'
    ELSE 'REQUEST'
  END AS schedule_origin,
  bha.contract_name AS hub_agent_region,
  IF(bha.id_schedule IS NOT NULL, TRUE, FALSE) AS is_hub_flow,
  brh.is_house_rented,
  DATEDIFF(v.dt_visit, ts_schedule_canceled) AS days_visit_cancelled_to_visit,
  DATEDIFF(v.dt_visit, ts_schedule_created) AS days_visit_booked_to_visit,
  DATEDIFF(ts_schedule_canceled, ts_schedule_created) AS days_visit_booked_to_cancelled,
  DATEDIFF(ts_schedule_completed, ts_schedule_created) AS days_visit_booked_to_visit_completed,
  so.hours_booking_to_offer,
  so.hours_visit_to_offer,
  TO_UTC_TIMESTAMP(
    (
      CAST(v.dt_visit AS TIMESTAMP) + FLOOR((v.slot * 15 / 60) + 8) * INTERVAL 1 HOURS + ABS(v.slot * 15 % 60) * INTERVAL 1 MINUTES
    ),
    COALESCE(ct.default_timezone, 'UTC')
  ) AS ts_visit,
  evd.ts_schedule_created,
  evd.ts_schedule_requested,
  evd.ts_schedule_rescheduled,
  evd.ts_schedule_confirmed,
  evd.ts_schedule_completed,
  evd.ts_schedule_unsuccessful,
  evd.ts_schedule_canceled,
  v_cin.ts_checkin AS ts_visit_checkin,
  ar.ts_created AS ts_agent_review_rating,
  br.dt_creation AS ts_buyer_review_rating,
  NOW() AS ts_load
FROM
  datalake_ebdb_clean.visit_status_log AS vse
INNER JOIN event_date AS evd
  ON vse.id_schedule = evd.id_schedule
INNER JOIN datalake_ebdb_clean.visit AS v
  ON vse.id_visit = v.id
INNER JOIN datalake_ebdb_clean.house AS h
  ON v.id_house = h.id
LEFT JOIN datalake_ebdb_listing.house AS hl
  ON v.id_house = hl.id
INNER JOIN datalake_ebdb_clean.user AS ua
  ON v.id_agent = ua.id
LEFT JOIN datalake_sale_visit_hubs.sale_visit_hubs AS svh
  ON svh.id_booking = vse.id_schedule
LEFT JOIN datalake_ebdb_clean.real_estate_agent_rating AS ar
  ON ar.id = v.id_real_estate_agent_rating
LEFT JOIN reschedules
  ON reschedules.id_schedule = vse.id_schedule
LEFT JOIN visit_model AS vm
  ON vse.id_visit = vm.id_visit
INNER JOIN schedule_creator AS sc
  ON vse.id_schedule = sc.id_schedule
LEFT JOIN schedule_cancelation AS scl
  ON vse.id_schedule = scl.id_schedule
LEFT JOIN datalake_hub_services.secretariat_hierarchy AS su
  ON su.id_user_5a = sc.id_user_creator
LEFT JOIN entrance_method_treatment AS emt
  ON v.id_house = emt.id_house
  AND v.dt_visit >= emt.start_date
  AND v.dt_visit < emt.end_date
LEFT JOIN booking_3p_demand_agent AS dm
  ON vse.id_schedule = dm.id_schedule
LEFT JOIN fixed_agent AS fa
  ON vse.id_schedule = fa.id_schedule
LEFT JOIN secretariat_on_visit_date AS sovd
  ON vse.id_schedule = sovd.id_schedule
LEFT JOIN last_secretariat AS ls
  ON vse.id_schedule = ls.id_schedule
LEFT JOIN offer_after_booking AS so
  ON vse.id_schedule = so.id_schedule
LEFT JOIN booking_hub_agent AS bha
  ON bha.id_schedule = vse.id_schedule
LEFT JOIN booking_in_rented_house AS brh
  ON vse.id_schedule = brh.id_schedule
LEFT JOIN datalake_ebdb_listing.house_listing AS hll
  ON v.id_house = hll.id_house
  AND DATE(v.ts_created) >= DATE(hll.ts_listing_version_start)
  AND (DATE(v.ts_created) <= DATE(hll.ts_listing_version_end) OR hll.ts_listing_version_end IS NULL)
LEFT JOIN datalake_ebdb_clean.country AS ct
  ON ct.code = hll.country_code
LEFT JOIN datalake_ebdb_clean.visit_checkin AS v_cin
  ON v_cin.id_visit = vse.id_visit
LEFT JOIN buyer_review AS br
  ON v.code = br.id_reviewed
  AND v.id_visitor = br.id_reviewer
LEFT JOIN datalake_rede_company.company_sks AS cs_demand
  ON (dm.id_company_demand IS NOT NULL AND dm.id_company_demand = cs_demand.id_hubspot)
  OR (dm.id_company_demand IS NULL AND dm.partner_3p_demand = cs_demand.extracted_3p_tag)
LEFT JOIN
    datalake_rede_company.company_sks AS cs_supply
        ON (
          hl.uuid_company IS NOT NULL
          AND hl.uuid_company = cs_supply.uuid_company
        ) OR (
          hl.uuid_company IS NULL
          AND hl.id_company_hubspot IS NOT NULL
          AND hl.id_company_hubspot = cs_supply.id_hubspot
        ) OR (
          hl.uuid_company IS NULL
          AND hl.id_company_hubspot IS NULL
          AND hl.partner_3p_supply = cs_supply.extracted_3p_tag
        )
GROUP BY ALL
HAVING
  MIN(vse.ts_created) >= '2024-11-01'
