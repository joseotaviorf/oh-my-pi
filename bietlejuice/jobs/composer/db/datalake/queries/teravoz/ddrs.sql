select
    int(id) as id,
    timestamp(activationDate) as ts_activated,
    from_utc_timestamp(activationDate, 'America/Sao_Paulo') as ts_activated_local,
    tinyint(cityCode) as city_code,
    tinyint(countryCode) as country_code,
    number as phone_number,
    smallint(prefix) as phone_number_prefix,
    smallint(suffix) as phone_number_suffix,
    current_timestamp as ts_load,
    smallint(year) as year,
    tinyint(month) as month,
    tinyint(day) as day
from datalake_teravoz_raw.ddrs
where year={year} and month={month} and day={day}