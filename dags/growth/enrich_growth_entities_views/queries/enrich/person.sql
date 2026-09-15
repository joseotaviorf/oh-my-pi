-- Identity view previously defined as hive.datalake_cdp.person (Trino SECURITY DEFINER)
-- in customer-data-platform. Grain: one row per EBDB user (datalake_ebdb_clean.user.id).
-- Source: bietlejuice.person runs at 0 21,8,12 * * *; identity contacts are not updated
-- every 30 minutes. Revisit if a faster identity SLA is needed.
WITH primary_contact AS (
    SELECT
        ranked_contact.id_person,
        ranked_contact.category,
        ranked_contact.contact_info
    FROM (
        SELECT
            contact.id_person,
            contact.category,
            contact.contact_info,
            ROW_NUMBER() OVER (
                PARTITION BY
                    contact.id_person,
                    contact.category
                ORDER BY
                    contact.ts_created DESC
            ) AS row_number
        FROM
            datalake_person_clean.contact_info AS contact
        WHERE
            UPPER(contact.priority) = 'PRIMARY'
    ) AS ranked_contact
    WHERE
        ranked_contact.row_number = 1
)
SELECT
    ebdb_user.id AS id_user,
    ebdb_user.uuid_person,
    phone.contact_info AS phone_number,
    email.contact_info AS email,
    person.is_blocked,
    CAST(ebdb_user.ts_created AS TIMESTAMP) AS ts_created,
    CAST(ebdb_user.ts_updated AS TIMESTAMP) AS ts_updated,
    CAST(person.ts_created AS TIMESTAMP) AS ts_created_person,
    CAST(person.ts_updated AS TIMESTAMP) AS ts_updated_person,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_ebdb_clean.user AS ebdb_user
LEFT JOIN
    datalake_person_clean.person AS person
        ON person.uuid_person = ebdb_user.uuid_person
LEFT JOIN
    primary_contact AS phone
        ON phone.id_person = person.id
        AND UPPER(phone.category) = 'PHONE'
LEFT JOIN
    primary_contact AS email
        ON email.id_person = person.id
        AND UPPER(email.category) = 'EMAIL'
