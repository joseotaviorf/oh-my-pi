WITH house_portability AS (
    SELECT
        h.id AS id_house,
        hl.id_house_listing,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end AS ts_listing_version_end
    FROM 
        datalake_ebdb_listing.house_listing hl
    JOIN 
        datalake_ebdb_clean.house h
            ON h.id = hl.id_house
    JOIN 
        datalake_ebdb_clean.portability por
            ON por.id_house = hl.id_house 
            AND por.owner_type = 'B2B'
    WHERE por.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01 00:00:00') AND COALESCE(hl.ts_listing_version_end, NOW())
),
house_aud AS (
    SELECT
        ha.id_house,
        ha.id_user,
        LAG(ha.id_user) OVER(PARTITION BY ha.id_house ORDER BY ha.rev) AS previous_id_user,
        ure.ts_revision AS ts_started
    FROM
        datalake_ebdb_clean.house_aud AS ha
    JOIN
        datalake_ebdb_user_revision_entity.user_revision_entity AS ure
            ON ha.rev = ure.id
),
owners_changes AS (
    SELECT
        id_house,
        id_user,
        ts_started,
        LEAD(ts_started) OVER(PARTITION BY id_house ORDER BY ts_started) AS ts_ended
    FROM
        house_aud
    WHERE
        id_user != COALESCE(previous_id_user, -1)
),
lead_aud AS (
    SELECT
        la.id_lead,
        la.affiliate_type,
        LAG(la.affiliate_type) OVER(PARTITION BY la.id_lead ORDER BY la.rev) AS previous_affiliate_type,
        ure.ts_revision AS ts_started
    FROM
        datalake_ebdb_clean.lead_aud AS la
    JOIN
        datalake_ebdb_user_revision_entity.user_revision_entity AS ure
            ON la.rev = ure.id
),
lead_changes AS (
    SELECT
        id_lead,
        affiliate_type,
        ts_started,
        LEAD(ts_started) OVER(PARTITION BY id_lead ORDER BY ts_started) AS ts_ended
    FROM
        lead_aud
    WHERE
        affiliate_type != COALESCE(previous_affiliate_type, -1)
),
conversion_lead_aud AS (
    SELECT
        cla.id AS id_conversion_lead,
        cla.id_converted_lead,
        cla.id_house,
        LAG(cla.id_converted_lead) OVER(PARTITION BY cla.id ORDER BY cla.rev) AS previous_id_converted_lead,
        ure.ts_revision AS ts_started
    FROM
        datalake_ebdb_clean.conversion_lead_aud AS cla
    JOIN
        datalake_ebdb_user_revision_entity.user_revision_entity AS ure
            ON cla.rev = ure.id
),
conversion_lead_changes AS (
    SELECT
        id_conversion_lead,
        id_converted_lead,
        id_house,
        ts_started,
        LEAD(ts_started) OVER(PARTITION BY id_conversion_lead ORDER BY ts_started) AS ts_ended
    FROM
        conversion_lead_aud
    WHERE
        id_converted_lead != COALESCE(previous_id_converted_lead, -1)
),
lead_event_bus AS (
    SELECT
        clc.id_house,
        clc.ts_started AS ts_started_conversion_lead,
        -- only consider changes in lead that occurs within a conversion_lead and that has a id_house related.
        CASE
            WHEN lc.ts_started < clc.ts_started AND COALESCE(lc.ts_ended, '2099-12-31') <= COALESCE(clc.ts_ended, '2099-12-31') THEN NULL
            WHEN lc.ts_started >= clc.ts_started AND COALESCE(lc.ts_ended, '2099-12-31') <= COALESCE(clc.ts_ended, '2099-12-31') THEN lc.ts_started
            ELSE NULL
        END AS ts_started_lead
    FROM
        conversion_lead_changes AS clc
    LEFT JOIN
        lead_changes AS lc
            ON lc.id_lead = clc.id_converted_lead
),
partner_agent_aud AS (
    SELECT
        pau.id_user,
        pau.id_partner,
        LAG(pau.id_partner) OVER(PARTITION BY pau.id_user ORDER BY pau.rev) AS previous_id_partner,
        ure.ts_revision AS ts_started
    FROM
        datalake_ebdb_clean.partner_agent_aud AS pau
    JOIN
        datalake_ebdb_user_revision_entity.user_revision_entity AS ure
            ON pau.rev = ure.id
),
partner_agent_changes AS (
    SELECT
        id_user,
        id_partner,
        previous_id_partner,
        ts_started,
        LEAD(ts_started) OVER(PARTITION BY id_user ORDER BY ts_started) AS ts_ended
    FROM
        partner_agent_aud
    WHERE
        id_partner != COALESCE(previous_id_partner, -1)
),
owner_partner_bus AS (
    SELECT
        oc.id_house,
        oc.id_user,
        pac.id_partner,
        oc.ts_started AS ts_started_owner,
        CASE
            WHEN pac.ts_started < oc.ts_started AND COALESCE(pac.ts_ended, '2099-12-31') <= COALESCE(oc.ts_ended, '2099-12-31') THEN NULL
            WHEN pac.ts_started >= oc.ts_started AND COALESCE(pac.ts_ended, '2099-12-31') <= COALESCE(oc.ts_ended, '2099-12-31') THEN pac.ts_started
            ELSE NULL
        END AS ts_started_partner
    FROM
        owners_changes AS oc
    LEFT JOIN
        partner_agent_changes AS pac
            ON oc.id_user = pac.id_user
),
event_bus AS (
    -- house and house_listing events
    SELECT
        id_house,
        ts_listing_version_start AS ts_event
    FROM
        house_portability
    UNION
    -- owner and partner events
    SELECT
        id_house,
        ts_started_owner AS ts_event
    FROM
        owner_partner_bus
    UNION
    SELECT
        id_house,
        ts_started_partner AS ts_event
    FROM
        owner_partner_bus
    UNION
    -- Lead events
    SELECT
        id_house,
        ts_started_conversion_lead AS ts_event
    FROM
        lead_event_bus
    UNION
    SELECT
        id_house,
        ts_started_lead AS ts_event
    FROM
        lead_event_bus      
),
house_b2b_status AS (
SELECT
    clc.id_converted_lead,
    eb.id_house,
    hp.id_house_listing,
    pac.id_partner,
    oc.id_user,
    lc.affiliate_type,
    eb.ts_event AS ts_started,
    LEAD(eb.ts_event) OVER(PARTITION BY eb.id_house ORDER BY eb.ts_event) AS ts_ended
FROM
    event_bus AS eb
LEFT JOIN
    owners_changes AS oc
        ON eb.id_house = oc.id_house
        AND eb.ts_event >= oc.ts_started
        AND eb.ts_event < COALESCE(oc.ts_ended, '2099-12-31')
LEFT JOIN
    house_portability AS hp
        ON eb.id_house = hp.id_house
        AND eb.ts_event >= hp.ts_listing_version_start
        AND eb.ts_event < COALESCE(hp.ts_listing_version_end, '2099-12-31')
LEFT JOIN
    conversion_lead_changes AS clc
        ON eb.id_house = clc.id_house
        AND eb.ts_event >= clc.ts_started
        AND eb.ts_event < COALESCE(clc.ts_ended, '2099-12-31')
LEFT JOIN
    lead_changes AS lc
        ON clc.id_converted_lead = lc.id_lead
        AND eb.ts_event >= lc.ts_started
        AND eb.ts_event < COALESCE(lc.ts_ended, '2099-12-31')
LEFT JOIN
    partner_agent_changes AS pac
        ON oc.id_user = pac.id_user
        AND eb.ts_event >= pac.ts_started
        AND eb.ts_event < COALESCE(pac.ts_ended, '2099-12-31')
WHERE
    eb.ts_event IS NOT NULL
)
SELECT
    id_converted_lead,
    id_house,
    id_house_listing,
    id_partner,
    id_user,
    affiliate_type,
    ts_started,
    ts_ended
FROM
    house_b2b_status