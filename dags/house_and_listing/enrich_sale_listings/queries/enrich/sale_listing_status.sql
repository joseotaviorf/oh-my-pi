WITH deactivation_legacy_gate AS (
    SELECT *
    FROM (
        VALUES
            ('UNPUBLISH', 'UNPUBLISHED', 'HOUSE_NOT_AVAILABLE'),
            ('UNPUBLISH', 'UNPUBLISHED', 'HOUSE_NOT_REACHABLE'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_ALREADY_SOLD_HOUSE'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_CONSEQUENCES_MANAGEMENT'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_DOESNT_AGREE'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_GAVE_UP_SALE'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_OTHER'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_RENTED_HOUSE'),
            ('UNPUBLISH', 'UNPUBLISHED', 'REQUEST_BY_OWNER_REAL_STATE'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OwnerConsequencesManagement'),
            ('SUSPEND', 'SUSPENDED', 'OWNER_GAVE_UP_SALE'),
            ('SUSPEND', 'SUSPENDED', 'OwnerConsequencesManagement'),
            ('SUSPEND', 'SUSPENDED', 'OwnerTemporarilySuspended'),
            ('SUSPEND', 'SUSPENDED', 'OwnerReforming'),
            ('SUSPEND', 'SUSPENDED', 'OwnerTraveling')
    ) AS t(deactivation_type, status_history, status_change_reason)
),
listing_status_log_events AS (
    SELECT
        hel.id_house,
        hlsl.id AS id_log,
        hlsl.status_to,
        hlsl.reason,
        hlsl.reason_category,
        hlsl.additional_context,
        hel.ts_created AS ts_event
    FROM
        datalake_ebdb_clean.house_listing_status_log AS hlsl
    INNER JOIN
        datalake_ebdb_clean.house_event_log AS hel
            ON hlsl.id = hel.id
    WHERE
        hel.business_context = 'SALE'
        AND hel.event_type = 'LISTING_STATUS_UPDATE'
        AND hlsl.status_to IN ('UNPUBLISHED', 'SUSPENDED')
),
status_base AS (
    SELECT
        BIGINT(STRING(ssvo.id_house) || '00' || STRING(ssvo.order_version)) AS id_sale_listing,
        ssvo.id_house,
        ssvo.id_user_revision,
        ssvo.id_region,
        h.uuid_company,
        h.partner_3p_supply,
        ssvo.status_history_new AS status_history,
        ssvo.status_closing_history,
        ssvo.status_reason AS status_change_reason,
        REGEXP_REPLACE(ssvo.status_reason_detail, '\n', '') AS status_change_reason_detail,
        COALESCE(
            -- get max ts per id_house_listings per day
            MAX(ssvo.ts_status_changed_new) OVER (
                PARTITION BY ssvo.id_house
            ) = ts_status_changed_new,
            FALSE
        ) AS is_last_status,
        COALESCE(h.is_sale_3p_supply, FALSE) AS is_3p_supply,
        ssvo.ts_first_publication,
        ssvo.ts_status_changed_new AS ts_status_started,
        ssvo.ts_status_changed_next AS ts_status_ended,
        gate.deactivation_type
    FROM
        datalake_sale_listings.sale_status_version_order AS ssvo
    LEFT JOIN
        datalake_ebdb_listing.house AS h
            ON ssvo.id_house = h.id
    LEFT JOIN
        deactivation_legacy_gate AS gate
            ON ssvo.status_history_new = gate.status_history
            AND ssvo.status_reason = gate.status_change_reason
),
deactivation_log_ranked AS (
    SELECT
        status_base.id_sale_listing,
        status_base.ts_status_started,
        log_event.reason,
        log_event.reason_category,
        log_event.additional_context,
        ROW_NUMBER() OVER (
            PARTITION BY status_base.id_sale_listing, status_base.ts_status_started
            ORDER BY
                ABS(UNIX_TIMESTAMP(log_event.ts_event) - UNIX_TIMESTAMP(status_base.ts_status_started)) ASC, -- closest in time
                log_event.ts_event DESC, -- latest event on tie
                CASE WHEN log_event.reason IS NULL THEN 1 ELSE 0 END ASC, -- prefer non-null reason
                log_event.id_log DESC -- deterministic tie-break; prefer newest log row
        ) AS deactivation_log_rn
    FROM
        status_base
    INNER JOIN
        listing_status_log_events AS log_event
            ON status_base.id_house = log_event.id_house
            AND (
                (status_base.deactivation_type = 'UNPUBLISH' AND log_event.status_to = 'UNPUBLISHED')
                OR (status_base.deactivation_type = 'SUSPEND' AND log_event.status_to = 'SUSPENDED')
            )
            -- 2-minute temporal match window between LBC interval start and log event
            AND ABS(UNIX_TIMESTAMP(log_event.ts_event) - UNIX_TIMESTAMP(status_base.ts_status_started)) <= 120
    WHERE
        status_base.deactivation_type IS NOT NULL
        AND NOT status_base.is_3p_supply
)
SELECT
    status_base.id_sale_listing,
    status_base.id_house,
    status_base.id_user_revision,
    status_base.id_region,
    status_base.uuid_company,
    status_base.partner_3p_supply,
    status_base.status_history,
    status_base.status_closing_history,
    status_base.status_change_reason,
    status_base.status_change_reason_detail,
    CASE
        WHEN status_base.deactivation_type IS NOT NULL
            AND NOT status_base.is_3p_supply
            AND deactivation_log_ranked.deactivation_log_rn = 1
            THEN deactivation_log_ranked.reason
    END AS deactivation_reason,
    CASE
        WHEN status_base.deactivation_type IS NOT NULL
            AND NOT status_base.is_3p_supply
            AND deactivation_log_ranked.deactivation_log_rn = 1
            THEN deactivation_log_ranked.reason_category
    END AS deactivation_reason_category,
    CASE
        WHEN status_base.deactivation_type IS NOT NULL
            AND NOT status_base.is_3p_supply
            AND deactivation_log_ranked.deactivation_log_rn = 1
            THEN deactivation_log_ranked.additional_context
    END AS deactivation_additional_context,
    status_base.is_last_status,
    status_base.is_3p_supply,
    status_base.ts_first_publication,
    status_base.ts_status_started,
    status_base.ts_status_ended
FROM
    status_base
LEFT JOIN
    deactivation_log_ranked
        ON status_base.id_sale_listing = deactivation_log_ranked.id_sale_listing
        AND status_base.ts_status_started = deactivation_log_ranked.ts_status_started
        AND deactivation_log_ranked.deactivation_log_rn = 1
