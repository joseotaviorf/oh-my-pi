import mock
import pytest
import requests
from requests import Request


class TestGithubService(object):

    @mock.patch.object(requests, 'post')
    def test_get_json_response(self, mock_requests_post, github_service):
        # arrange
        def __json():
            return {
                'data': {
                    'repositoryOwner': {
                        'repository': mock.ANY
                    }
                }
            }

        repo_name = 'repo_name'
        mock_requests_post.return_value = Request(json=__json)

        # act
        result = github_service.get_json_response(repo_name)

        # assert
        assert result is not None

    @mock.patch.object(requests, 'post')
    def test_get_json_response_with_repository_none(self, mock_requests_post, github_service):
        # arrange
        def __json():
            return {
                'data': {
                    'repositoryOwner': {
                        'repository': None
                    }
                }
            }

        repo_name = 'repo_name'
        mock_requests_post.return_value = Request(json=__json)

        # act & assert
        with pytest.raises(Exception):
            github_service.get_json_response(repo_name)

    def test_extract_pull_requests_with_empty_edges(self, github_service):
        # arrange
        json_response = {
            'data': {
                'repositoryOwner': {
                    'repository': {
                        'pullRequests': {
                            'edges': []
                        }
                    }
                }
            }
        }

        # act
        open_prs, approved_prs = github_service.extract_pull_requests(json_response=json_response)

        # assert
        assert len(open_prs) == len(approved_prs) == 0

    @pytest.mark.parametrize('review_edges, approved_prs_length',
                             [[[], 0],
                              [[{'node': {'state': 'COMMENT'}}], 0],
                              [[{'node': {'state': 'CHANGES_REQUESTED'}}], 1]])
    def test_extract_pull_requests_with_no_approved_prs(self, github_service, review_edges, approved_prs_length):
        # arrange
        json_response = {
            'data': {
                'repositoryOwner': {
                    'repository': {
                        'pullRequests': {
                            'edges': [{
                                'node': {
                                    'title': 'title',
                                    'author': {
                                        'login': 'login'
                                    },
                                    'url': 'url',
                                    'reviews': {
                                        'edges': review_edges
                                    }
                                }
                            }]
                        }
                    }
                }
            }
        }

        # act
        open_prs, approved_prs = github_service.extract_pull_requests(json_response=json_response)

        # assert
        assert len(open_prs) > 0
        assert len(approved_prs) == approved_prs_length

    def test_extract_pull_requests_with_approved_prs(self, github_service):
        # arrange
        json_response = {
            'data': {
                'repositoryOwner': {
                    'repository': {
                        'pullRequests': {
                            'edges': [{
                                'node': {
                                    'title': mock.ANY,
                                    'author': {
                                        'login': mock.ANY
                                    },
                                    'url': mock.ANY,
                                    'reviews': {
                                        'edges': [{
                                            'node': {
                                                'state': 'APPROVED'
                                            }
                                        }]
                                    }
                                }
                            }]
                        }
                    }
                }
            }
        }

        # act
        open_prs, approved_prs = github_service.extract_pull_requests(json_response=json_response)

        # assert
        assert len(open_prs) == 0
        assert len(approved_prs) > 0
