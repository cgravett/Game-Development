'use strict';
const { app, BrowserWindow, Menu, shell, dialog, session } = require('electron');
const path = require('node:path');
const SITE = 'https://worldbound-explorer.grantexec-0223.chatgpt.site';
const trustedHosts = new Set([new URL(SITE).hostname]);
const isTrusted = value => { try { const u = new URL(value); return u.protocol === 'https:' && trustedHosts.has(u.hostname); } catch { return false; } };
let main;
app.setName('Worldbound');
app.setAppUserModelId('com.worldbound.desktop');
app.enableSandbox();
const preferences = { nodeIntegration:false, contextIsolation:true, sandbox:true, webSecurity:true, allowRunningInsecureContent:false, partition:'persist:worldbound' };
async function offerBrowser(url) {
  let parsed; try { parsed = new URL(url); } catch { return; }
  if (parsed.protocol !== 'https:') return;
  const {response} = await dialog.showMessageBox({type:'question',title:'Open your browser?',message:`Open ${parsed.hostname} in your browser?`,buttons:['Cancel','Open browser'],defaultId:0,cancelId:0});
  if (response === 1) shell.openExternal(parsed.href);
}
function guard(contents) {
  contents.on('will-attach-webview', e => e.preventDefault());
  contents.on('will-navigate', (event,url) => { if (!isTrusted(url)) { event.preventDefault(); offerBrowser(url); } });
  contents.on('will-redirect', (event,url) => { if (!isTrusted(url)) { event.preventDefault(); offerBrowser(url); } });
  contents.setWindowOpenHandler(({url}) => {
    if (!isTrusted(url)) { offerBrowser(url); return {action:'deny'}; }
    return {action:'allow',overrideBrowserWindowOptions:{width:1000,height:780,autoHideMenuBar:true,webPreferences:preferences}};
  });
  contents.on('did-create-window', popup => guard(popup.webContents));
}
function loadGame() { if (main && !main.isDestroyed()) main.loadURL(SITE).catch(()=>{}); }
function createWindow() {
  main = new BrowserWindow({title:'Worldbound',width:1440,height:920,minWidth:800,minHeight:600,backgroundColor:'#17122e',show:false,webPreferences:preferences});
  guard(main.webContents);
  main.once('ready-to-show',()=>main.show());
  main.webContents.on('page-title-updated',event=>{event.preventDefault();main.setTitle('Worldbound');});
  main.webContents.on('did-fail-load',(_event,code,_description,_url,isMainFrame)=>{
    if (!isMainFrame || code===-3) return;
    main.loadFile(path.join(__dirname,'connection.html')).catch(()=>{});
    main.show();
  });
  loadGame();
}
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance',()=>{if(main){if(main.isMinimized())main.restore();main.show();main.focus();}});
  app.whenReady().then(()=>{
    const s=session.fromPartition('persist:worldbound');
    s.setPermissionRequestHandler((_contents,_permission,callback)=>callback(false));
    s.setPermissionCheckHandler(()=>false);
    s.on('will-download',event=>event.preventDefault());
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      {label:'Game',submenu:[{label:'Open Worldbound / Retry connection',accelerator:'CmdOrCtrl+R',click:loadGame},{label:'Open in browser',click:()=>shell.openExternal(SITE)},{type:'separator'},{role:'quit'}]},
      {label:'View',submenu:[{role:'togglefullscreen',accelerator:'F11'},{role:'resetZoom'},{role:'zoomIn'},{role:'zoomOut'}]},
      {label:'Help',submenu:[{label:'About Worldbound',click:()=>dialog.showMessageBox({title:'Worldbound',message:'Worldbound for Windows',detail:'Launch and play — no ChatGPT account or sign-in required. Internet is required for the game and Google Street View. Game updates load automatically. This desktop runtime does not update automatically.'})}]}
    ]));
    createWindow();
  });
  app.on('window-all-closed',()=>app.quit());
}
