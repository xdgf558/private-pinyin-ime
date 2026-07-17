use crate::AiFeature;
use serde::{Deserialize, Serialize};

const MIB: u64 = 1024 * 1024;
const GIB: u64 = 1024 * MIB;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum HardwareTier {
    #[serde(rename = "tier_0")]
    Tier0,
    #[serde(rename = "tier_1")]
    Tier1,
    #[serde(rename = "tier_2")]
    Tier2,
    #[serde(rename = "tier_3")]
    Tier3,
}

impl HardwareTier {
    pub const fn from_memory_bytes(memory_bytes: u64) -> Self {
        if memory_bytes < 8 * GIB {
            Self::Tier0
        } else if memory_bytes < 16 * GIB {
            Self::Tier1
        } else if memory_bytes < 24 * GIB {
            Self::Tier2
        } else {
            Self::Tier3
        }
    }

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Tier0 => "tier_0",
            Self::Tier1 => "tier_1",
            Self::Tier2 => "tier_2",
            Self::Tier3 => "tier_3",
        }
    }

    pub const fn supports(self, feature: AiFeature) -> bool {
        match self {
            Self::Tier0 => false,
            Self::Tier1 => feature.is_lite(),
            Self::Tier2 | Self::Tier3 => true,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HardwareProfile {
    memory_bytes: u64,
    gpu_available: bool,
}

impl HardwareProfile {
    pub const fn new(memory_bytes: u64, gpu_available: bool) -> Self {
        Self {
            memory_bytes,
            gpu_available,
        }
    }

    pub const fn from_memory_gib(memory_gib: u16, gpu_available: bool) -> Self {
        Self::new((memory_gib as u64).saturating_mul(GIB), gpu_available)
    }

    pub const fn memory_bytes(self) -> u64 {
        self.memory_bytes
    }

    pub const fn memory_mb(self) -> u64 {
        self.memory_bytes / MIB
    }

    pub const fn gpu_available(self) -> bool {
        self.gpu_available
    }

    pub const fn tier(self) -> HardwareTier {
        HardwareTier::from_memory_bytes(self.memory_bytes)
    }

    pub fn supports_model(self, requirements: ModelHardwareRequirements) -> bool {
        self.tier() >= requirements.min_tier
            && self.memory_mb() >= requirements.min_memory_mb
            && (!requirements.requires_gpu || self.gpu_available)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModelHardwareRequirements {
    min_tier: HardwareTier,
    min_memory_mb: u64,
    recommended_memory_mb: u64,
    requires_gpu: bool,
}

impl ModelHardwareRequirements {
    pub const fn new(
        min_tier: HardwareTier,
        min_memory_mb: u64,
        recommended_memory_mb: u64,
        requires_gpu: bool,
    ) -> Self {
        Self {
            min_tier,
            min_memory_mb,
            recommended_memory_mb,
            requires_gpu,
        }
    }

    pub const fn min_tier(self) -> HardwareTier {
        self.min_tier
    }

    pub const fn min_memory_mb(self) -> u64 {
        self.min_memory_mb
    }

    pub const fn recommended_memory_mb(self) -> u64 {
        self.recommended_memory_mb
    }

    pub const fn requires_gpu(self) -> bool {
        self.requires_gpu
    }

    pub(crate) const fn is_valid(self) -> bool {
        self.min_memory_mb > 0 && self.recommended_memory_mb >= self.min_memory_mb
    }
}
