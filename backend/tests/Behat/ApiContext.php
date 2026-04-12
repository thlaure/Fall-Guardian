<?php

declare(strict_types=1);

namespace App\Tests\Behat;

use App\Infrastructure\Push\FakePushStore;
use App\Infrastructure\Sms\FakeSmsStore;

use function array_key_exists;

use Behat\Behat\Context\Context;
use Behat\Behat\Hook\Scope\BeforeScenarioScope;
use Behat\Gherkin\Node\PyStringNode;

use function count;
use function is_array;
use function is_scalar;
use function json_decode;
use function json_encode;

use const JSON_THROW_ON_ERROR;

use function preg_replace_callback;

use RuntimeException;

use function sprintf;

use Symfony\Bundle\FrameworkBundle\KernelBrowser;
use Symfony\Component\HttpKernel\KernelInterface;

final class ApiContext implements Context
{
    private readonly KernelBrowser $client;

    /** @var array<string, string> token per role */
    private array $tokens = [];

    private string $currentToken = '';

    /** @var array<string, mixed> values saved from responses */
    private array $stored = [];

    private int $lastStatusCode = 0;

    /** @var array<mixed>|null */
    private ?array $lastResponseData = null;

    public function __construct(
        KernelInterface $kernel,
        private readonly FakeSmsStore $smsStore,
        private readonly FakePushStore $pushStore,
    ) {
        $this->client = new KernelBrowser($kernel);
        $this->client->disableReboot();
    }

    // ─── Hooks ─────────────────────────────────────────────────────────────────

    /**
     * @BeforeScenario
     */
    public function resetScenarioState(BeforeScenarioScope $scope): void
    {
        $this->tokens = [];
        $this->currentToken = '';
        $this->stored = [];
        $this->lastStatusCode = 0;
        $this->lastResponseData = null;
        $this->smsStore->clear();
        $this->pushStore->clear();
    }

    // ─── Given ─────────────────────────────────────────────────────────────────

    /**
     * @Given I register a protected person device
     */
    public function iRegisterAProtectedPersonDevice(): void
    {
        $this->sendRequest('POST', '/api/v1/devices/register', [
            'platform' => 'ios',
            'appVersion' => '1.0.0',
        ]);

        $this->tokens['protected'] = $this->requireResponseField('deviceToken');
    }

    /**
     * @Given I register a caregiver device
     */
    public function iRegisterACaregiverDevice(): void
    {
        $this->sendRequest('POST', '/api/v1/devices/register', [
            'platform' => 'android',
            'appVersion' => '1.0.0',
            'deviceType' => 'caregiver',
        ]);

        $this->tokens['caregiver'] = $this->requireResponseField('deviceToken');
    }

    /**
     * @Given I am authenticated as the protected person
     */
    public function iAmAuthenticatedAsProtectedPerson(): void
    {
        $this->currentToken = $this->tokens['protected']
            ?? throw new RuntimeException('No protected person registered yet.');
    }

    /**
     * @Given I am authenticated as the caregiver
     */
    public function iAmAuthenticatedAsCaregiver(): void
    {
        $this->currentToken = $this->tokens['caregiver']
            ?? throw new RuntimeException('No caregiver registered yet.');
    }

    // ─── When ──────────────────────────────────────────────────────────────────

    /**
     * @When I send a POST request to :path
     */
    public function iSendAPostRequestTo(string $path): void
    {
        $this->sendRequest('POST', $this->interpolate($path), []);
    }

    /**
     * @When I send a POST request to :path with:
     */
    public function iSendAPostRequestToWith(string $path, PyStringNode $body): void
    {
        /** @var array<mixed> $data */
        $data = json_decode($body->getRaw(), true, 512, JSON_THROW_ON_ERROR);
        $this->sendRequest('POST', $this->interpolate($path), $data);
    }

    /**
     * @When I send a PUT request to :path with:
     */
    public function iSendAPutRequestToWith(string $path, PyStringNode $body): void
    {
        /** @var array<mixed> $data */
        $data = json_decode($body->getRaw(), true, 512, JSON_THROW_ON_ERROR);
        $this->sendRequest('PUT', $this->interpolate($path), $data);
    }

    /**
     * @When I send a GET request to :path
     */
    public function iSendAGetRequestTo(string $path): void
    {
        $this->sendRequest('GET', $this->interpolate($path), null);
    }

    // ─── Then ──────────────────────────────────────────────────────────────────

    /**
     * @Then the response status code is :code
     */
    public function theResponseStatusCodeIs(int $code): void
    {
        if ($this->lastStatusCode !== $code) {
            throw new RuntimeException(sprintf(
                'Expected status %d but got %d. Body: %s',
                $code,
                $this->lastStatusCode,
                json_encode($this->lastResponseData, JSON_THROW_ON_ERROR),
            ));
        }
    }

