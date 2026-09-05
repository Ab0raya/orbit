pub mod errors;
pub mod events;
pub mod message;
pub mod request;
pub mod response;

pub use errors::ProtocolError;
pub use events::OrbitEvent;
pub use message::OrbitMessage;
pub use request::OrbitRequest;
pub use response::OrbitResponse;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_request_serialization() {
        let req = OrbitRequest::new("req_001", "ping", serde_json::json!({}));
        let serialized = serde_json::to_string(&req).expect("Failed to serialize");
        assert!(serialized.contains("\"id\":\"req_001\""));
        assert!(serialized.contains("\"type\":\"request\""));
        assert!(serialized.contains("\"action\":\"ping\""));

        let deserialized: OrbitRequest = serde_json::from_str(&serialized).expect("Failed to deserialize");
        assert_eq!(req, deserialized);
    }

    #[test]
    fn test_valid_response_serialization() {
        let res = OrbitResponse::success("req_001", "ping", serde_json::json!({"timestamp": 1234567890}));
        let serialized = serde_json::to_string(&res).expect("Failed to serialize");
        assert!(serialized.contains("\"success\":true"));
        assert!(serialized.contains("\"type\":\"response\""));

        let deserialized: OrbitResponse = serde_json::from_str(&serialized).expect("Failed to deserialize");
        assert_eq!(res, deserialized);
    }

    #[test]
    fn test_error_response_serialization() {
        let err = ProtocolError::invalid_pairing_code();
        let res = OrbitResponse::error("req_002", "pairing.verify", err);
        let serialized = serde_json::to_string(&res).expect("Failed to serialize");
        assert!(serialized.contains("\"success\":false"));
        assert!(serialized.contains("INVALID_PAIRING_CODE"));

        let deserialized: OrbitResponse = serde_json::from_str(&serialized).expect("Failed to deserialize");
        assert_eq!(res, deserialized);
    }

    #[test]
    fn test_event_serialization() {
        let ev = OrbitEvent::device_paired("dev_123", "iPhone 15", "ios", 1700000000);
        let serialized = serde_json::to_string(&ev).expect("Failed to serialize");
        assert!(serialized.contains("\"event\":\"device.paired\""));
        assert!(serialized.contains("\"type\":\"event\""));

        let deserialized: OrbitEvent = serde_json::from_str(&serialized).expect("Failed to deserialize");
        assert_eq!(ev, deserialized);
    }

    #[test]
    fn test_orbit_message_enum() {
        let req_json = r#"{"id":"req_100","type":"request","action":"ping","payload":{}}"#;
        let msg: OrbitMessage = serde_json::from_str(req_json).expect("Failed to deserialize");
        match msg {
            OrbitMessage::Request(r) => {
                assert_eq!(r.id, "req_100");
                assert_eq!(r.action, "ping");
            }
            _ => panic!("Expected Request variant"),
        }
    }
}
