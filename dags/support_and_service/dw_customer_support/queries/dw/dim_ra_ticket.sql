SELECT
    CAST(id AS BIGINT) AS sk_ra_ticket,
    ra_status["name"] AS ra_status,
    hugme_status["name"] AS hugme_status,
    source["name"] AS source,
    complaint_title AS title,
    customer_data:["cpf"] AS customer_cpf,
    REPLACE(customer_data:["city"], "name:") AS customer_city,
    REPLACE(customer_data:["state"], "name:") AS customer_state,
    customer_data:["email"] AS customer_email,
    customer_data:["phone_numbers"] AS customer_phone_numbers,
    customer_data:["tags"] AS customer_tags,
    moderation["status"] AS moderation_status,
    moderation["reason"] AS moderation_reason,
    ticket_moderations_count AS total_moderations,
    CASE
        WHEN rating = -1 THEN NULL
        ELSE rating
    END AS rating,
    rating_without_response AS total_ratings_without_response,
    is_resolved_issue AS is_resolved,
    would_do_business_again,
    ts_created,
    ts_last_replica,
    ts_rating,
    ts_last_modification,
    year,
    month,
    day
FROM
    datalake_reclameaqui_clean.tickets
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
-- this QUALIFY enables backfills as id_hugme is not unique on clean
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_last_modification DESC) = 1
