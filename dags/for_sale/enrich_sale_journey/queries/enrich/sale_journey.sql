WITH base_amplitude AS (
  SELECT
    IF(action='TALK_TO_SECRETARY', 9, NULL) AS id_event_type,
    id_user,
    NULL AS id_house,
    action,
    IF(action='Active Search', dt_event, NULL) AS active_search_date,
    IF(action='TALK_TO_SECRETARY', dt_event, NULL) AS secretary_action_date,
    NULL AS agent_action_date,
    NULL AS buyer_action_date,
    dt_event,
    ts_event
  FROM
    datalake_sale_journey.sale_amplitude_contact
),
hub_services_contact AS (
  SELECT
    IF(action='SV contact TTS' OR action='SV contact', 9, NULL) AS id_event_type,
    id_user,
    NULL AS id_house,
    action,
    NULL AS active_search_date,
    IF(action='SV contact TTS', dt_event, NULL) AS secretary_action_date,
    NULL AS agent_action_date,
    IF(action='SV contact', dt_event, NULL) AS buyer_action_date,
    dt_event,
    ts_event
  FROM
    datalake_sale_journey.hub_services_contact
),
base_booking AS (
  SELECT
    1 AS id_event_type,
    id_visitor AS id_user,
    id_house,
    CASE
      WHEN user_sale_booking_creator = 'Secretaria'
        THEN 'Booking Secretary'
      WHEN user_sale_booking_creator = 'Agent'
        THEN 'Booking Agent'
      WHEN user_sale_booking_creator = 'Buyer'
        THEN 'Booking Buyer'
      ELSE
        'Booking Others'
    END AS action,
    NULL AS active_search_date,
    CASE
      WHEN DATE(ts_created) > DATE(ts_booking_local_tz)
        THEN DATE(ts_booking_local_tz)
      ELSE
        DATE(ts_created)
    END AS dt_event,
    CASE
      WHEN ts_created > ts_booking_local_tz
        THEN ts_booking_local_tz
      ELSE
        ts_created
    END AS ts_event
  FROM
    datalake_booking.booking AS booking
  WHERE
    visit_intent = 'SALE'
    AND ts_created >= DATE('2022-01-01')
),
booking AS (
  SELECT
    id_event_type,
    id_user,
    id_house,
    action,
    active_search_date,
    IF(action='Booking Secretary', dt_event, NULL) AS secretary_action_date,
    IF(action='Booking Agent', dt_event, NULL) AS agent_action_date,
    IF(action='Booking Buyer', dt_event, NULL) AS buyer_action_date,
    dt_event,
    ts_event
  FROM
    base_booking
),
base_visit AS (
  SELECT
    id_visitor AS id_user,
    id_house,
    CASE
      WHEN status='Realizado' AND user_sale_booking_creator='Secretaria'
        THEN 'Visit Cancelled by Secretary'
      WHEN status='Realizado' AND user_sale_booking_creator='Agent'
        THEN 'Visit Cancelled by Agent'
      WHEN status='Realizado' AND user_sale_booking_creator='Buyer'
        THEN 'Visit Cancelled by Buyer'
      WHEN status='Cancelado' AND user_sale_booking_creator='Secretaria'
        THEN 'Visit Cancelled by Secretary'
      WHEN status='Cancelado' AND user_sale_booking_creator='Agent'
        THEN 'Visit Cancelled by Agent'
      WHEN status='Cancelado' AND user_sale_booking_creator='Buyer'
        THEN 'Visit Cancelled by Buyer'
    END AS action,
    NULL AS active_search_date,
    CASE
      WHEN status = 'Realizado'
        THEN DATE(ts_booking_local_tz)
      WHEN status = 'Cancelado'
        THEN DATE(ts_updated)
    END AS dt_event,
    CASE
      WHEN status = 'Realizado'
        THEN ts_booking_local_tz
      WHEN status = 'Cancelado'
        THEN ts_updated
    END AS ts_event
  FROM
    datalake_booking.booking
  WHERE
    visit_intent = 'SALE'
    AND status IN ('Realizado','Cancelado')
    AND ts_booking_local_tz >= DATE('2022-01-01')
),
visit_complete AS (
  SELECT
    2 AS id_event_type,
    id_user,
    id_house,
    action,
    active_search_date,
    IF(action='Visit Cancelled by Secretary', dt_event, NULL) AS secretary_action_date,
    IF(action='Visit Cancelled by Agent', dt_event, NULL) AS agent_action_date,
    IF(action='Visit Cancelled by Buyer', dt_event, NULL) AS buyer_action_date,
    dt_event,
    ts_event
  FROM
    base_visit
  WHERE
    action LIKE 'Visit Cancelled%'
),
visit_cancelled AS (
  SELECT
    7 AS id_event_type,
    id_user,
    id_house,
    action,
    active_search_date,
    IF(action='Visit Cancelled by Secretary', dt_event, NULL) AS secretary_action_date,
    IF(action='Visit Cancelled by Agent', dt_event, NULL) AS agent_action_date,
    IF(action='Visit Cancelled by Buyer', dt_event, NULL) AS buyer_action_date,
    dt_event,
    ts_event
  FROM
    base_visit
  WHERE
    action LIKE 'Visit Cancelled%'
),
offer_submission AS (
  SELECT
    3 AS id_event_type,
    id_buyer,
    id_house,
    'Offer Submitted' AS action,
    NULL AS active_search_date,
    NULL AS secretary_action_date,
    NULL AS agent_action_date,
    NULL AS buyer_action_date,
    DATE(ts_offer_submitted) AS dt_event,
    ts_offer_submitted AS ts_event
  FROM
    datalake_offer.sale_offer
  WHERE
    id_buyer IS NOT NULL
    AND id_house IS NOT NULL
    AND ts_offer_submitted >= DATE('2022-01-01')
),
offer_status AS(
  SELECT
    id_buyer,
    id_house,
    CASE
      WHEN DATE(dt_offer_accepted) IS NOT NULL
        THEN DATE(dt_offer_accepted)
      WHEN DATE(dt_offer_dismissed) IS NOT NULL
        THEN DATE(dt_offer_dismissed)
      ELSE
        DATE('1970-01-01')
    END AS dt_event,
    CASE
      WHEN dt_offer_accepted IS NOT NULL
        THEN DATE(dt_offer_accepted)
      WHEN dt_offer_dismissed IS NOT NULL
        THEN DATE(dt_offer_dismissed)
      ELSE
        current_timestamp
    END AS ts_event,
    CASE
      WHEN dt_offer_accepted IS NOT NULL
        THEN 'Offer Accepted'
      WHEN dt_offer_dismissed IS NOT NULL
        THEN 'Offer Rejected'
      ELSE
        NULL
    END AS action
  FROM
    datalake_offer.sale_offer
  WHERE
    (dt_offer_accepted IS NOT NULL OR dt_offer_dismissed IS NOT NULL)
    AND id_buyer IS NOT NULL
    AND id_house IS NOT NULL
    AND ts_offer_submitted >= DATE('2022-01-01')
),
offer_accepted AS (
  SELECT
    4 AS id_event_type,
    id_buyer AS id_user,
    id_house,
    action,
    NULL AS active_search_date,
    NULL AS secretary_action_date,
    NULL AS agent_action_date,
    NULL AS buyer_action_date,
    dt_event,
    ts_event
  FROM
    offer_status
  WHERE
    action = 'Offer Accepted'
),
offer_rejected AS (
  SELECT
    8 AS id_event_type,
    id_buyer,
    id_house,
    action,
    NULL AS active_search_date,
    NULL AS secretary_action_date,
    NULL AS agent_action_date,
    NULL AS buyer_action_date,
    dt_event,
    ts_event
  FROM
    offer_status
  WHERE
    action = 'Offer Rejected'
),
all_events AS (
  (SELECT * FROM base_amplitude)
  UNION ALL
  (SELECT * FROM booking)
  UNION ALL
  (SELECT * FROM hub_services_contact)
  UNION ALL
  (SELECT * FROM visit_complete)
  UNION ALL
  (SELECT * FROM visit_cancelled)
  UNION ALL
  (SELECT * FROM offer_submission)
  UNION ALL
  (SELECT * FROM offer_accepted)
  UNION ALL
  (SELECT * FROM offer_rejected)
),
previous_events AS(
  SELECT
    *,
    LEAD(dt_event) OVER(PARTITION BY id_user ORDER BY ts_event DESC, action DESC) AS previous_date,
    LEAD(action) OVER(PARTITION BY id_user ORDER BY ts_event DESC, action DESC) AS previous_action
  FROM
    all_events
),
diff_days AS (
  SELECT
    pe.*,
    DATEDIFF(pe.dt_event, previous_date) AS days,
    CASE
      WHEN previous_date IS NULL THEN 1
      WHEN DATEDIFF(dt_event, previous_date) > 14 THEN 1
      ELSE 0
    END AS new_journey
  FROM
    previous_events AS pe
),
general_base AS (
  SELECT
    dd.id_event_type,
    dd.id_user,
    dd.id_house,
    dd.action,
    dd.previous_action,
    dd.days AS days_since_last_event,
    dd.new_journey,
    SUM(dd.new_journey) OVER (PARTITION BY dd.id_user ORDER BY dd.ts_event) AS journey_number,
    dd.previous_date,
    dd.active_search_date,
    dd.secretary_action_date,
    dd.agent_action_date,
    dd.buyer_action_date,
    dd.dt_event,
    dd.ts_event
  FROM
    diff_days AS dd
),
days_at_event AS (
  SELECT
    *,
    CASE
      WHEN dt_event != LAG(dt_event) OVER (PARTITION BY id_user, journey_number ORDER BY ts_event) THEN 1
      ELSE 0
    END AS new_subjourney
  FROM
    general_base
),
subjourney_difinition AS (
  SELECT
    *,
    SUM(new_subjourney) OVER (PARTITION BY id_user, journey_number ORDER BY ts_event) AS event_day,
    YEAR(dt_event) AS year,
    MONTH(dt_event) AS month,
    DAY(dt_event) AS day
  FROM
    days_at_event
)
SELECT
  id_user,
  id_event_type,
  id_house,
  action,
  journey_number AS journey,
  CASE
    WHEN event_day = 0 THEN 1
    WHEN event_day = 1 THEN 2
    WHEN event_day = 2 THEN 3
    WHEN event_day = 3 THEN 4
    WHEN event_day >= 4 AND event_day <= 6 THEN 5
    ELSE 6
  END AS subjourney,
  days_since_last_event,
  active_search_date AS dt_active_search,
  secretary_action_date AS dt_secretary_action,
  agent_action_date AS dt_agent_action,
  buyer_action_date AS dt_buyer_action,
  dt_event,
  ts_event,
  year,
  month,
  day
FROM
  subjourney_difinition
