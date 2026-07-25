Feature: Companion watch enrollment

  Scenario: Protected person enrolls an Apple Watch with a one-time token
    Given I register a protected person device
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/companion-enrollments" with:
      """
      {"platform": "watchos"}
      """
    Then the response status code is 201
    And I store the response JSON field "enrollmentToken" as "enrollmentToken"
    And the response JSON field "expiresAt" is not empty
    And I am not authenticated
    When I send a POST request to "/api/v1/companion-enrollments/claim" with:
      """
      {
        "enrollmentToken": "{enrollmentToken}",
        "platform": "watchos",
        "appVersion": "1.0.0"
      }
      """
    Then the response status code is 201
    And the response JSON field "deviceId" is not empty
    And the response JSON field "deviceToken" is not empty
    When I send a POST request to "/api/v1/companion-enrollments/claim" with:
      """
      {
        "enrollmentToken": "{enrollmentToken}",
        "platform": "watchos",
        "appVersion": "1.0.0"
      }
      """
    Then the response status code is 404

  Scenario: Wrong companion platform does not consume the enrollment token
    Given I register a protected person device
    And I am authenticated as the protected person
    When I send a POST request to "/api/v1/companion-enrollments" with:
      """
      {"platform": "wearos"}
      """
    Then the response status code is 201
    And I store the response JSON field "enrollmentToken" as "enrollmentToken"
    And I am not authenticated
    When I send a POST request to "/api/v1/companion-enrollments/claim" with:
      """
      {
        "enrollmentToken": "{enrollmentToken}",
        "platform": "watchos",
        "appVersion": "1.0.0"
      }
      """
    Then the response status code is 404
    When I send a POST request to "/api/v1/companion-enrollments/claim" with:
      """
      {
        "enrollmentToken": "{enrollmentToken}",
        "platform": "wearos",
        "appVersion": "1.0.0"
      }
      """
    Then the response status code is 201

  Scenario: Caregiver cannot create a companion enrollment
    Given I register a caregiver device
    And I am authenticated as the caregiver
    When I send a POST request to "/api/v1/companion-enrollments" with:
      """
      {"platform": "watchos"}
      """
    Then the response status code is 422
