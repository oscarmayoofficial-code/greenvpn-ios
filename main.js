// Green VPN — Electron main process.
// Full-device VPN: on connect we launch sing-box in TUN mode, routing ALL PC
// traffic through the selected location's SOCKS5 proxy (proxy_host:socks_port).
const { app, BrowserWindow, ipcMain, Tray, Menu, shell } = require("electron");
const path = require("path");
const fs = require("fs");
const os = require("os");
const { spawn } = require("child_process");

// Fallback only — real creds arrive from the renderer (fetched + deobfuscated from
// /api/servers "px", so they rotate server-side without a new exe).
const FALLBACK_USER = "gvpnpro";
const FALLBACK_PASS = "GvpnPro2026Zk9";
let win = null, tray = null, sb = null;

function createWindow() {
  win = new BrowserWindow({
    width: 400, height: 660, resizable: false, maximizable: false,
    title: "Green VPN", backgroundColor: "#0b0e10", show: false,
    icon: path.join(__dirname, "ui", IS_MAC ? "logo.png" : "icon.ico"),
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true },
  });
  win.setMenuBarVisibility(false);
  win.loadFile(path.join(__dirname, "ui", "index.html"));
  win.once("ready-to-show", () => win.show());
  win.on("close", (e) => { if (!app.isQuitting) { e.preventDefault(); win.hide(); } });
}

const IS_MAC = process.platform === "darwin";

function singboxExe() {
  const base = app.isPackaged ? process.resourcesPath : __dirname;
  if (IS_MAC) {
    // arm64 / x64 binaries are both bundled; pick the one for this Mac.
    const arch = process.arch === "arm64" ? "arm64" : "x64";
    return path.join(base, "sing-box-mac", arch, "sing-box");
  }
  return path.join(base, "sing-box", "sing-box.exe");
}

function buildConfig(host, port, user, pass) {
  const cfg = {
    log: { level: "warn" },
    dns: { servers: [{ type: "udp", tag: "remote", server: "1.1.1.1", detour: "proxy" }] },
    inbounds: [{
      type: "tun", tag: "tun-in",
      ...(IS_MAC ? {} : { interface_name: "GreenVPN" }),
      address: ["172.19.0.1/30"], auto_route: true, strict_route: !IS_MAC,
      stack: IS_MAC ? "gvisor" : "system",
    }],
    outbounds: [
      { type: "socks", tag: "proxy", server: host, server_port: Number(port),
        version: "5", username: user || FALLBACK_USER, password: pass || FALLBACK_PASS },
      { type: "direct", tag: "direct" },
    ],
    route: {
      rules: [{ action: "sniff" }, { protocol: "dns", action: "hijack-dns" }],
      final: "proxy", auto_detect_interface: true,
    },
  };
  const p = path.join(os.tmpdir(), "gvpn-singbox.json");
  fs.writeFileSync(p, JSON.stringify(cfg, null, 2));
  return p;
}

const PID_FILE = path.join(os.tmpdir(), "gvpn-singbox.pid");

function stopVpn() {
  if (IS_MAC) {
    // sing-box runs as root on macOS, so a plain kill() from the user process
    // is denied; the root-side wrapper below wrote its pid and stops on SIGTERM
    // delivered through the same elevated shell.
    try {
      const pid = fs.readFileSync(PID_FILE, "utf8").trim();
      if (pid) spawn("osascript", ["-e",
        `do shell script "kill ${pid} 2>/dev/null; rm -f ${PID_FILE}" with administrator privileges`]);
    } catch (e) {}
  }
  if (sb) { try { sb.kill(); } catch (e) {} sb = null; }
}

function startVpn(host, port, user, pass) {
  stopVpn();
  const cfgPath = buildConfig(host, port, user, pass);
  const exe = singboxExe();
  if (!fs.existsSync(exe)) { win.webContents.send("vpn-status", { state: "error", msg: "engine missing" }); return; }
  if (IS_MAC) {
    // Native "Green VPN wants to make changes" dialog; sing-box then runs as root
    // with its pid recorded so Disconnect can stop it from the same elevation.
    const sh = `chmod +x '${exe}'; nohup '${exe}' run -c '${cfgPath}' >/tmp/gvpn-singbox.log 2>&1 & echo $! > ${PID_FILE}`;
    sb = spawn("osascript", ["-e", `do shell script "${sh.replace(/"/g, '\\"')}" with administrator privileges`]);
  } else {
    sb = spawn(exe, ["run", "-c", cfgPath], { windowsHide: true });
  }
  let started = false;
  const ready = () => { if (!started) { started = true; win.webContents.send("vpn-status", { state: "connected" }); } };
  // TUN takes ~1s to come up; report connected shortly after spawn if it didn't crash.
  setTimeout(() => { if (sb) ready(); }, 1500);
  sb.stderr.on("data", (d) => { const s = d.toString(); if (/started|tun/i.test(s)) ready(); });
  sb.on("exit", (code) => {
    sb = null;
    if (IS_MAC && code === 0) return;               // elevated launcher done; tunnel keeps running
    win.webContents.send("vpn-status", { state: IS_MAC ? "error" : "disconnected", code, msg: IS_MAC ? "cancelled" : undefined });
  });
  sb.on("error", () => { sb = null; win.webContents.send("vpn-status", { state: "error", msg: "engine failed" }); });
}

app.on("second-instance", () => { if (win) { win.show(); win.focus(); } });
if (!app.requestSingleInstanceLock()) app.quit();

app.whenReady().then(() => {
  createWindow();
  try {
    tray = new Tray(path.join(__dirname, "ui", IS_MAC ? "tray-mac.png" : "icon.ico"));
    tray.setToolTip("Green VPN");
    tray.setContextMenu(Menu.buildFromTemplate([
      { label: "Open", click: () => { win.show(); win.focus(); } },
      { label: "Quit", click: () => { app.isQuitting = true; stopVpn(); app.quit(); } },
    ]));
    tray.on("click", () => { win.show(); win.focus(); });
  } catch (e) {}
});
app.on("before-quit", () => { app.isQuitting = true; stopVpn(); });
app.on("activate", () => { if (win) { win.show(); win.focus(); } });
app.on("window-all-closed", () => {});

ipcMain.handle("vpn-connect", (e, loc) => { startVpn(loc.host, loc.port, loc.user, loc.pass); return true; });
ipcMain.handle("vpn-disconnect", () => { stopVpn(); win.webContents.send("vpn-status", { state: "disconnected" }); return true; });
ipcMain.handle("open-external", (e, url) => { shell.openExternal(url); });
