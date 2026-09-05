use std::collections::VecDeque;

pub const DEFAULT_MAX_BUFFER_BYTES: usize = 100 * 1024; // 100 KB

#[derive(Debug)]
pub struct RollingBuffer {
    data: VecDeque<u8>,
    max_capacity: usize,
}

impl RollingBuffer {
    pub fn new(max_capacity: Option<usize>) -> Self {
        let capacity = max_capacity.unwrap_or(DEFAULT_MAX_BUFFER_BYTES);
        Self {
            data: VecDeque::with_capacity(capacity.min(32 * 1024)),
            max_capacity: capacity,
        }
    }

    pub fn append(&mut self, bytes: &[u8]) {
        if bytes.is_empty() {
            return;
        }

        // If the chunk alone is bigger than max capacity, take only the last max_capacity bytes
        let slice = if bytes.len() > self.max_capacity {
            &bytes[bytes.len() - self.max_capacity..]
        } else {
            bytes
        };

        // Determine how many bytes need to be discarded
        let overflow = (self.data.len() + slice.len()).saturating_sub(self.max_capacity);
        if overflow > 0 {
            self.data.drain(0..overflow);
        }

        self.data.extend(slice);
    }

    pub fn get_history(&self) -> String {
        let (first, second) = self.data.as_slices();
        let mut full = Vec::with_capacity(first.len() + second.len());
        full.extend_from_slice(first);
        full.extend_from_slice(second);
        String::from_utf8_lossy(&full).into_owned()
    }

    pub fn len(&self) -> usize {
        self.data.len()
    }

    pub fn is_empty(&self) -> bool {
        self.data.is_empty()
    }

    pub fn clear(&mut self) {
        self.data.clear();
    }
}

impl Default for RollingBuffer {
    fn default() -> Self {
        Self::new(None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_buffer_append_and_history() {
        let mut buf = RollingBuffer::new(Some(100));
        buf.append(b"Hello ");
        buf.append(b"World!");
        assert_eq!(buf.get_history(), "Hello World!");
        assert_eq!(buf.len(), 12);
    }

    #[test]
    fn test_buffer_overflow_truncation() {
        let mut buf = RollingBuffer::new(Some(10));
        buf.append(b"0123456789");
        assert_eq!(buf.len(), 10);
        assert_eq!(buf.get_history(), "0123456789");

        // Add 5 more bytes -> earliest 5 should be discarded
        buf.append(b"ABCDE");
        assert_eq!(buf.len(), 10);
        assert_eq!(buf.get_history(), "56789ABCDE");
    }

    #[test]
    fn test_buffer_chunk_larger_than_capacity() {
        let mut buf = RollingBuffer::new(Some(5));
        buf.append(b"0123456789");
        assert_eq!(buf.len(), 5);
        assert_eq!(buf.get_history(), "56789");
    }
}
