WITH contract_user AS (
	SELECT
	    c.id,
	    COALESCE(rf.id_client, -1) AS id_client,
	    COALESCE(h.id_user, pa_b2b_online.id_user, pa_b2b_prime.id_user, -1) AS id_owner,
  	    COALESCE(pa_b2b_online.id_partner, pa_b2b_prime.id_partner, -1) AS id_partner
	FROM
        datalake_ebdb_clean.contract AS c
	INNER JOIN
        datalake_ebdb_clean.rent_flow AS rf
            ON c.id_house = rf.id_house
            AND c.id_user = rf.id_client
	INNER JOIN
        datalake_ebdb_clean.house AS h
            ON c.id_house = h.id
	LEFT JOIN
        datalake_ebdb_clean.partner_agent AS pa_b2b_prime
            ON h.id_user = pa_b2b_prime.id_user
	LEFT JOIN
        datalake_ebdb_clean.conversion_lead AS lc
            ON lc.id_house = h.id
	LEFT JOIN
        datalake_ebdb_clean.lead AS l
            ON l.id = lc.id_converted_lead
            AND l.affiliate_type = 'B2BPartner'
	LEFT JOIN
        datalake_ebdb_clean.affiliate_data AS ad
            ON ad.id = l.id_affiliate_has_indicated
    LEFT JOIN
        datalake_ebdb_clean.user AS ua
            ON ad.id=ua.id_affiliates
	LEFT JOIN
        datalake_ebdb_clean.partner_agent AS pa_b2b_online
            ON pa_b2b_online.id_user = ua.id
)

SELECT
	e.id_external AS id,
    e.id_external_reversed_entry,
	COALESCE(i.id_external, -1) AS id_invoice,
	COALESCE(c_rtsk.id_external, -1) AS id_contract,
	CASE
        WHEN af.type = 'tenant'
            OR at.type = 'tenant' THEN u.id_client
		WHEN af.type = 'landlord'
            OR at.type = 'landlord' THEN u.id_owner
		WHEN af.type = 'adm-partner'
            OR at.type = 'adm-partner' THEN u.id_partner
		ELSE -1
	END AS id_contract_user,
	COALESCE(h.id_region, -1) AS id_region,
	COALESCE(CAST(DATE_FORMAT(e.ts_created, 'yyyyMMdd') AS INT), -1) AS id_created_date,
	COALESCE(CAST(DATE_FORMAT(i.ts_due, 'yyyyMMdd') AS INT), -1) AS id_due_date,
	COALESCE(CAST(DATE_FORMAT(i.ts_paid, 'yyyyMMdd') AS INT), -1) AS id_paid_date,
    e.accounting_transaction_identifier,
	e.amount AS brl_entry_due_amount,
	ROUND(((1.0*e.amount/ABS(i.due_amount))*i.paid_amount), 2) AS brl_entry_paid_amount,
    e.ts_created
FROM
    datalake_retsuko.entry AS e
LEFT JOIN
    datalake_retsuko.invoice AS i
        ON e.id_invoice = i.id
INNER JOIN
    datalake_retsuko_clean.account AS af
        ON e.id_from_account = af.id
INNER JOIN
    datalake_retsuko_clean.account AS at
        ON e.id_to_account = at.id
LEFT JOIN datalake_retsuko_clean.contract AS c_rtsk
        ON e.id_contract = c_rtsk.id
LEFT JOIN datalake_ebdb_clean.contract AS c_ebdb
        ON c_rtsk.id_external = c_ebdb.id
LEFT JOIN datalake_ebdb_clean.house AS h
        ON c_ebdb.id_house = h.id
LEFT JOIN contract_user AS u
        ON u.id = c_rtsk.id_external
