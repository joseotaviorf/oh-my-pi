import mock
from mock import Mock

from bietlejuice.jobs.composer.base.db import DatabaseEnum


class TestSecretsService:
    @mock.patch("bietlejuice.jobs.composer.services.secrets_service.BaseDBUtils")
    def test_get_secret(self, mocked_basedbutils, secrets_service):
        # arrange
        secret_key = DatabaseEnum.GODFATHER
        mocked_secret_value = {"host": "www.very.secret_host.com"}

        db_utils_obj = Mock()
        db_utils_obj.secrets.get.return_value = mocked_secret_value

        mocked_base_dbutils_obj = Mock()
        mocked_base_dbutils_obj.get_dbutils.return_value = db_utils_obj
        mocked_basedbutils.return_value = mocked_base_dbutils_obj

        # act
        secrets_service.get_secret(secret_key)

        # assert
        db_utils_obj.secrets.get.assert_called_once_with("quintoandar", secret_key)
