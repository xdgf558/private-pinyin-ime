use crate::AiFeature;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum HardwareTier {
    Tier0,
    Tier1,
    Tier2,
    Tier3,
}

impl HardwareTier {
    pub const fn supports(self, feature: AiFeature) -> bool {
        match self {
            Self::Tier0 => false,
            Self::Tier1 => feature.is_lite(),
            Self::Tier2 | Self::Tier3 => true,
        }
    }
}
