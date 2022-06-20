WITH crisis_contracts as (
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
        dc.team IN ('Casos Especiais','Ouvidoria','Proteção 5A','ReclameAqui','Evictions')
		AND ft.sk_solved_date_local = -1
	GROUP BY 1
),
offboarding_contracts_wo_ticket as (
    WITH termination_requests_done AS (
        SELECT
            ct.sk_contract,
            DATEDIFF(current_date, ct.ts_termination_finished) AS days_since_finished
        FROM
            dw_datamarts_for_rent.contract_termination ct
		LEFT JOIN
			crisis_contracts cc
				ON cc.sk_contract = ct.sk_contract
		LEFT JOIN
			dw_public.fact_house_listings fhl
				ON ct.sk_contract = fhl.sk_contract
		LEFT JOIN
			dw_public.dim_contract dc
				ON ct.sk_contract = dc.sk_contract
        WHERE ct.status = 'DONE'
            AND cc.sk_contract IS NULL
            AND fhl.sk_partner = -1
            AND ct.dt_termination > dc.dt_start
			AND dc.country_code = 'BR'
            AND dc.rental_administrator = 'QUINTOANDAR' --Excluding brokerage only from these metrics
    )
    SELECT
    	sk_contract,
    	'Rescisão' AS step
    FROM
        termination_requests_done
    WHERE
        days_since_finished = 2
),
tenants_dwellers as (
	SELECT
		cp.cpf,
		cp.id_user,
		cp.name,
		cp.email,
		cp.phone_number,
		oc.sk_contract,
		oc.step
	FROM
        offboarding_contracts_wo_ticket oc
	INNER JOIN
        datalake_ebdb_clean.contract_person cp
		    ON oc.sk_contract = cp.id_contract
		    AND cp.type in ('Proprietario')
)
SELECT
	name as customer_name,
	email as customer_email,
	phone_number as customer_phone,
	step as campaign_step,
	'Proprietário' as customer_type,
	cpf as customer_cpf,
	id_user,
	'true' as campaign_type,
	'contract' as driver_type,
	sk_contract as id_driver
FROM tenants_dwellers
UNION ALL
SELECT
	'Teste Disparo' as customer_name,
	'testes.disparos.5a@gmail.com' as customer_email,
	'+5511123456789' as customer_phone,
	'Rescisão' as campaign_step,
	'Proprietário' as customer_type,
	'1234' as customer_cpf,
	'1234' as id_user,
	'true' as campaign_type,
	'contract' as driver_type,
	'1234' as id_driver