WITH user_registration_revision AS (
SELECT
	i.id AS id_house,
	i.usuarioquecadastrou_mod,
	i.rev,
	DATE(from_unixtime(CAST(ure.ts_revision / 1000 AS bigint))) as dt_migration
FROM
	datalake_ebdb_raw_prod.imovel_aud i
INNER JOIN datalake_ebdb_clean_prod.user_revision_entity ure ON
	ure.id = CAST(i.rev AS int)
WHERE
	i.usuarioquecadastrou_mod = 'true' ),
cr AS (
SELECT
	pa.sk_partner_agent,
	pa.id_user,
	dp.id AS sk_partner,
	dp.trade_name,
	dp.name,
	dp.phone,
	dp.city,
	DATE(dp.ts_created) AS ts_created
FROM
	dim_partner_agent pa
JOIN datalake_ebdb_clean_prod.partner dp ON
	pa.id_partner = dp.id
where
	dp.type = 'AUTONOMOUS_AGENT'
	AND dp.id <> '257' 
)
SELECT
	dhl.sk_house_listing,
	dhl.id_house,
	CASE WHEN rev.dt_migration <= dhl.ts_publication THEN rev.dt_migration
		ELSE NULL
	END AS dt_migration
FROM
	dim_house_listing dhl
JOIN fact_house_listings fhl ON
	fhl.sk_house_listing = dhl.sk_house_listing
JOIN cr ON
	cr.id_user = fhl.sk_user_registration
LEFT JOIN user_registration_revision rev ON
	rev.id_house = dhl.id_house
WHERE
	DATE(dhl.ts_house_create) >= cr.ts_created
	OR (rev.dt_migration IS NOT NULL AND rev.dt_migration <= dhl.ts_publication)
