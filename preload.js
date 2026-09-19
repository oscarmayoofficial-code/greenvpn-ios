const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("gvpn", {
  connect: (loc) => ipcRenderer.invoke("vpn-connect", loc),
  disconnect: () => ipcRenderer.invoke("vpn-disconnect"),
  openExternal: (url) => ipcRenderer.invoke("open-external", url),
  onStatus: (cb) => ipcRenderer.on("vpn-status", (e, data) => cb(data)),
});
