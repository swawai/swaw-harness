use std::io::{Read, Write};

pub(crate) const KIND_REQUEST: u16 = 1;
pub(crate) const KIND_STDOUT: u16 = 2;
pub(crate) const KIND_STDERR: u16 = 3;
pub(crate) const KIND_RESULT: u16 = 4;
pub(crate) const KIND_ERROR: u16 = 5;

const MAGIC: [u8; 4] = *b"SWAH";
const VERSION: u16 = 1;
const HEADER_BYTES: usize = 12;
const MAXIMUM_PAYLOAD_BYTES: usize = 256 * 1024;
const MAXIMUM_ARGUMENTS: usize = 64;
const MAXIMUM_STRING_UNITS: usize = 32 * 1024;

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct Request {
    pub(crate) user_id: Vec<u16>,
    pub(crate) user_home: Vec<u16>,
    pub(crate) arguments: Vec<Vec<u16>>,
}

pub(crate) fn read_request(reader: &mut impl Read) -> Result<Request, String> {
    let (kind, payload) = read_frame(reader)?;
    if kind != KIND_REQUEST {
        return Err("first Core Host frame must be a request".to_owned());
    }
    let mut cursor = PayloadCursor::new(&payload);
    let user_id = cursor.read_utf16("UserId", false)?;
    let user_home = cursor.read_utf16("UserHome", false)?;
    let argument_count = cursor.read_u32("argument count")? as usize;
    if argument_count == 0 || argument_count > MAXIMUM_ARGUMENTS {
        return Err(format!(
            "Core Host request must contain between 1 and {MAXIMUM_ARGUMENTS} arguments"
        ));
    }
    let mut arguments = Vec::with_capacity(argument_count);
    for _ in 0..argument_count {
        arguments.push(cursor.read_utf16("argument", true)?);
    }
    cursor.finish()?;
    Ok(Request {
        user_id,
        user_home,
        arguments,
    })
}

pub(crate) fn write_frame(
    writer: &mut impl Write,
    kind: u16,
    payload: &[u8],
) -> Result<(), String> {
    if !matches!(kind, KIND_STDOUT | KIND_STDERR | KIND_RESULT | KIND_ERROR) {
        return Err(format!("invalid Core Host response frame kind {kind}"));
    }
    if payload.len() > MAXIMUM_PAYLOAD_BYTES {
        return Err("Core Host response frame is too large".to_owned());
    }
    let mut header = [0_u8; HEADER_BYTES];
    header[0..4].copy_from_slice(&MAGIC);
    header[4..6].copy_from_slice(&VERSION.to_le_bytes());
    header[6..8].copy_from_slice(&kind.to_le_bytes());
    header[8..12].copy_from_slice(&(payload.len() as u32).to_le_bytes());
    writer
        .write_all(&header)
        .and_then(|_| writer.write_all(payload))
        .map_err(|error| format!("cannot write Core Host response: {error}"))
}

fn read_frame(reader: &mut impl Read) -> Result<(u16, Vec<u8>), String> {
    let mut header = [0_u8; HEADER_BYTES];
    reader
        .read_exact(&mut header)
        .map_err(|error| format!("cannot read Core Host request header: {error}"))?;
    if header[0..4] != MAGIC {
        return Err("Core Host request has invalid magic".to_owned());
    }
    if u16::from_le_bytes([header[4], header[5]]) != VERSION {
        return Err("Core Host request uses an unsupported protocol version".to_owned());
    }
    let kind = u16::from_le_bytes([header[6], header[7]]);
    let length = u32::from_le_bytes(header[8..12].try_into().unwrap()) as usize;
    if length == 0 || length > MAXIMUM_PAYLOAD_BYTES {
        return Err("Core Host request payload has an invalid size".to_owned());
    }
    let mut payload = vec![0_u8; length];
    reader
        .read_exact(&mut payload)
        .map_err(|error| format!("cannot read Core Host request payload: {error}"))?;
    Ok((kind, payload))
}

struct PayloadCursor<'a> {
    payload: &'a [u8],
    position: usize,
}

impl<'a> PayloadCursor<'a> {
    fn new(payload: &'a [u8]) -> Self {
        Self {
            payload,
            position: 0,
        }
    }

