WITH parsed AS (
    SELECT
        origem_da_receita,
        id,
        id_offer,
        data_de_envio_ao_escritorio,
        status_offer,
        o_caso_e_dm_,
        status,
        `1p_ou_3p`,
        escritorio,
        endereco_imovel,
        nome_proprietario_quintoandar,
        cpf_proprietario_quintoandar,
        email_proprietario_quintoandar,
        endereco_do_pp,
        logradourorua_pp,
        no_pp,
        complemento_pp,
        bairro_pp,
        cidade_pp,
        estado_pp,
        cep_pp,
        id_corretor,
        nome_corretor,
        corretor_esta_ativo,
        cpf_corretor,
        telefone_corretor,
        email_corretor,
        id_en,
        nome_executivo_de_negociacao,
        cpf_en,
        telefone_en,
        email_en,
        id_ea,
        nome_executivo_associado,
        cpf_ea,
        telefone_ea,
        email_ea,
        ciq,
        nome_ciq,
        cpf_ciq,
        email_ciq,
        telefone_ciq,
        tqc,
        data_de_atualizacao_da_matricula,
        valor_da_transacao,
        taxa_corretagem_ideal_6,
        valor_devido,
        valor_do_acordo_corretagem_,
        data_acordo_termo_confissao_transito_em_julgado,
        a_vista_parcelado,
        boleto,
        mes_do_ultimo_pagamento_,
        valor_a_vista_1a_parcela,
        valor_juros_e_multa_se_houver_1a_parcela,
        data_envio_boleto_1a_parcela,
        data_vencimento_pgto_1a_parcela,
        data_do_pagamento_1a_parcela,
        status_da_parcela_1a_parcela,
        valor_2a_parcela,
        valor_juros_e_multa_se_houver_2a_parcela,
        data_envio_boleto_2a_parcela,
        data_vencimento_pgto_2a_parcela,
        data_do_pagamento_2a_parcela,
        status_da_parcela_2a_parcela,
        valor_3a_parcela,
        valor_juros_e_multa_se_houver_3a_parcela,
        data_envio_boleto_3a_parcela,
        data_vencimento_pgto_3a_parcela,
        data_do_pagamento_3a_parcela,
        status_da_parcela_3a_parcela,
        valor_4a_parcela,
        valor_juros_e_multa_se_houver_4a_parcela,
        data_envio_boleto_4a_parcela,
        data_vencimento_pgto_4a_parcela,
        data_do_pagamento_4a_parcela,
        status_da_parcela_4a_parcela,
        valor_5a_parcela,
        valor_juros_e_multa_se_houver_5a_parcela,
        data_envio_boleto_5a_parcela,
        data_vencimento_pgto_5a_parcela,
        data_do_pagamento_5a_parcela,
        status_da_parcela_5a_parcela,
        valor_6a_parcela,
        valor_juros_e_multa_se_houver_6a_parcela,
        data_envio_boleto_6a_parcela,
        data_vencimento_pgto_6a_parcela,
        data_do_pagamento_6a_parcela,
        status_da_parcela_6a_parcela,
        valor_7a_parcela,
        valor_juros_e_multa_se_houver_7a_parcela,
        data_envio_boleto_7a_parcela,
        data_vencimento_pgto_7a_parcela,
        data_do_pagamento_7a_parcela,
        status_da_parcela_7a_parcela,
        valor_8a_parcela,
        data_envio_boleto_8a_parcela,
        data_vencimento_pgto_8a_parcela,
        data_do_pagamento_8a_parcela,
        status_da_parcela_8a_parcela,
        valor_9a_parcela,
        valor_juros_e_multa_se_houver_9a_parcela,
        data_envio_boleto_9a_parcela,
        data_vencimento_pgto_9a_parcela,
        data_do_pagamento_9a_parcela,
        status_da_parcela_9a_parcela,
        valor_10a_parcela,
        valor_juros_e_multa_se_houver_10a_parcela,
        data_envio_boleto_10a_parcela,
        data_vencimento_pgto_10a_parcela,
        data_do_pagamento_10a_parcela,
        status_da_parcela_10a_parcela,
        valor_11a_parcela,
        valor_juros_e_multa_se_houver_11a_parcela,
        data_envio_boleto_11a_parcela,
        data_vencimento_pgto_11a_parcela,
        data_do_pagamento_11a_parcela,
        status_da_parcela_11a_parcela,
        valor_12a_parcela,
        data_envio_boleto_12a_parcela,
        data_vencimento_pgto_12a_parcela,
        data_do_pagamento_12a_parcela,
        status_da_parcela_12a_parcela,
        valor_13a_parcela,
        data_envio_boleto_13a_parcela,
        data_vencimento_pgto_13a_parcela,
        data_do_pagamento_13a_parcela,
        status_da_parcela_13a_parcela,
        valor_14a_parcela,
        data_envio_boleto_14a_parcela,
        data_vencimento_pgto_14a_parcela,
        data_do_pagamento_14a_parcela,
        status_da_parcela_14a_parcela,
        valor_15a_parcela,
        data_envio_boleto_15a_parcela,
        data_vencimento_pgto_15a_parcela,
        data_do_pagamento_15a_parcela,
        status_da_parcela_15a_parcela,
        valor_16a_parcela,
        data_envio_boleto_16a_parcela,
        data_vencimento_pgto_16a_parcela,
        data_do_pagamento_16a_parcela,
        status_da_parcela_16a_parcela,
        valor_17a_parcela,
        data_envio_boleto_17a_parcela,
        data_vencimento_pgto_17a_parcela,
        data_do_pagamento_17a_parcela,
        status_da_parcela_17a_parcela,
        valor_18a_parcela,
        data_envio_boleto_18a_parcela,
        data_vencimento_pgto_18a_parcela,
        data_do_pagamento_18a_parcela,
        status_da_parcela_18a_parcela,
        valor_total_recebido,
        valor_do_acordo,
        comissao_escritorio_parceiro,
        valor_a_ser_partilhado_entre_os_parceiros,
        comissao_cr_175,
        valor_comissao_en_4,
        valor_comissao_ea_05,
        valor_comissao_ciq_667,
        valor_comissao_tqc_20,
        comissao_quintoandar,
        valor_nf,
        idactum,
        data_quitacao_acordo,
        links_comprovantes_drive,
        data_envio_termo_de_quitacao,
        data_da_comunicacao_do_parceiro_sobre_repasse,
        data_da_ultima_assinatura_do_termo_partilha,
        status_repasse_parceiros,
        total_repassado,
        data_repasse,
        data_emissao_nf_5a,
        link_nf_5a,
        nf_recon_20250531,
        comentario,
        logradourorua,
        no,
        complemento,
        bairro,
        cidade,
        estado,
        cep
    FROM
        datalake_gsheets_raw.for_sale_bypass_revenue_control
    WHERE
        (
            (NULLIF(TRIM(id), '') IS NOT NULL AND TRIM(id) RLIKE '^[0-9]+$')
            OR (NULLIF(TRIM(id_offer), '') IS NOT NULL AND TRIM(id_offer) RLIKE '^[0-9]+$')
        )
        AND TRIM(UPPER(COALESCE(id, ''))) NOT IN ('ID', 'ID OFFER')
        AND TRIM(UPPER(COALESCE(id_offer, ''))) NOT IN ('ID', 'ID OFFER')
)
SELECT
    NULLIF(TRIM(origem_da_receita), '') AS revenue_source,
    NULLIF(TRIM(id), '') AS id,
    NULLIF(TRIM(id_offer), '') AS id_offer,
    COALESCE(
        CAST(NULLIF(data_de_envio_ao_escritorio, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_de_envio_ao_escritorio, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_de_envio_ao_escritorio, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_sent_to_office,
    NULLIF(TRIM(status_offer), '') AS offer_status,
    NULLIF(TRIM(o_caso_e_dm_), '') AS is_dm_case,
    NULLIF(TRIM(status), '') AS status,
    NULLIF(TRIM(`1p_ou_3p`), '') AS partner_channel,
    NULLIF(TRIM(escritorio), '') AS office_name,
    NULLIF(TRIM(endereco_imovel), '') AS property_address,
    NULLIF(TRIM(nome_proprietario_quintoandar), '') AS owner_name,
    NULLIF(TRIM(cpf_proprietario_quintoandar), '') AS owner_cpf,
    NULLIF(TRIM(email_proprietario_quintoandar), '') AS owner_email,
    NULLIF(TRIM(endereco_do_pp), '') AS seller_address,
    NULLIF(TRIM(logradourorua_pp), '') AS seller_street,
    NULLIF(TRIM(no_pp), '') AS seller_number,
    NULLIF(TRIM(complemento_pp), '') AS seller_complement,
    NULLIF(TRIM(bairro_pp), '') AS seller_neighborhood,
    NULLIF(TRIM(cidade_pp), '') AS seller_city,
    NULLIF(TRIM(estado_pp), '') AS seller_state,
    NULLIF(TRIM(cep_pp), '') AS seller_zip_code,
    NULLIF(TRIM(id_corretor), '') AS id_broker,
    NULLIF(TRIM(nome_corretor), '') AS broker_name,
    NULLIF(TRIM(corretor_esta_ativo), '') AS is_broker_active,
    NULLIF(TRIM(cpf_corretor), '') AS broker_cpf,
    NULLIF(TRIM(telefone_corretor), '') AS broker_phone,
    NULLIF(TRIM(email_corretor), '') AS broker_email,
    NULLIF(TRIM(id_en), '') AS id_negotiation_executive,
    NULLIF(TRIM(nome_executivo_de_negociacao), '') AS negotiation_executive_name,
    NULLIF(TRIM(cpf_en), '') AS negotiation_executive_cpf,
    NULLIF(TRIM(telefone_en), '') AS negotiation_executive_phone,
    NULLIF(TRIM(email_en), '') AS negotiation_executive_email,
    NULLIF(TRIM(id_ea), '') AS id_associate_executive,
    NULLIF(TRIM(nome_executivo_associado), '') AS associate_executive_name,
    NULLIF(TRIM(cpf_ea), '') AS associate_executive_cpf,
    NULLIF(TRIM(telefone_ea), '') AS associate_executive_phone,
    NULLIF(TRIM(email_ea), '') AS associate_executive_email,
    NULLIF(TRIM(ciq), '') AS ciq_code,
    NULLIF(TRIM(nome_ciq), '') AS ciq_name,
    NULLIF(TRIM(cpf_ciq), '') AS ciq_cpf,
    NULLIF(TRIM(email_ciq), '') AS ciq_email,
    NULLIF(TRIM(telefone_ciq), '') AS ciq_phone,
    NULLIF(TRIM(tqc), '') AS tqc_code,
    COALESCE(
        CAST(NULLIF(data_de_atualizacao_da_matricula, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_de_atualizacao_da_matricula, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_de_atualizacao_da_matricula, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_deed_update,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_da_transacao, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS transaction_amount,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(taxa_corretagem_ideal_6, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_rate,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_devido, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS amount_due,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_do_acordo_corretagem_, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_amount,
    COALESCE(
        CAST(NULLIF(data_acordo_termo_confissao_transito_em_julgado, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_acordo_termo_confissao_transito_em_julgado, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_acordo_termo_confissao_transito_em_julgado, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_deal,
    NULLIF(TRIM(a_vista_parcelado), '') AS installment_plan,
    NULLIF(TRIM(boleto), '') AS bank_slip_reference,
    NULLIF(TRIM(mes_do_ultimo_pagamento_), '') AS last_payment_month,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_a_vista_1a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_1,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_juros_e_multa_se_houver_1a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_interest_penalty_amount_1,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_1a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_1a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_1a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_1,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_1a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_1a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_1a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_1,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_1a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_1a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_1a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_1,
    NULLIF(TRIM(status_da_parcela_1a_parcela), '') AS installment_status_1,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_2a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_2,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_juros_e_multa_se_houver_2a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_interest_penalty_amount_2,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_2a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_2a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_2a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_2,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_2a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_2a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_2a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_2,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_2a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_2a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_2a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_2,
    NULLIF(TRIM(status_da_parcela_2a_parcela), '') AS installment_status_2,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_3a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_3,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_juros_e_multa_se_houver_3a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_interest_penalty_amount_3,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_3a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_3a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_3a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_3,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_3a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_3a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_3a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_3,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_3a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_3a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_3a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_3,
    NULLIF(TRIM(status_da_parcela_3a_parcela), '') AS installment_status_3,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_4a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_4,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_juros_e_multa_se_houver_4a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_interest_penalty_amount_4,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_4a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_4a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_4a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_4,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_4a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_4a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_4a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_4,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_4a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_4a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_4a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_4,
    NULLIF(TRIM(status_da_parcela_4a_parcela), '') AS installment_status_4,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_5a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_5,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_juros_e_multa_se_houver_5a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_interest_penalty_amount_5,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_5a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_5a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_5a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_5,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_5a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_5a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_5a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_5,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_5a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_5a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_5a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_5,
    NULLIF(TRIM(status_da_parcela_5a_parcela), '') AS installment_status_5,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_6a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_6,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_juros_e_multa_se_houver_6a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_interest_penalty_amount_6,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_6a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_6a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_6a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_6,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_6a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_6a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_6a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_6,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_6a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_6a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_6a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_6,
    NULLIF(TRIM(status_da_parcela_6a_parcela), '') AS installment_status_6,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_7a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_7,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_juros_e_multa_se_houver_7a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_interest_penalty_amount_7,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_7a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_7a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_7a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_7,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_7a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_7a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_7a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_7,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_7a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_7a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_7a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_7,
    NULLIF(TRIM(status_da_parcela_7a_parcela), '') AS installment_status_7,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_8a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_8,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_8a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_8a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_8a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_8,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_8a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_8a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_8a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_8,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_8a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_8a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_8a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_8,
    NULLIF(TRIM(status_da_parcela_8a_parcela), '') AS installment_status_8,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_9a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_9,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_juros_e_multa_se_houver_9a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_interest_penalty_amount_9,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_9a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_9a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_9a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_9,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_9a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_9a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_9a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_9,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_9a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_9a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_9a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_9,
    NULLIF(TRIM(status_da_parcela_9a_parcela), '') AS installment_status_9,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_10a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_10,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_juros_e_multa_se_houver_10a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_interest_penalty_amount_10,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_10a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_10a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_10a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_10,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_10a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_10a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_10a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_10,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_10a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_10a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_10a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_10,
    NULLIF(TRIM(status_da_parcela_10a_parcela), '') AS installment_status_10,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_11a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_11,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_juros_e_multa_se_houver_11a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_interest_penalty_amount_11,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_11a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_11a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_11a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_11,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_11a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_11a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_11a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_11,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_11a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_11a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_11a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_11,
    NULLIF(TRIM(status_da_parcela_11a_parcela), '') AS installment_status_11,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_12a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_12,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_12a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_12a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_12a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_12,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_12a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_12a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_12a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_12,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_12a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_12a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_12a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_12,
    NULLIF(TRIM(status_da_parcela_12a_parcela), '') AS installment_status_12,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_13a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_13,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_13a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_13a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_13a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_13,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_13a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_13a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_13a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_13,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_13a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_13a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_13a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_13,
    NULLIF(TRIM(status_da_parcela_13a_parcela), '') AS installment_status_13,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_14a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_14,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_14a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_14a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_14a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_14,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_14a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_14a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_14a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_14,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_14a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_14a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_14a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_14,
    NULLIF(TRIM(status_da_parcela_14a_parcela), '') AS installment_status_14,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_15a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_15,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_15a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_15a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_15a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_15,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_15a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_15a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_15a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_15,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_15a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_15a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_15a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_15,
    NULLIF(TRIM(status_da_parcela_15a_parcela), '') AS installment_status_15,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_16a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_16,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_16a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_16a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_16a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_16,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_16a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_16a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_16a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_16,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_16a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_16a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_16a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_16,
    NULLIF(TRIM(status_da_parcela_16a_parcela), '') AS installment_status_16,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_17a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_17,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_17a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_17a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_17a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_17,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_17a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_17a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_17a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_17,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_17a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_17a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_17a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_17,
    NULLIF(TRIM(status_da_parcela_17a_parcela), '') AS installment_status_17,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_18a_parcela, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS installment_amount_18,
    COALESCE(
        CAST(NULLIF(data_envio_boleto_18a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_boleto_18a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_boleto_18a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_bank_slip_sent_18,
    COALESCE(
        CAST(NULLIF(data_vencimento_pgto_18a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_vencimento_pgto_18a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_vencimento_pgto_18a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_installment_due_18,
    COALESCE(
        CAST(NULLIF(data_do_pagamento_18a_parcela, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_do_pagamento_18a_parcela, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_do_pagamento_18a_parcela, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_payment_18,
    NULLIF(TRIM(status_da_parcela_18a_parcela), '') AS installment_status_18,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_total_recebido, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS total_received,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_do_acordo, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS agreement_amount,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(comissao_escritorio_parceiro, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS accounting_commission,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_a_ser_partilhado_entre_os_parceiros, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS partner_share_amount,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(comissao_cr_175, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_estate_agent_amount_1,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_comissao_en_4, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_estate_agent_amount_2,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_comissao_ea_05, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_estate_agent_amount_3,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_comissao_ciq_667, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_estate_agent_amount_4,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_comissao_tqc_20, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_estate_agent_amount_5,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(comissao_quintoandar, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS brokerage_quinto_andar_amount_without_accounting_commission,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(valor_nf, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS invoice_amount,
    NULLIF(TRIM(idactum), '') AS is_idactum,
    COALESCE(
        CAST(NULLIF(data_quitacao_acordo, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_quitacao_acordo, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_quitacao_acordo, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_agreement_settlement,
    NULLIF(TRIM(links_comprovantes_drive), '') AS receipt_links,
    COALESCE(
        CAST(NULLIF(data_envio_termo_de_quitacao, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_envio_termo_de_quitacao, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_envio_termo_de_quitacao, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_settlement_term_sent,
    COALESCE(
        CAST(NULLIF(data_da_comunicacao_do_parceiro_sobre_repasse, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_da_comunicacao_do_parceiro_sobre_repasse, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_da_comunicacao_do_parceiro_sobre_repasse, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_partner_transfer_communication,
    COALESCE(
        CAST(NULLIF(data_da_ultima_assinatura_do_termo_partilha, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_da_ultima_assinatura_do_termo_partilha, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_da_ultima_assinatura_do_termo_partilha, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_last_share_term_signature,
    NULLIF(TRIM(status_repasse_parceiros), '') AS payment_status,
    CAST(
        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(NULLIF(total_repassado, ''), '[^0-9,.-]', ''),
                    '\\.',
                    ''
                ),
                ',',
                '.'
            ),
            ''
        ) AS DOUBLE
    ) AS broker_payment,
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
        CAST(NULLIF(data_emissao_nf_5a, '') AS DATE),
        CAST(
            NULLIF(
                regexp_extract(data_emissao_nf_5a, '([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})', 1),
                ''
            ) AS DATE
        ),
        to_date(
            regexp_extract(data_emissao_nf_5a, '([0-9]{{2}}/[0-9]{{2}}/[0-9]{{4}})', 1),
            'dd/MM/yyyy'
        )
    ) AS dt_invoice_5a_issued,
    NULLIF(TRIM(link_nf_5a), '') AS invoice_5a_link,
    NULLIF(TRIM(nf_recon_20250531), '') AS invoice_recon_20250531,
    NULLIF(TRIM(comentario), '') AS comment,
    NULLIF(TRIM(logradourorua), '') AS logradourorua,
    NULLIF(TRIM(no), '') AS property_number,
    NULLIF(TRIM(complemento), '') AS complement,
    NULLIF(TRIM(bairro), '') AS neighborhood,
    NULLIF(TRIM(cidade), '') AS city,
    NULLIF(TRIM(estado), '') AS state,
    NULLIF(TRIM(cep), '') AS zip_code
FROM
    parsed
