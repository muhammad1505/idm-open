const MENU_ID = "idm-open-download";
const DEFAULTS = {
  autoCapture: false,
  cancelOriginal: true
};

let config = { ...DEFAULTS };

function refreshConfig() {
  chrome.storage.sync.get(DEFAULTS, (items) => {
    config = items;
  });
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: MENU_ID,
    title: "Download with IDM-Open",
    contexts: ["link", "page", "video", "audio"]
  });
  refreshConfig();
});

chrome.storage.onChanged.addListener(() => refreshConfig());

chrome.contextMenus.onClicked.addListener((info) => {
  const url = info.linkUrl || info.srcUrl || info.pageUrl;
  if (!url) {
    return;
  }
  sendToNative(url);
});

chrome.downloads.onCreated.addListener((item) => {
  if (!config.autoCapture) {
    return;
  }
  if (!item || !item.url) {
    return;
  }
  if (item.byExtensionId) {
    return;
  }
  if (item.url.startsWith("blob:") || item.url.startsWith("data:")) {
    return;
  }

  sendToNative(item.url, () => {
    if (config.cancelOriginal) {
      chrome.downloads.cancel(item.id);
      chrome.downloads.erase({ id: item.id });
    }
  });
});

function sendToNative(url, onSuccess) {
  chrome.runtime.sendNativeMessage(
    "com.idmopen.native",
    { url },
    (response) => {
      if (chrome.runtime.lastError) {
        console.error("IDM-Open native host error:", chrome.runtime.lastError.message);
        return;
      }
      if (response && response.ok) {
        console.log("IDM-Open queued:", response.id);
        if (onSuccess) {
          onSuccess();
        }
      } else {
        console.error("IDM-Open error:", response && response.error);
      }
    }
  );
}
