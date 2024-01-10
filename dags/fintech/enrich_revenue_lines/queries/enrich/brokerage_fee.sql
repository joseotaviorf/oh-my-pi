WITH contract_partnership_data AS (
    SELECT
        id_contract,
        partner_type,
        brokerage_split_percentage
    FROM
        datalake_ebdb_clean.contract_partnership_data
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY id DESC) = 1
),

brokerage_fee AS (
    WITH rental_brokerage_fee AS (
        SELECT
            c.sk_contract AS id_contract_ebdb,
            die.id AS id_invoice_entry,
            'quintoandar' AS brokerage_share,
            c.guarantee AS contract_guarantee,
            di.payment_status AS invoice_payment_status,
            c.first_rental_commission,
            ct.agent_brokerage_share AS agent_brokerage_share,
            p.brokerage_split_percentage,
            pp.brokerage_split_percentage AS select_agent_brokerage_split_percentage,
            ROUND(c.rent * c.first_rental_commission * (1.00 - COALESCE(ct.agent_brokerage_share,0.00) - COALESCE(p.brokerage_split_percentage,0.00) - COALESCE(pp.brokerage_split_percentage,0.00)),2) AS prod_theorical_amount,
            ROUND(SUM(fie.brl_entry_due_amount),2) AS invoice_theorical_amount,
            ROUND(SUM(fie.brl_entry_paid_amount),2) AS invoice_paid_amount,
            i.accrual_year_month AS accrual_year_month,
            DATE(di.ts_due) AS dt_due,
            DATE(di.ts_paid) AS dt_paid,
            c.dt_start AS dt_contract_start
        FROM datalake_invoice.invoice_entries fie
        INNER JOIN datalake_retsuko.invoice_entry die
            ON fie.id = die.id
        LEFT JOIN datalake_retsuko.invoice_info di
            ON di.id_invoice = fie.id_invoice
        LEFT JOIN datalake_retsuko.invoice i
            ON di.id_invoice = i.id_external
        LEFT JOIN dw_rent.dim_contract c
            ON c.sk_contract = fie.id_contract
        LEFT JOIN contract_partnership_data p
            ON c.sk_contract = p.id_contract
            AND p.partner_type = 'AUTONOMOUS_AGENT'
        LEFT JOIN contract_partnership_data pp
            ON c.sk_contract = pp.id_contract
            AND pp.partner_type = 'EXECUTIVE_FOR_RENT'
        LEFT JOIN datalake_ebdb_clean.contract ct
            ON c.sk_contract = ct.id
        WHERE
            die.from_account_type NOT IN ('quinto andar', 'contract expenses')
            AND di.payment_status <> 'canceled'
            AND die.entry_type IN ('brokerage quinto andar')
        GROUP BY
            1,2,3,4,5,6,7,8,9,10,13,14,15,16
    ),
    rental_agents_commission AS (
        SELECT
            c.sk_contract AS id_contract_ebdb,
            die.id AS id_invoice_entry,
            'rental agents' AS brokerage_share,
            c.guarantee AS contract_guarantee,
            di.payment_status AS invoice_payment_status,
            c.first_rental_commission,
            ct.agent_brokerage_share AS agent_brokerage_share,
            p.brokerage_split_percentage,
            pp.brokerage_split_percentage AS select_agent_brokerage_split_percentage,
            ROUND(c.rent * c.first_rental_commission * COALESCE(ct.agent_brokerage_share,0.00),2) AS prod_theorical_amount,
            ROUND(SUM(fie.brl_entry_due_amount),2) AS invoice_theorical_amount,
            ROUND(SUM(fie.brl_entry_paid_amount),2) AS invoice_paid_amount,
            i.accrual_year_month AS accrual_year_month,
            DATE(di.ts_due) AS dt_due,
            DATE(di.ts_paid) AS dt_paid,
            c.dt_start AS dt_contract_start
        FROM datalake_invoice.invoice_entries fie
        INNER JOIN datalake_retsuko.invoice_entry die
            ON fie.id = die.id
        LEFT JOIN datalake_retsuko.invoice_info di
            ON di.id_invoice = fie.id_invoice
        LEFT JOIN datalake_retsuko.invoice i
            ON di.id_invoice = i.id_external
        LEFT JOIN dw_rent.dim_contract c
            ON c.sk_contract = fie.id_contract
        LEFT JOIN contract_partnership_data p
            ON c.sk_contract = p.id_contract
            AND p.partner_type = 'AUTONOMOUS_AGENT'
        LEFT JOIN contract_partnership_data pp
            ON c.sk_contract = pp.id_contract
            AND pp.partner_type = 'EXECUTIVE_FOR_RENT'
        LEFT JOIN datalake_ebdb_clean.contract ct
            ON c.sk_contract = ct.id
        WHERE
            die.from_account_type NOT IN ('quinto andar', 'contract expenses')
            AND di.payment_status <> 'canceled'
            AND die.entry_type IN ('brokerage estate agent')
            AND di.invoice_user = 'landlord'
        GROUP BY
            1,2,3,4,5,6,7,8,9,10,13,14,15,16
    ),
    partner_revenue_share_brokerage AS (
        SELECT
            c.sk_contract AS id_contract_ebdb,
            die.id AS id_invoice_entry,
            'partner' AS brokerage_share,
            c.guarantee AS contract_guarantee,
            di.payment_status AS invoice_payment_status,
            c.first_rental_commission,
            ct.agent_brokerage_share AS agent_brokerage_share,
            p.brokerage_split_percentage,
            pp.brokerage_split_percentage AS select_agent_brokerage_split_percentage,
            ROUND(c.rent * c.first_rental_commission * COALESCE(p.brokerage_split_percentage,0.00),2) AS prod_theorical_amount,
            ROUND(SUM(fie.brl_entry_due_amount),2) AS invoice_theorical_amount,
            ROUND(SUM(fie.brl_entry_paid_amount),2) AS invoice_paid_amount,
            i.accrual_year_month AS accrual_year_month,
            DATE(di.ts_due) AS dt_due,
            DATE(di.ts_paid) AS dt_paid,
            c.dt_start AS dt_contract_start
        FROM datalake_invoice.invoice_entries fie
        INNER JOIN datalake_retsuko.invoice_entry die
            ON fie.id = die.id
        LEFT JOIN datalake_retsuko.invoice_info di
            ON di.id_invoice = fie.id_invoice
        LEFT JOIN datalake_retsuko.invoice i
            ON di.id_invoice = i.id_external
        LEFT JOIN dw_rent.dim_contract c
            ON c.sk_contract = fie.id_contract
        LEFT JOIN contract_partnership_data p
            ON c.sk_contract = p.id_contract
            AND p.partner_type = 'AUTONOMOUS_AGENT'
        LEFT JOIN contract_partnership_data pp
            ON c.sk_contract = pp.id_contract
            AND pp.partner_type = 'EXECUTIVE_FOR_RENT'
        LEFT JOIN datalake_ebdb_clean.contract ct
            ON c.sk_contract = ct.id
        WHERE
            die.from_account_type NOT IN ('quinto andar', 'contract expenses')
            AND di.payment_status <> 'canceled'
            AND die.entry_type IN ('brokerage adm partner')
            AND die.description NOT IN ('Taxa de corretagem - Consultor Imobiliário')
        GROUP BY
            1,2,3,4,5,6,7,8,9,10,13,14,15,16
    ),
    rental_ciq_commission AS (
        SELECT
            c.sk_contract AS id_contract_ebdb,
            die.id AS id_invoice_entry,
            'ciq' AS brokerage_share,
            c.guarantee AS contract_guarantee,
            di.payment_status AS invoice_payment_status,
            c.first_rental_commission,
            ct.agent_brokerage_share AS agent_brokerage_share,
            p.brokerage_split_percentage,
            pp.brokerage_split_percentage AS select_agent_brokerage_split_percentage,
            ROUND(c.rent * c.first_rental_commission * COALESCE(p.brokerage_split_percentage,0.00),2) AS prod_theorical_amount,
            ROUND(SUM(fie.brl_entry_due_amount),2) AS invoice_theorical_amount,
            ROUND(SUM(fie.brl_entry_paid_amount),2) AS invoice_paid_amount,
            i.accrual_year_month AS accrual_year_month,
            DATE(di.ts_due) AS dt_due,
            DATE(di.ts_paid) AS dt_paid,
            c.dt_start AS dt_contract_start
        FROM datalake_invoice.invoice_entries fie
        INNER JOIN datalake_retsuko.invoice_entry die
            ON fie.id = die.id
        LEFT JOIN datalake_retsuko.invoice_info di
            ON di.id_invoice = fie.id_invoice
        LEFT JOIN datalake_retsuko.invoice i
            ON di.id_invoice = i.id_external
        LEFT JOIN dw_rent.dim_contract c
            ON c.sk_contract = fie.id_contract
        LEFT JOIN contract_partnership_data p
            ON c.sk_contract = p.id_contract
            AND p.partner_type = 'AUTONOMOUS_AGENT'
        LEFT JOIN contract_partnership_data pp
            ON c.sk_contract = pp.id_contract
            AND pp.partner_type = 'EXECUTIVE_FOR_RENT'
        LEFT JOIN datalake_ebdb_clean.contract ct
            ON c.sk_contract = ct.id
        WHERE
            die.from_account_type NOT IN ('quinto andar', 'contract expenses')
            AND di.payment_status <> 'canceled'
            AND die.entry_type IN ('brokerage adm partner')
            AND die.description IN ('Taxa de corretagem - Consultor Imobiliário')
        GROUP BY
            1,2,3,4,5,6,7,8,9,10,13,14,15,16
    ),
    rental_ciq_select_commission AS (
        SELECT
            c.sk_contract AS id_contract_ebdb,
            die.id AS id_invoice_entry,
            'ciq select' AS brokerage_share,
            c.guarantee AS contract_guarantee,
            di.payment_status AS invoice_payment_status,
            c.first_rental_commission,
            ct.agent_brokerage_share AS agent_brokerage_share,
            p.brokerage_split_percentage,
            pp.brokerage_split_percentage AS select_agent_brokerage_split_percentage,
            ROUND(c.rent * c.first_rental_commission * COALESCE(pp.brokerage_split_percentage,0.00),2) AS prod_theorical_amount,
            ROUND(SUM(fie.brl_entry_due_amount),2) AS invoice_theorical_amount,
            ROUND(SUM(fie.brl_entry_paid_amount),2) AS invoice_paid_amount,
            i.accrual_year_month AS accrual_year_month,
            DATE(di.ts_due) AS dt_due,
            DATE(di.ts_paid) AS dt_paid,
            c.dt_start AS dt_contract_start
        FROM datalake_invoice.invoice_entries fie
        INNER JOIN datalake_retsuko.invoice_entry die
            ON fie.id = die.id
        LEFT JOIN datalake_retsuko.invoice_info di
            ON di.id_invoice = fie.id_invoice
        LEFT JOIN datalake_retsuko.invoice i
            ON di.id_invoice = i.id_external
        LEFT JOIN dw_rent.dim_contract c
            ON c.sk_contract = fie.id_contract
        LEFT JOIN contract_partnership_data p
            ON c.sk_contract = p.id_contract
            AND p.partner_type = 'AUTONOMOUS_AGENT'
        LEFT JOIN contract_partnership_data pp
            ON c.sk_contract = pp.id_contract
            AND pp.partner_type = 'EXECUTIVE_FOR_RENT'
        LEFT JOIN datalake_ebdb_clean.contract ct
            ON c.sk_contract = ct.id
        WHERE
            die.from_account_type NOT IN ('quinto andar', 'contract expenses')
            AND di.payment_status <> 'canceled'
            AND die.entry_type IN ('brokerage partner select')
        GROUP BY
            1,2,3,4,5,6,7,8,9,10,13,14,15,16
),
rental_brokerage_fee_discount AS (
    SELECT
        die.id AS id_invoice_entry
    FROM
        datalake_invoice.invoice_entries AS fie
    INNER JOIN
        datalake_retsuko.invoice_entry AS die
            ON fie.id = die.id
    WHERE
        die.description LIKE '%Desconto por cadastro com link de indicação%'
        AND fie.id_invoice > 0
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY fie.id_invoice, die.description ORDER BY fie.ts_created) > 1
),
rental_brokerage_fee_credit AS (
    SELECT
        die.id AS id_invoice_entry,
        die.description
    FROM
        datalake_invoice.invoice_entries AS fie
    INNER JOIN
        datalake_retsuko.invoice_entry AS die
            ON fie.id = die.id
    WHERE
        die.description LIKE '%Crédito - Parcelamento corretagem - QuintoAndar%'
        AND fie.id_invoice > 0
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY fie.id_invoice, die.description ORDER BY fie.ts_created) = 1
),
rental_brokerage_fee_installment AS (
  SELECT
    die.id AS id_invoice_entry
  FROM
    datalake_retsuko.invoice_entry AS die
  WHERE
    die.description LIKE 'Parcela%'
),
credit_fix_partner AS (
    SELECT
        die.id AS id_invoice_entry,
        die.description
    FROM
        datalake_invoice.invoice_entries AS fie
    INNER JOIN
        datalake_retsuko.invoice_entry AS die
            ON fie.id = die.id
    WHERE
        die.description LIKE '%Crédito - %'
        AND fie.id_invoice > 0
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY fie.id_invoice, die.description ORDER BY fie.ts_created) = 1
)

