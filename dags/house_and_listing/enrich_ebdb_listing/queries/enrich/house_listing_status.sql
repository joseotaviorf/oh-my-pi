WITH deactivation_legacy_gate AS (
    SELECT *
    FROM (
        VALUES
            ('UNPUBLISH', 'UNPUBLISHED', 'HOUSE_NOT_AVAILABLE'),
            ('UNPUBLISH', 'UNPUBLISHED', 'HOUSE_NOT_REACHABLE'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_ALREADY_SOLD_HOUSE'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_CONSEQUENCES_MANAGEMENT'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_DOESNT_AGREE'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_GAVE_UP_RENTING'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_MISSED_NEGOTIATIONS_LIMIT_REACHED'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_OTHER'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_RENTING_DIRECT_WITH_TENANT'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_RENTING_FOR_SHORT_PERIOD'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_RENTING_WITH_OTHER_COMPANY'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_REQUESTED_TERMINATION'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OWNER_SELLING_HOUSE'),
            ('UNPUBLISH', 'UNPUBLISHED', 'REQUEST_BY_OWNER_REAL_STATE'),
            ('UNPUBLISH', 'UNPUBLISHED', 'OwnerConsequencesManagement'),
            ('SUSPEND', 'SUSPENDED', 'OWNER_GAVE_UP_RENTING'),
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
        hel.business_context = 'RENT'
        AND hel.event_type = 'LISTING_STATUS_UPDATE'
        AND hlsl.status_to IN ('UNPUBLISHED', 'SUSPENDED')
),
status_base AS (
    SELECT
        CAST(CAST(lbc_version.id_house AS STRING) || '00' || CAST(lbc_version.listing_version AS STRING) AS BIGINT) AS id_house_listing,
        lbc_version.id_house,
        house.id_region,
        lbc_version.country_code,
        lbc_version.listing_version AS version,
        lbc_version.status AS status_history,
        lbc_version.status_reason AS status_change_reason,
        lbc_version.revision_reason,
        COALESCE(
            -- get MAX ts per id_house_listings per day
            MAX(lbc_version.rev) OVER (
                PARTITION BY lbc_version.id_house, lbc_version.listing_version, CAST(lbc_version.ts_state_started AS DATE)
            ) = lbc_version.rev,
            FALSE
        ) AS is_last_status_of_day,
        lbc_version.ts_first_publication,
        lbc_version.ts_state_started AS ts_status_started,
        lbc_version.ts_state_ended AS ts_status_ended,
        gate.deactivation_type,
        COALESCE(house_enrich.is_rent_3p_supply, FALSE) AS is_rent_3p_supply
    FROM
        datalake_ebdb_listing.lbc_status_version_order AS lbc_version
    JOIN
        datalake_ebdb_clean.house AS house
            ON house.id = lbc_version.id_house
    LEFT JOIN
        deactivation_legacy_gate AS gate
            ON lbc_version.status = gate.status_history
            AND lbc_version.status_reason = gate.status_change_reason
    LEFT JOIN
        datalake_ebdb_listing.house AS house_enrich
            ON house_enrich.id = lbc_version.id_house
            AND house_enrich.country_code = lbc_version.country_code
),
deactivation_log_ranked AS (
    SELECT
        status_base.id_house_listing,
        status_base.ts_status_started,
        log_event.reason,
        log_event.reason_category,
        log_event.additional_context,
        ROW_NUMBER() OVER (
            PARTITION BY status_base.id_house_listing, status_base.ts_status_started
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
        AND NOT status_base.is_rent_3p_supply
)
SELECT
    status_base.id_house_listing,
    status_base.id_house,
    status_base.id_region,
    status_base.country_code,
    status_base.version,
    status_base.status_history,
    status_base.status_change_reason,
    CASE
        WHEN status_base.deactivation_type IS NOT NULL
            AND NOT status_base.is_rent_3p_supply
            AND deactivation_log_ranked.deactivation_log_rn = 1
            THEN deactivation_log_ranked.reason
    END AS deactivation_reason,
    CASE
        WHEN status_base.deactivation_type IS NOT NULL
            AND NOT status_base.is_rent_3p_supply
            AND deactivation_log_ranked.deactivation_log_rn = 1
            THEN deactivation_log_ranked.reason_category
    END AS deactivation_reason_category,
    CASE
        WHEN status_base.deactivation_type IS NOT NULL
            AND NOT status_base.is_rent_3p_supply
            AND deactivation_log_ranked.deactivation_log_rn = 1
            THEN deactivation_log_ranked.additional_context
    END AS deactivation_additional_context,
    status_base.revision_reason,
    status_base.is_last_status_of_day,
    status_base.ts_first_publication,
    status_base.ts_status_started,
    status_base.ts_status_ended
FROM
    status_base
LEFT JOIN
    deactivation_log_ranked
        ON status_base.id_house_listing = deactivation_log_ranked.id_house_listing
        AND status_base.ts_status_started = deactivation_log_ranked.ts_status_started
        AND deactivation_log_ranked.deactivation_log_rn = 1
