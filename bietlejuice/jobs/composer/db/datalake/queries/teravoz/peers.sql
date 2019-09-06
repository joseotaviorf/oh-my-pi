select
    boolean(active) as is_active,
    tinyint(areaCode) as area_code,
    email,
    fullName as name,
    int(number) as internal_phone_number,
    current_timestamp as ts_load,
    smallint(year) as year,
    tinyint(month) as month,
    tinyint(day) as day
from
    datalake_teravoz_raw.peers
where
    year="{year}" and month="{month}" and day="{day}"