SELECT
    CAST(sk_house AS BIGINT) AS id_house,
    DOUBLE(score) AS score,
    aux_alocacao AS rental_assistant,
    TO_DATE(dt_first_publication, 'yyyy-MM-dd') AS dt_first_publication,
    TO_DATE(data_de_distribuicao, 'yyyy-MM-dd') AS dt_distribution,
    TO_DATE(data_exp, 'yyyy-MM-dd') AS dt_expiration
FROM
    datalake_gsheets_raw.asp_for_sale_alocated
