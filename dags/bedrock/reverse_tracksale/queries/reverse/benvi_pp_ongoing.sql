-- Benvi PP Ongoing: all landlords involved in contracts on every 6- month anniversary from start excluding people under rescision
WITH anniversary_contracts AS (
	SELECT 
		dc.sk_contract,
		CONCAT(ROUND(MONTHS_BETWEEN(CURRENT_DATE(), COALESCE(dc.dt_start, DATE(dc.ts_signature))), 0), ' meses') AS step
	FROM
		dw_public.dim_contract AS dc
	INNER JOIN
		dw_public.fact_listing_rent_flows AS rf 
			ON dc.sk_contract = rf.sk_contract
			AND rf.sk_contract_signed_date > 0 -- select only signed contracts
			AND dc.country_code = 'MX'
			AND dc.status = 'Ativo' -- select only ongoing contracts
	INNER JOIN
		dw_public.dim_house_listing AS dhl 
			ON dhl.sk_house_listing = rf.sk_house_listing
			AND dhl.is_b2b = FALSE -- excluding B2B listings
	LEFT JOIN
		datalake_terminator_clean.termination AS t
			ON dc.sk_contract = t.id_contract 
	WHERE
		-- select only contracts in each 6th anniversary
		COALESCE(dc.dt_start, DATE(dc.ts_signature)) IN (ADD_MONTHS(CURRENT_DATE(), -6), ADD_MONTHS(CURRENT_DATE(), -12), ADD_MONTHS(CURRENT_DATE(), -18), 
			ADD_MONTHS(CURRENT_DATE(), -24), ADD_MONTHS(CURRENT_DATE(), -30), ADD_MONTHS(CURRENT_DATE(), -36), ADD_MONTHS(CURRENT_DATE(), -42), 
			ADD_MONTHS(CURRENT_DATE(), -48), ADD_MONTHS(CURRENT_DATE(), -54), ADD_MONTHS(CURRENT_DATE(), -60))
		AND t.id_contract IS NULL -- excluding contracts that started termination process
),
recovery_contracts AS (
	SELECT 
		ft.sk_contract,
		'Repescagem Casos Especiais' AS step
	FROM
		dw_tickets.dim_ticket AS dt
	INNER JOIN
		dw_tickets.fact_tickets AS ft 
			ON dt.sk_ticket  = ft.sk_ticket
	INNER JOIN
		dw_customer_support.dim_department AS dc
			ON dt.group_name = dc.department
			AND dc.team IN ('Casos Especiais','Ouvidoria','ReclameAqui') -- exclude users from these areas (crisis)
	LEFT JOIN
		dw_public.dim_contract AS dc_
			ON dc_.sk_contract = ft.sk_contract
	WHERE
		dc_.country_code= 'BR'
		AND DATE(ft.ts_closed_local) = DATE_ADD(CURRENT_DATE(), -10) -- select tickets from Proteção 5A closed 10 days ago
		AND dc_.status = 'Ativo'
		AND COALESCE(dc_.dt_start, DATE(dc_.ts_signature)) IN (ADD_MONTHS(CURRENT_DATE(), -6), ADD_MONTHS(CURRENT_DATE(), -12), ADD_MONTHS(CURRENT_DATE(), -18), 
			ADD_MONTHS(CURRENT_DATE(), -24), ADD_MONTHS(CURRENT_DATE(), -30), ADD_MONTHS(CURRENT_DATE(), -36), ADD_MONTHS(CURRENT_DATE(), -42), 
			ADD_MONTHS(CURRENT_DATE(), -48), ADD_MONTHS(CURRENT_DATE(), -54), ADD_MONTHS(CURRENT_DATE(), -60))
	GROUP BY 1, 2
),
all_contracts AS (
	SELECT
		*
	FROM
		anniversary_contracts 
	UNION
	SELECT
		*
	FROM
		recovery_contracts
),
crisis_users AS (
	SELECT 
		ft.sk_contract
	FROM
		dw_tickets.dim_ticket AS dt
	INNER JOIN
		dw_tickets.fact_tickets AS ft 
			ON dt.sk_ticket  = ft.sk_ticket
			AND ft.sk_closed_date_local = -1 -- consider only users with crisis tickets not closed yet
	INNER JOIN
		dw_customer_support.dim_department AS dc
			ON dt.group_name = dc.department
			AND dc.team IN ('Casos Especiais','Proteção 5A','Ouvidoria','ReclameAqui') -- exclude users from these areas (crisis)
	GROUP BY 1
),
-- considering all owners involved in contracts
owners AS (
	SELECT
		cp.sk_user,
		ac.sk_contract,
		dcp.personal_document AS cpf,
		dcp.full_name AS name,
		dcp.email,
		dcp.phone_number,
		ac.step
	FROM
		all_contracts AS ac 
	INNER JOIN
		dw_quintoandar.fact_contract_people AS cp 
			ON ac.sk_contract = cp.sk_contract
			AND cp.contract_role = 'landlord'
	LEFT JOIN
		dw_quintoandar.dim_contract_person AS dcp
			ON cp.sk_contract_person = dcp.sk_contract_person
	LEFT JOIN
		crisis_users AS uc 
			ON uc.sk_contract = ac.sk_contract
	WHERE
		uc.sk_contract IS NULL -- exclude contracts with ongoing crisis ticket
)
SELECT
	name AS customer_name,
	email AS customer_email,
	phone_number AS customer_phone,
	step AS campaign_step,
	'Proprietário' AS customer_type,
	cpf AS customer_cpf,
	sk_user AS id_user,
	'true' AS campaign_type,
	'id_contract' AS driver_type,
	sk_contract AS id_driver,
	NOW() AS ts_load
FROM
	owners
UNION ALL
SELECT
	'Teste Disparo' AS customer_name,
	'testes.disparos.5a@gmail.com' AS customer_email,
	'+5511123456789' AS customer_phone,
	'12 meses' AS campaign_step,
	'Proprietário' AS customer_type,
	'1234' AS customer_cpf,
	'1234' AS id_user,
	'true' AS campaign_type,
	'id_contract' AS driver_type,
	'1234' AS id_driver,
	NOW() AS ts_load