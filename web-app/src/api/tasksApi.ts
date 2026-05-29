import { ApiLogEntry, CreateTaskRequest, TodoTask, UpdateTaskRequest } from '../types';

type LogListener = (entry: ApiLogEntry) => void;

const listeners: LogListener[] = [];
let accessTokenProvider: (() => Promise<string | null>) | null = null;

export function setAccessTokenProvider(provider: () => Promise<string | null>) {
  accessTokenProvider = provider;
}

export function onApiLog(listener: LogListener) {
  listeners.push(listener);
  return () => {
    const idx = listeners.indexOf(listener);
    if (idx >= 0) listeners.splice(idx, 1);
  };
}

function emitLog(entry: ApiLogEntry) {
  listeners.forEach((l) => l(entry));
}

let idCounter = 0;

async function apiCall<T>(method: string, url: string, body?: unknown): Promise<T> {
  const start = performance.now();
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };

  if (accessTokenProvider) {
    const token = await accessTokenProvider();
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }
  }

  const options: RequestInit = { method, headers };
  if (body !== undefined) {
    options.body = JSON.stringify(body);
  }

  const response = await fetch(url, options);
  const duration = Math.round(performance.now() - start);

  let responseBody: unknown = null;
  const contentType = response.headers.get('content-type');
  if (contentType?.includes('application/json')) {
    responseBody = await response.json();
  }

  const entry: ApiLogEntry = {
    id: `log-${++idCounter}`,
    timestamp: new Date(),
    method,
    url,
    requestBody: body,
    responseStatus: response.status,
    responseBody,
    duration,
  };
  emitLog(entry);

  if (!response.ok) {
    throw new Error(`API error: ${response.status} ${response.statusText}`);
  }

  return responseBody as T;
}

export const tasksApi = {
  list(): Promise<TodoTask[]> {
    return apiCall<TodoTask[]>('GET', '/tasks');
  },

  get(id: number): Promise<TodoTask> {
    return apiCall<TodoTask>('GET', `/tasks/${id}`);
  },

  create(req: CreateTaskRequest): Promise<TodoTask> {
    return apiCall<TodoTask>('POST', '/tasks', req);
  },

  update(id: number, req: UpdateTaskRequest): Promise<TodoTask> {
    return apiCall<TodoTask>('PUT', `/tasks/${id}`, req);
  },

  delete(id: number): Promise<void> {
    return apiCall<void>('DELETE', `/tasks/${id}`);
  },
};