    fn read_u32(&mut self, description: &str) -> Result<u32, String> {
        let end = self
            .position
            .checked_add(4)
            .filter(|end| *end <= self.payload.len())
            .ok_or_else(|| format!("Core Host request truncates {description}"))?;
        let value = u32::from_le_bytes(self.payload[self.position..end].try_into().unwrap());
        self.position = end;
        Ok(value)
    }

    fn read_utf16(&mut self, description: &str, allow_empty: bool) -> Result<Vec<u16>, String> {
        let units = self.read_u32(&format!("{description} length"))? as usize;
        if (!allow_empty && units == 0) || units > MAXIMUM_STRING_UNITS {
            return Err(format!(
                "Core Host request has an invalid {description} length"
            ));
        }
        let bytes = units
            .checked_mul(2)
            .ok_or_else(|| format!("Core Host request has an invalid {description} length"))?;
        let end = self
            .position
            .checked_add(bytes)
            .filter(|end| *end <= self.payload.len())
            .ok_or_else(|| format!("Core Host request truncates {description}"))?;
        let result = self.payload[self.position..end]
            .chunks_exact(2)
            .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
            .collect();
        self.position = end;
        Ok(result)
    }

    fn finish(self) -> Result<(), String> {
        if self.position == self.payload.len() {
            Ok(())
        } else {
            Err("Core Host request has trailing payload bytes".to_owned())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{KIND_REQUEST, MAGIC, Request, VERSION, read_request};

    fn append_utf16(payload: &mut Vec<u8>, value: &str) {
        let units: Vec<_> = value.encode_utf16().collect();
        payload.extend_from_slice(&(units.len() as u32).to_le_bytes());
        for unit in units {
            payload.extend_from_slice(&unit.to_le_bytes());
        }
    }

    fn request_frame() -> Vec<u8> {
        let mut payload = Vec::new();
        append_utf16(&mut payload, "admin");
        append_utf16(&mut payload, r"D:\harness\data\admin");
        payload.extend_from_slice(&2_u32.to_le_bytes());
        append_utf16(&mut payload, "helloworld");
        append_utf16(&mut payload, "Swaw");

        let mut frame = Vec::new();
        frame.extend_from_slice(&MAGIC);
        frame.extend_from_slice(&VERSION.to_le_bytes());
        frame.extend_from_slice(&KIND_REQUEST.to_le_bytes());
        frame.extend_from_slice(&(payload.len() as u32).to_le_bytes());
        frame.extend_from_slice(&payload);
        frame
    }

    #[test]
    fn request_preserves_utf16_arguments() {
        let request = read_request(&mut request_frame().as_slice()).unwrap();

        assert_eq!(
            request,
            Request {
                user_id: "admin".encode_utf16().collect(),
                user_home: r"D:\harness\data\admin".encode_utf16().collect(),
                arguments: vec![
                    "helloworld".encode_utf16().collect(),
                    "Swaw".encode_utf16().collect(),
                ],
            }
        );
    }

    #[test]
    fn trailing_bytes_are_rejected() {
        let mut frame = request_frame();
        let length = u32::from_le_bytes(frame[8..12].try_into().unwrap()) + 1;
        frame[8..12].copy_from_slice(&length.to_le_bytes());
        frame.push(0);

        assert!(
            read_request(&mut frame.as_slice())
                .unwrap_err()
                .contains("trailing")
        );
    }

    #[test]
    fn empty_dynamic_argument_is_preserved() {
        let mut frame = request_frame();
        let payload_length = u32::from_le_bytes(frame[8..12].try_into().unwrap());
        frame[8..12].copy_from_slice(&(payload_length + 4).to_le_bytes());
        let argument_count_position = 12
            + 4
            + "admin".encode_utf16().count() * 2
            + 4
            + r"D:\harness\data\admin".encode_utf16().count() * 2;
        frame[argument_count_position..argument_count_position + 4]
            .copy_from_slice(&3_u32.to_le_bytes());
        frame.extend_from_slice(&0_u32.to_le_bytes());

        let request = read_request(&mut frame.as_slice()).unwrap();
        assert_eq!(request.arguments[2], Vec::<u16>::new());
    }
}
