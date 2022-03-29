SELECT
    CAST(id_clusterizacao_ AS BIGINT) AS id_cluster,
    CAST(id_metabase_ AS BIGINT) AS id_metabase,
    CAST(id_sirena_ AS BIGINT) AS id_sirena,
    CAST(id_twilio_ AS BIGINT) AS id_twilio,
    email_ AS email,
    nomes_twillio AS twilio_name,
    nomes_sirena AS sirena_name,
    nome_metabase_ AS metabase_name,
    clusterizacao AS cluster,
    tipo_ AS type,
    time_ AS team,
    tl_ AS tl,
    time_fh AS fh_team
FROM
    datalake_gsheets_raw.de_para_analistas_proowner