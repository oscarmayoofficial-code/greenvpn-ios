// Green VPN desktop renderer — location list from the same /api/servers, connect
// drives sing-box (full-device TUN) via the preload IPC bridge.
const API = "https://green-vpn.app/api/servers";
const UPGRADE_FALLBACK = "https://green-vpn.app/vpn-pro";
const OBF_KEY = "GrnV!2026#px";
// deobfuscate the server-sent "px" (base64(XOR(user:pass))) -> {u,p}. Lets creds
// rotate server-side without a new exe (matches app/extension).
function deobfPx(b64) {
  try {
    const raw = atob(b64); let out = "";
    for (let i = 0; i < raw.length; i++) out += String.fromCharCode(raw.charCodeAt(i) ^ OBF_KEY.charCodeAt(i % OBF_KEY.length));
    const s = out.indexOf(":"); if (s > 0) return { u: out.slice(0, s), p: out.slice(s + 1) };
  } catch (e) {}
  return null;
}
let PROXY_CREDS = null;   // {u,p} from /api/servers px

const FLAGS = {
  de: '<svg viewBox="0 0 5 3"><rect width="5" height="3" fill="#FFCE00"/><rect width="5" height="2" fill="#D00"/><rect width="5" height="1" fill="#000"/></svg>',
  it: '<svg viewBox="0 0 3 2"><rect width="3" height="2" fill="#fff"/><rect width="1" height="2" fill="#009246"/><rect x="2" width="1" height="2" fill="#CE2B37"/></svg>',
  us: '<svg viewBox="0 0 7 4"><rect width="7" height="4" fill="#fff"/><g fill="#B22234"><rect width="7" height=".4"/><rect width="7" height=".4" y=".8"/><rect width="7" height=".4" y="1.6"/><rect width="7" height=".4" y="2.4"/><rect width="7" height=".4" y="3.2"/></g><rect width="3" height="2.2" fill="#3C3B6E"/></svg>',
  gb: '<svg viewBox="0 0 60 30"><rect width="60" height="30" fill="#012169"/><path d="M0,0 60,30 M60,0 0,30" stroke="#fff" stroke-width="6"/><path d="M0,0 60,30 M60,0 0,30" stroke="#C8102E" stroke-width="3"/><path d="M30,0 V30 M0,15 H60" stroke="#fff" stroke-width="10"/><path d="M30,0 V30 M0,15 H60" stroke="#C8102E" stroke-width="6"/></svg>',
  pk: '<svg viewBox="0 0 45 30"><rect width="45" height="30" fill="#01411C"/><rect width="11.25" height="30" fill="#fff"/><circle cx="26" cy="15" r="7" fill="#fff"/><circle cx="29" cy="15" r="6" fill="#01411C"/></svg>',
  in: '<svg viewBox="0 0 9 6"><rect width="9" height="6" fill="#fff"/><rect width="9" height="2" fill="#F93"/><rect width="9" height="2" y="4" fill="#138808"/><circle cx="4.5" cy="3" r=".85" fill="none" stroke="#008" stroke-width=".18"/></svg>',
  ph: '<svg viewBox="0 0 4 2"><rect width="4" height="1" fill="#0038A8"/><rect width="4" height="1" y="1" fill="#CE1126"/><path d="M0,0 L1.15,1 L0,2 Z" fill="#fff"/></svg>',
  es: '<svg viewBox="0 0 3 2"><rect width="3" height="2" fill="#AA151B"/><rect width="3" height="1" y=".5" fill="#F1BF00"/></svg>',
  fr: '<svg viewBox="0 0 3 2"><rect width="3" height="2" fill="#fff"/><rect width="1" height="2" fill="#0055A4"/><rect x="2" width="1" height="2" fill="#EF4135"/></svg>',
  nl: '<svg viewBox="0 0 3 2"><rect width="3" height="2" fill="#21468B"/><rect width="3" height="1.333" fill="#fff"/><rect width="3" height=".667" fill="#AE1C28"/></svg>',
  ca: '<svg viewBox="0 0 24 12"><rect width="24" height="12" fill="#fff"/><rect width="6" height="12" fill="#D52B1E"/><rect x="18" width="6" height="12" fill="#D52B1E"/><path d="M12 2.5l1 2.2 2.4-.5-1.4 1.9 1.4 1.2-2.2.3.2 2.4-1.4-1.1-1.4 1.1.2-2.4-2.2-.3 1.4-1.2-1.4-1.9 2.4.5z" fill="#D52B1E"/></svg>',
  au: '<svg viewBox="0 0 24 12"><rect width="24" height="12" fill="#00247D"/><path d="M0,0 12,6 M12,0 0,6" stroke="#fff" stroke-width="1.4"/><path d="M6,0 V6 M0,3 H12" stroke="#fff" stroke-width="2"/><path d="M6,0 V6 M0,3 H12" stroke="#CF142B" stroke-width="1"/></svg>',
  jp: '<svg viewBox="0 0 3 2"><rect width="3" height="2" fill="#fff"/><circle cx="1.5" cy="1" r=".6" fill="#BC002D"/></svg>',
  sg: '<svg viewBox="0 0 12 8"><rect width="12" height="8" fill="#fff"/><rect width="12" height="4" fill="#EF3340"/><circle cx="2.8" cy="2" r="1.4" fill="#fff"/><circle cx="3.5" cy="2" r="1.15" fill="#EF3340"/></svg>',
  ae: '<svg viewBox="0 0 12 6"><rect width="12" height="2" fill="#00732F"/><rect width="12" height="2" y="2" fill="#fff"/><rect width="12" height="2" y="4" fill="#000"/><rect width="3" height="6" fill="#FF0000"/></svg>',
  tr: '<svg viewBox="0 0 12 8"><rect width="12" height="8" fill="#E30A17"/><circle cx="4.8" cy="4" r="2" fill="#fff"/><circle cx="5.5" cy="4" r="1.6" fill="#E30A17"/></svg>',
  kr: '<svg viewBox="0 0 12 8"><rect width="12" height="8" fill="#fff"/><circle cx="6" cy="4" r="1.6" fill="#C60C30"/><path d="M4.4 4a1.6 1.6 0 0 0 3.2 0z" fill="#003478"/></svg>',
  hk: '<svg viewBox="0 0 12 8"><rect width="12" height="8" fill="#DE2910"/><circle cx="6" cy="4" r="1.7" fill="#fff"/><circle cx="6" cy="4" r="1.2" fill="#DE2910"/></svg>',
  br: '<svg viewBox="0 0 14 10"><rect width="14" height="10" fill="#009C3B"/><path d="M7 1.2 12.8 5 7 8.8 1.2 5Z" fill="#FFDF00"/><circle cx="7" cy="5" r="1.9" fill="#002776"/></svg>',
  se: '<svg viewBox="0 0 16 10"><rect width="16" height="10" fill="#006AA7"/><rect x="5" width="2" height="10" fill="#FECC00"/><rect y="4" width="16" height="2" fill="#FECC00"/></svg>',
  ch: '<svg viewBox="0 0 32 32"><rect width="32" height="32" fill="#D52B1E"/><rect x="13" y="6" width="6" height="20" fill="#fff"/><rect x="6" y="13" width="20" height="6" fill="#fff"/></svg>',
  pl: '<svg viewBox="0 0 8 5"><rect width="8" height="5" fill="#DC143C"/><rect width="8" height="2.5" fill="#fff"/></svg>',
  id: '<svg viewBox="0 0 3 2"><rect width="3" height="2" fill="#fff"/><rect width="3" height="1" fill="#CE1126"/></svg>',
  sa: '<svg viewBox="0 0 12 8"><rect width="12" height="8" fill="#165D31"/><rect x="2" y="5" width="8" height=".7" fill="#fff"/><rect x="3" y="2.7" width="6" height="1.1" rx=".3" fill="#fff"/></svg>',
  my: '<svg viewBox="0 0 14 8"><rect width="14" height="8" fill="#CC0001"/><g fill="#fff"><rect y="1.14" width="14" height="1.14"/><rect y="3.43" width="14" height="1.14"/><rect y="5.71" width="14" height="1.14"/></g><rect width="7" height="4.57" fill="#010066"/><circle cx="3" cy="2.3" r="1.2" fill="#FFCC00"/><circle cx="3.6" cy="2.3" r="1" fill="#010066"/></svg>',
  no: '<svg viewBox="0 0 22 16"><rect width="22" height="16" fill="#BA0C2F"/><rect x="6" width="4" height="16" fill="#fff"/><rect y="6" width="22" height="4" fill="#fff"/><rect x="7" width="2" height="16" fill="#00205B"/><rect y="7" width="22" height="2" fill="#00205B"/></svg>',
  pt: '<svg viewBox="0 0 30 20"><rect width="30" height="20" fill="#DA291C"/><rect width="12" height="20" fill="#046A38"/><circle cx="12" cy="10" r="3" fill="#FFE900"/><circle cx="12" cy="10" r="2" fill="#DA291C"/></svg>',
  nz: '<svg viewBox="0 0 24 12"><rect width="24" height="12" fill="#00247D"/><path d="M0,0 12,6 M12,0 0,6" stroke="#fff" stroke-width="1.4"/><path d="M6,0 V6 M0,3 H12" stroke="#fff" stroke-width="2"/><path d="M6,0 V6 M0,3 H12" stroke="#CC142B" stroke-width="1"/></svg>',
  auto: '<svg viewBox="0 0 22 15"><rect width="22" height="15" rx="2" fill="#12331f"/><path d="M12 2 L7 8.5 h3 l-1 4.5 6-7.5 h-3.2 z" fill="#2FE84A"/></svg>',
};
function flagHTML(cc) {
  const f = FLAGS[cc] || ('<span style="font:700 8px Segoe UI;color:#9fb0a8">' + String(cc || "").toUpperCase() + "</span>");
  return '<span class="flag">' + f + "</span>";
}
function barsLvl(mbps) { return mbps >= 150 ? 4 : mbps >= 60 ? 3 : mbps >= 20 ? 2 : 1; }
function barsHTML(l) { return '<span class="bars l' + l + '"><i></i><i></i><i></i><i></i></span>'; }

