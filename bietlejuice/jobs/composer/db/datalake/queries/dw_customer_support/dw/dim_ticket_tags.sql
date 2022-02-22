SELECT DISTINCT
  MD5(tags) AS sk_tags,
  SUBSTRING(tags, 1, 2800) AS tags
FROM
  datalake_customer_support.email
UNION
SELECT DISTINCT
  MD5(tags) AS sk_tags,
  SUBSTRING(tags, 1, 2800) AS tags
FROM
  datalake_customer_support.call
UNION
SELECT DISTINCT
  MD5(tags) AS sk_tags,
  SUBSTRING(tags, 1, 2800) AS tags
FROM
  datalake_customer_support.chat