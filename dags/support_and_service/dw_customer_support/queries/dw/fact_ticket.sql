WITH base_fcr AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS sk_main_session,
    EXPLODE(ticket_recontact_list) AS recontact_ticket,
    ticket_recontact_list,
    is_fcr AS is_fcr_customer
  FROM
    datalake_customer_resolution.customer_resolution_static
),
fcr_customer AS (
  SELECT
    sk_main_session,
    CAST(ticket_recontact_list[FIND_IN_SET(recontact_ticket, CONCAT_WS(',',ticket_recontact_list))] AS BIGINT) AS sk_next_ticket,
    recontact_ticket,
    is_fcr_customer
  FROM
    base_fcr
)
SELECT DISTINCT
    ut.id_ticket AS sk_ticket,
    ut.id_taxonomy AS sk_taxonomy,
    ut.id_tags AS sk_tags,
    ut.id_channel AS sk_channel,
    ut.id_first_agent AS sk_first_agent,
    ut.id_last_agent AS sk_last_agent,
    ut.id_first_department AS sk_first_department,
    ut.id_main_department AS sk_main_department,
    ut.id_user AS sk_user,
    ut.id_contract AS sk_contract,
    ut.id_session AS sk_session,
    ut.id_service_status AS sk_service_status,
    fc.sk_main_session,
    fc.sk_next_ticket,
    ut.channel,
    ut.ticket_origin,
    ut.context,
    ut.csat_score,
    ut.first_csat_score,
    ut.status,
    ut.first_department,
    ut.main_department,
    ut.total_departments,
    ut.total_segments,
    ut.full_resolution_time,
    ut.front_or_back,
    ut.last_back_ticket,
    ut.back_tickets,
    ut.resolution_survey,
    ut.ticket_rate_weight,
    ut.is_ticket_rate,
    ut.has_answered_csat,
    ut.has_back_ticket,
    ut.is_back_ticket_open,
    ut.is_solved,
    ut.is_fcr,
    IF(ut.id_ticket = fc.sk_main_session, TRUE, FALSE) AS is_ticket_session,
    IF(ut.id_ticket = fc.sk_main_session, fc.is_fcr_customer, FALSE) AS is_fcr_customer,
    IF(ut.id_ticket = fc.sk_main_session, FALSE, TRUE) AS is_recontact,
    ut.has_transfers,
    ut.total_minutes_reception_time,
    ut.total_minutes_talk_time,
    ut.total_minutes_queue_time,
    ut.total_minutes_wrap_up_time,
    ut.total_minutes_handling_time,
    ut.total_backoffice_minutes_time,
    ut.total_minutes_front_to_open_back_ticket_time,
    ut.replies,
    ut.reopens,
    SUBSTR(ut.csat_comment, 1, 1000) AS csat_comment,
    SUBSTR(ut.first_csat_comment, 1, 1000) AS first_csat_comment,
    ut.ts_started,
    ut.ts_closed,
    ut.ts_solved,
    ut.ts_csat_response,
    ut.ts_csat_first_response,
    ut.ts_survey,
    NOW() AS ts_load
FROM
  datalake_customer_support.unified_tickets AS ut
LEFT JOIN
  fcr_customer AS fc
    ON ut.id_ticket = fc.recontact_ticket