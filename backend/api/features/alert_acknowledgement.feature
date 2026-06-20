Feature: Alert acknowledgement and caregiver alert history

  Scenario: Caregiver can acknowledge a fall alert
    Given I register a protected person device
    And I register a caregiver device
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/invites"
    Then the response status code is 201
    And I store the response JSON field "code" as "inviteCode"
    And I am authenticated as the caregiver
    When I send a POST request to "/api/v1/invites/{inviteCode}/accept"
    Then the response status code is 204
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/fall-alerts" with:
      """
      {
        "clientAlertId": "ack-behat-001",
        "fallTimestamp": "2025-01-01T12:00:00+00:00",
        "locale": "en"
      }
      """
    Then the response status code is 201
    And I store the response JSON field "id" as "id"
    And I am authenticated as the caregiver
    When I send a POST request to "/api/v1/fall-alerts/{id}/acknowledge"
    Then the response status code is 204

  Scenario: Acknowledging the same alert twice is idempotent
    Given I register a protected person device
    And I register a caregiver device
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/invites"
    Then the response status code is 201
    And I store the response JSON field "code" as "inviteCode"
    And I am authenticated as the caregiver
    When I send a POST request to "/api/v1/invites/{inviteCode}/accept"
    Then the response status code is 204
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/fall-alerts" with:
      """
      {
        "clientAlertId": "ack-behat-idem",
        "fallTimestamp": "2025-01-01T12:00:00+00:00",
        "locale": "en"
      }
      """
    Then the response status code is 201
    And I store the response JSON field "id" as "id"
    And I am authenticated as the caregiver
    When I send a POST request to "/api/v1/fall-alerts/{id}/acknowledge"
    Then the response status code is 204
    When I send a POST request to "/api/v1/fall-alerts/{id}/acknowledge"
    Then the response status code is 204

  Scenario: Unlinked caregiver cannot acknowledge an alert
    Given I register a protected person device
    And I register a caregiver device
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/fall-alerts" with:
      """
      {
        "clientAlertId": "ack-behat-unlinked",
        "fallTimestamp": "2025-01-01T12:00:00+00:00",
        "locale": "en"
      }
      """
    Then the response status code is 201
    And I store the response JSON field "id" as "id"
    And I am authenticated as the caregiver
    When I send a POST request to "/api/v1/fall-alerts/{id}/acknowledge"
    Then the response status code is 403

  Scenario: Caregiver can list alerts for linked protected persons
    Given I register a protected person device
    And I register a caregiver device
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/invites"
    Then the response status code is 201
    And I store the response JSON field "code" as "inviteCode"
    And I am authenticated as the caregiver
    When I send a POST request to "/api/v1/invites/{inviteCode}/accept"
    Then the response status code is 204
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/fall-alerts" with:
      """
      {
        "clientAlertId": "list-behat-001",
        "fallTimestamp": "2025-01-01T12:00:00+00:00",
        "locale": "en"
      }
      """
    Then the response status code is 201
    And I am authenticated as the caregiver
    When I send a GET request to "/api/v1/caregiver/alerts"
    Then the response status code is 200
    And the response is a non-empty collection

  Scenario: Caregiver with no links sees an empty alert list
    Given I register a caregiver device
    And I am authenticated as the caregiver
    When I send a GET request to "/api/v1/caregiver/alerts"
    Then the response status code is 200
    And the response is an empty collection
