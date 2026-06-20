Feature: Device registration

  Scenario: Register a protected person device
    When I send a POST request to "/api/v1/devices/register" with:
      """
      {"platform": "ios", "appVersion": "1.0.0"}
      """
    Then the response status code is 201
    And the response JSON field "deviceId" is not empty
    And the response JSON field "deviceToken" is not empty

  Scenario: Register a caregiver device
    When I send a POST request to "/api/v1/devices/register" with:
      """
      {"platform": "android", "appVersion": "1.0.0", "deviceType": "caregiver"}
      """
    Then the response status code is 201
    And the response JSON field "deviceId" is not empty
    And the response JSON field "deviceToken" is not empty

  Scenario: Registration fails without required fields
    When I send a POST request to "/api/v1/devices/register" with:
      """
      {}
      """
    Then the response status code is 422
