WITH old_entry_model AS (
    SELECT
        at.id_house,
        key.name AS key_type,
        occupant.name AS occupant_type,
        restriction.name AS restriction_type,
        authorization.name AS authorization_type
    FROM
        datalake_ebdb_clean.access_type AS at
    LEFT JOIN
        datalake_ebdb_clean.key_type AS key
            ON at.id_type = key.id
    LEFT JOIN
        datalake_ebdb_clean.occupant_type AS occupant
            ON at.id_occupant = occupant.id
    LEFT JOIN
        datalake_ebdb_clean.restriction_type AS restriction
            ON at.id_restriction = restriction.id
    LEFT JOIN
        datalake_ebdb_clean.access_authorization_type AS authorization
            ON at.id_authorization = authorization.id
    WHERE
        at.id_house IS NOT NULL
),
new_entry_model AS (
    SELECT
        entry.id_house,
        entry.access_model,
        IF(entry.access_type = "KEY_HOLDER", holder.holder_role, entry.access_type) AS key_location,
        entry.access_code,
        entry.access_details,
        entry.location,
        holder.holder_type,
        holder.holder_identifier,
        entry.ts_created,
        entry.ts_updated
    FROM
        datalake_ebdb_clean.entry_access AS entry
    LEFT JOIN
        datalake_ebdb_clean.key_holder AS holder
            ON entry.id = holder.id_entry_access
    WHERE
        entry.id_house IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY entry.id_house ORDER BY holder.id DESC) = 1
),
last_contract_by_house AS (
    SELECT
        id_house,
        status
    FROM
        datalake_ebdb_clean.contract
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY ts_created DESC) = 1
),
agent_events AS (
    SELECT
        id_house,
        MAX(ts_entrance_started) FILTER (WHERE key_location != 'AGENT') AS last_not_agent,
        MAX(ts_entrance_started) FILTER (WHERE key_location = 'AGENT' AND event_type = 'KEY_HOLDER_ALLOCATED') AS ts_last_agent_allocation,
        IF(ts_last_agent_allocation >= COALESCE(last_not_agent, ts_last_agent_allocation), TRUE, FALSE) AS has_agent_allocated,
        MAX(ts_entrance_started) FILTER (WHERE key_location = 'AGENT' AND event_type = 'KEY_HOLDER_VALIDATED') AS ts_last_agent_validated,
        MAX(ts_entrance_started) FILTER (WHERE key_location = 'AGENT' AND event_type = 'KEY_HOLDER_DEALLOCATED') AS ts_last_agent_deallocation,
        IF(has_agent_allocated AND ts_last_agent_validated >= ts_last_agent_allocation, TRUE, FALSE) AS has_agent_validated,
        IF(has_agent_allocated AND ts_last_agent_deallocation >= ts_last_agent_allocation, TRUE, FALSE) AS has_agent_deallocated
    FROM
        datalake_ebdb_listing.house_entrance_history
    GROUP BY 1
)
SELECT
    new.id_house,
    old.key_type,
    IF(old.occupant_type = 'Empty' AND lc.status = 'Ativo', 'Tenant', old.occupant_type) AS occupant_type,
    old.restriction_type,
    old.authorization_type,
    new.key_location,
    COALESCE(first_event.key_location, new.key_location) AS first_key_location,
    new.access_model,
    new.access_code,
    new.access_details,
    new.location,
    new.holder_type,
    new.holder_identifier,
    ae.has_agent_allocated,
    ae.has_agent_validated,
    ae.has_agent_deallocated,
    IF(ae.has_agent_allocated, ts_last_agent_allocation, NULL) AS ts_last_agent_allocation,
    IF(ae.has_agent_validated, ts_last_agent_validated, NULL) AS ts_last_agent_validated,
    IF(ae.has_agent_deallocated, ts_last_agent_deallocation, NULL) AS ts_last_agent_deallocation,
    new.ts_created,
    COALESCE(first_event.ts_entrance_started, new.ts_created) AS ts_first_event,
    new.ts_updated
FROM
    new_entry_model AS new
LEFT JOIN
    old_entry_model AS old
        ON new.id_house = old.id_house
LEFT JOIN
    last_contract_by_house AS lc
        ON new.id_house = lc.id_house
LEFT JOIN
    agent_events AS ae
        ON new.id_house = ae.id_house
        AND new.key_location = 'AGENT'
LEFT JOIN
    datalake_ebdb_listing.house_entrance_history AS first_event
        ON new.id_house = first_event.id_house
        AND first_event.is_first_status
