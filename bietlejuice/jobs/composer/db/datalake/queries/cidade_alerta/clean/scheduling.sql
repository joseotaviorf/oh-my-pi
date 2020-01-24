SELECT
    _id, 
    house_id as id_house,
    user_id as id_user,
    timestamp(visit_date) as ts_visited_date
FROM
    datalake_cidade_alerta_raw.scheduling