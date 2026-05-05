from unittest import mock

import pytest

from bietlejuice.base.sst.domains.sfmc.raw import schema as schema_module


class TestGetDataExtensionSchema:
    @mock.patch.object(schema_module, "requests")
    def test_parses_and_sorts_fields_by_ordinal(self, mock_requests):
        # arrange
        success_xml = """<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:api="http://exacttarget.com/wsdl/partnerAPI">
    <soapenv:Body>
        <api:RetrieveResponseMsg>
            <api:Results>
                <api:Name>field_b</api:Name>
                <api:FieldType>Text</api:FieldType>
                <api:Ordinal>2</api:Ordinal>
            </api:Results>
            <api:Results>
                <api:Name>field_a</api:Name>
                <api:FieldType>Number</api:FieldType>
                <api:Ordinal>1</api:Ordinal>
            </api:Results>
        </api:RetrieveResponseMsg>
    </soapenv:Body>
</soapenv:Envelope>"""
        mock_response = mock.MagicMock()
        mock_response.text = success_xml
        mock_requests.post.return_value = mock_response

        # act
        result = schema_module.get_data_extension_schema(
            soap_url="https://soap.example.com",
            access_token="TOKEN",
            customer_key="EXT_KEY",
        )

        # assert
        assert [field["field_name"] for field in result] == ["field_a", "field_b"]
        assert result[0]["field_type"] == "Number"

    @mock.patch.object(schema_module, "requests")
    def test_raises_on_soap_fault(self, mock_requests):
        # arrange
        fault_xml = """<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
    <soapenv:Body>
        <soapenv:Fault>
            <faultstring>Bad request</faultstring>
        </soapenv:Fault>
    </soapenv:Body>
</soapenv:Envelope>"""
        mock_response = mock.MagicMock()
        mock_response.text = fault_xml
        mock_requests.post.return_value = mock_response

        # act / assert
        with pytest.raises(ValueError) as exc_info:
            schema_module.get_data_extension_schema(
                soap_url="https://soap.example.com",
                access_token="TOKEN",
                customer_key="EXT_KEY",
            )

        assert "SOAP fault" in str(exc_info.value)

    @mock.patch.object(schema_module, "requests")
    def test_raises_on_empty_results(self, mock_requests):
        # arrange
        empty_xml = """<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:api="http://exacttarget.com/wsdl/partnerAPI">
    <soapenv:Body>
        <api:RetrieveResponseMsg />
    </soapenv:Body>
</soapenv:Envelope>"""
        mock_response = mock.MagicMock()
        mock_response.text = empty_xml
        mock_requests.post.return_value = mock_response

        # act / assert
        with pytest.raises(ValueError) as exc_info:
            schema_module.get_data_extension_schema(
                soap_url="https://soap.example.com",
                access_token="TOKEN",
                customer_key="EXT_KEY",
            )

        assert "No DataExtensionField metadata returned" in str(exc_info.value)


class TestBuildSchemaColumns:
    def test_raises_on_duplicated_names(self):
        # arrange
        schema_fields = [
            {"field_name": "ContactID", "field_type": "Text"},
            {"field_name": "ContactID", "field_type": "Number"},
        ]

        # act / assert
        with pytest.raises(ValueError) as exc_info:
            schema_module.build_schema_columns(schema_fields)

        assert "Duplicated column name" in str(exc_info.value)

    def test_builds_mapping_preserving_original_names(self):
        # arrange
        schema_fields = [
            {"field_name": "UserName", "field_type": "Text"},
            {"field_name": "Amount", "field_type": "Number"},
        ]

        # act
        result = schema_module.build_schema_columns(schema_fields)

        # assert
        assert result == {"UserName": "Text", "Amount": "Number"}

    def test_skips_fields_with_empty_names(self):
        # arrange
        schema_fields = [
            {"field_name": "", "field_type": "Text"},
            {"field_name": "Amount", "field_type": "Number"},
        ]

        # act
        result = schema_module.build_schema_columns(schema_fields)

        # assert
        assert result == {"Amount": "Number"}


class TestFindSchemaAliasColumn:
    def test_maps_compact_id_alias(self):
        # arrange / act
        alias = schema_module._find_schema_alias_column(
            normalized_columns=["contactid", "external_key"],
            schema_column="id_contact",
        )

        # assert
        assert alias == "contactid"

    def test_returns_empty_on_ambiguous_alias(self):
        # arrange / act
        alias = schema_module._find_schema_alias_column(
            normalized_columns=["contactid", "contact_id"],
            schema_column="id_contact",
        )

        # assert
        assert alias == ""


class TestCastByFieldType:
    @pytest.mark.parametrize("field_type", ["Number", "Decimal"])
    def test_number_casts_to_double(self, field_type):
        # arrange
        df = mock.MagicMock()
        df.withColumn.return_value = "new_df"
        col_expr = mock.MagicMock()
        col_expr.cast.return_value = mock.MagicMock(name="double_expr")

        with mock.patch.object(schema_module, "F") as mock_f:
            mock_f.col.return_value = col_expr

            # act
            result = schema_module._cast_by_sfmc_field_type(df, "id_user", field_type)

        # assert
        assert result == "new_df"
        df.withColumn.assert_called_once()

    def test_boolean_casts_to_boolean(self):
        # arrange
        df = mock.MagicMock()
        df.withColumn.return_value = "new_df"
        col_expr = mock.MagicMock()
        col_expr.cast.return_value = mock.MagicMock(name="bool_expr")

        with mock.patch.object(schema_module, "F") as mock_f:
            mock_f.col.return_value = col_expr

            # act
            result = schema_module._cast_by_sfmc_field_type(df, "is_signed", "Boolean")

        # assert
        assert result == "new_df"
        df.withColumn.assert_called_once()

    def test_returns_original_df_for_unhandled_type(self):
        # arrange
        df = mock.MagicMock()

        # act
        result = schema_module._cast_by_sfmc_field_type(df, "user_name", "Text")

        # assert
        assert result is df
        df.withColumn.assert_not_called()


class TestCastDatetimeColumnWithValidation:
    def test_uses_timestamp_parser(self):
        # arrange
        df = mock.MagicMock()
        df.withColumn.return_value = df
        df.where.return_value.count.return_value = 0
        df.drop.return_value = "new_df"

        with mock.patch.object(schema_module, "F") as mock_f, mock.patch.object(
            schema_module, "_parse_sfmc_timestamp"
        ) as mock_parse:
            col_expr = mock.MagicMock()
            col_expr.cast.return_value = col_expr
            col_expr.isNotNull.return_value = mock.MagicMock()
            col_expr.isNotNull.return_value.__and__ = mock.MagicMock(
                return_value=mock.MagicMock()
            )
            col_expr.isNull.return_value = mock.MagicMock()
            mock_f.col.return_value = col_expr
            mock_f.length.return_value = mock.MagicMock()
            mock_f.length.return_value.__gt__ = mock.MagicMock(
                return_value=mock.MagicMock()
            )
            mock_f.trim.return_value = mock.MagicMock()
            mock_parse.return_value = mock.MagicMock(name="parsed_ts")

            # act
            result = schema_module._cast_datetime_column_with_validation(df, "ts_sent")

        # assert
        assert result == "new_df"
        mock_parse.assert_called_once()
        assert df.withColumn.call_count == 2
