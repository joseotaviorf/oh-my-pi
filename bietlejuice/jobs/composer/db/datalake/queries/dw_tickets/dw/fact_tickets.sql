WITH tenant AS (
    SELECT DISTINCT
        tmc_t.id_ticket,
        -- tickets will only have a valid client key according to its corresponding client type
        CASE
            WHEN tmc_t.client_type = 'inquilino' THEN ch_t.id_client
        END AS id_client
    FROM
        datalake_zendesk_tickets.ticket_measurements tmc_t
    LEFT JOIN
        datalake_ebdb_contract.contract_house ch_t
            ON tmc_t.id_contract = ch_t.id_contract
),
house_owner AS (
    SELECT
        tmc_o.id_ticket,
        MAX(ch_o.id_house_listing) AS id_house_listing,
        CASE
            WHEN tmc_o.client_type IN ('proprietário','imobiliária_b2b') THEN ch_o.id_owner -- COALESCE(dc.id_owner, dhl.id_owner)
        END AS id_owner
    FROM
        datalake_zendesk_tickets.ticket_measurements tmc_o
    LEFT JOIN
        datalake_ebdb_contract.contract_house ch_o
            ON tmc_o.id_house = ch_o.id_house
    WHERE
        ch_o.id_owner > 0
    GROUP BY 1, 3
)
SELECT
    CAST(t.id_ticket AS BIGINT) AS sk_ticket,
    COALESCE(own.id_house_listing, -1) AS sk_house_listing,
    COALESCE(t.id_contract, -1)  AS sk_contract,
    COALESCE(t.id_user, -1) AS sk_user,
    t.id_personal_document AS sk_personal_document,
    COALESCE(ten.id_client, -1) AS sk_client,
    COALESCE(own.id_owner, -1) AS sk_owner,
    t.id_zendesk_requester_user AS sk_zendesk_requester_user,
    t.id_zendesk_submitter_user AS sk_zendesk_submitter_user,
    t.id_zendesk_assignee_user AS sk_zendesk_assignee_user,
    CAST(COALESCE(t.id_session, -1) AS BIGINT) AS sk_session,
    COALESCE(t.id_call, '-1') AS sk_call,
    COALESCE(CAST(DATE_FORMAT(t.ts_created, 'yMMdd') AS INTEGER), -1) AS sk_created_date,
    COALESCE(CAST(DATE_FORMAT(t.ts_created_local, 'yMMdd') AS INTEGER), -1) AS sk_created_date_local,
    COALESCE(CAST(DATE_FORMAT(t.ts_solved, 'yMMdd') AS INTEGER), -1) AS sk_solved_date,
    COALESCE(CAST(DATE_FORMAT(t.ts_solved_local, 'yMMdd') AS INTEGER), -1) AS sk_solved_date_local,
    COALESCE(CAST(DATE_FORMAT(t.ts_closed, 'yMMdd') AS INTEGER), -1) AS sk_closed_date,
    COALESCE(CAST(DATE_FORMAT(t.ts_closed_local, 'yMMdd') AS INTEGER), -1) AS sk_closed_date_local,
    COALESCE(CAST(DATE_FORMAT(t.ts_initially_assigned, 'yMMdd') AS INTEGER), -1) AS sk_initially_assigned,
    COALESCE(CAST(DATE_FORMAT(t.ts_initially_assigned_local, 'yMMdd') AS INTEGER), -1) AS sk_initially_assigned_local,
    COALESCE(CAST(DATE_FORMAT(t.ts_last_assigned, 'yMMdd') AS INTEGER), -1) AS sk_last_assigned,
    COALESCE(CAST(DATE_FORMAT(t.ts_last_assigned_local, 'yMMdd') AS INTEGER), -1) AS sk_last_assigned_local,
    t.total_group_stations,
    t.total_assignee_stations,
    t.minutes_reply_calendar AS minutes_first_reply_time_calendar,
    t.minutes_reply_business AS minutes_first_reply_time_business,
    t.minutes_first_resolution_calendar AS minutes_first_resolution_time_calendar,
    t.minutes_first_resolution_business AS minutes_first_resolution_time_business,
    t.minutes_requester_wait_calendar AS minutes_requester_wait_time_calendar,
    t.minutes_requester_wait_business AS minutes_requester_wait_time_business,
    t.minutes_agent_wait_calendar AS minutes_agent_wait_time_calendar,
    t.minutes_agent_wait_business AS minutes_agent_wait_time_business,
    t.minutes_on_hold_calendar AS minutes_on_hold_time_calendar,
    t.minutes_on_hold_business AS minutes_on_hold_time_business,
    t.minutes_full_resolution_calendar AS minutes_full_resolution_time_calendar,
    t.minutes_full_resolution_business AS minutes_full_resolution_time_business,
    t.reopens,
    t.replies,
    t.ts_initially_assigned,
    t.ts_initially_assigned_local,
    t.ts_last_assigned,
    t.ts_last_assigned_local,
    t.ts_solved,
    t.ts_solved_local,
    t.ts_updated,
    t.ts_updated_local,
    t.ts_closed,
    t.ts_closed_local,
    NOW() AS ts_load
FROM
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics AS t
LEFT JOIN
    tenant ten
        ON t.id_ticket = ten.id_ticket
LEFT JOIN
    house_owner own
        ON t.id_ticket = own.id_ticket
