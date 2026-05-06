const chat = document.getElementById('chat');
const input = document.getElementById('input');
const statusLabel = document.getElementById('statusLabel');
const btnScan = document.getElementById('btnScan');
const btnSend = document.getElementById('btnSend');
const btnMin = document.getElementById('btnMin');
const btnClose = document.getElementById('btnClose');

const { ipcRenderer, desktopCapturer } = require('electron');
const { marked } = require('marked');
const hljs = require('highlight.js');

marked.setOptions({
  breaks: true,
  gfm: true
});

function renderMarkdown(text) {
  const src = typeof text === 'string' ? text : String(text ?? '');
  return marked.parse(src, {
    highlight(code, lang) {
      const language = lang && hljs.getLanguage(lang) ? lang : null;
      if (language) return hljs.highlight(code, { language }).value;
      return hljs.highlightAuto(code).value;
    }
  });
}

let isBusy = false;

function setStatus(msg) {
  statusLabel.textContent = msg || '';
}

function addMsg(text, sender, extraClass = '') {
  const div = document.createElement('div');
  div.className = `msg ${sender} ${extraClass}`.trim();
  chat.appendChild(div);
  if (sender === 'user') {
    div.textContent = text;
  } else {
    const html = renderMarkdown(String(text ?? ''));
    div.innerHTML = html || '';
  }
  chat.scrollTop = chat.scrollHeight;
  return div;
}

function setBusy(nextBusy) {
  isBusy = nextBusy;
  input.disabled = nextBusy;
  btnSend.disabled = nextBusy;
  btnScan.disabled = nextBusy;
}

function sendMessage() {
  const text = input.value.trim();
  if (!text || isBusy) return;
  setBusy(true);
  addMsg(text, 'user');
  input.value = '';
  input.style.height = '22px';
  ipcRenderer.send('ask-text', text);
}

function triggerScan() {
  if (isBusy) return;
  setBusy(true);
  addMsg('Screen captured — analyzing…', 'user', 'scan-source');
  ipcRenderer.send('trigger-scan');
}

input.addEventListener('input', () => {
  input.style.height = '22px';
  input.style.height = Math.min(input.scrollHeight, 80) + 'px';
});

input.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendMessage();
  }
});

btnSend.addEventListener('click', sendMessage);
btnScan.addEventListener('click', triggerScan);
btnMin.addEventListener('click', () => ipcRenderer.send('window-minimize'));
btnClose.addEventListener('click', () => ipcRenderer.send('window-close'));

ipcRenderer.on('status-update', (_, msg) => {
  setStatus(msg || '');
});

ipcRenderer.on('scan-source', (_, msg) => {
  if (msg) addMsg(String(msg), 'bot', 'scan-source');
});

ipcRenderer.on('groq-answer', (_, msg) => {
  addMsg(String(msg ?? ''), 'bot');
  setBusy(false);
});

ipcRenderer.on('groq-error', (_, msg) => {
  addMsg(`⚠️ ${String(msg ?? '')}`, 'bot');
  setBusy(false);
});

async function captureScreen({ displayId, thumbnailSize }) {
  if (!desktopCapturer) throw new Error('desktopCapturer unavailable');

  const sources = await desktopCapturer.getSources({
    types: ['screen'],
    thumbnailSize: thumbnailSize || { width: 1920, height: 1080 }
  });

  const source =
    sources.find((s) => String(s.display_id) === String(displayId)) ||
    sources.find((s) => s.id && String(s.id).includes('screen')) ||
    sources[0];

  if (!source) throw new Error('No screen source found');
  const jpeg = source.thumbnail.toJPEG(75);
  return jpeg.toString('base64');
}

ipcRenderer.on('perform-capture', async (_, req) => {
  try {
    const base64 = await captureScreen(req || {});
    ipcRenderer.send('capture-result', { ok: true, base64 });
  } catch (e) {
    ipcRenderer.send('capture-result', { ok: false, error: e?.message || String(e) });
  }
});

setStatus('Ready');
