-- Some fields are JSON strings. We're using REGEX because it's not possible to use get_json_object because of the special characters.

select
<<<<<<< HEAD
    regexp_extract(_id, '(\\w+\\d+)', 1) as _id,    -- format: {"$oid": "5b9ffb4da939ee6a2c873276"}
=======
   --format {"$oid": "59ae91c3a2da08fe49894707"}
    regexp_extract(_id, '(\\w+\\d+)', 1) as _id, 
>>>>>>> 272222dab5d67d0b4243f4d74a7948dec48bbfcf
    field,
    rank
from
    datalake_cidade_alerta_raw.highlights
