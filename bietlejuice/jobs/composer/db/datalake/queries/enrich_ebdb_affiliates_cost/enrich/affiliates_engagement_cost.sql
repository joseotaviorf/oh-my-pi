-- MEMBER GET MEMBER CTEs
WITH latest_revision AS (
	SELECT
		afd_aud.id_affiliate_data,
		MAX(afd_aud.rev) AS id_lastest_revision
	FROM
		datalake_ebdb_clean.affiliate_data_aud afd_aud
	INNER JOIN
		datalake_ebdb_clean.user_revision_entity usrev
			ON usrev.id = afd_aud.rev
	INNER JOIN
		datalake_ebdb_clean.user us
			ON afd_aud.id_affiliate_data = us.id_affiliates
	INNER JOIN
		datalake_ebdb_clean.account_transaction act
			ON us.id_account = act.id_account
			AND act.type IN ('valorFixoPorIndicacaoDeImovel', 'porcentagemPorIndicacaoDeImovel')
			AND FROM_UNIXTIME(usrev.ts_revision / 1000) <= act.ts_transaction
			AND DATE(act.ts_created) = DATE('{year}-{month}-{day}')
	GROUP BY
		1
),
member_get_member_transactions AS (
	SELECT
		us.id AS id_user,
		us.id_agent,
		us.id_affiliates,
		hs.id_region,
		act.ts_transaction,
		lr.id_lastest_revision,
		SUM(act.value) AS transaction_value
	FROM
		datalake_ebdb_clean.account_transaction act
	INNER JOIN
		datalake_ebdb_clean.user us
			ON us.id_account = act.id_account
	INNER JOIN
		datalake_ebdb_clean.house hs
    		ON hs.id = act.id_house
	INNER JOIN
		latest_revision lr
			ON lr.id_affiliate_data = us.id_affiliates
	WHERE
		act.type IN ('valorFixoPorIndicacaoDeImovel', 'porcentagemPorIndicacaoDeImovel')
		AND DATE(act.ts_created) = DATE('{year}-{month}-{day}')
	GROUP BY
		1, 2, 3, 4, 5, 6
),
indication_member_data AS (
	SELECT
		us.id AS id_user,
		us.id_affiliates,
		mgmt.id_region,
		mgmt.ts_transaction,
		SUM(mgmt.transaction_value) AS transaction_value
	FROM
		member_get_member_transactions mgmt
	INNER JOIN
		datalake_ebdb_clean.affiliate_data_aud afd_aud
			ON afd_aud.id_affiliate_data = mgmt.id_affiliates
			AND afd_aud.rev = mgmt.id_lastest_revision
			AND ADD_MONTHS(afd_aud.ts_operation_start, 6) >= mgmt.ts_transaction
	INNER JOIN
		datalake_ebdb_clean.user us
			ON afd_aud.id_indicated_by = us.id
	GROUP BY
		1, 2, 3, 4
)

-- INDICAÇÕES DE IMÓVEL
SELECT
	us.id AS id_user,
	hs.id_region,
	us.id_affiliates,
	ld.id_agent,
	CASE
		WHEN ld.affiliate_type = 'Doorman' AND ld.id_agent IS NOT NULL
			THEN 'Doorman & Agent'
		WHEN ld.id_agent IS NOT NULL
			THEN 'Agent'
		ELSE COALESCE(ld.affiliate_type, 'N/A')
	END AS affiliate_type,
	act.type AS commission_type,
	SUM(act.value) AS commission_cost,
	act.ts_transaction AS ts_commission_cost,
	{year} AS year,
	{month} AS month,
	{day} AS day
FROM
	datalake_ebdb_clean.account_transaction act
LEFT JOIN
	datalake_ebdb_clean.user us
		ON us.id_account = act.id_account
INNER JOIN
	datalake_ebdb_clean.house hs
		ON hs.id = act.id_house
LEFT JOIN
	datalake_ebdb_clean.conversion_lead cvl
		ON cvl.id_house = act.id_house
INNER JOIN
	datalake_ebdb_clean.lead ld
		ON ld.id = cvl.id_converted_lead
WHERE
	act.type IN ('valorFixoPorIndicacaoDeImovel', 'porcentagemPorIndicacaoDeImovel', 'comissaoUnicaSobreAfiliadoIndicado')
	AND DATE(act.ts_created) = DATE('{year}-{month}-{day}')
GROUP BY
	1, 2, 3, 4, 5, 6, 8

UNION ALL

-- MEMBER GET MEMBER
SELECT
	imd.id_user,
	imd.id_region,
	imd.id_affiliates,
	us.id_agent,
	CASE
		WHEN afd.affiliate_type = 'Doorman' AND us.id_agent IS NOT NULL
			THEN 'Doorman & Agent'
		WHEN us.id_agent IS NOT NULL
			THEN 'Agent'
		ELSE COALESCE(afd.affiliate_type, 'N/A')
	END AS affiliate_type,
	'comissaoSobreAfiliadoIndicado' AS commission_type,
	SUM(imd.transaction_value * 0.1) AS commission_cost,
	imd.ts_transaction AS ts_commission_cost,
	{year} AS year,
	{month} AS month,
	{day} AS day
FROM
	indication_member_data imd
INNER JOIN
	datalake_ebdb_clean.user us
		ON us.id = imd.id_user
INNER JOIN
	datalake_ebdb_clean.affiliate_data afd
		ON afd.id = imd.id_affiliates
GROUP BY
	1, 2, 3, 4, 5, 6, 8