SELECT
    *
FROM
    rental_brokerage_fee
WHERE
    id_invoice_entry NOT IN (SELECT id_invoice_entry FROM rental_brokerage_fee_discount)
    AND id_invoice_entry NOT IN (SELECT id_invoice_entry FROM rental_brokerage_fee_credit)
    AND id_invoice_entry NOT IN (SELECT id_invoice_entry FROM rental_brokerage_fee_installment)
UNION
SELECT
    *
FROM
    rental_ciq_commission
WHERE
    id_invoice_entry NOT IN (SELECT id_invoice_entry FROM rental_brokerage_fee_discount)
UNION
SELECT
    *
FROM
    rental_agents_commission
WHERE
    id_invoice_entry NOT IN (SELECT id_invoice_entry FROM rental_brokerage_fee_discount)
    AND id_invoice_entry NOT IN (SELECT id_invoice_entry FROM rental_brokerage_fee_installment)
UNION
SELECT
    *
FROM partner_revenue_share_brokerage
WHERE
    id_invoice_entry NOT IN (SELECT id_invoice_entry FROM credit_fix_partner)
UNION
SELECT
    *
FROM
    rental_ciq_select_commission
)

SELECT
  id_contract_ebdb,
  id_invoice_entry,
  brokerage_share,
  contract_guarantee,
  invoice_payment_status,
  first_rental_commission,
  agent_brokerage_share,
  brokerage_split_percentage,
  select_agent_brokerage_split_percentage,
  prod_theorical_amount,
  SUM(invoice_theorical_amount) AS invoice_theorical_amount,
  SUM(invoice_paid_amount) AS invoice_paid_amount,
  accrual_year_month,
  dt_due,
  dt_paid,
  dt_contract_start
FROM
    brokerage_fee
GROUP BY 1,2,3,4,5,6,7,8,9,10,13,14,15,16
