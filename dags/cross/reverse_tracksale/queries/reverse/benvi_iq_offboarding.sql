-- Benvi IQ Offboarding: 2 days after termination finished and status DONE
-- Get all contracts that were involved in Crisis, RA or Proteção 5A
WITH crisis_contracts AS (
	SELECT
		ft.sk_contract
	FROM
        dw_tickets.dim_ticket AS dt
	INNER JOIN
        dw_tickets.fact_tickets AS ft
		    ON dt.sk_ticket  = ft.sk_ticket
            AND ft.sk_solved_date_local = -1
    INNER JOIN
        dw_customer_support.dim_department AS dc
			ON dt.group_name = dc.department
			AND dc.team IN ('Casos Especiais','Ouvidoria','Proteção 5A','ReclameAqui','Evictions') -- exclude contracts from these areas
	GROUP BY 1
),
offboarding_contracts_wo_ticket AS (
-- get offboarding without tickets
    WITH termination_requests_done AS (
        SELECT
            ct.id_contract,
            DATEDIFF(CURRENT_DATE(), ct.ts_termination_finished) AS days_since_finished
        FROM
            datalake_offboarding.contract_termination AS ct
        LEFT JOIN
            crisis_contracts AS cc
                ON cc.sk_contract = ct.id_contract
        LEFT JOIN
            dw_public.fact_house_listings AS fhl
                ON ct.id_contract = fhl.sk_contract
        LEFT JOIN
            dw_rent.dim_contract AS dc
                ON ct.id_contract = dc.sk_contract
        WHERE
            dc.country_code = 'MX'
            AND ct.status = 'DONE'
            AND cc.sk_contract IS NULL -- excluding contracts with crisis
            AND fhl.sk_partner = -1 --excluding B2B listings
            AND ct.dt_termination > dc.dt_start
    )
    SELECT
    	id_contract,
    	'Rescisão' AS step
    FROM
        termination_requests_done
    WHERE
        days_since_finished = 2
),
-- considering all tenants and dwellers involved in contracts
tenants_dwellers AS (
	SELECT
		cp.sk_user,
        oc.id_contract,
		dcp.personal_document AS cpf,
		dcp.full_name AS name,
		dcp.email,
		dcp.phone_number,
		oc.step,
		DENSE_RANK() OVER(PARTITION BY cp.sk_contract, dcp.email ORDER BY cp.sk_contract_person) AS order_diff_email
	FROM
        offboarding_contracts_wo_ticket AS oc
    INNER JOIN
		dw_rent.fact_contract_people AS cp
			ON oc.id_contract = cp.sk_contract
			AND cp.contract_role IN ('tenant', 'dweller')
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
	id_contract AS id_driver,
    NOW() AS ts_load
FROM
    tenants_dwellers
WHERE
    order_diff_email = 1
UNION ALL
SELECT
	'Teste Disparo' AS customer_name,
	'testes.disparos.5a@gmail.com' AS customer_email,
	'+5511123456789' AS customer_phone,
	'Rescisão' AS campaign_step,
	'Inquilino' AS customer_type,
	'12345' AS customer_cpf,
	'12345' AS id_user,
	'true' AS campaign_type,
	'contract' AS driver_type,
	'12345' AS id_driver,
    NOW() AS ts_load
