WITH
rental_brokerage_fee_5A AS (
	WITH
        invoice_list AS (
          SELECT
              *,
              ROW_NUMBER() OVER (PARTITION BY  id_contract, accrual_year_month ORDER BY accrual_year_month) AS seqnum
          FROM 
              datalake_invoice.invoice_all
          WHERE
              bill_item IN ('brokerage quinto andar')
              AND (
                (description LIKE '%Credito%')
                OR (description LIKE '%credito%')
                OR (description LIKE '%Crédito%')
                OR (description LIKE '%crédito%')
              )
        ),
		credit_discount AS (
			SELECT
				id_invoice_entry
			FROM 
				invoice_list
			WHERE
				seqnum = 1
		),

		installment_discount AS (
			SELECT
				id_invoice_entry
			FROM
				datalake_invoice.invoice_all
			WHERE
				bill_item IN ('brokerage quinto andar')
                AND description LIKE '%parcela%'
				AND description NOT LIKE '%parcela% 1 de 1'
		),

		discount AS (
			SELECT 
				dc.id_invoice_entry
			FROM 
				credit_discount AS dc
			UNION ALL
			SELECT 
				dp.id_invoice_entry
			FROM 
				installment_discount AS dp
		)

        SELECT
            ia.id_invoice_entry,
            CAST('rental_brokerage_fee_5A' AS STRING) AS rental_brokerage_fee_5A
        FROM datalake_invoice.invoice_all AS ia
        LEFT JOIN discount AS d
            ON ia.id_invoice_entry = d.id_invoice_entry
        WHERE
            ia.bill_item IN ('brokerage quinto andar')
            AND d.id_invoice_entry IS NULL

),

rental_agents_commission AS (
	WITH
	invoice_list AS (
		SELECT
			*,
			ROW_NUMBER() OVER (PARTITION BY  id_contract, accrual_year_month ORDER BY accrual_year_month) AS seqnum
		FROM datalake_invoice.invoice_all
		WHERE 
			bill_item IN ('brokerage estate agent')
			AND (
			(description LIKE '%Credito%')
			OR (description LIKE '%credito%')
			OR (description LIKE '%Crédito%')
			OR (description LIKE '%crédito%')
			)
	),
	credit_discount AS (
		SELECT
			id_invoice_entry
		FROM 
			invoice_list
		WHERE
			seqnum = 1
	),

	installment_discount AS (
		SELECT
			id_invoice_entry
		FROM
			datalake_invoice.invoice_all
		WHERE 
			bill_item IN ('brokerage estate agent')
			AND description LIKE '%parcela%'
			AND description NOT LIKE '%parcela% 1 de 1'
	),

	discount AS (
		SELECT 
			dc.id_invoice_entry
		FROM 
			credit_discount AS dc
		UNION ALL
		SELECT 
			dp.id_invoice_entry
		FROM 
			installment_discount AS dp
	)
	
	SELECT
		ia.id_invoice_entry,
		cast('rental_agents_commission' as STRING) AS rental_agents_commission
	FROM datalake_invoice.invoice_all AS ia
	LEFT JOIN 
		discount AS d
			ON ia.id_invoice_entry = d.id_invoice_entry
	WHERE 
		ia.bill_item IN ('brokerage estate agent')
		AND d.id_invoice_entry IS NULL

),

partner_revenue_share_brokerage AS (
	WITH
    invoice_list AS (
      SELECT
          *,
          ROW_NUMBER() OVER (PARTITION BY  id_contract, accrual_year_month ORDER BY accrual_year_month) AS seqnum
      FROM 
          datalake_invoice.invoice_all
      WHERE
          bill_item IN ('brokerage adm partner')
          AND description NOT LIKE '%Consultor%'
          AND (

                  (description LIKE '%Credito%')
                  OR (description LIKE '%credito%')
                  OR (description LIKE '%Crédito%')
                  OR (description LIKE '%crédito%')
              )
    ),
	credit_discount AS (
	    SELECT
	    	id_invoice_entry
	    FROM 
			invoice_list
	    WHERE
	    	seqnum = 1
	),

	installment_discount AS (
		SELECT
	    	id_invoice_entry
	    FROM
	    	datalake_invoice.invoice_all
		WHERE
			bill_item IN ('brokerage adm partner')
			AND description NOT LIKE '%Consultor%'
            AND description LIKE '%parcela%'
	    	AND description NOT LIKE '%parcela% 1 de 1'
	),

	discount AS (
    	SELECT 
			dc.id_invoice_entry
		FROM 
			credit_discount AS dc
		UNION ALL
		SELECT 
			dp.id_invoice_entry
		FROM 
			installment_discount AS dp
	)
    
    SELECT
        ia.id_invoice_entry,
        CAST('partner_revenue_share_brokerage' as STRING) AS partner_revenue_share_brokerage
    FROM 
        datalake_invoice.invoice_all AS ia
    LEFT JOIN 
        discount AS d
            ON ia.id_invoice_entry = d.id_invoice_entry
    WHERE
        ia.bill_item IN ('brokerage adm partner')
        AND ia.description NOT LIKE '%Consultor%'
        AND d.id_invoice_entry IS NULL

),

