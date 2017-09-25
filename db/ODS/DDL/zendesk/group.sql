CREATE TABLE zendesk."group" (
	id varchar(30) NOT NULL,
	url varchar(100) NULL,
	"name" varchar(50) NULL,
	deleted bool NULL,
	created_at timestamp NULL,
	updated_at timestamp NULL,
	CONSTRAINT group_pkey PRIMARY KEY (id)
) ;
