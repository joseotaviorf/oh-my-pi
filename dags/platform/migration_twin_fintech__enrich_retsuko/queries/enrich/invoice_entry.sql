SELECT
    e.id_external AS id,
    e.id_invoice,
    e.id_external_reversed_entry,
    c.id_external AS id_contract,
    e.accounting_transaction_identifier,
    e.bill_item,
    REPLACE(regexp_extract(e.bill_item, 'entry.bill-item/(.+)', 1), '-', ' ') AS entry_type,
    REPLACE(af.type, '-', ' ') AS from_account_type,
    REPLACE(at.type, '-', ' ') AS to_account_type,
    CASE
        WHEN e.bill_item IN ('entry.bill-item/adm-fee',
                             'entry.bill-item/igpm-adm-fee',
                             'entry.bill-item/lockin') THEN 'adm fee'
		WHEN e.bill_item IN ('entry.bill-item/adm-fee-tax-ir',
                             'entry.bill-item/adm-fee-tax-pcc',
                             'entry.bill-item/adm-fee-tax-pcc-quintoandar',
                             'entry.bill-item/adm-fee-tax-pcc-adm-partner') then 'adm-fee-taxes'
		WHEN e.bill_item IN ('entry.bill-item/adm-fee-adm-partner',
                             'entry.bill-item/igpm-adm-partner-adm-fee') THEN 'adm partner adm fee'
		WHEN e.bill_item = 'entry.bill-item/advance' THEN 'advance'
		WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner',
                             'entry.bill-item/brokerage-adm-partner-postponed') THEN 'brokerage adm partner'
		WHEN e.bill_item IN ('entry.bill-item/brokerage-estate-agent',
                             'entry.bill-item/brokerage-estate-agent-postponed') THEN 'brokerage estate agent'
		WHEN e.bill_item IN ('entry.bill-item/brokerage-quinto-andar',
                             'entry.bill-item/brokerage-quinto-andar-postponed') THEN 'brokerage quintoandar'
		WHEN e.bill_item = 'entry.bill-item/brokerage-fee-tax-ir' THEN 'brokerage quintoandar taxes'
		WHEN e.bill_item IN ('entry.bill-item/brokerage-compensation',
                             'entry.bill-item/campaign') THEN 'campaign'
		WHEN e.bill_item IN ('entry.bill-item/condominium',
                             'entry.bill-item/condominium-usage',
                             'entry.bill-item/condominium-fine',
                             'entry.bill-item/improvement-work',
                             'entry.bill-item/repair-work') THEN 'condo'
		WHEN e.bill_item = 'entry.bill-item/early-termination-fee' THEN 'early termination fee'
		WHEN e.bill_item = 'entry.bill-item/fine-and-interest' THEN 'fine and interest'
		WHEN e.bill_item = 'entry.bill-item/home-insurance' THEN 'home insurance'
		WHEN e.bill_item = 'entry.bill-item/insurance-guarantee' THEN 'insurance guarantee'
		WHEN e.bill_item IN ('entry.bill-item/iptu',
                             'entry.bill-item/iptu-adjustment') THEN 'iptu'
		WHEN e.bill_item = 'entry.bill-item/loss' THEN 'loss'
		WHEN e.bill_item = 'entry.bill-item/others'	THEN 'others'
		WHEN e.bill_item = 'entry.bill-item/postponement' THEN 'postponement'
		WHEN e.bill_item = 'entry.bill-item/property-damage-fine' THEN 'property-damage-fine'
		WHEN e.bill_item = 'entry.bill-item/residential-protection-5A-acquittance' THEN 'protection-5A-acquittance'
		WHEN e.bill_item = 'entry.bill-item/residential-protection-5A-fund-transfer' THEN 'protection-5A-fund-transfer'
		WHEN e.bill_item IN ('entry.bill-item/rental',
                             'entry.bill-item/igpm-rental') THEN 'rental'
		WHEN e.bill_item = 'entry.bill-item/reservation' THEN 'reservation'
		ELSE REPLACE(regexp_extract(e.bill_item, 'entry.bill-item/(.+)', 1), '-', ' ')
    END AS accounting_account,
    c.is_rental_paid_in_advance,
    e.producer,
    e.description,
    e.accrual_year_month,
    e.due_year_month
FROM
    datalake_retsuko.entry AS e
INNER JOIN
    datalake_retsuko_clean.account AS af
        ON e.id_from_account = af.id
INNER JOIN
    datalake_retsuko_clean.account AS at
        ON e.id_to_account = at.id
LEFT JOIN
    datalake_retsuko_clean.contract c
        ON c.id = e.id_contract
