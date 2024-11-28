WITH new_contracts AS (
	SELECT
		dc.sk_contract,
		'Onboarding' AS step
	FROM
		dw_rent.dim_contract dc
	INNER JOIN
		dw_rent.fact_listing_rent_flows rf
			ON dc.sk_contract = rf.sk_contract
			AND rf.sk_contract_signed_date > 0
	INNER JOIN
		dw_rent.dim_house_listing dhl
			ON dhl.sk_house_listing = rf.sk_house_listing
	LEFT JOIN
		datalake_offboarding.contract_termination ct
			ON dc.sk_contract = ct.id_contract
	WHERE
		dc.dt_start = DATE_ADD(current_date, -10)
		AND dc.status = 'Ativo'
		AND ((ct.dt_termination > dc.dt_start) OR (ct.dt_termination is null))
		AND dhl.country_code = 'BR'
		AND dhl.rental_administrator = 'QUINTOANDAR' --Excluding brokerage only from these metrics
	GROUP BY 1,2
),
crisis_users AS (
	SELECT DISTINCT
        ft.sk_contract
    FROM
        dw_customer_support.fact_tickets AS ft
    INNER JOIN
        dw_customer_support.dim_ticket AS dt
            ON dt.sk_ticket = ft.sk_ticket
    INNER JOIN
        dw_customer_support.dim_department AS dd
            ON dd.department = dt.group_name
    WHERE
        (
            dt.group_name IN (
                'Notificação Extrajudicial [CE] [POS] [BACK]',
                'Dados Bancários [CE] [POS] [BACK]',
                'CX ReclameAqui Adquiridas [CE] [POS] [BACK]'
            ) OR dd.team IN ('Casos Especiais', 'Ouvidoria', 'ReclameAqui', 'Evictions')
        )
        AND ft.sk_user <> -1
        AND ft.ts_solved IS NULL
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
