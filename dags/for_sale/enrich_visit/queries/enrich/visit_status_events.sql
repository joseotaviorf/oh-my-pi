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
booking AS(
  SELECT
    vsl.id_schedule,
    b.id_visitor,
    b.id_agent,
    b.id_house,
    b.id_rent_flow,
    IF(b.business_context = 'SALE',
    CONCAT(b.id_visitor, '_', b.id_house),
    NULL
    ) AS id_sale_flow,
    b.id_fup_details,
    b.business_context,
    b.ts_created,
    vsl.id_visit_status_log,
    vsl.id_visit,
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
    datalake_ebdb_clean.booking AS b
  INNER JOIN
    vsl
      ON  b.id = vsl.id_schedule
  INNER JOIN
    datalake_ebdb_listing.house lh
      ON lh.id = b.id_house
  LEFT JOIN
    datalake_ebdb_clean.visit_cancellation_details AS vcd
      ON vsl.id_visit = vcd.id_visit
  INNER JOIN
    datalake_ebdb_listing.house_listing AS hl
      ON b.id_house = hl.id_house
      AND b.ts_created >= hl.ts_listing_version_start
      AND (b.ts_created <= hl.ts_listing_version_end OR hl.ts_listing_version_end IS NULL)
),
booking_3p_demand_agent AS (
    SELECT
        b.id_schedule,
        wc.id_company_hubspot AS id_company_demand,
        wc.3p_partner AS partner_3p_demand
    FROM
         datalake_ebdb_agents.agent_contract AS ac
    JOIN
        booking AS b
            ON b.ts_created BETWEEN ac.ts_work_contract_started AND COALESCE(ac.ts_work_contract_ended, CURRENT_TIMESTAMP)
            AND ac.id_agent = b.id_agent
    JOIN
        datalake_ebdb_work_contract.work_contract AS wc
            ON wc.id = ac.id_work_contract
    WHERE
        is_3p_contract
    GROUP BY 1, 2, 3
)
SELECT
  CONCAT(b.id_visit_status_log,'R',ranking) AS id_visit_status_events,
  b.id_visit_status_log,
  b.id_visit,
  b.id_schedule,
  b.id_visitor,
  b.id_owner,
  b.id_agent,
  b.id_author_user,
  b.id_house,
  b.id_house_listing,
  b.id_rent_flow,
  b.id_sale_flow,
  b.id_fup_details,
  b.id_cancellation_detail,
  b.id_company_supply,
  b.uuid_company_supply,
  b3da.id_company_demand,
  b.partner_3p_supply,
  b3da.partner_3p_demand,
  b.business_context,
  b.event_type,
  b.ranking,
  b.author_user_type,
  b.author_user_role,
  b.on_behalf_of,
  b.channel,
  b.country_code,
  b.is_visit_last_event,
  b.ts_event_created
FROM
   booking AS b
LEFT JOIN
  booking_3p_demand_agent AS b3da
    ON b.id_schedule = b3da.id_schedule
