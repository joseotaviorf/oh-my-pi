WITH new_contracts AS (
	SELECT
		dc.sk_contract,
		'Onboarding' AS step
	FROM
        dw_public.dim_contract dc
	INNER JOIN
        dw_public.fact_listing_rent_flows rf
			ON dc.sk_contract = rf.sk_contract
			AND rf.sk_contract_signed_date > 0
	INNER JOIN
        dw_public.dim_house_listing dhl
			ON dhl.sk_house_listing = rf.sk_house_listing
	LEFT JOIN
        dw_datamarts_for_rent.contract_termination ct
			ON dc.sk_contract = ct.sk_contract
    WHERE
        dc.dt_start = DATE_ADD(current_date, -10)
		AND dc.status = 'Ativo'
		AND ((ct.dt_termination > dc.dt_start) OR (ct.dt_termination is null))
		AND dhl.country_code = 'BR'
		AND dc.country_code = 'BR'
	GROUP BY 1,2
),
crisis_users AS (
	SELECT
		ft.sk_contract
	FROM
        dw_tickets.dim_ticket dt
	INNER JOIN
        dw_tickets.fact_tickets ft
			ON dt.sk_ticket = ft.sk_ticket
	INNER JOIN
        datalake_gsheets_clean.department_control dc
			ON dt.group_name = dc.department
	WHERE
        dc.team IN ('Casos Especiais','Proteção 5A','Ouvidoria','ReclameAqui')
		AND ft.sk_closed_date_local = -1
	GROUP BY 1
),
onboarding_contracts AS (
	SELECT
		c.sk_contract,
		'Onboarding' AS step
	FROM
        new_contracts c
	LEFT JOIN
        crisis_users uc
			ON uc.sk_contract = c.sk_contract
	WHERE
        uc.sk_contract IS NULL
	GROUP BY 1,2
),
tenants_dwellers AS (
	SELECT
		cp.cpf,
		cp.id_user,
		cp.name,
		cp.email,
		cp.phone_number,
		ac.sk_contract,
		ac.step,
		DENSE_RANK() OVER(PARTITION BY cp.id_contract, cp.email ORDER BY cp.id) AS order_diff_email
	FROM
        onboarding_contracts ac
	INNER JOIN
        datalake_ebdb_clean.contract_person cp
			ON ac.sk_contract = cp.id_contract
			AND cp.type IN ('Inquilino','Morador')
			AND cp.email IS NOT NULL
)
SELECT
	name AS customer_name,
	email AS customer_email,
	phone_number AS customer_phone,
	step AS campaign_step,
	'Inquilino' AS customer_type,
	cpf AS customer_cpf,
	id_user,
	'true' AS campaign_type,
	'contract' AS driver_type,
	sk_contract AS id_driver
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
	'1234' AS id_driver
