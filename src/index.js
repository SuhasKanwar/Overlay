const { app, BrowserWindow, globalShortcut, ipcMain, screen } = require('electron');
const path = require('node:path');

require('dotenv').config();

const GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions';
const GROQ_VISION_MODEL = 'llama-3.2-11b-vision-preview';
const GROQ_TEXT_MODEL = 'llama-3.3-70b-versatile';

const SHORTCUT_TOGGLE = 'CommandOrControl+Shift+Alt+O';
const SHORTCUT_SCAN = 'CommandOrControl+Shift+Alt+S';

const TEXT_SYSTEM_PROMPT =
  'Give ONLY the direct answer. MCQ: option letter + one short reason. Math/logic: final answer only. No greetings.';

const VISION_EXTRACT_PROMPT =
  'Extract the question(s) visible in this screenshot as plain text. Keep it short, readable, and only include the problem statement and options (if any). Do not answer.';

const TEXT_ANSWER_PROMPT_PREFIX =
  'Answer the extracted question(s) below. If MCQ: return only the option letter and one short reason. If math/logic: return only the final answer.';

app.commandLine.appendSwitch('disable-gpu');
app.commandLine.appendSwitch('disable-software-rasterizer');
app.commandLine.appendSwitch('force-color-profile', 'srgb');
app.commandLine.appendSwitch('disable-features', 'ColorCorrectRendering,GpuProcessHighPriority');
app.commandLine.appendSwitch('use-angle', 'gl');
app.commandLine.appendSwitch('disable-direct-composition');

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) app.quit();
else {
  app.on('second-instance', () => {
    if (!mainWindow) return;
    showOverlay();
  });
}

if (require('electron-squirrel-startup')) app.quit();

let mainWindow;
let isProcessing = false;

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function showOverlay() {
  if (!mainWindow) return;
  mainWindow.showInactive();
  mainWindow.setAlwaysOnTop(true, 'screen-saver');
}

function hideOverlay() {
  if (!mainWindow) return;
  mainWindow.hide();
}

function setStatus(msg) {
  if (!mainWindow) return;
  mainWindow.webContents.send('status-update', msg);
}

function setAnswer(msg) {
  if (!mainWindow) return;
  mainWindow.webContents.send('groq-answer', msg);
}

function setError(msg) {
  if (!mainWindow) return;
  mainWindow.webContents.send('groq-error', msg);
}

function createWindow() {
  const { width: screenW, height: screenH } = screen.getPrimaryDisplay().workAreaSize;

  mainWindow = new BrowserWindow({
    width: 420,
    height: 650,
    x: Math.max(0, screenW - 440),
    y: Math.max(0, screenH - 670),
    resizable: false,
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    skipTaskbar: true,
    hasShadow: false,
    backgroundColor: '#00000000',
    webPreferences: {
      contextIsolation: false,
      nodeIntegration: true,
      sandbox: false
    }
  });

  mainWindow.loadFile(path.join(__dirname, 'index.html'));
  mainWindow.setMenuBarVisibility(false);
  mainWindow.setContentProtection(true);
}

async function groqChatCompletion(body) {
  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) throw new Error('Missing GROQ_API_KEY (set it in .env)');

  const res = await fetch(GROQ_API_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Groq ${res.status}: ${text.slice(0, 200)}`);
  }

  const data = await res.json();
  return data;
}

async function groqMessageContent(body) {
  const data = await groqChatCompletion(body);
  const content = data?.choices?.[0]?.message?.content;
  const text = typeof content === 'string' ? content.trim() : '';
  return text || '';
}

async function extractTextFromScreenshot(base64Jpeg) {
  const extracted = await groqMessageContent({
    model: GROQ_VISION_MODEL,
    messages: [
      {
        role: 'user',
        content: [
          { type: 'text', text: VISION_EXTRACT_PROMPT },
          {
            type: 'image_url',
            image_url: { url: `data:image/jpeg;base64,${base64Jpeg}` }
          }
        ]
      }
    ],
    temperature: 0.2,
    max_tokens: 1024
  });

  return extracted || '(No text extracted)';
}

async function answerFromExtractedText(extractedText) {
  const prompt = `${TEXT_ANSWER_PROMPT_PREFIX}\n\n${extractedText}`;
  const answer = await groqMessageContent({
    model: GROQ_TEXT_MODEL,
    messages: [
      { role: 'system', content: TEXT_SYSTEM_PROMPT },
      { role: 'user', content: prompt }
    ],
    temperature: 0.2,
    max_tokens: 512
  });

  return answer || '(No answer returned)';
}

async function startCapture() {
  if (!mainWindow || isProcessing) return;
  isProcessing = true;

  const wasVisible = mainWindow.isVisible();
  try {
    if (wasVisible) {
      hideOverlay();
      await delay(150);
    }

    const display = screen.getPrimaryDisplay();
    const req = {
      displayId: String(display.id),
      thumbnailSize: {
        width: Math.min(display.size.width, 1920),
        height: Math.min(display.size.height, 1080)
      }
    };

    setStatus('Capturing…');
    mainWindow.webContents.send('perform-capture', req);

    const startedAt = Date.now();
    const timeoutMs = 12000;
    const timer = setInterval(() => {
      if (!isProcessing) {
        clearInterval(timer);
        return;
      }
      if (Date.now() - startedAt > timeoutMs) {
        clearInterval(timer);
        isProcessing = false;
        showOverlay();
        setStatus('Error');
        setError('Capture timed out');
      }
    }, 300);
  } catch (e) {
    showOverlay();
    setStatus('Error');
    setError(e?.message || String(e));
    isProcessing = false;
  }
}

ipcMain.on('window-minimize', () => {
  if (mainWindow) mainWindow.minimize();
});

ipcMain.on('window-close', () => {
  if (mainWindow) mainWindow.close();
});

ipcMain.on('trigger-scan', () => {
  startCapture();
});

ipcMain.on('capture-result', async (_, payload) => {
  try {
    showOverlay();

    if (!payload?.ok) {
      setStatus('Error');
      setError(payload?.error || 'Capture failed');
      return;
    }

    setStatus('Extracting…');
    const extracted = await extractTextFromScreenshot(payload.base64);
    mainWindow.webContents.send('scan-source', extracted);

    setStatus('Answering…');
    const answer = await answerFromExtractedText(extracted);
    setAnswer(answer);
    setStatus('Ready');
  } catch (e) {
    setStatus('Error');
    setError(e?.message || String(e));
  } finally {
    isProcessing = false;
  }
});

ipcMain.on('ask-text', async (_, text) => {
  try {
    const cleaned = String(text ?? '').trim();
    if (!cleaned) return;
    setStatus('Thinking…');
    const answer = await groqMessageContent({
      model: GROQ_TEXT_MODEL,
      messages: [
        { role: 'system', content: TEXT_SYSTEM_PROMPT },
        { role: 'user', content: cleaned }
      ],
      temperature: 0.2,
      max_tokens: 512
    });
    setAnswer(answer || '(No answer returned)');
    setStatus('Ready');
  } catch (e) {
    setStatus('Error');
    setError(e?.message || String(e));
  }
});

app.whenReady().then(() => {
  createWindow();

  const okToggle = globalShortcut.register(SHORTCUT_TOGGLE, () => {
    if (!mainWindow) return;
    if (mainWindow.isVisible()) hideOverlay();
    else showOverlay();
  });

  const okScan = globalShortcut.register(SHORTCUT_SCAN, () => startCapture());

  if (!okToggle || !okScan) {
    setStatus('Error');
    setError('Failed to register global shortcuts');
  }

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});