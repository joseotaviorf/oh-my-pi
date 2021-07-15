WITH house_listings AS (
    SELECT
        id_house,
        COUNT(DISTINCT CASE
            WHEN status_history = 'publicado' THEN id_house_listing
        END) AS versions_published
    FROM
        datalake_ebdb_listing.house_listing_status
    GROUP BY
        1
),
house_listings_owners AS (
    SELECT
        id,
        id_user AS id_listing_owner
    FROM
        datalake_ebdb_listing.house
),
contracts AS (
    SELECT
        h.id_listing_owner,
        SUM(INT(c.status = 'Cancelado')) AS contracts_cancelled,
        SUM(INT(c.status IN ('Minuta', 'PreAssinaturas'))) AS contracts_to_be_signed,
        SUM(INT(c.status IN ('Ativo', 'Finalizado'))) AS contracts_signed,
        SUM(INT(c.status = 'Finalizado')) AS contracts_annuled,
        SUM(INT(
                c.status IN ('Ativo', 'Finalizado')
                AND DATE(COALESCE(c.ts_signed, c.dt_started, c.dt_entered)) <= CURRENT_DATE
                AND (COALESCE(c.dt_termination, CURRENT_DATE) - INTERVAL '1' DAY) >= CURRENT_DATE
                AND c.type != 'DealOnly'
        )) AS ongoing_contracts,
        MIN(c.ts_signed) AS ts_first_contract_signed,
        MAX(c.ts_signed) AS ts_last_contract_signed
    FROM
        datalake_ebdb_contract.contract AS c
    JOIN
        house_listings_owners AS h
        ON c.id_house = h.id
    GROUP BY
        1
),
visits AS (
    SELECT
        h.id_listing_owner,
        COUNT(b.id) AS visits_booked,
        SUM(INT(b.is_visit_completed)) AS visits_completed,
        SUM(INT(
                NOT b.is_visit_completed
                AND NOT b.is_canceled
        )) AS visits_expected_to_happen,
        SUM(INT(b.is_canceled)) AS visits_cancelled,
        MIN(CASE
            WHEN b.is_visit_completed THEN b.dt_booking
        END) AS dt_first_visited,
        MAX(CASE
            WHEN b.is_visit_completed THEN b.dt_booking
        END) AS dt_last_visited,
        MIN(b.ts_created) AS ts_first_booking,
        MAX(b.ts_created) AS ts_last_booking
    FROM
        datalake_booking.booking AS b
    JOIN
        house_listings_owners AS h
            ON b.id_house = h.id
    WHERE
        b.visit_intent = 'RENT'
        AND b.type = 'Visita'
    GROUP BY
        1
),
offers AS (
    SELECT
        h.id_listing_owner,
        COUNT(o.id) AS offers_received,
        SUM(INT(o.status = 'Rejeitada')) AS offers_rejected,
        SUM(INT(o.status = 'EmNegociacao')) AS offers_negotiating,
        MIN(o.ts_created) AS ts_first_offer_received,
        MAX(o.ts_created) AS ts_last_offer_received
    FROM
        datalake_offer.offer AS o
    JOIN
        house_listings_owners AS h
            ON o.id_house = h.id
    WHERE
        o.id != -1
    GROUP BY
        1
),
proposals AS (
    SELECT
        h.id_listing_owner,
        COUNT(p.id) AS offers_accepted,
        SUM(INT(p.status = 'Rejeitada')) AS proposals_rejected,
        SUM(INT(p.status = 'Aprovada')) AS proposals_approved,
        MIN(p.ts_created) AS ts_first_offer_accepted,
        MAX(p.ts_created) AS ts_last_offer_accepted
    FROM
        datalake_ebdb_clean.proposal AS p
    JOIN
        house_listings_owners AS h
            ON p.id_house = h.id
    GROUP BY
        1
),
reservations AS (
    SELECT
        hlo.id_listing_owner,
        SUM(INT(r.status IN ('CANCELED', 'FINISHED', 'RETURNED'))) AS reservations_received
    FROM
        house_listings_owners AS hlo
    LEFT JOIN
        datalake_kill_queue.reservation AS r
            ON r.id_reservation = hlo.id
    GROUP BY
        1
),
rent_listing_owners AS (
    SELECT
        h.id_listing_owner,
        COUNT(lbc.id_house) AS properties_registered,
        SUM(hl.versions_published) AS listings_published,
        SUM(INT(lbc.status = 'PUBLISHED')) AS ongoing_listings,
        MIN(lbc.ts_created) AS ts_first_listing_registered,
        MAX(lbc.ts_created) AS ts_last_listing_registered
    FROM
        datalake_ebdb_listing.listing_business_context AS lbc
    JOIN
        house_listings_owners AS h
            ON lbc.id_house = h.id
    LEFT JOIN
        house_listings AS hl
            ON lbc.id_house = hl.id_house
    WHERE
        lbc.business_context = 'RENT'
        AND h.id_listing_owner IS NOT NULL
    GROUP BY
        1
)
SELECT
    rlo.id_listing_owner,
    CAST(rlo.properties_registered AS INTEGER),
    CAST(rlo.listings_published AS INTEGER),
    CAST(COALESCE(v.visits_booked, 0) AS INTEGER) AS visits_booked,
    CAST(COALESCE(v.visits_completed, 0) AS INTEGER) AS visits_received,
    CAST(COALESCE(v.visits_expected_to_happen, 0) AS INTEGER) AS visits_expected_to_happen,
    CAST(COALESCE(v.visits_cancelled, 0) AS INTEGER) AS visits_cancelled,
    CAST(COALESCE(o.offers_received, 0) AS INTEGER) AS offers_received,
    CAST(COALESCE(o.offers_rejected, 0) AS INTEGER) AS offers_rejected,
    CAST(COALESCE(o.offers_negotiating, 0) AS INTEGER) AS offers_negotiating,
    CAST(COALESCE(p.offers_accepted, 0) AS INTEGER) AS offers_accepted,
    CAST(COALESCE(p.proposals_rejected, 0) AS INTEGER) AS proposals_rejected,
    CAST(COALESCE(p.proposals_approved, 0) AS INTEGER) AS proposals_approved,
    CAST(COALESCE(r.reservations_received, 0) AS INTEGER) AS reservations_received,
    CAST(COALESCE(c.contracts_cancelled, 0) AS INTEGER) AS contracts_cancelled,
    CAST(COALESCE(c.contracts_to_be_signed, 0) AS INTEGER) AS contracts_to_be_signed,
    CAST(COALESCE(c.contracts_signed, 0) AS INTEGER) AS contracts_signed,
    CAST(COALESCE(c.contracts_annuled, 0) AS INTEGER) AS contracts_annuled,
    CAST(COALESCE(rlo.ongoing_listings, 0) AS INTEGER) AS ongoing_listings,
    CAST(COALESCE(c.ongoing_contracts, 0) AS INTEGER) AS ongoing_contracts,
    v.dt_first_visited,
    v.dt_last_visited,
    v.ts_first_booking,
    o.ts_first_offer_received,
    p.ts_first_offer_accepted,
    c.ts_first_contract_signed,
    rlo.ts_first_listing_registered,
    v.ts_last_booking,
    o.ts_last_offer_received,
    p.ts_last_offer_accepted,
    c.ts_last_contract_signed,
    rlo.ts_last_listing_registered
FROM
  rent_listing_owners AS rlo
LEFT JOIN
  contracts AS c
    ON rlo.id_listing_owner = c.id_listing_owner
LEFT JOIN
  visits AS v
    ON rlo.id_listing_owner = v.id_listing_owner
LEFT JOIN
  proposals AS p
    ON rlo.id_listing_owner = p.id_listing_owner
LEFT JOIN
  offers AS o
    ON rlo.id_listing_owner = o.id_listing_owner
LEFT JOIN
  reservations AS r
    ON rlo.id_listing_owner = r.id_listing_owner
