export default {
  async fetch(request, env) {
    const response = await env.ASSETS.fetch(request);
    if (response.status === 404) {
      const url = new URL(request.url);
      return env.ASSETS.fetch(new Request(`${url.origin}/index.html`, request));
    }
    return response;
  },
};
