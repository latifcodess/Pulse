use pulse_core::model::AiState;
use pulse_core::monitor::AiMonitor;

#[test]
fn la_methode_de_test_parse_la_fixture() {
    let AiState::Ok(usage) = AiMonitor::new().claude_fixture_state() else {
        panic!("la fixture devrait donner AiState::Ok");
    };

    assert_eq!(usage.windows[0].label, "Session (5 h)");
    assert_eq!(usage.windows[0].percent, 49.0);
}
