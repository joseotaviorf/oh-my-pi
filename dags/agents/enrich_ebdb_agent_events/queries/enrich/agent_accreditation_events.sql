WITH user_revision_entity AS (
    SELECT
        id,
        CAST(ts_revision / 1000 AS TIMESTAMP) AS ts_revision
    FROM
        datalake_ebdb_clean.user_revision_entity
),
last_agent_updated AS (
    SELECT
        id_unified_agent,
        id_user,
        id_agent,
        id_agent_data,
        id_partner,
        uuid_person,
        is_agent_data_replace_key,
        is_partner_replace_key
    FROM
        datalake_ebdb_agent_events.agent_unified_identity
    WHERE
        DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
agent_accreditation_history AS (
    SELECT
        updated.id_unified_agent,
        updated.id_agent,
        updated.id_agent_data,
        updated.id_partner,
        updated.uuid_person,
        SPLIT(events.event_type, '_')[1] AS event,
        CASE
          WHEN ARRAY_CONTAINS(SPLIT(events.reason, '_'), "REENROLLMENT") THEN "INACTIVE_AGENT_REENROLLMENT"
          WHEN TRIM(events.reason) LIKE "%MIGRATION_ACCREDITATION" THEN "LEGACY_AGENT_MIGRATION"
          WHEN TRIM(events.reason) LIKE "%MIGRATION_BACKFILL" THEN "LEGACY_AGENT_MIGRATION_BACKFILL"
          WHEN ARRAY_CONTAINS(SPLIT(events.reason, '_'), "DEACCREDITATION") THEN "AGENT_DEACCREDITATION"
          WHEN ARRAY_CONTAINS(SPLIT(events.reason, '_'), "ACCREDITATION") 
            AND NOT ARRAY_CONTAINS(SPLIT(events.reason, '_'), "MIGRATION")
            THEN "AGENT_ACCREDITATION"
        END AS event_reason,
        events.event_type IN ("AGENT_ACTIVATED", "AGENT_REACTIVATED") AS is_active,
        events.ts_created,
        FIRST_VALUE(events.ts_created) OVER (PARTITION BY events.id_agent ORDER BY events.ts_created ASC) AS ts_first_event
    FROM
        last_agent_updated AS updated
    JOIN
        datalake_ebdb_clean.agent_event_log AS events
            ON events.id_agent = updated.id_agent
    WHERE
        events.event_type IN ("AGENT_ACTIVATED", "AGENT_INACTIVATED", "AGENT_REACTIVATED")
),
agent_data_accreditation AS (
    SELECT
        updated.id_unified_agent,
        updated.id_agent,
        updated.id_agent_data,
        updated.id_partner,
        updated.uuid_person,
        a.rev_type,
        COALESCE(  
            (
                MIN(IF(a.is_active IS TRUE, u.ts_revision, NULL)) OVER (PARTITION BY a.id ORDER BY u.ts_revision) = u.ts_revision
                AND a.is_active IS TRUE
            ),
            FALSE
        ) AS is_first_active,
        a.is_active,
        LAG(a.is_active) OVER (PARTITION BY a.id ORDER BY u.ts_revision) AS previous_is_active,
        COALESCE(
            LAG(a.is_active) OVER (PARTITION BY a.id ORDER BY u.ts_revision),
            FALSE
        ) <> a.is_active AS mod_is_active,
        u.ts_revision
    FROM
        last_agent_updated AS updated
    JOIN
        datalake_ebdb_clean.agent_data_aud AS a
            ON a.id = updated.id_agent_data
    JOIN 
        user_revision_entity AS u 
            ON u.id = a.rev
    WHERE
        updated.is_agent_data_replace_key IS TRUE
),
agent_data_accreditation_events AS (
    SELECT
        ac.id_unified_agent,
        ac.id_agent,
        ac.id_agent_data,
        ac.id_partner,
        ac.uuid_person,
        CASE 
            WHEN ac.rev_type = 0 
                AND ac.is_active IS TRUE
                THEN "ACTIVATED"  
            WHEN ac.rev_type = 0 
                AND ac.is_active IS FALSE
                THEN "INACTIVATED"  
            WHEN 
                ac.rev_type = 1 
                AND ac.is_first_active IS TRUE 
                AND ac.mod_is_active IS TRUE 
                AND ac.is_active IS TRUE 
                AND ac.previous_is_active IS FALSE 
                THEN "ACTIVATED"   
            WHEN 
                ac.rev_type = 1 
                AND ac.mod_is_active IS TRUE 
                AND ac.is_active IS FALSE 
                THEN "INACTIVATED"  
            WHEN 
                ac.rev_type = 1 
                AND ac.is_first_active IS FALSE 
                AND ac.mod_is_active IS TRUE 
                AND ac.is_active IS TRUE 
                AND ac.previous_is_active IS FALSE 
                THEN "REACTIVATED"  
        END AS event,
        CASE
            WHEN 
                ac.rev_type = 1 
                AND ac.mod_is_active IS TRUE 
                AND ac.is_active IS FALSE 
                THEN "AGENT_DEACCREDITATION"
            ELSE "AGENT_ACCREDITATION"
        END AS event_reason,
        ac.is_active,
        ac.ts_revision
    FROM
        agent_data_accreditation AS ac
),
agent_data_accreditation_history AS (
    SELECT
        ac.id_unified_agent,
        ac.id_agent,
        ac.id_agent_data,
        ac.id_partner,
        ac.uuid_person,
        ac.event,
        ac.event_reason,
        ac.is_active,
        ac.ts_revision
    FROM
        agent_data_accreditation_events AS ac
    LEFT JOIN
        agent_accreditation_history AS new
            ON ac.id_agent = new.id_agent
    WHERE
        new.id_agent IS NULL
        OR (
            ac.event = "INACTIVATED"
            AND ac.ts_revision < new.ts_first_event
        )
        OR (
            ac.event <> "INACTIVATED"
            AND new.event = "ACTIVATED" 
            AND DATE(ac.ts_revision) < DATE(new.ts_created)
        )   
),
partner_accreditation AS (
    SELECT
        updated.id_unified_agent,
        updated.id_agent,
        updated.id_agent_data,
        updated.id_partner,
        updated.uuid_person,
        paa.status,
        COALESCE(LAG(paa.status) OVER(PARTITION BY paa.id_partner ORDER BY paa.rev) <> paa.status, TRUE) AS mod_status, 
        COALESCE(  
            (
                MIN(IF(paa.status = 'ACTIVE', u.ts_revision, NULL)) OVER (PARTITION BY paa.id_partner ORDER BY u.ts_revision) = u.ts_revision
                AND paa.status = 'ACTIVE'
            ),
            FALSE
        ) AS is_first_active,
        u.ts_revision
    FROM
        last_agent_updated AS updated
    JOIN
        datalake_ebdb_clean.partner_agent_aud AS paa
            ON paa.id_partner = updated.id_partner
    JOIN
        datalake_ebdb_clean.partner AS p
            ON p.id = paa.id_partner
    LEFT JOIN
        user_revision_entity AS u
            ON paa.rev = u.id
    WHERE
        p.type = 'AUTONOMOUS_AGENT'
        AND updated.is_partner_replace_key IS TRUE
),
partner_accreditation_history AS (
    SELECT
        pah.id_unified_agent,
        pah.id_agent,
        pah.id_agent_data,
        pah.id_partner,
        pah.uuid_person,
        CASE
            WHEN pah.status = "ACTIVE" 
              AND pah.is_first_active IS TRUE
              THEN "ACTIVATED"
            WHEN pah.status = "ACTIVE" 
              AND pah.is_first_active IS FALSE
              THEN "REACTIVATED"
            WHEN pah.status = "INACTIVE" THEN "INACTIVATED"
        END AS event,
        CASE
            WHEN pah.status = "ACTIVE" THEN "AGENT_ACCREDITATION"
            WHEN pah.status = "INACTIVE" THEN "AGENT_DEACCREDITATION"
        END AS event_reason,
        pah.ts_revision
    FROM
        partner_accreditation AS pah
    LEFT JOIN
        agent_accreditation_history AS new
            ON pah.id_agent = new.id_agent
    WHERE 
        pah.mod_status IS TRUE
        AND (
          new.id_agent IS NULL
          OR (
            pah.status = "INACTIVE"
            AND pah.ts_revision < new.ts_first_event
          )
          OR (
              pah.status <> "INACTIVE"
              AND new.event = "ACTIVATED" 
              AND DATE(pah.ts_revision) < DATE(new.ts_created)
          )  
        )
),
union_sources AS (
    SELECT
        id_unified_agent,
        id_agent,
        id_agent_data,
        id_partner,
        uuid_person,
        "AGENT_DOMAIN" AS source,
        event,
        event_reason,
        ts_created
    FROM
        agent_accreditation_history
    UNION
    SELECT 
        id_unified_agent,
        id_agent,
        id_agent_data,
        id_partner,
        uuid_person,
        "AGENT_DATA" AS source,
        event,
        event_reason,
        ts_revision AS ts_created
    FROM 
        agent_data_accreditation_history
    WHERE
        event IS NOT NULL
    UNION
    SELECT 
        id_unified_agent,
        id_agent,
        id_agent_data,
        id_partner,
        uuid_person,
        "PARTNER_DATA" AS source,
        event,
        event_reason,
        ts_revision AS ts_created
    FROM 
        partner_accreditation_history
    WHERE
        event IS NOT NULL
),
person_events AS (
  SELECT
      id_unified_agent,
      id_agent,
      id_agent_data,
      id_partner,
      uuid_person,
      source,
      event,
      event_reason,
      LAG(source) OVER(PARTITION BY id_unified_agent ORDER BY ts_created) <> source AS is_new_source,
      LAG(event) OVER(PARTITION BY id_unified_agent ORDER BY ts_created) = "INACTIVATED" AS is_previous_inactivated,
      ts_created
  FROM
      union_sources
)
SELECT
    XXHASH64(id_unified_agent, source, event, ts_created) AS id_event,
    id_unified_agent,
    id_agent,
    id_agent_data,
    id_partner,
    uuid_person,
    source,
    CASE
        WHEN source = "AGENT_DOMAIN"
            AND event = "ACTIVATED"
            AND is_new_source IS TRUE
            AND is_previous_inactivated IS TRUE
            THEN "REACTIVATED"
        WHEN source = "AGENT_DOMAIN"
            AND is_new_source IS TRUE
            AND is_previous_inactivated IS FALSE
            AND event_reason LIKE "%MIGRATION%" 
            THEN "MIGRATED"
        ELSE event
    END AS event,
    event_reason,
    (
        source = "AGENT_DOMAIN"
        AND is_new_source IS TRUE
        AND event_reason LIKE "%MIGRATION%"
    ) AS has_source_migrated,
    event <> "INACTIVATED" AS is_active,
    ts_created
FROM
    person_events