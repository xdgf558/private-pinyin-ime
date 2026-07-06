#[derive(Debug, Clone, Default)]
pub struct UserLexicon;

impl UserLexicon {
    pub fn is_enabled_for_stage_one(&self) -> bool {
        false
    }
}