    /**
     * @Then the response JSON field :field equals :value
     */
    public function theResponseJsonFieldEquals(string $field, string $value): void
    {
        $actual = $this->requireResponseField($field);
        $expected = $this->interpolate($value);

        if ($actual !== $expected) {
            throw new RuntimeException(sprintf(
                'Expected field "%s" to equal "%s" but got "%s".',
                $field,
                $expected,
                $actual,
            ));
        }
    }

    /**
     * @Then the response JSON field :field exists
     */
    public function theResponseJsonFieldExists(string $field): void
    {
        $this->requireResponseField($field);
    }

    /**
     * @Then the response JSON field :field is not empty
     */
    public function theResponseJsonFieldIsNotEmpty(string $field): void
    {
        $value = $this->requireResponseField($field);

        if ('' === $value) {
            throw new RuntimeException(sprintf('Expected field "%s" to be non-empty.', $field));
        }
    }

    /**
     * @Then the response is a non-empty collection
     */
    public function theResponseIsANonEmptyCollection(): void
    {
        // Accepts both hydra collection {"hydra:member":[...]} and plain array [...].
        $members = $this->lastResponseData['hydra:member'] ?? (is_array($this->lastResponseData) && array_is_list($this->lastResponseData) ? $this->lastResponseData : null);

        if (!is_array($members) || [] === $members) {
            throw new RuntimeException(sprintf(
                'Expected a non-empty collection but got: %s',
                json_encode($this->lastResponseData, JSON_THROW_ON_ERROR),
            ));
        }
    }

    /**
     * @Then the response is an empty collection
     */
    public function theResponseIsAnEmptyCollection(): void
    {
        // Accepts both hydra collection {"hydra:member":[]} and plain empty array [].
        $members = $this->lastResponseData['hydra:member'] ?? (is_array($this->lastResponseData) && array_is_list($this->lastResponseData) ? $this->lastResponseData : null);

        if (!is_array($members) || [] !== $members) {
            throw new RuntimeException(sprintf(
                'Expected an empty collection but got: %s',
                json_encode($this->lastResponseData, JSON_THROW_ON_ERROR),
            ));
        }
    }

    /**
     * @Then the fake SMS inbox contains :count messages
     */
    public function theFakeSmsInboxContainsMessages(int $count): void
    {
        $actual = count($this->smsStore->all());

        if ($actual !== $count) {
            throw new RuntimeException(sprintf('Expected %d SMS message(s) but found %d.', $count, $actual));
        }
    }

    /**
     * @Then the fake push inbox contains :count messages
     */
    public function theFakePushInboxContainsMessages(int $count): void
    {
        $actual = count($this->pushStore->all());

        if ($actual !== $count) {
            throw new RuntimeException(sprintf('Expected %d push message(s) but found %d.', $count, $actual));
        }
    }

    /**
     * @Then I store the response JSON field :field as :key
     */
    public function iStoreTheResponseJsonFieldAs(string $field, string $key): void
    {
        $this->stored[$key] = $this->requireResponseField($field);
    }

    // ─── Helpers ───────────────────────────────────────────────────────────────

    /** @param array<mixed>|null $data */
    private function sendRequest(string $method, string $path, ?array $data): void
    {
        $server = [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_ACCEPT' => 'application/json',
        ];

        if ('' !== $this->currentToken) {
            $server['HTTP_AUTHORIZATION'] = sprintf('Bearer %s', $this->currentToken);
        }

        $content = null !== $data ? json_encode($data, JSON_THROW_ON_ERROR) : null;

        $this->client->request($method, $path, server: $server, content: $content);

        $response = $this->client->getResponse();
        $this->lastStatusCode = $response->getStatusCode();

        $body = $response->getContent();

        if (false !== $body && '' !== $body) {
            /** @var array<mixed> $decoded */
            $decoded = json_decode($body, true, 512, JSON_THROW_ON_ERROR);
            $this->lastResponseData = $decoded;
        } else {
            $this->lastResponseData = null;
        }
    }

    /** Replace {key} placeholders in paths with stored values. */
    private function interpolate(string $path): string
    {
        return (string) preg_replace_callback('/\{(\w+)\}/', function (array $matches): string {
            $key = $matches[1];
            $val = $this->stored[$key] ?? null;

            return is_scalar($val) ? (string) $val : $matches[0];
        }, $path);
    }

    private function requireResponseField(string $field): string
    {
        if (null === $this->lastResponseData || !array_key_exists($field, $this->lastResponseData)) {
            throw new RuntimeException(sprintf(
                'Field "%s" not found in response: %s',
                $field,
                json_encode($this->lastResponseData, JSON_THROW_ON_ERROR),
            ));
        }

        $value = $this->lastResponseData[$field];

        if (!is_scalar($value) && null !== $value) {
            throw new RuntimeException(sprintf('Field "%s" is not a scalar value.', $field));
        }

        return (string) $value;
    }
}
