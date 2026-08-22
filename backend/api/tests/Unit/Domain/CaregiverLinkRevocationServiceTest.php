<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Service\CaregiverLinkRevocationService;
use App\Entity\CaregiverLink;
use App\Entity\Device;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;

final class CaregiverLinkRevocationServiceTest extends TestCase
{
    private CaregiverLinkRepositoryInterface&MockObject $repository;

    private CaregiverLinkRevocationService $service;

    protected function setUp(): void
    {
        $this->repository = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $this->service = new CaregiverLinkRevocationService($this->repository);
    }

    #[Test]
    public function itRevokesTheLinkOwnedByTheCaregiver(): void
    {
        $caregiver = $this->createMock(Device::class);
        $link = $this->createMock(CaregiverLink::class);

        $this->repository->expects($this->once())
            ->method('findActiveByIdAndCaregiverDevice')
            ->with('link-id', $caregiver)
            ->willReturn($link);
        $link->expects($this->once())->method('revoke');
        $this->repository->expects($this->once())->method('save')->with($link);

        self::assertTrue($this->service->revokeForCaregiver($caregiver, 'link-id'));
    }

    #[Test]
    public function itDoesNotModifyALinkTheCaregiverDoesNotOwn(): void
    {
        $caregiver = $this->createMock(Device::class);

        $this->repository->expects($this->once())
            ->method('findActiveByIdAndCaregiverDevice')
            ->with('foreign-link', $caregiver)
            ->willReturn(null);
        $this->repository->expects($this->never())->method('save');

        self::assertFalse($this->service->revokeForCaregiver($caregiver, 'foreign-link'));
    }
}
