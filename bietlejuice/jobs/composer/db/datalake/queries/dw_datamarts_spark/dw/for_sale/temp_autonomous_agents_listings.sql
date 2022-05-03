WITH user_registration_revision AS (
	SELECT
		i.id_house AS id_house,
		i.id_user_registrant,
		i.rev,
		DATE(from_unixtime(CAST(ure.ts_revision / 1000 AS BIGINT))) AS dt_migration
	FROM
		datalake_ebdb_clean.house_aud AS i
	INNER JOIN 
		datalake_ebdb_clean.user_revision_entity AS ure 
			ON ure.id = CAST(i.rev AS int)
	WHERE
		i.mod_user_registrant = true 
),
cr AS (
	SELECT
		pa.sk_partner_agent,
		pa.id_user,
		dp.id AS sk_partner,
		dp.trade_name,
		dp.name,
		dp.phone,
		dp.city,
		DATE(pa.ts_created) AS ts_created
	FROM
		dw_public.dim_partner_agent AS pa
	JOIN 
		datalake_ebdb_clean.partner AS dp
			ON pa.id_partner = dp.id
	WHERE
		dp.type = 'AUTONOMOUS_AGENT'
		AND dp.id <> 257 
)
SELECT
	dhl.id_house,
	dhl.sk_house_listing,
	CASE
		WHEN rev.dt_migration <= dhl.ts_publication THEN rev.dt_migration
		ELSE NULL
	END AS dt_migration,
	dhl.ts_house_create,
	cr.sk_partner,
	cr.trade_name,
	cr.id_user AS id_partner_agent_user,
	cr.ts_created AS ts_partner_agent_created,
	h.id_user_registrant,
	h.id_user AS sk_owner,
	h.id_external,
	dhl.version, 
	dhl.status,
	dhl.house_status,
	dhl.ts_house_first_publication,
	dhl.ts_house_last_publication,
	dhl.ts_publication,
	dhl.ts_last_de_publication,
	dhl.listing_category_start,
	dhl.is_last_version
FROM
	cr
JOIN
	datalake_ebdb_clean.house AS h 
		ON cr.id_user = h.id_user_registrant
LEFT JOIN 
	dw_public.dim_house_listing AS dhl
		ON h.id = dhl.id_house
LEFT JOIN 
	dw_public.fact_house_listings AS fhl
		ON fhl.sk_house_listing = dhl.sk_house_listing
LEFT JOIN
	user_registration_revision AS rev
		ON rev.id_house = h.id
LEFT JOIN
	datalake_ebdb_clean.listing_business_context AS lbc
		ON lbc.id_house = h.id
WHERE
	h.id_external IS NOT NULL
	AND lbc.business_context <> 'SALE'
	AND (dhl.ts_house_create >= cr.ts_created
	OR (rev.dt_migration IS NOT NULL AND rev.dt_migration <= dhl.ts_publication))