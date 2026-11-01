// Local stand-in for Supabase: serves the site and maps /rest/v1/rpc/<fn> to the SQL function, run as role anon.
const http = require("http"), fs = require("fs"), path = require("path"), { Pool } = require("pg");
const ROOT = path.resolve(process.argv[2] || ".."), PORT = 8787;
const pool = new Pool({ host: "localhost", port: 54329, user: "postgres", database: "postgres" });
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8" };
http.createServer(async (req, res) => {
  const m = req.url.match(/^\/rest\/v1\/rpc\/([a-z_]+)$/);
  if (m && req.method === "POST") {
    let body = ""; for await (const c of req) body += c;
    const args = body ? JSON.parse(body) : {};
    const keys = Object.keys(args).filter(k => /^p_[a-z_]+$/.test(k));
    const vals = keys.map(k => (args[k] && typeof args[k] === "object" && !Array.isArray(args[k])) ? JSON.stringify(args[k]) : args[k]);
    const sql = `select public.${m[1]}(${keys.map((k, i) => `${k} => $${i + 1}`).join(", ")}) as r`;
    const client = await pool.connect();
    try {
      await client.query("set role anon");
      const out = await client.query(sql, vals);
      res.writeHead(200, { "Content-Type": "application/json" }); res.end(JSON.stringify(out.rows[0].r));
    } catch (e) {
      res.writeHead(400, { "Content-Type": "application/json" }); res.end(JSON.stringify({ message: e.message }));
    } finally { await client.query("reset role").catch(() => {}); client.release(); }
    return;
  }
  let p = decodeURIComponent(req.url.split("?")[0]); if (p === "/") p = "/index.html";
  if (p === "/config.js") { res.writeHead(200, { "Content-Type": types[".js"] }); return res.end(`window.WICHTEL_CONFIG={supabaseUrl:"http://localhost:${PORT}",supabaseKey:"local-dev"};`); }
  const f = path.join(ROOT, path.normalize(p));
  if (!f.startsWith(path.resolve(ROOT)) || !fs.existsSync(f)) { res.writeHead(404); return res.end("not found"); }
  res.writeHead(200, { "Content-Type": types[path.extname(f)] || "application/octet-stream" }); fs.createReadStream(f).pipe(res);
}).listen(PORT, () => console.log("http://localhost:" + PORT));