const $ = (id) => document.getElementById(id);
const orb = $("orb"), stateEl = $("state"), timerEl = $("timer"), toggle = $("toggle");
const drop = $("drop"), dropSel = $("dropSel"), dropList = $("dropList");

let LOCATIONS = [], SIG = {}, currentId = null, proxyHost = "", userPro = true;
let connected = false, connecting = false, tStart = 0, tHandle = null;

function getIid() {
  let id = localStorage.getItem("iid");
  if (!id) { id = (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2)); localStorage.setItem("iid", id); }
  return id;
}
function cur() { return LOCATIONS.find((l) => l.id === currentId) || LOCATIONS[0]; }

async function loadServers() {
  try {
    const r = await fetch(API + "?iid=" + encodeURIComponent(getIid()) + "&src=pc&ft=1", { cache: "no-store" });
    const d = await r.json();
    proxyHost = d.proxy_host || proxyHost;
    userPro = !!d.pro;
    if (d.px) { const c = deobfPx(d.px); if (c) { PROXY_CREDS = c; localStorage.setItem("pxCreds", JSON.stringify(c)); } }
    LOCATIONS = (d.servers || []).filter((s) => s.socks_port).map((s) => ({
      id: s.id, name: s.name, city: s.city, cc: s.cc || "", port: s.socks_port, pro: !!s.pro,
      // direct-dial (USA/Finland live on the EU box): dial dhost:dsport (its own SOCKS) instead
      // of the global relay. Empty/0 -> fall back to proxyHost:socks_port.
      dhost: s.dhost || "", dsport: Number(s.dsport || 0),
    }));
    SIG = {}; (d.servers || []).forEach((s) => (SIG[s.id] = barsLvl(s.mbps || 0)));
    if (!currentId || !LOCATIONS.some((l) => l.id === currentId)) currentId = (LOCATIONS[0] || {}).id;
    renderSel(); renderList();
    localStorage.setItem("locCache", JSON.stringify({ LOCATIONS, proxyHost }));
  } catch (e) {
    const c = JSON.parse(localStorage.getItem("locCache") || "null");
    if (c) { LOCATIONS = c.LOCATIONS; proxyHost = c.proxyHost; currentId = currentId || (LOCATIONS[0] || {}).id; renderSel(); renderList(); }
  }
}
function renderSel() {
  const l = cur(); if (!l) return;
  dropSel.querySelector(".dsel-main").innerHTML = flagHTML(l.cc) + "<span>" + l.name + " · " + l.city + "</span>";
}
function renderList() {
  dropList.innerHTML = "";
  LOCATIONS.forEach((l) => {
    const locked = l.pro && !userPro;
    const row = document.createElement("div");
    row.className = "drop-row" + (l.id === currentId ? " sel" : "") + (locked ? " locked" : "");
    const badge = locked ? '<span class="drow-lock">PRO</span>' : "";
    row.innerHTML = flagHTML(l.cc) + '<span class="drow-txt"><div class="drow-name">' + l.name + '</div><div class="drow-city">' + l.city + "</div></span>" + badge + barsHTML(SIG[l.id] || 3);
    row.addEventListener("click", () => { dropList.classList.remove("open"); choose(l.id); });
    dropList.appendChild(row);
  });
}
function choose(id) {
  const l = LOCATIONS.find((x) => x.id === id); if (!l) return;
  if (l.pro && !userPro) { window.gvpn.openExternal(UPGRADE_FALLBACK + "?iid=" + encodeURIComponent(getIid()) + "&src=pc"); return; }
  currentId = id; renderSel(); renderList();
  if (connected) doConnect();   // switch server live
}

