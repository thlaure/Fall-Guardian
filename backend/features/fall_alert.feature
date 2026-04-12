Feature: Fall alert management

  Scenario: Protected person can create a fall alert
    Given I register a protected person device
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/fall-alerts" with:
      """
      {
        "clientAlertId": "fa-behat-001",
        "fallTimestamp": "2025-01-01T12:00:00+00:00",
        "locale": "en"
      }
      """
    Then the response status code is 201
    And the response JSON field "id" is not empty
    And the response JSON field "status" equals "received"
    And the response JSON field "clientAlertId" equals "fa-behat-001"

  Scenario: Creating the same alert twice is idempotent
    Given I register a protected person device
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/fall-alerts" with:
      """
      {
        "clientAlertId": "fa-behat-idem",
        "fallTimestamp": "2025-01-01T12:00:00+00:00",
        "locale": "en"
      }
      """
    Then the response status code is 201
    And I store the response JSON field "id" as "id"
    When I send a POST request to "/api/v1/fall-alerts" with:
      """
      {
        "clientAlertId": "fa-behat-idem",
        "fallTimestamp": "2025-01-01T12:00:00+00:00",
        "locale": "en"
      }
      """
    Then the response status code is 201
    And the response JSON field "id" equals "{id}"

  Scenario: Protected person can cancel a fall alert
    Given I register a protected person device
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/fall-alerts" with:
      """
      {
        "clientAlertId": "fa-behat-cancel",
        "fallTimestamp": "2025-01-01T12:00:00+00:00",
        "locale": "en"
      }
      """
    Then the response status code is 201
    When I send a POST request to "/api/v1/fall-alerts/fa-behat-cancel/cancel" with:
      """
      {}
      """
    Then the response status code is 201
    And the response JSON field "status" equals "cancelled"

  Scenario: Fall alert dispatches a push notification to a linked caregiver
    Given I register a protected person device
    And I register a caregiver device
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/invites"
    Then the response status code is 201
    And I store the response JSON field "code" as "inviteCode"
    And I am authenticated as the caregiver
    When I send a POST request to "/api/v1/invites/{inviteCode}/accept"
    Then the response status code is 204
    When I send a POST request to "/api/v1/caregiver/push-token" with:
      """
      {"fcmToken": "test-fcm-token-e2e-001"}
      """
    Then the response status code is 204
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/fall-alerts" with:
      """
      {
        "clientAlertId": "fa-behat-push-e2e",
        "fallTimestamp": "2025-01-01T12:00:00+00:00",
        "locale": "en"
      }
      """
    Then the response status code is 201
    And the fake push inbox contains 1 messages

  Scenario: Creating a fall alert without authentication is rejected
    When I send a POST request to "/api/v1/fall-alerts" with:
      """
      {
        "clientAlertId": "fa-behat-unauth",
        "fallTimestamp": "2025-01-01T12:00:00+00:00",
        "locale": "en"
      }
      """
    Then the response status code is 401
