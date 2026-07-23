<?php

declare(strict_types=1);

namespace App;

use Symfony\Bundle\FrameworkBundle\Kernel\MicroKernelTrait;
use Symfony\Component\HttpKernel\Kernel as BaseKernel;

final class Kernel extends BaseKernel
{
    use MicroKernelTrait;

    public function __construct(string $environment, bool $debug)
    {
        // PostgreSQL timestamps are stored without timezone using UTC by
        // convention. Doctrine hydrates those values in PHP's default
        // timezone, so the process must use the same UTC convention.
        date_default_timezone_set('UTC');

        parent::__construct($environment, $debug);
    }
}
