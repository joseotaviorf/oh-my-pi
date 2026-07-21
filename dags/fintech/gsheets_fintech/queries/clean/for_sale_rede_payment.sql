WITH parsed AS (
    SELECT
        id_house,
        id_offer,
        address,
        partner_type,
        file,
        partner,
        sale_type,
        partner_fee,
        cnpj,
        company_name,
        bank_name,
        bank_code,
        agency,
        account_pj,
        account_type,
        balance_of_the_financial_flow,
        have_balence_in_financial_flow,
        found_in,
        paid_in,
        month,
        year,
        status,
        was_located_in_the_recent_scan,
        theres_a_duplicate_id_house,
        tipo_de_repasse,
        modelo_repasse,
        aux
    FROM
        datalake_gsheets_raw.for_sale_rede_payment
    WHERE
        NULLIF(TRIM(id_offer), '') IS NOT NULL
        AND TRIM(id_offer) != 'ID OFFER'
)
SELECT
    CAST(NULLIF(TRIM(id_house), '') AS BIGINT) AS id_house,
    NULLIF(TRIM(id_offer), '') AS id_offer,
    address,
    partner_type,
    file AS file_reference,
    partner AS partner_name,
    sale_type,
    cnpj,
    company_name,
    bank_name,
    bank_code,
    agency AS bank_agency,
    account_pj AS bank_account_pj,
    account_type AS bank_account_type,
    found_in,
    status,
    have_balence_in_financial_flow AS has_financial_flow_balance,
    was_located_in_the_recent_scan AS was_located_in_recent_scan,
    theres_a_duplicate_id_house AS has_duplicate_id_house,
    tipo_de_repasse AS transfer_type,
    modelo_repasse AS transfer_model,
    aux,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(partner_fee, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS partner_fee,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(balance_of_the_financial_flow, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS financial_flow_balance,
    CAST(NULLIF(month, '') AS INT) AS month,
    CAST(NULLIF(year, '') AS INT) AS year,
    COALESCE(
        CAST(NULLIF(paid_in, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(paid_in, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(paid_in, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_paid_in
FROM
    parsed
