WITH tenant AS (
    SELECT DISTINCT
        tmc_t.id_ticket,
        -- tickets will only have a valid client key according to its corresponding client type
        CASE
            WHEN tmc_t.client_type = 'inquilino' THEN ch_t.id_client
        END AS id_client
    FROM
        datalake_zendesk.tickets_current AS tmc_t
    LEFT JOIN
        datalake_ebdb_contract.contract_house ch_t
            ON tmc_t.id_contract = ch_t.id_contract
),
house_owner AS (
    SELECT
        tmc_o.id_ticket,
        MAX(ch_o.id_house_listing) AS id_house_listing,
        CASE
            WHEN REGEXP_REPLACE(tmc_o.client_type, "_so$", "") IN ('proprietário', 'imobiliária_b2b') THEN ch_o.id_owner -- COALESCE(dc.id_owner, dhl.id_owner)
        END AS id_owner
    FROM
        datalake_zendesk.tickets_current tmc_o
    LEFT JOIN
        datalake_ebdb_contract.contract_house ch_o
            ON tmc_o.id_house = ch_o.id_house
    WHERE
        ch_o.id_owner > 0
    GROUP BY 1, 3
),
ticket_comment_metrics AS (
  SELECT
    tc.id_ticket,
    SUM(CASE WHEN tc.is_public THEN 1 ELSE 0 END) AS total_public_comments,
    SUM(CASE WHEN NOT tc.is_public THEN 1 ELSE 0 END) AS total_private_comments,
    MAX(CASE WHEN is_public AND zu.role = 'end-user' THEN tc.ts_created END) AS ts_latest_customer_comment,
    MAX(CASE WHEN is_public AND zu.role = 'agent' THEN tc.ts_created END) AS ts_lastest_analyst_comment
  FROM
    datalake_zendesk_clean.ticket_comments AS tc
  LEFT JOIN
    datalake_support_users.zendesk_users AS zu
      ON zu.id_user_zendesk = tc.id_author
  GROUP BY 1
)
SELECT
    CAST(t.id_ticket AS BIGINT) AS sk_ticket,
    CAST(t.id_ticket_form AS BIGINT) AS sk_ticket_form,
    COALESCE(own.id_house_listing, -1) AS sk_house_listing,
    COALESCE(CAST(t.id_contract AS BIGINT), -1)  AS sk_contract,
    COALESCE(t.offer_ids[0], -1) AS sk_sale_offer,
    CAST(COALESCE(t.id_job, -1) AS BIGINT) AS sk_job,
    COALESCE(t.id_user_main, -1) AS sk_user,
    COALESCE(ten.id_client, -1) AS sk_client,
    COALESCE(own.id_owner, -1) AS sk_owner,
    COALESCE(CAST(t.id_requester AS BIGINT), -1) AS sk_zendesk_requester_user,
    COALESCE(CAST(t.id_submitter AS BIGINT), -1) AS sk_zendesk_submitter_user,
    COALESCE(CAST(t.id_assignee AS BIGINT), -1) AS sk_zendesk_assignee_user,
    MD5(t.analyst_email) AS sk_agent,
    CAST(COALESCE(t.id_session, -1) AS BIGINT) AS sk_session,
    COALESCE(t.id_call, '-1') AS sk_call,
    COALESCE(CAST(DATE_FORMAT(t.ts_created, 'yMMdd') AS INTEGER), -1) AS sk_created_date,
    COALESCE(CAST(DATE_FORMAT(t.ts_created - INTERVAL 3 HOUR, 'yMMdd') AS INTEGER), -1) AS sk_created_date_local,
    COALESCE(CAST(DATE_FORMAT(t.ts_solved, 'yMMdd') AS INTEGER), -1) AS sk_solved_date,
    COALESCE(CAST(DATE_FORMAT(t.ts_solved - INTERVAL 3 HOUR, 'yMMdd') AS INTEGER), -1) AS sk_solved_date_local,
    CASE
      WHEN t.status = 'closed' THEN COALESCE(CAST(DATE_FORMAT(t.ts_updated, 'yMMdd') AS INTEGER), -1)
      ELSE NULL
    END AS sk_closed_date,
    CASE
      WHEN t.status = 'closed' THEN COALESCE(CAST(DATE_FORMAT(t.ts_updated - INTERVAL 3 HOUR, 'yMMdd') AS INTEGER), -1)
      ELSE NULL
    END AS sk_closed_date_local,
    COALESCE(CAST(DATE_FORMAT(t.ts_initially_assigned, 'yMMdd') AS INTEGER), -1) AS sk_initially_assigned,
    COALESCE(CAST(DATE_FORMAT(t.ts_initially_assigned - INTERVAL 3 HOUR, 'yMMdd') AS INTEGER), -1) AS sk_initially_assigned_local,
    COALESCE(CAST(DATE_FORMAT(t.ts_assigned, 'yMMdd') AS INTEGER), -1) AS sk_last_assigned,
    COALESCE(CAST(DATE_FORMAT(t.ts_assigned - INTERVAL 3 HOUR, 'yMMdd') AS INTEGER), -1) AS sk_last_assigned_local,
    t.group_stations AS total_group_stations,
    t.assignee_stations AS total_assignee_stations,
    t.reply_time_min_calendar AS minutes_first_reply_time_calendar,
    t.reply_time_min_business AS minutes_first_reply_time_business,
    t.first_resolution_time_min_calendar AS minutes_first_resolution_time_calendar,
    t.first_resolution_time_min_business AS minutes_first_resolution_time_business,
    t.requester_wait_time_min_calendar AS minutes_requester_wait_time_calendar,
    t.requester_wait_time_min_business AS minutes_requester_wait_time_business,
    t.agent_wait_time_min_calendar AS minutes_agent_wait_time_calendar,
    t.agent_wait_time_min_business AS minutes_agent_wait_time_business,
    t.on_hold_time_min_calendar AS minutes_on_hold_time_calendar,
    t.on_hold_time_min_business AS minutes_on_hold_time_business,
    t.full_resolution_time_min_calendar AS minutes_full_resolution_time_calendar,
    t.full_resolution_time_min_business AS minutes_full_resolution_time_business,
    t.reopens,
    t.replies,
    tcm.total_public_comments,
    tcm.total_private_comments,
    tcm.ts_latest_customer_comment,
    tcm.ts_lastest_analyst_comment,
    t.ts_initially_assigned,
    t.ts_initially_assigned - INTERVAL 3 HOUR AS ts_initially_assigned_local,
    t.ts_assigned AS ts_last_assigned,
    t.ts_assigned - INTERVAL 3 HOUR AS ts_last_assigned_local,
    t.ts_solved,
    t.ts_solved - INTERVAL 3 HOUR AS ts_solved_local,
    CASE
      WHEN t.status = 'closed' THEN t.ts_updated
      ELSE NULL
    END AS ts_closed,
    CASE
      WHEN t.status = 'closed' THEN t.ts_updated - INTERVAL 3 HOUR
      ELSE NULL
    END AS ts_closed_local,
    t.ts_updated,
    t.ts_updated - INTERVAL 3 HOUR AS ts_updated_local,
    NOW() AS ts_load
FROM
    datalake_zendesk.tickets_current AS t
LEFT JOIN
    tenant ten
        ON t.id_ticket = ten.id_ticket
LEFT JOIN
    house_owner own
        ON t.id_ticket = own.id_ticket
LEFT JOIN
    ticket_comment_metrics AS tcm
      ON tcm.id_ticket = t.id_ticket
