SELECT
	id AS id_notifications_sent,
	contract_id AS id_contract,
	property_id AS id_property,
	msg_type,
	recipient,
	channel,
	remaining_days,
	created_at AS ts_created,
    year,
    month,
    day
FROM
	datalake_klefki_test_raw.notifications_sent
