SELECT
    CAST(id_house AS BIGINT) AS id_house,
    INT(rent) AS rent,
    INT(sugestao_preco) AS price_suggestion,
    preco_certo_asp AS right_price,
    elegibilidade AS eligibility,
    aux_alocacao AS rental_assistant,
    TO_DATE(dt_publicacao, 'yyyy-MM-dd') AS dt_publication,
    TO_DATE(data_de_distribuicao, 'yyyy-MM-dd') AS dt_distribution,
    TO_DATE(data_exp, 'yyyy-MM-dd') AS dt_expiration
FROM
    datalake_gsheets_raw.asp_relisting_opportunities_distribution
