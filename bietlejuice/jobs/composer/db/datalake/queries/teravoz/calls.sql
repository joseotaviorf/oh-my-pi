select
      timestamp(call_date) as ts_created,
      call_id as id,
      called_number as number,
      extension as extension_phone_number, 
      number_type, 
      round(float(price), 2) as price,
      source,
      status,
      smallint(talk_time) as seconds_talk_time,
      type,
      smallint(year) as year,
      tinyint(month) as month,
      tinyint(day) as day
  from
      datalake_teravoz_raw.calls
  where
      year={} and month={} and day={}