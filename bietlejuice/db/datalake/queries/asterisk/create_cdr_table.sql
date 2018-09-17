select
  calldate,
  clid ,
  src,
  dst,
  dcontext,
  channel,
  dstchannel,
  lastapp,
  lastdata,
  cast(duration as integer) as duration,
  cast(billsec as integer) as billsec,
  disposition,
  cast(amaflags as integer) as amaflags,
  accountcode,
  uniqueid,
  userfield,
  did,
  recordingfile,
  cnum,
  cnam,
  outbound_cnum,
  outbound_cnam,
  dst_cnam
from datalake_raw.asterisk_cdr
where date(from_iso8601_timestamp(calldate)) = date('{partition_date}')
;