dropSel.addEventListener("click", () => dropList.classList.toggle("open"));
document.addEventListener("click", (e) => { if (!drop.contains(e.target)) dropList.classList.remove("open"); });

function paint(st) {
  orb.className = "orb " + st; stateEl.className = "state " + st;
  if (st === "on") { stateEl.textContent = "CONNECTED"; toggle.className = "btn on"; toggle.textContent = "Disconnect"; }
  else if (st === "connecting") { stateEl.textContent = "CONNECTING…"; toggle.className = "btn off busy"; toggle.textContent = "Connecting…"; }
  else { stateEl.textContent = "NOT CONNECTED"; toggle.className = "btn off"; toggle.textContent = "Connect"; }
}
function startTimer() { tStart = Date.now(); tHandle = setInterval(() => {
  const s = Math.floor((Date.now() - tStart) / 1000);
  timerEl.textContent = String(Math.floor(s / 3600)).padStart(2, "0") + ":" + String(Math.floor(s / 60) % 60).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0");
}, 1000); }
function stopTimer() { clearInterval(tHandle); timerEl.textContent = ""; }

async function doConnect() {
  const l = cur(); if (!l) return;
  if (l.pro && !userPro) { window.gvpn.openExternal(UPGRADE_FALLBACK + "?iid=" + encodeURIComponent(getIid()) + "&src=pc"); return; }
  connecting = true; paint("connecting"); startProgress();
  // direct-dial for locations carrying dhost/dsport (USA cities + Finland on the EU box)
  const direct = !!l.dhost && l.dsport > 0;
  const host = direct ? l.dhost : proxyHost;
  const port = direct ? l.dsport : l.port;
  const creds = PROXY_CREDS || JSON.parse(localStorage.getItem("pxCreds") || "null") || { u: "gvpnpro", p: "GvpnPro2026Zk9" };
  await window.gvpn.connect({ host, port, user: creds.u, pass: creds.p });
}

