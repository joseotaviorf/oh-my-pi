WITH ranked_tickets AS (
    -- customer_data is varchar but NOT valid JSON (unquoted keys/string values,
    -- e.g. {{name:Jane Doe, city:{{name:Sao Paulo, id:768}}, cpf:...}}) — GET_JSON_OBJECT
    -- silently returned NULL for every row on EMR. Databricks' `:` operator tolerates
    -- this loose format; EMR has no equivalent, so fields are regex-extracted here.
    -- Not validated against a live Databricks run — spot-check before merging,
    -- especially customer_phone_numbers (source list has no delimiter of its own,
    -- so only the first number is captured).
    SELECT
        CAST(id AS BIGINT) AS sk_ra_ticket,
        ra_status["name"] AS ra_status,
        hugme_status["name"] AS hugme_status,
        source["name"] AS source,
        complaint_title AS title,
        company.name AS company,
        NULLIF(REGEXP_EXTRACT(customer_data, '[{{ ]cpf:([^,}}]+)', 1), '') AS customer_cpf,
        NULLIF(REPLACE(REGEXP_EXTRACT(customer_data, '[{{ ]city:(\\{{[^}}]*\\}})', 1), 'name:', ''), '') AS customer_city,
        NULLIF(REPLACE(REGEXP_EXTRACT(customer_data, '[{{ ]state:(\\{{[^}}]*\\}})', 1), 'name:', ''), '') AS customer_state,
        NULLIF(REGEXP_EXTRACT(customer_data, '[{{ ]email:([^,}}]+)', 1), '') AS customer_email,
        NULLIF(REGEXP_EXTRACT(customer_data, '[{{ ]phone_numbers:([^,}}]+)', 1), '') AS customer_phone_numbers,
        NULLIF(REGEXP_EXTRACT(customer_data, '[{{ ]tags:([^,}}]+)', 1), '') AS customer_tags,
        moderation["status"] AS moderation_status,
        moderation["reason"] AS moderation_reason,
        ticket_moderations_count AS total_moderations,
        CASE
            WHEN rating = -1 THEN NULL
            ELSE rating
        END AS rating,
        rating_without_response AS total_ratings_without_response,
        is_resolved_issue AS is_resolved,
        ra["internal_process"] AS is_internal_process,
        would_do_business_again,
        ts_created,
        ts_last_replica,
        ts_complaint_response,
        ts_rating,
        ts_last_modification,
        NOW() AS ts_load,
        year,
        month,
        day,
        -- this rn enables backfills as id_hugme is not unique on clean
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_last_modification DESC) AS rn
    FROM
        datalake_reclameaqui_clean.tickets
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
)
SELECT
    sk_ra_ticket,
    ra_status,
    hugme_status,
    source,
    title,
    company,
    customer_cpf,
    customer_city,
    customer_state,
    customer_email,
    customer_phone_numbers,
    customer_tags,
    moderation_status,
    moderation_reason,
    total_moderations,
    rating,
    total_ratings_without_response,
    is_resolved,
    is_internal_process,
    would_do_business_again,
    ts_created,
    ts_last_replica,
    ts_complaint_response,
    ts_rating,
    ts_last_modification,
    ts_load,
    year,
    month,
    day
FROM
    ranked_tickets
WHERE
    rn = 1
