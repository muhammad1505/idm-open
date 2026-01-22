use std::collections::HashMap;

use reqwest::blocking::{Client, Response};
use reqwest::header::{
    HeaderMap, HeaderName, HeaderValue, ACCEPT_RANGES, CONTENT_DISPOSITION, CONTENT_LENGTH,
    CONTENT_TYPE, RANGE,
};

use crate::error::{CoreError, CoreResult};

#[derive(Debug, Clone)]
pub struct DownloadRequest {
    pub url: String,
    pub headers: HashMap<String, String>,
    pub cookies: HashMap<String, String>,
    pub range: Option<(u64, u64)>,
    pub proxy: Option<String>,
    pub basic_auth: Option<(String, String)>,
    pub user_agent: String,
}

impl DownloadRequest {
    pub fn new(url: String, user_agent: String) -> Self {
        Self {
            url,
            headers: HashMap::new(),
            cookies: HashMap::new(),
            range: None,
            proxy: None,
            basic_auth: None,
            user_agent,
        }
    }
}

#[derive(Debug, Clone)]
pub struct DownloadResponse {
    pub status_code: u16,
    pub total_bytes: Option<u64>,
    pub accept_ranges: bool,
    pub content_type: Option<String>,
    pub content_disposition: Option<String>,
}

pub trait NetClient: Send + Sync {
    fn head(&self, req: &DownloadRequest) -> CoreResult<DownloadResponse>;
    fn get(&self, req: &DownloadRequest) -> CoreResult<Response>;
    fn get_stream(&self, req: &DownloadRequest) -> CoreResult<Response>;
}

#[derive(Clone)]
pub struct ReqwestNetClient {
    client: Client,
}

impl ReqwestNetClient {
    pub fn new(user_agent: &str) -> CoreResult<Self> {
        let client = Client::builder()
            .user_agent(user_agent)
            .build()
            .map_err(|err| CoreError::Network(err.to_string()))?;
        Ok(Self { client })
    }

    fn build_client(&self, user_agent: &str, proxy: Option<&str>) -> CoreResult<Client> {
        let mut builder = Client::builder().user_agent(user_agent);
        if let Some(proxy_url) = proxy {
            let proxy = reqwest::Proxy::all(proxy_url)
                .map_err(|err| CoreError::Network(err.to_string()))?;
            builder = builder.proxy(proxy);
        }
        builder
            .build()
            .map_err(|err| CoreError::Network(err.to_string()))
    }

    fn request_headers(&self, req: &DownloadRequest) -> CoreResult<HeaderMap> {
        let mut headers = HeaderMap::new();
        for (key, value) in &req.headers {
            let name = HeaderName::from_bytes(key.as_bytes())
                .map_err(|err| CoreError::Network(err.to_string()))?;
            let value = HeaderValue::from_str(value)
                .map_err(|err| CoreError::Network(err.to_string()))?;
            headers.insert(name, value);
        }
        if !req.cookies.is_empty() {
            let cookie_value = req
                .cookies
                .iter()
                .map(|(k, v)| format!("{}={}", k, v))
                .collect::<Vec<String>>()
                .join("; ");
            headers.insert(
                reqwest::header::COOKIE,
                HeaderValue::from_str(&cookie_value)
                    .map_err(|err| CoreError::Network(err.to_string()))?,
            );
        }
        if let Some((start, end)) = req.range {
            let value = format!("bytes={}-{}", start, end);
            headers.insert(
                RANGE,
                HeaderValue::from_str(&value).map_err(|err| CoreError::Network(err.to_string()))?,
            );
        }
        Ok(headers)
    }

    fn pick_client(&self, req: &DownloadRequest) -> CoreResult<Client> {
        if req.proxy.is_some() {
            self.build_client(&req.user_agent, req.proxy.as_deref())
        } else {
            Ok(self.client.clone())
        }
    }
}

impl NetClient for ReqwestNetClient {
    fn head(&self, req: &DownloadRequest) -> CoreResult<DownloadResponse> {
        let client = self.pick_client(req)?;
        let mut request = client.head(&req.url).headers(self.request_headers(req)?);
        if let Some((user, pass)) = &req.basic_auth {
            request = request.basic_auth(user, Some(pass));
        }
        let resp = request
            .send()
            .map_err(|err| CoreError::Network(err.to_string()))?;
        let status = resp.status();
        let headers = resp.headers();
        let total_bytes = headers
            .get(CONTENT_LENGTH)
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse::<u64>().ok());
        let accept_ranges = headers
            .get(ACCEPT_RANGES)
            .and_then(|value| value.to_str().ok())
            .map(|value| value.eq_ignore_ascii_case("bytes"))
            .unwrap_or(false);
        let content_type = headers
            .get(CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .map(|value| value.to_string());
        let content_disposition = headers
            .get(CONTENT_DISPOSITION)
            .and_then(|value| value.to_str().ok())
            .map(|value| value.to_string());

        Ok(DownloadResponse {
            status_code: status.as_u16(),
            total_bytes,
            accept_ranges,
            content_type,
            content_disposition,
        })
    }

    fn get(&self, req: &DownloadRequest) -> CoreResult<Response> {
        self.get_stream(req)
    }

    fn get_stream(&self, req: &DownloadRequest) -> CoreResult<Response> {
        let client = self.pick_client(req)?;
        let mut request = client.get(&req.url).headers(self.request_headers(req)?);
        if let Some((user, pass)) = &req.basic_auth {
            request = request.basic_auth(user, Some(pass));
        }
        request
            .send()
            .map_err(|err| CoreError::Network(err.to_string()))
    }
}
