WITH contract_house AS (
    SELECT DISTINCT
        CAST(COALESCE(dhl.id_house_listing, '-1') AS BIGINT) AS id_house_listing,
        CAST(COALESCE(dc.id_user, '-1') AS BIGINT) AS id_client,
        CAST(COALESCE(dc.id, '-1') AS BIGINT) AS id_contract,
        CAST(COALESCE(house.id_user, '-1') AS BIGINT) AS id_owner,
        dhl.ts_listing_version_start AS dt_listing_version_start,
        dhl.ts_listing_version_end AS dt_listing_version_end,
        dhl.id_house,
        COALESCE(CAST(dhl.version AS SMALLINT), 1) AS version
    FROM
        datalake_ebdb_listing.house_listing dhl
    LEFT JOIN
        datalake_ebdb_clean.contract dc
            ON dc.id_house = dhl.id_house
            AND dc.house_number = CAST(SUBSTRING(dhl.id_house_listing, -3) AS INT)
    LEFT JOIN
        datalake_ebdb_clean.rent_flow fl
            ON fl.id_current_proposal = dc.id_proposal
    LEFT JOIN
        datalake_ebdb_listing.house house
            ON house.id = fl.id_house
),
custom_field_ids AS (
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
),
tickets AS (
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
),
distinct_customer_email AS (
    SELECT DISTINCT
        cci_e.id_user,
        cci_e.customer_contact as email,
        cci_e.cpf
    FROM
        datalake_ebdb_customer_contact_identification.customer_contact_identification cci_e
    WHERE
        cci_e.channel = 'email'
),
distinct_customer_phone AS (
    SELECT DISTINCT
        cci_p.id_user,
        CASE
            WHEN cci_p.customer_contact NOT LIKE '+%' AND LENGTH(REGEXP_REPLACE(cci_p.customer_contact, '\\D|^0+', '')) < 12
                THEN CONCAT('55', REGEXP_REPLACE(cci_p.customer_contact, '\\D|^0+', ''))
                ELSE REGEXP_REPLACE(cci_p.customer_contact, '\\D|^0+', '')
        END AS phone,
        cci_p.cpf
    FROM
        datalake_ebdb_customer_contact_identification.customer_contact_identification cci_p
    WHERE
        cci_p.channel  = 'phone'
),
zendesk_user_contact AS (
    SELECT
        CAST(zu.id_user AS BIGINT) AS id_zendesk_user,
        CASE
            WHEN zu.phone NOT LIKE '+%' AND LENGTH(REGEXP_REPLACE(zu.phone, '\\D|^0+', '')) < 12
                THEN CONCAT('55', REGEXP_REPLACE(zu.phone, '\\D|^0+', ''))
                ELSE REGEXP_REPLACE(zu.phone, '\\D|^0+', '')
        END AS phone,
        zu.email
    FROM
        datalake_zendesk_tickets_clean.users zu
),
-- evaluate funnel keys FROM each ticket according to business rules
ticket_funnel_keys AS (
    SELECT
        tck.id_tckt,
        cntt_hse.id_house_listing,
        cntt_hse.id_contract AS id_contract,
        COALESCE(dc_e.id_user, dc_p.id_user) AS id_user,
        COALESCE(dc_e.cpf, dc_p.cpf) AS id_personal_document,
        -- tickets will only have a valid client key according to its corresponding client type
        CASE
            WHEN tck.client_type = 'inquilino' THEN cntt_hse.id_client
        END AS id_client,
        CASE
            WHEN tck.client_type IN ('proprietário','imobiliária_b2b') THEN cntt_hse.id_owner -- COALESCE(dc.id_owner, dhl.id_owner)
        END AS id_owner
    FROM
        tickets tck
    LEFT JOIN
        contract_house cntt_hse
            ON tck.id_house = cntt_hse.id_house
            AND tck.id_contract = cntt_hse.id_contract
    LEFT JOIN
        zendesk_user_contact zuc
            ON zuc.id_zendesk_user = tck.id_zendesk_requester_user
    LEFT JOIN
        distinct_customer_email dc_e
            ON dc_e.email = zuc.email
    LEFT JOIN
        distinct_customer_phone dc_p
            ON dc_p.phone = zuc.phone
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
    tickets t
INNER JOIN
    ticket_funnel_keys fk
        ON t.id_tckt = fk.id_tckt
