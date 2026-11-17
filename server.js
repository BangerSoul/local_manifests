import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

const manifest = await readFile(new URL('./TB311FU.xml', import.meta.url));
const home = Buffer.from(`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>TB311FU local manifest</title>
  </head>
  <body>
    <main>
      <h1>Lenovo TB311FU local manifest</h1>
      <p><a href="/TB311FU.xml">View or download the manifest</a></p>
    </main>
  </body>
</html>`, 'utf8');

createServer((request, response) => {
  const method = request.method ?? 'GET';
  if (method !== 'GET' && method !== 'HEAD') {
    response.writeHead(405, { allow: 'GET, HEAD' }).end();
    return;
  }

  const path = new URL(request.url ?? '/', 'http://localhost').pathname;
  const result = path === '/health'
    ? { status: 200, type: 'application/json; charset=utf-8', body: Buffer.from('{"status":"ok"}') }
    : path === '/'
      ? { status: 200, type: 'text/html; charset=utf-8', body: home }
      : path === '/TB311FU.xml'
        ? { status: 200, type: 'application/xml; charset=utf-8', body: manifest }
        : { status: 404, type: 'text/plain; charset=utf-8', body: Buffer.from('Not found\n') };

  response.writeHead(result.status, {
    'content-type': result.type,
    'content-length': result.body.length,
    'x-content-type-options': 'nosniff'
  });
  response.end(method === 'HEAD' ? undefined : result.body);
}).listen(Number(process.env.PORT || 3000), '0.0.0.0');
