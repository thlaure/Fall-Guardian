<?php

declare(strict_types=1);

use Symfony\Component\Dotenv\Dotenv;

require dirname(__DIR__) . '/vendor/autoload.php';

// Force test environment so bootEnv loads .env.test overrides.
$_SERVER['APP_ENV'] = $_ENV['APP_ENV'] = 'test';

if (file_exists(dirname(__DIR__) . '/.env')) {
    new Dotenv()->bootEnv(dirname(__DIR__) . '/.env');
}
