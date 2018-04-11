CREATE TABLE zendesk.ticket_fields (
	id varchar(30) NOT NULL,
	ticket_id varchar(30) NOT NULL,
	value varchar NULL,
	CONSTRAINT ticket_fields_pkey PRIMARY KEY (id,ticket_id)
) ;
