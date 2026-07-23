WITH canceled_date AS (
    SELECT
        id AS id_booking,
        MIN(rev) AS rev_cancelled
    FROM
        datalake_ebdb_clean.booking_aud
    WHERE
        status = 'Cancelado'
        AND mod_status = 1
    GROUP BY 1
),
owner_users AS (
    WITH lbc AS (
        SELECT
            id_house,
            CAST(MAX(CAST((business_context = 'SALE') AS INTEGER)) AS BOOLEAN) AS is_for_sale,
            CAST(MAX(CAST((business_context = 'RENT') AS INTEGER)) AS BOOLEAN) AS is_for_rent
        FROM
           datalake_ebdb_listing.listing_business_context
        GROUP BY 1
    )
    SELECT
        h.id AS id_house,
        h.id_user,
        COALESCE(NULLIF(NULLIF(h.id_user, pa_b2b_online.id_user), pa_b2b_prime.id_user), -1) AS id_owner -- Ignore id_users that are companies
    FROM 
        datalake_ebdb_listing.house AS h
    LEFT JOIN 
        lbc
            ON lbc.id_house = h.id
    LEFT JOIN 
        datalake_ebdb_clean.partner_agent AS pa_b2b_prime
            ON h.id_user = pa_b2b_prime.id_user
    LEFT JOIN 
        datalake_ebdb_clean.conversion_lead AS lc
            ON lc.id_house = h.id
    LEFT JOIN 
        datalake_ebdb_clean.lead AS l
            ON l.id = lc.id_converted_lead
            AND l.affiliate_type = 'B2BPartner'
    LEFT JOIN 
        datalake_ebdb_clean.affiliate_data AS ad
            ON ad.id = l.id_affiliate_has_indicated
    LEFT JOIN 
        datalake_ebdb_clean.user AS user_affiliate
            ON ad.id = user_affiliate.id_affiliates
    LEFT JOIN 
        datalake_ebdb_clean.partner_agent AS pa_b2b_online
            ON pa_b2b_online.id_user = user_affiliate.id
    WHERE
        lbc.id_house IS NULL
        OR lbc.is_for_rent
)
SELECT
    b.id AS id_booking,
    ure.id_user AS id_user_cancellation,
    CASE
        WHEN ou.id_owner IS NOT NULL THEN 'Owner'
        WHEN b.id_agent = u.id_agent THEN 'Agent'
        WHEN b.id_visitor = ure.id_user THEN 'Tenant'
        WHEN u.email RLIKE '(?i)@quintoandar.com.br|@concentrix.com|@casamineiraimoveis.com.br|@casamineira.com.br|@atento.com.br' THEN 'QuintoAndar'
        WHEN ure.id_user IS NULL THEN 'Automatic'
    END AS cancelled_by,
    -- Keeping the mlliseconds just to avoid a divergencie of precision with booking right now.
    CAST(FROM_UNIXTIME(ure.ts_revision/1000) AS TIMESTAMP) + (ure.ts_revision % 1000) * INTERVAL 1 MILLISECONDS AS ts_first_cancelled
FROM
    datalake_ebdb_clean.booking AS b
JOIN
    canceled_date AS cd
        ON b.id = cd.id_booking
JOIN
    datalake_ebdb_clean.user_revision_entity AS ure
        ON cd.rev_cancelled = ure.id
LEFT JOIN
    owner_users AS ou
        ON b.id_house = ou.id_house
        AND ure.id_user = ou.id_user
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON ure.id_user = u.id