// ---- connection progress line: fills while securing, hits 100% once data flows ----
let progHandle = null, progVal = 0;
function setProg(p) { progVal = p; const b = $("progBar"); if (b) b.style.width = p + "%"; }
function startProgress() {
  const w = $("progWrap"), t = $("progTxt");
  if (w) w.classList.add("show");
  if (t) t.textContent = "Securing connection…";
  progVal = 0; setProg(5);
  clearInterval(progHandle);
  progHandle = setInterval(() => { if (progVal < 88) setProg(progVal + Math.max(1, (88 - progVal) * 0.07)); }, 200);
}
function finishProgress() {
  clearInterval(progHandle); setProg(100);
  const t = $("progTxt"); if (t) t.textContent = "Connected";
  setTimeout(() => { const w = $("progWrap"); if (w) w.classList.remove("show"); }, 550);
}
function hideProgress() { clearInterval(progHandle); const w = $("progWrap"); if (w) w.classList.remove("show"); setProg(0); }
async function dataCheck() {
  // verify real traffic flows through the freshly-built tunnel, THEN show 100%
  const t = $("progTxt"); if (t) t.textContent = "Verifying…";
  setProg(94);
  try {
    const c = new AbortController(); const to = setTimeout(() => c.abort(), 4000);
    await fetch(API + "?iid=" + encodeURIComponent(getIid()) + "&src=pc&_=" + Date.now(), { cache: "no-store", signal: c.signal });
    clearTimeout(to);
  } catch (e) {}
  connected = true; connecting = false; paint("on"); startTimer(); finishProgress();
}
async function doDisconnect() { await window.gvpn.disconnect(); }

toggle.addEventListener("click", () => { if (connected) doDisconnect(); else if (!connecting) doConnect(); });
orb.addEventListener("click", () => { if (connected) doDisconnect(); else if (!connecting) doConnect(); });

window.gvpn.onStatus((s) => {
  if (s.state === "connected") { dataCheck(); }   // tunnel up -> verify data flow -> 100% -> CONNECTED
  else if (s.state === "disconnected") { connected = false; connecting = false; paint("off"); stopTimer(); hideProgress(); }
  else if (s.state === "error") { connected = false; connecting = false; paint("off"); stopTimer(); hideProgress(); }
});

paint("off");
loadServers();
setInterval(loadServers, 60000);
