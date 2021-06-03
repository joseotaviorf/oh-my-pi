WITH tenant AS (
    SELECT DISTINCT
        tmc_t.id_ticket,
        ch_t.id_contract AS id_contract,
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
SELECT DISTINCT
    t.id_ticket,
    own.id_house_listing,
    t.id_contract,
    zuc.id_user,
    zuc.id_personal_document,
    ten.id_client,
    own.id_owner,
    t.id_zendesk_requester_user,
    t.id_zendesk_submitter_user,
    t.id_zendesk_assignee_user,
    t.id_session,
    t.id_call,
    t.total_group_stations,
    t.total_assignee_stations,
    t.minutes_reply_calendar,
    t.minutes_reply_business,
    t.minutes_first_resolution_calendar,
    t.minutes_first_resolution_business,
    t.minutes_requester_wait_calendar,
    t.minutes_requester_wait_business,
    t.minutes_agent_wait_calendar,
    t.minutes_agent_wait_business,
    t.minutes_on_hold_calendar,
    t.minutes_on_hold_business,
    t.minutes_full_resolution_calendar,
    t.minutes_full_resolution_business,
    t.reopens,
    t.replies,
    t.ts_created,
    t.ts_created_local,
    t.ts_solved,
    t.ts_solved_local,
    t.ts_closed,
    t.ts_closed_local,
    t.ts_initially_assigned,
    t.ts_initially_assigned_local,
    t.ts_last_assigned,
    t.ts_last_assigned_local,
    t.ts_updated,
    t.ts_updated_local,
    NOW() AS ts_load,
    YEAR(t.ts_updated) AS year,
    MONTH(t.ts_updated) AS month,
    DAY(t.ts_updated) AS day
FROM
    datalake_zendesk_tickets.ticket_measurements t
LEFT JOIN
    tenant ten
        ON t.id_ticket = ten.id_ticket
LEFT JOIN
    house_owner own
        ON t.id_ticket = own.id_ticket
LEFT JOIN
    datalake_zendesk_tickets.zendesk_users_contact zuc
        ON zuc.id_zendesk_user = t.id_zendesk_requester_user