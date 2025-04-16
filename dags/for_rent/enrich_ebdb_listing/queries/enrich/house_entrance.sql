WITH old_entry_model AS (
    SELECT
        at.id_house,
        key.name AS key_type,
        occupant.name AS occupant_type,
        restriction.name AS restriction_type,
        authorization.name AS authorization_type
    FROM
        datalake_ebdb_clean.access_type AS at
    JOIN
        datalake_ebdb_clean.key_type AS key
            ON at.id_type = key.id
    JOIN
        datalake_ebdb_clean.occupant_type AS occupant
            ON at.id_occupant = occupant.id
    JOIN
        datalake_ebdb_clean.restriction_type AS restriction
            ON at.id_restriction = restriction.id
    JOIN
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
)

SELECT
    new.id_house,
    old.key_type,
    old.occupant_type,
    old.restriction_type,
    old.authorization_type,
    new.key_location,
    new.access_model,
    new.access_code,
    new.access_details,
    new.location,
    new.holder_type,
    new.holder_identifier,
    new.ts_created,
    new.ts_updated
FROM
    new_entry_model AS new
LEFT JOIN
    old_entry_model AS old
        ON new.id_house = old.id_house
