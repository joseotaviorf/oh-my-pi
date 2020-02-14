-- Some fields are JSON strings. We're using REGEX because it's not possible to use get_json_object because of the special characters.

select
    regexp_extract(_id, '(\\w+\\d+)', 0) as _id,    -- format: {"$oid": "5b9ffb4da939ee6a2c873276"}
    house_id as id_house,
    user_id as id_user,
    cast(regexp_extract(visit_date, '(\\d{4}-\\d{2}-\\d{2}\\w{1}\\d{2}:\\d{2}:\\d{2})', 0) as timestamp) as ts_visited  -- format {"$date": "2019-05-01T10:00:00Z" }
from
    datalake_cidade_alerta_raw.scheduling