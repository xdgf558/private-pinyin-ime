use ime_core::ImeEngine;

#[test]
fn stage_one_prediction_is_not_enabled_yet() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let session = engine.create_session();

    assert!(session.predict_next().is_empty());
}
