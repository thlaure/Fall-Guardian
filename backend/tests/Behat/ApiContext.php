<?php

declare(strict_types=1);

namespace App\Tests\Behat;

use Behat\Behat\Context\Context;

final class ApiContext implements Context
{
    /**
     * @Given nothing
     */
    public function nothing(): void
    {
    }
}
