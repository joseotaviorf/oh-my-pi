from bietlejuice.base.db import DatabaseEnum
from bietlejuice.validation_suites.executors.database_validation_suites_executor import (
    DatabaseValidationSuitesExecutor,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer


class PostgresValidationSuite(DatabaseValidationSuitesExecutor):
    REPOSITORY_CONSUMER_CLASS = PostgresConsumer

    def validate_big_agent(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.BIG_AGENT], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_bigfone(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.BIGFONE], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_bob(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.BOB], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_brokers_supply_processor(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.BROKERS_SUPPLY_PROCESSOR], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_chat_fup(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.CHAT_FUP], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_classified_leads(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.CLASSIFIED_LEADS], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_company(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.COMPANY], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_condominium_payments(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.CONDOMINIUM_PAYMENTS], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_demand_contact_submission(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.DEMAND_CONTACT_SUBMISSION], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_docx(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.DOCX], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_fastforward(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.FASTFORWARD], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_godfather(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.GODFATHER], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_greenseer(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.GREENSEER], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_hub_services(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.HUB_SERVICES], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_insider(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.INSIDER], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_inspections(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.INSPECTIONS], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_klefki(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.KLEFKI], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_linha_direta(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.LINHADIRETA], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_metabase(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.METABASE], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_monopoly(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.MONOPOLY], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_owner_fees(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.OWNER_FEES], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_person(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.PERSON], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_property_tax(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.PROPERTY_TAX], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_quinto_messenger(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.QUINTO_MESSENGER], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_rental_guarantee(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.RENTAL_GUARANTEE], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_rental_guarantee_platform(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.RENTAL_GUARANTEE_PLATFORM], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_repairs(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.REPAIRS], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_retsuko(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.RETSUKO], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_robin_hood(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.ROBIN_HOOD], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_sales_flow(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.SALES_FLOW], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_saruman(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.SARUMAN], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_sauron(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.SAURON], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_signatures(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.SIGNATURES], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_sorting_hat(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.SORTING_HAT], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_taskmaster(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.TASKMASTER], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_terminator(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.TERMINATOR], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_trato_feito(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.TRATO_FEITO], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_rene_descartes(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.RENE_DESCARTES], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_sap_gateway(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.SAP_GATEWAY], SparkClient()
        )
        self._validate_connection(db_consumer)
