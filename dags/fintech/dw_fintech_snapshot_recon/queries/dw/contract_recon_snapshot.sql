WITH locale_ids AS (
    SELECT
        DISTINCT city,
        MIN(id_locale) AS id_locale
    FROM
        datalake_gsheets_clean.cod_locale
    GROUP BY
        1
),
contract_invoice_region AS (
    SELECT
        sk_contract,
        MAX_BY(sk_region, ts_created) AS sk_region
    FROM
        dw_payment.fact_invoice_entries
    WHERE
        sk_contract IS NOT NULL
        AND sk_region IS NOT NULL
        AND sk_region <> -1
    GROUP BY
        sk_contract
),
contract_recon_base AS (
    SELECT
        c.sk_contract,
        ct.id_house,
        COALESCE(r_listing.city_name, r_invoice.city_name, r_house.city_name) AS locale,
        cl.id_locale AS localidade,
        c.status,
        c.version,
        c.guarantee,
        c.is_contract_b2b,
        cr.is_rental_paid_in_advance,
        c.rental_administrator,
        c.dt_start,
        ct.dt_termination AS contract_annulment,
        c.dt_intended_end,
        c.dt_start > ct.dt_termination AND ct.dt_termination IS NOT NULL AS ended_before_started,
        c.rent,
        c.iptu,
        c.condo,
        c.home_insurance_value,
        c.monthly_administration_fee,
        c.tenant_service_fee,
        c.condo_payer,
        c.iptu_payer,
        c.first_rent_charged,
        b.`5A_brokerage_amount`,
        b.agent_brokerage_amount,
        b.ciq_brokerage_amount,
        b.select_brokerage_amount,
        b.`3p_brokerage_amount`,
        b.`5A_brokerage_share`,
        b.agent_brokerage_share,
        b.ciq_brokerage_share,
        b.select_brokerage_share,
        b.`3p_brokerage_share`,
        MAX(IF(LENGTH(ctype.cpf) = 18, 'PJ', 'PF')) AS contract_type
    FROM
        dw_rent.dim_contract AS c
    LEFT JOIN
        dw_rent.fact_house_listings AS rf
            ON rf.sk_contract = c.sk_contract
    LEFT JOIN
        dw_public.dim_region AS r_listing
            ON r_listing.sk_region = rf.sk_region
    LEFT JOIN
        contract_invoice_region AS fir
            ON fir.sk_contract = c.sk_contract
    LEFT JOIN
        dw_public.dim_region AS r_invoice
            ON r_invoice.sk_region = fir.sk_region
    LEFT JOIN
        datalake_accounting_funnel.for_rent_contract_brokerage AS b
            ON b.id_contract = c.sk_contract
    LEFT JOIN
        datalake_ebdb_clean.contract AS ct
            ON c.sk_contract = ct.id
    LEFT JOIN
        datalake_ebdb_clean.house AS h
            ON h.id = ct.id_house
    LEFT JOIN
        dw_public.dim_region AS r_house
            ON h.id_region IS NOT NULL
            AND h.id_region <> -1
            AND r_house.sk_region = h.id_region
    LEFT JOIN
        locale_ids AS cl
            ON cl.city = COALESCE(r_listing.city_name, r_invoice.city_name, r_house.city_name)
    LEFT JOIN
        datalake_ebdb_clean.contract_person AS ctype
            ON ctype.id_contract = c.sk_contract
    LEFT JOIN
        datalake_retsuko_clean.contract AS cr
            ON cr.id_external = c.sk_contract
    WHERE
        c.country_code = 'BR'
        AND c.status IN ('Ativo', 'Finalizado')
        AND c.type = 'FullService'
    GROUP BY ALL
)
SELECT
    sk_contract,
    id_house,
    locale,
    localidade,
    status,
    version,
    guarantee,
    is_contract_b2b,
    is_rental_paid_in_advance,
    rental_administrator,
    dt_start,
    contract_annulment,
    dt_intended_end,
    ended_before_started,
    rent,
    iptu,
    condo,
    home_insurance_value,
    monthly_administration_fee,
    tenant_service_fee,
    condo_payer,
    iptu_payer,
    first_rent_charged,
    5A_brokerage_amount,
    agent_brokerage_amount,
    ciq_brokerage_amount,
    select_brokerage_amount,
    3p_brokerage_amount,
    5A_brokerage_share,
    agent_brokerage_share,
    ciq_brokerage_share,
    select_brokerage_share,
    3p_brokerage_share,
    contract_type,
    NOW() AS ts_snapshot,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    contract_recon_base
