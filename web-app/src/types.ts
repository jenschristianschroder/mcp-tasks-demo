export interface TodoTask {
  id: number;
  title: string;
  description: string | null;
  status: TodoStatus;
  dueDate: string | null;
  createdAt: string;
  updatedAt: string;
  ownerOid: string;
}

export type TodoStatus = 'Open' | 'InProgress' | 'Done' | 'Cancelled';

export interface CreateTaskRequest {
  title: string;
  description?: string | null;
  dueDate?: string | null;
}

export interface UpdateTaskRequest {
  title?: string | null;
  description?: string | null;
  status?: TodoStatus | null;
  dueDate?: string | null;
}

export interface ApiLogEntry {
  id: string;
  timestamp: Date;
  method: string;
  url: string;
  requestBody?: unknown;
  responseStatus: number;
  responseBody?: unknown;
  duration: number;
}
