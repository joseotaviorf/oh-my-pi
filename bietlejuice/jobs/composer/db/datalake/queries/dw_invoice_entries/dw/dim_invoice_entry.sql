with entry_type as (
    select 
        id_external, 
        replace(regexp_extract(bill_item, 'entry.bill-item/(.+)', 1), '-', ' ') as entry_type
    from
        datalake_retsuko_clean.entry
)
select 
    e.id_external as sk_invoice_entry,
    et.entry_type,
    replace(af.type, '-', ' ') as from_account_type,
    replace(at.type, '-', ' ') as to_account_type,
    case 
        when e.bill_item in ('entry.bill-item/adm-fee', 
                             'entry.bill-item/igpm-adm-fee',
                             'entry.bill-item/lockin') then 'adm fee'
		when e.bill_item in ('entry.bill-item/adm-fee-tax-ir', 
                             'entry.bill-item/adm-fee-tax-pcc',
                             'entry.bill-item/adm-fee-tax-pcc-quintoandar',
                             'entry.bill-item/adm-fee-tax-pcc-adm-partner') then 'adm-fee-taxes'
		when e.bill_item in ('entry.bill-item/adm-fee-adm-partner', 
                             'entry.bill-item/igpm-adm-partner-adm-fee') then 'adm partner adm fee'
		when e.bill_item = 'entry.bill-item/advance' then 'advance'
		when e.bill_item in ('entry.bill-item/brokerage-adm-partner', 
                             'entry.bill-item/brokerage-adm-partner-postponed') then 'brokerage adm partner'
		when e.bill_item in ('entry.bill-item/brokerage-estate-agent', 
                             'entry.bill-item/brokerage-estate-agent-postponed') then 'brokerage estate agent'
		when e.bill_item in ('entry.bill-item/brokerage-quinto-andar', 
                             'entry.bill-item/brokerage-quinto-andar-postponed') then 'brokerage quintoandar'
		when e.bill_item = 'entry.bill-item/brokerage-fee-tax-ir' then 'brokerage quintoandar taxes'
		when e.bill_item in ('entry.bill-item/brokerage-compensation', 
                             'entry.bill-item/campaign') then 'campaign'
		when e.bill_item in ('entry.bill-item/condominium', 
                             'entry.bill-item/condominium-usage', 
                             'entry.bill-item/condominium-fine', 
                             'entry.bill-item/improvement-work', 
                             'entry.bill-item/repair-work') then 'condo'
		when e.bill_item = 'entry.bill-item/early-termination-fee' then 'early termination fee'
		when e.bill_item = 'entry.bill-item/fine-and-interest' then 'fine and interest'
		when e.bill_item = 'entry.bill-item/home-insurance' then 'home insurance'
		when e.bill_item = 'entry.bill-item/insurance-guarantee' then 'insurance guarantee'
		when e.bill_item in ('entry.bill-item/iptu',
                             'entry.bill-item/iptu-adjustment') then 'iptu'
		when e.bill_item = 'entry.bill-item/loss' then 'loss'
		when e.bill_item = 'entry.bill-item/others'	then 'others'
		when e.bill_item = 'entry.bill-item/postponement' then 'postponement'
		when e.bill_item = 'entry.bill-item/property-damage-fine' then 'property-damage-fine'
		when e.bill_item = 'entry.bill-item/residential-protection-5A-acquittance' then 'protection-5A-acquittance'
		when e.bill_item = 'entry.bill-item/residential-protection-5A-fund-transfer' then 'protection-5A-fund-transfer'
		when e.bill_item in ('entry.bill-item/rental',
                             'entry.bill-item/igpm-rental') then 'rental'
		when e.bill_item = 'entry.bill-item/reservation' then 'reservation'
		else et.entry_type
    end as accounting_account,
    e.producer,
    e.description,
    e.accrual_year_month,
    now() as ts_load
from datalake_retsuko_clean.entry e
inner join entry_type et
    on e.id_external=et.id_external
inner join datalake_retsuko_clean.account af 
    on e.id_from_account = af.id
inner join datalake_retsuko_clean.account at 
    on e.id_to_account = at.id