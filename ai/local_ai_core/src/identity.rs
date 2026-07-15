use std::fmt;

const FNV_OFFSET_BASIS: u64 = 0xcbf29ce484222325;
const FNV_PRIME: u64 = 0x100000001b3;

#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct AiSessionId([u8; 16]);

impl AiSessionId {
    pub const fn from_bytes(bytes: [u8; 16]) -> Self {
        Self(bytes)
    }

    pub const fn from_u128(value: u128) -> Self {
        Self(value.to_be_bytes())
    }

    pub const fn as_bytes(self) -> [u8; 16] {
        self.0
    }
}

impl fmt::Debug for AiSessionId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("AiSessionId(<opaque>)")
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct AiRequestId(u64);

impl AiRequestId {
    pub const fn new(value: u64) -> Self {
        Self(value)
    }

    pub const fn get(self) -> u64 {
        self.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct AiCompositionRevision(u64);

impl AiCompositionRevision {
    pub const fn new(value: u64) -> Self {
        Self(value)
    }

    pub const fn get(self) -> u64 {
        self.0
    }
}

/// A non-cryptographic fingerprint of one ordered candidate set.
///
/// This value is only a lifecycle guard within the request that carries it. It is not
/// collision-resistant and must not be used for integrity checks, authorization,
/// persistent cache identity, or cross-process cache identity. A future persistent or
/// cross-process cache must define a separately versioned, collision-resistant key.
#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct AiCandidateSetHash(u64);

impl AiCandidateSetHash {
    pub fn from_ordered_texts<I, S>(texts: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: AsRef<str>,
    {
        // This fingerprint is for lifecycle identity, not cryptographic verification.
        let mut hash = FNV_OFFSET_BASIS;
        let mut count = 0_u64;
        for text in texts {
            count = count.wrapping_add(1);
            let bytes = text.as_ref().as_bytes();
            hash_bytes(&mut hash, &(bytes.len() as u64).to_le_bytes());
            hash_bytes(&mut hash, bytes);
        }
        hash_bytes(&mut hash, &count.to_le_bytes());
        Self(hash)
    }

    pub const fn get(self) -> u64 {
        self.0
    }
}

impl fmt::Debug for AiCandidateSetHash {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("AiCandidateSetHash(<redacted>)")
    }
}

fn hash_bytes(hash: &mut u64, bytes: &[u8]) {
    for byte in bytes {
        *hash ^= u64::from(*byte);
        *hash = hash.wrapping_mul(FNV_PRIME);
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct AiRequestIdentity {
    session_id: AiSessionId,
    request_id: AiRequestId,
    composition_revision: AiCompositionRevision,
    candidate_set_hash: AiCandidateSetHash,
}

impl fmt::Debug for AiRequestIdentity {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AiRequestIdentity")
            .field("session_id", &self.session_id)
            .field("request_id", &self.request_id)
            .field("composition_revision", &self.composition_revision)
            .field("candidate_set_hash", &self.candidate_set_hash)
            .finish()
    }
}

impl AiRequestIdentity {
    pub const fn new(
        session_id: AiSessionId,
        request_id: AiRequestId,
        composition_revision: AiCompositionRevision,
        candidate_set_hash: AiCandidateSetHash,
    ) -> Self {
        Self {
            session_id,
            request_id,
            composition_revision,
            candidate_set_hash,
        }
    }

    pub const fn session_id(self) -> AiSessionId {
        self.session_id
    }

    pub const fn request_id(self) -> AiRequestId {
        self.request_id
    }

    pub const fn composition_revision(self) -> AiCompositionRevision {
        self.composition_revision
    }

    pub const fn candidate_set_hash(self) -> AiCandidateSetHash {
        self.candidate_set_hash
    }

    pub fn matches_current(
        self,
        session_id: AiSessionId,
        composition_revision: AiCompositionRevision,
        candidate_set_hash: AiCandidateSetHash,
    ) -> bool {
        self.session_id == session_id
            && self.composition_revision == composition_revision
            && self.candidate_set_hash == candidate_set_hash
    }
}
