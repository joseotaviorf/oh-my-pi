SELECT
    NULLIF(NULLIF(TRIM(lp.email), ''), '-') AS employee_email,
    NULLIF(NULLIF(TRIM(lp.ciclo), ''), '-') AS performance_cycle,
    NULLIF(NULLIF(TRIM(lp.email_avaliador), ''), '-') AS evaluator_email,
    NULLIF(NULLIF(TRIM(lp.comentarios_do_comite), ''), '-') AS committee_comments,
    NULLIF(NULLIF(TRIM(lp.self_evaluation), ''), '-') AS self_evaluation_comments,
    NULLIF(NULLIF(TRIM(lp.peers_1), ''), '-') AS peer_1_comments,
    NULLIF(NULLIF(TRIM(lp.peers_2), ''), '-') AS peer_2_comments,
    NULLIF(NULLIF(TRIM(lp.peers_3), ''), '-') AS peer_3_comments,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(lp.how_faz_o_certo), ''), '-')
        AS DOUBLE
    ) AS how_doing_the_right_thing_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(lp.how_resolve_a_dor_do_cliente), ''), '-')
        AS DOUBLE
    ) AS how_customer_pain_resolution_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(lp.how_abraca_o_novo), ''), '-')
        AS DOUBLE
    ) AS how_embracing_change_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(lp.how_entrega_o_que_promete), ''), '-')
        AS DOUBLE
    ) AS how_delivers_on_commitments_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(lp.how_colabora_para_ir_mais_longe), ''), '-')
        AS DOUBLE
    ) AS how_collaborates_to_go_further_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(lp.how_protagoniza_a_propria_carreira), ''), '-')
        AS DOUBLE
    ) AS how_career_ownership_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(lp.`what`), ''), '-')
        AS DOUBLE
    ) AS what_raw_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(lp.what_calculado), ''), '-')
        AS DOUBLE
    ) AS what_normalized_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(lp.`how`), ''), '-')
        AS DOUBLE
    ) AS how_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(lp.performance), ''), '-')
        AS DOUBLE
    ) AS performance_score,
    TRY_CAST(
        NULLIF(NULLIF(TRIM(lp.avg_what_and_how), ''), '-')
        AS DOUBLE
    ) AS avg_what_and_how,
    NULLIF(NULLIF(TRIM(lp.fx_performance), ''), '-') AS performance_band_name,
    NULLIF(NULLIF(TRIM(lp.prontidao), ''), '-') AS readiness_rating,
    NULLIF(NULLIF(TRIM(lp.risco_de_perda), ''), '-') AS risk_of_loss_rating,
    NULLIF(NULLIF(TRIM(lp.potencial), ''), '-') AS potential_rating,
    NULLIF(NULLIF(TRIM(lp.criticidade), ''), '-') AS criticality_rating,
    NULLIF(NULLIF(TRIM(lp.matriz_de_desenvolvimento), ''), '-') AS development_matrix,
    lp.ts_load
FROM
    datalake_gsheets_people_raw.legacy_performance_review AS lp
