-- The double curly brackets (chave) had to be put to escape that character in the function .format in Python. If you test this in Databricks or somewhere else, remember to replace by a single curly bracket
WITH filtered_custom_fields AS (
    SELECT
        tck.id_ticket,
        -- The double curly brackets (chave) had to be put to escape that character in the function .format in Python. If you test this in Databricks or somewhere else, remember to replace by a single curly bracket
        EXPLODE(SPLIT(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(tck.custom_fields, '"(?!")', ''), 'id:', ''), ',value', ''), '[', ''), ']', ''), '{{', ''), '}}', ''), ',')) AS custom_field
    FROM
        datalake_zendesk_tickets_clean.tickets AS tck
),
parsed_custom_fields AS (
    SELECT DISTINCT
        id_ticket,
        SPLIT(custom_field, ':')[0] AS id_custom_field,
        SPLIT(custom_field, ':')[1] AS custom_field_value,
        tf.raw_title AS custom_field_title
    FROM
        filtered_custom_fields AS tcf
    JOIN
        datalake_zendesk_tickets_clean.ticket_fields AS tf
            ON tf.id_ticket_fields = SPLIT(custom_field, ':')[0]
    WHERE
        NULLIF(NULLIF(REPLACE(SPLIT(custom_field, ':')[1], '"', ''), ''), 'null') IS NOT NULL
)
SELECT
    id_ticket,
    MAP_FROM_ARRAYS(COLLECT_LIST(custom_field_title), COLLECT_LIST(custom_field_value)) AS custom_fields
FROM
    parsed_custom_fields
GROUP BY 1
