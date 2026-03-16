/**
 * Akkoma API proxy worker
 *
 * Deployed via Terraform on specific routes:
 *   akkoma.littledevil.club/api/*
 *   akkoma.littledevil.club/oauth/*
 *   akkoma.littledevil.club/nodeinfo/*
 *
 * Everything else is served by the Pages project (the frontend).
 * This worker only fires on the routes above, so it unconditionally
 * proxies to the backend — no path checking needed.
 */

export default {
  async fetch(request, env) {
    const backend = env.BACKEND_ORIGIN || "https://ap.littledevil.club";
    const backendHost = new URL(backend).hostname;

    const url = new URL(request.url);
    url.hostname = backendHost;
    url.protocol = "https:";

    const headers = new Headers(request.headers);
    headers.set("Host", backendHost);
    headers.set("X-Forwarded-For", request.headers.get("CF-Connecting-IP") || "");
    headers.set("X-Forwarded-Proto", "https");
    headers.set("X-Real-IP", request.headers.get("CF-Connecting-IP") || "");

    const proxyReq = new Request(url.toString(), {
      method: request.method,
      headers,
      body: request.body,
      redirect: "manual",
    });

    let response = await fetch(proxyReq);
    response = new Response(response.body, response);

    // rewrite redirects so they stay on the proxy domain
    const location = response.headers.get("Location");
    if (location) {
      response.headers.set(
        "Location",
        location.replace(backend, "https://akkoma.littledevil.club")
      );
    }

    return response;
  },
};
