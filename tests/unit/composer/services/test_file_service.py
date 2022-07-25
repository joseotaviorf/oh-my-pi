from unittest import mock

from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services.file_service import FileService

MOCK_DATALAKE_METADATA_PATH = (
    "/home/user/bi-etl-ejuice/jobs/composer/base/db/../../db/datalake/metadata"
)


class TestFileService:
    @mock.patch(
        "bietlejuice.jobs.composer.services.file_service.DATALAKE_METADATA_PATH",
        MOCK_DATALAKE_METADATA_PATH,
    )
    @mock.patch("bietlejuice.jobs.composer.services.file_service.glob")
    def test_metadata_file_exists(self, mocked_glob):
        # arrange
        mocked_glob.glob.return_value = [
            f"{MOCK_DATALAKE_METADATA_PATH}/example/clean/example_table.yaml"
        ]

        # act
        exists = FileService.metadata_file_exists(
            "example", LayerEnum.CLEAN.value, "example_table"
        )

        # assert
        assert exists

    @mock.patch(
        "bietlejuice.jobs.composer.services.file_service.DATALAKE_METADATA_PATH",
        MOCK_DATALAKE_METADATA_PATH,
    )
    @mock.patch("bietlejuice.jobs.composer.services.file_service.glob")
    def test_metadata_file_does_not_exists(self, mocked_glob):
        # arrange
        mocked_glob.glob.return_value = []

        # act
        exists = FileService.metadata_file_exists(
            "example", LayerEnum.CLEAN.value, "non_existing_example_table"
        )

        # assert
        assert not exists

    @mock.patch(
        "bietlejuice.jobs.composer.services.file_service.DATALAKE_METADATA_PATH",
        MOCK_DATALAKE_METADATA_PATH,
    )
    @mock.patch("bietlejuice.jobs.composer.services.file_service.glob")
    def test_metadata_folder_exists(self, mocked_glob):
        # arrange
        mocked_glob.glob.return_value = [
            f"{MOCK_DATALAKE_METADATA_PATH}/example/clean/"
        ]

        # act
        exists = FileService.metadata_file_exists(
            "example", LayerEnum.CLEAN.value, None, True
        )

        # assert
        assert exists

    @mock.patch(
        "bietlejuice.jobs.composer.services.file_service.DATALAKE_METADATA_PATH",
        MOCK_DATALAKE_METADATA_PATH,
    )
    @mock.patch("bietlejuice.jobs.composer.services.file_service.glob")
    def test_metadata_folder_does_not_exists(self, mocked_glob):
        # arrange
        mocked_glob.glob.return_value = []

        # act
        exists = FileService.metadata_file_exists(
            "example", LayerEnum.CLEAN.value, None, True
        )

        # assert
        assert not exists
