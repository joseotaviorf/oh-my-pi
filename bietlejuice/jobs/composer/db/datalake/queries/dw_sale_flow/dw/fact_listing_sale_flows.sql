WITH listing_rent_flows AS (
    WITH reservation AS (
        SELECT
            id_reservation,
            ts_created,
            id_house,
            id_tenant,
            MAX(id_reservation) OVER (PARTITION BY id_house, id_tenant) AS max_id,
            COUNT(1) OVER (PARTITION BY id_house, id_tenant) AS reservation_attempts
        FROM datalake_kill_queue.reservation
    ),
    rent_flows_base AS (
        SELECT
            rent_flow.id_house_rent_flow,
            rent_flow.id_house,
            COALESCE(
                CAST(
                    rent_flow.id_house ||
                    LPAD(
                        COALESCE(
                            CAST(dim_house_listing.version AS VARCHAR(3)),
                            '1'
                        ),
                        3,
                        '0')
                    AS BIGINT),
                CAST(-1 AS BIGINT)
            ) AS sk_house_listing,
            COALESCE(h.id_region, -1) AS sk_region,
            COALESCE(rent_flow.id_rent_flow, -1) AS sk_sale_flow,
            COALESCE(rent_flow.id_booking, -1) AS sk_booking,
            COALESCE(rent_flow.id_owner, -1) AS sk_owner,
            COALESCE(rent_flow.id_user_agent, -1) AS sk_user_agent,
            COALESCE(rent_flow.id_client, -1) AS sk_client,
            COALESCE(rent_flow.id_visit, -1) AS sk_visit,
            COALESCE(reservation.id_reservation, -1) AS sk_reservation,
            rent_flow.visit_created_type,
            CASE
                WHEN dim_booking.status = 'Cancelado'
                    THEN dim_booking.cancellation_reason
                END
            AS cancellation_reason,
            dim_house_listing.ts_listing_version_start AS dt_house_listing,
            rent_flow.dt_booking_created,
            rent_flow.dt_visit,
            rent_flow.dt_client_sign_up,
            CAST(rent_flow.is_visit_completed AS BOOLEAN) AS is_visit_completed,
            CAST(rent_flow.is_visit_performed AS BOOLEAN) AS is_visit_performed,
            CAST(rent_flow.is_visit_created_from_app AS BOOLEAN) AS is_visit_created_from_app,
            CAST(rent_flow.is_visit_last_updated_from_app AS BOOLEAN) AS is_visit_last_updated_from_app,
            COALESCE(CAST(DATE_FORMAT(rent_flow.dt_house_first_listing, "yyyyMMdd") AS BIGINT), -1) AS sk_house_first_listing_date,
            COALESCE(CAST(DATE_FORMAT(dim_house_listing.ts_listing_version_start, "yyyyMMdd") AS BIGINT), -1) AS sk_house_listing_date,
            COALESCE(CAST(DATE_FORMAT(dim_house_listing.ts_last_de_publication, "yyyyMMdd") AS BIGINT), -1) AS sk_house_listing_de_publication_date,
            COALESCE(CAST(DATE_FORMAT(rent_flow.dt_booking_created, "yyyyMMdd") AS BIGINT), -1) AS sk_booking_created_date,
            COALESCE(CAST(DATE_FORMAT(rent_flow.dt_visit, "yyyyMMdd") AS BIGINT), -1) AS sk_visit_date,
            COALESCE(CAST(DATE_FORMAT(ar.ts_rating_created, "yyyyMMdd") AS BIGINT), -1) AS sk_agent_review_rating_date,
            COALESCE(CAST(DATE_FORMAT(reservation.ts_created, "yyyyMMdd") AS BIGINT), -1) AS sk_reservation_created_date,
            CAST(reservation.reservation_attempts AS SMALLINT) AS reservation_attempts,
            CAST(NOW() AS TIMESTAMP) AS ts_load
        FROM datalake_ebdb_rent_flow.rent_flow
        JOIN dw_janus.dim_house_listing
            ON dim_house_listing.id_house = rent_flow.id_house
            AND COALESCE(rent_flow.dt_rent_flow_created, '1900-01-01') BETWEEN
                COALESCE(dim_house_listing.ts_listing_version_start, '1900-01-01')
                AND COALESCE(dim_house_listing.ts_listing_version_end, NOW())
        LEFT JOIN datalake_ebdb_listing.house h
            ON dim_house_listing.id_house = h.id
        LEFT JOIN datalake_ebdb_agents.agents_review ar
            ON rent_flow.id_booking = ar.id_booking
        LEFT JOIN reservation
            ON reservation.max_id = reservation.id_reservation
            AND rent_flow.id_house = reservation.id_house
            AND rent_flow.id_client = id_tenant
            AND reservation.ts_created BETWEEN
                COALESCE(dim_house_listing.ts_listing_version_start, '1900-01-01')
                AND COALESCE(dim_house_listing.ts_listing_version_end, NOW())
        LEFT JOIN dw_janus.dim_booking
            ON dim_booking.sk_booking = rent_flow.id_booking
        WHERE dim_house_listing.is_for_sale
            AND dim_booking.visit_intent = 'SALE'
    )
    SELECT
        *,
        -- SparkSQL's datediff ignores the time part, so we get the seconds diff and convert it to integer days.
        -- 60s*60m*24h = 86400s
        CAST((CAST(CAST(dt_visit AS TIMESTAMP) AS LONG) - CAST(CAST(dt_booking_created AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_booking_created_to_visit,
        CAST((CAST(CAST(dt_visit AS TIMESTAMP) AS LONG) - CAST(CAST(dt_client_sign_up AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_user_created_to_visit,
        CAST((CAST(CAST(dt_visit AS TIMESTAMP) AS LONG) - CAST(CAST(dt_house_listing AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_house_listing_to_visit,
        CASE
            WHEN (sk_booking_created_date > 0
                    OR sk_booking > 0)
                AND is_visit_completed
                THEN 'visit_completed'
            WHEN (sk_booking_created_date > 0
                    OR sk_booking > 0)
                AND NOT COALESCE(is_visit_completed, FALSE)
                THEN 'visit_booked'
        ELSE NULL END AS funnel_step
    FROM
        rent_flows_base
)
SELECT
    id_house_rent_flow AS ods_id,
    sk_house_listing,
    sk_region,
    sk_sale_flow,
    sk_booking,
    sk_owner,
    sk_user_agent,
    sk_client,
    sk_visit,
    sk_house_first_listing_date,
    sk_house_listing_date,
    sk_house_listing_de_publication_date,
    sk_booking_created_date,
    sk_visit_date,
    sk_agent_review_rating_date,
    visit_created_type,
    funnel_step,
    CASE
        WHEN funnel_step IN ('visit_completed',
                             'visit_booked')
            THEN cancellation_reason
        ELSE 'Not Mapped'
    END AS funnel_step_drop_reason,
    is_visit_completed AS flg_visit_completed,
    is_visit_performed AS flg_visit_performed,
    is_visit_created_from_app AS flg_visit_created_from_app,
    is_visit_last_updated_from_app AS flg_visit_last_updated_from_app,
    days_booking_created_to_visit,
    days_user_created_to_visit,
    days_house_listing_to_visit,
    ts_load
FROM
    listing_rent_flows