WITH
promotional_bonus_cluster_targets AS (
	SELECT
		dd.year_month AS year_month,
		NULLIF(pbct.cluster,'') AS cluster,
		pbct.target_base AS target_base,
		pbct.target_boost AS target_boost,
		pbct.bonus_base AS bonus_base,
		pbct.bonus_boost AS bonus_boost
	FROM
		datalake_gsheets_clean_prod.promotional_bonus_cluster_targets pbct
		JOIN dim_date dd
			ON DATE(pbct.year_month) = dd.date
),
promotional_bonus_user_cluster_targets AS (
	SELECT
		dd.year_month,
		pbut.sk_user AS sk_user,
		pbut.target_base AS target_base,
		pbut.target_boost AS target_boost,
		pbut.bonus_base AS bonus_base,
		pbut.bonus_boost AS bonus_boost
	FROM
		datalake_gsheets_clean_prod.promotional_bonus_user_cluster_targets pbut
		JOIN dim_date dd
			ON DATE(pbut.year_month) = dd.date
),
listings AS (
	WITH
	cluster AS (
		SELECT
			dd.year_month AS year_month,
			dd.sk_date AS sk_date,
			ac.sk_user AS sk_user,
			ac.cluster AS cluster
		FROM
			datamarts.affiliates_clusters ac
			JOIN dim_date dd
				ON dd.date = ac.month_start
	),
	total_listings AS (
		SELECT
            distinct
        	dl.sk_lead,
        	dd.date AS listing_date,
        	dl.usuario_que_indicou_id AS sk_user,
        	llf.sk_first_listing_date AS sk_first_listing_date,
        	llf.context_first_listing AS context_first_listing,
        	NULLIF(llf.sk_house_listing,-1)/1000 AS id_house
        FROM
        	dim_lead dl
        	LEFT JOIN datamarts.lead_listing_flows llf
        		ON dl.sk_lead = llf.sk_lead
        	INNER JOIN dim_date dd
        		ON dd.sk_date = llf.sk_first_listing_date
          	        AND dd.sk_date > 0
	),
	base_listings AS (
		SELECT
			sk_lead,
			sk_user,
			id_house,
            listing_date,
            TO_CHAR(listing_date, 'YYYY/MM') AS year_month,
			context_first_listing
		FROM
			total_listings
		WHERE
			sk_user>0
	)
	SELECT
		b.year_month,
		b.sk_user::bigint,
		dua.is_active,
		dua.type AS affiliate_type,
		COALESCE(clu.cluster,'') AS cluster,
		COUNT(DISTINCT CASE WHEN context_first_listing = 'Rent' THEN b.id_house ELSE NULL END) AS cnt_first_conversion_rent_only,
		COUNT(DISTINCT CASE WHEN context_first_listing = 'Sale' THEN b.id_house ELSE NULL END) AS cnt_first_conversion_sale_only,
		COUNT(DISTINCT CASE WHEN context_first_listing = 'Hybrid' THEN b.id_house ELSE NULL END) AS cnt_first_conversion_hybrid,
		COUNT(DISTINCT CASE WHEN context_first_listing = 'Rent' THEN b.id_house ELSE NULL END)
		+ COUNT(DISTINCT CASE WHEN context_first_listing = 'Sale' THEN b.id_house ELSE NULL END)
		+ COUNT(DISTINCT CASE WHEN context_first_listing = 'Hybrid' THEN b.id_house ELSE NULL END) AS total_listings
	FROM
		base_listings b
		JOIN dim_user_affiliate dua
			ON b.sk_user = dua.sk_user
		LEFT JOIN cluster clu
			ON b.sk_user = clu.sk_user
			AND b.year_month = clu.year_month
	GROUP BY 1,2,3,4,5
),
listings_with_bonus AS (
	SELECT
		l.*,
		CASE
			WHEN pbut.sk_user IS NOT NULL THEN pbut.target_base
			ELSE pbct.target_base
		END AS target_base,
		CASE
			WHEN pbut.sk_user IS NOT NULL THEN pbut.target_boost
			ELSE pbct.target_boost
		END AS target_boost,
		CASE
			WHEN pbut.sk_user IS NOT NULL THEN pbut.bonus_base
			ELSE pbct.bonus_base
		END AS bonus_base,
		CASE
			WHEN pbut.sk_user IS NOT NULL THEN pbut.bonus_boost
			ELSE pbct.bonus_boost
		END AS bonus_boost
	FROM
		listings l
		LEFT JOIN promotional_bonus_user_cluster_targets pbut
			ON l.year_month = pbut.year_month
			AND l.sk_user = pbut.sk_user
		LEFT JOIN promotional_bonus_cluster_targets pbct
			ON l.year_month = pbct.year_month
			AND LOWER(l.cluster) = LOWER(pbct.cluster)
)
SELECT
    lwb.sk_user,
    lwb.year_month,
    lwb.affiliate_type,
    lwb.is_active,
    NULLIF(lwb.cluster, ''),
    lwb.cnt_first_conversion_rent_only,
    lwb.cnt_first_conversion_sale_only,
    lwb.cnt_first_conversion_hybrid,
    lwb.total_listings,
    lwb.target_base,
    CASE
        WHEN (lwb.target_base - lwb.total_listings)>=0 THEN (lwb.target_base - lwb.total_listings)
        ELSE 0
    END AS diff_base,
    lwb.bonus_base,
    lwb.target_boost,
    CASE
        WHEN (lwb.target_boost - lwb.total_listings)>=0 THEN (lwb.target_boost - lwb.total_listings)
        ELSE 0
    END AS diff_boost,
    lwb.bonus_boost,
    lwb.total_listings >= lwb.target_base AS has_hit_base,
    lwb.total_listings >= lwb.target_boost AS has_hit_boost,
    CASE
        WHEN lwb.total_listings >= lwb.target_boost THEN bonus_boost
        WHEN lwb.total_listings >= lwb.target_base THEN bonus_base
        ELSE 0::float
    END AS promotional_bonus,
    lwb.total_listings*100 AS commission_listing
FROM
	listings_with_bonus lwb