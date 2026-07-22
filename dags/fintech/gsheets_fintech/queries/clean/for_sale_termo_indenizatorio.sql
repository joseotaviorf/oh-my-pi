WITH parsed AS (
    SELECT
        id_imovel,
        offer,
        valor_por_imovel,
        link_do_termo,
        data_de_assinatura,
        data_de_pagamento,
        aux_recon,
        valor_liquido_por_termo,
        valor_bruto_por_termo,
        valor_do_imposto,
        _imposto,
        _da_perda,
        valor_apos_perda,
        sale_price_agreed,
        brokerage_fee,
        brokerage_fee_value_5a,
        fee_5a,
        fee_5a_value,
        partner_fee,
        partner_fee_value,
        data_apto
    FROM
        datalake_gsheets_raw.for_sale_termo_indenizatorio
    WHERE
        NULLIF(TRIM(offer), '') IS NOT NULL
        AND TRIM(offer) != 'Offer'
)
SELECT
    CAST(NULLIF(TRIM(id_imovel), '') AS BIGINT) AS id_house,
    NULLIF(TRIM(offer), '') AS id_offer,
    link_do_termo AS term_link,
    aux_recon,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(valor_por_imovel, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS amount_per_property,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(valor_liquido_por_termo, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS net_amount_per_term,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(valor_bruto_por_termo, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS gross_amount_per_term,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(valor_do_imposto, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS tax_amount,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(valor_apos_perda, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS amount_after_loss,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(sale_price_agreed, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS sale_price_agreed,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(brokerage_fee, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_fee,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(brokerage_fee_value_5a, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_fee_value_5a,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(fee_5a, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS fee_5a,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(fee_5a_value, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS fee_5a_value,
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
                REGEXP_REPLACE(NULLIF(partner_fee_value, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS partner_fee_value,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(_imposto, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS tax_rate,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(_da_perda, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS loss_rate,
    COALESCE(
        CAST(NULLIF(data_de_assinatura, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_de_assinatura, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        )
    ) AS dt_term_signed,
    COALESCE(
        CAST(NULLIF(data_de_pagamento, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_de_pagamento, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        )
    ) AS dt_indemnity_payment,
    COALESCE(
        CAST(NULLIF(data_apto, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_apto, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        )
    ) AS dt_eligible
FROM
    parsed
