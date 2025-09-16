# API Base Framework: Usage and Extension Guide

## 1. Purpose

This framework was created to solve common challenges faced when developing data ingestion pipelines from REST APIs, such as:

-   **Code Duplication**: Authentication, pagination, and error-handling logic was rewritten for each new DAG.
-   **Inconsistency**: Each pipeline implemented its own strategies, making maintenance difficult.
-   **Lack of Robustness**: Critical logic like rate limiting and retries was often overlooked.

The goal of this set of base classes is to **standardize, accelerate, and improve the reliability** of developing new API-based data ingestions.

---

## 2. Framework Architecture

The framework is composed of reusable modules located in `bietlejuice/base/api/`. The main components are:

-   **`BaseAPIClient`**: The core client that manages the `requests` session, timeouts, and standardized handling of HTTP errors.
-   **`Authentication`**: A module to encapsulate different authentication strategies (e.g., OAuth2, API Key).
-   **`Pagination`**: A module to handle various pagination types (e.g., via `Link` header, `offset`/`limit`).
-   **`Rate Limiting`**: An adapter for the `requests` session that proactively and reactively manages API request limits.

---

## 3. Tutorial: Integrating a New API

This guide outlines the process for using and extending the framework to integrate a new API.

### Step 1: Create a Dedicated API Client
For each new API, create a dedicated client class that inherits from `BaseAPIClient`. This class will be responsible for holding API-specific configurations, such as the base URL, and for orchestrating the authentication and data fetching methods.

### Step 2: Implement Authentication
Determine the authentication method required by the new API.

First, check the existing handlers in `bietlejuice/base/api/auth/`. If a suitable handler already exists (e.g., `BasicAuthOAuth2ClientCredentials`), instantiate and apply it within your new API client.

If the API uses a new authentication strategy, create a new class that inherits from `AuthBase` and implement the `apply_auth` method to modify the `requests.Session` accordingly.

### Step 3: Implement Pagination
Identify the pagination strategy used by the API endpoint.

Check the existing paginators in `bietlejuice/base/api/pagination/`. If a paginator matches the API's strategy (e.g., `HeaderLinkPaginator`), instantiate it within your client's data-fetching methods.

If a new strategy is needed (e.g., cursor-based or offset/limit), create a new class that inherits from `BasePaginator` and implement the `fetch_all` generator method to yield pages of data.

### Step 4: Use the Client in a Spark Job
In your Spark ingestion job, import and instantiate your new API client. Use its methods to fetch the complete, paginated dataset. The data can then be passed to standard Spark functions for processing and loading into the raw layer.

---

## 4. Best Practices

-   **Reuse Before You Create**: Always check if an existing authentication or pagination class already solves your problem.
-   **Add Tests**: If you create a new base class (e.g., a new `Paginator` or `AuthBase` subclass), add corresponding unit tests to ensure it works correctly.