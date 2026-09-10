import base64
from unittest import mock

import pytest

from bietlejuice.base.sst.domains.sfmc.raw import api


class TestSfmcApiCredentials:
    def test_derive_soap_url_from_rest_url(self):
        soap_url = api.derive_soap_url(
            rest_url="https://subdomain.rest.marketingcloudapis.com",
            auth_url="",
        )

        assert soap_url == "https://subdomain.soap.marketingcloudapis.com"

    def test_derive_soap_url_from_auth_url(self):
        soap_url = api.derive_soap_url(
            rest_url="",
            auth_url="https://subdomain.auth.marketingcloudapis.com",
        )

        assert soap_url == "https://subdomain.soap.marketingcloudapis.com"

    def test_derive_soap_url_raises_for_unknown_host_pattern(self):
        with pytest.raises(ValueError) as exc_info:
            api.derive_soap_url(
                rest_url="https://example.com",
                auth_url="https://example.org",
            )

        assert "Could not derive SFMC soap_url" in str(exc_info.value)

    @mock.patch.object(api, "BaseDBUtils")
    def test_get_api_credentials_raises_when_dbutils_is_missing(
        self, mock_base_dbutils
    ):
        mock_base_dbutils.return_value.get_dbutils.return_value = None

        with pytest.raises(ValueError) as exc_info:
            api.get_api_credentials()

        assert "dbutils is not available" in str(exc_info.value)

    @mock.patch.object(api, "BaseDBUtils")
    def test_get_api_credentials_raises_when_secret_is_not_dict(
        self, mock_base_dbutils
    ):
        dbutils = mock.MagicMock()
        dbutils.secrets.get.return_value = "[]"
        mock_base_dbutils.return_value.get_dbutils.return_value = dbutils

        with pytest.raises(ValueError) as exc_info:
            api.get_api_credentials()

        assert "Expected JSON object" in str(exc_info.value)

    @mock.patch.object(api, "BaseDBUtils")
    def test_get_api_credentials_success(self, mock_base_dbutils):
        dbutils = mock.MagicMock()
        dbutils.secrets.get.return_value = (
            '{"client_id":" a ","client_secret":" b ","auth_url":" c ",'
            '"rest_url":" d ","soap_url":" e "}'
        )
        mock_base_dbutils.return_value.get_dbutils.return_value = dbutils

        credentials = api.get_api_credentials()

        assert credentials == {
            "client_id": "a",
            "client_secret": "b",
            "auth_url": "c",
            "rest_url": "d",
            "soap_url": "e",
        }

    @mock.patch.object(api, "BaseDBUtils")
    def test_get_api_credentials_decodes_base64_json(self, mock_base_dbutils):
        plaintext = (
            '{"client_id":"a","client_secret":"b","auth_url":"c",'
            '"rest_url":"d","soap_url":"e"}'
        )
        dbutils = mock.MagicMock()
        dbutils.secrets.get.return_value = base64.b64encode(
            plaintext.encode("utf-8")
        ).decode("ascii")
        mock_base_dbutils.return_value.get_dbutils.return_value = dbutils

        credentials = api.get_api_credentials()

        assert credentials["client_id"] == "a"
        assert credentials["client_secret"] == "b"

    @mock.patch.object(api, "BaseDBUtils")
    def test_get_api_credentials_raises_when_secret_is_empty(self, mock_base_dbutils):
        dbutils = mock.MagicMock()
        dbutils.secrets.get.return_value = "   "
        mock_base_dbutils.return_value.get_dbutils.return_value = dbutils

        with pytest.raises(ValueError) as exc_info:
            api.get_api_credentials()

        assert "secret is empty" in str(exc_info.value)

    @mock.patch.object(api, "get_api_credentials")
    def test_resolve_api_credentials_uses_derived_soap_url(
        self, mock_get_api_credentials
    ):
        mock_get_api_credentials.return_value = {
            "client_id": "client",
            "client_secret": "secret",
            "auth_url": "https://subdomain.auth.marketingcloudapis.com",
            "rest_url": "https://subdomain.rest.marketingcloudapis.com",
            "soap_url": "",
        }

        credentials = api.resolve_api_credentials(require_soap_url=True)

        assert (
            credentials["soap_url"] == "https://subdomain.soap.marketingcloudapis.com"
        )

    @pytest.mark.parametrize(
        "credentials, kwargs, expected_message",
        [
            (
                {
                    "client_id": "",
                    "client_secret": "secret",
                    "auth_url": "https://auth.example.com",
                    "rest_url": "https://rest.example.com",
                    "soap_url": "https://soap.example.com",
                },
                {},
                "client_id and client_secret",
            ),
            (
                {
                    "client_id": "client",
                    "client_secret": "secret",
                    "auth_url": "",
                    "rest_url": "https://rest.example.com",
                    "soap_url": "https://soap.example.com",
                },
                {},
                "must include auth_url",
            ),
            (
                {
                    "client_id": "client",
                    "client_secret": "secret",
                    "auth_url": "https://auth.example.com",
                    "rest_url": "",
                    "soap_url": "",
                },
                {"require_rest_url": True},
                "must include rest_url",
            ),
            (
                {
                    "client_id": "client",
                    "client_secret": "secret",
                    "auth_url": "https://auth.example.com",
                    "rest_url": "",
                    "soap_url": "",
                },
                {"require_soap_url": True},
                "Could not derive SFMC soap_url",
            ),
        ],
    )
    @mock.patch.object(api, "get_api_credentials")
    def test_resolve_api_credentials_validation_errors(
        self,
        mock_get_api_credentials,
        credentials,
        kwargs,
        expected_message,
    ):
        mock_get_api_credentials.return_value = credentials

        with pytest.raises(ValueError) as exc_info:
            api.resolve_api_credentials(**kwargs)

        assert expected_message in str(exc_info.value)


