WITH
    promo_bonus_business_context AS (
        WITH
        final_bonus AS (
            SELECT
                pb.sk_user AS sk_user,
                pb.year_month AS year_month,
                pb.affiliate_type AS affiliate_type,
                NVL(SUM((pb.promotional_bonus/NULLIF(pb.total_listings, 0))*(pb.cnt_first_conversion_rent_only)),0) AS bonus_rent_only,
                NVL(SUM((pb.promotional_bonus/NULLIF(pb.total_listings, 0))*(pb.cnt_first_conversion_sale_only)),0) AS bonus_sale_only,
                NVL(SUM(((pb.promotional_bonus/NULLIF(pb.total_listings, 0))*(pb.cnt_first_conversion_hybrid))/2),0) AS bonus_hybrid_rent,
                NVL(SUM(((pb.promotional_bonus/NULLIF(pb.total_listings, 0))*(pb.cnt_first_conversion_hybrid))/2),0) AS bonus_hybrid_sale,
                NVL(SUM(pb.promotional_bonus),0) AS promotional_bonus
            FROM
                dw_datamarts_growth_cross.performance_marketing_cluster_promotional_bonus pb
            WHERE
                pb.is_active = 'true'
            GROUP BY 1,2,3
        )
        SELECT
            f.sk_user AS sk_user,
            f.year_month AS year_month,
            f.affiliate_type AS affiliate_type,
            NVL(SUM(f.bonus_rent_only + f.bonus_hybrid_rent),0) AS bonus_rent,
            NVL(SUM(f.bonus_sale_only + f.bonus_hybrid_sale),0) AS bonus_sale,
            NVL(SUM(f.promotional_bonus),0) AS promotional_bonus
        FROM
            final_bonus f
        GROUP BY 1,2,3
        ORDER BY 1
    ),
    first_listings AS (
        WITH
            clusters AS (
                SELECT
                    dd.date,
                    dd.week_start,
                    dd.year_month,
                    f.month_start,
                    f.sk_user,
                    cluster
                FROM
                    dw_datamarts_growth_cross.affiliates_clusters f
                    JOIN dw_public.dim_date dd
                        ON dd.date = f.month_start
            ),
            listings_rent_sale AS (
                SELECT
                    dl.sk_lead,
                    dd.sk_date,
                    dd.date AS listing_date,
                    dd.week_start AS listing_week_start,
                    dd.year_month AS listing_year_month,
                    dl.usuario_que_indicou_id AS sk_user,
                    dd.sk_date AS skfld_rent,
                    NULL::int AS skfld_sale,
                    rf.mkt_origin,
                    rf.sk_region,
                    NULLIF(rf.sk_house_listing,-1)/1000 AS id_house
                FROM
                    dw_public.dim_lead dl
                    LEFT JOIN dw_public.fact_house_listing_flows rf
                        ON dl.sk_lead = rf.sk_lead
                    JOIN dw_public.dim_date dd
                        ON dd.sk_date = rf.sk_first_listing_date
                WHERE
                    dd.sk_date > 0
                UNION ALL
                SELECT
                    dl.sk_lead,
                    dd.sk_date,
                    dd.date AS listing_date,
                    dd.week_start AS listing_week_start,
                    dd.year_month AS listing_year_month,
                    dl.usuario_que_indicou_id AS sk_user,
                    null::int AS skfld_rent,
                    dd.sk_date AS skfld_sale,
                    sf.mkt_origin,
                    sf.sk_region,
                    NULLIF(sf.sk_house_listing,-1)/1000 AS id_house
                FROM
                    dw_public.dim_lead dl
                    LEFT JOIN dw_sale.fact_listing_flows sf
                        ON dl.sk_lead = sf.sk_lead
                    JOIN dw_public.dim_date dd
                        ON dd.sk_date = sf.sk_first_listing_date
                WHERE
                    dd.sk_date > 0
            ),
            base AS (
                SELECT
                    sk_lead,
                    sk_user,
                    id_house,
                    mkt_origin,
                    sk_region,
                    sk_date,
                    listing_date,
                    listing_week_start,
                    listing_year_month,
                    NVL(SUM(skfld_rent), 0) > 0 AS has_conversion_rent,
                    NVL(SUM(skfld_sale), 0) > 0 AS has_conversion_sale,
                    ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY listing_date) AS listing_rank
                FROM
                    listings_rent_sale
                WHERE
                    sk_user>0
                GROUP BY 1,2,3,4,5,6,7,8,9
            ),
        final AS(
            SELECT
                b.sk_date,
                b.listing_date,
                b.listing_week_start,
                b.listing_year_month,
                b.sk_user::bigint,
                dr.city_group,
                NVL(COUNT(DISTINCT CASE WHEN b.has_conversion_rent AND b.has_conversion_sale = FALSE THEN b.id_house ELSE NULL END),0) AS cnt_first_conversion_rent_only,
                NVL(COUNT(DISTINCT CASE WHEN b.has_conversion_rent AND b.has_conversion_sale THEN b.id_house ELSE NULL END),0) AS cnt_first_conversion_hybrid,
                (NVL(COUNT(DISTINCT CASE WHEN b.has_conversion_rent AND b.has_conversion_sale = FALSE THEN b.id_house ELSE NULL END),0)
                + (NVL(COUNT(DISTINCT CASE WHEN b.has_conversion_rent AND b.has_conversion_sale THEN b.id_house ELSE NULL END),0))/2.0) AS total_rent_listings,
                COUNT(DISTINCT CASE WHEN b.has_conversion_rent = FALSE AND b.has_conversion_sale THEN b.id_house ELSE NULL END) AS cnt_first_conversion_sale_only,
                (NVL(COUNT(DISTINCT CASE WHEN b.has_conversion_rent = FALSE AND b.has_conversion_sale THEN b.id_house ELSE NULL END),0)
                + (NVL(COUNT(DISTINCT CASE WHEN b.has_conversion_rent AND b.has_conversion_sale THEN b.id_house ELSE NULL END),0))/2.0) AS total_sale_listings
            FROM
                base b
                LEFT JOIN dw_public.dim_user_affiliate dua
                    ON b.sk_user = dua.sk_user
                LEFT JOIN dw_public.dim_user du
                    ON du.sk_user = dua.sk_user
                LEFT JOIN dw_public.dim_region dr
                    ON dr.sk_region = b.sk_region
                LEFT JOIN clusters clu
                    ON b.sk_user = clu.sk_user
                    AND b.listing_year_month = clu.year_month
            WHERE
                b.listing_rank = 1 --showing only the first conversion
                AND dua.is_active = 1
            GROUP BY 1,2,3,4,5,6
            ORDER BY 1 DESC,2,3,4,5,6
        ),
        cum_listings AS(
            SELECT
                sk_date,
                listing_date,
                listing_week_start,
                listing_year_month,
                sk_user,
                city_group,
                NVL(total_rent_listings, 0) AS daily_rent_listings,
                NVL(SUM(total_rent_listings) OVER (PARTITION BY listing_year_month, sk_user, city_group ORDER BY listing_date ROWS UNBOUNDED PRECEDING), 0) AS total_rent_listings,
                NVL(total_sale_listings, 0) AS daily_sale_listings,
                NVL(SUM(total_sale_listings) OVER (PARTITION BY listing_year_month, sk_user, city_group ORDER BY listing_date ROWS UNBOUNDED PRECEDING), 0) AS total_sale_listings
            FROM final
            GROUP BY 1,2,3,4,5,6,7,9,total_rent_listings, total_sale_listings
            ORDER BY 1 DESC,2,3,4,5,6
        )
        SELECT
            sk_date,
            listing_date,
            listing_week_start,
            listing_year_month,
            sk_user,
            city_group,
            NVL(total_rent_listings, 0) AS total_rent_listings,
            NVL((total_rent_listings - daily_rent_listings), 0) AS previous_total_rent_listings,
            NVL(daily_rent_listings, 0) AS daily_rent_listings,
            NVL(total_sale_listings, 0) AS total_sale_listings,
            NVL((total_sale_listings - daily_sale_listings), 0) AS previous_total_sale_listings,
            NVL(daily_sale_listings, 0) AS daily_sale_listings
            FROM cum_listings
            ORDER BY 1 DESC,2,3,4,5,6
    ),
    total_user_listings AS(
        SELECT
            p.sk_user,
            p.year_month,
            p.affiliate_type,
            NVL(sum(fl.daily_rent_listings), 0) AS total_user_rent_listings ,
            NVL(sum(fl.daily_sale_listings), 0) AS total_user_sale_listings
        FROM
            promo_bonus_business_context p
            JOIN first_listings fl
                ON p.sk_user = fl.sk_user
                AND p.year_month = fl.listing_year_month
        GROUP BY 1,2,3
        ORDER BY 2 desc, 1
        ),
    final_bonus AS(
        SELECT
            p.sk_user,
            fl.city_group,
            fl.sk_date,
            fl.listing_date,
            fl.listing_week_start,
            p.year_month,
            p.affiliate_type,
            NVL(((p.bonus_rent/NULLIF(u.total_user_rent_listings, 0))*fl.total_rent_listings), 0) AS final_bonus_rent,
            NVL(LAG(NVL(((p.bonus_rent/NULLIF(u.total_user_rent_listings, 0))*fl.total_rent_listings), 0)) OVER (PARTITION BY p.year_month, p.sk_user, fl.city_group ORDER BY fl.listing_date), 0) AS previous_bonus_rent,
            NVL(((p.bonus_sale/NULLIF(u.total_user_sale_listings, 0))*fl.total_sale_listings), 0) AS final_bonus_sale,
            NVL(LAG(NVL(((p.bonus_sale/NULLIF(u.total_user_sale_listings, 0))*fl.total_sale_listings), 0)) OVER (PARTITION BY p.year_month, p.sk_user, fl.city_group ORDER BY fl.listing_date), 0) AS previous_bonus_sale
        FROM
            promo_bonus_business_context p
            LEFT JOIN first_listings fl
                ON p.sk_user = fl.sk_user
                AND p.year_month = fl.listing_year_month
            LEFT JOIN total_user_listings u
                ON p.sk_user = u.sk_user
                AND p.year_month = u.year_month
        ORDER BY 3 DESC,1)
SELECT
    sk_user,
    city_group,
    sk_date,
    listing_date,
    listing_week_start,
    year_month,
    affiliate_type,
    (final_bonus_rent - previous_bonus_rent) AS final_bonus_rent,
    (final_bonus_sale - previous_bonus_sale) AS final_bonus_sale
FROM
    final_bonus
WHERE
    sk_date >= 20190101
AND
    sk_user NOT IN (360754,912255,1711931,2257503)