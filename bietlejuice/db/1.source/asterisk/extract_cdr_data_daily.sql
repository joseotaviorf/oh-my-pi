DELIMITER $$
CREATE DEFINER=`root`@`localhost` PROCEDURE `extract_cdr_data_daily`()
BEGIN
SELECT
  *
FROM
  asteriskcdrdb.cdr
WHERE DATE(calldate) = CURRENT_DATE - INTERVAL '1' DAY
INTO OUTFILE '/var/tmp/cdr_dump.csv'
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n';

END
$$