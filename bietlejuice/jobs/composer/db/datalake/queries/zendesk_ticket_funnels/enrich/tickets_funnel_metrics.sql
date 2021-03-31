-- evaluate funnel keys FROM each ticket according to business rules
WITH ticket_funnel_keys AS (
    SELECT
        tck.id_tckt,
        cntt_hse.id_house_listing,
        cntt_hse.id_contract AS id_contract,
        zuc.id_user,
        zuc.id_personal_document,
        -- tickets will only have a valid client key according to its corresponding client type
        CASE
            WHEN tck.client_type = 'inquilino' THEN cntt_hse.id_client
        END AS id_client,
        CASE
            WHEN tck.client_type IN ('proprietário','imobiliária_b2b') THEN cntt_hse.id_owner -- COALESCE(dc.id_owner, dhl.id_owner)
        END AS id_owner
    FROM
        datalake_zendesk_tickets.ticket_measurements tck
    LEFT JOIN
        datalake_ebdb_contract.contract_house cntt_hse
            ON tck.id_house = cntt_hse.id_house
            AND tck.id_contract = cntt_hse.id_contract
    LEFT JOIN
        datalake_zendesk_tickets.zendesk_users_contact zuc
            ON zuc.id_zendesk_user = tck.id_zendesk_requester_user
)
SELECT
    t.id_tckt AS id_ticket,
    fk.id_house_listing,
    fk.id_contract,
    fk.id_user,
    fk.id_personal_document,
    fk.id_client,
    fk.id_owner,
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
INNER JOIN
    ticket_funnel_keys fk
        ON t.id_tckt = fk.id_tckt
