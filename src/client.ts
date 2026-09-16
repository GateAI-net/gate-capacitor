/** Shared public contract for the React Native and Capacitor SDKs. */
export interface GateAIConfiguration {
  baseUrl: string;
  ios?: { teamIdentifier: string; bundleIdentifier?: string };
  android?: {
    signingCertSha256: string;
    /** Decimal string to preserve all digits across the native bridge. */
    cloudProjectNumber?: string;
    developmentToken?: string;
    deviceIdentifierEnabled?: boolean;
  };
}

export interface GateAIContext {
  userStatus?: string;
  userTier?: string;
  userIdentifier?: string;
  appFeature?: string;
  quotaAnchorDay?: number;
}

export interface GateAIRequest {
  /** Relative path only, without query strings, fragments, or dot segments. */
  path: string;
  method?: 'GET' | 'POST';
  /** UTF-8 text; use JSON.stringify for JSON. Responses are buffered. */
  body?: string;
  headers?: Record<string, string>;
  context?: GateAIContext;
}

export interface GateAIResponse {
  status: number;
  headers: Record<string, string>;
  body: string;
}

export class GateAIError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly status?: number,
    public readonly headers: Record<string, string> = {},
    public readonly body?: string,
  ) {
    super(message);
    this.name = 'GateAIError';
  }

  header(name: string): string | undefined {
    return Object.entries(this.headers).find(([key]) => key.toLowerCase() === name.toLowerCase())?.[1];
  }
}

/** @internal Framework adapters transport a JSON envelope to the native SDK. */
export type NativeTransport = (payload: string) => Promise<string>;

function invalid(message: string): never {
  throw new GateAIError('configuration', message);
}

export function validateConfiguration(config: GateAIConfiguration): void {
  // Avoid depending on a URL polyfill in React Native. Native code validates again.
  if (!/^https:\/\/[a-zA-Z0-9.-]+(?::\d{1,5})?\/?$/.test(config.baseUrl)) {
    invalid('baseUrl must be an HTTPS origin without credentials, path, query, or fragment.');
  }
  if (!config.ios && !config.android) invalid('Provide ios and/or android configuration.');
  if (config.ios && !/^[A-Za-z0-9]{10}$/.test(config.ios.teamIdentifier)) invalid('Invalid Apple teamIdentifier.');
  if (config.android) {
    const fingerprint = config.android.signingCertSha256.replace(/:/g, '');
    if (!/^[a-fA-F0-9]{64}$/.test(fingerprint)) invalid('signingCertSha256 must contain 32 hexadecimal bytes.');
    if (config.android.cloudProjectNumber !== undefined && !/^[1-9][0-9]{0,17}$/.test(config.android.cloudProjectNumber)) {
      invalid('cloudProjectNumber must be a positive decimal string (up to 18 digits).');
    }
  }
}

export function requestOptions(request: GateAIRequest): GateAIRequest {
  if (!/^[A-Za-z0-9_~-]+(?:\/[A-Za-z0-9_~.-]+)*$/.test(request.path) || request.path.split('/').some(p => p === '.' || p === '..')) {
    invalid('path must be relative, with no query, fragment, percent escapes, or dot segments.');
  }
  const method = request.method ?? 'POST';
  if (method !== 'GET' && method !== 'POST') invalid('Only GET and POST are supported.');
  if (request.body !== undefined && typeof request.body !== 'string') invalid('body must be UTF-8 text.');
  if (method === 'GET' && request.body !== undefined) invalid('GET requests cannot have a body.');
  const headers: Record<string, string> = {};
  for (const [key, value] of Object.entries(request.headers ?? {})) {
    const name = key.toLowerCase();
    if (!/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(key) || typeof value !== 'string' || /[\r\n]/.test(value)) invalid('Invalid request header.');
    if (['authorization', 'dpop', 'host', 'content-length', 'connection'].includes(name)) invalid(`Header ${key} is managed by the SDK.`);
    headers[name] = value;
  }
  const context = request.context ?? {};
  const contextHeaders = { userStatus: 'x-user-status', userTier: 'x-user-tier', userIdentifier: 'x-user-identifier', appFeature: 'x-app-feature' } as const;
  for (const [key, header] of Object.entries(contextHeaders)) {
    const value = context[key as keyof typeof contextHeaders];
    if (value !== undefined) {
      if (typeof value !== 'string' || /[\r\n]/.test(value)) invalid(`Invalid ${key}.`);
      headers[header] ??= value;
    }
  }
  if (context.quotaAnchorDay !== undefined) {
    if (!Number.isInteger(context.quotaAnchorDay) || context.quotaAnchorDay < 1 || context.quotaAnchorDay > 31) invalid('quotaAnchorDay must be an integer from 1 to 31.');
    headers['x-quota-anchor-day'] ??= String(context.quotaAnchorDay);
  }
  return { path: request.path, method, body: request.body, headers };
}

/** @internal Shared implementation; framework entry points supply the transport. */
export class GateAIClientBase {
  private disposed = false;
  private constructor(private readonly transport: NativeTransport, private readonly clientId: string) {}

  static async connect(transport: NativeTransport, configuration: GateAIConfiguration): Promise<GateAIClientBase> {
    validateConfiguration(configuration);
    const result = await this.invoke<{ clientId: string }>(transport, { operation: 'configure', configuration });
    return new GateAIClientBase(transport, result.clientId);
  }

  private static async invoke<T>(transport: NativeTransport, payload: unknown): Promise<T> {
    let raw: string;
    try { raw = await transport(JSON.stringify(payload)); }
    catch (error) {
      if (error instanceof GateAIError) throw error;
      throw new GateAIError('native_bridge', error instanceof Error ? error.message : String(error));
    }
    let envelope;
    try { envelope = JSON.parse(raw); }
    catch { throw new GateAIError('invalid_response', 'Invalid response from native Gate/AI module.'); }
    if (envelope.error) {
      const e = envelope.error;
      throw new GateAIError(e.code, e.message, e.status, e.headers, e.body);
    }
    return envelope.result as T;
  }

  private call<T>(operation: string, options: object = {}): Promise<T> {
    if (this.disposed) return Promise.reject(new GateAIError('disposed', 'This Gate/AI client has been disposed.'));
    return GateAIClientBase.invoke(this.transport, { operation, clientId: this.clientId, ...options });
  }

  async request(options: GateAIRequest): Promise<GateAIResponse> {
    const response = await this.call<GateAIResponse>('request', requestOptions(options));
    if (response.status < 200 || response.status >= 300) {
      throw new GateAIError('http', `HTTP ${response.status}`, response.status, response.headers, response.body);
    }
    return response;
  }

  /** For custom transports; callers handle nonce challenges and HTTP errors themselves. */
  authorizationHeaders(options: Omit<GateAIRequest, 'body'> & { nonce?: string }): Promise<Record<string, string>> {
    return this.call('authorizationHeaders', { ...requestOptions(options), nonce: options.nonce });
  }

  clearCachedState(): Promise<void> { return this.call('clearCachedState'); }

  /** Releases this client; in-flight requests finish and hardware keys remain stored. */
  async dispose(): Promise<void> {
    if (this.disposed) return;
    await this.call('dispose');
    this.disposed = true;
  }
}
