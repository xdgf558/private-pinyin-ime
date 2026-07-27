/// The first visible candidate is the default Space-key commit target.
///
/// ABC-01 keeps that identity stable when an optional ranker proposes a
/// permutation for an already computed candidate page. Lower candidates may
/// still be reordered.
pub const STABLE_DEFAULT_CANDIDATE_COUNT: usize = 1;

/// Validates an exact candidate-page permutation and pins the default candidate.
///
/// Candidate indices refer to the base page before optional reranking. The
/// returned order contains every index exactly once, with the stable prefix
/// preserved in its original position.
pub fn stabilize_candidate_page_order(
    candidate_count: usize,
    proposed_order: &[usize],
) -> Option<Vec<usize>> {
    if proposed_order.len() != candidate_count {
        return None;
    }

    let mut seen = vec![false; candidate_count];
    for &index in proposed_order {
        if index >= candidate_count || seen[index] {
            return None;
        }
        seen[index] = true;
    }

    let stable_count = candidate_count.min(STABLE_DEFAULT_CANDIDATE_COUNT);
    let mut stable_order = Vec::with_capacity(candidate_count);
    stable_order.extend(0..stable_count);
    stable_order.extend(
        proposed_order
            .iter()
            .copied()
            .filter(|&index| index >= stable_count),
    );
    Some(stable_order)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_candidate_stays_first_while_lower_candidates_follow_the_proposal() {
        assert_eq!(
            stabilize_candidate_page_order(4, &[3, 2, 0, 1]),
            Some(vec![0, 3, 2, 1])
        );
    }

    #[test]
    fn empty_page_is_a_valid_stable_permutation() {
        assert_eq!(stabilize_candidate_page_order(0, &[]), Some(Vec::new()));
    }

    #[test]
    fn incomplete_duplicate_or_out_of_range_orders_fail_closed() {
        assert_eq!(stabilize_candidate_page_order(3, &[0, 1]), None);
        assert_eq!(stabilize_candidate_page_order(3, &[0, 1, 1]), None);
        assert_eq!(stabilize_candidate_page_order(3, &[0, 1, 3]), None);
    }
}
