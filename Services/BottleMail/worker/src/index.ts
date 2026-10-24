import { handleRequest } from "./app.js";
import type { Env } from "./env.js";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env);
  },
};
