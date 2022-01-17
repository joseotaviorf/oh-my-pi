WITH bookings AS (
    SELECT
        turf.*,
        CAST(COALESCE(db.sk_booking, '-1') AS BIGINT) AS sk_booking,
        CAST(COALESCE(dhl.sk_house_listing, '-1') AS BIGINT) AS sk_house_listing
    FROM 
        datalake_crm_tasks_flows.tasks_users_resolutions_flow AS turf
    LEFT JOIN
        dw_public.dim_booking db
            ON turf.origin = 'Agendamento'
            AND turf.id_origin = db.sk_booking
    LEFT JOIN 
        dw_janus.dim_house_listing dhl
            ON turf.origin = 'Imovel'
            AND turf.id_origin = dhl.id_house
            AND turf.ts_start BETWEEN dhl.ts_listing_version_start AND COALESCE(NULLIF(dhl.ts_listing_version_end,''), NOW())
    WHERE
        turf.year = {year}
        AND turf.month = {month}
        AND turf.day = {day}
        AND turf.type IN (
                        'ConfirmarAgendamento',
                        'ConfirmarCondicoesEntrada',
                        'ConfirmarDisponibilidadeDoImovel',
                        'SolicitarLockbox',
                        'VisitaCanceladaOutroDDD'
        ) 
),
listing_rent_flows AS (
    SELECT
        CAST(sk_booking AS BIGINT) AS sk_booking,
        CAST(sk_house_listing AS BIGINT) AS sk_house_listing,
        CAST(sk_owner AS BIGINT) AS sk_house_owner,
        CAST(sk_client AS BIGINT) AS sk_visitor
    FROM 
        dw_public.fact_listing_rent_flows
    GROUP BY 1, 2, 3, 4
)
SELECT DISTINCT
    b.id_task AS sk_task,
    b.sk_booking AS sk_booking,
    b.id_action_date AS sk_action_date,
    b.id_assignee AS sk_assignee,
    b.id_completed_date AS sk_completed_date,
    COALESCE(bookings.sk_house_listing, houses.sk_house_listing, b.sk_house_listing) AS sk_house_listing,
    COALESCE(bookings.sk_house_owner, houses.sk_house_owner, -1) AS sk_house_owner,
    COALESCE(CAST(b.id_origin AS BIGINT), -1) AS sk_origin,
    b.id_receiver AS sk_receiver,
    b.id_start_date AS sk_start_date,
    b.id_task_user_end_date AS sk_task_action_end_date,
    b.id_task_user_start_date AS sk_task_action_start_date,
    b.id_user_action AS sk_user_action,
    COALESCE(bookings.sk_visitor, -1) AS sk_visitor,
    b.action_type,
    b.action_user_name,
    b.task_user_resolve_hours AS task_user_action_resolve_hours,
    b.task_user_type AS task_action_type,
    b.ts_action,
    b.ts_task_user_end AS ts_task_action_end,
    b.ts_task_user_start AS ts_task_action_start,
    NOW() AS ts_load,
    b.year,
    b.month,
    b.day
FROM 
    bookings b
LEFT JOIN
    listing_rent_flows bookings
        ON b.sk_booking = bookings.sk_booking
        AND b.sk_booking != -1
LEFT JOIN
    listing_rent_flows houses
        ON b.sk_house_listing = houses.sk_house_listing
        AND b.sk_house_listing != -1
        AND b.sk_booking = -1