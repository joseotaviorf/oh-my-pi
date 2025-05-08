WITH old_entry_model AS (
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
        END AS key_location_unified,
        authorization.name AS key_location,
        access.has_opted_keys_with_agent,
        NULL AS entry_model_channel,
        NULL AS actor_role,
        NULL AS event_type,
        NULL AS entry_access_model,
        NULL AS key_holder_type,
        NULL AS key_holder_identifier,
        NULL AS key_holder_business_context,
        NULL AS actor_user_type,
        "OLD_MODEL" AS entry_model_source,
        ure.ts_revision AS ts_updated
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
        ROW_NUMBER() OVER(PARTITION BY access.id_house, DATE_TRUNC("SECOND", ure.ts_revision) ORDER BY ure.ts_revision DESC, access.rev DESC) = 1
),
new_entry_model AS (
    SELECT
        id_house,
        NULL AS id_occupant,
        NULL AS occupant_type,
        NULL AS restriction_type,
        NULL AS key_type,
        entry_access_details AS entry_model_details,
        IF(entry_access_type = "KEY_HOLDER", key_holder_role, entry_access_type) AS key_location_unified,
        NULL AS key_location,
        NULL AS has_opted_keys_with_agent,
        channel AS entry_model_channel,
        actor_role,
        event_type,
        entry_access_model,
        key_holder_type,
        key_holder_identifier,
        key_holder_business_context,
        actor_user_type,
        "NEW_MODEL" AS entry_model_source,
        ts_updated
    FROM
        datalake_ebdb_clean.entry_access_tracking
    WHERE
        id_house IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_house, DATE_TRUNC("SECOND", ts_updated) ORDER BY ts_updated DESC, ts_created DESC) = 1
),
unified_model AS ( -- When a field is null in the new model, we will consider the value from the old model
    SELECT
        COALESCE(new_entry_model.id_house, old_entry_model.id_house) AS id_house,
        COALESCE(new_entry_model.id_occupant, old_entry_model.id_occupant) AS id_occupant,
        COALESCE(new_entry_model.occupant_type, old_entry_model.occupant_type) AS occupant_type,
        COALESCE(new_entry_model.restriction_type, old_entry_model.restriction_type) AS restriction_type,
        COALESCE(new_entry_model.key_type, old_entry_model.key_type) AS key_type,
        COALESCE(new_entry_model.entry_model_details, old_entry_model.entry_model_details) AS entry_model_details,
        COALESCE(new_entry_model.key_location_unified, old_entry_model.key_location_unified) AS key_location_unified,
        COALESCE(new_entry_model.key_location, old_entry_model.key_location) AS key_location,
        COALESCE(new_entry_model.has_opted_keys_with_agent, old_entry_model.has_opted_keys_with_agent) AS has_opted_keys_with_agent,
        COALESCE(new_entry_model.entry_model_channel, old_entry_model.entry_model_channel) AS entry_model_channel,
        COALESCE(new_entry_model.actor_role, old_entry_model.actor_role) AS actor_role,
        COALESCE(new_entry_model.event_type, old_entry_model.event_type) AS event_type,
        COALESCE(new_entry_model.entry_access_model, old_entry_model.entry_access_model) AS entry_access_model,
        COALESCE(new_entry_model.key_holder_type, old_entry_model.key_holder_type) AS key_holder_type,
        COALESCE(new_entry_model.key_holder_identifier, old_entry_model.key_holder_identifier) AS key_holder_identifier,
        COALESCE(new_entry_model.key_holder_business_context, old_entry_model.key_holder_business_context) AS key_holder_business_context,
        COALESCE(new_entry_model.actor_user_type, old_entry_model.actor_user_type) AS actor_user_type,
        CASE
            WHEN new_entry_model.entry_model_source IS NOT NULL AND old_entry_model.entry_model_source IS NOT NULL THEN "NEW_AND_OLD_MODEL"
            WHEN new_entry_model.entry_model_source IS NULL AND old_entry_model.entry_model_source IS NOT NULL THEN "OLD_MODEL"
            WHEN new_entry_model.entry_model_source IS NOT NULL AND old_entry_model.entry_model_source IS NULL THEN "NEW_MODEL"
        END AS entry_model_source,
        COALESCE(new_entry_model.ts_updated, old_entry_model.ts_updated) AS ts_updated
    FROM
        old_entry_model
    FULL OUTER JOIN
        new_entry_model
            ON old_entry_model.id_house = new_entry_model.id_house
            AND DATE_TRUNC("SECOND", old_entry_model.ts_updated) = DATE_TRUNC("SECOND", new_entry_model.ts_updated)
),
doorman_aud AS (
    SELECT
        aud.id_house,
        aud.doorman_type,
        ure.ts_revision AS ts_updated
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
        unified.key_location_unified,
        unified.key_location,
        unified.has_opted_keys_with_agent,
        unified.entry_model_channel,
        unified.actor_role,
        unified.event_type,
        unified.entry_access_model,
        unified.key_holder_type,
        unified.key_holder_identifier,
        unified.key_holder_business_context,
        unified.actor_user_type,
        unified.entry_model_source,
        COALESCE(house.country_code, 'Undefined') AS country_code,
        unified.ts_updated,
        doorman.doorman_type
    FROM
        unified_model AS unified
    LEFT JOIN
        datalake_ebdb_country.house AS house
            ON house.id_house = unified.id_house
    LEFT JOIN
        doorman_aud AS doorman
            ON unified.id_house = doorman.id_house
            AND DATE_TRUNC("SECOND", unified.ts_updated) >= DATE_TRUNC("SECOND", doorman.ts_updated)
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY unified.id_house, unified.ts_updated ORDER BY doorman.ts_updated DESC) = 1
),
lag_model AS (
    SELECT
        id_house,
        COALESCE(id_occupant, LAG(id_occupant) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_updated)) AS id_occupant,
        COALESCE(occupant_type, LAG(occupant_type) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_updated)) AS occupant_type,
        COALESCE(restriction_type, LAG(restriction_type) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_updated)) AS restriction_type,
        COALESCE(key_type, LAG(key_type) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_updated)) AS key_type,
        entry_model_details,
        key_location_unified,
        COALESCE(key_location, LAG(key_location) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_updated)) AS key_location,
        COALESCE(has_opted_keys_with_agent, LAG(has_opted_keys_with_agent) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_updated)) AS has_opted_keys_with_agent,
        doorman_type,
        entry_model_channel,
        actor_role,
        event_type,
        entry_access_model,
        key_holder_type,
        key_holder_identifier,
        key_holder_business_context,
        actor_user_type,
        entry_model_source,
        country_code,
        LAG(id_occupant) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_id_occupant,
        LAG(occupant_type) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_occupant_type,
        LAG(restriction_type) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_restriction_type,
        LAG(key_type) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_key_type,
        LAG(key_location) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_key_location,
        LAG(has_opted_keys_with_agent) IGNORE NULLS OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_has_opted_keys_with_agent,
        LAG(entry_model_details) OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_entry_model_details,
        LAG(key_location_unified) OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_key_location_unified,
        LAG(doorman_type) OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_doorman_type,
        LAG(entry_model_channel) OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_entry_model_channel,
        LAG(actor_role) OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_actor_role,
        LAG(event_type) OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_event_type,
        LAG(key_holder_identifier) OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_key_holder_identifier,
        LAG(actor_user_type) OVER(PARTITION BY id_house ORDER BY ts_updated) AS lag_actor_user_type,
        ts_updated AS ts_entrance_started
    FROM
        enriched_model
)
SELECT
    MD5(id_house || CAST(ts_entrance_started AS STRING)) AS id,
    id_house,
    id_occupant,
    occupant_type,
    restriction_type,
    key_type,
    entry_model_details,
    key_location_unified,
    key_location,
    doorman_type,
    entry_model_channel,
    actor_role,
    event_type,
    entry_access_model,
    key_holder_type,
    key_holder_identifier,
    key_holder_business_context,
    actor_user_type,
    entry_model_source,
    country_code,
    has_opted_keys_with_agent,
    COALESCE(key_location, -1) <> COALESCE(lag_key_location, -1) AS mod_authorization,
    COALESCE(occupant_type, -1) <> COALESCE(lag_occupant_type, -1) AS mod_occupant,
    COALESCE(key_type, -1) <> COALESCE(lag_key_type, -1) AS mod_type,
    COALESCE(has_opted_keys_with_agent::INTEGER, -1) <> COALESCE(lag_has_opted_keys_with_agent::INTEGER, -1) AS mod_has_opted_keys_with_agent,
    COALESCE(MAX(lag_model.ts_entrance_started) OVER(PARTITION BY lag_model.id_house, DATE(lag_model.ts_entrance_started)) = lag_model.ts_entrance_started, FALSE) AS is_last_status_of_day,
    ts_entrance_started,
    LEAD(lag_model.ts_entrance_started) OVER(PARTITION BY lag_model.id_house ORDER BY lag_model.ts_entrance_started) AS ts_entrance_ended
FROM
    lag_model
WHERE
    (id_occupant <> COALESCE(lag_id_occupant, -1))
    OR (occupant_type <> COALESCE(lag_occupant_type, -1))
    OR (restriction_type <> COALESCE(lag_restriction_type, -1))
    OR (key_type <> COALESCE(lag_key_type, -1))
    OR (entry_model_details <> COALESCE(lag_entry_model_details, -1))
    OR (key_location_unified <> COALESCE(lag_key_location_unified, -1))
    OR (doorman_type <> COALESCE(lag_doorman_type, -1))
    OR (entry_model_channel <> COALESCE(lag_entry_model_channel, -1))
    OR (actor_role <> COALESCE(lag_actor_role, -1))
    OR (event_type <> COALESCE(lag_event_type, -1))
    OR (key_holder_identifier <> COALESCE(lag_key_holder_identifier, -1))
    OR (actor_user_type <> COALESCE(lag_actor_user_type, -1))
    OR (has_opted_keys_with_agent::INTEGER <> COALESCE(lag_has_opted_keys_with_agent::INTEGER, -1))
    OR (key_location <> COALESCE(lag_key_location, -1))
