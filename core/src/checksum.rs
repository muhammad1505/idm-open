use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::{BufReader, Read};

use md5::{Digest as Md5Digest, Md5};
use sha1::{Digest as Sha1Digest, Sha1};
use sha2::{Digest as Sha2Digest, Sha256};

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum ChecksumType {
    Md5,
    Sha1,
    Sha256,
}

impl ChecksumType {
    pub fn as_str(&self) -> &'static str {
        match self {
            ChecksumType::Md5 => "md5",
            ChecksumType::Sha1 => "sha1",
            ChecksumType::Sha256 => "sha256",
        }
    }

    pub fn from_str(value: &str) -> Option<Self> {
        match value {
            "md5" => Some(ChecksumType::Md5),
            "sha1" => Some(ChecksumType::Sha1),
            "sha256" => Some(ChecksumType::Sha256),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChecksumRequest {
    pub checksum_type: ChecksumType,
    pub expected_hex: String,
}

pub fn verify_checksum(path: &str, req: &ChecksumRequest) -> bool {
    match req.checksum_type {
        ChecksumType::Md5 => verify_md5(path, &req.expected_hex),
        ChecksumType::Sha1 => verify_sha1(path, &req.expected_hex),
        ChecksumType::Sha256 => verify_sha256(path, &req.expected_hex),
    }
}

fn verify_md5(path: &str, expected: &str) -> bool {
    let mut file = match File::open(path) {
        Ok(file) => file,
        Err(_) => return false,
    };
    let mut hasher = <Md5 as Md5Digest>::new();
    let mut buf = [0u8; 1024 * 64];
    loop {
        let read = match file.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(_) => return false,
        };
        hasher.update(&buf[..read]);
    }
    let actual = format!("{:x}", hasher.finalize());
    actual.eq_ignore_ascii_case(expected)
}

fn verify_sha1(path: &str, expected: &str) -> bool {
    let file = match File::open(path) {
        Ok(file) => file,
        Err(_) => return false,
    };
    let mut reader = BufReader::new(file);
    let mut hasher = <Sha1 as Sha1Digest>::new();
    let mut buf = [0u8; 1024 * 64];
    loop {
        let read = match reader.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(_) => return false,
        };
        hasher.update(&buf[..read]);
    }
    let actual = format!("{:x}", hasher.finalize());
    actual.eq_ignore_ascii_case(expected)
}

fn verify_sha256(path: &str, expected: &str) -> bool {
    let file = match File::open(path) {
        Ok(file) => file,
        Err(_) => return false,
    };
    let mut reader = BufReader::new(file);
    let mut hasher = <Sha256 as Sha2Digest>::new();
    let mut buf = [0u8; 1024 * 64];
    loop {
        let read = match reader.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(_) => return false,
        };
        hasher.update(&buf[..read]);
    }
    let actual = format!("{:x}", hasher.finalize());
    actual.eq_ignore_ascii_case(expected)
}
