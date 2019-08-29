select
    boolean(active) as is_active,
    tinyint(areaCode) as area_code,
    email,
    fullName as name,
    number as internal_phone_number,
    current_timestamp as ts_load
from
    datalake_teravoz_raw.peers;