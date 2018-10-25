CREATE DATABASE IF NOT EXISTS skynet
  COMMENT 'Skynet data'
  LOCATION 's3://5a-skynet/'
  WITH DBPROPERTIES ('creator'='Igor Hoelscher', 'owner'='Data Team')