rental_CIQ_commission AS (
	WITH
        invoice_list AS (
          SELECT
              *,
              ROW_NUMBER() OVER (PARTITION BY  id_contract, accrual_year_month ORDER BY accrual_year_month) AS seqnum
          FROM 
              datalake_invoice.invoice_all
          WHERE
              bill_item IN ('brokerage adm partner')
              AND description LIKE '%Consultor%'
              AND (
                      (description LIKE '%Credito%')
                      OR (description LIKE '%credito%')
                      OR (description LIKE '%Crédito%')
                      OR (description LIKE '%crédito%')
                   )
        ),
		credit_discount AS (
			SELECT
				id_invoice_entry
			FROM 
				invoice_list
			WHERE
				seqnum = 1
		),

		installment_discount AS (
			SELECT
				id_invoice_entry
			FROM
				datalake_invoice.invoice_all
			WHERE
				bill_item IN ('brokerage adm partner')
				AND description LIKE '%Consultor%'
                AND description LIKE '%parcela%'
				AND description NOT LIKE '%parcela% 1 de 1'
		),

		discount AS (
			SELECT 
				dc.id_invoice_entry
			FROM 
				credit_discount AS dc
			UNION ALL
			SELECT 
				dp.id_invoice_entry
			FROM 
				installment_discount AS dp
		)
		
        SELECT
            ia.id_invoice_entry,
            CAST('rental_CIQ_commission' AS STRING) AS rental_CIQ_commission
        FROM 
            datalake_invoice.invoice_all AS ia
        LEFT JOIN 
            discount AS d
                ON ia.id_invoice_entry = d.id_invoice_entry
        WHERE
            ia.bill_item IN ('brokerage adm partner')
            AND ia.description LIKE '%Consultor%'
            AND d.id_invoice_entry IS NULL

),

rental_management_fee_5A AS (
	SELECT
		id_invoice_entry,
		CAST('rental_management_fee_5A' AS STRING) AS rental_management_fee_5A
	FROM 
		datalake_invoice.invoice_all
    WHERE
        bill_item IN ('adm fee', 'igpm adm fee', 'lockin', 'ipca adm fee', 'adjustment agreement adm fee')
),

partner_revenue_share_management AS (
	SELECT
		id_invoice_entry,
		CAST('partner_revenue_share_management' AS STRING) AS partner_revenue_share_management
	FROM 
		datalake_invoice.invoice_all
    WHERE
        bill_item IN ('adm fee adm partner', 'igpm adm partner adm fee', 'adjustment agreement adm partner adm fee')
),

brokerage_financing_fee AS (
	SELECT
		id_invoice_entry,
		CAST('brokerage_financing_fee' AS STRING) AS brokerage_financing_fee
	FROM 
		datalake_invoice.invoice_all
    WHERE
        bill_item IN ('brokerage installment fee')
)


SELECT
	ia.id_invoice_entry,
	COALESCE(rbf.rental_brokerage_fee_5a, rac.rental_agents_commission, prsb.partner_revenue_share_brokerage, rc.rental_ciq_commission, rmf.rental_management_fee_5a, prsm.partner_revenue_share_management, bff.brokerage_financing_fee) AS invoice_entry_revenue
FROM 
	datalake_invoice.invoice_all AS ia
	LEFT JOIN 
		rental_brokerage_fee_5A AS rbf
			ON ia.id_invoice_entry = rbf.id_invoice_entry
	LEFT JOIN 
		rental_agents_commission AS rac
			ON ia.id_invoice_entry = rac.id_invoice_entry
	LEFT JOIN 
		partner_revenue_share_brokerage AS prsb
			ON ia.id_invoice_entry = prsb.id_invoice_entry
	LEFT JOIN 
		rental_CIQ_commission AS rc
			ON ia.id_invoice_entry = rc.id_invoice_entry
	LEFT JOIN 
		rental_management_fee_5A AS rmf
			ON ia.id_invoice_entry = rmf.id_invoice_entry
	LEFT JOIN 
		partner_revenue_share_management AS prsm
			ON ia.id_invoice_entry = prsm.id_invoice_entry
	LEFT JOIN 
		brokerage_financing_fee AS bff
			ON ia.id_invoice_entry = bff.id_invoice_entry