WITH weekly_listings AS (
    SELECT
        hldi.id_house_listing,
        hldi.id_house,
        hldi.id_contract,
        CASE
            WHEN hldi.consultant_type IS NULL THEN 'Core'
            ELSE hldi.consultant_type
        END AS consultant_type,
        CASE
            WHEN hldi.first_key_location = 'OwnerPresent'
                OR hldi.first_key_location = 'None'
                OR hldi.first_key_location IS NULL THEN ('PP Acompanha' ||
                    CASE
                        WHEN ot.name = 'Empty'
                            OR ot.name = 'None' THEN ' Vago'
                        ELSE 'Ocupado'
                    END ||
                        CASE
                            WHEN hldi.doorman_type in ('horas24','Diurno')
                                AND (ot.name = 'Empty' OR ot.name = 'None') THEN ' Com Portaria'
                            ELSE ' Sem Portaria'
                        END)
            ELSE hldi.first_key_location
        END AS entry_condition,
        CASE
            WHEN hldi.is_exclusive THEN 'Exclusivo'
            ELSE 'Não Exclusivo'
        END AS exclusivity,
        CASE
            WHEN hldi.is_for_rent = TRUE
                AND hldi.is_for_sale = TRUE THEN 'Hibrido'
            WHEN hldi.is_for_rent = TRUE
                AND hldi.is_for_sale = FALSE THEN 'For Rent'
        END AS hybrid,
        hldi.listing_category AS listing_category_start,
        hldi.status_change_reason,
        CASE
            WHEN hldi.status_history = 'suspenso'
                AND (LOWER(status_change_reason) RLIKE 'reserv|minuta|negocia|proposta%') THEN 'negociacao avancada' -- casos de suspensão por negociação avançada não são churn
            WHEN hldi.status_history = 'despublicado'
                AND LOWER(status_change_reason) RLIKE 'disabled|erro ao|despublicação automática após rescisão|\\[auto\\] \\[rescisao\\]' THEN 'opt out / erro' -- casos de despublicação após aluguel sem re-publicação não são churn
            ELSE hldi.status_history
        END AS status_history,
        -- When we have transitions between listings, we endup with two listings registered
        -- on the same day, but for coincidents what matters is just the last status of this
        -- house on this week, so we need to guaranteee that we are getting only the last listing.
        -- In addition, two listings in the same week would do the LAG to calculate last status
        -- randomic, we are partitioning by house and ordering by week.
        MAX(hldi.id_house_listing) OVER(PARTITION BY hldi.id_house, hldi.dt_day) = hldi.id_house_listing AS is_last_listing_on_day,
        IF(DATE(DATE_TRUNC('week', hldi.ts_status_started)) = d.week_start, TRUE, FALSE) AS is_status_started_on_week,
        d.week_start AS dt_week,
        DATE(DATE_TRUNC('week', hldi.ts_status_started)) AS dt_week_status_started,
        hldi.ts_status_started
    FROM
        datalake_rental_historical_follow_up.house_listings_daily_info AS hldi
    JOIN
        dw_public.dim_house_listing AS dhl
            ON hldi.id_house_listing = dhl.sk_house_listing
    JOIN -- We will get just one day : Sunday
        dw_public.dim_date AS d
            ON d.date = hldi.dt_day
    JOIN
        dw_public.dim_region AS dr
            ON hldi.id_region = dr.sk_region
    LEFT JOIN
        datalake_ebdb_clean.occupant_type AS ot
            ON hldi.id_occupant = ot.id
    WHERE
        dr.sk_region > 0
        AND RIGHT(hldi.id_house_listing, 3) <> '000'
        -- We get weeks that already are closed or ongoing ones.
        -- Instead of CURRENT_DATE, DATE('{year}-{month}-{day}') try to ensure idempotence
        -- If a listing ends on the middle of a week, we won`t have a problem because
        -- we are considering the final state of the house on that week.
        AND (hldi.is_week_end = TRUE
            OR DATE(CONCAT(hldi.year, '-', hldi.month, '-', hldi.day)) = DATE('{year}-{month}-{day}')
            )
        AND dr.country_code = 'BR'
        AND DATE(CONCAT(hldi.year, '-', hldi.month, '-', hldi.day)) >= DATE('{year}-{month}-{day}') - INTERVAL 58 WEEK
),
mkt_house AS (
-- We set this to house grain to avoid mess up with
-- the listing grain
    SELECT
        LEFT(sk_house_listing, 9) AS id_house,
        MAX(mkt_completion) AS mkt_completion,
        MAX(mkt_origin) AS mkt_origin
    FROM
        dw_public.fact_house_listing_flows AS fhlf
    WHERE
        sk_house_listing > 0
    GROUP BY 1
),
weekly_listings_mkt AS (
-- Already deduplicated, so a group by or a distinct is unnecessary: id_house_listing, week
    SELECT
        dc.sk_contract,
        wl.id_house_listing,
        wl.id_house,
        wl.consultant_type,
        wl.entry_condition,
        wl.exclusivity,
        wl.hybrid,
        wl.listing_category_start,
        COALESCE(LAG(wl.listing_category_start) OVER(PARTITION BY wl.id_house ORDER BY wl.id_house_listing), 'indisponivel') AS listing_category_previous,
        mkt.mkt_completion,
        mkt.mkt_origin,
        wl.status_history,
        COALESCE(LAG(wl.status_history) OVER(PARTITION BY wl.id_house ORDER BY wl.dt_week), 'indisponivel') AS last_week_status_history,
        wl.is_status_started_on_week,
        DATE(DATE_TRUNC('month', (wl.dt_week + INTERVAL 3 DAY))) AS dt_month,
        wl.dt_week,
        DATE(DATE_TRUNC('week', dc.ts_signature)) AS dt_week_signed
    FROM
        weekly_listings AS wl
    JOIN
        mkt_house AS mkt
            ON wl.id_house = mkt.id_house
    LEFT JOIN
        dw_rent.dim_contract AS dc
            ON wl.id_contract = dc.sk_contract
            AND dc.ts_signature IS NOT NULL
    WHERE
        wl.is_last_listing_on_day = True
),
weekly_listings_base AS (
    SELECT
        wlm.sk_contract,
        MD5(wlm.dt_week || wlm.dt_month || wlm.listing_category_start || wlm.hybrid || wlm.mkt_completion || wlm.mkt_origin || wlm.entry_condition || wlm.consultant_type || wlm.exclusivity || wlm.listing_category_previous) AS id_coincident_listing,
        wlm.id_house_listing,
        wlm.consultant_type,
        wlm.entry_condition,
        wlm.exclusivity,
        wlm.hybrid,
        wlm.last_week_status_history,
        wlm.listing_category_previous,
        wlm.listing_category_start,
        wlm.mkt_completion,
        wlm.mkt_origin,
        wlm.status_history,
        wlm.is_status_started_on_week,
        wlm.dt_month,
        wlm.dt_week,
        wlm.dt_week_signed
    FROM
        weekly_listings_mkt AS wlm
),
weekly_coincident AS (
    -- Create a PK for these elements to join them and guarantee uniqueness
    SELECT
        wlb.id_coincident_listing,
        wlb.consultant_type,
        wlb.entry_condition,
        wlb.exclusivity,
        wlb.hybrid,
        wlb.listing_category_start,
        wlb.listing_category_previous,
        wlb.mkt_completion,
        wlb.mkt_origin,
        wlb.dt_month,
        wlb.dt_week
    FROM
        weekly_listings_base AS wlb
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
churned AS (
    SELECT
        id_coincident_listing,
        COUNT(DISTINCT IF(status_history = 'despublicado', id_house_listing, NULL)) AS unpublished,
        COUNT(DISTINCT IF(status_history = 'excluido', id_house_listing, NULL)) AS excluded,
        COUNT(DISTINCT IF(status_history = 'suspenso', id_house_listing, NULL)) AS suspended
    FROM
        weekly_listings_base
    WHERE
        status_history IN ('suspenso', 'despublicado', 'excluido')
        AND last_week_status_history NOT IN ('suspenso', 'despublicado', 'excluido')
        AND is_status_started_on_week = TRUE
    GROUP BY 1
),
returned AS (
    SELECT
        id_coincident_listing,
        COUNT(DISTINCT IF(last_week_status_history IN ('despublicado', 'excluido'), id_house_listing, NULL)) AS return_from_unpublished,
        COUNT(DISTINCT IF(last_week_status_history = 'suspenso', id_house_listing, NULL)) AS return_from_suspended
    FROM
        weekly_listings_base
    WHERE
        status_history IN ('alugado', 'publicado', 'negociacao avancada')
        AND last_week_status_history IN ('suspenso', 'despublicado', 'excluido')
        AND is_status_started_on_week = TRUE
    GROUP BY 1
),
contracts AS (
    SELECT
        id_coincident_listing,
        COUNT(DISTINCT sk_contract) AS listings_with_contracts_signed
    FROM
        weekly_listings_base
    WHERE
        dt_week_signed = dt_week
    GROUP BY 1
)
SELECT
    wc.id_coincident_listing,
    wc.consultant_type,
    wc.entry_condition,
    wc.exclusivity,
    wc.hybrid,
    wc.listing_category_start,
    wc.listing_category_previous,
    wc.mkt_completion,
    wc.mkt_origin,
    COALESCE(c.listings_with_contracts_signed, 0) AS listings_with_contracts_signed,
    COALESCE(ch.unpublished, 0) AS unpublished,
    COALESCE(ch.excluded, 0) AS excluded,
    COALESCE(ch.suspended, 0) AS suspended,
    COALESCE(r.return_from_unpublished, 0) AS return_from_unpublished,
    COALESCE(r.return_from_suspended, 0) AS return_from_suspended,
    wc.dt_month AS dt_month_started,
    wc.dt_week AS dt_week_started
FROM
    weekly_coincident AS wc
LEFT JOIN
    churned AS ch
        ON wc.id_coincident_listing = ch.id_coincident_listing
LEFT JOIN
    contracts AS c
        ON wc.id_coincident_listing = c.id_coincident_listing
LEFT JOIN
    returned AS r
        ON wc.id_coincident_listing = r.id_coincident_listing
