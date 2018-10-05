select *
  from datalake_raw.amplitude_events
where dt = '{dt_partition}'
;
