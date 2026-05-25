SELECT
    clp.id_house AS sk_house,
    clp.id_house_listing AS sk_house_listing,
    clp.id_contract AS sk_contract,
    clp.id_accounting_entry AS sk_accounting_entry,
    clp.id_partner AS sk_partner,
    clp.id_ciq_user AS sk_user,
    clp.id_internal_agent AS sk_internal_agent,
    clp.id_enrollment AS sk_enrollment,
    clp.id_owner AS sk_owner,
    clp.payment_status,
    clp.pricing_type,
    clp.purchase_value,
    clp.amount_paid,
    clp.is_paid,
    clp.dt_paid,
    clp.ts_contract_signed,
    clp.ts_house_registration,
    clp.ts_first_listing,
    GREATEST(
        clp.ts_contract_signed, 
        clp.dt_paid
    ) AS ts_updated,
    NOW() AS ts_load,
    clp.year,
    clp.month,
    clp.day
FROM
    datalake_ciq.ciq_listing_purchase AS clp
WHERE
    clp.is_eligible IS TRUE
    AND DATE(GREATEST(
        clp.ts_contract_signed, 
        clp.dt_paid
    )) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY clp.id_house, clp.id_contract, clp.id_partner
        ORDER BY GREATEST(clp.ts_contract_signed, clp.dt_paid) DESC NULLS LAST
    ) = 1