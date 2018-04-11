CREATE TABLE "condition" (
  "id" bigint NOT NULL,
  "atualizadoEm" timestamp DEFAULT NULL,
  "criadoEm" timestamp DEFAULT NULL,
  "concordado" smallint NOT NULL,
  "descricao" text,
  "titulo" varchar(128) DEFAULT NULL,
  PRIMARY KEY ("id")
) 