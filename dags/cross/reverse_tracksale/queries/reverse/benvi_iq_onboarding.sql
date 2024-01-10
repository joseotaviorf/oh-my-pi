-- Benvi IQ Onboarding (MX): Tenants with contract start on D-10
-- Get all contracts started on D-10
WITH new_contracts AS (
	SELECT
		dc.sk_contract,
		'Onboarding' AS step
	FROM
		dw_rent.dim_contract AS dc
	INNER JOIN
    	dw_public.fact_listing_rent_flows AS rf
			ON dc.sk_contract = rf.sk_contract
			AND rf.sk_contract_signed_date > 0 -- only signed contracts
			AND dc.country_code = 'MX'
	INNER JOIN
		dw_public.dim_house_listing AS dhl
			ON dhl.sk_house_listing = rf.sk_house_listing
			AND dhl.country_code = 'MX'
	LEFT JOIN
		datalake_offboarding.contract_termination AS ct
			ON dc.sk_contract = ct.id_contract
	WHERE
		dc.dt_start = DATE_ADD(NOW(), -10) -- select contracts started on D-10
		AND dc.status = 'Ativo'
		AND ((ct.dt_termination > dc.dt_start) OR (ct.dt_termination IS NULL))
	GROUP BY 1, 2
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
onboarding_contracts AS (
	SELECT
		c.sk_contract,
		'Onboarding' AS step
	FROM
		new_contracts AS c
	LEFT JOIN
		crisis_users AS uc
			ON uc.sk_contract = c.sk_contract
	WHERE
		uc.sk_contract IS NULL -- exclude contracts with ongoing crisis ticket
	GROUP BY 1, 2
),
-- considering all tenants or dwellers involved in contracts
tenants_dwellers AS (
	SELECT
		cp.sk_user,
		ac.sk_contract,
		dcp.personal_document AS cpf,
		dcp.full_name AS name,
		dcp.email,
		dcp.phone_number,
		ac.step,
		DENSE_RANK() OVER(PARTITION BY cp.sk_contract, dcp.email ORDER BY cp.sk_contract_person) AS order_diff_email
	FROM
		onboarding_contracts AS ac
	INNER JOIN
		dw_rent.fact_contract_people AS cp
			ON ac.sk_contract = cp.sk_contract
			AND cp.contract_role IN ('dweller', 'tenant')
	LEFT JOIN
		dw_rent.dim_contract_person AS dcp
			ON cp.sk_contract_person = dcp.sk_contract_person
	WHERE
		dcp.email IS NOT NULL
)
SELECT
	name AS customer_name,
	email AS customer_email,
	phone_number AS customer_phone,
	step AS campaign_step,
	'Inquilino' AS customer_type,
	cpf AS customer_cpf,
	sk_user AS id_user,
	'true' AS campaign_type,
	'contract' AS driver_type,
	sk_contract AS id_driver,
	NOW() AS ts_load
FROM
	tenants_dwellers
WHERE
	order_diff_email = 1
UNION ALL
SELECT
	'Teste Disparos' AS customer_name,
	'testes.disparos.5a@gmail.com' AS customer_email,
	'+5511123456789' AS customer_phone,
	'Onboarding' AS campaign_step,
	'Inquilino' AS customer_type,
	'1234' AS customer_cpf,
	'1234' AS id_user,
	'true' AS campaign_type,
	'contract' AS driver_type,
	'1234' AS id_driver,
	NOW() AS ts_load
