SELECT
    NULLIF(NULLIF(TRIM(email), ''), '-') AS employee_email,
    NULLIF(NULLIF(TRIM(ciclo), ''), '-') AS performance_cycle,
    NULLIF(NULLIF(TRIM(email_avaliador), ''), '-') AS evaluator_email,
    NULLIF(NULLIF(TRIM(comentarios_do_comite), ''), '-') AS committee_comments,
    NULLIF(NULLIF(TRIM(self_evaluation), ''), '-') AS self_evaluation_comments,
    NULLIF(NULLIF(TRIM(peers_1), ''), '-') AS peer_1_comments,
    NULLIF(NULLIF(TRIM(peers_2), ''), '-') AS peer_2_comments,
    NULLIF(NULLIF(TRIM(peers_3), ''), '-') AS peer_3_comments,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(how_faz_o_certo), ''), '-')
        AS INT
    ) AS how_doing_the_right_thing_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(how_resolve_a_dor_do_cliente), ''), '-')
        AS INT
    ) AS how_customer_pain_resolution_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(how_abraca_o_novo), ''), '-')
        AS INT
    ) AS how_embracing_change_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(how_entrega_o_que_promete), ''), '-')
        AS INT
    ) AS how_delivers_on_commitments_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(how_colabora_para_ir_mais_longe), ''), '-')
        AS INT
    ) AS how_collaborates_to_go_further_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(how_protagoniza_a_propria_carreira), ''), '-')
        AS INT
    ) AS how_career_ownership_score,
    TRY_CAST(
        regexp_replace(
            NULLIF(NULLIF(TRIM(`what`), ''), '-'),
            ',', '.'
        ) AS DOUBLE
    ) AS what_raw_score,
    TRY_CAST(
        regexp_replace(
            NULLIF(NULLIF(TRIM(what_calculado), ''), '-'),
            ',', '.'
        ) AS DOUBLE
    ) AS what_normalized_score,
    TRY_CAST(
        regexp_replace(
            NULLIF(NULLIF(TRIM(`how`), ''), '-'),
            ',', '.'
        ) AS DOUBLE
    ) AS how_score,
    TRY_CAST(
        regexp_replace(
            NULLIF(NULLIF(TRIM(performance), ''), '-'),
            ',', '.'
        ) AS DOUBLE
    ) AS performance_score,
    TRY_CAST(
        regexp_replace(
            NULLIF(NULLIF(TRIM(avg_what_and_how), ''), '-'),
            ',', '.'
        ) AS DOUBLE
    ) AS avg_what_and_how,
    NULLIF(NULLIF(TRIM(fx_performance), ''), '-') AS performance_band_name,
    NULLIF(NULLIF(TRIM(prontidao), ''), '-') AS readiness_rating,
    NULLIF(NULLIF(TRIM(risco_de_perda), ''), '-') AS risk_of_loss_rating,
    NULLIF(NULLIF(TRIM(potencial), ''), '-') AS potential_rating,
    NULLIF(NULLIF(TRIM(criticidade), ''), '-') AS criticality_rating,
    NULLIF(NULLIF(TRIM(matriz_de_desenvolvimento), ''), '-') AS development_matrix,
    ts_load
FROM
    datalake_gsheets_people_raw.legacy_performance_review
