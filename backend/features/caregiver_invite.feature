Feature: Caregiver invite flow

  Scenario: Protected person can generate an invite code
    Given I register a protected person device
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/invites"
    Then the response status code is 201
    And the response JSON field "code" is not empty
    And the response JSON field "expiresAt" is not empty

  Scenario: Caregiver can accept an invite and become linked
    Given I register a protected person device
    And I register a caregiver device
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/invites"
    Then the response status code is 201
    And I store the response JSON field "code" as "inviteCode"
    And I am authenticated as the caregiver
    When I send a POST request to "/api/v1/invites/{inviteCode}/accept"
    Then the response status code is 204

  Scenario: Caregiver can register a push token after linking
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
      {"fcmToken": "test-fcm-token-behat-001"}
      """
    Then the response status code is 204

  Scenario: Accepting a non-existent invite code returns 404
    Given I register a caregiver device
    And I am authenticated as the caregiver
    When I send a POST request to "/api/v1/invites/BADCODE/accept"
    Then the response status code is 404

  Scenario: A protected person device cannot accept an invite
    Given I register a protected person device
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/invites"
    Then the response status code is 201
    And I store the response JSON field "code" as "inviteCode"
    When I send a POST request to "/api/v1/invites/{inviteCode}/accept"
    Then the response status code is 422
