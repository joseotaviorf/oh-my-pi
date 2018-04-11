CREATE TABLE files.de_para_cancelamento (
	reason varchar(364) NULL,
	reason_category varchar(6) NULL,
	count int8 NULL,
	"new reason" varchar(100) NULL,
	responsible varchar(100) NULL
)
WITH (
	OIDS=FALSE
) ;