class TestSfmcApiToken:
    @mock.patch.object(api, "requests")
    def test_get_access_token_success(self, mock_requests):
        mock_response = mock.MagicMock()
        mock_response.json.return_value = {"access_token": "TOKEN"}
        mock_requests.post.return_value = mock_response

        token = api.get_access_token(
            auth_url="https://auth.example.com",
            client_id="client",
            client_secret="secret",
        )

        assert token == "TOKEN"
        mock_requests.post.assert_called_once()

    @mock.patch.object(api, "requests")
    def test_get_access_token_raises_when_missing_token(self, mock_requests):
        mock_response = mock.MagicMock()
        mock_response.json.return_value = {}
        mock_requests.post.return_value = mock_response

        with pytest.raises(ValueError) as exc_info:
            api.get_access_token(
                auth_url="https://auth.example.com",
                client_id="client",
                client_secret="secret",
            )

        assert "access token not found" in str(exc_info.value)


class TestSfmcApiFetchObjectRows:
    @pytest.mark.parametrize(
        "response_json, expected_rows",
        [
            ([{"id_user": 1}], [{"id_user": 1}]),
            ({"items": [{"id_user": 2}]}, [{"id_user": 2}]),
            ({"rowset": [{"id_user": 3}]}, [{"id_user": 3}]),
        ],
    )
    @mock.patch.object(api, "requests")
    def test_fetch_object_rows_supports_response_shapes(
        self,
        mock_requests,
        response_json,
        expected_rows,
    ):
        # arrange
        response = mock.MagicMock()
        response.json.return_value = response_json
        mock_requests.get.return_value = response

        # act
        rows = api.fetch_object_rows(
            rest_url="https://rest.example.com",
            access_token="TOKEN",
            external_key="EXT_KEY",
            page_size=2500,
        )

        # assert
        assert rows == expected_rows

    @mock.patch.object(api, "requests")
    def test_fetch_object_rows_handles_pagination(self, mock_requests):
        # arrange
        first_response = mock.MagicMock()
        first_response.json.return_value = {"items": [{"id_user": 1}, {"id_user": 2}]}
        second_response = mock.MagicMock()
        second_response.json.return_value = {"items": [{"id_user": 3}]}
        mock_requests.get.side_effect = [first_response, second_response]

        # act
        rows = api.fetch_object_rows(
            rest_url="https://rest.example.com",
            access_token="TOKEN",
            external_key="EXT_KEY",
            page_size=2,
        )

        # assert
        assert rows == [{"id_user": 1}, {"id_user": 2}, {"id_user": 3}]
        assert mock_requests.get.call_count == 2

    @mock.patch.object(api, "requests")
    def test_fetch_object_rows_returns_empty_for_unknown_shape(self, mock_requests):
        # arrange
        response = mock.MagicMock()
        response.json.return_value = {"unexpected": "shape"}
        mock_requests.get.return_value = response

        # act
        rows = api.fetch_object_rows(
            rest_url="https://rest.example.com",
            access_token="TOKEN",
            external_key="EXT_KEY",
        )

        # assert
        assert rows == []
