const defaults = {
  autoCapture: false,
  cancelOriginal: true
};

function loadOptions() {
  chrome.storage.sync.get(defaults, (items) => {
    document.getElementById('autoCapture').checked = items.autoCapture;
    document.getElementById('cancelOriginal').checked = items.cancelOriginal;
  });
}

function saveOptions() {
  const autoCapture = document.getElementById('autoCapture').checked;
  const cancelOriginal = document.getElementById('cancelOriginal').checked;
  chrome.storage.sync.set({ autoCapture, cancelOriginal });
}

document.addEventListener('DOMContentLoaded', () => {
  loadOptions();
  document.getElementById('autoCapture').addEventListener('change', saveOptions);
  document.getElementById('cancelOriginal').addEventListener('change', saveOptions);
});
