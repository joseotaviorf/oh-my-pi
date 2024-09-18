WITH
vsl AS (
  SELECT
    id_visit_status_log,
    id_visit,
    id_schedule,
    id_author_user,
    CASE
        WHEN event_type = 'VISIT_BOOKED' THEN 'VISIT_CONFIRMED'
        ELSE event_type
    END AS event_type,
    ROW_NUMBER() OVER(PARTITION BY id_visit ORDER BY ts_created ASC) AS ranking,
    CASE
      WHEN ROW_NUMBER() OVER(PARTITION BY id_visit ORDER BY ts_created DESC) == 1 THEN TRUE
      ELSE FALSE
    END AS is_visit_last_event,
    author_user_type,
    author_user_role,
    on_behalf_of,
    channel,
    ts_created AS ts_event_created
  FROM
    datalake_ebdb_clean.visit_status_log
),
visit AS(
  SELECT
    vsl.id_visit,
    v.id_visitor,
    v.id_agent,
    v.id_house,
    '' AS id_rent_flow,
    '' AS id_sale_flow,
    '' AS id_fup_details,
    '' AS business_context,
    v.ts_created,
    vsl.id_visit_status_log,
    vsl.id_author_user,
    vsl.id_schedule,
    vsl.event_type,
    vsl.ranking,
    vsl.is_visit_last_event,
    vsl.author_user_type,
    vsl.author_user_role,
    vsl.on_behalf_of,
    vsl.channel,
    vsl.ts_event_created,
    vcd.id AS id_cancellation_detail,
    lh.id_company_hubspot AS id_company_supply,
    lh.uuid_company AS uuid_company_supply,
    lh.partner_3p_supply,
    lh.id_user AS id_owner,
    hl.id_house_listing,
    hl.country_code
  FROM
    datalake_ebdb_clean.visit AS v
  INNER JOIN
    vsl
      ON v.id = vsl.id_visit
  INNER JOIN
    datalake_ebdb_listing.house lh
      ON lh.id = v.id_house
  LEFT JOIN
    datalake_ebdb_clean.visit_cancellation_details AS vcd
      ON vsl.id_visit = vcd.id_visit
  INNER JOIN
    datalake_ebdb_listing.house_listing AS hl
      ON v.id_house = hl.id_house
      AND v.ts_created >= hl.ts_listing_version_start
      AND (v.ts_created <= hl.ts_listing_version_end OR hl.ts_listing_version_end IS NULL)
),
booking_3p_demand_agent AS (
    SELECT
        v.id_visit,
        wc.id_company_hubspot AS id_company_demand,
        wc.3p_partner AS partner_3p_demand
    FROM
         datalake_ebdb_agents.agent_contract AS ac
    JOIN
        visit AS v
            ON v.ts_created BETWEEN ac.ts_work_contract_started AND COALESCE(ac.ts_work_contract_ended, CURRENT_TIMESTAMP)
            AND ac.id_agent = v.id_agent
    JOIN
        datalake_ebdb_work_contract.work_contract AS wc
            ON wc.id = ac.id_work_contract
    WHERE
        is_3p_contract
    GROUP BY 1, 2, 3
)
SELECT
  CONCAT(v.id_visit_status_log,'R',ranking) AS id_visit_status_events,
  v.id_visit_status_log,
  v.id_visit,
  v.id_schedule,
  v.id_visitor,
  v.id_owner,
  v.id_agent,
  v.id_author_user,
  v.id_house,
  v.id_house_listing,
  v.id_rent_flow,
  v.id_sale_flow,
  v.id_fup_details,
  v.id_cancellation_detail,
  v.id_company_supply,
  v.uuid_company_supply,
  b3da.id_company_demand,
  v.partner_3p_supply,
  b3da.partner_3p_demand,
  v.business_context,
  v.event_type,
  v.ranking,
  v.author_user_type,
  v.author_user_role,
  v.on_behalf_of,
  v.channel,
  v.country_code,
  v.is_visit_last_event,
  v.ts_event_created
FROM
   visit AS v
LEFT JOIN
  booking_3p_demand_agent AS b3da
    ON v.id_visit = b3da.id_visit
