select
    int(id) as id,
    timestamp(activationDate) as ts_activated_local,
    'to do' as ts_activated,
    tinyint(cityCode) as city_code,
    tinyint(countryCode) as country_code,
    number as phone_number,
    prefix as phone_number_prefix,
    suffix as phone_number_suffix,
    current_timestamp as ts_load,
    year,
    month,
    day
from datalake_teravoz_raw.ddrs
where year="{year}" and month="{month}" and day="{day}"