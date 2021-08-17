WITH
promotional_bonus_segmentation_targets AS (
	SELECT
		dd.year_month,
		COALESCE(pbst.affiliate_type,'')::varchar AS affiliate_type,
		COALESCE(pbst.segmentation,'')::varchar AS segmentation,
		NULLIF(pbst.target_base,'')::float AS target_base,
		NULLIF(pbst.target_boost,'')::float AS target_boost,
		NULLIF(pbst.bonus_base,'')::float AS bonus_base,
		NULLIF(pbst.bonus_boost,'')::float AS bonus_boost
	FROM
		datalake_raw.gsheets_promotional_bonus_segmentation_targets pbst
		JOIN dim_date dd
			ON NULLIF(pbst.year_month,'')::date = dd.date
),
promotional_bonus_user_targets AS (
	SELECT
		dd.year_month,
		NULLIF(pbut.sk_user,'')::bigint AS sk_user,
		NULLIF(pbut.target_base,'')::float AS target_base,
		NULLIF(pbut.target_boost,'')::float AS target_boost,
		NULLIF(pbut.bonus_base,'')::float AS bonus_base,
		NULLIF(pbut.bonus_boost,'')::float AS bonus_boost
	FROM
		datalake_raw.gsheets_promotional_bonus_user_targets pbut
		JOIN dim_date dd
			ON NULLIF(pbut.year_month,'')::date = dd.date
),
listings AS (
	WITH
	segmentations AS (
		SELECT
			dd.year_month,
			f.sk_date,
			f.sk_user,
			CASE
				WHEN f.sk_user IN (912255,480177,915763,917375,360754,1711931,2257503) THEN 'spinver'
				ELSE f.segmentation
			END AS segmentation
		FROM
			fact_affiliate_monthly_category_segmentations f
			JOIN dim_date dd
				ON dd.sk_date = f.sk_date
	),
	total_listings AS (
		SELECT
			dl.sk_lead,
			dd.date AS listing_date,
			dl.usuario_que_indicou_id AS sk_user,
			dd.sk_date AS skfld_rent,
			NULL::int AS skfld_sale,
			NULLIF(rf.sk_house_listing,-1)/1000 AS id_house
		FROM
			dim_lead dl
			LEFT JOIN fact_house_listing_flows rf
				ON dl.sk_lead = rf.sk_lead
			JOIN dim_date dd
				ON dd.sk_date = rf.sk_first_listing_date
		WHERE
			dd.sk_date > 0
	    UNION ALL
		SELECT
			dl.sk_lead,
			dd.date AS listing_date,
			dl.usuario_que_indicou_id AS sk_user,
			null::int AS skfld_rent,
			dd.sk_date AS skfld_sale,
			NULLIF(sf.sk_house_listing,-1)/1000 AS id_house
		FROM
			dim_lead dl
			LEFT JOIN sale.fact_listing_flows sf
				ON dl.sk_lead = sf.sk_lead
			JOIN dim_date dd
				ON dd.sk_date = sf.sk_first_listing_date
		WHERE
			dd.sk_date > 0
	),
	base_listings AS (
		SELECT
			sk_lead,
			sk_user,
			id_house,
            listing_date,
            TO_CHAR(listing_date, 'YYYY/MM') AS year_month,
			COALESCE(SUM(skfld_rent), 0) > 0 AS has_conversion_rent,
			COALESCE(SUM(skfld_sale), 0) > 0 AS has_conversion_sale,
			ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY listing_date) AS listing_rank
		FROM
			total_listings
		WHERE
			sk_user>0
		GROUP BY 1,2,3,4,5
	)
	SELECT
		b.year_month,
		b.sk_user::bigint,
		dua.type AS affiliate_type,
		dua.is_active,
		COALESCE(seg.segmentation,'') AS segmentation,
		COUNT(DISTINCT CASE WHEN b.has_conversion_rent AND b.has_conversion_sale = FALSE THEN b.id_house ELSE NULL END) AS cnt_first_conversion_rent_only,
		COUNT(DISTINCT CASE WHEN b.has_conversion_rent = FALSE AND b.has_conversion_sale THEN b.id_house ELSE NULL END) AS cnt_first_conversion_sale_only,
		COUNT(DISTINCT CASE WHEN b.has_conversion_rent AND b.has_conversion_sale THEN b.id_house ELSE NULL END) AS cnt_first_conversion_hybrid,
		COUNT(DISTINCT CASE WHEN b.has_conversion_rent AND b.has_conversion_sale = FALSE THEN b.id_house ELSE NULL END)
		+ COUNT(DISTINCT CASE WHEN b.has_conversion_rent = FALSE AND b.has_conversion_sale THEN b.id_house ELSE NULL END)
		+ COUNT(DISTINCT CASE WHEN b.has_conversion_rent AND b.has_conversion_sale THEN b.id_house ELSE NULL END) AS total_listings
	FROM
		base_listings b
		JOIN dim_user_affiliate dua
			ON b.sk_user = dua.sk_user
		LEFT JOIN segmentations seg
			ON b.sk_user = seg.sk_user
			AND b.year_month = seg.year_month
	WHERE
		b.listing_rank = 1 --showing only the first conversion
	GROUP BY 1,2,3,4,5
),
listings_with_bonus AS (
	SELECT
		l.*,
		CASE
			WHEN pbut.sk_user IS NOT NULL THEN pbut.target_base
			ELSE pbst.target_base
		END AS target_base,
		CASE
			WHEN pbut.sk_user IS NOT NULL THEN pbut.target_boost
			ELSE pbst.target_boost
		END AS target_boost,
		CASE
			WHEN pbut.sk_user IS NOT NULL THEN pbut.bonus_base
			ELSE pbst.bonus_base
		END AS bonus_base,
		CASE
			WHEN pbut.sk_user IS NOT NULL THEN pbut.bonus_boost
			ELSE pbst.bonus_boost
		END AS bonus_boost
	FROM
		listings l
		LEFT JOIN promotional_bonus_user_targets pbut
			ON l.year_month = pbut.year_month
			AND l.sk_user = pbut.sk_user
		LEFT JOIN promotional_bonus_segmentation_targets pbst
			ON l.year_month = pbst.year_month
			AND LOWER(l.segmentation) = LOWER(pbst.segmentation)
			AND LOWER(l.affiliate_type) = LOWER(pbst.affiliate_type)
)
SELECT
    lwb.sk_user,
	lwb.year_month,
	lwb.affiliate_type,
	lwb.is_active,
	lwb.segmentation,
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
WHERE
    lwb.sk_user NOT IN (360754,912255,1711931,2257503)