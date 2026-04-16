WITH old_entry_model AS (
    WITH access_type AS (
        SELECT
            access.id_house,
            access.id_occupant,
            occupant.name AS occupant_type,
            restriction.name AS restriction_type,
            key.name AS key_type,
            access.additional_info AS entry_model_details,
            CASE
                WHEN authorization.name = "LockBox" THEN "LOCK_BOX"
                WHEN authorization.name = "FrontDoor" THEN "FRONT_DOOR"
                WHEN authorization.name = "KeysLocker" THEN "LOCKER"
                WHEN authorization.name = "KeysWithAgent" THEN "AGENT"
                WHEN authorization.name = "OwnerPresent" THEN "OWNER"
                ELSE UPPER(authorization.name)
            END AS key_location,
            authorization.name AS authorization_type,
            access.has_opted_keys_with_agent,
            NULL AS entry_model_channel,
            NULL AS actor_role,
            NULL AS key_holder_name,
            NULL AS key_holder_contact,
            ure.ts_revision AS ts_entrance_started
        FROM
            datalake_ebdb_clean.access_type_aud AS access
        LEFT JOIN
            datalake_ebdb_clean.access_authorization_type AS authorization
                ON access.id_authorization = authorization.id
        LEFT JOIN
            datalake_ebdb_clean.occupant_type AS occupant
                ON access.id_occupant = occupant.id
        LEFT JOIN
            datalake_ebdb_clean.restriction_type AS restriction
                ON access.id_restriction = restriction.id
        LEFT JOIN
            datalake_ebdb_clean.key_type AS key
                ON access.id_type = key.id
        LEFT JOIN
            datalake_ebdb_user.user_revision_entity AS ure
                ON access.rev = ure.id
        WHERE
            access.id_house IS NOT NULL
        QUALIFY
            ROW_NUMBER() OVER(PARTITION BY access.id_house, ure.ts_revision ORDER BY access.rev) = 1
    ),
    inspection AS (
        SELECT
            c.id_house,
            NULL AS id_occupant,
            NULL AS occupant_type,
            NULL AS restriction_type,
            NULL AS key_type,
            i.details AS entry_model_details,
            CASE
                WHEN i.inspector_key_location_type = 'GATEHOUSE' THEN 'FRONT_DOOR'
                WHEN i.inspector_key_location_type = 'LOCKBOX' THEN 'LOCK_BOX'
                WHEN i.inspector_key_location_type = 'PERSONALLYWITHSOMEONE' THEN 'EXTERNAL_RESPONSIBLE'
                WHEN i.inspector_key_location_type = 'KEYSWITHAGENT' THEN 'AGENT'
                ELSE i.inspector_key_location_type
            END AS key_location,
            NULL AS authorization_type,
            NULL AS has_opted_keys_with_agent,
            'INSPECTION_APP' AS entry_model_channel,
            'INSPECTOR' AS actor_role,
            NULL AS key_holder_name,
            NULL AS key_holder_contact,
            i.ts_created AS ts_entrance_started
        FROM
            datalake_klefki_clean.inspection_key_retrieval_confirmation AS i
        JOIN
            datalake_ebdb_clean.contract AS c
                ON i.id_contract = c.id
        WHERE
            i.ts_created::DATE < '2025-03-01'
    ),
    tenant AS (
        SELECT
            id_property AS id_house,
            NULL AS id_occupant,
            NULL AS occupant_type,
            NULL AS restriction_type,
            NULL AS key_type,
            NULL AS entry_model_details,
            CASE
                WHEN location = 'PERSONALLYWITHMYSELF' THEN 'TENANT'
                WHEN location = 'GATEHOUSE' THEN 'FRONT_DOOR'
                WHEN location = 'PERSONALLYWITHSOMEONE' THEN 'EXTERNAL_RESPONSIBLE'
                WHEN location = 'LOCKBOX' THEN 'LOCK_BOX'
                ELSE location
            END AS key_location,
            NULL AS authorization_type,
            NULL AS has_opted_keys_with_agent,
            'TENANT_PWA' AS entry_model_channel,
            'TENANT' AS actor_role,
            responsible_person_name AS key_holder_name,
            responsible_person_phone AS key_holder_contact,
            ts_created AS ts_entrance_started
        FROM
            datalake_klefki_clean.key_delivery_location
        WHERE
            ts_created::DATE < '2025-03-01'
    ),
    union_old AS (
        SELECT
            id_house,
            id_occupant,
            occupant_type,
            restriction_type,
            key_type,
            entry_model_details,
            key_location,
            authorization_type,
            has_opted_keys_with_agent,
            entry_model_channel,
            actor_role,
            key_holder_name,
            key_holder_contact,
            ts_entrance_started
        FROM
            access_type
        UNION ALL
        SELECT
            id_house,
            id_occupant,
            occupant_type,
            restriction_type,
            key_type,
            entry_model_details,
            key_location,
            authorization_type,
            has_opted_keys_with_agent,
            entry_model_channel,
            actor_role,
            key_holder_name,
            key_holder_contact,
            ts_entrance_started
        FROM
            inspection
        UNION ALL
        SELECT
            id_house,
            id_occupant,
            occupant_type,
            restriction_type,
            key_type,
            entry_model_details,
            key_location,
            authorization_type,
            has_opted_keys_with_agent,
            entry_model_channel,
            actor_role,
            key_holder_name,
            key_holder_contact,
            ts_entrance_started
        FROM
            tenant
    )
    SELECT
        id_house,
        COALESCE(id_occupant, LAG(id_occupant) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_entrance_started)) AS id_occupant,
        COALESCE(occupant_type, LAG(occupant_type) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_entrance_started)) AS occupant_type,
        COALESCE(restriction_type, LAG(restriction_type) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_entrance_started)) AS restriction_type,
        COALESCE(key_type, LAG(key_type) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_entrance_started)) AS key_type,
        entry_model_details,
        key_location,
        authorization_type,
        has_opted_keys_with_agent,
        entry_model_channel,
        actor_role,
        key_holder_name,
        key_holder_contact,
        ts_entrance_started
    FROM union_old
),
new_entry_model AS (
    SELECT
        id_house,
        entry_access_details AS entry_model_details,
        IF(entry_access_type = "KEY_HOLDER", key_holder_role, entry_access_type) AS key_location,
        IF(key_holder_role = 'AGENT' AND event_type != 'KEY_HOLDER_DEALLOCATED', TRUE, FALSE) AS has_opted_keys_with_agent,
        channel AS entry_model_channel,
        actor_role,
        event_type,
        entry_access_model,
        key_holder_type,
        key_holder_identifier,
        key_holder_name,
        key_holder_contact,
        key_holder_business_context,
        actor_user_type,
        "NEW_MODEL" AS entry_model_source,
        ts_created AS ts_entrance_started
    FROM
        datalake_ebdb_clean.entry_access_tracking
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_house, ts_created ORDER BY id) = 1
),
new_entry_model_enriched AS ( -- new entry model enriched with old entry model because some fields are not present in the new model
    SELECT
        new.id_house,
        old.id_occupant,
        old.occupant_type,
        old.restriction_type,
        old.key_type,
        new.entry_model_details,
        new.key_location,
        old.authorization_type,
        new.has_opted_keys_with_agent,
        new.entry_model_channel,
        new.actor_role,
        new.event_type,
        new.entry_access_model,
        new.key_holder_type,
        new.key_holder_identifier,
        new.key_holder_name,
        new.key_holder_contact,
        new.key_holder_business_context,
        new.actor_user_type,
        new.entry_model_source,
        new.ts_entrance_started
    FROM
        new_entry_model AS new
    LEFT JOIN
        old_entry_model AS old
            ON new.id_house = old.id_house
            AND DATE_ADD(SECOND, 1, new.ts_entrance_started) >= old.ts_entrance_started
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY new.id_house, new.ts_entrance_started ORDER BY old.ts_entrance_started DESC) = 1
),
unified_model AS (
    SELECT
        id_house,
        id_occupant,
        occupant_type,
        restriction_type,
        key_type,
        entry_model_details,
        key_location,
        authorization_type,
        has_opted_keys_with_agent,
        entry_model_channel,
        actor_role,
        NULL AS event_type,
        NULL AS entry_access_model,
        NULL AS key_holder_type,
        NULL AS key_holder_identifier,
        key_holder_name,
        key_holder_contact,
        NULL AS key_holder_business_context,
        NULL AS actor_user_type,
        "OLD_MODEL" AS entry_model_source,
        ts_entrance_started
    FROM
        old_entry_model
    WHERE
        ts_entrance_started::DATE < '2025-03-01'
    UNION ALL
    SELECT
        id_house,
        id_occupant,
        occupant_type,
        restriction_type,
        key_type,
        entry_model_details,
        key_location,
        authorization_type,
        has_opted_keys_with_agent,
        entry_model_channel,
        actor_role,
        event_type,
        entry_access_model,
        key_holder_type,
        key_holder_identifier,
        key_holder_name,
        key_holder_contact,
        key_holder_business_context,
        actor_user_type,
        entry_model_source,
        ts_entrance_started
    FROM
        new_entry_model_enriched
    WHERE
        ts_entrance_started::DATE >= '2025-03-01'
),
doorman_aud AS (
    SELECT
        aud.id_house,
        aud.doorman_type,
        ure.ts_revision AS ts_created
    FROM
        datalake_ebdb_clean.house_aud AS aud
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON aud.rev= ure.id
    WHERE
        aud.id_house IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY aud.id_house, ure.ts_revision ORDER BY aud.rev DESC) = 1
),
enriched_model AS ( -- the events of entry models are enriched with the last event of house
    SELECT
        unified.id_house,
        unified.id_occupant,
        unified.occupant_type,
        unified.restriction_type,
        unified.key_type,
        unified.entry_model_details,
        unified.key_location,
        unified.authorization_type,
        unified.has_opted_keys_with_agent,
        unified.entry_model_channel,
        unified.actor_role,
        unified.event_type,
        unified.entry_access_model,
        unified.key_holder_type,
        unified.key_holder_identifier,
        unified.key_holder_name,
        unified.key_holder_contact,
        unified.key_holder_business_context,
        unified.actor_user_type,
        unified.entry_model_source,
        COALESCE(house.country_code, 'Undefined') AS country_code,
        unified.ts_entrance_started,
        doorman.doorman_type
    FROM
        unified_model AS unified
    LEFT JOIN
        datalake_ebdb_country.house AS house
            ON house.id_house = unified.id_house
    LEFT JOIN
        doorman_aud AS doorman
            ON unified.id_house = doorman.id_house
            AND unified.ts_entrance_started >= doorman.ts_created
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY unified.id_house, unified.ts_entrance_started ORDER BY doorman.ts_created DESC) = 1
),
window_model AS (
    SELECT
        id_house,
        id_occupant,
        occupant_type,
        restriction_type,
        key_type,
        entry_model_details,
        key_location,
        authorization_type,
        has_opted_keys_with_agent,
        doorman_type,
        entry_model_channel,
        actor_role,
        event_type,
        entry_access_model,
        key_holder_type,
        key_holder_identifier,
        key_holder_name,
        key_holder_contact,
        key_holder_business_context,
        actor_user_type,
        entry_model_source,
        country_code,
        LAG(occupant_type) OVER(PARTITION BY id_house ORDER BY ts_entrance_started) AS lag_occupant_type,
        COALESCE(occupant_type, -1) <> COALESCE(lag_occupant_type, -1) AS mod_occupant,
        LAG(key_type) OVER(PARTITION BY id_house ORDER BY ts_entrance_started) AS lag_key_type,
        COALESCE(key_type, -1) <> COALESCE(lag_key_type, -1) AS mod_type,
        LAG(key_location) OVER(PARTITION BY id_house ORDER BY ts_entrance_started) AS lag_key_location,
        COALESCE(key_location, -1) <> COALESCE(lag_key_location, -1) AS mod_authorization,
        LAG(has_opted_keys_with_agent) OVER(PARTITION BY id_house ORDER BY ts_entrance_started) AS lag_has_opted_keys_with_agent,
        COALESCE(has_opted_keys_with_agent::INTEGER, -1) <> COALESCE(lag_has_opted_keys_with_agent::INTEGER, -1) AS mod_has_opted_keys_with_agent,
        ts_entrance_started,
        LEAD(ts_entrance_started) OVER(PARTITION BY id_house ORDER BY ts_entrance_started) AS ts_entrance_ended,
        IF(ts_entrance_ended IS NULL, TRUE, FALSE) AS is_last_status,
        COALESCE(MAX(ts_entrance_started) OVER(PARTITION BY id_house, DATE(ts_entrance_started)) = ts_entrance_started, FALSE) AS is_last_status_of_day
    FROM
        enriched_model
),
terminations AS (
    SELECT
        id_contract,
        status,
        dt_vacancy,
        IF(status = 'DONE', DATE(ts_updated), NULL) AS dt_termination_finished
    FROM
        datalake_terminator_clean.termination
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_contract ORDER BY ts_created DESC) = 1
),
contracts AS (
    SELECT
        c.id_house,
        c.status,
        c.dt_started,
        IF(t.status = 'DONE' AND c.dt_termination > DATE('2020-01-07'), t.dt_vacancy, c.dt_termination) AS dt_termination,
        c.ts_created
    FROM
        datalake_ebdb_clean.contract AS c
    LEFT JOIN
        terminations AS t
            ON t.id_contract = c.id
)
SELECT
    MD5(wm.id_house || CAST(wm.ts_entrance_started AS STRING)) AS id,
    wm.id_house,
    CASE
        WHEN wm.occupant_type = 'Empty' AND c.status IN ('Ativo', 'Finalizado') AND wm.ts_entrance_ended IS NOT NULL THEN 2
        WHEN wm.occupant_type = 'Empty' AND c.status = 'Ativo' AND wm.ts_entrance_ended IS NULL THEN 2
        ELSE wm.id_occupant
    END AS id_occupant,
    CASE
        WHEN wm.occupant_type = 'Empty' AND c.status IN ('Ativo', 'Finalizado') AND wm.ts_entrance_ended IS NOT NULL THEN 'Tenant'
        WHEN wm.occupant_type = 'Empty' AND c.status = 'Ativo' AND wm.ts_entrance_ended IS NULL THEN 'Tenant'
        ELSE wm.occupant_type
    END AS occupant_type,
    wm.restriction_type,
    wm.key_type,
    wm.entry_model_details,
    wm.key_location,
    CASE
        wm.key_location
        WHEN 'OWNER' THEN 'ASSISTED_ENTRANCE'
        WHEN 'TENANT' THEN 'ASSISTED_ENTRANCE'
        WHEN 'INSPECTOR' THEN 'ASSISTED_ENTRANCE'
        WHEN 'EXTERNAL_RESPONSIBLE' THEN 'ASSISTED_ENTRANCE'
        WHEN 'EXTERNAL_TENANT' THEN 'ASSISTED_ENTRANCE'
        WHEN 'FRONT_DOOR' THEN 'EASY_ENTRANCE'
        WHEN 'AGENT' THEN 'EASY_ENTRANCE'
        WHEN 'PASSWORD' THEN 'EASY_ENTRANCE'
        WHEN 'LOCK_BOX' THEN 'EASY_ENTRANCE'
        WHEN 'LOCKER' THEN 'EASY_ENTRANCE'
        ELSE 'NOT_CLASSIFIED'
    END AS entry_model_type,
    wm.authorization_type,
    wm.doorman_type,
    wm.entry_model_channel,
    wm.actor_role,
    wm.event_type,
    wm.entry_access_model,
    wm.key_holder_type,
    wm.key_holder_identifier,
    wm.key_holder_name,
    wm.key_holder_contact,
    wm.key_holder_business_context,
    wm.actor_user_type,
    wm.entry_model_source,
    wm.country_code,
    wm.has_opted_keys_with_agent,
    wm.mod_authorization,
    wm.mod_occupant,
    wm.mod_type,
    wm.mod_has_opted_keys_with_agent,
    wm.is_last_status_of_day,
    wm.is_last_status,
    wm.ts_entrance_started,
    wm.ts_entrance_ended
FROM
    window_model AS wm
LEFT JOIN
    contracts AS c
        ON wm.id_house = c.id_house
        AND wm.ts_entrance_started >= c.dt_started
        AND wm.ts_entrance_started < COALESCE(c.dt_termination, NOW())
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY wm.id_house, wm.ts_entrance_started ORDER BY c.ts_created DESC) = 1
