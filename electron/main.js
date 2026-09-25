'use strict';

const { app, BrowserWindow, shell, Menu } = require('electron');
const path = require('path');

// Только одно окно приложения
if (!app.requestSingleInstanceLock()) {
  app.quit();
}

let win = null;

function createWindow() {
  win = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 380,
    minHeight: 560,
    title: 'Расписание уроков',
    icon: path.join(__dirname, '..', 'www', 'icon.png'),
    backgroundColor: '#f2f2f7',
    autoHideMenuBar: true,
    show: false,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false,
    },
  });

  Menu.setApplicationMenu(null);
  win.loadFile(path.join(__dirname, '..', 'www', 'index.html'));
  win.once('ready-to-show', () => win.show());

  // Внешние ссылки — в браузере, а не внутри приложения
  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  win.on('closed', () => { win = null; });
}

app.on('second-instance', () => {
  if (win) {
    if (win.isMinimized()) win.restore();
    win.focus();
  }
});

app.whenReady().then(createWindow);

app.on('window-all-closed', () => app.quit());
