pub fn pinyin_to_nine_key(pinyin: &str) -> String {
    pinyin.chars().filter_map(nine_key_digit).collect()
}

pub fn is_valid_nine_key_input(input: &str) -> bool {
    !input.is_empty() && input.chars().all(|ch| matches!(ch, '2'..='9'))
}

fn nine_key_digit(ch: char) -> Option<char> {
    match ch.to_ascii_lowercase() {
        'a' | 'b' | 'c' => Some('2'),
        'd' | 'e' | 'f' => Some('3'),
        'g' | 'h' | 'i' => Some('4'),
        'j' | 'k' | 'l' => Some('5'),
        'm' | 'n' | 'o' => Some('6'),
        'p' | 'q' | 'r' | 's' => Some('7'),
        't' | 'u' | 'v' => Some('8'),
        'w' | 'x' | 'y' | 'z' => Some('9'),
        'ü' => Some('8'),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::{is_valid_nine_key_input, pinyin_to_nine_key};

    #[test]
    fn maps_compact_and_spaced_pinyin() {
        assert_eq!(pinyin_to_nine_key("ni hao"), "64426");
        assert_eq!(pinyin_to_nine_key("gai'lv"), "42458");
        assert_eq!(pinyin_to_nine_key("lü"), "58");
    }

    #[test]
    fn validates_composition_digits() {
        assert!(is_valid_nine_key_input("23456789"));
        assert!(!is_valid_nine_key_input(""));
        assert!(!is_valid_nine_key_input("120"));
    }
}
