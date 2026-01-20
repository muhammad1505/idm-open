use std::collections::HashSet;
use std::io::Read;

use reqwest::header::CONTENT_TYPE;
use reqwest::Url;

use crate::error::{CoreError, CoreResult};
use crate::net::{DownloadRequest, NetClient};

const MAX_HTML_BYTES: usize = 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Provider {
    Pixeldrain,
    GoogleDrive,
    Mediafire,
    Mega,
    Unknown,
}

pub fn detect_provider(url: &str) -> Provider {
    let parsed = match Url::parse(url) {
        Ok(value) => value,
        Err(_) => return Provider::Unknown,
    };
    let host = match parsed.host_str() {
        Some(value) => value.to_ascii_lowercase(),
        None => return Provider::Unknown,
    };

    if host == "pixeldrain.com" || host == "www.pixeldrain.com" {
        return Provider::Pixeldrain;
    }
    if host == "drive.google.com" || host == "docs.google.com" {
        return Provider::GoogleDrive;
    }
    if host.ends_with("mediafire.com") {
        return Provider::Mediafire;
    }
    if host == "mega.nz" || host == "mega.co.nz" {
        return Provider::Mega;
    }

    Provider::Unknown
}

pub fn is_html_content_type(content_type: Option<&str>) -> bool {
    let Some(value) = content_type else {
        return false;
    };
    let value = value.to_ascii_lowercase();
    value.contains("text/html") || value.contains("application/xhtml")
}

pub fn resolve_url_candidates(urls: Vec<String>) -> Vec<String> {
    let mut out = Vec::new();
    let mut seen = HashSet::new();

    for url in urls {
        if let Some(resolved) = resolve_pixeldrain(&url) {
            if seen.insert(resolved.clone()) {
                out.push(resolved);
            }
        }
        if let Some(id) = resolve_google_drive_id(&url) {
            let direct = build_google_drive_direct(&id);
            if seen.insert(direct.clone()) {
                out.push(direct);
            }
        }
        if seen.insert(url.clone()) {
            out.push(url);
        }
    }

    out
}

pub fn resolve_html_download(
    net: &dyn NetClient,
    base_req: &DownloadRequest,
) -> CoreResult<Vec<String>> {
    let html = match fetch_html(net, base_req)? {
        Some(html) => html,
        None => return Ok(Vec::new()),
    };

    let provider = detect_provider(&base_req.url);
    let mut out = Vec::new();

    if provider == Provider::Mediafire {
        if let Some(link) = resolve_mediafire_html(&html) {
            out.push(link);
        }
    }

    if provider == Provider::GoogleDrive {
        if let Some(id) = resolve_google_drive_id(&base_req.url) {
            if let Some(link) = resolve_google_drive_confirm(&html, &id) {
                out.push(link);
            }
        }
        if let Some(link) = resolve_google_drive_direct_from_html(&html) {
            out.push(link);
        }
    }

    if out.is_empty() {
        if let Some(link) = resolve_generic_html(&html) {
            out.push(link);
        }
    }

    Ok(dedup(out))
}

