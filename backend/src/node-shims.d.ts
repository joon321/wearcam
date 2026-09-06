declare namespace NodeJS {
  interface ProcessEnv {
    readonly [key: string]: string | undefined;
  }
}

declare module "node:http" {
  export interface IncomingMessage extends AsyncIterable<Uint8Array> {
    readonly method?: string;
    readonly url?: string;
    readonly socket: { readonly remoteAddress?: string };
  }
  export interface ServerResponse {
    writeHead(status: number, headers?: Record<string, string>): void;
    end(body?: string): void;
  }
  export interface Server {
    listen(port: number, host: string, callback: () => void): void;
    close(callback: () => void): void;
  }
  export function createServer(
    listener: (
      request: IncomingMessage,
      response: ServerResponse,
    ) => void | Promise<void>,
  ): Server;
}

declare const Buffer: { byteLength(value: Uint8Array): number };
declare const process: {
  readonly env: NodeJS.ProcessEnv;
  on(signal: "SIGINT" | "SIGTERM", listener: () => void): void;
  exit(code?: number): never;
};
