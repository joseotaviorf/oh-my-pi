WITH filtered_custom_fields AS(
    SELECT
        tck.id_ticket,
        REGEXP_REPLACE(REGEXP_REPLACE(tck.custom_fields,'(`\\{)\\{([^\n\\{\\}\\[\\]](?!value":(?!null)))*?\\}(,|\\])', ''), ',$', ']') AS custom_fields
    FROM
        datalake_zendesk_tickets_clean.tickets AS tck
),
exploded_custom_fields AS(
    SELECT
        id_ticket,
        EXPLODE(from_json(custom_fields, 'ARRAY<STRUCT<id: BIGINT, value: STRING>>')) AS custom_field
    FROM
        filtered_custom_fields
),
cleaned_custom_fields AS (
    SELECT
        ecf.id_ticket,
        tf.id_ticket_fields,
        tf.raw_title AS custom_field_title,
        -- removes unwanted character groups from values
        REGEXP_REPLACE(ecf.custom_field['value'], '(\\[\\\")|(\\\"\\])|[\\[\\]\\{\\}\\\\"]', '') AS custom_field_value
    FROM
        exploded_custom_fields AS ecf
    JOIN
        datalake_zendesk_tickets_clean.ticket_fields AS tf
            ON tf.id_ticket_fields = custom_field['id']
    WHERE
        NULLIF(NULLIF(custom_field['value'], ''), 'null') IS NOT NULL
)
SELECT
    id_ticket,
    MAP_FROM_ARRAYS(COLLECT_LIST(custom_field_title), COLLECT_LIST(custom_field_value)) AS custom_fields
FROM
    cleaned_custom_fields
GROUP BY id_ticket
