import { createReadStream, existsSync } from "node:fs";
import { access } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const websiteRoot = fileURLToPath(new URL(".", import.meta.url));
const distRoot = join(websiteRoot, ".vitepress", "dist");
const port = Number.parseInt(process.env.PORT || "8080", 10);
const comingSoonEnabled = /^(1|true|yes|on)$/i.test(process.env.WEBSITE_COMING_SOON || "");
const siteTitle = "Undercover Agents";
const comingSoonTitle = `${siteTitle} | Coming Soon`;
const siteLogoPath = "/logo.png";

console.log(`[server] websiteRoot: ${websiteRoot}`);
console.log(`[server] distRoot:    ${distRoot}`);
console.log(`[server] dist exists: ${existsSync(distRoot)}`);
console.log(`[server] port:        ${port}`);
console.log(`[server] comingSoon:  ${comingSoonEnabled}`);

const mimeTypes = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".txt": "text/plain; charset=utf-8",
  ".webp": "image/webp",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
};

const isReadableFile = async (filePath) => {
  try {
    await access(filePath);
    return true;
  } catch {
    return false;
  }
};

const isAssetRequest = (requestPath) => {
  const extension = extname(requestPath).toLowerCase();
  return extension.length > 0 && extension !== ".html";
};

const renderComingSoonPage = () => `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>${comingSoonTitle}</title>
    <style>
      :root {
        color-scheme: dark;
        --ua-ink-950: #050813;
        --ua-ink-900: #09101d;
        --ua-sky-400: #8de9ff;
        --ua-cobalt-500: #8ca6ff;
        --ua-text-1: #f4f7ff;
        --ua-text-2: #a7b6d4;
        font-family: "Space Grotesk", "Avenir Next", "Segoe UI", sans-serif;
      }

      * {
        box-sizing: border-box;
      }

      html,
      body {
        min-height: 100%;
        margin: 0;
      }

      body {
        display: grid;
        place-items: center;
        padding: 2rem;
        background:
          radial-gradient(circle at 18% 20%, rgb(141 233 255 / 0.12), transparent 28%),
          radial-gradient(circle at 82% 12%, rgb(140 166 255 / 0.16), transparent 26%),
          linear-gradient(180deg, var(--ua-ink-950) 0%, var(--ua-ink-900) 100%);
        color: var(--ua-text-1);
      }

      main {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 1rem;
        text-align: center;
      }

      img {
        width: clamp(4.5rem, 12vw, 7rem);
        height: auto;
        filter: drop-shadow(0 0 30px rgb(68 210 255 / 0.18));
      }

      h1,
      p {
        margin: 0;
      }

      h1 {
        font-size: clamp(2rem, 5vw, 3.75rem);
        letter-spacing: -0.05em;
      }

      p {
        color: var(--ua-text-2);
        font-size: 0.9rem;
        letter-spacing: 0.32em;
        text-transform: uppercase;
      }

      strong {
        color: var(--ua-sky-400);
        font-weight: 600;
      }
    </style>
  </head>
  <body>
    <main>
      <img src="${siteLogoPath}" alt="${siteTitle} logo">
      <h1>${siteTitle}</h1>
      <p><strong>Coming soon</strong></p>
    </main>
  </body>
</html>`;

const resolvePath = async (requestPath) => {
  const decodedPath = decodeURIComponent(requestPath || "/");
  const safePath = normalize(decodedPath).replace(/^([./\\])+/, "");
  const cleanPath = safePath === "." ? "" : safePath.replace(/^[/\\]+/, "");

  const candidates = [];

  if (cleanPath.length === 0) {
    candidates.push(join(distRoot, "index.html"));
  } else {
    candidates.push(join(distRoot, cleanPath));
    candidates.push(join(distRoot, `${cleanPath}.html`));
    candidates.push(join(distRoot, cleanPath, "index.html"));
  }

  for (const candidate of candidates) {
    if (candidate.startsWith(distRoot) && (await isReadableFile(candidate))) {
      return { filePath: candidate, status: 200 };
    }
  }

  const notFoundPath = join(distRoot, "404.html");

  if (await isReadableFile(notFoundPath)) {
    return { filePath: notFoundPath, status: 404 };
  }

  return { filePath: null, status: 404 };
};

createServer(async (request, response) => {
  const url = new URL(request.url || "/", `http://${request.headers.host || "localhost"}`);
  console.log(`[request] ${request.method} ${url.pathname}`);

  if (comingSoonEnabled && !isAssetRequest(url.pathname)) {
    response.writeHead(200, {
      "Cache-Control": "no-store",
      "Content-Type": "text/html; charset=utf-8",
      "X-Robots-Tag": "noindex, nofollow",
    });

    if (request.method === "HEAD") {
      response.end();
      return;
    }

    response.end(renderComingSoonPage());
    return;
  }

  const { filePath, status } = await resolvePath(url.pathname);

  if (!filePath) {
    console.error(`[error] No file found for path: ${url.pathname} (distRoot: ${distRoot}, exists: ${existsSync(distRoot)})`);
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end(`404 Not Found\n\ndistRoot: ${distRoot}\ndist exists: ${existsSync(distRoot)}`);
    return;
  }

  const extension = extname(filePath).toLowerCase();
  const contentType = mimeTypes[extension] || "application/octet-stream";
  const isHtml = extension === ".html";

  response.writeHead(status, {
    "Cache-Control": isHtml ? "public, max-age=0, must-revalidate" : "public, max-age=31536000, immutable",
    "Content-Type": contentType,
  });

  const stream = createReadStream(filePath);
  stream.on("error", (err) => {
    console.error(`[error] Failed to read file ${filePath}: ${err.message}`);
    if (!response.headersSent) {
      response.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
    }
    response.end(`500 Internal Server Error\n\n${err.message}`);
  });
  stream.pipe(response);
}).listen(port, "0.0.0.0", () => {
  console.log(`[server] Listening on port ${port}`);
});
