select *
  from datalake_amplitude_raw_prod.events
where dt = '{dt_partition}'
;
