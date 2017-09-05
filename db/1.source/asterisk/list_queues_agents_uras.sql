DELIMITER $$
CREATE DEFINER=`root`@`localhost` PROCEDURE `list_queues_agents_uras`()
BEGIN
SELECT
    qd.id AS queue_id,
    qc.descr AS queue_name,
    substring_index(substring_index(qd.data, '@', 1), '/', -1) AS agent_extension,
    u.name AS agent_name,
    ie.ivr_id AS ura_id,
    ie.selection AS ura_option,
    id.name AS ura_name,
    concat('ivr-',id.id) AS ura_code,
    now() AS dt_created,
    now() AS dt_updated
FROM
    queues_details qd
LEFT JOIN
    queues_config qc
    ON qd.id = qc.extension
LEFT JOIN
    users u
    ON u.extension = substring_index(substring_index(qd.data, '@', 1), '/', -1)
LEFT JOIN
    (
        SELECT
        ivr_id,
        selection,
        substring_index(substring_index(dest, ",",2),",",-1) AS type
        FROM ivr_entries
        WHERE substring_index(dest,"-",1)<>'ivr'
    ) ie
    ON ie.type = qd.id
LEFT JOIN
    ivr_details id
    ON id.id = ie.ivr_id
WHERE qd.keyword='member'
INTO OUTFILE '/var/tmp/results.csv'
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n';

END
$$