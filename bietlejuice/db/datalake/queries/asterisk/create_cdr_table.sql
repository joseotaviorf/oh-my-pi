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
  duration as duration,
  billsec as billsec,
  disposition,
  amaflags as amaflags,
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