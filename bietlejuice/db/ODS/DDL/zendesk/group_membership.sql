CREATE TABLE zendesk.group_membership (
	id varchar(30) NOT NULL,
	url varchar(100) NULL,
	user_id varchar(30) NOT NULL,
	group_id varchar(30) NOT NULL,
	"default" bool NULL,
	created_at timestamp NULL,
	updated_at timestamp NULL,
	CONSTRAINT group_membership_pkey PRIMARY KEY (id)
) ;