fn fetch_html(net: &dyn NetClient, base_req: &DownloadRequest) -> CoreResult<Option<String>> {
    let mut req = base_req.clone();
    req.range = None;

    let mut response = net.get_stream(&req)?;
    let content_type = response
        .headers()
        .get(CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .map(|value| value.to_string());
    if !is_html_content_type(content_type.as_deref()) {
        return Ok(None);
    }

    let mut buf = Vec::new();
    let mut total = 0usize;
    let mut chunk = [0u8; 8192];
    loop {
        let read = response
            .read(&mut chunk)
            .map_err(|err| CoreError::Network(err.to_string()))?;
        if read == 0 {
            break;
        }
        buf.extend_from_slice(&chunk[..read]);
        total = total.saturating_add(read);
        if total >= MAX_HTML_BYTES {
            break;
        }
    }

    let html = String::from_utf8_lossy(&buf).to_string();
    Ok(Some(html))
}

fn resolve_pixeldrain(url: &str) -> Option<String> {
    let parsed = Url::parse(url).ok()?;
    let host = parsed.host_str()?.to_ascii_lowercase();
    if host != "pixeldrain.com" && host != "www.pixeldrain.com" {
        return None;
    }

    let path = parsed.path().trim_end_matches('/');
    let segments: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
    if segments.len() >= 2 && segments[0] == "d" {
        let id = segments[1];
        return Some(format!("https://pixeldrain.com/api/filesystem/{}", id));
    }

    None
}

fn resolve_google_drive_id(url: &str) -> Option<String> {
    let parsed = Url::parse(url).ok()?;
    let host = parsed.host_str()?.to_ascii_lowercase();
    if host != "drive.google.com" && host != "docs.google.com" {
        return None;
    }

    let path = parsed.path().trim_end_matches('/');
    let segments: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
    if segments.len() >= 3 && segments[0] == "file" && segments[1] == "d" {
        return Some(segments[2].to_string());
    }

    for (key, value) in parsed.query_pairs() {
        if key == "id" {
            return Some(value.to_string());
        }
    }

    None
}

fn build_google_drive_direct(id: &str) -> String {
    format!(
        "https://drive.google.com/uc?export=download&id={}",
        id
    )
}

fn resolve_google_drive_confirm(html: &str, id: &str) -> Option<String> {
    if let Some(link) = resolve_google_drive_direct_from_html(html) {
        return Some(link);
    }

    let token = extract_token_after(html, "confirm=")?;
    Some(format!(
        "https://drive.google.com/uc?export=download&confirm={}&id={}",
        token, id
    ))
}

fn resolve_google_drive_direct_from_html(html: &str) -> Option<String> {
    let pos = html.find("/uc?export=download")?;
    let slice = &html[pos..];
    let end = slice.find('"').or_else(|| slice.find('\''))?;
    let mut link = slice[..end].to_string();
    if !link.starts_with("http") {
        link = format!("https://drive.google.com{}", link);
    }
    Some(link)
}

fn resolve_mediafire_html(html: &str) -> Option<String> {
    if let Some(link) = extract_attr_before(html, "downloadButton", "href=\"") {
        return Some(link);
    }
    if let Some(link) = extract_first_href_prefix(html, "https://download") {
        return Some(link);
    }
    None
}

fn resolve_generic_html(html: &str) -> Option<String> {
    if let Some(link) = extract_first_href_with_keyword(html, "download") {
        return Some(link);
    }
    if let Some(link) = extract_meta_content(html, "og:video") {
        return Some(link);
    }
    if let Some(link) = extract_meta_content(html, "og:video:url") {
        return Some(link);
    }
    None
}

fn extract_attr_before(html: &str, marker: &str, attr: &str) -> Option<String> {
    let pos = html.find(marker)?;
    let slice = &html[..pos];
    slice
        .rfind(attr)
        .map(|start| &slice[start + attr.len()..])
        .and_then(|rest| rest.split('\"').next())
        .map(|value| value.to_string())
}

fn extract_attr_value(slice: &str, attr: &str) -> Option<String> {
    let start = slice.find(attr)? + attr.len();
    let rest = &slice[start..];
    let end = rest.find('"')?;
    Some(rest[..end].to_string())
}

fn extract_first_href_prefix(html: &str, prefix: &str) -> Option<String> {
    let mut offset = 0usize;
    while let Some(pos) = html[offset..].find("href=\"") {
        let start = offset + pos + 6;
        let rest = &html[start..];
        let end = rest.find('"')?;
        let link = &rest[..end];
        if link.starts_with(prefix) {
            return Some(link.to_string());
        }
        offset = start + end + 1;
    }
    None
}

fn extract_first_href_with_keyword(html: &str, keyword: &str) -> Option<String> {
    let mut offset = 0usize;
    while let Some(pos) = html[offset..].find("href=\"") {
        let start = offset + pos + 6;
        let rest = &html[start..];
        let end = rest.find('"')?;
        let link = &rest[..end];
        if link.starts_with("http") && link.contains(keyword) {
            return Some(link.to_string());
        }
        offset = start + end + 1;
    }
    None
}

fn extract_meta_content(html: &str, property: &str) -> Option<String> {
    let marker = format!("property=\"{}\"", property);
    let pos = html.find(&marker)?;
    let slice = &html[pos..];
    extract_attr_value(slice, "content=\"")
}

fn extract_token_after(html: &str, marker: &str) -> Option<String> {
    let pos = html.find(marker)?;
    let start = pos + marker.len();
    let rest = &html[start..];
    let mut token = String::new();
    for ch in rest.chars() {
        if ch.is_ascii_alphanumeric() || ch == '_' || ch == '-' {
            token.push(ch);
        } else {
            break;
        }
    }
    if token.is_empty() {
        None
    } else {
        Some(token)
    }
}

fn dedup(urls: Vec<String>) -> Vec<String> {
    let mut out = Vec::new();
    let mut seen = HashSet::new();
    for url in urls {
        if seen.insert(url.clone()) {
            out.push(url);
        }
    }
    out
}
