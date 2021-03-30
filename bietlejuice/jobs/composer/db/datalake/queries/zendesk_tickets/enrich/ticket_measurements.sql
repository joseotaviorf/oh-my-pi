WITH custom_field_ids AS (
    SELECT
        base.id_ticket,
        cf_client_type.value_field AS client_type,
        CASE
            WHEN LENGTH(CAST(cf_house.value_field AS STRING)) < 9
                THEN 892700000 + CAST(cf_house.value_field AS BIGINT)
            ELSE CAST(cf_house.value_field AS BIGINT)
        END AS id_house,
        cf_contract.value_field AS id_contract,
        cf_session.value_field AS id_session,
        cf_call.value_field AS id_call
    FROM
        datalake_zendesk_custom_fields.custom_fields base
    LEFT JOIN
        datalake_zendesk_custom_fields.custom_fields cf_house
            ON base.id_ticket = cf_house.id_ticket
            AND cf_house.id_field = "31646438" -- refers to id_house
    LEFT JOIN
        datalake_zendesk_custom_fields.custom_fields cf_contract
            ON base.id_ticket = cf_contract.id_ticket
            AND cf_contract.id_field = "114096515211" -- refers to id_contract
    LEFT JOIN
        datalake_zendesk_custom_fields.custom_fields cf_session --Sauron
            ON base.id_ticket = cf_session.id_ticket
            AND cf_session.id_field = "360034234371" -- refers to id_session
    LEFT JOIN
        datalake_zendesk_custom_fields.custom_fields cf_call -- Bigfone
            ON base.id_ticket = cf_call.id_ticket
            AND cf_call.id_field = "360020220412" -- refers to id_call
    LEFT JOIN
        datalake_zendesk_custom_fields.custom_fields cf_client_type
            ON base.id_ticket = cf_client_type.id_ticket
            AND cf_client_type.id_field = "46785608" -- refers to id_client_type
)
SELECT
    t.id_ticket AS id_tckt,
    -- id_contract AND id_house may be filled WITH string (filled wrong)
    -- id_house may be filled WITH id_house OR short_id_house
    cfi.id_house,
    cfi.id_contract,
    cfi.id_session,
    cfi.id_call,
    cfi.client_type, -- included to enable id_owner AND id_client relationship
    tm.id_ticket,
    CAST(tm.group_stations AS SMALLINT) AS total_group_stations,
    CAST(tm.assignee_stations AS SMALLINT) AS total_assignee_stations,
    tm.minutes_reply_calendar,
    tm.minutes_reply_business,
    tm.minutes_first_resolution_business,
    tm.minutes_first_resolution_calendar,
    tm.minutes_requester_wait_business,
    tm.minutes_requester_wait_calendar,
    tm.minutes_agent_wait_business,
    tm.minutes_agent_wait_calendar,
    tm.minutes_on_hold_business,
    tm.minutes_on_hold_calendar,
    tm.minutes_full_resolution_business,
    tm.minutes_full_resolution_calendar,
    CAST(tm.reopens AS SMALLINT) AS reopens,
    CAST(tm.replies AS SMALLINT) AS replies,
    tm.ts_initially_assigned AS ts_initially_assigned,
    FROM_UTC_TIMESTAMP(tm.ts_initially_assigned, 'Brazil/East') AS ts_initially_assigned_local,
    tm.ts_assigned AS ts_last_assigned,
    FROM_UTC_TIMESTAMP(tm.ts_assigned, 'Brazil/East') AS ts_last_assigned_local,
    tm.ts_solved AS ts_solved,
    FROM_UTC_TIMESTAMP(tm.ts_solved, 'Brazil/East') AS ts_solved_local,
    t.tags, -- included to enable id_user relationship model
    COALESCE(CAST(t.id_requester AS BIGINT), -1) AS id_zendesk_requester_user,
    COALESCE(CAST(t.id_submitter AS BIGINT), -1) AS id_zendesk_submitter_user,
    COALESCE(CAST(t.id_assignee AS BIGINT), -1) AS id_zendesk_assignee_user,
    t.ts_created AS ts_created,
    DATE_FORMAT(t.ts_created, '%Y-%m-%d') AS str_created_date,
    t.ts_created_local AS ts_created_local,
    t.ts_updated AS ts_updated,
    FROM_UTC_TIMESTAMP(t.ts_updated, 'Brazil/East') AS ts_updated_local,
    CASE
        WHEN t.status='closed' THEN t.ts_updated
        ELSE NULL
    END AS ts_closed,
    CASE
        WHEN t.status='closed' THEN FROM_UTC_TIMESTAMP(t.ts_updated, 'Brazil/East')
        ELSE NULL
    END AS ts_closed_local,
    t.ts_load AS ts_load
FROM
    datalake_zendesk_tickets_clean.tickets t
LEFT JOIN
    datalake_zendesk_tickets_clean.ticket_metrics tm
        ON t.id_ticket=tm.id_ticket
LEFT JOIN
    custom_field_ids cfi
        ON t.id_ticket = cfi.id_ticket
WHERE
(
    t.ticket_via <> 'api'
    OR (
        t.ticket_via = 'api'
        AND t.tags NOT LIKE '%hsm%'
    )
)
