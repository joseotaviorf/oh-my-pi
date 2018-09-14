select
  calldate,
  clid,
  src,
  dst,
  dcontext,
  channel,
  dstchannel,
  lastapp,
  lastdata,
  duration,
  billsec,
  disposition,
  amaflags,
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
from asteriskcdrdb.cdr
where date(calldate) = '{partition_date}'
;