// BLOCKLAND server: serves the site AND runs the WebSocket multiplayer rooms.
// Env (optional): PORT, SUPABASE_URL, SUPABASE_ANON_KEY
const http = require("http"), fs = require("fs"), path = require("path");
const { WebSocketServer } = require("ws");
const PORT = process.env.PORT || 8080;

const srv = http.createServer((q, s) => {
  const css = q.url.split("?")[0] === "/style.css";
  fs.readFile(path.join(__dirname, css ? "style.css" : "index.html"), "utf8", (e, d) => {
    if (e) { s.writeHead(404); return s.end("Not found"); }
    if (!css) {
      const proto = q.headers["x-forwarded-proto"] === "https" ? "wss://" : "ws://";
      d = d.replace('const WS_URL="";', "const WS_URL=" + JSON.stringify(proto + q.headers.host) + ";")
           .replace('const SB_URL="",SB_KEY="";', "const SB_URL=" + JSON.stringify(process.env.SUPABASE_URL || "") + ",SB_KEY=" + JSON.stringify(process.env.SUPABASE_ANON_KEY || "") + ";");
    }
    s.writeHead(200, { "Content-Type": css ? "text/css" : "text/html; charset=utf-8" });
    s.end(d);
  });
});

const wss = new WebSocketServer({ server: srv, maxPayload: 4096 });
const rooms = new Map(); let next = 1;
const send = (w, m) => w.readyState === 1 && w.send(JSON.stringify(m));
const ok = (v, lim) => Number.isFinite(v) && Math.abs(v) < lim;

wss.on("connection", ws => {
  ws.id = next++; ws.room = null; ws.lastChat = 0;
  ws.on("message", raw => {
    let m; try { m = JSON.parse(raw); } catch { return; }
    if (m.t === "join" && !ws.room) {
      const name = String(m.room || "lobby").slice(0, 40);
      if (!rooms.has(name)) rooms.set(name, new Set());
      const R = rooms.get(name);
      if (R.size >= 20) return send(ws, { t: "full" });
      ws.room = name; ws.n = String(m.name || "Player").slice(0, 20); ws.a = m.av; ws.s = [0, 5, 0, 0, "idle"];
      R.forEach(o => send(ws, { t: "join", id: o.id, n: o.n, a: o.a }));
      send(ws, { t: "hello", id: ws.id });
      R.add(ws);
      R.forEach(o => o !== ws && send(o, { t: "join", id: ws.id, n: ws.n, a: ws.a }));
    } else if (ws.room && m.t === "pos" && ok(m.x, 1000) && ok(m.y, 1000) && ok(m.z, 1000) && ok(m.r, 10)) {
      ws.s = [m.x, m.y, m.z, m.r, String(m.s).slice(0, 6)];
    } else if (ws.room && m.t === "chat" && Date.now() - ws.lastChat > 500) {
      ws.lastChat = Date.now();
      const msg = String(m.m || "").slice(0, 100);
      rooms.get(ws.room).forEach(o => send(o, { t: "chat", n: ws.n, m: msg }));
    }
  });
  ws.on("close", () => {
    const R = rooms.get(ws.room); if (!R) return;
    R.delete(ws); R.forEach(o => send(o, { t: "leave", id: ws.id, n: ws.n }));
    if (!R.size) rooms.delete(ws.room);
  });
});

// Server-held state: broadcast one snapshot per room, 10 times a second.
setInterval(() => rooms.forEach(R => {
  const p = [...R].map(o => [o.id, ...o.s]);
  R.forEach(o => send(o, { t: "snap", p }));
}), 100);

srv.listen(PORT, () => console.log("BLOCKLAND running on http://localhost:" + PORT));
