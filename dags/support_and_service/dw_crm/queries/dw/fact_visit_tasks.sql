WITH bookings AS (
    SELECT
        turf.*,
        CAST(COALESCE(db.id, '-1') AS BIGINT) AS sk_booking,
        CAST(COALESCE(dhl.id_house_listing, '-1') AS BIGINT) AS sk_house_listing
    FROM
        datalake_crm_tasks_flows.tasks_users_resolutions_flow AS turf
    LEFT JOIN
        datalake_booking.booking db
            ON turf.origin = 'Agendamento'
            AND turf.id_origin = db.id
    LEFT JOIN
        datalake_ebdb_listing.house_listing dhl
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
house_listing AS (
    SELECT
        hl.id_house_listing,
        hl.id_contract,
        hl.id_house,
        hl.ts_listing_version_start,
        COALESCE(hl.ts_listing_version_end, NOW()) AS ts_listing_version_end
    FROM
        datalake_ebdb_listing.house_listing AS hl
    UNION
    SELECT
        lc.id_house_listing,
        lc.id_contract,
        lc.id_house,
        lc.ts_listing_version_started AS ts_listing_version_start,
        lc.ts_listing_version_ended AS ts_listing_version_end
    FROM
        datalake_listing_contracts.listing_contracts AS lc
),
listing_rent_flows AS (
    SELECT DISTINCT
        COALESCE(rf.id_booking, -1) AS sk_booking,
        COALESCE(hl.id_house_listing, -1) AS sk_house_listing,
        COALESCE(rf.id_owner, -1) AS sk_house_owner,
        COALESCE(rf.id_client, -1) AS sk_visitor
    FROM
        house_listing AS hl
    LEFT JOIN
        datalake_ebdb_rent_flow.rent_flow AS rf
            ON rf.id_contract = hl.id_contract
            OR (
                rf.id_house = hl.id_house
                AND rf.dt_rent_flow_created BETWEEN hl.ts_listing_version_start AND hl.ts_listing_version_end
            )
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