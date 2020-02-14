-- Some fields are JSON strings. We're using REGEX because it's not possible to use get_json_object because of the special characters.

select
    regexp_extract(_id, '(\\w+\\d+)', 1) as _id,    -- format: {"$oid": "5b9ffb4da939ee6a2c873276"}
    field,
    rank
from
    datalake_cidade_alerta_raw.highlights
