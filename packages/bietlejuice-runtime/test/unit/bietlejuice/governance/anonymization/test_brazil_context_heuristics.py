import pytest

from bietlejuice.governance.anonymization.brazil_context_heuristics import (
    apply_context_heuristics_to_cleaned_results,
    is_identifier_column,
    is_location_column,
    is_person_name_column,
    should_keep_person_or_location,
)


class TestPersonContext:
    def test_deal_name_is_business_context(self):
        # act
        keep = should_keep_person_or_location("PERSON", "deal_name", "Acme")

        # assert
        assert keep is False

    @pytest.mark.parametrize(
        "column_name",
        [
            "name",
            "nome",
            "full_name",
            "nome_completo",
            "user_name",
            "nome_cliente",
            "customer_full_name",
            "nome_proprietario",
            "tenant_name",
            "nome_do_fiador",
        ],
    )
    def test_person_name_columns_keep_person(self, column_name):
        # act
        name_column = is_person_name_column(column_name)
        keep = should_keep_person_or_location("PERSON", column_name, "Joao Silva")

        # assert
        assert name_column is True
        assert keep is True

    @pytest.mark.parametrize(
        "column_name",
        [
            "deal_name",
            "company_name",
            "tickets_subject",
            "deal_title",
            "deal_description",
        ],
    )
    def test_business_columns_demote_person(self, column_name):
        # act
        keep = should_keep_person_or_location("PERSON", column_name, "Joao Silva")

        # assert
        assert keep is False

    def test_unknown_column_defaults_to_keep_person(self):
        # act
        keep = should_keep_person_or_location("PERSON", "product_name", "Joao Silva")

        # assert
        assert keep is True

    def test_person_name_column_wins_over_identifier(self):
        # act
        keep = should_keep_person_or_location("PERSON", "user_name", "Joao Silva")

        # assert
        assert keep is True

    @pytest.mark.parametrize("column_name", ["city", "cidade", "street", "endereco"])
    def test_geo_column_demotes_person(self, column_name):
        # act
        keep = should_keep_person_or_location("PERSON", column_name, "Sao Paulo")

        # assert
        assert keep is False

    @pytest.mark.parametrize(
        "entity_type,column_name",
        [
            ("PERSON", "ts_last_modified"),
            ("PERSON", "dt_completion"),
            ("PERSON", "advertiser_date_ocr"),
            ("PERSON", "created_at"),
            ("LOCATION", "ts_last_modified"),
            ("LOCATION", "updated_at"),
        ],
    )
    def test_temporal_columns_demote_person_or_location(self, entity_type, column_name):
        # act
        keep = should_keep_person_or_location(entity_type, column_name, "Joao Silva")

        # assert
        assert keep is False

    @pytest.mark.parametrize(
        "column_name",
        ["ticket_number", "transaction_id", "card_number", "protocol_number"],
    )
    def test_ticket_number_columns_demote_person(self, column_name):
        # act
        identifier = is_identifier_column(column_name)
        keep = should_keep_person_or_location("PERSON", column_name, "Joao Silva")

        # assert
        assert identifier is True
        assert keep is False

    def test_analytics_columns_demote_person(self):
        # act / assert
        assert not should_keep_person_or_location("PERSON", "up_utm_source", "google")
        assert not should_keep_person_or_location(
            "PERSON", "search_query", "apartamento"
        )
        assert not should_keep_person_or_location("PERSON", "pod_name", "worker-1")

    @pytest.mark.parametrize(
        "column_name",
        ["personUUID", "person_uuid", "uuid_external_person", "externalUuid"],
    )
    def test_uuid_columns_demote_person(self, column_name):
        # act
        identifier = is_identifier_column(column_name)
        keep_uuid = should_keep_person_or_location(
            "PERSON", column_name, "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
        )
        keep_sf_id = should_keep_person_or_location(
            "PERSON", column_name, "005bL00000JNWCLQA5"
        )

        # assert
        assert identifier is True
        assert keep_uuid is False
        assert keep_sf_id is False


class TestLocationContext:
    @pytest.mark.parametrize(
        "column_name",
        [
            "condominio_name",
            "nome_condominio",
            "endereco",
            "logradouro",
            "city",
            "cidade",
            "cep",
            "bairro",
            "address_complement",
        ],
    )
    def test_location_columns_keep_location(self, column_name):
        # act
        location_column = is_location_column(column_name)
        keep = should_keep_person_or_location(
            "LOCATION", column_name, "Rua das Flores, 100"
        )

        # assert
        assert location_column is True
        assert keep is True

    def test_total_condominio_demotes_location(self):
        # act
        location_column = is_location_column("total_condominio")
        keep = should_keep_person_or_location("LOCATION", "total_condominio", "1500")

        # assert
        assert location_column is False
        assert keep is False


class TestActorFkColumns:
    """Actor FK columns (*_by) must demote PERSON/LOCATION like datetime heuristics."""

    @pytest.mark.parametrize(
        "column_name",
        [
            "created_by",
            "updated_by",
            "last_modified_by",
            "signed_by",
            "id_created_by",
            "id_last_modified_by",
        ],
    )
    def test_actor_fk_columns_are_identifiers(self, column_name):
        # act
        identifier = is_identifier_column(column_name)

        # assert
        assert identifier is True

    @pytest.mark.parametrize(
        "entity_type,column_name,value",
        [
            ("PERSON", "created_by", "Joao Silva"),
            ("PERSON", "id_last_modified_by", "005bL00000JNWCLQA5"),
            ("LOCATION", "updated_by", "Sao Paulo"),
        ],
    )
    def test_actor_fk_columns_demote_person_or_location(
        self, entity_type, column_name, value
    ):
        # act
        keep = should_keep_person_or_location(entity_type, column_name, value)

        # assert
        assert keep is False

    def test_apply_context_demotes_person_on_created_by(self):
        # arrange
        chunk = [{"type": "PERSON", "score": 0.9, "matched_value": "Maria Santos"}]

        # act
        result = apply_context_heuristics_to_cleaned_results(chunk, "created_by")

        # assert
        assert result[0]["type"] == "NOT_FOUND"


class TestIdentifierColumns:
    @pytest.mark.parametrize(
        "column_name",
        [
            "id_application",
            "id_amplitude",
            "application_id",
            "uuid",
            "deal_id",
            "external_id",
            "id",
            "session_key",
            "protocol_number",
        ],
    )
    def test_identifier_columns_demote_person(self, column_name):
        # act
        identifier = is_identifier_column(column_name)
        keep = should_keep_person_or_location("PERSON", column_name, "ABC123")

        # assert
        assert identifier is True
        assert keep is False

    def test_identifier_columns_demote_location(self):
        # act
        keep = should_keep_person_or_location("LOCATION", "id_application", "ABC123")

        # assert
        assert keep is False
