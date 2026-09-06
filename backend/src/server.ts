import { createApp } from "./app.ts";
import { loadConfig } from "./config.ts";

const config = loadConfig(process.env);
const server = createApp(config);
server.listen(config.port, "0.0.0.0", () => {
  console.log(JSON.stringify({ event: "listening", port: config.port }));
});

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
