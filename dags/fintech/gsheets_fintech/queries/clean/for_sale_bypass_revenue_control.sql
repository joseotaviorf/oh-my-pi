WITH parsed AS (
    SELECT
        id,
        valor_do_acordo,
        data_acordo_termo_confissao_transito_em_julgado,
        comissao_cr_175,
        valor_comissao_en_4,
        valor_comissao_ea_05,
        valor_comissao_ciq_667,
        valor_comissao_tqc_20,
        comissao_escritorio_parceiro,
        comissao_quintoandar,
        status_repasse_parceiros,
        total_repassado,
        data_repasse,
        data_do_pagamento,
        data_do_pagamento_1,
        data_do_pagamento_2,
        data_do_pagamento_3,
        data_do_pagamento_4,
        data_do_pagamento_5,
        parcela_1,
        parcela_2,
        parcela_3,
        parcela_4,
        parcela_5,
        parcela_6,
        status_parcela_1,
        status_parcela_2,
        status_parcela_3,
        status_parcela_4,
        status_parcela_5,
        status_parcela_6,
        parcelado
    FROM
        datalake_gsheets_raw.for_sale_bypass_revenue_control
    WHERE
        NULLIF(TRIM(id), '') IS NOT NULL
        AND TRIM(UPPER(id)) != 'ID'
        AND TRIM(id) RLIKE '^[0-9]+$'
)
SELECT
    NULLIF(TRIM(id), '') AS id_offer,
    status_repasse_parceiros AS payment_status,
    parcelado AS installment_plan,
    status_parcela_1 AS installment_status_1,
    status_parcela_2 AS installment_status_2,
    status_parcela_3 AS installment_status_3,
    status_parcela_4 AS installment_status_4,
    status_parcela_5 AS installment_status_5,
    status_parcela_6 AS installment_status_6,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(valor_do_acordo, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_amount,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(comissao_cr_175, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_estate_agent_amount_1,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(valor_comissao_en_4, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_estate_agent_amount_2,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(valor_comissao_ea_05, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_estate_agent_amount_3,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(valor_comissao_ciq_667, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_estate_agent_amount_4,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(valor_comissao_tqc_20, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_estate_agent_amount_5,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(comissao_escritorio_parceiro, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS accounting_commission,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(comissao_quintoandar, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_quinto_andar_amount_without_accounting_commission,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(total_repassado, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS broker_payment,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(parcela_1, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_1,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(parcela_2, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_2,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(parcela_3, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_3,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(parcela_4, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_4,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(parcela_5, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_5,
    CAST(
        NULLIF(
            REPLACE(
                REGEXP_REPLACE(NULLIF(parcela_6, ''), '[^0-9,.-]', ''),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_6,
    COALESCE(
        CAST(NULLIF(data_acordo_termo_confissao_transito_em_julgado, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(
                    data_acordo_termo_confissao_transito_em_julgado,
                    '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})',
                    1
                ),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(
                data_acordo_termo_confissao_transito_em_julgado,
                '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})',
                1
            ),
            'dd/MM/yyyy'
        )
    ) AS dt_deal,
    COALESCE(
        CAST(NULLIF(data_repasse, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_repasse, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_repasse, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_transfer,
    COALESCE(
        CAST(NULLIF(data_do_pagamento, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_1, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_1, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_1, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_1,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_2, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_2, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_2, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_2,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_3, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_3, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_3, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_3,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_4, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_4, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_4, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_4,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_5, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_5, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_5, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_5
FROM
    parsed
