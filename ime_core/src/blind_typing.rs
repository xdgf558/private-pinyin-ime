/// Space commits the first candidate on the currently visible page.
pub const BLIND_DEFAULT_CANDIDATE_INDEX: usize = 0;

/// Physical number keys select at most the nine visible candidate positions.
pub const LAST_NUMBERED_CANDIDATE_KEY: u8 = 9;

/// Maps a physical `1` through `9` key to a visible page index.
///
/// Returning `None` for an unavailable slot keeps the active composition and
/// candidate page unchanged, which is essential for blind-typing recovery.
pub fn numbered_candidate_index(number: u8, visible_candidate_count: usize) -> Option<usize> {
    if !(1..=LAST_NUMBERED_CANDIDATE_KEY).contains(&number) {
        return None;
    }

    let index = usize::from(number - 1);
    (index < visible_candidate_count).then_some(index)
}

#[cfg(test)]
mod tests {
    use super::{
        numbered_candidate_index, BLIND_DEFAULT_CANDIDATE_INDEX, LAST_NUMBERED_CANDIDATE_KEY,
    };

    #[test]
    fn space_default_and_number_keys_share_visible_page_indices() {
        assert_eq!(BLIND_DEFAULT_CANDIDATE_INDEX, 0);
        assert_eq!(numbered_candidate_index(1, 9), Some(0));
        assert_eq!(
            numbered_candidate_index(LAST_NUMBERED_CANDIDATE_KEY, 9),
            Some(8)
        );
    }

    #[test]
    fn unavailable_or_invalid_numbered_slots_fail_closed() {
        assert_eq!(numbered_candidate_index(0, 9), None);
        assert_eq!(numbered_candidate_index(4, 3), None);
        assert_eq!(numbered_candidate_index(10, 10), None);
    }
}
