WITH anniversary_contracts AS (
	SELECT
		dc.sk_contract,
		CAST(((current_date - COALESCE(dc.dt_start, date(dc.ts_signature))) / 30) + ' meses' AS STRING) AS step
	FROM
        dw_public.dim_contract dc
	LEFT JOIN
        datalake_terminator_clean.termination t
		    ON dc.sk_contract = t.id_contract
	WHERE
        dc.status = 'Ativo'
		AND COALESCE(dc.dt_start, date(dc.ts_signature)) IN (ADD_MONTHS(current_date, -6), ADD_MONTHS(current_date, -12), ADD_MONTHS(current_date, -18),
			ADD_MONTHS(current_date, -24), ADD_MONTHS(current_date, -30), ADD_MONTHS(current_date, -36), ADD_MONTHS(current_date, -42),
			ADD_MONTHS(current_date, -48), ADD_MONTHS(current_date, -54), ADD_MONTHS(current_date, -60))
		AND t.id_contract IS NULL
		AND dc.country_code = 'BR'
),
recovery_contracts AS (
	SELECT
		ft.sk_contract,
		'Repescagem Casos Especiais' AS step
	FROM
        dw_tickets.dim_ticket dt
	INNER JOIN
        dw_tickets.fact_tickets ft
		    ON dt.sk_ticket  = ft.sk_ticket
	INNER JOIN
        datalake_gsheets_clean.department_control dc
		    ON dt.group_name = dc.department
	LEFT JOIN
        dw_public.dim_contract dc_
	        ON dc_.sk_contract = ft.sk_contract
	WHERE
        dc.team IN ('Casos Especiais','Ouvidoria','ReclameAqui')
		AND DATE(ft.ts_closed_local) = DATE_ADD(current_date, -10)
		AND dc_.status = 'Ativo'
		AND COALESCE(dc_.dt_start, date(dc_.ts_signature)) IN (ADD_MONTHS(current_date, -6), ADD_MONTHS(current_date, -12), ADD_MONTHS(current_date, -18),
			ADD_MONTHS(current_date, -24), ADD_MONTHS(current_date, -30), ADD_MONTHS(current_date, -36), ADD_MONTHS(current_date, -42),
			ADD_MONTHS(current_date, -48), ADD_MONTHS(current_date, -54), ADD_MONTHS(current_date, -60))
		AND dc_.country_code = 'BR'
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
		AND ft.sk_solved_date_local = -1
	GROUP BY 1
),
all_contracts AS (
	SELECT * FROM anniversary_contracts
	UNION
	SELECT * FROM recovery_contracts
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
        all_contracts ac
	INNER JOIN
        datalake_ebdb_clean.contract_person cp
		    ON ac.sk_contract = cp.id_contract
		    AND cp.type IN ('Inquilino','Morador')
		    AND cp.email IS NOT NULL
	LEFT JOIN
        crisis_users uc
		    ON uc.sk_contract = ac.sk_contract
	WHERE
        uc.sk_contract IS NULL
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
	'id_contract' AS driver_type,
	sk_contract AS id_driver
FROM tenants_dwellers
WHERE order_diff_email = 1
UNION ALL
SELECT
	'Teste Disparo' AS customer_name,
	'testes.disparos.5a@gmail.com' AS customer_email,
	'+5511123456789' AS customer_phone,
	'12 meses' AS campaign_step,
	'Inquilino' AS customer_type,
	'1234' AS customer_cpf,
	'1234' AS id_user,
	'true' AS campaign_type,
	'id_contract' AS driver_type,
	'1234' AS id_driver